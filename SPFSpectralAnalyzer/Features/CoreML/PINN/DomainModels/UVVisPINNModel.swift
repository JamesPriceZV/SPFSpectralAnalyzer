import Foundation
import CoreML

/// Physics-Informed Neural Network model for UV-Vis spectroscopy.
///
/// Embeds Beer-Lambert law (A = εcl), the SPF Diffey integral, spectral smoothness,
/// and concentration non-negativity as physics constraints in the training loss.
///
/// Architecture: 4-layer MLP (256-128-128-64), Tanh activation, ReLoBRaLo loss balancing.
///
/// References:
/// - Diffey & Robson (1989) — SPF integral formulation
/// - COLIPA 2011 — in vitro SPF method
/// - ISO 24443:2021 — UVA protection measurement
final class UVVisPINNModel: @unchecked Sendable, PINNDomainModel {

    let domain: PINNDomain = .uvVis

    private(set) var status: PINNModelStatus = .notTrained

    var modelDescription: String {
        "UV-Vis PINN with Beer-Lambert + SPF Diffey integral physics constraints"
    }

    var physicsConstraints: [String] {
        [
            "Beer-Lambert: A(λ) = Σ εᵢ(λ)·cᵢ·l",
            "SPF integral: SPF = ∫[E(λ)·S(λ)] / ∫[E(λ)·S(λ)·10^(-A(λ))]",
            "Spectral smoothness: ‖∂²A/∂λ²‖² penalty",
            "Concentration non-negativity: cᵢ ≥ 0"
        ]
    }

    // MARK: - Private State

    /// The compiled CoreML PINN model.
    nonisolated(unsafe) private var model: MLModel?

    /// Conformal prediction residuals from calibration split.
    nonisolated(unsafe) private var conformalResiduals: [Double] = []

    /// Model file name for this domain.
    static let modelName = "PINN_UVVis"

    // MARK: - Model Loading

    func loadModel() async throws {
        status = .loading

        let fm = FileManager.default

        // 1. App Support
        let appSupportURL = PINNModelRegistry.modelDirectory
            .appendingPathComponent("\(Self.modelName).mlmodelc")
        if fm.fileExists(atPath: appSupportURL.path) {
            try loadFromURL(appSupportURL)
            return
        }

        // 2. iCloud
        if let iCloudDir = PINNModelRegistry.iCloudModelDirectory {
            let iCloudURL = iCloudDir.appendingPathComponent("\(Self.modelName).mlmodelc")
            if fm.fileExists(atPath: iCloudURL.path) {
                try loadFromURL(iCloudURL)
                return
            }
            // Trigger download if available
            try? fm.startDownloadingUbiquitousItem(at: iCloudURL)
        }

        // 3. Bundle fallback
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
        status = .ready
    }

    private func loadConformalResiduals() {
        let residualsURL = PINNModelRegistry.modelDirectory
            .appendingPathComponent("\(Self.modelName)_calibration.json")
        guard FileManager.default.fileExists(atPath: residualsURL.path),
              let data = try? Data(contentsOf: residualsURL),
              let residuals = try? JSONDecoder().decode([Double].self, from: data) else {
            return
        }
        conformalResiduals = residuals.sorted()
    }

    // MARK: - Prediction

