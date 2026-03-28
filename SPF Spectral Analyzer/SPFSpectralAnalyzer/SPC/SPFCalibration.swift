import Foundation

struct CalibrationSample: Sendable {
    let name: String
    let labelSPF: Double
    let metrics: SpectralMetrics
    let rawInVitroSPF: Double?
    /// Resampled absorbance curve at 1 nm intervals, 290-400 nm (111 points).
    /// Used for spectral cosine similarity matching.
    let resampledAbsorbance: [Double]?

    nonisolated init(name: String = "", labelSPF: Double, metrics: SpectralMetrics, rawInVitroSPF: Double? = nil,
                     resampledAbsorbance: [Double]? = nil) {
        self.name = name
        self.labelSPF = labelSPF
        self.metrics = metrics
        self.rawInVitroSPF = rawInVitroSPF
        self.resampledAbsorbance = resampledAbsorbance
    }
}

/// Result of finding the reference spectrum whose spectral profile most closely
/// matches a given sample.
struct NearestReferenceMatch: Sendable {
    let matchedReferenceName: String      // display name of best-match reference
    let matchedReferenceSPF: Double       // known in-vivo SPF of best-match reference
    let matchedReferenceRawSPF: Double    // raw in-vitro SPF of best-match reference
    let estimatedSPF: Double              // C-coefficient calibrated estimate
    let distance: Double                  // 1 - cosine similarity (0 = perfect match)
    let cCoefficient: Double?             // ISO 24443 C-coefficient used for estimation
    let sampleCount: Int                  // total reference spectra considered
}

struct CalibrationResult: Sendable {
    let coefficients: [Double]
    let r2: Double
    let rmse: Double
    let sampleCount: Int
    let featureNames: [String]

    func predict(metrics: SpectralMetrics) -> Double {
        let features = [
            1.0,
            metrics.uvbArea,
            metrics.uvaArea,
            metrics.criticalWavelength,
            metrics.uvaUvbRatio,
            metrics.meanUVBTransmittance,
            metrics.meanUVATransmittance,
            metrics.peakAbsorbanceWavelength
        ]
        let logSpf = zip(coefficients, features).map(*).reduce(0, +)
        return max(exp(logSpf), 0.0)
    }
}

