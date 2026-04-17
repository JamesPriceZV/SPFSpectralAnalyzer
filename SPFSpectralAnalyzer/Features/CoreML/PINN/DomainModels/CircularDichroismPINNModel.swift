import Foundation
import CoreML

/// Physics-Informed Neural Network model for Circular Dichroism (CD) Spectroscopy.
///
/// Embeds Cotton effect differential absorption, secondary structure basis-spectrum
/// decomposition, and the constraint that structure fractions sum to unity.
///
/// Architecture: 4-layer MLP, Cotton effect + basis decomposition loss terms.
///
/// References:
/// - PCDDB (pcddb.cryst.bbk.ac.uk) — Protein Circular Dichroism Data Bank
/// - Greenfield & Fasman, basis spectra for secondary structure estimation
final class CircularDichroismPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .circularDichroism

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Circular Dichroism PINN with Cotton effect + secondary structure basis decomposition constraints"
    }

    var physicsConstraints: [String] {
        [
            "Cotton effect: differential absorption of L/R circularly polarised light",
            "Basis decomposition: CD = sum(fi*CDi) for secondary structure",
            "Secondary structure fractions sum to 1"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_CircularDichroism"

    /// Characteristic CD band positions (nm) for secondary structures.
    static let characteristicBands: [(structure: String, wavelength: Double, sign: String)] = [
        ("alpha-helix",  222.0, "negative"),   // n-pi* transition
        ("alpha-helix",  208.0, "negative"),   // pi-pi* exciton split
        ("alpha-helix",  193.0, "positive"),   // pi-pi* parallel
        ("beta-sheet",   218.0, "negative"),   // n-pi*
        ("beta-sheet",   196.0, "positive"),   // pi-pi*
        ("random-coil",  198.0, "negative"),   // strong negative near 198
        ("random-coil",  218.0, "weak"),       // weak positive/negative
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

        // wavelengths = nm, intensities = delta-epsilon (mdeg or delta-epsilon units)
        let featureDict = buildFeatures(wavelengths: wavelengths, deltaEpsilon: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let helixPct = prediction.featureValue(for: "alpha_helix_pct")?.doubleValue else {
                return nil
            }

            var denormalizedValue = helixPct
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                deltaEpsilon: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Alpha Helix (%)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: min(denormalizedValue + q90, 100),
                decomposition: estimateSecondaryStructure(wavelengths: wavelengths, deltaEpsilon: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .circularDichroism,
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
        deltaEpsilon: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxAbs = deltaEpsilon.map { abs($0) }.max() ?? 1
        features["max_abs_delta_epsilon"] = MLFeatureValue(double: maxAbs)

        // Band intensities at characteristic wavelengths
        features["cd_193"] = MLFeatureValue(double: valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 193))
        features["cd_208"] = MLFeatureValue(double: valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 208))
        features["cd_218"] = MLFeatureValue(double: valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 218))
        features["cd_222"] = MLFeatureValue(double: valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 222))

        // Ratio features (alpha-helix indicators)
        let cd222 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 222)
        let cd208 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 208)
        features["ratio_222_208"] = MLFeatureValue(double: abs(cd208) > 1e-6 ? cd222 / cd208 : 0)

        // Zero-crossing count (sign changes indicate Cotton effects)
        var zeroCrossings = 0
        for i in 1..<deltaEpsilon.count {
            if deltaEpsilon[i] * deltaEpsilon[i - 1] < 0 { zeroCrossings += 1 }
        }
        features["zero_crossings"] = MLFeatureValue(double: Double(zeroCrossings))

        // Positive vs negative integral
        let posIntegral = deltaEpsilon.filter { $0 > 0 }.reduce(0, +)
        let negIntegral = deltaEpsilon.filter { $0 < 0 }.reduce(0, +)
        features["positive_integral"] = MLFeatureValue(double: posIntegral)
        features["negative_integral"] = MLFeatureValue(double: negIntegral)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        deltaEpsilon: [Double]
    ) -> Double {
        var score = 1.0

        // 1. CD spectrum should have both positive and negative regions (Cotton effect)
        let hasPositive = deltaEpsilon.contains { $0 > 0 }
        let hasNegative = deltaEpsilon.contains { $0 < 0 }
        if !(hasPositive && hasNegative) {
            score -= 0.2
        }

        // 2. Alpha-helix signature: negative at 208 and 222, positive near 193
        let cd193 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 193)
        let cd208 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 208)
        let cd222 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 222)

        // Check if the spectrum is consistent with any known secondary structure
        let helixLike = cd208 < 0 && cd222 < 0 && cd193 > 0
        let sheetLike = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 218) < 0
            && valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 196) > 0
        let coilLike = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 198) < 0
        if !(helixLike || sheetLike || coilLike) {
            score -= 0.15
        }

        // 3. For alpha-helix, ratio of [theta]222/[theta]208 should be ~1.0
        if cd208 < 0 && cd222 < 0 {
            let ratio = cd222 / cd208
            if ratio < 0.5 || ratio > 2.0 {
                score -= 0.1
            }
        }

        // 4. Signal should be concentrated in 180-260 nm range
        let outOfRangePairs = zip(wavelengths, deltaEpsilon).filter { $0.0 < 180 || $0.0 > 260 }
        let outOfRangeValues = outOfRangePairs.map { abs($0.1) }
        let outOfRange: Double = outOfRangeValues.reduce(0, +)
        let absValues = deltaEpsilon.map { abs($0) }
        let totalSignal: Double = absValues.reduce(0, +)
        if totalSignal > 0 && outOfRange / totalSignal > 0.3 {
            score -= 0.15
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Secondary Structure Estimation

    private func estimateSecondaryStructure(
        wavelengths: [Double],
        deltaEpsilon: [Double]
    ) -> [String: [Double]] {
        var structure: [String: [Double]] = [:]

        let cd222 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 222)
        let cd208 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 208)
        let cd218 = valueAt(wavelengths: wavelengths, values: deltaEpsilon, target: 218)

        // Rough estimation based on band intensities
        let helixScore = max(0, min(100, -cd222 * 2.5))
        let sheetScore = max(0, min(100, -cd218 * 2.0))
        let coilScore = max(0, 100 - helixScore - sheetScore)

        structure["Alpha Helix"] = [helixScore]
        structure["Beta Sheet"] = [sheetScore]
        structure["Random Coil"] = [coilScore]

        // Diagnostic ratios
        if abs(cd208) > 1e-6 {
            structure["222/208 Ratio"] = [cd222 / cd208]
        }

        return structure
    }

    // MARK: - Helpers

    private func valueAt(wavelengths: [Double], values: [Double], target: Double) -> Double {
        guard let idx = wavelengths.enumerated().min(by: { abs($0.1 - target) < abs($1.1 - target) }) else {
            return 0
        }
        return idx.offset < values.count ? values[idx.offset] : 0
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
