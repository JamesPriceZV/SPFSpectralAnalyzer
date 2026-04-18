import Foundation
import CoreML

/// Physics-Informed Neural Network model for Small-Angle X-ray Scattering (SAXS/SANS).
///
/// Embeds Guinier approximation for radius of gyration at low q, Porod law for
/// interface scattering at high q, and non-negativity of scattering intensity.
///
/// Architecture: 4-layer MLP, Guinier + Porod physics loss terms.
///
/// References:
/// - SASBDB (sasbdb.org) — open small-angle scattering biological data bank
/// - Guinier & Fournet, "Small-Angle Scattering of X-rays"
final class SAXSPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .saxs

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "SAXS PINN with Guinier radius of gyration + Porod law interface scattering constraints"
    }

    var physicsConstraints: [String] {
        [
            "Guinier: I(q) = I0*exp(-q^2*Rg^2/3) at low q",
            "Porod: I(q) ~ q^-4 at high q for sharp interfaces",
            "I(q) must be non-negative"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_SAXS"

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

        // wavelengths = q values (inverse angstroms), intensities = I(q)
        let featureDict = buildFeatures(qValues: wavelengths, iq: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let rgValue = prediction.featureValue(for: "rg_nm")?.doubleValue else {
                return nil
            }

            var denormalizedValue = rgValue
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                qValues: wavelengths,
                iq: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Rg (nm)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: extractScatteringRegions(qValues: wavelengths, iq: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .saxs,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        qValues: [Double],
        iq: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxI = iq.max() ?? 1
        features["i_zero_est"] = MLFeatureValue(double: maxI)
        features["total_scattering"] = MLFeatureValue(double: iq.reduce(0, +))

        // Guinier region estimate: fit ln(I) vs q^2 at low q (q*Rg < 1.3)
        let lowQPairs = zip(qValues, iq).filter { $0.0 < 0.05 && $0.1 > 0 }
        if lowQPairs.count >= 3 {
            let x = lowQPairs.map { $0.0 * $0.0 }
            let y = lowQPairs.map { log($0.1) }
            let slope = linearSlope(x: x, y: y)
            let rgEstimate = slope < 0 ? sqrt(-3.0 * slope) : 0
            features["guinier_rg_est"] = MLFeatureValue(double: rgEstimate)
            features["guinier_slope"] = MLFeatureValue(double: slope)
        } else {
            features["guinier_rg_est"] = MLFeatureValue(double: 0)
            features["guinier_slope"] = MLFeatureValue(double: 0)
        }

        // Porod region: fit log(I) vs log(q) at high q
        let highQPairs = zip(qValues, iq).filter { $0.0 > 0.2 && $0.1 > 0 }
        if highQPairs.count >= 3 {
            let x = highQPairs.map { log($0.0) }
            let y = highQPairs.map { log($0.1) }
            let porodSlope = linearSlope(x: x, y: y)
            features["porod_exponent"] = MLFeatureValue(double: porodSlope)
        } else {
            features["porod_exponent"] = MLFeatureValue(double: 0)
        }

        // Mid-q features
        let midQIntegral = zip(qValues, iq)
            .filter { $0.0 >= 0.01 && $0.0 <= 0.1 }
            .map(\.1)
            .reduce(0, +)
        features["mid_q_integral"] = MLFeatureValue(double: midQIntegral)

        // Dynamic range
        let minPositiveI = iq.filter { $0 > 0 }.min() ?? 1
        features["dynamic_range_log"] = MLFeatureValue(double: maxI > 0 ? log10(maxI / minPositiveI) : 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        qValues: [Double],
        iq: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity: I(q) must be >= 0
        let negCount = iq.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(iq.count) * 0.3

        // 2. Guinier region should show decreasing I with increasing q
        let lowQPairs = zip(qValues, iq).filter { $0.0 < 0.05 && $0.1 > 0 }.map(\.1)
        if lowQPairs.count >= 3 {
            var violations = 0
            for i in 1..<lowQPairs.count {
                if lowQPairs[i] > lowQPairs[i - 1] * 1.2 { violations += 1 }
            }
            score -= Double(violations) / Double(max(lowQPairs.count - 1, 1)) * 0.2
        }

        // 3. Porod exponent should be approximately -4 for sharp interfaces
        let highQPairs = zip(qValues, iq).filter { $0.0 > 0.2 && $0.1 > 0 }
        if highQPairs.count >= 3 {
            let x = highQPairs.map { log($0.0) }
            let y = highQPairs.map { log($0.1) }
            let slope = linearSlope(x: x, y: y)
            // Valid Porod exponents are typically between -1 and -4
            if slope > 0 || slope < -6 {
                score -= 0.2
            }
        }

        // 4. Overall monotonic decrease at larger q
        let sortedByQ = zip(qValues, iq).sorted { $0.0 < $1.0 }
        if sortedByQ.count >= 10 {
            let lastQuarter = Array(sortedByQ.suffix(sortedByQ.count / 4))
            let firstQuarter = Array(sortedByQ.prefix(sortedByQ.count / 4))
            let lastMean = lastQuarter.map(\.1).reduce(0, +) / Double(lastQuarter.count)
            let firstMean = firstQuarter.map(\.1).reduce(0, +) / Double(firstQuarter.count)
            if lastMean > firstMean && firstMean > 0 {
                score -= 0.15
            }
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Scattering Region Extraction

    private func extractScatteringRegions(
        qValues: [Double],
        iq: [Double]
    ) -> [String: [Double]] {
        var regions: [String: [Double]] = [:]

        let guinierI = zip(qValues, iq).filter { $0.0 < 0.02 }.map(\.1).reduce(0, +)
        regions["Guinier Region"] = [guinierI]

        let midI = zip(qValues, iq).filter { $0.0 >= 0.02 && $0.0 <= 0.1 }.map(\.1).reduce(0, +)
        regions["Mid-q Region"] = [midI]

        let porodI = zip(qValues, iq).filter { $0.0 > 0.1 }.map(\.1).reduce(0, +)
        regions["Porod Region"] = [porodI]

        return regions
    }

    // MARK: - Helpers

    private func linearSlope(x: [Double], y: [Double]) -> Double {
        let n = Double(x.count)
        guard n >= 2 else { return 0 }
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        let denom = n * sumX2 - sumX * sumX
        guard abs(denom) > 1e-15 else { return 0 }
        return (n * sumXY - sumX * sumY) / denom
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
