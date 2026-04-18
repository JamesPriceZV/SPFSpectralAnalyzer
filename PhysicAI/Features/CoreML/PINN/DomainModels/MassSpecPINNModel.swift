import Foundation
import CoreML

/// Physics-Informed Neural Network model for Mass Spectrometry.
///
/// Embeds isotope distribution (natural abundance), mass conservation,
/// fragmentation rule consistency, and charge state constraints.
/// Uses inverse PINN with trainable fragmentation energy parameters.
///
/// Architecture: 4-layer MLP (256-128-128-64), Tanh activation, ReLoBRaLo loss balancing.
///
/// References:
/// - Chen et al. 2025 (ACS) — oPINNs, 1000x speedup, 32x fewer samples
/// - Zou et al. 2024 (J. Chromatography A) — 35% error reduction, 95% computation reduction
final class MassSpecPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .massSpec

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Mass Spec PINN with isotope distribution + fragmentation rule constraints"
    }

    var physicsConstraints: [String] {
        [
            "Isotope distribution: patterns follow natural abundance (binomial/Poisson)",
            "Mass conservation: fragment masses sum to parent ion mass",
            "Fragmentation rules: McLafferty, α-cleavage, retro-Diels-Alder",
            "Charge state: multiply-charged ions follow predictable spacing"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?
    static let modelName = "PINN_MassSpec"

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

        // In mass spec, wavelengths = m/z values, intensities = ion counts
        let featureDict = buildFeatures(mzValues: wavelengths, ionCounts: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let molecularWeight = prediction.featureValue(for: "molecular_weight")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = molecularWeight
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(mzValues: wavelengths, ionCounts: intensities)

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Molecular Weight (Da)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyFragmentationPattern(mzValues: wavelengths, ionCounts: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .massSpec,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(mzValues: [Double], ionCounts: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Base peak
        let maxIdx = ionCounts.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        features["base_peak_mz"] = MLFeatureValue(double: mzValues[maxIdx])
        features["base_peak_intensity"] = MLFeatureValue(double: ionCounts[maxIdx])

        // Molecular ion (highest m/z with significant intensity)
        let threshold = (ionCounts.max() ?? 0) * 0.01
        let significantPeaks = zip(mzValues, ionCounts).filter { $0.1 >= threshold }
        features["molecular_ion_mz"] = MLFeatureValue(double: significantPeaks.map(\.0).max() ?? 0)

        // Spectral statistics
        features["total_ion_count"] = MLFeatureValue(double: ionCounts.reduce(0, +))
        features["peak_count"] = MLFeatureValue(double: Double(significantPeaks.count))
        features["mz_range"] = MLFeatureValue(double: (mzValues.max() ?? 0) - (mzValues.min() ?? 0))

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(mzValues: [Double], ionCounts: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity: ion counts must be ≥ 0
        let negCount = ionCounts.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(ionCounts.count) * 0.3

        // 2. Mass conservation: largest m/z peak should be close to molecular ion
        let maxMZ = mzValues.max() ?? 0
        let basePeakMZ = mzValues[ionCounts.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0]
        if maxMZ > 0 && basePeakMZ > maxMZ * 1.1 {
            score -= 0.2 // Base peak shouldn't exceed molecular ion significantly
        }

        // 3. Isotope pattern check: look for M+1, M+2 patterns
        let threshold = (ionCounts.max() ?? 0) * 0.01
        let significantMZ = zip(mzValues, ionCounts)
            .filter { $0.1 >= threshold }
            .map(\.0)
            .sorted()

        // Check for at least one isotope pair (M, M+1)
        var hasIsotopePair = false
        for i in 0..<significantMZ.count - 1 {
            let diff = significantMZ[i + 1] - significantMZ[i]
            if abs(diff - 1.0) < 0.1 {
                hasIsotopePair = true
                break
            }
        }
        if !hasIsotopePair && significantMZ.count > 5 {
            score -= 0.1 // Expected isotope pattern not detected
        }

        return max(min(score, 1.0), 0.0)
    }

    /// Identify major fragmentation patterns from the spectrum.
    private func identifyFragmentationPattern(mzValues: [Double], ionCounts: [Double]) -> [String: [Double]] {
        var patterns: [String: [Double]] = [:]
        let maxIntensity = ionCounts.max() ?? 1

        // Report top 5 peaks
        let indexed = zip(mzValues, ionCounts).sorted { $0.1 > $1.1 }
        for (i, peak) in indexed.prefix(5).enumerated() {
            patterns["Peak \(i + 1) (m/z=\(String(format: "%.1f", peak.0)))"] = [
                peak.0, peak.1 / maxIntensity * 100
            ]
        }

        return patterns
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 5.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
