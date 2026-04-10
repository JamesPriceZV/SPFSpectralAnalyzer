import Foundation
import CoreML

/// Physics-Informed Neural Network model for NIR (Near-Infrared) spectroscopy.
///
/// Embeds modified Beer-Lambert for diffuse reflectance, Kubelka-Munk corrections,
/// and overtone frequency relationships as physics constraints.
///
/// Architecture: Same as FTIR PINN (shared Beer-Lambert physics) with NIR-specific wavenumber range.
///
/// References:
/// - Shared physics with FTIR; Kubelka-Munk corrections for diffuse reflectance
/// - Shootout datasets (IDRC benchmark) for validation
final class NIRPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .nir

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "NIR PINN with modified Beer-Lambert + Kubelka-Munk + overtone constraints"
    }

    var physicsConstraints: [String] {
        [
            "Modified Beer-Lambert: A = log(1/R) for diffuse reflectance",
            "Kubelka-Munk: f(R) = (1-R)²/2R relates reflectance to absorption/scattering",
            "Overtone relationships: ν_overtone ≈ 2·ν_fundamental",
            "Combination bands: ν_combo = ν₁ + ν₂",
            "Reflectance non-negativity: 0 ≤ R ≤ 1"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_NIR"

    /// Known NIR absorption band positions (nm) for physics constraint validation.
    /// These are overtone and combination bands of fundamental mid-IR vibrations.
    static let nirBandPositions: [(name: String, center: Double, tolerance: Double)] = [
        ("O-H 1st overtone",     1440, 40),
        ("O-H combination",      1940, 60),
        ("C-H 1st overtone",     1725, 50),
        ("C-H 2nd overtone",     1195, 40),
        ("C-H combination",      2310, 60),
        ("N-H 1st overtone",     1510, 40),
        ("N-H combination",      2050, 60),
        ("C=O combination",      2170, 50),
        ("S-H 1st overtone",     1740, 40),
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
        guard wavelengths.count == intensities.count, wavelengths.count >= 10 else { return nil }

        // NIR uses wavelength (nm) on x-axis, reflectance/absorbance on y-axis
        let featureDict = buildFeatures(wavelengths: wavelengths, values: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let primaryValue = prediction.featureValue(for: "concentration")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = primaryValue
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                values: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Concentration",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyNIRBands(wavelengths: wavelengths, values: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .nir,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(wavelengths: [Double], values: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Statistical features
        let mean = values.reduce(0, +) / Double(values.count)
        features["mean_value"] = MLFeatureValue(double: mean)
        features["max_value"] = MLFeatureValue(double: values.max() ?? 0)
        features["total_area"] = MLFeatureValue(double: values.reduce(0, +))

        // NIR band region intensities
        for band in Self.nirBandPositions {
            let regionIntensity = values.enumerated()
                .filter { abs(wavelengths[$0.offset] - band.center) <= band.tolerance }
                .map(\.element)
                .max() ?? 0
            features["band_\(band.name.replacingOccurrences(of: " ", with: "_"))"] = MLFeatureValue(double: regionIntensity)
        }

        // First derivative features (baseline-insensitive)
        if values.count >= 3 {
            var firstDerivMax = 0.0
            for i in 1..<values.count - 1 {
                let d1 = (values[i + 1] - values[i - 1]) / 2.0
                firstDerivMax = max(firstDerivMax, abs(d1))
            }
            features["first_deriv_max"] = MLFeatureValue(double: firstDerivMax)
        }

        // Kubelka-Munk transform: f(R) = (1-R)²/(2R) for diffuse reflectance data
        let kmValues = values.map { r -> Double in
            let clampedR = max(r, 0.001) // Avoid division by zero
            return (1 - clampedR) * (1 - clampedR) / (2.0 * clampedR)
        }
        features["km_mean"] = MLFeatureValue(double: kmValues.reduce(0, +) / Double(kmValues.count))
        features["km_max"] = MLFeatureValue(double: kmValues.max() ?? 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(wavelengths: [Double], values: [Double]) -> Double {
        var score = 1.0

        // 1. Reflectance range constraint: values should be in [0, 1] for reflectance
        // or non-negative for absorbance
        let outOfRange = values.filter { $0 < -0.01 }.count
        score -= Double(outOfRange) / Double(values.count) * 0.3

        // 2. Spectral smoothness (second derivative penalty)
        if values.count >= 3 {
            var secondDerivSum = 0.0
            for i in 1..<values.count - 1 {
                let d2 = values[i + 1] - 2 * values[i] + values[i - 1]
                secondDerivSum += d2 * d2
            }
            let avgD2 = secondDerivSum / Double(values.count - 2)
            score -= min(avgD2 * 5.0, 0.3)
        }

        // 3. Overtone ratio validation: check that known overtone regions
        // have plausible intensity relationships
        let ohFirstOvertone = peakInRegion(wavelengths: wavelengths, values: values, center: 1440, tolerance: 40)
        let ohCombination = peakInRegion(wavelengths: wavelengths, values: values, center: 1940, tolerance: 60)
        if ohFirstOvertone > 0.05 && ohCombination > 0.05 {
            // Combination band is typically stronger than 1st overtone
            if ohFirstOvertone > ohCombination * 3.0 {
                score -= 0.1 // Unusual overtone ratio
            }
        }

        // 4. Baseline behavior
        let baselineDeviation = abs(values.first ?? 0) + abs(values.last ?? 0)
        score -= min(baselineDeviation * 0.05, 0.15)

        return max(min(score, 1.0), 0.0)
    }

    private func peakInRegion(wavelengths: [Double], values: [Double], center: Double, tolerance: Double) -> Double {
        values.enumerated()
            .filter { abs(wavelengths[$0.offset] - center) <= tolerance }
            .map(\.element)
            .max() ?? 0
    }

    // MARK: - NIR Band Identification

    private func identifyNIRBands(
        wavelengths: [Double],
        values: [Double]
    ) -> [String: [Double]] {
        var bands: [String: [Double]] = [:]

        for band in Self.nirBandPositions {
            let regionIntensities = values.enumerated()
                .filter { abs(wavelengths[$0.offset] - band.center) <= band.tolerance }
                .map(\.element)

            if let maxIntensity = regionIntensities.max(), maxIntensity > 0.02 {
                bands[band.name] = [maxIntensity, band.center]
            }
        }

        return bands
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
