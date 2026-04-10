import Foundation
import CoreML

/// Physics-Informed Neural Network model for Raman spectroscopy.
///
/// Uses dual-network architecture (Puleio et al. 2025): a background network for
/// fluorescence/baseline estimation and a concentration network for agent decomposition.
/// Physics constraints include spectral reconstruction fidelity, background smoothness,
/// concentration non-negativity, and Raman shift selection rules.
///
/// References:
/// - Puleio et al. 2025 (Scientific Reports) — multi-agent decomposition, R²>75-99%
/// - Vulchi et al. 2025 (SPIE) — etaloning correction, outperforms traditional DL
final class RamanPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .raman

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Raman PINN with dual-network spectral decomposition + fluorescence background correction"
    }

    var physicsConstraints: [String] {
        [
            "Spectral reconstruction: I(λ) = Σ cⱼ·I₀ⱼ(λ) + I_b(λ)",
            "Background smoothness: ‖∂I_b/∂λ‖² penalty",
            "Concentration non-negativity: cⱼ ≥ 0",
            "Raman shift selection rules: vibrational modes → allowed transitions",
            "Etaloning correction: sinusoidal interference pattern removal"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    static let modelName = "PINN_Raman"

    // MARK: - Model Loading

    func loadModel() async throws {
        status = .loading
        let fm = FileManager.default

        let appSupportURL = PINNModelRegistry.modelDirectory
            .appendingPathComponent("\(Self.modelName).mlmodelc")
        if fm.fileExists(atPath: appSupportURL.path) {
            try loadFromURL(appSupportURL)
            return
        }

        if let iCloudDir = PINNModelRegistry.iCloudModelDirectory {
            let iCloudURL = iCloudDir.appendingPathComponent("\(Self.modelName).mlmodelc")
            if fm.fileExists(atPath: iCloudURL.path) {
                try loadFromURL(iCloudURL)
                return
            }
            try? fm.startDownloadingUbiquitousItem(at: iCloudURL)
        }

        if let bundleURL = Bundle.main.url(forResource: Self.modelName, withExtension: "mlmodelc") {
            try loadFromURL(bundleURL)
            return
        }

        status = .notTrained
    }

    private func loadFromURL(_ url: URL) throws {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        model = try MLModel(contentsOf: url, configuration: config)
        loadConformalResiduals()
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
        guard wavelengths.count == intensities.count, wavelengths.count >= 10 else { return nil }

        let featureDict = buildFeatures(ramanShifts: wavelengths, intensities: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let primaryValue = prediction.featureValue(for: "concentration")?.doubleValue else {
                return nil
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                ramanShifts: wavelengths,
                intensities: intensities
            )

            return PINNPredictionResult(
                primaryValue: primaryValue,
                primaryLabel: "Concentration",
                confidenceLow: max(primaryValue - q90, 0),
                confidenceHigh: primaryValue + q90,
                decomposition: estimateBaselineDecomposition(ramanShifts: wavelengths, intensities: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .raman
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(ramanShifts: [Double], intensities: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        features["mean_intensity"] = MLFeatureValue(double: intensities.reduce(0, +) / Double(intensities.count))
        features["max_intensity"] = MLFeatureValue(double: intensities.max() ?? 0)
        features["spectral_range"] = MLFeatureValue(double: (ramanShifts.max() ?? 0) - (ramanShifts.min() ?? 0))

        // Background fluorescence estimate (polynomial baseline)
        let backgroundLevel = estimateBackgroundLevel(intensities: intensities)
        features["background_level"] = MLFeatureValue(double: backgroundLevel)
        features["signal_to_background"] = MLFeatureValue(double:
            backgroundLevel > 0 ? (intensities.max() ?? 0) / backgroundLevel : 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(ramanShifts: [Double], intensities: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity: Raman intensities should be ≥ 0
        let negCount = intensities.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(intensities.count) * 0.3

        // 2. Background smoothness assessment
        let backgroundLevel = estimateBackgroundLevel(intensities: intensities)
        if backgroundLevel > 0 {
            let snr = (intensities.max() ?? 0) / backgroundLevel
            if snr < 2.0 {
                score -= 0.2 // Poor signal-to-noise suggests fluorescence dominance
            }
        }

        // 3. Spectral continuity
        if intensities.count >= 3 {
            var jumpCount = 0
            let median = intensities.sorted()[intensities.count / 2]
            for i in 1..<intensities.count {
                let diff = abs(intensities[i] - intensities[i - 1])
                if diff > median * 3 { jumpCount += 1 }
            }
            score -= min(Double(jumpCount) / Double(intensities.count) * 2.0, 0.3)
        }

        return max(min(score, 1.0), 0.0)
    }

    /// Estimate fluorescence background level (simple median-based).
    private func estimateBackgroundLevel(intensities: [Double]) -> Double {
        guard !intensities.isEmpty else { return 0 }
        let sorted = intensities.sorted()
        return sorted[sorted.count / 4] // Q1 as background estimate
    }

    /// Baseline/Raman decomposition for result reporting.
    private func estimateBaselineDecomposition(
        ramanShifts: [Double],
        intensities: [Double]
    ) -> [String: [Double]] {
        let background = estimateBackgroundLevel(intensities: intensities)
        let corrected = intensities.map { max($0 - background, 0) }
        return [
            "Background": [background],
            "Corrected Signal": [corrected.max() ?? 0]
        ]
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
