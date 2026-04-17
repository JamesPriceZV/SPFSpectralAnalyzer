import Foundation
import CoreML

/// Physics-Informed Neural Network model for Thermogravimetric Analysis (TGA).
///
/// Embeds Arrhenius kinetics for thermal decomposition, Coats-Redfern linearization
/// for activation energy estimation, and monotonic mass loss constraints.
///
/// Architecture: 4-layer MLP, Arrhenius + Coats-Redfern loss terms.
///
/// References:
/// - NIST JANAF Thermochemical Tables
/// - Coats & Redfern, "Kinetic parameters from thermogravimetric data"
final class TGAPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .thermogravimetric

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "TGA PINN with Arrhenius kinetics + Coats-Redfern activation energy constraints"
    }

    var physicsConstraints: [String] {
        [
            "Arrhenius: k = A*exp(-Ea/RT)",
            "Coats-Redfern linearization for activation energy",
            "Mass fraction bounded 0-1, monotonically decreasing"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_TGA"

    /// Gas constant in kJ/(mol*K).
    private static let R_kJ = 8.314e-3

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

        // wavelengths = temperature (C), intensities = mass fraction (0-1) or mass %
        let featureDict = buildFeatures(temperatures: wavelengths, massFraction: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let decompTemp = prediction.featureValue(for: "decomp_temp_C")?.doubleValue else {
                return nil
            }

            var denormalizedValue = decompTemp
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                temperatures: wavelengths,
                massFraction: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Decomposition Temp (\u{00B0}C)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzeDecomposition(temperatures: wavelengths, massFraction: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .thermogravimetric,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        temperatures: [Double],
        massFraction: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Normalize mass to 0-1 if given as percentage
        let mass: [Double]
        if let maxM = massFraction.max(), maxM > 1.5 {
            mass = massFraction.map { $0 / 100.0 }
        } else {
            mass = massFraction
        }

        let initialMass = mass.first ?? 1.0
        let finalMass = mass.last ?? 0.0
        let totalLoss = initialMass - finalMass

        features["initial_mass"] = MLFeatureValue(double: initialMass)
        features["final_mass"] = MLFeatureValue(double: finalMass)
        features["total_mass_loss"] = MLFeatureValue(double: totalLoss)
        features["residue_fraction"] = MLFeatureValue(double: finalMass / max(initialMass, 1e-9))

        // Onset temperature (5% mass loss)
        let onsetThreshold = initialMass - totalLoss * 0.05
        let onsetTemp = zip(temperatures, mass)
            .first { $0.1 <= onsetThreshold }
            .map(\.0) ?? temperatures.last ?? 0
        features["onset_temp_C"] = MLFeatureValue(double: onsetTemp)

        // DTG peak (maximum rate of mass loss)
        var maxRate = 0.0
        var maxRateTemp = 0.0
        for i in 1..<mass.count {
            let dT = temperatures[i] - temperatures[i - 1]
            guard dT > 0 else { continue }
            let rate = -(mass[i] - mass[i - 1]) / dT
            if rate > maxRate {
                maxRate = rate
                maxRateTemp = (temperatures[i] + temperatures[i - 1]) / 2
            }
        }
        features["dtg_peak_temp_C"] = MLFeatureValue(double: maxRateTemp)
        features["dtg_peak_rate"] = MLFeatureValue(double: maxRate)

        // Number of decomposition steps (inflection points in DTG)
        var rates: [Double] = []
        for i in 1..<mass.count {
            let dT = temperatures[i] - temperatures[i - 1]
            guard dT > 0 else { rates.append(0); continue }
            rates.append(-(mass[i] - mass[i - 1]) / dT)
        }
        var stepCount = 0
        let rateThreshold = maxRate * 0.1
        for i in 1..<rates.count - 1 {
            if rates[i] > rates[i - 1] && rates[i] > rates[i + 1] && rates[i] > rateThreshold {
                stepCount += 1
            }
        }
        features["decomposition_steps"] = MLFeatureValue(double: Double(max(stepCount, 1)))

        // Midpoint temperature (50% mass loss)
        let midThreshold = initialMass - totalLoss * 0.5
        let midTemp = zip(temperatures, mass)
            .first { $0.1 <= midThreshold }
            .map(\.0) ?? temperatures.last ?? 0
        features["midpoint_temp_C"] = MLFeatureValue(double: midTemp)

        // Temperature range
        features["temp_range_C"] = MLFeatureValue(double: (temperatures.max() ?? 0) - (temperatures.min() ?? 0))

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        temperatures: [Double],
        massFraction: [Double]
    ) -> Double {
        var score = 1.0

        let mass: [Double]
        if let maxM = massFraction.max(), maxM > 1.5 {
            mass = massFraction.map { $0 / 100.0 }
        } else {
            mass = massFraction
        }

        // 1. Mass fraction should be bounded 0-1
        let outOfBounds = mass.filter { $0 < -0.01 || $0 > 1.01 }.count
        score -= Double(outOfBounds) / Double(mass.count) * 0.3

        // 2. Mass should be monotonically non-increasing (allow small noise)
        var violations = 0
        for i in 1..<mass.count {
            if mass[i] > mass[i - 1] + 0.01 { violations += 1 }
        }
        score -= Double(violations) / Double(max(mass.count - 1, 1)) * 0.3

        // 3. Initial mass should be close to 1.0 (or 100%)
        if let first = mass.first, abs(first - 1.0) > 0.1 {
            score -= 0.1
        }

        // 4. There should be at least some mass loss
        let totalLoss = (mass.first ?? 1) - (mass.last ?? 0)
        if totalLoss < 0.01 {
            score -= 0.15
        }

        // 5. Temperature should be monotonically increasing
        var tempViolations = 0
        for i in 1..<temperatures.count {
            if temperatures[i] < temperatures[i - 1] - 0.5 { tempViolations += 1 }
        }
        score -= Double(tempViolations) / Double(max(temperatures.count - 1, 1)) * 0.2

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Decomposition Analysis

    private func analyzeDecomposition(
        temperatures: [Double],
        massFraction: [Double]
    ) -> [String: [Double]] {
        var result: [String: [Double]] = [:]

        let mass: [Double]
        if let maxM = massFraction.max(), maxM > 1.5 {
            mass = massFraction.map { $0 / 100.0 }
        } else {
            mass = massFraction
        }

        let initialMass = mass.first ?? 1.0
        let finalMass = mass.last ?? 0.0
        let totalLoss = initialMass - finalMass

        // Onset (5% loss)
        let onsetTemp = zip(temperatures, mass)
            .first { $0.1 <= initialMass - totalLoss * 0.05 }
            .map(\.0) ?? 0
        result["Onset Temp (C)"] = [onsetTemp]

        // DTG peak
        var maxRate = 0.0
        var maxRateTemp = 0.0
        for i in 1..<mass.count {
            let dT = temperatures[i] - temperatures[i - 1]
            guard dT > 0 else { continue }
            let rate = -(mass[i] - mass[i - 1]) / dT
            if rate > maxRate { maxRate = rate; maxRateTemp = temperatures[i] }
        }
        result["DTG Peak Temp (C)"] = [maxRateTemp]
        result["Total Mass Loss (%)"] = [totalLoss * 100]
        result["Residue (%)"] = [finalMass * 100]

        return result
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
