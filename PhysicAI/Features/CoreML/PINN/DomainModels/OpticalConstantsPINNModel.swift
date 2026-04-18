import Foundation
import CoreML

/// Physics-Informed Neural Network model for optical constants (refractive index n, extinction k).
///
/// Embeds Sellmeier dispersion equation for refractive index, Kramers-Kronig relations
/// linking n and k, and the physical constraint that n > 1 for most materials.
///
/// Architecture: 4-layer MLP, Sellmeier + Kramers-Kronig integral transform loss.
///
/// References:
/// - refractiveindex.info database (GitHub, >1,000 materials)
/// - Sellmeier (1871) — Dispersion equation for transparent media
final class OpticalConstantsPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .opticalConstants

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Optical Constants PINN with Sellmeier dispersion + Kramers-Kronig constraints"
    }

    var physicsConstraints: [String] {
        [
            "Sellmeier: n^2 = 1 + Sum(Bi*lambda^2/(lambda^2-Ci))",
            "Kramers-Kronig: n and k are related by integral transform",
            "Refractive index n > 1 for most materials"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_OpticalConstants"

    /// Reference refractive indices for common materials at 589 nm (sodium D-line).
    static let referenceIndices: [(material: String, n_d: Double, abbeNumber: Double)] = [
        ("Fused silica",    1.458, 67.8),
        ("BK7 glass",       1.517, 64.2),
        ("SF11 glass",      1.785, 25.8),
        ("Diamond",         2.417, 55.3),
        ("Sapphire",        1.770, 72.2),
        ("Water",           1.333, 55.7),
        ("NaCl",            1.544, 42.9),
        ("CaF2",            1.434, 95.1),
        ("MgF2",            1.380, 106.2),
        ("ZnSe",            2.403, 56.0),
        ("Silicon",         3.475,  0.0),
        ("Germanium",       4.003,  0.0),
        ("TiO2 (rutile)",   2.614, 12.4),
        ("LiNbO3",          2.286, 29.5),
    ]

    // MARK: - Model Loading

    func loadModel() async throws {
        status = .loading

        if let url = PINNModelRegistry.resolveModelURL(named: Self.modelName) {
            try loadFromURL(url)
            return
        }

        status = .notTrained
    }

    private func loadFromURL(_ url: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: config)
        loadConformalResiduals()
        normParams = PINNNormalizationParams.load(modelName: Self.modelName)
        status = .ready
    }

    private func loadConformalResiduals() {
        let url = PINNModelRegistry.modelDirectory
            .appendingPathComponent("\(Self.modelName)_calibration.json")
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let residuals = try? JSONDecoder().decode([Double].self, from: data) else { return }
        conformalResiduals = residuals.sorted()
    }

    // MARK: - Prediction

    func predict(
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata
    ) -> PINNPredictionResult? {
        guard status.isReady, let model else { return nil }
        guard wavelengths.count == intensities.count, wavelengths.count >= 5 else { return nil }

        // wavelengths = nm, intensities = refractive index n(lambda)
        let featureDict = buildFeatures(wavelengths: wavelengths, refractiveIndex: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let bandgap = prediction.featureValue(for: "bandgap_eV")?.doubleValue else {
                return nil
            }

            var denormalizedValue = bandgap
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                refractiveIndex: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Bandgap (eV)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzeDispersion(wavelengths: wavelengths, refractiveIndex: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .opticalConstants,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        wavelengths: [Double],
        refractiveIndex: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxN = refractiveIndex.max() ?? 1
        let minN = refractiveIndex.min() ?? 1
        let meanN = refractiveIndex.reduce(0, +) / Double(max(refractiveIndex.count, 1))
        features["max_n"] = MLFeatureValue(double: maxN)
        features["min_n"] = MLFeatureValue(double: minN)
        features["mean_n"] = MLFeatureValue(double: meanN)
        features["dispersion_range"] = MLFeatureValue(double: maxN - minN)

        // n at sodium D-line (589 nm) interpolation
        let nD = interpolateAt(wavelengths: wavelengths, values: refractiveIndex, target: 589.0)
        features["n_d_line"] = MLFeatureValue(double: nD ?? meanN)

        // Abbe number estimate: V = (n_D - 1) / (n_F - n_C)
        // F-line = 486 nm, C-line = 656 nm
        let nF = interpolateAt(wavelengths: wavelengths, values: refractiveIndex, target: 486.0)
        let nC = interpolateAt(wavelengths: wavelengths, values: refractiveIndex, target: 656.0)
        if let nd = nD, let nf = nF, let nc = nC, (nf - nc) > 1e-6 {
            features["abbe_number"] = MLFeatureValue(double: (nd - 1.0) / (nf - nc))
        } else {
            features["abbe_number"] = MLFeatureValue(double: 0)
        }

        // Sellmeier-like dispersion curvature
        // dn/dlambda slope (negative for normal dispersion)
        if wavelengths.count >= 2 {
            let n = Double(wavelengths.count)
            let sumXY = zip(wavelengths, refractiveIndex).map { $0 * $1 }.reduce(0, +)
            let sumX = wavelengths.reduce(0, +)
            let sumY = refractiveIndex.reduce(0, +)
            let sumX2 = wavelengths.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            let slope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0
            features["dn_dlambda"] = MLFeatureValue(double: slope)
        }

        // Transparency window estimate
        let transparentCount = refractiveIndex.filter { $0 > 1.0 && $0 < 5.0 }.count
        features["transparency_fraction"] = MLFeatureValue(double: Double(transparentCount) / Double(max(refractiveIndex.count, 1)))

        return features
    }

    private func interpolateAt(wavelengths: [Double], values: [Double], target: Double) -> Double? {
        guard wavelengths.count == values.count, wavelengths.count >= 2 else { return nil }
        // Find bracketing points
        for i in 0..<wavelengths.count - 1 {
            let w0 = wavelengths[i], w1 = wavelengths[i + 1]
            if (w0 <= target && w1 >= target) || (w0 >= target && w1 <= target) {
                let t = (target - w0) / (w1 - w0)
                return values[i] + t * (values[i + 1] - values[i])
            }
        }
        return nil
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        refractiveIndex: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Refractive index should be > 0 (and typically > 1 for solid materials)
        let invalidN = refractiveIndex.filter { $0 <= 0 }.count
        score -= Double(invalidN) / Double(refractiveIndex.count) * 0.4

        // 2. Normal dispersion: n should generally decrease with increasing wavelength
        // (in the transparent region, away from absorption bands)
        var anomalousCount = 0
        for i in 1..<refractiveIndex.count {
            if wavelengths[i] > wavelengths[i - 1] && refractiveIndex[i] > refractiveIndex[i - 1] + 0.01 {
                anomalousCount += 1
            }
        }
        // Some anomalous dispersion is OK near absorption bands, but excessive is suspicious
        let anomalousFraction = Double(anomalousCount) / Double(max(refractiveIndex.count - 1, 1))
        if anomalousFraction > 0.5 {
            score -= 0.15
        }

        // 3. Refractive index should be in a physically reasonable range (1.0 to ~6.0 for most materials)
        let outOfRange = refractiveIndex.filter { $0 > 10.0 }.count
        score -= Double(outOfRange) / Double(refractiveIndex.count) * 0.2

        // 4. Smoothness: n(lambda) should be smooth (Sellmeier is analytic)
        var jumpCount = 0
        for i in 1..<refractiveIndex.count {
            if abs(refractiveIndex[i] - refractiveIndex[i - 1]) > 0.5 {
                jumpCount += 1
            }
        }
        score -= min(Double(jumpCount) * 0.05, 0.2)

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Dispersion Analysis

    private func analyzeDispersion(
        wavelengths: [Double],
        refractiveIndex: [Double]
    ) -> [String: [Double]] {
        var results: [String: [Double]] = [:]

        let nD = interpolateAt(wavelengths: wavelengths, values: refractiveIndex, target: 589.0)
        if let nd = nD {
            results["n_at_589nm"] = [nd, 589.0]
        }

        // Find closest reference material
        if let nd = nD {
            var bestMatch = ""
            var bestDiff = Double.infinity
            for ref in Self.referenceIndices {
                let diff = abs(ref.n_d - nd)
                if diff < bestDiff {
                    bestDiff = diff
                    bestMatch = ref.material
                }
            }
            if !bestMatch.isEmpty {
                results["closest_material"] = [bestDiff, nd]
            }
        }

        // Dispersion characteristics
        let maxN = refractiveIndex.max() ?? 1
        let minN = refractiveIndex.min() ?? 1
        results["dispersion"] = [maxN - minN, (maxN + minN) / 2.0]

        return results
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
