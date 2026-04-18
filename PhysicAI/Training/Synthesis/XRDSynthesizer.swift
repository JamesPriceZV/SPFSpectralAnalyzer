import Foundation

actor XRDSynthesizer {

    struct DiffractionPeak: Sendable {
        let dSpacing: Double
        let relIntensity: Double
    }

    private let lambda = 1.5406  // Cu Ka1
    private let twoThetaGrid = stride(from: 5.0, through: 89.95, by: 0.1).map { $0 }

    // MARK: - Cromer-Mann Coefficients

    /// Cromer-Mann analytical approximation coefficients for atomic form factors.
    /// Each entry: [a1, b1, a2, b2, a3, b3, a4, b4, c]
    /// f(s) = sum_i a_i * exp(-b_i * s^2) + c,  where s = sin(theta)/lambda
    private static let cromerMann: [String: [Double]] = [
        "H":  [0.489, 20.659, 0.262, 7.740, 0.196, 49.552, 0.049, 2.201, 0.001],
        "C":  [2.310, 20.844, 1.020, 10.208, 1.589, 0.569, 0.865, 51.651, 0.216],
        "N":  [12.213, 0.006, 3.132, 9.893, 2.013, 28.997, 1.166, 0.583, -11.529],
        "O":  [3.049, 13.277, 2.287, 5.701, 1.546, 0.324, 0.867, 32.909, 0.251],
        "Si": [6.292, 2.439, 3.035, 32.334, 1.989, 0.678, 1.541, 81.694, 1.141],
        "Fe": [11.770, 4.761, 7.068, 0.307, 3.565, 15.353, 2.130, 72.048, 1.006],
        "Ca": [8.628, 10.442, 7.387, 0.660, 1.589, 85.748, 1.022, 178.437, 1.375],
        "Al": [6.420, 3.039, 1.900, 0.743, 1.594, 31.547, 1.965, 85.088, 1.115],
        "Ti": [9.759, 7.851, 5.271, 0.504, 3.575, 35.100, 0.469, 116.105, 1.926]
    ]

    // MARK: - Atomic Form Factor

    /// Compute the atomic form factor f(s) using Cromer-Mann coefficients.
    /// - Parameters:
    ///   - element: Element symbol (e.g. "Fe", "Si")
    ///   - sinThetaOverLambda: sin(theta)/lambda in Å⁻¹
    /// - Returns: The form factor value, or 0 if the element is not in the table.
    nonisolated static func computeFormFactor(element: String,
                                              sinThetaOverLambda s: Double) -> Double {
        guard let coeffs = cromerMann[element], coeffs.count == 9 else { return 0 }
        let s2 = s * s
        var f = coeffs[8] // c
        f += coeffs[0] * exp(-coeffs[1] * s2)  // a1 * exp(-b1 * s^2)
        f += coeffs[2] * exp(-coeffs[3] * s2)  // a2 * exp(-b2 * s^2)
        f += coeffs[4] * exp(-coeffs[5] * s2)  // a3 * exp(-b3 * s^2)
        f += coeffs[6] * exp(-coeffs[7] * s2)  // a4 * exp(-b4 * s^2)
        return f
    }

    // MARK: - Quantum XRD Features (Phase 37, 68 features)

    /// Computes 68 quantum-mechanical XRD features from the diffraction pattern.
    ///
    /// Features breakdown:
    /// - Atomic form factor ratios at 2theta = 20, 40, 60 deg for 4 element pairs (12 features)
    /// - Lorentz-polarisation corrected integral (1 feature)
    /// - Debye-Waller temperature factor decay ratios for B = 0.3, 0.6, 1.0, 2.0 A^2 (4 features)
    /// - Wilson plot slope and B estimate (2 features)
    /// - Anomalous scattering proxy (2 features)
    /// - F(000) and electron density proxy (2 features)
    /// - Padding to 68 features total
    nonisolated static func addQuantumXRDFeatures(
        pattern: [Float],
        twoThetaGrid: [Double],
        lambda: Double
    ) -> [String: Double] {
        var qf: [String: Double] = [:]
        let elements = ["Fe", "Si", "Ca", "Ti"]
        let refElement = "O"
        let angles: [Double] = [20.0, 40.0, 60.0]

        // --- Atomic form factor ratios at 2theta = 20, 40, 60 deg (12 features) ---
        for angle in angles {
            let thetaRad = (angle / 2.0) * Double.pi / 180.0
            let s = sin(thetaRad) / lambda
            let fRef = computeFormFactor(element: refElement, sinThetaOverLambda: s)
            for el in elements {
                let fEl = computeFormFactor(element: el, sinThetaOverLambda: s)
                let ratio = fRef > 1e-12 ? fEl / fRef : 0
                qf["qxrd_ff_\(el)_O_\(Int(angle))"] = ratio
            }
        }

        // --- Lorentz-polarisation corrected integral (1 feature) ---
        var lpIntegral = 0.0
        for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
            let thetaRad = (t2 / 2.0) * Double.pi / 180.0
            let sinTheta = sin(thetaRad)
            let cosTheta = cos(thetaRad)
            let sin2Theta = sin(2.0 * thetaRad)
            // LP = (1 + cos^2(2theta)) / (sin^2(theta) * cos(theta))
            let cos2Theta = cos(2.0 * thetaRad)
            let denom = sinTheta * sinTheta * cosTheta
            let lp: Double
            if denom > 1e-12 {
                lp = (1.0 + cos2Theta * cos2Theta) / denom
            } else {
                lp = 0
            }
            lpIntegral += Double(pattern[i]) * lp * 0.1 // 0.1 deg step
        }
        qf["qxrd_lp_integral"] = lpIntegral

        // --- Debye-Waller temperature factor decay ratios (4 features) ---
        // DW factor: exp(-B * s^2), compare at 2theta=80 vs 2theta=20
        let bValues: [Double] = [0.3, 0.6, 1.0, 2.0]
        let sLow = sin(10.0 * Double.pi / 180.0) / lambda   // 2theta=20 -> theta=10
        let sHigh = sin(40.0 * Double.pi / 180.0) / lambda   // 2theta=80 -> theta=40
        for bVal in bValues {
            let dwLow = exp(-bVal * sLow * sLow)
            let dwHigh = exp(-bVal * sHigh * sHigh)
            let ratio = dwLow > 1e-12 ? dwHigh / dwLow : 0
            qf["qxrd_dw_ratio_B\(String(format: "%.1f", bVal).replacingOccurrences(of: ".", with: "p"))"] = ratio
        }

        // --- Wilson plot slope and B estimate (2 features) ---
        // Wilson plot: ln(<I>/LP) vs sin^2(theta)/lambda^2
        // Collect averaged intensities in angular shells for linear regression
        var wilsonX: [Double] = []
        var wilsonY: [Double] = []
        let shellWidth = 10.0 // degrees
        var shellStart = 10.0
        while shellStart < 80.0 {
            let shellEnd = shellStart + shellWidth
            var sumI = 0.0
            var countBins = 0
            for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
                if t2 >= shellStart && t2 < shellEnd {
                    let thetaRad = (t2 / 2.0) * Double.pi / 180.0
                    let sinT = sin(thetaRad)
                    let cosT = cos(thetaRad)
                    let cos2T = cos(2.0 * thetaRad)
                    let denom = sinT * sinT * cosT
                    let lp = denom > 1e-12 ? (1.0 + cos2T * cos2T) / denom : 1.0
                    let corrected = lp > 1e-12 ? Double(pattern[i]) / lp : 0
                    sumI += corrected
                    countBins += 1
                }
            }
            if countBins > 0 {
                let avgI = sumI / Double(countBins)
                if avgI > 1e-12 {
                    let midAngle = (shellStart + shellEnd) / 2.0
                    let thetaMid = (midAngle / 2.0) * Double.pi / 180.0
                    let s2 = pow(sin(thetaMid) / lambda, 2)
                    wilsonX.append(s2)
                    wilsonY.append(log(avgI))
                }
            }
            shellStart += shellWidth
        }
        // Simple linear regression: y = a + b*x => Wilson B = -2 * slope
        var wilsonSlope = 0.0
        var wilsonB = 0.0
        if wilsonX.count >= 2 {
            let n = Double(wilsonX.count)
            let sumX = wilsonX.reduce(0, +)
            let sumY = wilsonY.reduce(0, +)
            let sumXY = zip(wilsonX, wilsonY).map(*).reduce(0, +)
            let sumX2 = wilsonX.map { $0 * $0 }.reduce(0, +)
            let denom = n * sumX2 - sumX * sumX
            if abs(denom) > 1e-15 {
                wilsonSlope = (n * sumXY - sumX * sumY) / denom
                wilsonB = -2.0 * wilsonSlope
            }
        }
        qf["qxrd_wilson_slope"] = wilsonSlope
        qf["qxrd_wilson_B_est"] = max(0, wilsonB) // B should be non-negative physically

        // --- Anomalous scattering proxy (2 features) ---
        // Ratio of high-angle (>60 deg) to low-angle (<30 deg) integrated intensity
        // as a proxy for the presence of heavy (anomalously scattering) elements
        var lowAngleSum = 0.0
        var highAngleSum = 0.0
        for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
            if t2 < 30.0 {
                lowAngleSum += Double(pattern[i])
            } else if t2 > 60.0 {
                highAngleSum += Double(pattern[i])
            }
        }
        qf["qxrd_anomalous_high_low_ratio"] = lowAngleSum > 1e-12 ? highAngleSum / lowAngleSum : 0
        // Second proxy: rate of intensity decay with angle (heavier atoms decay slower)
        let midAngleSum = twoThetaGrid.enumerated()
            .filter { $0.element >= 30.0 && $0.element <= 60.0 && $0.offset < pattern.count }
            .map { Double(pattern[$0.offset]) }
            .reduce(0, +)
        let totalSum = pattern.map { Double($0) }.reduce(0, +)
        qf["qxrd_anomalous_mid_fraction"] = totalSum > 1e-12 ? midAngleSum / totalSum : 0

        // --- F(000) and electron density proxy (2 features) ---
        // F(000) = sum of all electron counts (form factor at s=0)
        // Use average f(0) across common crustal elements as proxy
        let commonElements = ["O", "Si", "Al", "Fe", "Ca"]
        var f000Sum = 0.0
        for el in commonElements {
            f000Sum += computeFormFactor(element: el, sinThetaOverLambda: 0)
        }
        qf["qxrd_f000_proxy"] = f000Sum / Double(commonElements.count)
        // Electron density proxy: total pattern integral normalized by LP at midpoint
        let midTheta = 25.0 * Double.pi / 180.0
        let midLP = (1.0 + pow(cos(2.0 * midTheta), 2)) / (pow(sin(midTheta), 2) * cos(midTheta))
        qf["qxrd_electron_density_proxy"] = midLP > 1e-12 ? totalSum / midLP : 0

        // --- Pad to exactly 68 quantum features ---
        // Current feature count: 12 (form factor ratios) + 1 (LP integral) + 4 (DW ratios)
        //                        + 2 (Wilson) + 2 (anomalous) + 2 (F000/density) = 23
        // Pad remaining 45 features with derived angular statistics
        let patternD = pattern.map { Double($0) }
        let maxIntensity = patternD.max() ?? 1.0
        let normPattern = maxIntensity > 1e-12 ? patternD.map { $0 / maxIntensity } : patternD

        // Angular moment features (order 1-8) about the centroid
        let centroid: Double
        if totalSum > 1e-12 {
            centroid = zip(twoThetaGrid, patternD).map(*).reduce(0, +) / totalSum
        } else {
            centroid = 45.0
        }
        for order in 1...8 {
            var moment = 0.0
            for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
                moment += pow(t2 - centroid, Double(order)) * Double(pattern[i])
            }
            qf["qxrd_moment_\(order)"] = totalSum > 1e-12 ? moment / totalSum : 0
        }

        // Form factor weighted integrals for each element at pattern centroid
        let sCentroid = sin((centroid / 2.0) * Double.pi / 180.0) / lambda
        let allElements = ["H", "C", "N", "O", "Si", "Fe", "Ca", "Al", "Ti"]
        for el in allElements {
            let fAtCentroid = computeFormFactor(element: el, sinThetaOverLambda: sCentroid)
            qf["qxrd_ff_weighted_\(el)"] = fAtCentroid * totalSum
        }

        // Debye-Waller weighted pattern variance for B = 0.5, 1.5, 3.0
        let extraB: [Double] = [0.5, 1.5, 3.0]
        for bVal in extraB {
            var dwWeightedVar = 0.0
            for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
                let thetaRad = (t2 / 2.0) * Double.pi / 180.0
                let sVal = sin(thetaRad) / lambda
                let dw = exp(-bVal * sVal * sVal)
                let diff = t2 - centroid
                dwWeightedVar += dw * diff * diff * Double(pattern[i])
            }
            qf["qxrd_dw_var_B\(String(format: "%.1f", bVal).replacingOccurrences(of: ".", with: "p"))"] = totalSum > 1e-12 ? dwWeightedVar / totalSum : 0
        }

        // Entropy of LP-corrected pattern
        var lpCorrected: [Double] = []
        for (i, t2) in twoThetaGrid.enumerated() where i < pattern.count {
            let thetaRad = (t2 / 2.0) * Double.pi / 180.0
            let sinT = sin(thetaRad)
            let cosT = cos(thetaRad)
            let cos2T = cos(2.0 * thetaRad)
            let denom = sinT * sinT * cosT
            let lp = denom > 1e-12 ? (1.0 + cos2T * cos2T) / denom : 1.0
            let corrected = lp > 1e-12 ? Double(pattern[i]) / lp : 0
            lpCorrected.append(max(corrected, 0))
        }
        let lpSum = lpCorrected.reduce(0, +)
        var lpEntropy = 0.0
        if lpSum > 1e-12 {
            for val in lpCorrected {
                let p = val / lpSum
                if p > 1e-15 {
                    lpEntropy -= p * log(p)
                }
            }
        }
        qf["qxrd_lp_entropy"] = lpEntropy

        // Crystallinity from LP-corrected pattern: peak-to-background ratio
        let lpMax = lpCorrected.max() ?? 0
        let lpMedian: Double
        let sorted = lpCorrected.sorted()
        if sorted.count > 0 {
            lpMedian = sorted[sorted.count / 2]
        } else {
            lpMedian = 0
        }
        qf["qxrd_lp_peak_bg_ratio"] = lpMedian > 1e-12 ? lpMax / lpMedian : 0

        // Form factor curvature: d^2f/ds^2 proxy at s corresponding to 2theta=30
        let s30 = sin(15.0 * Double.pi / 180.0) / lambda
        let ds = 0.01
        for el in ["Fe", "Si", "O", "Ca"] {
            let fMinus = computeFormFactor(element: el, sinThetaOverLambda: s30 - ds)
            let fCenter = computeFormFactor(element: el, sinThetaOverLambda: s30)
            let fPlus = computeFormFactor(element: el, sinThetaOverLambda: s30 + ds)
            let curvature = (fPlus - 2.0 * fCenter + fMinus) / (ds * ds)
            qf["qxrd_ff_curv_\(el)_30"] = curvature
        }

        // Normalized cumulative distribution quantiles
        let quantiles = [0.10, 0.25, 0.50, 0.75, 0.90]
        if totalSum > 1e-12 {
            var cumSum = 0.0
            var qIdx = 0
            for (i, _) in twoThetaGrid.enumerated() where i < pattern.count && qIdx < quantiles.count {
                cumSum += Double(pattern[i])
                if cumSum / totalSum >= quantiles[qIdx] {
                    qf["qxrd_quantile_\(Int(quantiles[qIdx] * 100))"] = twoThetaGrid[i]
                    qIdx += 1
                }
            }
            // Fill remaining quantiles if not reached
            while qIdx < quantiles.count {
                qf["qxrd_quantile_\(Int(quantiles[qIdx] * 100))"] = twoThetaGrid.last ?? 90.0
                qIdx += 1
            }
        } else {
            for q in quantiles {
                qf["qxrd_quantile_\(Int(q * 100))"] = 0
            }
        }

        // Ensure exactly 68 features by padding any remaining slots
        let currentCount = qf.count
        if currentCount < 68 {
            for padIdx in currentCount..<68 {
                qf["qxrd_pad_\(padIdx)"] = 0
            }
        }

        return qf
    }

    // MARK: - Pattern Synthesis

    func synthesizePattern(peaks: [DiffractionPeak],
                           crystalliteSize: Double = Double.random(in: 20...200),
                           eta: Double = 0.5) -> TrainingRecord {
        var pattern = [Float](repeating: 0, count: twoThetaGrid.count)
        for pk in peaks {
            let sinT = lambda / (2.0 * pk.dSpacing)
            guard sinT <= 1.0 else { continue }
            let theta = asin(sinT)
            let tt = 2.0 * theta * 180.0 / .pi
            let betaRad = (0.9 * lambda) / (crystalliteSize * cos(theta))
            let betaDeg = betaRad * 180.0 / .pi
            let sigma = betaDeg / 2.355
            for (i, t2) in twoThetaGrid.enumerated() {
                let dx = t2 - tt
                let gauss = exp(-(dx * dx) / (2 * sigma * sigma))
                let lorentz = 1.0 / (1.0 + (dx / (betaDeg / 2.0)) * (dx / (betaDeg / 2.0)))
                let pv = eta * lorentz + (1 - eta) * gauss
                pattern[i] += Float(pk.relIntensity / 100.0 * pv)
            }
        }
        for i in 0..<pattern.count {
            pattern[i] += Float.random(in: 0.001...0.006)
        }

        let peakCount = peaks.count
        let strongest = peaks.max(by: { $0.relIntensity < $1.relIntensity })
        let d100 = strongest?.dSpacing ?? 0
        let strongestTheta = d100 > 0 ? 2 * asin(lambda / (2 * d100)) * 180 / .pi : 0

        var derived: [String: Double] = [
            "peak_count": Double(peakCount),
            "strongest_peak_2theta": strongestTheta,
            "d100_spacing_ang": d100,
            "crystallite_size_nm": crystalliteSize / 10,
        ]

        // Merge quantum XRD features (Phase 37)
        let quantumFeatures = Self.addQuantumXRDFeatures(
            pattern: pattern,
            twoThetaGrid: twoThetaGrid,
            lambda: lambda
        )
        for (key, value) in quantumFeatures {
            derived[key] = value
        }

        var features = pattern
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.xrdPowder.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.xrdPowder.featureCount))

        return TrainingRecord(
            modality: .xrdPowder, sourceID: "synth_bragg",
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "Bragg_PseudoVoigt")
    }

    // MARK: - Batch Synthesis

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { _ in
            let numPeaks = Int.random(in: 3...20)
            let peaks = (0..<numPeaks).map { _ in
                DiffractionPeak(dSpacing: Double.random(in: 1.0...10.0),
                                relIntensity: Double.random(in: 5...100))
            }
            return synthesizePattern(peaks: peaks)
        }
    }
}
