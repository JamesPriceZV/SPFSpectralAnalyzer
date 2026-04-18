import Foundation
import CoreML

/// Physics-Informed Neural Network model for Fluorescence spectroscopy.
///
/// Uses dual-network architecture for excitation-emission matrix decomposition.
/// Embeds Stokes shift constraint, mirror-image rule, Kasha's rule,
/// Beer-Lambert for excitation, and quantum yield consistency.
///
/// References:
/// - Puleio et al. 2025 — multi-agent decomposition (applicable to EEM/PARAFAC)
final class FluorescencePINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .fluorescence

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "Fluorescence PINN with Stokes shift + mirror-image + Kasha's rule constraints"
    }

    var physicsConstraints: [String] {
        [
            "Stokes shift: λ_em > λ_ex (emission redshifted from excitation)",
            "Mirror-image rule: absorption and emission spectra are approximately mirror images",
            "Kasha's rule: emission from lowest excited singlet (single emission peak per fluorophore)",
            "Beer-Lambert: absorbance at excitation wavelength follows concentration law",
            "Quantum yield: emission intensity ∝ quantum yield × absorbed photons"
        ]
    }

    nonisolated(unsafe) private var model: MLModel?
    nonisolated(unsafe) private var conformalResiduals: [Double] = []
    /// Z-score normalization parameters (nil for pre-normalization models).
    nonisolated(unsafe) private var normParams: PINNNormalizationParams?
    static let modelName = "PINN_Fluorescence"

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
        guard wavelengths.count == intensities.count, wavelengths.count >= 10 else { return nil }

        let featureDict = buildFeatures(wavelengths: wavelengths, intensities: intensities)

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
            let physicsScore = computePhysicsConsistency(wavelengths: wavelengths, intensities: intensities)

            return PINNPredictionResult(
                primaryValue: denormalizedValue,
                primaryLabel: "Fluorophore Concentration",
                confidenceLow: max(denormalizedValue - q90, 0),
                confidenceHigh: denormalizedValue + q90,
                decomposition: analyzeEmissionCharacteristics(wavelengths: wavelengths, intensities: intensities),
                physicsConsistencyScore: physicsScore,
                domain: .fluorescence,
                ensembleStd: 0,
                headValues: []
            )
        } catch {
            return nil
        }
    }

    // MARK: - Feature Engineering

    private func buildFeatures(wavelengths: [Double], intensities: [Double]) -> [String: MLFeatureValue] {
        var features: [String: MLFeatureValue] = [:]

        // Emission peak characteristics
        let maxIdx = intensities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        features["emission_peak_wavelength"] = MLFeatureValue(double: wavelengths[maxIdx])
        features["emission_peak_intensity"] = MLFeatureValue(double: intensities[maxIdx])

        // Full-width at half maximum (FWHM)
        let halfMax = (intensities.max() ?? 0) / 2.0
        let fwhm = computeFWHM(wavelengths: wavelengths, intensities: intensities, halfMax: halfMax)
        features["fwhm"] = MLFeatureValue(double: fwhm)

        // Spectral statistics
        features["total_emission"] = MLFeatureValue(double: intensities.reduce(0, +))
        features["mean_intensity"] = MLFeatureValue(double: intensities.reduce(0, +) / Double(intensities.count))

        // Spectral asymmetry (mirror-image rule)
        features["spectral_asymmetry"] = MLFeatureValue(double: computeAsymmetry(
            wavelengths: wavelengths, intensities: intensities, peakIdx: maxIdx
        ))

        return features
    }

    // MARK: - Physics Consistency

    private func computePhysicsConsistency(wavelengths: [Double], intensities: [Double]) -> Double {
        var score = 1.0

        // 1. Non-negativity: fluorescence intensity ≥ 0
        let negCount = intensities.filter { $0 < 0 }.count
        score -= Double(negCount) / Double(intensities.count) * 0.3

        // 2. Single emission peak (Kasha's rule)
        let peakCount = countSignificantPeaks(intensities: intensities)
        if peakCount > 2 {
            score -= 0.15 // Multiple peaks may violate Kasha's rule (though could be multiple fluorophores)
        }

        // 3. Spectral smoothness (emission bands should be smooth Gaussian-like)
        if intensities.count >= 3 {
            var d2Sum = 0.0
            for i in 1..<intensities.count - 1 {
                let d2 = intensities[i + 1] - 2 * intensities[i] + intensities[i - 1]
                d2Sum += d2 * d2
            }
            let avgD2 = d2Sum / Double(intensities.count - 2)
            let maxI = intensities.max() ?? 1
            let normalizedD2 = avgD2 / (maxI * maxI)
            score -= min(normalizedD2 * 100, 0.2)
        }

        // 4. FWHM consistency (typical fluorescence FWHM: 20-100nm)
        let halfMax = (intensities.max() ?? 0) / 2.0
        let fwhm = computeFWHM(wavelengths: wavelengths, intensities: intensities, halfMax: halfMax)
        if fwhm > 0 && (fwhm < 10 || fwhm > 200) {
            score -= 0.15 // Unusual FWHM
        }

        return max(min(score, 1.0), 0.0)
    }

    /// Compute FWHM of the emission band.
    private func computeFWHM(wavelengths: [Double], intensities: [Double], halfMax: Double) -> Double {
        var leftWL: Double?
        var rightWL: Double?

        for i in 0..<intensities.count {
            if intensities[i] >= halfMax && leftWL == nil {
                leftWL = wavelengths[i]
            }
            if leftWL != nil && intensities[i] >= halfMax {
                rightWL = wavelengths[i]
            }
        }

        guard let left = leftWL, let right = rightWL else { return 0 }
        return right - left
    }

    /// Count significant peaks in the emission spectrum.
    private func countSignificantPeaks(intensities: [Double]) -> Int {
        guard intensities.count >= 3 else { return 0 }
        let threshold = (intensities.max() ?? 0) * 0.1
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

    /// Compute spectral asymmetry around the peak.
    private func computeAsymmetry(wavelengths: [Double], intensities: [Double], peakIdx: Int) -> Double {
        guard peakIdx > 0 && peakIdx < intensities.count - 1 else { return 0 }
        let leftHalf = intensities[0..<peakIdx].reduce(0, +)
        let rightHalf = intensities[peakIdx...].reduce(0, +)
        let total = leftHalf + rightHalf
        return total > 0 ? (rightHalf - leftHalf) / total : 0
    }

    /// Analyze emission characteristics for decomposition output.
    private func analyzeEmissionCharacteristics(
        wavelengths: [Double],
        intensities: [Double]
    ) -> [String: [Double]] {
        let maxIdx = intensities.enumerated().max(by: { $0.element < $1.element })?.offset ?? 0
        let halfMax = (intensities.max() ?? 0) / 2.0
        let fwhm = computeFWHM(wavelengths: wavelengths, intensities: intensities, halfMax: halfMax)

        return [
            "Emission Peak": [wavelengths[maxIdx]],
            "FWHM": [fwhm],
            "Asymmetry": [computeAsymmetry(wavelengths: wavelengths, intensities: intensities, peakIdx: maxIdx)]
        ]
    }

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 0.5 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}
