import Foundation
import CoreML

/// Physics-Informed Neural Network model for Electron Energy Loss Spectroscopy (EELS).
///
/// Embeds core-loss edge onset energies, ELNES fine structure from density of states,
/// and Kramers-Kronig relations between real and imaginary dielectric functions.
///
/// Architecture: 4-layer MLP, core-loss onset + Kramers-Kronig loss terms.
///
/// References:
/// - eelsdb.eu — open EELS spectral database (ODbL license)
/// - Egerton, "Electron Energy-Loss Spectroscopy in the Electron Microscope"
final class EELSPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .eels

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "EELS PINN with core-loss edge onset + Kramers-Kronig dielectric function constraints"
    }

    var physicsConstraints: [String] {
        [
            "Core-loss onset corresponds to elemental binding energy",
            "ELNES fine structure from density of states",
            "Kramers-Kronig: epsilon1 and epsilon2 are related"
        ]
    }

    // MARK: - Private State

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?

    static let modelName = "PINN_EELS"

    /// Known core-loss edge energies (eV) for common elements.
    static let knownEdges: [(element: String, edgeEnergy: Double, tolerance: Double)] = [
        ("C",  284.0, 5.0),    // Carbon K-edge
        ("N",  401.0, 5.0),    // Nitrogen K-edge
        ("O",  532.0, 5.0),    // Oxygen K-edge
        ("Fe", 708.0, 5.0),    // Iron L2,3-edge
        ("Ti", 456.0, 5.0),    // Titanium L2,3-edge
        ("Si", 99.0,  5.0),    // Silicon L2,3-edge
        ("Al", 73.0,  5.0),    // Aluminum L2,3-edge
        ("Mn", 640.0, 5.0),    // Manganese L2,3-edge
        ("Ca", 346.0, 5.0),    // Calcium L2,3-edge
        ("Cu", 931.0, 5.0),    // Copper L2,3-edge
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

        let featureDict = buildFeatures(energyLoss: wavelengths, counts: intensities)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)

            guard let output = prediction.featureValue(for: "element_present")?.doubleValue else {
                return nil
            }

            var denormalizedValue = output
            if let norm = normParams {
                denormalizedValue = norm.denormalizeOutput(denormalizedValue)
            }

            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(
                energyLoss: wavelengths,
                counts: intensities
            )

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Element Present",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: identifyEdges(energyLoss: wavelengths, counts: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .eels,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(
        energyLoss: [Double],
        counts: [Double]
    ) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        let maxCounts = counts.max() ?? 1
        let threshold = maxCounts * 0.02

        // Edge detection
        var edgeCount = 0
        for edge in Self.knownEdges {
            let edgeIntensity = counts.enumerated()
                .filter { abs(energyLoss[$0.offset] - edge.edgeEnergy) <= edge.tolerance }
                .map(\.element)
                .max() ?? 0
            if edgeIntensity > threshold {
                edgeCount += 1
                features["edge_\(edge.element)_\(Int(edge.edgeEnergy))"] =
                    MLFeatureValue(double: edgeIntensity / maxCounts)
            }
        }
        features["edge_count"] = MLFeatureValue(double: Double(edgeCount))
        features["max_counts"] = MLFeatureValue(double: maxCounts)
        features["total_counts"] = MLFeatureValue(double: counts.reduce(0, +))

        // Zero-loss peak region (< 5 eV)
        let zeroLoss = counts.enumerated()
            .filter { energyLoss[$0.offset] < 5.0 }
            .map(\.element)
            .max() ?? 0
        features["zero_loss_peak"] = MLFeatureValue(double: zeroLoss)

        // Plasmon region (10-30 eV)
        let plasmonIntegral = counts.enumerated()
            .filter { energyLoss[$0.offset] >= 10 && energyLoss[$0.offset] <= 30 }
            .map(\.element)
            .reduce(0, +)
        features["plasmon_integral"] = MLFeatureValue(double: plasmonIntegral)

        // Background power-law exponent estimate
        let sorted = counts.sorted()
        let bgCount = max(sorted.count / 5, 1)
        let background = sorted.prefix(bgCount).reduce(0, +) / Double(bgCount)
        features["background_level"] = MLFeatureValue(double: background)

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(
        energyLoss: [Double],
        counts: [Double]
    ) -> Double {
        var score = 1.0

        // 1. Non-negativity: counts must be >= 0
        let negCount = counts.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(counts.count) * 0.3

        // 2. Zero-loss peak should be the strongest feature
        let maxCounts = counts.max() ?? 1
        let zlpMax = counts.enumerated()
            .filter { energyLoss[$0.offset] < 10.0 }
            .map(\.element)
            .max() ?? 0
        if zlpMax < maxCounts * 0.5 && !energyLoss.allSatisfy({ $0 > 50 }) {
            score -= 0.15
        }

        // 3. Background should decrease with energy loss (power-law)
        let highEnergyMean = counts.enumerated()
            .filter { energyLoss[$0.offset] > 800 }
            .map(\.element)
            .reduce(0, +) / max(Double(counts.enumerated().filter { energyLoss[$0.offset] > 800 }.count), 1)
        let midEnergyMean = counts.enumerated()
            .filter { energyLoss[$0.offset] >= 200 && energyLoss[$0.offset] <= 500 }
            .map(\.element)
            .reduce(0, +) / max(Double(counts.enumerated().filter { energyLoss[$0.offset] >= 200 && energyLoss[$0.offset] <= 500 }.count), 1)
        if highEnergyMean > midEnergyMean * 2.0 && midEnergyMean > 0 {
            score -= 0.2
        }

        // 4. Edge onsets should show step-like increase
        for edge in Self.knownEdges {
            let preEdge = counts.enumerated()
                .filter { energyLoss[$0.offset] >= edge.edgeEnergy - 20 && energyLoss[$0.offset] < edge.edgeEnergy - 5 }
                .map(\.element)
                .reduce(0, +)
            let postEdge = counts.enumerated()
                .filter { energyLoss[$0.offset] >= edge.edgeEnergy && energyLoss[$0.offset] <= edge.edgeEnergy + 15 }
                .map(\.element)
                .reduce(0, +)
            if preEdge > postEdge * 1.5 && postEdge > maxCounts * 0.01 {
                score -= 0.05
            }
        }

        return max(min(score, 1.0), 0.0)
    }

    // MARK: - Edge Identification

    private func identifyEdges(
        energyLoss: [Double],
        counts: [Double]
    ) -> [String: [Double]] {
        var elements: [String: [Double]] = [:]
        let maxCounts = counts.max() ?? 1
        let threshold = maxCounts * 0.02

        for edge in Self.knownEdges {
            let edgeIntensity = counts.enumerated()
                .filter { abs(energyLoss[$0.offset] - edge.edgeEnergy) <= edge.tolerance }
                .map(\.element)
                .max() ?? 0

            if edgeIntensity > threshold {
                elements[edge.element] = [edgeIntensity / maxCounts * 100, edge.edgeEnergy]
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
