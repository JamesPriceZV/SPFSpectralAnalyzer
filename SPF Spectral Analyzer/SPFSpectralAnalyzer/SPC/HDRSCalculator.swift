import Foundation

// MARK: - ISO 23675:2024 HDRS Calculation Engine

/// Pure calculation engine implementing all ISO 23675:2024 formulas for
/// Hybrid Diffuse Reflectance Spectrophotometry (HDRS) in vitro SPF determination.
enum HDRSCalculator {

    /// Number of wavelength points in the 290–400 nm range at 1 nm intervals.
    private static let wavelengthCount = 111  // 290...400 inclusive

    /// Target wavelength grid for resampling (290–400 nm at 1 nm).
    private static let targetGrid: [Double] = (0...110).map { 290.0 + Double($0) }

    // MARK: - Correction Coefficients (ISO 23675 Table 1)

    /// Returns the correction coefficients (C_Moulded, C_Sandblasted) for the given product type.
    static func correctionCoefficients(
        for productType: HDRSProductType
    ) -> (cMoulded: Double, cSandblasted: Double) {
        (productType.cMoulded, productType.cSandblasted)
    }

    // MARK: - Formula 3: Combined Initial Absorbance

    /// Calculates the combined initial absorbance for one plate pair.
    ///
    /// Formula 3: A_Initial,i(λ) = C_Moulded × min{2.2, A_Moulded(λ)} + C_Sandblasted × min{2.2, A_Sandblasted(λ)}
    ///
    /// Both input arrays must be 111 elements (290–400 nm at 1 nm).
    static func combinedAbsorbance(
        mouldedAbsorbance: [Double],
        sandblastAbsorbance: [Double],
        productType: HDRSProductType
    ) -> [Double] {
        let (cM, cS) = correctionCoefficients(for: productType)
        return zip(mouldedAbsorbance, sandblastAbsorbance).map { aM, aS in
            cM * min(2.2, aM) + cS * min(2.2, aS)
        }
    }

    // MARK: - Formula 4: SPF from Absorbance

