import Foundation
import CoreML

/// Physics-Informed Neural Network model for atmospheric UV/Vis absorption cross-sections.
///
/// Embeds Beer-Lambert absorption with temperature-dependent cross-sections sigma(lambda, T),
/// photolysis J-value calculation, and actinic flux weighting constraints.
///
/// Architecture: 4-layer MLP, Beer-Lambert + temperature-dependent cross-section loss.
///
/// References:
/// - MPI-Mainz UV/Vis Spectral Atlas (~800 atmospheric species)
/// - Burkholder et al. (2020) — Chemical kinetics and photochemical data (JPL/NASA)
final class AtmosphericUVVisPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .atmosphericUVVis

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Atmospheric UV/Vis PINN with temperature-dependent cross-sections + J-value constraints"
    }

    var physicsConstraints: [String] {
        [
            "Beer-Lambert: I = I0*exp(-sigma*N*l)",
            "Temperature-dependent cross-sections: sigma(lambda,T)",
            "Photolysis J-value calculation"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_AtmosphericUVVis"

    /// Key atmospheric absorbers and their characteristic UV/Vis absorption ranges (nm).
    static let knownAbsorbers: [(species: String, peakWavelength: Double, bandWidth: Double)] = [
        ("O3",   255.0,  40.0),    // Hartley band
        ("O3",   320.0,  30.0),    // Huggins band
        ("O3",   600.0, 100.0),    // Chappuis band
        ("NO2",  400.0,  50.0),    // Visible absorption
        ("SO2",  300.0,  20.0),    // UV absorption
        ("HCHO", 330.0,  20.0),    // Near-UV absorption
        ("BrO",  338.0,  15.0),
        ("OClO", 360.0,  20.0),
        ("ClO",  265.0,  15.0),
        ("HOCl", 303.0,  15.0),
        ("H2O2", 260.0,  30.0),
        ("N2O5", 260.0,  30.0),
        ("HNO3", 260.0,  20.0),
        ("NO3",  662.0,  10.0),    // Strong visible band
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

        // wavelengths = nm, intensities = cross-section sigma (cm^2/molecule)
        let featureDict = buildFeatures(wavelengths: wavelengths, crossSections: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let jValue = prediction.featureValue(for: "photolysis_J_value")?.doubleValue else {
                return nil
            }

            var denormalizedValue = jValue
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                wavelengths: wavelengths,
                crossSections: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Photolysis J-value (s\u{207B}\u{00B9})",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyAbsorbers(wavelengths: wavelengths, crossSections: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .atmosphericUVVis,
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
        crossSections: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxSigma = crossSections.max() ?? 1
        features["max_cross_section"] = MLFeatureValue(double: maxSigma)
        features["total_cross_section"] = MLFeatureValue(double: crossSections.reduce(0, +))

        // UV vs visible partitioning
        let uvIntegral = zip(wavelengths, crossSections)
            .filter { $0.0 >= 150 && $0.0 < 400 }.map(\.1).reduce(0, +)
        let visIntegral = zip(wavelengths, crossSections)
            .filter { $0.0 >= 400 && $0.0 < 800 }.map(\.1).reduce(0, +)
        let total = uvIntegral + visIntegral
        features["uv_fraction"] = MLFeatureValue(double: total > 0 ? uvIntegral / total : 0)

        // Peak wavelength
        if let peakIdx = crossSections.enumerated().max(by: { $0.1 < $1.1 }) {
            features["peak_wavelength_nm"] = MLFeatureValue(double: wavelengths[peakIdx.offset])
        }

        // Match known atmospheric absorbers
        var matchedSpecies = 0
        for absorber in Self.knownAbsorbers {
            let bandMax = zip(wavelengths, crossSections)
                .filter { abs($0.0 - absorber.peakWavelength) <= absorber.bandWidth }
                .map(\.1)
                .max() ?? 0
            if bandMax > maxSigma * 0.02 {
                matchedSpecies += 1
                features["absorber_\(absorber.species)"] = MLFeatureValue(double: bandMax / maxSigma)
            }
        }
        features["matched_species"] = MLFeatureValue(double: Double(matchedSpecies))

        // Spectral slope (proxy for Rayleigh vs molecular absorption)
        if wavelengths.count >= 2 {
            let logSigma = crossSections.map { log(max($0, 1e-25)) }
            let logLam = wavelengths.map { log(max($0, 1.0)) }
            let n = Double(logSigma.count)
            let sumXY = zip(logLam, logSigma).map { $0 * $1 }.reduce(0, +)
            let sumX = logLam.reduce(0, +)
            let sumY = logSigma.reduce(0, +)
            let sumX2 = logLam.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            let slope = denom != 0 ? (n * sumXY - sumX * sumY) / denom : 0
            features["spectral_slope"] = MLFeatureValue(double: slope)
        }

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        wavelengths: [Double],
        crossSections: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Cross-sections must be non-negative
        let negCount = crossSections.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(crossSections.count) * 0.3

        // 2. Wavelength range: atmospheric UV/Vis typically 150-800 nm
        let minWL = wavelengths.min() ?? 0
        let maxWL = wavelengths.max() ?? 0
        if minWL < 0 || maxWL > 2000 {
            score -= 0.15
        }

        // 3. Cross-section magnitude check: typical values 1e-24 to 1e-17 cm^2
        let maxSigma = crossSections.max() ?? 0
        if maxSigma > 1e-10 {
            score -= 0.2 // Unreasonably large cross-section
        }

        // 4. Smooth variation expected (no single-point spikes in cross-section data)
        var spikeCount = 0
        for i in 1..<crossSections.count - 1 {
            let localAvg = (crossSections[i - 1] + crossSections[i + 1]) / 2
            if localAvg > 0 && crossSections[i] / localAvg > 100.0 {
                spikeCount += 1
            }
        }
        score -= min(Double(spikeCount) * 0.05, 0.2)

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Absorber Identification

    private func identifyAbsorbers(
        wavelengths: [Double],
        crossSections: [Double]
    ) -> [String: [Double]] {
        var absorbers: [String: [Double]] = [:]
        let maxSigma = crossSections.max() ?? 1

        for absorber in Self.knownAbsorbers {
            let bandMax = zip(wavelengths, crossSections)
                .filter { abs($0.0 - absorber.peakWavelength) <= absorber.bandWidth }
                .map(\.1)
                .max() ?? 0

            if bandMax > maxSigma * 0.02 {
                let key = absorber.species
                let relStrength = bandMax / maxSigma * 100
                if absorbers[key] == nil || relStrength > (absorbers[key]?[0] ?? 0) {
                    absorbers[key] = [relStrength, absorber.peakWavelength]
                }
            }
        }

        return absorbers
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 1e-5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
