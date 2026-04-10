import Foundation
import CoreML

/// Physics-Informed Neural Network model for FTIR/FT-NIR spectroscopy.
///
/// Embeds Beer-Lambert law (wavenumber domain), functional group frequency constraints,
/// spectral decomposition, and mass conservation as physics constraints.
///
/// Architecture: 4-layer MLP (512-256-128-64), Tanh activation, ReLoBRaLo loss balancing.
///
/// References:
/// - Puleio et al. 2025 (Scientific Reports) — unsupervised PINN spectral extraction, R²>75-99%
/// - Vulchi et al. 2025 (SPIE) — etaloning correction for spectroscopy
final class FTIRPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .ftir

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "FTIR PINN with Beer-Lambert + functional group frequency constraints"
    }

    var physicsConstraints: [String] {
        [
            "Beer-Lambert: A(ν) = Σ εᵢ(ν)·cᵢ·l (wavenumber domain)",
            "Spectral decomposition: spectrum = Σ pure component spectra",
            "Peak position: known functional group frequencies (C=O ~1700cm⁻¹, O-H ~3400cm⁻¹, etc.)",
            "Mass conservation: Σ concentrations ≤ total sample mass"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []

    static let modelName = "PINN_FTIR"

    /// Known functional group frequencies (cm⁻¹) for physics constraint validation.
    static let functionalGroupFrequencies: [(name: String, center: Double, tolerance: Double)] = [
        ("O-H stretch",     3400, 200),
        ("N-H stretch",     3300, 150),
        ("C-H stretch",     2950, 150),
        ("C≡N stretch",     2200, 50),
        ("C=O stretch",     1700, 80),
        ("C=C stretch",     1650, 80),
        ("C-O stretch",     1100, 100),
        ("C-F stretch",     1150, 100),
        ("S=O stretch",     1050, 80),
    ]

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

        // FTIR typically uses wavenumber (cm⁻¹) on x-axis
        // Build a generic feature vector from the spectral data
        let featureDict = buildFeatures(wavenumbers: wavelengths, absorbances: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let primaryValue = prediction.featureValue(for: "concentration")?.doubleValue else {
                return nil
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavenumbers: wavelengths,
                absorbances: intensities
            )

            return PINNPredictionResult(
                primaryValue: primaryValue,
                primaryLabel: "Concentration",
                confidenceLow: max(primaryValue - q90, 0),
                confidenceHigh: primaryValue + q90,
                decomposition: identifyFunctionalGroups(wavenumbers: wavelengths, absorbances: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .ftir,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(wavenumbers: [Double], absorbances: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Statistical features
        features["mean_absorbance"] = MLFeatureValue(double: absorbances.reduce(0, +) / Double(absorbances.count))
        features["max_absorbance"] = MLFeatureValue(double: absorbances.max() ?? 0)
        features["total_area"] = MLFeatureValue(double: absorbances.reduce(0, +))

        // Functional group region intensities
        for group in Self.functionalGroupFrequencies {
            let regionIntensity = absorbances.enumerated()
                .filter { abs(wavenumbers[$0.offset] - group.center) <= group.tolerance }
                .map(\.element)
                .max() ?? 0
            features["peak_\(group.name.replacingOccurrences(of: " ", with: "_"))"] = MLFeatureValue(double: regionIntensity)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(wavenumbers: [Double], absorbances: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity constraint (Beer-Lambert requires A ≥ 0)
        let negCount = absorbances.filter { $0 < -0.01 }.count
        score -= Double(negCount) / Double(absorbances.count) * 0.3

        // 2. Spectral smoothness
        if absorbances.count >= 3 {
            var secondDerivSum = 0.0
            for i in 1..<absorbances.count - 1 {
                let d2 = absorbances[i + 1] - 2 * absorbances[i] + absorbances[i - 1]
                secondDerivSum += d2 * d2
            }
            let avgD2 = secondDerivSum / Double(absorbances.count - 2)
            score -= min(avgD2 * 5.0, 0.3)
        }

        // 3. Baseline behavior: absorbance should approach baseline at extremes
        let baselineDeviation = abs(absorbances.first ?? 0) + abs(absorbances.last ?? 0)
        score -= min(baselineDeviation * 0.1, 0.2)

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Functional Group Identification

    private func identifyFunctionalGroups(
        wavenumbers: [Double],
        absorbances: [Double]
    ) -> [String: [Double]] {
        var groups: [String: [Double]] = [:]

        for group in Self.functionalGroupFrequencies {
            let regionIntensities = absorbances.enumerated()
                .filter { abs(wavenumbers[$0.offset] - group.center) <= group.tolerance }
                .map(\.element)

            if let maxIntensity = regionIntensities.max(), maxIntensity > 0.05 {
                groups[group.name] = [maxIntensity, group.center]
            }
        }

        return groups
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
