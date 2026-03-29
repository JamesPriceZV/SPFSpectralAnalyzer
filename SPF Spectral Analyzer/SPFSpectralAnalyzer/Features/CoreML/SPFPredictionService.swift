import Foundation
import Observation
import CoreML

/// CoreML-based numerical SPF predictor.
/// Loads a trained model from app support (user-trained) or app bundle (pre-bundled),
/// computes predictions with conformal prediction intervals.
@MainActor @Observable
final class SPFPredictionService {

    // MARK: - Model Status

    enum ModelStatus: Equatable {
        case notTrained
        case loading
        case ready
        case error(String)

        var label: String {
            switch self {
            case .notTrained: return "Model not yet trained"
            case .loading:    return "Loading model…"
            case .ready:      return "Ready"
            case .error(let msg): return "Error: \(msg)"
            }
        }

        var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    var status: ModelStatus = .notTrained

    // MARK: - Private State

    private var model: MLModel?
    private var conformalResiduals: [Double] = []

    // MARK: - Singleton

    static let shared = SPFPredictionService()

    private init() {
        loadModelIfAvailable()
    }

    // MARK: - Model Loading

    /// Attempts to load a compiled CoreML model.
    /// Checks app support directory first (user-trained), then falls back to the app bundle.
    func loadModelIfAvailable() {
        status = .loading
        model = nil
        conformalResiduals = []

        // 1. Check app support directory (user-trained model)
        let userModelURL = MLTrainingService.compiledModelURL
        if FileManager.default.fileExists(atPath: userModelURL.path) {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: userModelURL, configuration: config)
                loadConformalResiduals()
                status = .ready
                Instrumentation.log("ML model loaded from app support", area: .processing, level: .info)
                return
            } catch {
                Instrumentation.log("Failed to load user-trained model", area: .processing, level: .warning,
                                    details: "error=\(error.localizedDescription)")
            }
        }

        // 2. Fall back to bundle
        if let bundleURL = Bundle.main.url(forResource: SPFModelSchema.modelResourceName,
                                           withExtension: SPFModelSchema.modelExtension) {
            do {
                let config = MLModelConfiguration()
                config.computeUnits = .all
                model = try MLModel(contentsOf: bundleURL, configuration: config)
                loadConformalResiduals()
                status = .ready
                Instrumentation.log("ML model loaded from bundle", area: .processing, level: .info)
                return
            } catch {
                status = .error(error.localizedDescription)
                return
            }
        }

        status = .notTrained
    }

    private func loadConformalResiduals() {
        let resultURL = MLTrainingService.trainingResultURL
        guard FileManager.default.fileExists(atPath: resultURL.path),
              let data = try? Data(contentsOf: resultURL),
              let result = try? JSONDecoder().decode(MLTrainingResult.self, from: data) else {
            return
        }
        conformalResiduals = result.conformalResiduals
    }

    // MARK: - Prediction

    /// Predicts SPF from raw wavelength/absorbance arrays with auxiliary metadata.
    func predict(
        wavelengths: [Double],
        absorbances: [Double],
        plateType: SubstratePlateType = .pmma,
        applicationQuantityMg: Double? = nil,
        formulationType: FormulationType = .unknown,
        isPostIrradiation: Bool = false
    ) -> SPFMLPrediction? {
        guard status.isReady, let model else { return nil }
        guard wavelengths.count == absorbances.count, wavelengths.count >= 2 else { return nil }

        // 1. Resample to 290-400nm at 1nm (111 points)
        guard let resampled = SPFCalibration.resampleAbsorbance(
            x: wavelengths, y: absorbances, yAxisMode: .absorbance
        ) else { return nil }

        // 2. Compute spectral metrics
        guard let metrics = SpectralMetricsCalculator.metrics(
            x: wavelengths, y: absorbances, yAxisMode: .absorbance
        ) else { return nil }

        // 3. Build feature dictionary
        var featureDict: [String: MLFeatureValue] = [:]

        // Spectral features
        for i in 0..<SPFModelSchema.spectralFeatureCount {
            let colName = SPFModelSchema.spectralFeatureColumns[i]
            featureDict[colName] = MLFeatureValue(double: i < resampled.count ? resampled[i] : 0)
        }

        // Derived metrics
        featureDict["critical_wavelength"] = MLFeatureValue(double: metrics.criticalWavelength)
        featureDict["uva_uvb_ratio"] = MLFeatureValue(double: metrics.uvaUvbRatio)
        featureDict["uvb_area"] = MLFeatureValue(double: metrics.uvbArea)
        featureDict["uva_area"] = MLFeatureValue(double: metrics.uvaArea)
        featureDict["mean_uvb_transmittance"] = MLFeatureValue(double: metrics.meanUVBTransmittance)
        featureDict["mean_uva_transmittance"] = MLFeatureValue(double: metrics.meanUVATransmittance)
        featureDict["peak_absorbance_wavelength"] = MLFeatureValue(double: metrics.peakAbsorbanceWavelength)

        // Auxiliary features
        let plateValue: Double = plateType == .pmma ? 0 : (plateType == .quartz ? 1 : 2)
        featureDict["plate_type"] = MLFeatureValue(double: plateValue)
        featureDict["application_quantity_mg"] = MLFeatureValue(double: applicationQuantityMg ?? 15.0)
        featureDict["formulation_type"] = MLFeatureValue(double: Double(formulationType.featureValue))
        featureDict["is_post_irradiation"] = MLFeatureValue(double: isPostIrradiation ? 1.0 : 0.0)

        // 4. Run prediction
        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let spfValue = prediction.featureValue(for: SPFModelSchema.targetColumn)?.doubleValue else {
                return nil
            }

            let spf = max(spfValue, 1.0)

            // 5. Compute conformal prediction intervals
            let q90 = conformalQuantile(level: 0.9)
            let confidenceLow = max(spf - q90, 1.0)
            let confidenceHigh = spf + q90

            return SPFMLPrediction(
                spfEstimate: spf,
                confidenceLow: confidenceLow,
                confidenceHigh: confidenceHigh
            )
        } catch {
            Instrumentation.log("ML prediction failed", area: .processing, level: .warning,
                                details: "error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Convenience overload for spectrum x/y arrays with y-axis mode.
    func predict(
        x: [Double], y: [Double],
        yAxisMode: SpectralYAxisMode,
        plateType: SubstratePlateType = .pmma,
        applicationQuantityMg: Double? = nil,
        formulationType: FormulationType = .unknown,
        isPostIrradiation: Bool = false
    ) -> SPFMLPrediction? {
        // Convert transmittance to absorbance if needed
        let absorbances: [Double]
        switch yAxisMode {
        case .absorbance:
            absorbances = y
        case .transmittance:
            absorbances = y.map { t in
                let clamped = max(t, 1.0e-10)
                return -log10(clamped)
            }
        }
        return predict(
            wavelengths: x,
            absorbances: absorbances,
            plateType: plateType,
            applicationQuantityMg: applicationQuantityMg,
            formulationType: formulationType,
            isPostIrradiation: isPostIrradiation
        )
    }

    // MARK: - Conformal Intervals

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else {
            return 5.0  // Default fallback interval when no calibration data
        }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}

// MARK: - Prediction Result

struct SPFMLPrediction: Equatable, Sendable {
    let spfEstimate: Double
    let confidenceLow: Double
    let confidenceHigh: Double

    var formatted: String {
        String(format: "%.1f (%.1f–%.1f)", spfEstimate, confidenceLow, confidenceHigh)
    }
}
