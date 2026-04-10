import Foundation
import CoreML

/// Physics-Informed Neural Network model for NMR spectroscopy.
///
/// Embeds Bloch equation residuals, chemical shift prediction via shielding constants,
/// J-coupling multiplet patterns (Pascal's triangle), integration constraints
/// (peak area ∝ number of equivalent nuclei), and Kramers-Kronig relations.
///
/// Architecture: 4-layer MLP (512-256-128-64), Tanh activation, ReLoBRaLo loss balancing.
///
/// References:
/// - Bao et al. 2026 (Communications Chemistry) — physics-informed pure-shift NMR reconstruction
/// - Bonnin et al. 2024 — PINN for ¹H-MRS fitting at ultra-high field
final class NMRPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .nmr

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "NMR PINN with Bloch equation residuals + J-coupling pattern constraints"
    }

    var physicsConstraints: [String] {
        [
            "Bloch equations: dM/dt = γ(M × B) - R·(M - M₀)",
            "Chemical shift: δ correlates with electron density (shielding constants)",
            "J-coupling: multiplet splitting follows Pascal's triangle (first-order)",
            "Integration: peak areas proportional to number of equivalent nuclei",
            "Kramers-Kronig: absorption and dispersion are Hilbert-transform pairs"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?
    static let modelName = "PINN_NMR"

    /// Common chemical shift ranges (ppm) for ¹H NMR.
    static let chemicalShiftRegions: [(name: String, range: ClosedRange<Double>)] = [
        ("Alkyl (R-CH₃, R₂-CH₂)",  0.5...2.0),
        ("Allylic/α-CO",            2.0...2.5),
        ("Amino/Hydroxyl",          2.5...5.0),
        ("Olefinic",                5.0...6.5),
        ("Aromatic",                6.5...8.5),
        ("Aldehyde",                9.0...10.0),
        ("Carboxylic acid",        10.0...12.0),
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

        // In NMR, wavelengths = chemical shift (ppm), intensities = signal intensity
        let featureDict = buildFeatures(chemicalShifts: wavelengths, intensities: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let primaryValue = prediction.featureValue(for: "proton_count")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = primaryValue
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                chemicalShifts: wavelengths,
                intensities: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Estimated Proton Count",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyChemicalShiftRegions(
                    chemicalShifts: wavelengths,
                    intensities: intensities
                ),
                physicsConsistencyScore: physicsScore,
                domain: .nmr,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(chemicalShifts: [Double], intensities: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let totalIntegral = intensities.reduce(0, +)
        features["total_integral"] = MLFeatureValue(double: totalIntegral)
        features["peak_count"] = MLFeatureValue(double: Double(countPeaks(intensities: intensities)))

        // Region-specific integrals
        for region in Self.chemicalShiftRegions {
            let regionIntegral = zip(chemicalShifts, intensities)
                .filter { region.range.contains($0.0) }
                .map(\.1)
                .reduce(0, +)
            let safeName = region.name.replacingOccurrences(of: " ", with: "_")
                .replacingOccurrences(of: "(", with: "")
                .replacingOccurrences(of: ")", with: "")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "-", with: "_")
                .replacingOccurrences(of: "₃", with: "3")
                .replacingOccurrences(of: "₂", with: "2")
            features["region_\(safeName)"] = MLFeatureValue(double: regionIntegral)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(chemicalShifts: [Double], intensities: [Double]) -> Double {
        var score = 1.0

        // 1. Chemical shift range: ¹H NMR should be within 0-15 ppm
        let outOfRange = chemicalShifts.filter { $0 < -1 || $0 > 16 }.count
        score -= Double(outOfRange) / Double(chemicalShifts.count) * 0.3

        // 2. Integration ratio check: peak areas should be in approximately integer ratios
        let peaks = findPeakIntegrals(chemicalShifts: chemicalShifts, intensities: intensities)
        if peaks.count >= 2 {
            let minIntegral = peaks.min() ?? 1
            if minIntegral > 0 {
                let ratios = peaks.map { $0 / minIntegral }
                let nonIntegerCount = ratios.filter { r in
                    let nearest = round(r)
                    return abs(r - nearest) > 0.3
                }.count
                score -= Double(nonIntegerCount) / Double(ratios.count) * 0.2
            }
        }

        // 3. Baseline flatness outside peaks
        let baseline = intensities.sorted()
        let baselineMedian = baseline[baseline.count / 4]
        if baselineMedian > (intensities.max() ?? 0) * 0.1 {
            score -= 0.15 // High baseline suggests phase issues
        }

        return max(min(score, 1.0), 0.0)
    }

    /// Find approximate peak integrals for integration ratio check.
    private func findPeakIntegrals(chemicalShifts: [Double], intensities: [Double]) -> [Double] {
        let threshold = (intensities.max() ?? 0) * 0.05
        var integrals: [Double] = []
        var inPeak = false
        var currentIntegral = 0.0

        for intensity in intensities {
            if intensity > threshold {
                inPeak = true
                currentIntegral += intensity
            } else if inPeak {
                integrals.append(currentIntegral)
                currentIntegral = 0
                inPeak = false
            }
        }
        if inPeak { integrals.append(currentIntegral) }

        return integrals
    }

    /// Count peaks in the NMR spectrum.
    private func countPeaks(intensities: [Double]) -> Int {
        guard intensities.count >= 3 else { return 0 }
        let threshold = (intensities.max() ?? 0) * 0.05
        var count = 0
        for i in 1..<intensities.count - 1 {
            if intensities[i] > intensities[i - 1] &&
               intensities[i] > intensities[i + 1] &&
               intensities[i] > threshold {
                count += 1
            }
        }
        return count
    }

    /// Identify chemical shift regions present in the spectrum.
    private func identifyChemicalShiftRegions(
        chemicalShifts: [Double],
        intensities: [Double]
    ) -> [String: [Double]] {
        var regions: [String: [Double]] = [:]
        let totalIntegral = max(intensities.reduce(0, +), 1.0)

        for region in Self.chemicalShiftRegions {
            let regionIntegral = zip(chemicalShifts, intensities)
                .filter { region.range.contains($0.0) }
                .map(\.1)
                .reduce(0, +)

            if regionIntegral > totalIntegral * 0.02 {
                let percentage = regionIntegral / totalIntegral * 100
                regions[region.name] = [percentage]
            }
        }

        return regions
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 2.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
