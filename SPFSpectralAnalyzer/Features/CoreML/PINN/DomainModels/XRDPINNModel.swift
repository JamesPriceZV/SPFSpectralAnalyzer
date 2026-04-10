import Foundation
import CoreML

/// Physics-Informed Neural Network model for X-ray Diffraction.
///
/// Uses f-PICNN architecture (Yuan et al. 2024) with NCU convolution units.
/// Embeds Bragg's law (nλ = 2d·sinθ), systematic absences from space group symmetry,
/// structure factor constraints, and Debye-Waller thermal vibration corrections.
///
/// References:
/// - Yuan et al. 2024 (J. Computational Physics) — f-PICNN, 5-10x convergence speedup
/// - Zhou et al. 2025 (Communications Physics) — Auto-PICNN architecture search
final class XRDPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .xrd

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "XRD PINN (f-PICNN) with Bragg's law + structure factor constraints"
    }

    var physicsConstraints: [String] {
        [
            "Bragg's law: nλ = 2d·sinθ — peak positions → valid d-spacings",
            "Systematic absences: space group symmetry → forbidden reflections absent",
            "Structure factor: F(hkl) = Σ fⱼ·exp(2πi(hxⱼ+kyⱼ+lzⱼ))",
            "Debye-Waller: peak widths related to thermal vibration (B-factor)",
            "Preferred orientation: March-Dollase correction"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?
    static let modelName = "PINN_XRD"

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

        // In XRD, wavelengths = 2θ angles (degrees), intensities = diffraction counts
        let featureDict = buildFeatures(twoTheta: wavelengths, counts: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let latticeParam = prediction.featureValue(for: "lattice_parameter")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = latticeParam
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(twoTheta: wavelengths, counts: intensities)

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Lattice Parameter (Å)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: extractDSpacings(twoTheta: wavelengths, counts: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .xrd,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(twoTheta: [Double], counts: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Peak positions and d-spacings
        let peaks = findPeaks(twoTheta: twoTheta, counts: counts)
        features["peak_count"] = MLFeatureValue(double: Double(peaks.count))

        // Primary peak d-spacing (using Cu Kα: λ = 1.5406 Å)
        let cuKAlpha = 1.5406
        if let firstPeak = peaks.first {
            let dSpacing = cuKAlpha / (2.0 * sin(firstPeak.twoTheta / 2.0 * .pi / 180.0))
            features["primary_d_spacing"] = MLFeatureValue(double: dSpacing)
            features["primary_peak_2theta"] = MLFeatureValue(double: firstPeak.twoTheta)
            features["primary_peak_intensity"] = MLFeatureValue(double: firstPeak.intensity)
        } else {
            features["primary_d_spacing"] = MLFeatureValue(double: 0)
            features["primary_peak_2theta"] = MLFeatureValue(double: 0)
            features["primary_peak_intensity"] = MLFeatureValue(double: 0)
        }

        // Background and crystallinity
        let sortedCounts = counts.sorted()
        let background = sortedCounts[sortedCounts.count / 4]
        let peakSum = counts.filter { $0 > background * 2 }.reduce(0, +)
        let totalSum = counts.reduce(0, +)
        features["crystallinity_index"] = MLFeatureValue(double: totalSum > 0 ? peakSum / totalSum : 0)
        features["background_level"] = MLFeatureValue(double: background)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(twoTheta: [Double], counts: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity: diffraction counts must be ≥ 0
        let negCount = counts.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(counts.count) * 0.3

        // 2. Bragg's law consistency: check that peak spacings correspond to crystallographic planes
        let peaks = findPeaks(twoTheta: twoTheta, counts: counts)
        if peaks.count >= 2 {
            // Check for rational d-spacing ratios (characteristic of cubic, etc.)
            let cuKAlpha = 1.5406
            let dSpacings = peaks.map { cuKAlpha / (2.0 * sin($0.twoTheta / 2.0 * .pi / 180.0)) }
            if let maxD = dSpacings.first, maxD > 0 {
                let ratios = dSpacings.map { maxD / $0 }
                // For cubic crystals: ratios should approximate √(h²+k²+l²)
                let cubicRatios: [Double] = [1.0, 1.414, 1.732, 2.0, 2.236, 2.449]
                var matchCount = 0
                for ratio in ratios {
                    for target in cubicRatios {
                        if abs(ratio - target) < 0.1 { matchCount += 1; break }
                    }
                }
                let matchFraction = Double(matchCount) / Double(ratios.count)
                score -= (1.0 - matchFraction) * 0.15
            }
        }

        // 3. Reasonable 2θ range
        let minAngle = twoTheta.min() ?? 0
        let maxAngle = twoTheta.max() ?? 0
        if minAngle < 0 || maxAngle > 180 {
            score -= 0.2
        }

        return max(min(score, 1.0), 0.0)
    }

    /// Find diffraction peaks (local maxima above threshold).
    private func findPeaks(twoTheta: [Double], counts: [Double]) -> [(twoTheta: Double, intensity: Double)] {
        guard counts.count >= 3 else { return [] }
        let threshold = (counts.max() ?? 0) * 0.05
        var peaks: [(twoTheta: Double, intensity: Double)] = []

        for i in 1..<counts.count - 1 {
            if counts[i] > counts[i - 1] &&
               counts[i] > counts[i + 1] &&
               counts[i] > threshold {
                peaks.append((twoTheta: twoTheta[i], intensity: counts[i]))
            }
        }

        return peaks.sorted { $0.intensity > $1.intensity }
    }

    /// Extract d-spacings from peak positions using Bragg's law.
    private func extractDSpacings(twoTheta: [Double], counts: [Double]) -> [String: [Double]] {
        let cuKAlpha = 1.5406
        let peaks = findPeaks(twoTheta: twoTheta, counts: counts)
        var result: [String: [Double]] = [:]

        for (i, peak) in peaks.prefix(5).enumerated() {
            let sinTheta = sin(peak.twoTheta / 2.0 * .pi / 180.0)
            let dSpacing = sinTheta > 0 ? cuKAlpha / (2.0 * sinTheta) : 0
            result["Peak \(i + 1) (2θ=\(String(format: "%.2f°", peak.twoTheta)))"] = [dSpacing]
        }

        return result
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.1 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
