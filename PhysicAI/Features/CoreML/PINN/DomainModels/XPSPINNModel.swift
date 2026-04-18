import Foundation
import CoreML

/// Physics-Informed Neural Network model for X-ray Photoelectron Spectroscopy (XPS).
///
/// Embeds the photoelectric equation BE = hv - KE - phi, Scofield photoionisation
/// cross-sections for quantification, and chemical shift correlations with oxidation state.
///
/// Architecture: 4-layer MLP, photoelectric equation loss for binding energy constraints.
///
/// References:
/// - NIST XPS Database SRD 20 (>33,000 records)
/// - Scofield photoionisation cross-section tables (1973)
final class XPSPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .xps

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "XPS PINN with photoelectric equation + Scofield cross-section constraints"
    }

    var physicsConstraints: [String] {
        [
            "Photoelectric equation: BE = hv - KE - phi",
            "Scofield cross-sections for quantification",
            "Chemical shift correlation with oxidation state"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_XPS"

    /// Known core-level binding energies (eV) for common elements (NIST SRD 20).
    static let knownCoreLevels: [(element: String, orbital: String, be: Double, tolerance: Double)] = [
        ("C",  "1s", 284.8, 3.0),
        ("O",  "1s", 532.0, 3.0),
        ("N",  "1s", 400.0, 3.0),
        ("Si", "2p",  99.5, 3.0),
        ("Fe", "2p", 706.8, 5.0),
        ("Al", "2p",  72.8, 3.0),
        ("Ti", "2p", 453.8, 5.0),
        ("S",  "2p", 164.0, 3.0),
        ("F",  "1s", 686.0, 3.0),
        ("Cl", "2p", 199.0, 3.0),
        ("Cu", "2p", 932.7, 5.0),
        ("Zn", "2p", 1021.8, 5.0),
    ]

    /// Scofield cross-sections relative to C 1s = 1.00 at Al Ka (1486.6 eV).
    static let scofieldCrossSections: [String: Double] = [
        "C_1s": 1.00, "O_1s": 2.93, "N_1s": 1.80, "Si_2p": 0.87,
        "Fe_2p": 12.4, "Al_2p": 0.54, "Ti_2p": 7.90, "S_2p": 1.68,
        "F_1s": 4.43, "Cl_2p": 2.28, "Cu_2p": 21.1, "Zn_2p": 22.0,
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

        // wavelengths = binding energies (eV), intensities = photoelectron counts
        let featureDict = buildFeatures(bindingEnergies: wavelengths, counts: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let surfaceCarbon = prediction.featureValue(for: "surface_carbon_pct")?.doubleValue else {
                return nil
            }

            var denormalizedValue = surfaceCarbon
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                bindingEnergies: wavelengths,
                counts: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Surface Carbon (%)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: min(denormalizedValue + q90, 100),
                decomposition: identifyElements(bindingEnergies: wavelengths, counts: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .xps,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        bindingEnergies: [Double],
        counts: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxCount = counts.max() ?? 1
        let totalSignal = counts.reduce(0, +)
        features["max_intensity"] = MLFeatureValue(double: maxCount)
        features["total_signal_area"] = MLFeatureValue(double: totalSignal)

        // Detect core-level peaks for each known element
        var detectedElements = 0
        for cl in Self.knownCoreLevels {
            let peakIntensity = counts.enumerated()
                .filter { abs(bindingEnergies[$0.offset] - cl.be) <= cl.tolerance }
                .map(\.element)
                .max() ?? 0
            let key = "\(cl.element)_\(cl.orbital)"
            features["peak_\(key)"] = MLFeatureValue(double: peakIntensity / maxCount)
            if peakIntensity > maxCount * 0.02 {
                detectedElements += 1
            }
        }
        features["detected_elements"] = MLFeatureValue(double: Double(detectedElements))

        // Shirley background estimate (median of lowest 20%)
        let sorted = counts.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        features["background_level"] = MLFeatureValue(double: background)
        features["signal_to_background"] = MLFeatureValue(double: background > 0 ? maxCount / background : maxCount)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        bindingEnergies: [Double],
        counts: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity: photoelectron counts must be >= 0
        let negCount = counts.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(counts.count) * 0.3

        // 2. Binding energy range: XPS with Al Ka should have BE 0-1486.6 eV
        let outOfRange = bindingEnergies.filter { $0 < 0 || $0 > 1487 }.count
        score -= Double(outOfRange) / Double(bindingEnergies.count) * 0.2

        // 3. C 1s reference check: adventitious carbon at ~284.8 eV should typically be present
        let maxCount = counts.max() ?? 1
        let c1sIntensity = counts.enumerated()
            .filter { abs(bindingEnergies[$0.offset] - 284.8) <= 3.0 }
            .map(\.element)
            .max() ?? 0
        if c1sIntensity < maxCount * 0.01 {
            score -= 0.1 // Unusual to have no adventitious carbon
        }

        // 4. Scofield cross-section consistency: O 1s area should scale with sigma ratio
        let o1sIntensity = counts.enumerated()
            .filter { abs(bindingEnergies[$0.offset] - 532.0) <= 3.0 }
            .map(\.element)
            .max() ?? 0
        if c1sIntensity > 0 && o1sIntensity > 0 {
            let measuredRatio = o1sIntensity / c1sIntensity
            // Expected ratio ~2.93 for equal atomic concentrations
            if measuredRatio > 20.0 {
                score -= 0.1
            }
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Element Identification

    private func identifyElements(
        bindingEnergies: [Double],
        counts: [Double]
    ) -> [String: [Double]] {
        var elements: [String: [Double]] = [:]
        let maxCount = counts.max() ?? 1

        for cl in Self.knownCoreLevels {
            let peakIntensity = counts.enumerated()
                .filter { abs(bindingEnergies[$0.offset] - cl.be) <= cl.tolerance }
                .map(\.element)
                .max() ?? 0

            if peakIntensity > maxCount * 0.02 {
                let key = "\(cl.element) \(cl.orbital)"
                let sf = Self.scofieldCrossSections["\(cl.element)_\(cl.orbital)"] ?? 1.0
                let atomicPct = (peakIntensity / sf) / maxCount * 100
                elements[key] = [atomicPct, cl.be]
            }
        }

        return elements
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 5.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