    /// Calculates SPF from a combined absorbance spectrum (111 elements, 290–400 nm).
    ///
    /// Formula 4: SPF = ∫E(λ)·I_sol(λ)dλ / ∫E(λ)·I_sol(λ)·10^(-A(λ))dλ
    ///
    /// Uses the CIE erythemal action spectrum (ISO/CIE 17166:2019) and reference solar
    /// spectral irradiance from the existing `CIEErythemalSpectrum` tables.
    static func spfFromAbsorbance(_ absorbance: [Double]) -> Double? {
        guard absorbance.count == wavelengthCount else { return nil }

        var numerator = 0.0
        var denominator = 0.0

        for i in 0..<wavelengthCount {
            let wl = 290.0 + Double(i)
            let e = CIEErythemalSpectrum.erythema(at: wl)
            let s = CIEErythemalSpectrum.solarIrradiance(at: wl)
            let weight = e * s
            let transmittance = pow(10.0, -absorbance[i])
            numerator += weight
            denominator += weight * transmittance
        }

        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    // MARK: - Formula 5: Irradiation Dose

    /// Calculates the irradiation dose for post-irradiation measurement.
    ///
    /// Formula 5: Dx = 0.25 × SPF_pre × 210 (J/m²)
    static func irradiationDose(spfPre: Double) -> Double {
        0.25 * spfPre * 210.0
    }

    // MARK: - Formula 7/8: Final SPF Correction

    /// Applies the nonlinear correction to post-irradiation SPF.
    ///
    /// Formula 7: If SPF_post ≥ 3.5: SPF_final = (√SPF_post − 1.457) / 0.107
    /// Formula 8: If SPF_post < 3.5: SPF_final = SPF_post
    static func finalSPF(spfPost: Double) -> Double {
        if spfPost >= 3.5 {
            return (sqrt(spfPost) - 1.457) / 0.107
        } else {
            return spfPost
        }
    }

    // MARK: - Resampling

    /// Resamples a spectrum to the standard 1 nm grid (290–400 nm) and caps absorbance at 2.2.
    ///
    /// - Parameters:
    ///   - x: Wavelength array from the original spectrum.
    ///   - y: Y-axis values (absorbance or transmittance).
    ///   - yAxisMode: Whether input values are absorbance or transmittance.
    /// - Returns: 111-element absorbance array capped at 2.2, or nil if resampling fails.
    static func resampleTo1nm(
        x: [Double], y: [Double],
        yAxisMode: SpectralYAxisMode
    ) -> [Double]? {
        guard x.count == y.count, x.count > 1 else { return nil }

        // Convert to absorbance if needed
        let absorbance: [Double]
        switch yAxisMode {
        case .absorbance:
            absorbance = y
        case .transmittance:
            absorbance = y.map { -log10(max($0, 1.0e-9)) }
        }

        // Resample onto 1 nm grid
        let resampled = SpectraProcessing.resampleLinear(x: x, y: absorbance, onto: targetGrid)
        guard resampled.count == wavelengthCount else { return nil }

        // Cap at 2.2 per ISO 23675 requirement
        return resampled.map { min(max($0, 0.0), 2.2) }
    }

    // MARK: - Full HDRS Calculation Pipeline

    /// Performs the complete HDRS SPF calculation for one sample.
    ///
    /// - Parameters:
    ///   - pairs: Pre-irradiation plate pairs (moulded + sandblasted, matched by plateIndex).
    ///   - postIrradiationPairs: Optional post-irradiation plate pairs. If provided,
    ///     the final SPF uses post-irradiation measurements with the Formula 7/8 correction.
    ///   - productType: The product formulation type (emulsion or alcoholic).
    /// - Returns: An `HDRSResult` with per-pair results, mean SPF, SD, and 95% CI validation.
    static func calculate(
        pairs: [HDRSPlatePair],
        postIrradiationPairs: [HDRSPlatePair]?,
        productType: HDRSProductType
    ) -> HDRSResult? {
        guard !pairs.isEmpty else { return nil }

        var pairResults: [HDRSPairResult] = []

        for pair in pairs {
            // Formula 3: Combined initial absorbance
            let combined = combinedAbsorbance(
                mouldedAbsorbance: pair.mouldedAbsorbance,
                sandblastAbsorbance: pair.sandblastAbsorbance,
                productType: productType
            )

            // Formula 4: Pre-irradiation SPF
            guard let spfPre = spfFromAbsorbance(combined) else { continue }

            // Formula 5: Irradiation dose
            let dose = irradiationDose(spfPre: spfPre)

            // Post-irradiation calculation (if available)
            var spfPost: Double? = nil
            var spfFinal = spfPre  // Default: pre-irradiation SPF if no post data

            if let postPairs = postIrradiationPairs,
               let postPair = postPairs.first(where: { $0.plateIndex == pair.plateIndex }) {
                let combinedPost = combinedAbsorbance(
                    mouldedAbsorbance: postPair.mouldedAbsorbance,
                    sandblastAbsorbance: postPair.sandblastAbsorbance,
                    productType: productType
                )
                if let spfPostVal = spfFromAbsorbance(combinedPost) {
                    spfPost = spfPostVal
                    // Formula 7/8: Final correction
                    spfFinal = finalSPF(spfPost: spfPostVal)
                }
            }

            pairResults.append(HDRSPairResult(
                plateIndex: pair.plateIndex,
                combinedAbsorbance: combined,
                spfPre: spfPre,
                irradiationDose: dose,
                spfPost: spfPost,
                spfFinal: spfFinal
            ))
        }

        guard !pairResults.isEmpty else { return nil }

        let finals = pairResults.map(\.spfFinal)
        let n = Double(finals.count)
        let mean = finals.reduce(0.0, +) / n

        // Standard deviation (sample SD, n-1 denominator)
        let variance: Double
        if finals.count > 1 {
            variance = finals.map { pow($0 - mean, 2) }.reduce(0.0, +) / (n - 1.0)
        } else {
            variance = 0.0
        }
        let sd = sqrt(variance)

        // 95% CI = t(α/2, n-1) × SD / √n
        // t-values for common degrees of freedom
        let ci: Double
        let ciPercent: Double
        if finals.count > 1 {
            let tValue = tCritical(degreesOfFreedom: finals.count - 1)
            ci = tValue * sd / sqrt(n)
            ciPercent = mean > 0 ? (ci / mean) * 100.0 : 0.0
        } else {
            ci = 0.0
            ciPercent = 0.0
        }

        var warnings: [String] = []
        if ciPercent > 17.0 {
            warnings.append(String(format: "95%% CI (%.1f%%) exceeds ISO 23675 limit of 17%%", ciPercent))
        }
        if pairResults.count < 3 {
            warnings.append("ISO 23675 requires at least 3 plate pairs; only \(pairResults.count) provided")
        }

        return HDRSResult(
            sampleName: "",  // Caller fills in the sample name
            productType: productType,
            pairResults: pairResults,
            meanSPF: mean,
            standardDeviation: sd,
            confidenceInterval95Percent: ciPercent,
            isValid: ciPercent <= 17.0 && pairResults.count >= 3,
            warnings: warnings
        )
    }

    // MARK: - Spectral Correlation (Part 2: Baseline Matching)

    /// Calculates the Pearson correlation coefficient between two equal-length arrays.
    static func pearsonCorrelation(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0.0 }
        let n = Double(a.count)
        let meanA = a.reduce(0.0, +) / n
        let meanB = b.reduce(0.0, +) / n

        var numerator = 0.0
        var denomA = 0.0
        var denomB = 0.0
        for i in 0..<a.count {
            let da = a[i] - meanA
            let db = b[i] - meanB
            numerator += da * db
            denomA += da * da
            denomB += db * db
        }

        let denom = sqrt(denomA * denomB)
        return denom > 0 ? numerator / denom : 0.0
    }

