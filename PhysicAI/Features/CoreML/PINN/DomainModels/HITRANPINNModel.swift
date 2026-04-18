import Foundation
import CoreML

/// Physics-Informed Neural Network model for HITRAN molecular absorption line spectra.
///
/// Embeds Voigt line profile physics (Doppler + Lorentzian broadening convolution),
/// temperature-scaled line intensities from partition functions, and pressure-dependent
/// broadening coefficients.
///
/// Architecture: 4-layer MLP, Voigt profile loss for spectral line shape constraints.
///
/// References:
/// - HITRAN2024 database (hitran.org) — 61 molecules, millions of transitions
/// - Gordon et al. (2022) — The HITRAN2020 molecular spectroscopic database
final class HITRANPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .hitran

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "HITRAN PINN with Voigt line profile + temperature-scaled intensity constraints"
    }

    var physicsConstraints: [String] {
        [
            "Voigt profile: convolution of Doppler and Lorentzian broadening",
            "Temperature-scaled line intensity from partition functions",
            "Pressure-dependent broadening coefficients"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_HITRAN"

    /// Common HITRAN molecule IDs and their characteristic absorption bands (cm-1).
    static let knownMolecules: [(moleculeID: Int, name: String, bandCenter: Double, bandWidth: Double)] = [
        (1,  "H2O",  1595.0, 200.0),
        (1,  "H2O",  3657.0, 300.0),
        (2,  "CO2",  2349.0, 100.0),
        (2,  "CO2",   667.0,  50.0),
        (3,  "O3",   1042.0, 100.0),
        (4,  "N2O",  2224.0, 100.0),
        (5,  "CO",   2143.0,  80.0),
        (6,  "CH4",  3019.0, 200.0),
        (6,  "CH4",  1306.0, 100.0),
        (7,  "O2",   1556.0,  50.0),
        (8,  "NO",   1876.0,  80.0),
        (9,  "SO2",  1152.0,  80.0),
        (10, "NO2",  1617.0, 100.0),
        (11, "NH3",   950.0, 100.0),
        (12, "HNO3", 1326.0, 100.0),
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

        // wavelengths = wavenumbers (cm-1), intensities = absorption coefficient k(nu)
        let featureDict = buildFeatures(wavenumbers: wavelengths, absorption: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let moleculeID = prediction.featureValue(for: "molecule_id")?.doubleValue else {
                return nil
            }

            var denormalizedValue = moleculeID
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavenumbers: wavelengths,
                absorption: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Molecule ID",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyMolecules(wavenumbers: wavelengths, absorption: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .hitran,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        wavenumbers: [Double],
        absorption: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxAbs = absorption.max() ?? 1
        features["max_absorption"] = MLFeatureValue(double: maxAbs)
        features["total_absorption"] = MLFeatureValue(double: absorption.reduce(0, +))

        // Peak detection
        var peakCount = 0
        for i in 1..<absorption.count - 1 {
            if absorption[i] > absorption[i - 1] && absorption[i] > absorption[i + 1]
                && absorption[i] > maxAbs * 0.01 {
                peakCount += 1
            }
        }
        features["peak_count"] = MLFeatureValue(double: Double(peakCount))

        // Match known molecular bands
        var matchedMolecules = 0
        for mol in Self.knownMolecules {
            let bandIntensity = zip(wavenumbers, absorption)
                .filter { abs($0.0 - mol.bandCenter) <= mol.bandWidth }
                .map(\.1)
                .max() ?? 0
            if bandIntensity > maxAbs * 0.02 {
                matchedMolecules += 1
                features["band_\(mol.name)_\(Int(mol.bandCenter))"] =
                    MLFeatureValue(double: bandIntensity / maxAbs)
            }
        }
        features["matched_molecules"] = MLFeatureValue(double: Double(matchedMolecules))

        // Spectral centroid
        let totalWeighted = zip(wavenumbers, absorption).map { $0.0 * $0.1 }.reduce(0, +)
        let totalAbs = absorption.reduce(0, +)
        features["spectral_centroid_cm1"] = MLFeatureValue(double: totalAbs > 0 ? totalWeighted / totalAbs : 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavenumbers: [Double],
        absorption: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity of absorption coefficient
        let negCount = absorption.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(absorption.count) * 0.3

        // 2. Voigt profile shape check: peaks should have smooth, symmetric-ish profiles
        let maxAbs = absorption.max() ?? 1
        var sharpPeaks = 0
        for i in 1..<absorption.count - 1 {
            if absorption[i] > maxAbs * 0.1 {
                let leftDiff = abs(absorption[i] - absorption[i - 1])
                let rightDiff = abs(absorption[i] - absorption[i + 1])
                // Extremely asymmetric peaks violate Voigt profile expectation
                if min(leftDiff, rightDiff) > 0 {
                    let asymmetry = max(leftDiff, rightDiff) / min(leftDiff, rightDiff)
                    if asymmetry > 50.0 { sharpPeaks += 1 }
                }
            }
        }
        score -= min(Double(sharpPeaks) * 0.05, 0.2)

        // 3. Wavenumber range should be physically meaningful for molecular absorption
        let minWN = wavenumbers.min() ?? 0
        let maxWN = wavenumbers.max() ?? 0
        if minWN < 0 || maxWN > 50000 {
            score -= 0.15
        }

        // 4. At least one known molecular band should be detectable
        var anyBandDetected = false
        for mol in Self.knownMolecules {
            let bandMax = zip(wavenumbers, absorption)
                .filter { abs($0.0 - mol.bandCenter) <= mol.bandWidth }
                .map(\.1)
                .max() ?? 0
            if bandMax > maxAbs * 0.05 {
                anyBandDetected = true
                break
            }
        }
        if !anyBandDetected && maxAbs > 0 {
            score -= 0.1
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Molecule Identification

    private func identifyMolecules(
        wavenumbers: [Double],
        absorption: [Double]
    ) -> [String: [Double]] {
        var molecules: [String: [Double]] = [:]
        let maxAbs = absorption.max() ?? 1

        for mol in Self.knownMolecules {
            let bandMax = zip(wavenumbers, absorption)
                .filter { abs($0.0 - mol.bandCenter) <= mol.bandWidth }
                .map(\.1)
                .max() ?? 0

            if bandMax > maxAbs * 0.02 {
                let key = mol.name
                let relStrength = bandMax / maxAbs * 100
                if molecules[key] == nil || relStrength > (molecules[key]?[0] ?? 0) {
                    molecules[key] = [relStrength, mol.bandCenter]
                }
            }
        }

        return molecules
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
