import Foundation
import CoreML

/// Physics-Informed Neural Network model for Laser-Induced Breakdown Spectroscopy (LIBS).
///
/// Embeds Saha-Boltzmann plasma diagnostics for ionization equilibrium,
/// Stark broadening for electron density estimation, and self-absorption correction.
///
/// Architecture: 4-layer MLP, Saha-Boltzmann equilibrium loss for plasma temperature.
///
/// References:
/// - NIST Atomic Spectra Database (ASD) — emission line parameters
/// - Griem, H.R. — Plasma Spectroscopy (Stark broadening tables)
final class LIBSPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .libs

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "LIBS PINN with Saha-Boltzmann plasma diagnostics + Stark broadening constraints"
    }

    var physicsConstraints: [String] {
        [
            "Saha-Boltzmann: ionization equilibrium for plasma temperature",
            "Stark broadening: line width proportional to electron density",
            "Self-absorption correction at high concentrations"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_LIBS"

    /// Diagnostic emission lines commonly used in LIBS plasma characterisation.
    static let diagnosticLines: [(element: String, wavelength: Double, upperEnergy_eV: Double, gA: Double, tolerance: Double)] = [
        ("Fe I",  371.9, 4.26, 1.63e8,  2.0),
        ("Fe I",  374.6, 4.22, 1.15e8,  2.0),
        ("Fe I",  382.0, 4.10, 6.67e7,  2.0),
        ("Fe I",  404.6, 4.55, 8.62e7,  2.0),
        ("Ca II", 393.4, 3.15, 1.47e8,  2.0),
        ("Ca II", 396.8, 3.12, 1.40e8,  2.0),
        ("Ca I",  422.7, 2.93, 2.18e8,  2.0),
        ("Mg I",  285.2, 4.35, 4.91e8,  2.0),
        ("Mg II", 279.6, 4.43, 2.60e8,  2.0),
        ("Na I",  589.0, 2.10, 6.16e7,  2.0),
        ("Na I",  589.6, 2.10, 6.14e7,  2.0),
        ("H I",   656.3, 12.09, 4.41e7, 2.0),  // H-alpha (Stark broadened)
        ("Si I",  288.2, 5.08, 1.89e8,  2.0),
        ("Al I",  396.2, 3.14, 9.85e7,  2.0),
        ("Cu I",  324.8, 3.82, 1.39e8,  2.0),
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

        let featureDict = buildFeatures(wavelengths: wavelengths, emissionIntensities: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let temperature = prediction.featureValue(for: "plasma_temperature_K")?.doubleValue else {
                return nil
            }

            var denormalizedValue = temperature
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                emissionIntensities: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Plasma Temperature (K)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyElements(wavelengths: wavelengths, emissionIntensities: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .libs,
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
        emissionIntensities: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxIntensity = emissionIntensities.max() ?? 1
        let threshold = maxIntensity * 0.01
        features["max_intensity"] = MLFeatureValue(double: maxIntensity)
        features["total_emission"] = MLFeatureValue(double: emissionIntensities.reduce(0, +))

        // Match diagnostic lines
        var matchedLines = 0
        for line in Self.diagnosticLines {
            let lineIntensity = emissionIntensities.enumerated()
                .filter { abs(wavelengths[$0.offset] - line.wavelength) <= line.tolerance }
                .map(\.element)
                .max() ?? 0
            if lineIntensity > threshold {
                matchedLines += 1
                features["line_\(line.element.replacingOccurrences(of: " ", with: "_"))_\(Int(line.wavelength))"] =
                    MLFeatureValue(double: lineIntensity / maxIntensity)
            }
        }
        features["matched_lines"] = MLFeatureValue(double: Double(matchedLines))

        // H-alpha Stark width estimate (proxy for electron density)
        let hAlphaRegion = zip(wavelengths, emissionIntensities)
            .filter { abs($0.0 - 656.3) <= 10.0 }
        if let hMax = hAlphaRegion.map(\.1).max(), hMax > threshold {
            let halfMax = hMax / 2.0
            let aboveHalf = hAlphaRegion.filter { $0.1 >= halfMax }.map(\.0)
            let fwhm = (aboveHalf.max() ?? 656.3) - (aboveHalf.min() ?? 656.3)
            features["h_alpha_fwhm_nm"] = MLFeatureValue(double: fwhm)
        } else {
            features["h_alpha_fwhm_nm"] = MLFeatureValue(double: 0)
        }

        // Continuum background
        let sorted = emissionIntensities.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        features["continuum_level"] = MLFeatureValue(double: background)
        features["signal_to_background"] = MLFeatureValue(double: background > 0 ? maxIntensity / background : maxIntensity)

        // Ion-to-neutral ratio (Mg II / Mg I as proxy)
        let mgII = emissionIntensities.enumerated()
            .filter { abs(wavelengths[$0.offset] - 279.6) <= 2.0 }.map(\.element).max() ?? 0
        let mgI = emissionIntensities.enumerated()
            .filter { abs(wavelengths[$0.offset] - 285.2) <= 2.0 }.map(\.element).max() ?? 0
        features["ion_neutral_ratio"] = MLFeatureValue(double: mgI > threshold ? mgII / mgI : 0)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        emissionIntensities: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity
        let negCount = emissionIntensities.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(emissionIntensities.count) * 0.3

        // 2. Saha-Boltzmann: ion lines (Ca II, Mg II) should increase relative to neutrals at higher T
        let maxIntensity = emissionIntensities.max() ?? 1
        let threshold = maxIntensity * 0.05
        let caII = emissionIntensities.enumerated()
            .filter { abs(wavelengths[$0.offset] - 393.4) <= 2.0 }.map(\.element).max() ?? 0
        let caI = emissionIntensities.enumerated()
            .filter { abs(wavelengths[$0.offset] - 422.7) <= 2.0 }.map(\.element).max() ?? 0
        if caII > threshold && caI > threshold {
            // In a valid LIBS plasma, Ca II/Ca I ratio should be reasonable (0.1–100)
            let ratio = caII / max(caI, 1e-9)
            if ratio < 0.01 || ratio > 1000 {
                score -= 0.15
            }
        }

        // 3. Stark-broadened H-alpha should be wider than other lines
        let hAlphaRegion = zip(wavelengths, emissionIntensities)
            .filter { abs($0.0 - 656.3) <= 10.0 }
        if let hMax = hAlphaRegion.map(\.1).max(), hMax > threshold {
            let halfMax = hMax / 2.0
            let aboveHalf = hAlphaRegion.filter { $0.1 >= halfMax }.map(\.0)
            let fwhm = (aboveHalf.max() ?? 0) - (aboveHalf.min() ?? 0)
            if fwhm > 20.0 {
                score -= 0.15 // Unreasonably broad H-alpha
            }
        }

        // 4. Background level
        let sorted = emissionIntensities.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        if maxIntensity > 0 && background / maxIntensity > 0.5 {
            score -= 0.15
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Element Identification

    private func identifyElements(
        wavelengths: [Double],
        emissionIntensities: [Double]
    ) -> [String: [Double]] {
        var elements: [String: [Double]] = [:]
        let maxIntensity = emissionIntensities.max() ?? 1
        let threshold = maxIntensity * 0.01

        for line in Self.diagnosticLines {
            let lineIntensity = emissionIntensities.enumerated()
                .filter { abs(wavelengths[$0.offset] - line.wavelength) <= line.tolerance }
                .map(\.element)
                .max() ?? 0

            if lineIntensity > threshold {
                let key = line.element
                if elements[key] == nil {
                    elements[key] = [lineIntensity / maxIntensity * 100, line.wavelength]
                } else if lineIntensity / maxIntensity * 100 > (elements[key]?[0] ?? 0) {
                    elements[key] = [lineIntensity / maxIntensity * 100, line.wavelength]
                }
            }
        }

        return elements
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 500.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
