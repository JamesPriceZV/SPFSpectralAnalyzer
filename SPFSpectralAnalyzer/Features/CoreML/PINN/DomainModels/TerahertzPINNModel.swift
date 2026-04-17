import Foundation
import CoreML

/// Physics-Informed Neural Network model for Terahertz (THz) Spectroscopy.
///
/// Embeds Drude free-carrier conductivity model, Lorentz oscillator for phonon
/// modes, and non-negativity of optical conductivity.
///
/// Architecture: 4-layer MLP, Drude + Lorentz oscillator loss terms.
///
/// References:
/// - Zenodo THz pharmaceutical datasets
/// - Jepsen & Fischer, "Dynamic range in terahertz time-domain spectroscopy"
final class TerahertzPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .terahertz

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Terahertz PINN with Drude free-carrier + Lorentz oscillator model constraints"
    }

    var physicsConstraints: [String] {
        [
            "Drude: sigma1(w) = sigma0/(1+w^2*tau^2)",
            "Lorentz oscillator for phonon modes",
            "Optical conductivity must be non-negative"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_THz"

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

        // wavelengths = THz frequencies, intensities = absorption/conductivity
        let featureDict = buildFeatures(frequencies: wavelengths, absorption: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let classValue = prediction.featureValue(for: "compound_class")?.doubleValue else {
                return nil
            }

            var denormalizedValue = classValue
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                frequencies: wavelengths,
                absorption: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Compound Class",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzeSpectralFeatures(frequencies: wavelengths, absorption: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .terahertz,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        frequencies: [Double],
        absorption: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxAbs = absorption.max() ?? 1
        let threshold = maxAbs * 0.05

        features["max_absorption"] = MLFeatureValue(double: maxAbs)
        features["total_absorption"] = MLFeatureValue(double: absorption.reduce(0, +))

        // Peak detection for phonon modes
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)
        features["peak_count"] = MLFeatureValue(double: Double(peaks.count))

        if let strongest = peaks.max(by: { $0.intensity < $1.intensity }) {
            features["strongest_peak_THz"] = MLFeatureValue(double: strongest.frequency)
        } else {
            features["strongest_peak_THz"] = MLFeatureValue(double: 0)
        }

        // Low-frequency behavior (Drude-like: should decrease with frequency)
        let lowFreqPairs = zip(frequencies, absorption).filter { $0.0 < 1.0 }
        if lowFreqPairs.count >= 2 {
            let lowFreqSlope = linearSlope(
                x: lowFreqPairs.map(\.0),
                y: lowFreqPairs.map(\.1)
            )
            features["low_freq_slope"] = MLFeatureValue(double: lowFreqSlope)
        } else {
            features["low_freq_slope"] = MLFeatureValue(double: 0)
        }

        // Spectral regions
        let region1 = zip(frequencies, absorption)
            .filter { $0.0 >= 0.1 && $0.0 < 2.0 }.map(\.1).reduce(0, +)
        let region2 = zip(frequencies, absorption)
            .filter { $0.0 >= 2.0 && $0.0 < 5.0 }.map(\.1).reduce(0, +)
        let region3 = zip(frequencies, absorption)
            .filter { $0.0 >= 5.0 && $0.0 <= 10.0 }.map(\.1).reduce(0, +)
        features["region_0p1_2_THz"] = MLFeatureValue(double: region1)
        features["region_2_5_THz"] = MLFeatureValue(double: region2)
        features["region_5_10_THz"] = MLFeatureValue(double: region3)

        // Background level
        let sorted = absorption.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        features["background_level"] = MLFeatureValue(double: background)

        // Spectral contrast
        let minAbs = absorption.min() ?? 0
        features["spectral_contrast"] = MLFeatureValue(double: maxAbs > 0 ? (maxAbs - minAbs) / maxAbs : 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        frequencies: [Double],
        absorption: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity: optical conductivity / absorption must be >= 0
        let negCount = absorption.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(absorption.count) * 0.3

        // 2. Drude check: at very low frequencies, absorption should be high or flat
        //    (free-carrier response decreases with frequency)
        let lowFreq = zip(frequencies, absorption).filter { $0.0 < 0.5 }.map(\.1)
        let midFreq = zip(frequencies, absorption).filter { $0.0 >= 2.0 && $0.0 <= 5.0 }.map(\.1)
        if !lowFreq.isEmpty && !midFreq.isEmpty {
            let lowMean = lowFreq.reduce(0, +) / Double(lowFreq.count)
            let midMean = midFreq.reduce(0, +) / Double(midFreq.count)
            // For Drude materials, low freq should be higher; for insulators this may not hold
            // Only penalize if mid-freq is dramatically higher than expected
            if midMean > lowMean * 10 && lowMean > 0 {
                score -= 0.1
            }
        }

        // 3. Lorentz peaks should have finite width (not delta functions)
        let maxAbs = absorption.max() ?? 1
        let threshold = maxAbs * 0.1
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)
        for peak in peaks {
            // Check that neighboring points are lower (peak has width)
            let nearPeak = zip(frequencies, absorption)
                .filter { abs($0.0 - peak.frequency) < 0.5 && abs($0.0 - peak.frequency) > 0.01 }
                .map(\.1)
            if !nearPeak.isEmpty {
                let nearMax = nearPeak.max() ?? 0
                if nearMax < peak.intensity * 0.1 {
                    score -= 0.05  // Suspiciously narrow peak
                }
            }
        }

        // 4. Signal dynamic range should be reasonable
        let minPositive = absorption.filter { $0 > 0 }.min() ?? 1
        if maxAbs > 0 && maxAbs / minPositive > 1e6 {
            score -= 0.1
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Spectral Feature Analysis

    private struct THzPeak {
        let frequency: Double
        let intensity: Double
    }

    private func detectPeaks(
        frequencies: [Double],
        intensities: [Double],
        threshold: Double
    ) -> [THzPeak] {
        var peaks: [THzPeak] = []
        for i in 1..<intensities.count - 1 {
            if intensities[i] > intensities[i - 1]
                && intensities[i] > intensities[i + 1]
                && intensities[i] >= threshold {
                peaks.append(THzPeak(frequency: frequencies[i], intensity: intensities[i]))
            }
        }
        return peaks
    }

    private func analyzeSpectralFeatures(
        frequencies: [Double],
        absorption: [Double]
    ) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        let maxAbs = absorption.max() ?? 1
        let threshold = maxAbs * 0.05
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)

        result["Peak Count"] = [Double(peaks.count)]

        if let strongest = peaks.max(by: { $0.intensity < $1.intensity }) {
            result["Strongest Peak (THz)"] = [strongest.frequency, strongest.intensity]
        }

        // Region integrals
        let lowRegion = zip(frequencies, absorption)
            .filter { $0.0 < 2.0 }.map(\.1).reduce(0, +)
        let highRegion = zip(frequencies, absorption)
            .filter { $0.0 >= 2.0 }.map(\.1).reduce(0, +)
        result["Low-freq Integral (<2 THz)"] = [lowRegion]
        result["High-freq Integral (>2 THz)"] = [highRegion]

        return result
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
