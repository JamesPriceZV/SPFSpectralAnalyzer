import Foundation
import CoreML

/// Physics-Informed Neural Network model for USGS mineral reflectance spectroscopy.
///
/// Embeds Kubelka-Munk diffuse reflectance theory F(R) = (1-R)^2/2R,
/// continuum removal for absorption feature extraction, and reflectance bounded 0-1.
///
/// Architecture: 4-layer MLP, Kubelka-Munk + continuum removal loss.
///
/// References:
/// - USGS Spectral Library Version 7 (splib07, >2,800 spectra)
/// - Kokaly et al. (2017) — USGS Spectral Library Version 7
final class USGSReflectancePINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .usgsReflectance

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "USGS Reflectance PINN with Kubelka-Munk + continuum removal constraints"
    }

    var physicsConstraints: [String] {
        [
            "Kubelka-Munk: F(R) = (1-R)^2/2R",
            "Continuum removal for absorption feature extraction",
            "Reflectance bounded 0-1"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_USGSReflectance"

    /// Diagnostic absorption features for common mineral classes (wavelength nm, width nm).
    static let diagnosticFeatures: [(mineral: String, centerNM: Double, widthNM: Double)] = [
        ("Iron oxide (hematite)",     870.0,  80.0),
        ("Iron oxide (goethite)",     900.0, 100.0),
        ("Iron Fe2+",                1000.0, 200.0),
        ("Al-OH (kaolinite)",        2200.0,  30.0),
        ("Al-OH (montmorillonite)",  2200.0,  30.0),
        ("Mg-OH (serpentine)",       2320.0,  30.0),
        ("Carbonate (calcite)",      2340.0,  30.0),
        ("Water/OH",                 1400.0,  40.0),
        ("Water",                    1900.0,  60.0),
        ("Vegetation red edge",       700.0,  30.0),
        ("Chlorophyll",               680.0,  20.0),
        ("Dry vegetation cellulose", 2100.0,  40.0),
        ("Gypsum",                   1750.0,  30.0),
        ("Alunite",                  2170.0,  25.0),
        ("Epidote",                  2250.0,  30.0),
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

        // wavelengths = nm, intensities = reflectance (0-1)
        let featureDict = buildFeatures(wavelengths: wavelengths, reflectance: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let mineralClass = prediction.featureValue(for: "mineral_class")?.doubleValue else {
                return nil
            }

            var denormalizedValue = mineralClass
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                reflectance: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Mineral Class",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyMinerals(wavelengths: wavelengths, reflectance: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .usgsReflectance,
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
        reflectance: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxR = reflectance.max() ?? 1
        let minR = reflectance.min() ?? 0
        let meanR = reflectance.reduce(0, +) / Double(max(reflectance.count, 1))
        features["max_reflectance"] = MLFeatureValue(double: maxR)
        features["min_reflectance"] = MLFeatureValue(double: minR)
        features["mean_reflectance"] = MLFeatureValue(double: meanR)
        features["reflectance_range"] = MLFeatureValue(double: maxR - minR)

        // Kubelka-Munk transform of mean reflectance
        if meanR > 0 && meanR < 1 {
            let km = (1.0 - meanR) * (1.0 - meanR) / (2.0 * meanR)
            features["kubelka_munk_mean"] = MLFeatureValue(double: km)
        } else {
            features["kubelka_munk_mean"] = MLFeatureValue(double: 0)
        }

        // Absorption feature depths at diagnostic wavelengths
        var matchedFeatures = 0
        for feature in Self.diagnosticFeatures {
            let regionValues = zip(wavelengths, reflectance)
                .filter { abs($0.0 - feature.centerNM) <= feature.widthNM }
                .map(\.1)
            if let regionMin = regionValues.min() {
                // Continuum-removed depth: 1 - R_min/R_continuum
                let depth = maxR > 0 ? 1.0 - regionMin / maxR : 0
                if depth > 0.02 {
                    matchedFeatures += 1
                    features["depth_\(Int(feature.centerNM))"] = MLFeatureValue(double: depth)
                }
            }
        }
        features["matched_features"] = MLFeatureValue(double: Double(matchedFeatures))

        // VNIR vs SWIR ratio
        let vnirMean = zip(wavelengths, reflectance)
            .filter { $0.0 >= 400 && $0.0 < 1000 }.map(\.1)
        let swirMean = zip(wavelengths, reflectance)
            .filter { $0.0 >= 1000 && $0.0 <= 2500 }.map(\.1)
        let vnirAvg = vnirMean.isEmpty ? 0 : vnirMean.reduce(0, +) / Double(vnirMean.count)
        let swirAvg = swirMean.isEmpty ? 0 : swirMean.reduce(0, +) / Double(swirMean.count)
        features["vnir_swir_ratio"] = MLFeatureValue(double: swirAvg > 0 ? vnirAvg / swirAvg : 0)

        // Spectral slope
        if wavelengths.count >= 2 {
            let n = Double(wavelengths.count)
            let sumXY = zip(wavelengths, reflectance).map { $0 * $1 }.reduce(0, +)
            let sumX = wavelengths.reduce(0, +)
            let sumY = reflectance.reduce(0, +)
            let sumX2 = wavelengths.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            let slope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0
            features["spectral_slope"] = MLFeatureValue(double: slope)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        reflectance: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Reflectance must be bounded 0-1
        let outOfBounds = reflectance.filter { $0 < 0 || $0 > 1.0 }.count
        score -= Double(outOfBounds) / Double(reflectance.count) * 0.4

        // 2. Wavelength range: USGS splib07 covers 350-2500 nm
        let minWL = wavelengths.min() ?? 0
        let maxWL = wavelengths.max() ?? 0
        if minWL < 0 || maxWL > 5000 {
            score -= 0.15
        }

        // 3. Kubelka-Munk transform should be non-negative for valid reflectance
        let invalidKM = reflectance.filter { $0 <= 0 || $0 >= 1.0 }.count
        score -= min(Double(invalidKM) / Double(reflectance.count) * 0.1, 0.1)

        // 4. Smoothness: reflectance spectra should not have extreme point-to-point variation
        var jumpCount = 0
        for i in 1..<reflectance.count {
            if abs(reflectance[i] - reflectance[i - 1]) > 0.3 {
                jumpCount += 1
            }
        }
        score -= min(Double(jumpCount) * 0.03, 0.2)

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Mineral Identification

    private func identifyMinerals(
        wavelengths: [Double],
        reflectance: [Double]
    ) -> [String: [Double]] {
        var minerals: [String: [Double]] = [:]
        let maxR = reflectance.max() ?? 1

        for feature in Self.diagnosticFeatures {
            let regionValues = zip(wavelengths, reflectance)
                .filter { abs($0.0 - feature.centerNM) <= feature.widthNM }
                .map(\.1)

            if let regionMin = regionValues.min() {
                let depth = maxR > 0 ? 1.0 - regionMin / maxR : 0
                if depth > 0.03 {
                    let key = feature.mineral
                    minerals[key] = [depth * 100, feature.centerNM]
                }
            }
        }

        return minerals
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
