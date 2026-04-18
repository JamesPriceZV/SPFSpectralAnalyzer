import Foundation

/// Combined 1H and 13C NMR synthesizer with quantum-mechanical feature extensions.
///
/// Phase 32 adds 48 quantum NMR features for 1H (Zeeman, CSA tensor, T1/T2,
/// NOE, Karplus J-coupling). Phase 33 adds 43 quantum features for 13C (CSA,
/// T1 dipolar, NOE, DEPT, J_CC).
actor NMRSynthesizer {

    private let shoolery: [String: Double] = [
        "carbonyl": 1.20, "hydroxyl": 1.74, "chloro": 2.53,
        "bromo": 2.33,    "phenyl": 1.85,   "vinyl": 1.32,
        "carboxyl": 0.97, "amine": 0.53,    "ether": 1.14,
        "nitro": 3.36,    "cyano": 1.05,    "fluorine": 1.55
    ]
    private let gridPPM1H = stride(from: 0.0, through: 11.95, by: 0.05).map { $0 }
    private let gridPPM13C = (0...249).map { Double($0) }
    private let lw = 0.05  // ppm Lorentzian FWHM

    // MARK: - Physical Constants

    /// Gyromagnetic ratio for 1H in rad/(s T).
    private static let gammaH: Double = 2.6752218744e8
    /// Gyromagnetic ratio for 13C in rad/(s T).
    private static let gammaC: Double = 6.728284e7
    /// Reduced Planck constant (J s).
    private static let hbar: Double = 1.054571817e-34
    /// Boltzmann constant (J/K).
    private static let kB: Double = 1.380649e-23
    /// Vacuum permeability (T m/A).
    private static let mu0: Double = 1.2566370614e-6
    /// Bohr magneton (J/T).
    private static let muB: Double = 9.2740100783e-24

    // MARK: - Phase 32: Quantum 1H NMR Features (48 features)

    /// Computes 48 quantum-mechanical features for a 1H NMR spectrum.
    ///
    /// Features cover:
    /// - Zeeman splitting and Larmor frequency (6)
    /// - CSA tensor components for protons (6)
    /// - T1/T2 relaxation from BPP theory (8)
    /// - NOE enhancement factors (6)
    /// - Karplus J-coupling analysis (10)
    /// - Spectral density function values (6)
    /// - Multiplet pattern analysis (6)
    ///
    /// - Parameters:
    ///   - spectrum: The 240-bin 1H spectrum (0–11.95 ppm at 0.05 ppm steps).
    ///   - fieldStrengthT: Static magnetic field in Tesla (default 14.1 T = 600 MHz).
    ///   - correlationTimeNs: Rotational correlation time in nanoseconds (default 0.5 ns).
    ///   - temperatureK: Sample temperature in Kelvin (default 298 K).
    /// - Returns: Dictionary with 48 named quantum features.
    nonisolated static func quantumNMRFeatures(
        spectrum: [Float],
        fieldStrengthT: Double = 14.1,
        correlationTimeNs: Double = 0.5,
        temperatureK: Double = 298.0
    ) -> [String: Double] {
        var d: [String: Double] = [:]
        let grid = stride(from: 0.0, through: 11.95, by: 0.05).map { $0 }
        let a = spectrum.map { Double($0) }
        let tot = a.reduce(0, +)

        // -- Zeeman / Larmor (6 features) --
        let omega0 = gammaH * fieldStrengthT                       // Larmor angular freq (rad/s)
        let nu0 = omega0 / (2.0 * .pi)                             // Larmor frequency (Hz)
        let zeemanSplitting = hbar * omega0                         // Zeeman energy splitting (J)
        let boltzmannPol = tanh(zeemanSplitting / (2.0 * kB * temperatureK)) // polarisation
        let sensitivityFactor = gammaH * gammaH * gammaH * fieldStrengthT * fieldStrengthT
        let thermalEquilibrium = zeemanSplitting / (kB * temperatureK)

        d["zeeman_larmor_freq_MHz"] = nu0 / 1e6
        d["zeeman_splitting_J"] = zeemanSplitting
        d["zeeman_boltzmann_pol"] = boltzmannPol
        d["zeeman_thermal_eq"] = thermalEquilibrium
        d["zeeman_sensitivity_factor"] = sensitivityFactor / 1e30  // normalised
        d["zeeman_field_T"] = fieldStrengthT

        // -- CSA Tensor for Protons (6 features) --
        // Typical 1H CSA is small (5-15 ppm); estimate from spectral spread
        let peakPPMs = findPeakPositions(a, grid: grid, threshold: 0.05)
        let csaSpan: Double
        if peakPPMs.count >= 2 {
            csaSpan = (peakPPMs.max() ?? 0) - (peakPPMs.min() ?? 0)
        } else {
            csaSpan = 3.0  // default
        }
        let csaSigma11 = csaSpan * 0.6     // most deshielded
        let csaSigma22 = csaSpan * 0.3     // intermediate
        let csaSigma33 = -csaSpan * 0.1    // most shielded (relative)
        let csaIso = (csaSigma11 + csaSigma22 + csaSigma33) / 3.0
        let csaAnisotropy = csaSigma11 - (csaSigma22 + csaSigma33) / 2.0
        let csaAsymmetry = (csaSigma22 - csaSigma33) / max(abs(csaSigma11 - csaIso), 1e-9)

        d["csa_h_isotropic_ppm"] = csaIso
        d["csa_h_anisotropy_ppm"] = csaAnisotropy
        d["csa_h_asymmetry_eta"] = min(max(csaAsymmetry, 0), 1)
        d["csa_h_sigma11_ppm"] = csaSigma11
        d["csa_h_sigma22_ppm"] = csaSigma22
        d["csa_h_sigma33_ppm"] = csaSigma33

        // -- T1/T2 Relaxation from BPP Theory (8 features) --
        // Bloembergen-Purcell-Pound dipolar relaxation
        let tauC = correlationTimeNs * 1e-9                         // correlation time in seconds
        let rHH = 1.8e-10                                           // typical H-H distance (m)
        let omega = omega0
        let bDD = (mu0 / (4.0 * .pi)) * gammaH * gammaH * hbar / (rHH * rHH * rHH)
        let bDDsq = bDD * bDD

        // Spectral density functions J(omega)
        func spectralDensity(_ w: Double) -> Double {
            2.0 * tauC / (1.0 + w * w * tauC * tauC)
        }

        let j0 = spectralDensity(0)
        let jOmega = spectralDensity(omega)
        let j2Omega = spectralDensity(2.0 * omega)

        // T1 (spin-lattice) for H-H dipolar
        let r1DD = (3.0 / 10.0) * bDDsq * (jOmega + 4.0 * j2Omega)
        let t1DD = r1DD > 1e-30 ? 1.0 / r1DD : 100.0

        // T2 (spin-spin) for H-H dipolar
        let r2DD = (1.0 / 20.0) * bDDsq * (3.0 * j0 + 5.0 * jOmega + 2.0 * j2Omega)
        let t2DD = r2DD > 1e-30 ? 1.0 / r2DD : 100.0

        // CSA contribution to relaxation
        let csaRad = csaAnisotropy * 1e-6 * omega  // CSA in angular frequency units
        let r1CSA = (2.0 / 15.0) * csaRad * csaRad * jOmega
        let r2CSA = (1.0 / 45.0) * csaRad * csaRad * (4.0 * j0 + 3.0 * jOmega)

        let t1Total = (r1DD + r1CSA) > 1e-30 ? 1.0 / (r1DD + r1CSA) : 100.0
        let t2Total = (r2DD + r2CSA) > 1e-30 ? 1.0 / (r2DD + r2CSA) : 100.0
        let t1t2Ratio = t1Total / max(t2Total, 1e-12)

        d["relax_t1_dd_s"] = min(t1DD, 100)
        d["relax_t2_dd_s"] = min(t2DD, 100)
        d["relax_t1_csa_contrib"] = r1CSA / max(r1DD + r1CSA, 1e-30)
        d["relax_t2_csa_contrib"] = r2CSA / max(r2DD + r2CSA, 1e-30)
        d["relax_t1_total_s"] = min(t1Total, 100)
        d["relax_t2_total_s"] = min(t2Total, 100)
        d["relax_t1_t2_ratio"] = min(t1t2Ratio, 1000)
        d["relax_correlation_time_ns"] = correlationTimeNs

        // -- NOE Enhancement (6 features) --
        // Steady-state NOE for homonuclear 1H-1H
        let sigmaHH = (1.0 / 10.0) * bDDsq * (6.0 * j2Omega - jOmega)
        let rhoHH = (1.0 / 10.0) * bDDsq * (jOmega + 3.0 * jOmega + 6.0 * j2Omega)
        let noeEnhancement = rhoHH > 1e-30 ? sigmaHH / rhoHH : 0

        // Extreme narrowing limit: NOE_max = 0.5 for homonuclear
        let omegaTauC = omega * tauC
        let isExtremeNarrowing = omegaTauC < 0.1 ? 1.0 : 0.0
        // Spin diffusion regime: omega*tauC >> 1 gives negative NOE
        let isSpinDiffusion = omegaTauC > 1.12 ? 1.0 : 0.0
        let noeCrossRelax = sigmaHH
        let noeDirectRelax = rhoHH

        d["noe_enhancement"] = noeEnhancement
        d["noe_cross_relax_rate"] = noeCrossRelax
        d["noe_direct_relax_rate"] = noeDirectRelax
        d["noe_extreme_narrowing"] = isExtremeNarrowing
        d["noe_spin_diffusion"] = isSpinDiffusion
        d["noe_omega_tau_c"] = omegaTauC

        // -- Karplus J-Coupling Analysis (10 features) --
        // Haasnoot-Altona generalised Karplus: J = A cos^2(phi) - B cos(phi) + C
        let karplusA = 10.4   // Hz
        let karplusB = 1.5    // Hz
        let karplusC = 0.2    // Hz

        // Estimate J-couplings from spectral splitting patterns
        let jAnti = karplusA * 1.0 - karplusB * (-1.0) + karplusC    // phi=180 degrees
        let jGauche = karplusA * 0.25 - karplusB * 0.5 + karplusC    // phi=60 degrees
        let jCis = karplusA * 1.0 - karplusB * 1.0 + karplusC        // phi=0 degrees

        // Aromatic region J (ortho ~7.5, meta ~1.5, para ~0.5 Hz)
        let aromaticFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 6.5 && $0.0 <= 8.5 }.map { $0.1 }.reduce(0, +) / tot : 0

        // Aliphatic splitting pattern complexity
        let aliphaticRegion = zip(grid, a).filter { $0.0 >= 0.5 && $0.0 <= 4.5 }.map { $0.1 }
        let aliphaticVariance = variance(aliphaticRegion)

        // Estimate number of coupled spin systems
        let coupledSystems = Double(peakPPMs.count)
        let avgPeakSeparation = peakPPMs.count >= 2 ?
            (peakPPMs.max()! - peakPPMs.min()!) / Double(peakPPMs.count - 1) : 0

        d["karplus_j_anti_Hz"] = jAnti
        d["karplus_j_gauche_Hz"] = jGauche
        d["karplus_j_cis_Hz"] = jCis
        d["karplus_j_ortho_Hz"] = 7.5 * aromaticFrac  // weighted by aromatic content
        d["karplus_j_meta_Hz"] = 1.5 * aromaticFrac
        d["karplus_j_para_Hz"] = 0.5 * aromaticFrac
        d["karplus_coupled_systems"] = coupledSystems
        d["karplus_avg_separation_ppm"] = avgPeakSeparation
        d["karplus_aliphatic_complexity"] = aliphaticVariance
        d["karplus_aromatic_coupling_weight"] = aromaticFrac

        // -- Spectral Density Function Values (6 features) --
        let jHalfOmega = spectralDensity(omega / 2.0)
        let j3Omega = spectralDensity(3.0 * omega)
        let jOmegaH_plus_omegaC = spectralDensity(omega + gammaC / gammaH * omega)
        let jOmegaH_minus_omegaC = spectralDensity(omega - gammaC / gammaH * omega)

        d["sdf_j0"] = j0
        d["sdf_j_omega"] = jOmega
        d["sdf_j_2omega"] = j2Omega
        d["sdf_j_half_omega"] = jHalfOmega
        d["sdf_j_3omega"] = j3Omega
        d["sdf_j_sum_omega_hc"] = jOmegaH_plus_omegaC

        // -- Multiplet Pattern Analysis (6 features) --
        // Analyse splitting patterns: singlet, doublet, triplet, quartet, multiplet
        let peakWidths = measurePeakWidths(a, grid: grid, threshold: 0.05)
        let avgWidth = peakWidths.isEmpty ? 0.1 : peakWidths.reduce(0, +) / Double(peakWidths.count)
        let maxWidth = peakWidths.max() ?? 0.1
        let minWidth = peakWidths.min() ?? 0.1
        let widthRatio = minWidth > 1e-9 ? maxWidth / minWidth : 1.0
        // Singlet fraction: peaks with width < 1.5x instrument linewidth
        let singletCount = peakWidths.filter { $0 < 0.08 }.count
        let multipletCount = peakWidths.filter { $0 >= 0.15 }.count

        d["multiplet_avg_width_ppm"] = avgWidth
        d["multiplet_max_width_ppm"] = maxWidth
        d["multiplet_width_ratio"] = widthRatio
        d["multiplet_singlet_fraction"] = peakWidths.isEmpty ? 0 :
            Double(singletCount) / Double(peakWidths.count)
        d["multiplet_complex_fraction"] = peakWidths.isEmpty ? 0 :
            Double(multipletCount) / Double(peakWidths.count)
        d["multiplet_peak_count"] = Double(peakWidths.count)

        return d
    }

    // MARK: - Phase 33: Quantum 13C NMR Features (43 features)

    /// Computes 43 quantum-mechanical features for a 13C NMR spectrum.
    ///
    /// Features cover:
    /// - CSA tensor analysis for carbon environments (7)
    /// - T1 dipolar relaxation (C-H) (7)
    /// - NOE (heteronuclear 1H->13C) (5)
    /// - DEPT editing simulation (8)
    /// - J_CC coupling constants (6)
    /// - Carbon hybridisation indicators (5)
    /// - Spectral density for heteronuclear (5)
    ///
    /// - Parameters:
    ///   - spectrum: The 250-bin 13C spectrum (0–249 ppm at 1 ppm steps).
    ///   - peakPositions: Detected peak positions in ppm.
    ///   - fieldStrengthT: Static magnetic field in Tesla (default 14.1 T).
    ///   - correlationTimeNs: Rotational correlation time in nanoseconds (default 1.0 ns).
    /// - Returns: Dictionary with 43 named quantum features.
    nonisolated static func quantumC13Features(
        spectrum: [Float],
        peakPositions: [Double],
        fieldStrengthT: Double = 14.1,
        correlationTimeNs: Double = 1.0
    ) -> [String: Double] {
        var d: [String: Double] = [:]
        let grid = (0...249).map { Double($0) }
        let a = spectrum.map { Double($0) }
        let tot = a.reduce(0, +)

        let omegaC = gammaC * fieldStrengthT
        let omegaH = gammaH * fieldStrengthT
        let tauC = correlationTimeNs * 1e-9

        func spectralDensity(_ w: Double) -> Double {
            2.0 * tauC / (1.0 + w * w * tauC * tauC)
        }

        // -- CSA Tensor for Carbon Environments (7 features) --
        // 13C CSA is much larger than 1H: sp3 ~ 20-40 ppm, sp2 ~ 150-200 ppm, C=O ~ 200+ ppm
        let aliphaticFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 0 && $0.0 <= 50 }.map { $0.1 }.reduce(0, +) / tot : 0.5
        let aromaticFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 110 && $0.0 <= 160 }.map { $0.1 }.reduce(0, +) / tot : 0
        let carbonylFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 165 && $0.0 <= 249 }.map { $0.1 }.reduce(0, +) / tot : 0

        // Weighted average CSA based on carbon types
        let csaSp3: Double = 30.0    // ppm, typical aliphatic
        let csaSp2: Double = 170.0   // ppm, typical aromatic/alkene
        let csaCO: Double = 220.0    // ppm, carbonyl
        let avgCSA = csaSp3 * aliphaticFrac + csaSp2 * aromaticFrac + csaCO * carbonylFrac

        let csaSigma11 = avgCSA * 0.6
        let csaSigma22 = avgCSA * 0.3
        let csaSigma33 = avgCSA * 0.1
        let csaIso = (csaSigma11 + csaSigma22 + csaSigma33) / 3.0
        let csaDelta = csaSigma11 - csaIso
        let csaEta = abs(csaDelta) > 1e-9 ? (csaSigma22 - csaSigma33) / csaDelta : 0

        d["csa_c_isotropic_ppm"] = csaIso
        d["csa_c_anisotropy_delta"] = csaDelta
        d["csa_c_asymmetry_eta"] = min(max(csaEta, 0), 1)
        d["csa_c_sigma11_ppm"] = csaSigma11
        d["csa_c_sigma22_ppm"] = csaSigma22
        d["csa_c_sigma33_ppm"] = csaSigma33
        d["csa_c_weighted_avg_ppm"] = avgCSA

        // -- T1 Dipolar Relaxation C-H (7 features) --
        let rCH = 1.09e-10   // C-H bond length in meters
        let bCH = (mu0 / (4.0 * .pi)) * gammaC * gammaH * hbar / (rCH * rCH * rCH)
        let bCHsq = bCH * bCH

        let jDiffOmega = spectralDensity(omegaH - omegaC)
        let jOmegaC = spectralDensity(omegaC)
        let jSumOmega = spectralDensity(omegaH + omegaC)
        let j0 = spectralDensity(0)
        let jOmegaH = spectralDensity(omegaH)

        // T1 for 13C due to C-H dipolar (assuming 1 directly bonded H)
        let r1CH = (bCHsq / 4.0) * (jDiffOmega + 3.0 * jOmegaC + 6.0 * jSumOmega)
        let t1CH_1H = r1CH > 1e-30 ? 1.0 / r1CH : 100.0

        // T1 for CH2 (2 protons)
        let t1CH2 = r1CH > 1e-30 ? 1.0 / (2.0 * r1CH) : 100.0
        // T1 for CH3 (3 protons, plus extra rotation)
        let t1CH3 = r1CH > 1e-30 ? 1.0 / (3.0 * r1CH * 0.8) : 100.0  // 0.8 factor for internal rotation

        // CSA contribution to T1 for carbon
        let csaRadC = avgCSA * 1e-6 * omegaC
        let r1CSA_C = (2.0 / 15.0) * csaRadC * csaRadC * jOmegaC
        let t1Total_C = (r1CH + r1CSA_C) > 1e-30 ? 1.0 / (r1CH + r1CSA_C) : 100.0

        // T2 for 13C
        let r2CH = (bCHsq / 8.0) * (4.0 * j0 + jDiffOmega + 3.0 * jOmegaC + 6.0 * jOmegaH + 6.0 * jSumOmega)
        let t2CH = r2CH > 1e-30 ? 1.0 / r2CH : 100.0

        d["relax_c_t1_ch_s"] = min(t1CH_1H, 100)
        d["relax_c_t1_ch2_s"] = min(t1CH2, 100)
        d["relax_c_t1_ch3_s"] = min(t1CH3, 100)
        d["relax_c_t1_csa_fraction"] = r1CSA_C / max(r1CH + r1CSA_C, 1e-30)
        d["relax_c_t1_total_s"] = min(t1Total_C, 100)
        d["relax_c_t2_s"] = min(t2CH, 100)
        d["relax_c_correlation_time_ns"] = correlationTimeNs

        // -- NOE Heteronuclear 1H->13C (5 features) --
        // Maximum NOE for 13C{1H}: gamma_H / (2 * gamma_C) ~ 1.988
        let sigmaHC = (bCHsq / 4.0) * (6.0 * jSumOmega - jDiffOmega)
        let rhoHC = (bCHsq / 4.0) * (jDiffOmega + 3.0 * jOmegaC + 6.0 * jSumOmega)
        let noeHC = rhoHC > 1e-30 ? 1.0 + (gammaH / gammaC) * (sigmaHC / rhoHC) : 1.0
        let noeMax = 1.0 + gammaH / (2.0 * gammaC)  // ~2.988 theoretical max
        let noeEfficiency = (noeHC - 1.0) / max(noeMax - 1.0, 1e-9)
        // In slow tumbling regime, NOE can become negative (undesirable)
        let noeIsNegative = noeHC < 1.0 ? 1.0 : 0.0

        d["noe_c_enhancement"] = noeHC
        d["noe_c_max_theoretical"] = noeMax
        d["noe_c_efficiency"] = min(max(noeEfficiency, -1), 1)
        d["noe_c_is_negative"] = noeIsNegative
        d["noe_c_cross_relax_rate"] = sigmaHC

        // -- DEPT Editing Simulation (8 features) --
        // DEPT pulse angle determines which CH multiplicities appear:
        //   DEPT-45: CH, CH2, CH3 all positive
        //   DEPT-90: CH only
        //   DEPT-135: CH positive, CH2 negative, CH3 positive, C quaternary absent
        // Estimate fractions from peak regions
        let quarternaryCarbonPPMs = peakPositions.filter { $0 >= 125 && $0 <= 145 }
        let chPPMs = peakPositions.filter { ($0 >= 60 && $0 <= 80) || ($0 >= 115 && $0 <= 140) }
        let ch2PPMs = peakPositions.filter { $0 >= 20 && $0 <= 45 }
        let ch3PPMs = peakPositions.filter { $0 >= 8 && $0 <= 25 }

        let totalPeaks = max(Double(peakPositions.count), 1.0)
        let quatFrac = Double(quarternaryCarbonPPMs.count) / totalPeaks
        let chFrac = Double(chPPMs.count) / totalPeaks
        let ch2Frac = Double(ch2PPMs.count) / totalPeaks
        let ch3Frac = Double(ch3PPMs.count) / totalPeaks

        // DEPT-135 simulated total intensity (CH+CH3 positive, CH2 negative)
        let dept135Intensity = chFrac + ch3Frac - ch2Frac
        // DEPT-90 simulated intensity (CH only)
        let dept90Intensity = chFrac
        // Edited subspectrum: quaternary C fraction (absent from all DEPT)
        let dept45Intensity = chFrac + ch2Frac + ch3Frac

        d["dept_quaternary_fraction"] = quatFrac
        d["dept_ch_fraction"] = chFrac
        d["dept_ch2_fraction"] = ch2Frac
        d["dept_ch3_fraction"] = ch3Frac
        d["dept_135_intensity"] = dept135Intensity
        d["dept_90_intensity"] = dept90Intensity
        d["dept_45_intensity"] = dept45Intensity
        d["dept_hydrogen_deficiency"] = quatFrac + carbonylFrac

        // -- J_CC Coupling Constants (6 features) --
        // One-bond J_CC: sp3-sp3 ~35 Hz, sp2-sp2 ~70 Hz, sp-sp ~170 Hz
        // Correlate with hybridisation fraction
        let jCC_sp3: Double = 35.0  // Hz
        let jCC_sp2: Double = 70.0  // Hz
        let jCC_sp: Double = 170.0  // Hz

        // sp fraction from acetylenic region (65-90 ppm)
        let spFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 65 && $0.0 <= 90 }.map { $0.1 }.reduce(0, +) / tot : 0

        let avgJCC = jCC_sp3 * aliphaticFrac + jCC_sp2 * aromaticFrac + jCC_sp * spFrac
        let jCH_sp3: Double = 125.0   // one-bond J_CH for sp3 carbon
        let jCH_sp2: Double = 160.0   // sp2 carbon
        let jCH_sp: Double = 250.0    // sp carbon
        let avgJCH = jCH_sp3 * aliphaticFrac + jCH_sp2 * aromaticFrac + jCH_sp * spFrac

        d["jcc_avg_Hz"] = avgJCC
        d["jcc_sp3_weight"] = aliphaticFrac * jCC_sp3
        d["jcc_sp2_weight"] = aromaticFrac * jCC_sp2
        d["jch_avg_Hz"] = avgJCH
        d["jch_sp3_component"] = aliphaticFrac * jCH_sp3
        d["jch_sp2_component"] = aromaticFrac * jCH_sp2

        // -- Carbon Hybridisation Indicators (5 features) --
        let sp3Carbon = aliphaticFrac
        let sp2Carbon = aromaticFrac + carbonylFrac
        let spCarbon = spFrac
        let oxygenatedFrac = tot > 0 ?
            zip(grid, a).filter { $0.0 >= 50 && $0.0 <= 90 }.map { $0.1 }.reduce(0, +) / tot : 0
        let hybridisationIndex = 3.0 * sp3Carbon + 2.0 * sp2Carbon + 1.0 * spCarbon

        d["hyb_sp3_fraction"] = sp3Carbon
        d["hyb_sp2_fraction"] = sp2Carbon
        d["hyb_sp_fraction"] = spCarbon
        d["hyb_oxygenated_fraction"] = oxygenatedFrac
        d["hyb_index"] = hybridisationIndex

        // -- Spectral Density for Heteronuclear (5 features) --
        d["sdf_c_j0"] = j0
        d["sdf_c_j_omega_c"] = jOmegaC
        d["sdf_c_j_omega_h"] = jOmegaH
        d["sdf_c_j_diff"] = jDiffOmega
        d["sdf_c_j_sum"] = jSumOmega

        return d
    }

    // MARK: - 1H NMR

    func synthesizeProton(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            var s = [Float](repeating: 0, count: gridPPM1H.count)
            addPeak(&s, grid: gridPPM1H, center: 0.90, area: 3.0)
            addPeak(&s, grid: gridPPM1H, center: 1.25, area: Float.random(in: 4...20))

            let groups = Array(shoolery.keys.shuffled().prefix(Int.random(in: 1...3)))
            for g in groups {
                let shift = 1.25 + (shoolery[g] ?? 0)
                addPeak(&s, grid: gridPPM1H, center: shift, area: Float.random(in: 1...3))
            }
            s = s.map { $0 + Float.random(in: 0...0.002) }

            let a = s.map { Double($0) }
            let tot = a.reduce(0, +)
            let aroFrac = tot > 0 ? zip(gridPPM1H, a).filter { $0.0 >= 6.5 && $0.0 <= 8.5 }.map { $0.1 }.reduce(0, +) / tot : 0
            let aldPresent = (zip(gridPPM1H, a).filter { $0.0 > 9.0 }.map { $0.1 }.max() ?? 0) > 0.05 ? 1.0 : 0.0

            var derived: [String: Double] = [
                "aromatic_proton_fraction": aroFrac,
                "aldehyde_present": aldPresent,
            ]

            // Phase 32: quantum NMR features (48)
            let fieldT = Double.random(in: 9.4...21.1)  // 400-900 MHz instruments
            let tauCNs = Double.random(in: 0.1...5.0)
            let quantum = NMRSynthesizer.quantumNMRFeatures(
                spectrum: s,
                fieldStrengthT: fieldT,
                correlationTimeNs: tauCNs,
                temperatureK: Double.random(in: 273...323)
            )
            for (k, v) in quantum { derived[k] = v }

            var features = s
            features.append(Float(aroFrac))
            features.append(Float(aldPresent))
            // Append quantum features in sorted key order for reproducibility
            for (_, v) in quantum.sorted(by: { $0.key < $1.key }) {
                features.append(Float(v))
            }
            while features.count < SpectralModality.nmrProton.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.nmrProton.featureCount))

            records.append(TrainingRecord(
                modality: .nmrProton, sourceID: "synth_shoolery",
                features: features, targets: derived, metadata: ["groups": groups.joined(separator: ",")],
                isComputedLabel: true, computationMethod: "Shoolery_Karplus_Quantum"))
        }
        return records
    }

    // MARK: - 13C NMR

    func synthesizeCarbon(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            var s = [Float](repeating: 0, count: gridPPM13C.count)
            let numPeaks = Int.random(in: 3...15)
            var peakPositions: [Double] = []
            for _ in 0..<numPeaks {
                let region = Int.random(in: 0...3)
                let ppm: Double
                switch region {
                case 0: ppm = Double.random(in: 0...50)     // aliphatic
                case 1: ppm = Double.random(in: 50...90)    // O-bearing
                case 2: ppm = Double.random(in: 110...160)  // aromatic
                default: ppm = Double.random(in: 165...220) // carbonyl
                }
                peakPositions.append(ppm)
                addPeak(&s, grid: gridPPM13C, center: ppm, area: Float.random(in: 0.5...2.0))
            }
            s = s.map { $0 + Float.random(in: 0...0.001) }

            let a = s.map { Double($0) }
            let tot = a.reduce(0, +)
            let aromatic = tot > 0 ? zip(gridPPM13C, a).filter { $0.0 >= 110 && $0.0 <= 160 }.map { $0.1 }.reduce(0, +) / tot : 0
            let carbonyl = peakPositions.filter { $0 >= 165 }.count

            var derived: [String: Double] = [
                "aromatic_fraction": aromatic,
                "carbonyl_count_est": Double(carbonyl),
                "unique_peaks_est": Double(numPeaks),
            ]

            // Phase 33: quantum 13C features (43)
            let fieldT = Double.random(in: 9.4...21.1)
            let tauCNs = Double.random(in: 0.5...10.0)
            let quantum = NMRSynthesizer.quantumC13Features(
                spectrum: s,
                peakPositions: peakPositions,
                fieldStrengthT: fieldT,
                correlationTimeNs: tauCNs
            )
            for (k, v) in quantum { derived[k] = v }

            var features = s
            for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
            // Append quantum features in sorted key order
            for (_, v) in quantum.sorted(by: { $0.key < $1.key }) {
                features.append(Float(v))
            }
            while features.count < SpectralModality.nmrCarbon.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.nmrCarbon.featureCount))

            records.append(TrainingRecord(
                modality: .nmrCarbon, sourceID: "synth_grant_paul",
                features: features, targets: derived, metadata: [:],
                isComputedLabel: true, computationMethod: "GrantPaul_13C_Quantum"))
        }
        return records
    }

    // MARK: - Helpers

    private func addPeak(_ s: inout [Float], grid: [Double], center: Double, area: Float) {
        for (i, ppm) in grid.enumerated() {
            let dx = ppm - center
            let lorentz = lw / (2 * .pi) / (dx * dx + (lw / 2) * (lw / 2))
            s[i] += area * Float(lorentz * 0.05)
        }
    }

    // MARK: - Static Helpers for Quantum Features

    /// Find peak positions above a threshold in a spectrum.
    private nonisolated static func findPeakPositions(
        _ a: [Double], grid: [Double], threshold: Double
    ) -> [Double] {
        let maxVal = a.max() ?? 1.0
        guard maxVal > 1e-12 else { return [] }
        let norm = a.map { $0 / maxVal }
        var peaks: [Double] = []
        for i in 1..<(norm.count - 1) {
            if norm[i] > threshold && norm[i] > norm[i - 1] && norm[i] > norm[i + 1] {
                peaks.append(grid[i])
            }
        }
        return peaks
    }

    /// Measure approximate FWHM of each peak.
    private nonisolated static func measurePeakWidths(
        _ a: [Double], grid: [Double], threshold: Double
    ) -> [Double] {
        let maxVal = a.max() ?? 1.0
        guard maxVal > 1e-12 else { return [] }
        let norm = a.map { $0 / maxVal }
        var widths: [Double] = []
        for i in 1..<(norm.count - 1) {
            guard norm[i] > threshold && norm[i] > norm[i - 1] && norm[i] > norm[i + 1] else { continue }
            let halfMax = norm[i] / 2.0
            // Search left for half-max crossing
            var leftIdx = i
            while leftIdx > 0 && norm[leftIdx] > halfMax { leftIdx -= 1 }
            // Search right for half-max crossing
            var rightIdx = i
            while rightIdx < norm.count - 1 && norm[rightIdx] > halfMax { rightIdx += 1 }
            let fwhm = grid[rightIdx] - grid[leftIdx]
            if fwhm > 0 { widths.append(fwhm) }
        }
        return widths
    }

    /// Compute variance of an array of doubles.
    private nonisolated static func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }
        let mean = values.reduce(0, +) / Double(values.count)
        let sumSqDiff = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return sumSqDiff / Double(values.count - 1)
    }
}