nonisolated struct SPFCalibration {

    // MARK: - Nearest-Reference Matching (Spectral Cosine Similarity + ISO 24443 C-Coefficient)

    /// Finds the reference spectrum whose full 290-400 nm absorbance curve is
    /// most similar to the sample (cosine similarity on 111-point resampled
    /// curves).  Falls back to 8-D feature-vector Euclidean distance when
    /// resampled curves are unavailable.
    ///
    /// SPF is estimated using the ISO 24443 C-coefficient approach:
    ///   1. Solve for C on the reference: find C such that
    ///      `SPF_in_vitro(C · A_ref) = labelSPF`.
    ///   2. Apply C to the sample: `SPF_estimated = SPF_in_vitro(C · A_sample)`.
    ///
    /// Falls back to proportional scaling if the C-coefficient solve fails or
    /// resampled data is unavailable.
    static func findNearestMatch(
        sampleMetrics: SpectralMetrics,
        sampleRawSPF: Double,
        sampleResampledAbsorbance: [Double]? = nil,
        references: [CalibrationSample]
    ) -> NearestReferenceMatch? {
        let eligible = references.filter { $0.rawInVitroSPF != nil && $0.rawInVitroSPF! > 0 }
        guard !eligible.isEmpty else { return nil }

        // Try spectral cosine similarity first (preferred)
        let useCosineSimilarity = sampleResampledAbsorbance != nil
            && eligible.contains(where: { $0.resampledAbsorbance != nil })

        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

        if useCosineSimilarity, let sampleCurve = sampleResampledAbsorbance {
            for (idx, ref) in eligible.enumerated() {
                guard let refCurve = ref.resampledAbsorbance,
                      refCurve.count == sampleCurve.count else { continue }
                let similarity = cosineSimilarity(sampleCurve, refCurve)
                let dist = 1.0 - similarity  // 0 = identical shape
                if dist < bestDistance {
                    bestDistance = dist
                    bestIndex = idx
                }
            }
        } else {
            // Fallback: normalized Euclidean distance on feature vectors
            let featureVectors = eligible.map { featureVector(for: $0.metrics, rawSPF: $0.rawInVitroSPF!) }
            let sampleFeatures = featureVector(for: sampleMetrics, rawSPF: sampleRawSPF)

            var mins = sampleFeatures
            var maxs = sampleFeatures
            for fv in featureVectors {
                for i in 0..<fv.count {
                    mins[i] = min(mins[i], fv[i])
                    maxs[i] = max(maxs[i], fv[i])
                }
            }

            for (idx, fv) in featureVectors.enumerated() {
                var sumSq = 0.0
                for i in 0..<fv.count {
                    let range = maxs[i] - mins[i]
                    if range < 1.0e-12 { continue }
                    let normSample = (sampleFeatures[i] - mins[i]) / range
                    let normRef = (fv[i] - mins[i]) / range
                    sumSq += pow(normSample - normRef, 2)
                }
                let dist = sqrt(sumSq)
                if dist < bestDistance {
                    bestDistance = dist
                    bestIndex = idx
                }
            }
        }

        let best = eligible[bestIndex]
        let refRaw = best.rawInVitroSPF!

        // Try ISO 24443 C-coefficient calibration
        var estimatedSPF: Double
        var cCoefficient: Double? = nil

        if let refCurve = best.resampledAbsorbance,
           let sampleCurve = sampleResampledAbsorbance,
           refCurve.count == sampleCurve.count {
            // Solve for C on the reference: SPF_in_vitro(C · A_ref) = labelSPF
            if let cValue = solveCCoefficient(absorbance: refCurve, targetSPF: best.labelSPF) {
                // Apply C to the sample
                let scaledSampleAbs = sampleCurve.map { $0 * cValue }
                estimatedSPF = computeSPFFromAbsorbanceCurve(scaledSampleAbs)
                cCoefficient = cValue
            } else {
                // C-coefficient solve failed; fall back to proportional scaling
                estimatedSPF = best.labelSPF * (sampleRawSPF / refRaw)
            }
        } else {
            // No resampled data; proportional scaling
            estimatedSPF = best.labelSPF * (sampleRawSPF / refRaw)
        }

        return NearestReferenceMatch(
            matchedReferenceName: best.name,
            matchedReferenceSPF: best.labelSPF,
            matchedReferenceRawSPF: refRaw,
            estimatedSPF: max(estimatedSPF, 0.0),
            distance: bestDistance,
            cCoefficient: cCoefficient,
            sampleCount: eligible.count
        )
    }

    // MARK: - Spectral Cosine Similarity

    /// Cosine similarity between two absorbance curves.
    /// Returns a value in [0, 1] where 1 = identical spectral shape.
    private static func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        let denom = sqrt(normA) * sqrt(normB)
        guard denom > 1.0e-12 else { return 0 }
        return max(min(dotProduct / denom, 1.0), 0.0)
    }

    // MARK: - ISO 24443 C-Coefficient Solver

    /// Iteratively solves for C such that SPF_in_vitro(C · A(λ)) = targetSPF.
    /// The absorbance array is assumed to be 290-400 nm at 1 nm intervals (111 points).
    /// Returns C in the valid range [0.1, 5.0], or nil if convergence fails.
    /// The wider range accommodates higher-SPF products where the C-coefficient
    /// needed to bridge raw in-vitro to label SPF can be large.
    private static func solveCCoefficient(absorbance: [Double], targetSPF: Double) -> Double? {
        guard absorbance.count == 111, targetSPF > 0 else { return nil }

        // Binary search for C in [0.1, 5.0]
        var lo = 0.1
        var hi = 5.0

        let spfAtLo = computeSPFFromAbsorbanceCurve(absorbance.map { $0 * lo })
        let spfAtHi = computeSPFFromAbsorbanceCurve(absorbance.map { $0 * hi })

        // Check that the target is bracketed
        guard spfAtLo <= targetSPF || spfAtHi >= targetSPF else { return nil }

        for _ in 0..<50 {  // max 50 iterations for convergence
            let mid = (lo + hi) / 2.0
            let spfAtMid = computeSPFFromAbsorbanceCurve(absorbance.map { $0 * mid })

            if abs(spfAtMid - targetSPF) < 0.01 {
                return mid
            }

            if spfAtMid < targetSPF {
                lo = mid
            } else {
                hi = mid
            }

            if hi - lo < 1.0e-6 { break }
        }

        let finalC = (lo + hi) / 2.0
        let finalSPF = computeSPFFromAbsorbanceCurve(absorbance.map { $0 * finalC })
        // Accept if within 5% of target
        return abs(finalSPF - targetSPF) / targetSPF < 0.05 ? finalC : nil
    }

    /// Computes SPF from a 290-400 nm absorbance curve (111 points at 1 nm intervals)
    /// using the COLIPA/ISO formula: SPF = ∫E(λ)·I(λ)dλ / ∫E(λ)·I(λ)·10^(-A(λ))dλ.
    /// Absorbance values are capped at 2.2 per ISO 23675 to avoid non-linear artifacts.
    static func computeSPFFromAbsorbanceCurve(_ absorbance: [Double]) -> Double {
        guard absorbance.count == 111 else { return 0 }
        var numerator = 0.0
        var denominator = 0.0
        for i in 0..<111 {
            let wavelength = Double(290 + i)
            let erythema = CIEErythemalSpectrum.erythema(at: wavelength)
            let solar = CIEErythemalSpectrum.solarIrradiance(at: wavelength)
            let weight = erythema * solar
            let cappedAbs = min(absorbance[i], 2.2)  // ISO 23675 absorbance cap
            let transmittance = max(pow(10.0, -cappedAbs), 0.0)
            numerator += weight
            denominator += weight * transmittance
        }
        guard denominator > 0 else { return 0 }
        return numerator / denominator
    }

    /// Resamples a spectrum to 1 nm intervals from 290-400 nm (111 points).
    /// Returns nil if the spectrum doesn't cover the required range.
    static func resampleAbsorbance(x: [Double], y: [Double], yAxisMode: SpectralYAxisMode) -> [Double]? {
        let count = min(x.count, y.count)
        guard count > 2 else { return nil }

        var xValues = Array(x.prefix(count))
        var yValues = Array(y.prefix(count))
        if let first = xValues.first, let last = xValues.last, first > last {
            xValues.reverse()
            yValues.reverse()
        }

        let absorbance: [Double]
        switch yAxisMode {
        case .absorbance:
            absorbance = yValues
        case .transmittance:
            absorbance = yValues.map { t in
                let clamped = max(t, 1.0e-10)
                return -log10(clamped)
            }
        }

        guard let firstX = xValues.first, let lastX = xValues.last,
              firstX <= 290.0, lastX >= 400.0 else { return nil }

        var result = [Double]()
        result.reserveCapacity(111)
        for wl in 290...400 {
            let wavelength = Double(wl)
            var found = false
            for i in 1..<xValues.count {
                let x0 = xValues[i - 1]
                let x1 = xValues[i]
                if wavelength >= x0 && wavelength <= x1 {
                    let t = (wavelength - x0) / (x1 - x0)
                    result.append(absorbance[i - 1] + (absorbance[i] - absorbance[i - 1]) * t)
                    found = true
                    break
                }
            }
            if !found { return nil }
        }
        return result
    }

    private static func featureVector(for m: SpectralMetrics, rawSPF: Double) -> [Double] {
        [m.uvbArea, m.uvaArea, m.criticalWavelength, m.uvaUvbRatio,
         m.meanUVBTransmittance, m.meanUVATransmittance, m.peakAbsorbanceWavelength, rawSPF]
    }

    // MARK: - OLS Calibration

    static func build(samples: [CalibrationSample]) -> CalibrationResult? {
        guard samples.count >= 2 else { return nil }

        let featureNames = [
            "Intercept",
            "UVB Area",
            "UVA Area",
            "Critical WL",
            "UVA/UVB",
            "Mean UVB T",
            "Mean UVA T",
            "Peak λ"
        ]

        let x = samples.map { sample in
            [
                1.0,
                sample.metrics.uvbArea,
                sample.metrics.uvaArea,
                sample.metrics.criticalWavelength,
                sample.metrics.uvaUvbRatio,
                sample.metrics.meanUVBTransmittance,
                sample.metrics.meanUVATransmittance,
                sample.metrics.peakAbsorbanceWavelength
            ]
        }
        let y = samples.map { log(max($0.labelSPF, 1.0e-6)) }

        guard let coefficients = solveLeastSquares(x: x, y: y) else { return nil }

        let predictions = x.map { row in
            let logSpf = zip(coefficients, row).map(*).reduce(0, +)
            return exp(logSpf)
        }

        let r2 = rSquared(actual: samples.map { $0.labelSPF }, predicted: predictions)
        let rmse = rootMeanSquaredError(actual: samples.map { $0.labelSPF }, predicted: predictions)

        return CalibrationResult(
            coefficients: coefficients,
            r2: r2,
            rmse: rmse,
            sampleCount: samples.count,
            featureNames: featureNames
        )
    }

    private static func solveLeastSquares(x: [[Double]], y: [Double]) -> [Double]? {
        guard let xT = transpose(x) else { return nil }
        let xTx = multiply(xT, x)
        guard let xTxInv = invert(xTx) else { return nil }
        let xTy = multiply(xT, y)
        let coeffs = multiply(xTxInv, xTy)
        return coeffs
    }

    private static func transpose(_ m: [[Double]]) -> [[Double]]? {
        guard let first = m.first else { return nil }
        var result = Array(repeating: Array(repeating: 0.0, count: m.count), count: first.count)
        for i in 0..<m.count {
            for j in 0..<first.count {
                result[j][i] = m[i][j]
            }
        }
        return result
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rows = a.count
        let cols = b.first?.count ?? 0
        let inner = b.count
        var result = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        for i in 0..<rows {
            for k in 0..<inner {
                let aik = a[i][k]
                if abs(aik) < 1.0e-12 { continue }
                for j in 0..<cols {
                    result[i][j] += aik * b[k][j]
                }
            }
        }
        return result
    }

    private static func multiply(_ a: [[Double]], _ b: [Double]) -> [Double] {
        let rows = a.count
        let cols = a.first?.count ?? 0
        var result = Array(repeating: 0.0, count: rows)
        for i in 0..<rows {
            var sum = 0.0
            for j in 0..<cols {
                sum += a[i][j] * b[j]
            }
            result[i] = sum
        }
        return result
    }

    private static func invert(_ matrix: [[Double]]) -> [[Double]]? {
        let n = matrix.count
        guard n > 0 && matrix[0].count == n else { return nil }

        var a = matrix
        var inv = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { inv[i][i] = 1.0 }

        for i in 0..<n {
            var maxRow = i
            var maxVal = abs(a[i][i])
            for row in (i + 1)..<n {
                if abs(a[row][i]) > maxVal {
                    maxVal = abs(a[row][i])
                    maxRow = row
                }
            }

            if maxVal < 1.0e-12 { return nil }
            if maxRow != i {
                a.swapAt(i, maxRow)
                inv.swapAt(i, maxRow)
            }

            let pivot = a[i][i]
            for col in 0..<n {
                a[i][col] /= pivot
                inv[i][col] /= pivot
            }

            for row in 0..<n where row != i {
                let factor = a[row][i]
                if abs(factor) < 1.0e-12 { continue }
                for col in 0..<n {
                    a[row][col] -= factor * a[i][col]
                    inv[row][col] -= factor * inv[i][col]
                }
            }
        }

        return inv
    }

    private static func rSquared(actual: [Double], predicted: [Double]) -> Double {
        guard actual.count == predicted.count, actual.count > 1 else { return 0 }
        let mean = actual.reduce(0, +) / Double(actual.count)
        var ssTot = 0.0
        var ssRes = 0.0
        for i in 0..<actual.count {
            ssTot += pow(actual[i] - mean, 2)
            ssRes += pow(actual[i] - predicted[i], 2)
        }
        return ssTot == 0 ? 0 : (1.0 - ssRes / ssTot)
    }

    private static func rootMeanSquaredError(actual: [Double], predicted: [Double]) -> Double {
        guard actual.count == predicted.count, !actual.isEmpty else { return 0 }
        let mse = zip(actual, predicted).map { pow($0 - $1, 2) }.reduce(0, +) / Double(actual.count)
        return sqrt(mse)
    }
}