    /// Finds the reference spectrum with the highest spectral correlation
    /// to the given analysis spectrum.
    ///
    /// - Parameters:
    ///   - analysisX: Wavelength array of the analysis spectrum.
    ///   - analysisY: Y-values of the analysis spectrum.
    ///   - references: Array of reference spectra (x, y tuples).
    ///   - yAxisMode: Whether values are absorbance or transmittance.
    /// - Returns: Index of the best-matching reference, or nil if no valid match found.
    static func bestReferenceMatch(
        analysisX: [Double], analysisY: [Double],
        references: [(x: [Double], y: [Double])],
        yAxisMode: SpectralYAxisMode
    ) -> Int? {
        guard !references.isEmpty else { return nil }

        guard let analysisResampled = resampleTo1nm(
            x: analysisX, y: analysisY, yAxisMode: yAxisMode
        ) else { return nil }

        var bestIndex: Int?
        var bestCorrelation = -Double.infinity

        for (i, ref) in references.enumerated() {
            guard let refResampled = resampleTo1nm(
                x: ref.x, y: ref.y, yAxisMode: yAxisMode
            ) else { continue }

            let corr = pearsonCorrelation(analysisResampled, refResampled)
            if corr > bestCorrelation {
                bestCorrelation = corr
                bestIndex = i
            }
        }

        return bestIndex
    }

    /// Averages multiple absorbance spectra (all must be 111 elements).
    /// Returns nil if input is empty or contains mismatched lengths.
    static func averageAbsorbance(_ spectra: [[Double]]) -> [Double]? {
        guard !spectra.isEmpty else { return nil }
        guard spectra.allSatisfy({ $0.count == wavelengthCount }) else { return nil }

        var avg = [Double](repeating: 0.0, count: wavelengthCount)
        for spectrum in spectra {
            for i in 0..<wavelengthCount {
                avg[i] += spectrum[i]
            }
        }
        let n = Double(spectra.count)
        return avg.map { $0 / n }
    }

    // MARK: - Statistical Helpers

    /// Returns the two-tailed t-critical value for 95% confidence at the given degrees of freedom.
    private static func tCritical(degreesOfFreedom df: Int) -> Double {
        // Pre-computed t(0.025, df) values for common sample sizes
        let table: [Int: Double] = [
            1: 12.706,
            2: 4.303,
            3: 3.182,
            4: 2.776,
            5: 2.571,
            6: 2.447,
            7: 2.365,
            8: 2.306,
            9: 2.262,
            10: 2.228,
            15: 2.131,
            20: 2.086,
            30: 2.042
        ]

        if let exact = table[df] { return exact }

        // Interpolate or use closest lower bound
        let sortedKeys = table.keys.sorted()
        for i in 1..<sortedKeys.count {
            if df > sortedKeys[i - 1] && df < sortedKeys[i] {
                let lower = table[sortedKeys[i - 1]]!
                let upper = table[sortedKeys[i]]!
                let fraction = Double(df - sortedKeys[i - 1]) / Double(sortedKeys[i] - sortedKeys[i - 1])
                return lower + (upper - lower) * fraction
            }
        }

        // Fallback for large df: approximate with 1.96 (z-value)
        return 1.96
    }
}
