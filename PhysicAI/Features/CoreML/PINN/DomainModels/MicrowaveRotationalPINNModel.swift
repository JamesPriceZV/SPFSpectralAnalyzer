import Foundation
import CoreML

/// Physics-Informed Neural Network model for Microwave / Rotational Spectroscopy.
///
/// Embeds rigid rotor energy levels, centrifugal distortion corrections,
/// and selection rules for rotational transitions.
///
/// Architecture: 4-layer MLP, rigid rotor + centrifugal distortion loss terms.
///
/// References:
/// - CDMS (cdms.astro.uni-koeln.de) — Cologne Database for Molecular Spectroscopy
/// - Gordy & Cook, "Microwave Molecular Spectra"
final class MicrowaveRotationalPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .microwaveRotational

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Microwave PINN with rigid rotor energy levels + centrifugal distortion constraints"
    }

    var physicsConstraints: [String] {
        [
            "Rigid rotor: E_J = hBJ(J+1)",
            "Centrifugal distortion: E_J correction -hDJ^2(J+1)^2",
            "Selection rule: Delta J = +/-1"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_MicrowaveRotational"

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
        guard wavelengths.count == intensities.count, wavelengths.count >= 3 else { return nil }

        // wavelengths = frequencies (GHz), intensities = absorption intensity
        let featureDict = buildFeatures(frequencies: wavelengths, absorption: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let bConst = prediction.featureValue(for: "rotational_constant_B_GHz")?.doubleValue else {
                return nil
            }

            var denormalizedValue = bConst
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
                primaryLabel: "Rotational Constant B (GHz)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzeTransitions(frequencies: wavelengths, absorption: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .microwaveRotational,
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

        // Peak detection for rotational lines
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)
        features["line_count"] = MLFeatureValue(double: Double(peaks.count))
        features["max_absorption"] = MLFeatureValue(double: maxAbs)
        features["total_absorption"] = MLFeatureValue(double: absorption.reduce(0, +))

        // Line spacing analysis (for rigid rotor, spacing ~ 2B)
        if peaks.count >= 2 {
            let sortedFreqs = peaks.map(\.frequency).sorted()
            var spacings: [Double] = []
            for i in 1..<sortedFreqs.count {
                spacings.append(sortedFreqs[i] - sortedFreqs[i - 1])
            }
            let meanSpacing = spacings.reduce(0, +) / Double(spacings.count)
            let spacingVar = spacings.map { ($0 - meanSpacing) * ($0 - meanSpacing) }
                .reduce(0, +) / Double(spacings.count)

            features["mean_line_spacing_GHz"] = MLFeatureValue(double: meanSpacing)
            features["spacing_variance"] = MLFeatureValue(double: spacingVar)
            // B ~ mean_spacing / 2 for rigid rotor
            features["b_estimate_GHz"] = MLFeatureValue(double: meanSpacing / 2.0)
        } else {
            features["mean_line_spacing_GHz"] = MLFeatureValue(double: 0)
            features["spacing_variance"] = MLFeatureValue(double: 0)
            features["b_estimate_GHz"] = MLFeatureValue(double: 0)
        }

        // Frequency range
        let minFreq = frequencies.min() ?? 0
        let maxFreq = frequencies.max() ?? 0
        features["freq_range_GHz"] = MLFeatureValue(double: maxFreq - minFreq)
        features["strongest_line_GHz"] = MLFeatureValue(double: peaks.max(by: { $0.intensity < $1.intensity })?.frequency ?? 0)

        // Intensity envelope (should peak at J_max proportional to sqrt(T/B))
        if let strongestPeak = peaks.max(by: { $0.intensity < $1.intensity }) {
            features["envelope_peak_GHz"] = MLFeatureValue(double: strongestPeak.frequency)
        } else {
            features["envelope_peak_GHz"] = MLFeatureValue(double: 0)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        frequencies: [Double],
        absorption: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity of absorption
        let negCount = absorption.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(absorption.count) * 0.3

        // 2. Equal spacing check (rigid rotor: spacing = 2B, constant)
        let maxAbs = absorption.max() ?? 1
        let threshold = maxAbs * 0.05
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)

        if peaks.count >= 3 {
            let sortedFreqs = peaks.map(\.frequency).sorted()
            var spacings: [Double] = []
            for i in 1..<sortedFreqs.count {
                spacings.append(sortedFreqs[i] - sortedFreqs[i - 1])
            }
            let meanSpacing = spacings.reduce(0, +) / Double(spacings.count)
            if meanSpacing > 0 {
                // Coefficient of variation of spacings (should be small for rigid rotor)
                let cv = sqrt(spacings.map { ($0 - meanSpacing) * ($0 - meanSpacing) }
                    .reduce(0, +) / Double(spacings.count)) / meanSpacing
                if cv > 0.5 {
                    score -= 0.2  // Very irregular spacing
                } else if cv > 0.2 {
                    score -= 0.1  // Moderately irregular (centrifugal distortion is OK)
                }
            }
        }

        // 3. Intensity envelope should rise then fall with J
        if peaks.count >= 5 {
            let sortedPeaks = peaks.sorted { $0.frequency < $1.frequency }
            let intensities = sortedPeaks.map(\.intensity)
            // Find the peak of the intensity envelope
            if let maxIdx = intensities.enumerated().max(by: { $0.1 < $1.1 })?.offset {
                // Maximum should not be at the very first or last line
                if maxIdx == 0 || maxIdx == intensities.count - 1 {
                    score -= 0.1
                }
            }
        }

        // 4. Centrifugal distortion: spacing should slightly decrease with J
        if peaks.count >= 4 {
            let sortedFreqs = peaks.map(\.frequency).sorted()
            var spacings: [Double] = []
            for i in 1..<sortedFreqs.count {
                spacings.append(sortedFreqs[i] - sortedFreqs[i - 1])
            }
            // Check that spacing doesn't increase dramatically
            if spacings.count >= 3 {
                let lastSpacing = spacings.last!
                let firstSpacing = spacings.first!
                if lastSpacing > firstSpacing * 1.5 {
                    score -= 0.15  // Spacing increasing too much
                }
            }
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Transition Analysis

    private struct RotationalLine {
        let frequency: Double
        let intensity: Double
    }

    private func detectPeaks(
        frequencies: [Double],
        intensities: [Double],
        threshold: Double
    ) -> [RotationalLine] {
        var peaks: [RotationalLine] = []
        for i in 1..<intensities.count - 1 {
            if intensities[i] > intensities[i - 1]
                && intensities[i] > intensities[i + 1]
                && intensities[i] >= threshold {
                peaks.append(RotationalLine(frequency: frequencies[i], intensity: intensities[i]))
            }
        }
        return peaks
    }

    private func analyzeTransitions(
        frequencies: [Double],
        absorption: [Double]
    ) -> [String: [Double]] {
        var result: [String: [Double]] = [:]
        let maxAbs = absorption.max() ?? 1
        let threshold = maxAbs * 0.05
        let peaks = detectPeaks(frequencies: frequencies, intensities: absorption, threshold: threshold)

        if peaks.count >= 2 {
            let sortedFreqs = peaks.map(\.frequency).sorted()
            var spacings: [Double] = []
            for i in 1..<sortedFreqs.count {
                spacings.append(sortedFreqs[i] - sortedFreqs[i - 1])
            }
            let meanSpacing = spacings.reduce(0, +) / Double(spacings.count)
            result["Estimated 2B (GHz)"] = [meanSpacing]
            result["Estimated B (GHz)"] = [meanSpacing / 2.0]
        }

        result["Line Count"] = [Double(peaks.count)]

        if let strongest = peaks.max(by: { $0.intensity < $1.intensity }) {
            result["Strongest Line (GHz)"] = [strongest.frequency]
        }

        return result
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
