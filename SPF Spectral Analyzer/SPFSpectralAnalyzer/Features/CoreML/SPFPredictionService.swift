import Foundation
import Observation

/// Scaffold for a future CoreML-based numerical SPF predictor.
/// The model is not yet trained — this service provides the interface and
/// placeholder logic so the rest of the app can integrate against a stable API.
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

    // MARK: - Singleton

    static let shared = SPFPredictionService()

    private init() {
        loadModelIfAvailable()
    }

    // MARK: - Model Loading

    /// Attempts to load a compiled CoreML model from the app bundle.
    /// Currently a no-op since the model has not been trained yet.
    func loadModelIfAvailable() {
        // Future implementation:
        // guard let modelURL = Bundle.main.url(forResource: "SPFPredictor", withExtension: "mlmodelc") else {
        //     status = .notTrained
        //     return
        // }
        // status = .loading
        // do {
        //     let config = MLModelConfiguration()
        //     config.computeUnits = .all
        //     model = try MLModel(contentsOf: modelURL, configuration: config)
        //     status = .ready
        // } catch {
        //     status = .error(error.localizedDescription)
        // }
        status = .notTrained
    }

    // MARK: - Prediction

    /// Predicts SPF from raw wavelength/absorbance arrays.
    /// - Parameters:
    ///   - wavelengths: Array of wavelength values (nm), expected 290–510 in 1 nm steps (221 points).
    ///   - absorbances: Corresponding absorbance values.
    /// - Returns: An `SPFMLPrediction` or `nil` if the model is not available.
    func predict(wavelengths: [Double], absorbances: [Double]) -> SPFMLPrediction? {
        guard status.isReady else { return nil }
        guard wavelengths.count == absorbances.count, wavelengths.count >= 111 else { return nil }

        // Placeholder — return nil until a trained model is bundled.
        // Future implementation will:
        // 1. Interpolate input to 290–510 nm at 1 nm spacing (221 points)
        // 2. Create MLMultiArray [1, 221] from absorbance values
        // 3. Run model.prediction(from:)
        // 4. Extract spf_estimate, confidence_low, confidence_high from output
        return nil
    }

    /// Convenience overload that accepts the spectrum x/y arrays and y-axis mode.
    func predict(x: [Double], y: [Double], yAxisMode: String) -> SPFMLPrediction? {
        // Only absorbance-mode input is supported for the model
        guard yAxisMode == "absorbance" || yAxisMode == "Absorbance" else { return nil }
        return predict(wavelengths: x, absorbances: y)
    }
}

// MARK: - Prediction Result

struct SPFMLPrediction: Equatable {
    let spfEstimate: Double
    let confidenceLow: Double
    let confidenceHigh: Double

    var formatted: String {
        String(format: "%.1f (%.1f–%.1f)", spfEstimate, confidenceLow, confidenceHigh)
    }
}