    func predict(
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata
    ) -> PINNPredictionResult? {
        guard status.isReady, let model else { return nil }
        guard wavelengths.count == intensities.count, wavelengths.count >= 2 else { return nil }

        // Preprocessing: resample to 290-400nm at 1nm (111 points)
        let resampled = resampleToUVRange(wavelengths: wavelengths, intensities: intensities)
        guard resampled.count == 111 else { return nil }

        // Build feature dictionary
        var featureDict: [String: MLFeatureValue] = [:]

        // Spectral features
        for i in 0..<111 {
            featureDict["abs_\(290 + i)"] = MLFeatureValue(double: resampled[i])
        }

        // Derived metrics
        let metrics = computeSpectralMetrics(resampled: resampled)
        featureDict["critical_wavelength"] = MLFeatureValue(double: metrics.criticalWavelength)
        featureDict["uva_uvb_ratio"] = MLFeatureValue(double: metrics.uvaUvbRatio)
        featureDict["uvb_area"] = MLFeatureValue(double: metrics.uvbArea)
        featureDict["uva_area"] = MLFeatureValue(double: metrics.uvaArea)
        featureDict["mean_uvb_transmittance"] = MLFeatureValue(double: metrics.meanUVBTransmittance)
        featureDict["mean_uva_transmittance"] = MLFeatureValue(double: metrics.meanUVATransmittance)
        featureDict["peak_absorbance_wavelength"] = MLFeatureValue(double: metrics.peakWavelength)

        // Auxiliary features
        let plateValue: Double = (metadata.plateType == .pmma) ? 0 : (metadata.plateType == .quartz ? 1 : 2)
        featureDict["plate_type"] = MLFeatureValue(double: plateValue)
        featureDict["application_quantity_mg"] = MLFeatureValue(double: metadata.applicationQuantityMg ?? 15.0)
        featureDict["formulation_type"] = MLFeatureValue(double: Double(metadata.formulationType?.featureValue ?? 3))
        featureDict["is_post_irradiation"] = MLFeatureValue(double: metadata.isPostIrradiation ? 1.0 : 0.0)

        do {
            let provider = try MLDictionaryFeatureProvider(dictionary: featureDict)
            let prediction = try model.prediction(from: provider)
            guard let spfValue = prediction.featureValue(for: "spf")?.doubleValue else { return nil }

            let spf = max(spfValue, 1.0)
            let q90 = conformalQuantile(level: 0.9)
            let physicsScore = computePhysicsConsistency(resampled: resampled, predictedSPF: spf)

            return PINNPredictionResult(
                primaryValue: spf,
                primaryLabel: "SPF",
                confidenceLow: max(spf - q90, 1.0),
                confidenceHigh: spf + q90,
                decomposition: nil,
                physicsConsistencyScore: physicsScore,
                domain: .uvVis
            )
        } catch {
            return nil
        }
    }

    // MARK: - Preprocessing

    /// Resample spectral data to 290-400nm at 1nm intervals via linear interpolation.
    private func resampleToUVRange(wavelengths: [Double], intensities: [Double]) -> [Double] {
        var result: [Double] = []
        result.reserveCapacity(111)

        for target in 290...400 {
            let targetWL = Double(target)
            // Find surrounding points for interpolation
            var lowerIdx = 0
            for i in 0..<wavelengths.count - 1 {
                if wavelengths[i] <= targetWL && wavelengths[i + 1] >= targetWL {
                    lowerIdx = i
                    break
                }
                if wavelengths[i] >= targetWL {
                    lowerIdx = max(i - 1, 0)
                    break
                }
            }

            let upperIdx = min(lowerIdx + 1, wavelengths.count - 1)

            if lowerIdx == upperIdx || wavelengths[lowerIdx] == wavelengths[upperIdx] {
                result.append(intensities[lowerIdx])
            } else {
                let fraction = (targetWL - wavelengths[lowerIdx]) / (wavelengths[upperIdx] - wavelengths[lowerIdx])
                let interpolated = intensities[lowerIdx] + fraction * (intensities[upperIdx] - intensities[lowerIdx])
                result.append(interpolated)
            }
        }

        return result
    }

    // MARK: - Physics Consistency

    /// Score how well the prediction satisfies embedded physics constraints.
    /// Returns 0-1 where 1 means perfect physics consistency.
    private func computePhysicsConsistency(resampled: [Double], predictedSPF: Double) -> Double {
        var score = 1.0

        // 1. SPF integral consistency: compare predicted SPF with Diffey integral from spectrum
        let diffeyIntegral = computeDiffeyIntegral(absorbances: resampled)
        if diffeyIntegral > 0 {
            let ratio = predictedSPF / diffeyIntegral
            // Penalize large deviations from integral-based SPF
            let deviation = abs(ratio - 1.0)
            score -= min(deviation * 0.5, 0.3) // Max 0.3 penalty
        }

        // 2. Spectral smoothness: penalize noisy spectra
        let smoothnessScore = computeSmoothnessScore(absorbances: resampled)
        score -= (1.0 - smoothnessScore) * 0.2 // Max 0.2 penalty

        // 3. Non-negativity: absorbance should be ≥ 0
        let negativeCount = resampled.filter { $0 < -0.01 }.count
        let negFraction = Double(negativeCount) / Double(resampled.count)
        score -= negFraction * 0.5 // Penalty proportional to negative fraction

        return max(min(score, 1.0), 0.0)
    }

    /// Compute the Diffey SPF integral from absorbance values.
    /// SPF = ∫E(λ)·S(λ)dλ / ∫E(λ)·S(λ)·10^(-A(λ))dλ
    private func computeDiffeyIntegral(absorbances: [Double]) -> Double {
        // CIE erythemal action spectrum (simplified, key values 290-400nm)
        // Using McKinlay-Diffey (1987) approximation
        var numerator = 0.0
        var denominator = 0.0

        for i in 0..<min(absorbances.count, 111) {
            let wavelength = Double(290 + i)
            let erythemalWeight = erythemalActionSpectrum(wavelength: wavelength)
            let solarIrradiance = solarSpectrum(wavelength: wavelength)

            let weight = erythemalWeight * solarIrradiance
            numerator += weight
            denominator += weight * pow(10.0, -absorbances[i])
        }

        return denominator > 0 ? numerator / denominator : 0
    }

