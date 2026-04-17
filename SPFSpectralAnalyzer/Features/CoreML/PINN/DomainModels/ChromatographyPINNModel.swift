import Foundation
import CoreML

/// Physics-Informed Neural Network model for Chromatography (HPLC/GC).
///
/// Implements LKM-PINN (Tang et al. 2023) architecture embedding the Lumped Kinetic Model
/// transport PDE: ∂c/∂t + u·∂c/∂z + F·∂q/∂t = D·∂²c/∂z²
/// with Langmuir isotherm: q = qₛ·K·c/(1+K·c).
/// Uses inverse PINN mode with trainable parameters for D, k, qₛ, and K.
///
/// References:
/// - Tang et al. 2023 (J. Chromatography A) — LKM-PINN, 30-160s training, 0.075 avg error
/// - Rekas et al. 2025 (J. Chromatography A) — first gradient LC PINN
/// - Zou et al. 2024 (J. Chromatography A) — 35% error reduction, 95% computation reduction
/// - Punj et al. 2025 (I&EC Research) — IEC mAb, R²=0.999
final class ChromatographyPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .chromatography

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Chromatography LKM-PINN with transport PDE + Langmuir isotherm constraints"
    }

    var physicsConstraints: [String] {
        [
            "Mass balance PDE: ∂c/∂t + u·∂c/∂z + F·∂q/∂t = D·∂²c/∂z²",
            "Langmuir isotherm: q = qₛ·K·c / (1 + K·c)",
            "Boundary conditions: inlet concentration profile matching",
            "Initial conditions: empty column equilibration",
            "Isotherm consistency: adsorption/desorption equilibrium"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?
    static let modelName = "PINN_Chromatography"

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
        guard wavelengths.count == intensities.count, wavelengths.count >= 10 else { return nil }

        // In chromatography, wavelengths = retention time (minutes), intensities = detector response
        let featureDict = buildFeatures(retentionTimes: wavelengths, response: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let retentionTime = prediction.featureValue(for: "retention_time")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = retentionTime
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(retentionTimes: wavelengths, response: intensities)

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Retention Time (min)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzePeaks(retentionTimes: wavelengths, response: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .chromatography,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(retentionTimes: [Double], response: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let peaks = findChromatographicPeaks(times: retentionTimes, response: response)
        features["peak_count"] = MLFeatureValue(double: Double(peaks.count))

        // Main peak characteristics
        if let mainPeak = peaks.first {
            features["main_peak_time"] = MLFeatureValue(double: mainPeak.retentionTime)
            features["main_peak_height"] = MLFeatureValue(double: mainPeak.height)
            features["main_peak_width"] = MLFeatureValue(double: mainPeak.width)
            features["main_peak_asymmetry"] = MLFeatureValue(double: mainPeak.asymmetry)
        } else {
            features["main_peak_time"] = MLFeatureValue(double: 0)
            features["main_peak_height"] = MLFeatureValue(double: 0)
            features["main_peak_width"] = MLFeatureValue(double: 0)
            features["main_peak_asymmetry"] = MLFeatureValue(double: 1.0)
        }

        // Column efficiency
        if let mainPeak = peaks.first, mainPeak.width > 0 {
            let theoreticalPlates = 5.545 * pow(mainPeak.retentionTime / mainPeak.width, 2)
            features["theoretical_plates"] = MLFeatureValue(double: theoreticalPlates)
        } else {
            features["theoretical_plates"] = MLFeatureValue(double: 0)
        }

        // Resolution (if 2+ peaks)
        if peaks.count >= 2 {
            let resolution = 2.0 * (peaks[1].retentionTime - peaks[0].retentionTime) /
                (peaks[0].width + peaks[1].width)
            features["resolution"] = MLFeatureValue(double: resolution)
        } else {
            features["resolution"] = MLFeatureValue(double: 0)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(retentionTimes: [Double], response: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity: detector response ≥ 0
        let negCount = response.filter { $0 < -0.001 }.count
        score -= Double(negCount) / Double(response.count) * 0.3

        // 2. Time ordering: retention times must be monotonically increasing
        var isMonotonic = true
        for i in 1..<retentionTimes.count {
            if retentionTimes[i] < retentionTimes[i - 1] {
                isMonotonic = false
                break
            }
        }
        if !isMonotonic { score -= 0.2 }

        // 3. Peak shape: chromatographic peaks should be approximately Gaussian
        let peaks = findChromatographicPeaks(times: retentionTimes, response: response)
        for peak in peaks.prefix(3) {
            // Asymmetry factor should be close to 1.0 (ideal Gaussian)
            if peak.asymmetry < 0.5 || peak.asymmetry > 3.0 {
                score -= 0.1 // Severely tailing or fronting peaks
            }
        }

        // 4. Baseline return: signal should return to baseline between peaks
        let sortedResponse = response.sorted()
        let baseline = sortedResponse[sortedResponse.count / 10]
        let maxResponse = sortedResponse.last ?? 0
        if baseline > maxResponse * 0.2 {
            score -= 0.1 // Elevated baseline suggests column issues
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Peak Detection

    private struct ChromPeak {
        let retentionTime: Double
        let height: Double
        let width: Double      // Width at half height
        let asymmetry: Double  // Tailing factor
    }

    private func findChromatographicPeaks(times: [Double], response: [Double]) -> [ChromPeak] {
        guard response.count >= 5 else { return [] }

        let threshold = (response.max() ?? 0) * 0.03
        var peaks: [ChromPeak] = []

        for i in 2..<response.count - 2 {
            if response[i] > response[i - 1] &&
               response[i] > response[i + 1] &&
               response[i] > response[i - 2] &&
               response[i] > response[i + 2] &&
               response[i] > threshold {

                let halfHeight = response[i] / 2.0

                // Find width at half height
                var leftIdx = i
                while leftIdx > 0 && response[leftIdx] > halfHeight { leftIdx -= 1 }
                var rightIdx = i
                while rightIdx < response.count - 1 && response[rightIdx] > halfHeight { rightIdx += 1 }

                let width = times[rightIdx] - times[leftIdx]

                // Asymmetry factor (USP tailing factor)
                let leftHalf = times[i] - times[leftIdx]
                let rightHalf = times[rightIdx] - times[i]
                let asymmetry = leftHalf > 0 ? rightHalf / leftHalf : 1.0

                peaks.append(ChromPeak(
                    retentionTime: times[i],
                    height: response[i],
                    width: max(width, 0.001),
                    asymmetry: asymmetry
                ))
            }
        }

        return peaks.sorted { $0.height > $1.height }
    }

    /// Analyze chromatographic peaks for decomposition output.
    private func analyzePeaks(retentionTimes: [Double], response: [Double]) -> [String: [Double]] {
        let peaks = findChromatographicPeaks(times: retentionTimes, response: response)
        var result: [String: [Double]] = [:]

        for (i, peak) in peaks.prefix(5).enumerated() {
            result["Peak \(i + 1) (t=\(String(format: "%.2f", peak.retentionTime)) min)"] = [
                peak.height, peak.width, peak.asymmetry
            ]
        }

        if let mainPeak = peaks.first, mainPeak.width > 0 {
            let plates = 5.545 * pow(mainPeak.retentionTime / mainPeak.width, 2)
            result["Column Efficiency"] = [plates]
        }

        return result
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
