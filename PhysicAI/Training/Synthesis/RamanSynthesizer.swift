import Foundation
import Accelerate

actor RamanSynthesizer {

    private var mineralSpectra: [String: [Float]] = [:]
    private let grid = stride(from: 100.0, through: 3590.0, by: 10.0).map { $0 }

    func loadReference(mineral: String, shifts: [Double], intensities: [Double]) {
        let maxI = intensities.max() ?? 1.0
        let norm = intensities.map { $0 / max(maxI, 1e-9) }
        if let g = SpectralNormalizer.resampleToGrid(x: shifts, y: norm, grid: grid) {
            mineralSpectra[mineral] = g
        }
    }

    func synthesize(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        let keys = Array(mineralSpectra.keys)
        guard !keys.isEmpty else { return [] }
        for _ in 0..<count {
            let useMix = Double.random(in: 0...1) < 0.3
            let n = useMix ? 2 : 1
            let chosen = (0..<n).compactMap { _ in keys.randomElement() }
            var spectrum = [Float](repeating: 0, count: grid.count)
            let weights = (0..<n).map { _ in Float.random(in: 0.3...0.7) }
            let wSum = weights.reduce(0, +)
            for (mineral, w) in zip(chosen, weights) {
                if let ref = mineralSpectra[mineral] {
                    for i in 0..<grid.count { spectrum[i] += ref[i] * (w / wSum) }
                }
            }
            // Bose-Einstein thermal correction at 298 K
            let kTcm: Double = 207.2
            for i in 0..<grid.count {
                let nu = grid[i]
                let beCorr = Float(1.0 / (1.0 - exp(-nu / kTcm)))
                spectrum[i] *= beCorr
            }
            // Background + shot noise
            let bgSlope = Float.random(in: 0...0.0003)
            spectrum = spectrum.enumerated().map { i, v in
                max(0, v + bgSlope * Float(i) * 0.001 + Float.random(in: -0.01...0.01))
            }
            var derived = deriveFeatures(spectrum)

            // Phase 34: Quantum Raman features (60 additional)
            let excNM = [532.0, 633.0, 785.0, 1064.0].randomElement()!
            let resNM: Double? = Double.random(in: 0...1) < 0.1 ? excNM + Double.random(in: -50...50) : nil
            let qFeatures = Self.quantumRamanFeatures(spectrum: spectrum, grid: grid, excitationNM: excNM, nearResonanceNM: resNM)
            for (k, v) in qFeatures { derived[k] = v }

            var features = spectrum
            for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
            while features.count < SpectralModality.raman.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.raman.featureCount))
            let label = chosen.first ?? "unknown"
            records.append(TrainingRecord(
                modality: .raman, sourceID: "rruff_synth_\(label)",
                features: features, targets: derived,
                metadata: ["mineral": label],
                isComputedLabel: true, computationMethod: "BoseEinstein_Raman"))
        }
        return records
    }

    // MARK: - Phase 34 — Quantum Raman Features (60 features)

    /// Computes 60 quantum-mechanical Raman features from the spectrum:
    ///
    /// - Resonance Raman enhancement (Albrecht A-term and B-term)
    /// - Anharmonic oscillator (Morse potential) features for the 2 strongest peaks
    /// - Depolarisation ratio estimates
    /// - CARS (Coherent Anti-Stokes Raman) virtual level estimates
    /// - Stokes / Anti-Stokes ratio as a temperature probe
    /// - Surface-enhanced Raman (SERS) proximity proxy
    /// - Fermi resonance detection between overtones and fundamentals
    nonisolated static func quantumRamanFeatures(
        spectrum: [Float],
        grid: [Double],
        excitationNM: Double,
        nearResonanceNM: Double? = nil
    ) -> [String: Double] {
        guard !spectrum.isEmpty, spectrum.count == grid.count else { return [:] }
        var d: [String: Double] = [:]
        let a = spectrum.map { Double($0) }
        let totalIntensity = a.reduce(0, +)
        guard totalIntensity > 1e-12 else { return [:] }

        // --- Utility: convert nm to cm^-1 ---
        let excCM = 1.0e7 / excitationNM  // excitation in cm^-1

        // --- Find top N peaks ---
        let peakIndices = findTopPeaks(spectrum: a, count: 10)
        let top2 = Array(peakIndices.prefix(2))

        // ============================================================
        // 1. Resonance Raman Enhancement — Albrecht A-term (8 features)
        // ============================================================
        // A-term: enhancement ~ |M_eg|^4 / (Delta_e^2)
        // where Delta_e = |E_excitation - E_electronic_transition|
        let resCM: Double
        if let resNM = nearResonanceNM {
            resCM = 1.0e7 / resNM
        } else {
            // Assume nearest electronic transition is far off-resonance (50000 cm^-1 ~ 200 nm)
            resCM = 50000.0
        }
        let deltaE = abs(excCM - resCM)
        let aTermEnhancement = 1.0 / max(deltaE * deltaE, 1.0)
        let aTermNorm = aTermEnhancement * 1e10  // scale to useful range
        d["q_albrecht_a_term"] = aTermNorm
        d["q_resonance_delta_cm"] = deltaE
        d["q_excitation_cm"] = excCM
        d["q_excitation_nm"] = excitationNM
        d["q_is_resonance"] = deltaE < 2000.0 ? 1.0 : 0.0

        // B-term (vibronic coupling): enhancement ~ sum_peaks (nu_peak / Delta_e)
        var bTermSum = 0.0
        for idx in peakIndices.prefix(5) {
            let nuPeak = grid[idx]
            bTermSum += nuPeak / max(deltaE, 1.0)
        }
        d["q_albrecht_b_term"] = bTermSum
        // Pre-resonance Raman excitation profile (RREP) slope
        d["q_rrep_slope"] = 2.0 * excCM / max(deltaE * deltaE * deltaE, 1.0) * 1e15
        // Resonance selectivity: ratio of top peak to mean spectrum under resonance
        let meanSpec = totalIntensity / Double(spectrum.count)
        let topPeakIntensity = top2.isEmpty ? 0.0 : a[top2[0]]
        d["q_resonance_selectivity"] = topPeakIntensity / max(meanSpec, 1e-12)

        // ============================================================
        // 2. Anharmonic Oscillator / Morse Potential — 2 peaks (16 features)
        // ============================================================
        // Morse: E_n = hc * omega_e * (n+0.5) - hc * omega_e * chi_e * (n+0.5)^2
        // chi_e (anharmonicity) estimated from peak asymmetry and overtone search
        for (pIdx, peakI) in top2.enumerated() {
            let prefix = "q_morse_p\(pIdx)_"
            let omega_e = grid[peakI]  // fundamental frequency cm^-1
            d["\(prefix)omega_e"] = omega_e

            // Estimate anharmonicity from peak shape asymmetry
            let asymmetry = peakAsymmetry(spectrum: a, grid: grid, peakIndex: peakI)
            let chi_e = 0.01 + 0.04 * abs(asymmetry)  // typical chi_e ~ 0.01 - 0.05
            d["\(prefix)chi_e"] = chi_e

            // Predicted overtone positions
            let firstOvertone = 2.0 * omega_e * (1.0 - 3.0 * chi_e)
            let secondOvertone = 3.0 * omega_e * (1.0 - 4.0 * chi_e)
            d["\(prefix)overtone_1_cm"] = firstOvertone
            d["\(prefix)overtone_2_cm"] = secondOvertone

            // Dissociation energy estimate: D_e = omega_e / (4 * chi_e)
            let d_e = omega_e / max(4.0 * chi_e, 1e-6)
            d["\(prefix)dissociation_cm"] = d_e

            // Zero-point energy: E_0 = 0.5 * omega_e * (1 - 0.5 * chi_e)
            d["\(prefix)zpe_cm"] = 0.5 * omega_e * (1.0 - 0.5 * chi_e)

            // Peak FWHM estimate
            d["\(prefix)fwhm_cm"] = estimateFWHM(spectrum: a, grid: grid, peakIndex: peakI)

            // Relative intensity of this peak
            d["\(prefix)rel_intensity"] = a[peakI] / max(topPeakIntensity, 1e-12)
        }
        // Pad if fewer than 2 peaks found
        for pIdx in top2.count..<2 {
            let prefix = "q_morse_p\(pIdx)_"
            for suffix in ["omega_e", "chi_e", "overtone_1_cm", "overtone_2_cm",
                           "dissociation_cm", "zpe_cm", "fwhm_cm", "rel_intensity"] {
                d["\(prefix)\(suffix)"] = 0.0
            }
        }

        // ============================================================
        // 3. Depolarisation Ratio Estimates (6 features)
        // ============================================================
        // rho = I_perp / I_parallel; for totally symmetric modes rho -> 0,
        // for non-symmetric rho -> 0.75 (for linearly polarised excitation)
        // Estimate from peak shape: narrow, symmetric peaks -> likely symmetric mode
        for (pIdx, peakI) in top2.enumerated() {
            let prefix = "q_depol_p\(pIdx)_"
            let fwhm = estimateFWHM(spectrum: a, grid: grid, peakIndex: peakI)
            let asym = abs(peakAsymmetry(spectrum: a, grid: grid, peakIndex: peakI))
            // Heuristic: symmetric, narrow peaks -> low depolarisation ratio
            let rhoEst = min(0.75, 0.1 + 0.4 * asym + 0.002 * fwhm)
            d["\(prefix)rho_est"] = rhoEst
            d["\(prefix)is_symmetric"] = rhoEst < 0.3 ? 1.0 : 0.0
        }
        for pIdx in top2.count..<2 {
            let prefix = "q_depol_p\(pIdx)_"
            d["\(prefix)rho_est"] = 0.0
            d["\(prefix)is_symmetric"] = 0.0
        }
        // Weighted mean depolarisation for all peaks above 10% of max
        let threshold = topPeakIntensity * 0.1
        var rhoWeightedSum = 0.0
        var rhoWeightSum = 0.0
        for idx in peakIndices {
            let fwhm = estimateFWHM(spectrum: a, grid: grid, peakIndex: idx)
            let asym = abs(peakAsymmetry(spectrum: a, grid: grid, peakIndex: idx))
            let rho = min(0.75, 0.1 + 0.4 * asym + 0.002 * fwhm)
            let w = a[idx]
            rhoWeightedSum += rho * w
            rhoWeightSum += w
        }
        d["q_depol_mean_weighted"] = rhoWeightSum > 1e-12 ? rhoWeightedSum / rhoWeightSum : 0.0
        d["q_depol_symmetric_fraction"] = Double(peakIndices.filter { a[$0] > threshold }.count) /
            max(Double(peakIndices.count), 1.0)

        // ============================================================
        // 4. CARS Virtual Level Estimates (6 features)
        // ============================================================
        // CARS: omega_CARS = 2*omega_pump - omega_Stokes
        // Virtual level: omega_virtual = omega_pump + omega_vib
        let pumpCM = excCM
        for (pIdx, peakI) in top2.enumerated() {
            let prefix = "q_cars_p\(pIdx)_"
            let omegaVib = grid[peakI]
            let omegaStokes = pumpCM - omegaVib
            let omegaCARS = 2.0 * pumpCM - omegaStokes  // = pump + vib
            d["\(prefix)omega_cars_cm"] = omegaCARS
            d["\(prefix)virtual_level_cm"] = pumpCM + omegaVib
            // CARS signal scales as (chi^(3))^2 ~ N^2, proportional to peak intensity squared
            d["\(prefix)chi3_proxy"] = a[peakI] * a[peakI]
        }
        for pIdx in top2.count..<2 {
            let prefix = "q_cars_p\(pIdx)_"
            d["\(prefix)omega_cars_cm"] = 0.0
            d["\(prefix)virtual_level_cm"] = 0.0
            d["\(prefix)chi3_proxy"] = 0.0
        }

        // ============================================================
        // 5. Stokes / Anti-Stokes Ratio — Temperature Probe (6 features)
        // ============================================================
        // I_AS / I_S = ((nu0 + nu_m)/(nu0 - nu_m))^4 * exp(-hc*nu_m / kT)
        // At T=298 K, kT = 207.2 cm^-1
        let kT298: Double = 207.2
        let tempK = 298.0
        for (pIdx, peakI) in top2.enumerated() {
            let prefix = "q_stokes_p\(pIdx)_"
            let nuM = grid[peakI]
            let freqRatio = (excCM + nuM) / max(excCM - nuM, 1.0)
            let boltzmann = exp(-nuM / kT298)
            let asRatio = pow(freqRatio, 4.0) * boltzmann
            d["\(prefix)as_ratio"] = asRatio
            d["\(prefix)boltzmann_factor"] = boltzmann
            // Effective temperature from this ratio (self-consistent at 298 K for synth data)
            d["\(prefix)temp_est_K"] = tempK
        }
        for pIdx in top2.count..<2 {
            let prefix = "q_stokes_p\(pIdx)_"
            d["\(prefix)as_ratio"] = 0.0
            d["\(prefix)boltzmann_factor"] = 0.0
            d["\(prefix)temp_est_K"] = 0.0
        }

        // ============================================================
        // 6. Surface Enhancement (SERS) Proxy (6 features)
        // ============================================================
        // SERS enhancement ~ |E_local / E_0|^4 ~ (lambda_LSPR / lambda_exc)^4 for
        // nanoparticle resonance; we model proximity to common Ag/Au LSPR bands
        let agLSPR_nm = 420.0   // Ag nanoparticle LSPR ~ 420 nm
        let auLSPR_nm = 530.0   // Au nanoparticle LSPR ~ 530 nm
        let agDetuning = abs(excitationNM - agLSPR_nm)
        let auDetuning = abs(excitationNM - auLSPR_nm)
        // EM enhancement factor (order-of-magnitude proxy): peaks when excitation near LSPR
        let agEF = 1e4 / max(agDetuning * agDetuning + 100.0, 1.0)
        let auEF = 1e4 / max(auDetuning * auDetuning + 100.0, 1.0)
        d["q_sers_ag_ef_proxy"] = agEF
        d["q_sers_au_ef_proxy"] = auEF
        d["q_sers_ag_detuning_nm"] = agDetuning
        d["q_sers_au_detuning_nm"] = auDetuning
        // Chemical enhancement contribution (charge transfer): heuristic from low-freq modes
        let lowFreqPower = zip(grid, a).filter { $0.0 >= 100 && $0.0 <= 300 }
            .map { $0.1 }.reduce(0, +)
        d["q_sers_ct_proxy"] = lowFreqPower / max(totalIntensity, 1e-12)
        // Total SERS enhancement estimate (EM * CT)
        d["q_sers_total_ef"] = max(agEF, auEF) * (1.0 + d["q_sers_ct_proxy"]!)

        // ============================================================
        // 7. Fermi Resonance Detection (12 features)
        // ============================================================
        // Fermi resonance: when an overtone (2*nu_i) or combination (nu_i + nu_j)
        // is near a fundamental nu_k, intensity borrowing occurs producing a doublet
        // with anomalous intensity ratio
        var fermiCount = 0
        var fermiStrength = 0.0
        var fermiBestShift = 0.0
        var fermiBestIntensityRatio = 0.0
        let significantPeaks = peakIndices.filter { a[$0] > topPeakIntensity * 0.05 }
        for i in 0..<significantPeaks.count {
            let nuI = grid[significantPeaks[i]]
            // Check if 2 * nuI is near another peak (overtone Fermi resonance)
            let overtone = 2.0 * nuI
            for j in 0..<significantPeaks.count where j != i {
                let nuJ = grid[significantPeaks[j]]
                let delta = abs(overtone - nuJ)
                if delta < 30.0 {  // within 30 cm^-1 coupling window
                    fermiCount += 1
                    let coupling = 30.0 - delta  // stronger when closer
                    fermiStrength += coupling
                    if coupling > fermiBestShift {
                        fermiBestShift = coupling
                        let iRatio = min(a[significantPeaks[i]], a[significantPeaks[j]]) /
                            max(a[significantPeaks[i]], a[significantPeaks[j]], 1e-12)
                        fermiBestIntensityRatio = iRatio
                    }
                }
            }
            // Check combination bands: nu_i + nu_j near nu_k
            if i + 1 < significantPeaks.count {
                for j in (i + 1)..<significantPeaks.count {
                    let nuJ = grid[significantPeaks[j]]
                    let combo = nuI + nuJ
                    for k in 0..<significantPeaks.count where k != i && k != j {
                        let nuK = grid[significantPeaks[k]]
                        if abs(combo - nuK) < 30.0 {
                            fermiCount += 1
                            fermiStrength += 30.0 - abs(combo - nuK)
                        }
                    }
                }
            }
        }
        d["q_fermi_count"] = Double(fermiCount)
        d["q_fermi_total_strength"] = fermiStrength
        d["q_fermi_best_coupling_cm"] = fermiBestShift
        d["q_fermi_best_intensity_ratio"] = fermiBestIntensityRatio
        d["q_fermi_has_resonance"] = fermiCount > 0 ? 1.0 : 0.0
        // Doublet splitting estimate: if Fermi resonance exists, the splitting W
        // relates to coupling matrix element: W^2 = delta^2 + 4*V^2
        // We use the best coupling proximity as a proxy for V
        let vProxy = fermiBestShift / 2.0
        d["q_fermi_splitting_est_cm"] = sqrt(fermiBestShift * fermiBestShift + 4.0 * vProxy * vProxy)
        // Anomalous intensity redistribution index
        let pairIntensityVar = significantPeaks.count >= 2 ?
            zip(significantPeaks, significantPeaks.dropFirst()).map { abs(a[$0] - a[$1]) }.reduce(0, +) /
            Double(significantPeaks.count) : 0.0
        d["q_fermi_anomaly_index"] = pairIntensityVar / max(topPeakIntensity, 1e-12)
        // Number of combination-band candidates
        d["q_fermi_combo_candidates"] = Double(max(0, fermiCount - significantPeaks.count))
        // Spectral region most affected by Fermi resonance (centroid of resonance activity)
        d["q_fermi_active_region_cm"] = fermiBestShift > 0 && !top2.isEmpty ?
            grid[top2[0]] : 0.0
        // Fraction of total spectrum intensity in Fermi-active peaks
        let fermiPeakIntensity = significantPeaks.prefix(min(fermiCount + 1, significantPeaks.count))
            .map { a[$0] }.reduce(0, +)
        d["q_fermi_intensity_fraction"] = fermiPeakIntensity / max(totalIntensity, 1e-12)
        // Overall Fermi resonance probability score (composite)
        let fermiProb = fermiCount > 0 ?
            min(1.0, Double(fermiCount) * 0.15 + fermiStrength * 0.005) : 0.0
        d["q_fermi_probability"] = fermiProb

        return d
    }

    // MARK: - Peak Finding Helpers

    /// Finds the indices of the top `count` peaks by intensity with minimal separation.
    private nonisolated static func findTopPeaks(spectrum: [Double], count: Int) -> [Int] {
        guard spectrum.count > 2 else { return [] }
        var peaks: [(index: Int, value: Double)] = []
        for i in 1..<(spectrum.count - 1) {
            if spectrum[i] > spectrum[i - 1] && spectrum[i] > spectrum[i + 1] {
                peaks.append((i, spectrum[i]))
            }
        }
        peaks.sort { $0.value > $1.value }
        // Enforce minimum separation of 3 bins between selected peaks
        var selected: [Int] = []
        for p in peaks {
            if selected.allSatisfy({ abs($0 - p.index) >= 3 }) {
                selected.append(p.index)
                if selected.count >= count { break }
            }
        }
        return selected
    }

    /// Estimates the FWHM (in cm^-1) of the peak at the given index.
    private nonisolated static func estimateFWHM(spectrum: [Double], grid: [Double], peakIndex: Int) -> Double {
        let halfMax = spectrum[peakIndex] / 2.0
        var leftIdx = peakIndex
        while leftIdx > 0 && spectrum[leftIdx] > halfMax { leftIdx -= 1 }
        var rightIdx = peakIndex
        while rightIdx < spectrum.count - 1 && spectrum[rightIdx] > halfMax { rightIdx += 1 }
        return grid[min(rightIdx, grid.count - 1)] - grid[max(leftIdx, 0)]
    }

    /// Measures peak asymmetry: negative = left-skewed, positive = right-skewed.
    private nonisolated static func peakAsymmetry(spectrum: [Double], grid: [Double], peakIndex: Int) -> Double {
        let halfMax = spectrum[peakIndex] / 2.0
        var leftIdx = peakIndex
        while leftIdx > 0 && spectrum[leftIdx] > halfMax { leftIdx -= 1 }
        var rightIdx = peakIndex
        while rightIdx < spectrum.count - 1 && spectrum[rightIdx] > halfMax { rightIdx += 1 }
        let leftWidth = grid[peakIndex] - grid[max(leftIdx, 0)]
        let rightWidth = grid[min(rightIdx, grid.count - 1)] - grid[peakIndex]
        let totalWidth = leftWidth + rightWidth
        guard totalWidth > 1e-6 else { return 0.0 }
        return (rightWidth - leftWidth) / totalWidth
    }

    // MARK: - Classical Derived Features

    private func deriveFeatures(_ s: [Float]) -> [String: Double] {
        let a = s.map { Double($0) }
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 10
        }
        let peakIdx = s.enumerated().max(by: { $0.1 < $1.1 })?.0 ?? 0
        return [
            "d_band": integral(1300, 1400),
            "g_band": integral(1500, 1620),
            "d_g_ratio": integral(1300, 1400) / max(integral(1500, 1620), 1e-9),
            "fingerprint_integral": integral(200, 1200),
            "high_freq_integral": integral(2700, 3200),
            "peak_position_cm1": grid[peakIdx],
            "background_slope": Double(s.last ?? 0) - Double(s.first ?? 0),
        ]
    }
}
