import Foundation
import CoreML

/// Physics-Informed Neural Network model for Atomic Emission Spectroscopy (AES/OES).
///
/// Embeds Boltzmann distribution for excited state populations, transition selection rules,
/// and Voigt line profile constraints as physics constraints.
///
/// Architecture: 4-layer MLP, Boltzmann distribution loss for excited state populations.
///
/// References:
/// - NIST Atomic Spectra Database — comprehensive emission line lists
/// - Kurucz atomic line database (Harvard-Smithsonian)
final class AtomicEmissionPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .atomicEmission

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Atomic Emission PINN with Boltzmann distribution + transition selection rule constraints"
    }

    var physicsConstraints: [String] {
        [
            "Boltzmann distribution: I ∝ gA·exp(-E/kT) for excited state populations",
            "Transition selection rules: Δl = ±1 (allowed electric dipole transitions)",
            "Line profiles: Voigt profile (Gaussian Doppler + Lorentzian pressure broadening)",
            "Self-absorption correction at high concentrations"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_AtomicEmission"

    /// Known emission line positions (nm) for common elements (NIST Atomic Spectra Database).
    static let knownEmissionLines: [(element: String, wavelength: Double, tolerance: Double)] = [
        ("Na I",  589.0, 2.0),   // Sodium D-line doublet
        ("Na I",  589.6, 2.0),
        ("Ca II", 393.4, 2.0),   // Calcium H-line
        ("Ca II", 396.8, 2.0),   // Calcium K-line
        ("Ca I",  422.7, 2.0),
        ("K I",   766.5, 2.0),   // Potassium
        ("K I",   769.9, 2.0),
        ("Fe I",  371.9, 2.0),   // Iron
        ("Fe I",  374.6, 2.0),
        ("Fe I",  382.0, 2.0),
        ("Mg I",  285.2, 2.0),   // Magnesium
        ("Mg II", 279.6, 2.0),
        ("Cu I",  324.8, 2.0),   // Copper
        ("Cu I",  327.4, 2.0),
        ("Zn I",  213.9, 2.0),   // Zinc
        ("Al I",  396.2, 2.0),   // Aluminum
        ("Li I",  670.8, 2.0),   // Lithium
        ("Sr II", 407.8, 2.0),   // Strontium
        ("Ba II", 455.4, 2.0),   // Barium
        ("Cr I",  357.9, 2.0),   // Chromium
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
        guard wavelengths.count == intensities.count, wavelengths.count >= 5 else { return nil }

        // In atomic emission, wavelengths = emission wavelengths (nm), intensities = emission intensity
        let featureDict = buildFeatures(wavelengths: wavelengths, emissionIntensities: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let concentration = prediction.featureValue(for: "concentration")?.doubleValue else {
                return nil
            }

            // Denormalize if model was trained with normalization
            var denormalizedValue = concentration
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
                primaryLabel: "Concentration (ppm)",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyElements(wavelengths: wavelengths, emissionIntensities: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .atomicEmission,
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

        // Peak detection: count significant emission lines
        let peaks = detectPeaks(wavelengths: wavelengths, intensities: emissionIntensities, threshold: threshold)
        features["peak_count"] = MLFeatureValue(double: Double(peaks.count))
        features["max_intensity"] = MLFeatureValue(double: maxIntensity)
        features["total_emission"] = MLFeatureValue(double: emissionIntensities.reduce(0, +))

        // Known element line matching
        var matchedElements = 0
        for line in Self.knownEmissionLines {
            let lineIntensity = emissionIntensities.enumerated()
                .filter { abs(wavelengths[$0.offset] - line.wavelength) <= line.tolerance }
                .map(\.element)
                .max() ?? 0
            if lineIntensity > threshold {
                matchedElements += 1
                features["line_\(line.element.replacingOccurrences(of: " ", with: "_"))_\(Int(line.wavelength))"] =
                    MLFeatureValue(double: lineIntensity / maxIntensity)
            }
        }
        features["matched_elements"] = MLFeatureValue(double: Double(matchedElements))

        // Background continuum estimate (median of lowest 20% intensities)
        let sorted = emissionIntensities.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        features["background_level"] = MLFeatureValue(double: background)

        // Signal-to-background ratio
        if background > 0 {
            features["signal_to_background"] = MLFeatureValue(double: maxIntensity / background)
        } else {
            features["signal_to_background"] = MLFeatureValue(double: maxIntensity)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        emissionIntensities: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity: emission intensities must be ≥ 0
        let negCount = emissionIntensities.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(emissionIntensities.count) * 0.3

        // 2. Boltzmann plot linearity check
        // For a single-temperature plasma, ln(I·λ/(g·A)) vs E should be linear
        // Approximate: check that relative peak intensities decrease with energy (shorter wavelengths)
        let maxIntensity = emissionIntensities.max() ?? 1
        let threshold = maxIntensity * 0.05
        let peaks = detectPeaks(wavelengths: wavelengths, intensities: emissionIntensities, threshold: threshold)

        if peaks.count >= 3 {
            // Check monotonic trend in intensity vs wavelength for dominant peaks
            // Higher energy (shorter λ) lines should generally be weaker for thermal sources
            let sortedPeaks = peaks.sorted { $0.wavelength < $1.wavelength }
            var violations = 0
            for i in 0..<sortedPeaks.count - 1 {
                // Short λ peak significantly stronger than long λ peak is unusual for thermal emission
                if sortedPeaks[i].intensity > sortedPeaks[i + 1].intensity * 5.0
                    && sortedPeaks[i].wavelength < sortedPeaks[i + 1].wavelength * 0.7 {
                    violations += 1
                }
            }
            score -= Double(violations) / Double(max(sortedPeaks.count - 1, 1)) * 0.2
        }

        // 3. Known line spacing validation: if Na D-lines detected, check doublet spacing (~0.6nm)
        let naD1 = peakInRegion(wavelengths: wavelengths, intensities: emissionIntensities, center: 589.0, tolerance: 2.0)
        let naD2 = peakInRegion(wavelengths: wavelengths, intensities: emissionIntensities, center: 589.6, tolerance: 2.0)
        if naD1 > threshold && naD2 > threshold {
            // D-line intensities should be similar (roughly 2:1 ratio)
            let ratio = max(naD1, naD2) / max(min(naD1, naD2), 0.001)
            if ratio > 5.0 {
                score -= 0.1 // Unexpected Na doublet ratio
            }
        }

        // 4. Background noise level
        let sorted = emissionIntensities.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        if maxIntensity > 0 && background / maxIntensity > 0.5 {
            score -= 0.15 // High background relative to signal
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Peak Detection

    private struct EmissionPeak {
        let wavelength: Double
        let intensity: Double
    }

    private func detectPeaks(
        wavelengths: [Double],
        intensities: [Double],
        threshold: Double
    ) -> [EmissionPeak] {
        var peaks: [EmissionPeak] = []

        for i in 1..<intensities.count - 1 {
            if intensities[i] > intensities[i - 1]
                && intensities[i] > intensities[i + 1]
                && intensities[i] >= threshold {
                peaks.append(EmissionPeak(wavelength: wavelengths[i], intensity: intensities[i]))
            }
        }

        return peaks
    }

    private func peakInRegion(
        wavelengths: [Double],
        intensities: [Double],
        center: Double,
        tolerance: Double
    ) -> Double {
        intensities.enumerated()
            .filter { abs(wavelengths[$0.offset] - center) <= tolerance }
            .map(\.element)
            .max() ?? 0
    }

    // MARK: - Element Identification

    private func identifyElements(
        wavelengths: [Double],
        emissionIntensities: [Double]
    ) -> [String: [Double]] {
        var elements: [String: [Double]] = [:]
        let maxIntensity = emissionIntensities.max() ?? 1
        let threshold = maxIntensity * 0.01

        for line in Self.knownEmissionLines {
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
        guard !conformalResiduals.isEmpty else { return 1.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