    /// CIE erythemal action spectrum (McKinlay & Diffey, 1987).
    private func erythemalActionSpectrum(wavelength: Double) -> Double {
        if wavelength <= 298 {
            return 1.0
        } else if wavelength <= 328 {
            return pow(10.0, 0.094 * (298.0 - wavelength))
        } else if wavelength <= 400 {
            return pow(10.0, 0.015 * (139.0 - wavelength))
        }
        return 0.0
    }

    /// Simplified solar irradiance (relative, normalized).
    private func solarSpectrum(wavelength: Double) -> Double {
        // Simplified spectral irradiance for 290-400nm range
        if wavelength < 295 { return 0.01 }
        if wavelength < 300 { return 0.05 + (wavelength - 295) * 0.03 }
        if wavelength < 320 { return 0.2 + (wavelength - 300) * 0.015 }
        return 0.5 + (wavelength - 320) * 0.005
    }

    /// Smoothness score based on second derivative magnitude.
    private func computeSmoothnessScore(absorbances: [Double]) -> Double {
        guard absorbances.count >= 3 else { return 1.0 }
        var totalSecondDeriv = 0.0
        for i in 1..<absorbances.count - 1 {
            let d2 = absorbances[i + 1] - 2 * absorbances[i] + absorbances[i - 1]
            totalSecondDeriv += d2 * d2
        }
        let avgSecondDeriv = totalSecondDeriv / Double(absorbances.count - 2)
        // Empirical threshold: score = 1 when avg < 0.001, score = 0 when avg > 0.1
        return max(1.0 - avgSecondDeriv * 10.0, 0.0)
    }

    // MARK: - Conformal Intervals

    private func conformalQuantile(level: Double) -> Double {
        guard !conformalResiduals.isEmpty else { return 5.0 }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1,
                        conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }

    // MARK: - Spectral Metrics

    private struct SpectralMetrics {
        let criticalWavelength: Double
        let uvaUvbRatio: Double
        let uvbArea: Double
        let uvaArea: Double
        let meanUVBTransmittance: Double
        let meanUVATransmittance: Double
        let peakWavelength: Double
    }

    /// Compute derived spectral metrics matching SPFModelSchema.
    private func computeSpectralMetrics(resampled: [Double]) -> SpectralMetrics {
        // UVB range: 290-320nm (indices 0-30)
        // UVA range: 320-400nm (indices 30-110)
        let uvbAbsorbances = Array(resampled[0..<min(31, resampled.count)])
        let uvaAbsorbances = resampled.count > 30 ? Array(resampled[30...]) : []

        let uvbArea = uvbAbsorbances.reduce(0, +)
        let uvaArea = uvaAbsorbances.reduce(0, +)
        let uvaUvbRatio = uvbArea > 0 ? uvaArea / uvbArea : 0

        // Mean transmittance
        let meanUVBTransmittance = uvbAbsorbances.isEmpty ? 0 :
            uvbAbsorbances.map { pow(10.0, -$0) }.reduce(0, +) / Double(uvbAbsorbances.count)
        let meanUVATransmittance = uvaAbsorbances.isEmpty ? 0 :
            uvaAbsorbances.map { pow(10.0, -$0) }.reduce(0, +) / Double(uvaAbsorbances.count)

        // Peak wavelength
        var peakIdx = 0
        var peakVal = -Double.infinity
        for (i, v) in resampled.enumerated() {
            if v > peakVal { peakVal = v; peakIdx = i }
        }
        let peakWavelength = Double(290 + peakIdx)

        // Critical wavelength: where 90% of total absorbance integral is reached
        let totalArea = resampled.reduce(0, +)
        var cumulativeArea = 0.0
        var criticalWavelength = 400.0
        for (i, v) in resampled.enumerated() {
            cumulativeArea += v
            if cumulativeArea >= 0.9 * totalArea {
                criticalWavelength = Double(290 + i)
                break
            }
        }

        return SpectralMetrics(
            criticalWavelength: criticalWavelength,
            uvaUvbRatio: uvaUvbRatio,
            uvbArea: uvbArea,
            uvaArea: uvaArea,
            meanUVBTransmittance: meanUVBTransmittance,
            meanUVATransmittance: meanUVATransmittance,
            peakWavelength: peakWavelength
        )
    }
}
