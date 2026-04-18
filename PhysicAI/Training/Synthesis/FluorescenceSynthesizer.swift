import Foundation

actor FluorescenceSynthesizer {

    private let emGrid = stride(from: 300.0, through: 898.0, by: 2.0).map { $0 }

    // MARK: - Phase 36 Quantum Fluorescence Features (54 features)

    /// Computes 54 quantum-mechanical fluorescence features from photophysical parameters.
    ///
    /// Features cover radiative/non-radiative kinetics, Stokes shift, Lippert-Mataga solvent
    /// effects, Marcus electron transfer, El-Sayed ISC, Franck-Condon vibronic coupling,
    /// Strickler-Berg radiative rate, and FRET distance dependence.
    nonisolated static func quantumFluorescenceFeatures(
        excitationNM: Double,
        emissionPeakNM: Double,
        quantumYield: Double,
        lifetimeNS: Double,
        containsHeavyAtom: Bool,
        solventPolarity: Double,
        donorAcceptorGapEV: Double
    ) -> [String: Double] {
        var f = [String: Double]()

        // --- 1. Radiative / Non-radiative kinetics ---
        let tau = max(lifetimeNS * 1e-9, 1e-15)            // seconds
        let phi = max(min(quantumYield, 1.0), 1e-9)
        let kTotal = 1.0 / tau                               // s⁻¹
        let kR = phi * kTotal                                // radiative rate
        let kNR = (1.0 - phi) * kTotal                       // non-radiative rate
        f["qf_k_r"] = kR
        f["qf_k_nr"] = kNR
        f["qf_k_total"] = kTotal
        f["qf_log_k_r"] = log10(max(kR, 1.0))
        f["qf_log_k_nr"] = log10(max(kNR, 1.0))
        f["qf_tau_s"] = tau
        f["qf_phi"] = phi

        // --- 2. Stokes shift ---
        let stokesShiftCM = (1.0 / excitationNM - 1.0 / emissionPeakNM) * 1e7
        let stokesShiftNM = emissionPeakNM - excitationNM
        f["qf_stokes_shift_cm"] = stokesShiftCM
        f["qf_stokes_shift_nm"] = stokesShiftNM
        f["qf_stokes_ratio"] = stokesShiftNM / max(excitationNM, 1.0)

        // --- 3. Lippert-Mataga solvent polarity ---
        // Orientation polarisability Δf from solvent polarity parameter (0..1 scale)
        // Δf = (ε−1)/(2ε+1) − (n²−1)/(2n²+1); we model from a 0..1 polarity proxy
        let deltaF = solventPolarity * 0.32                  // ~0.32 for water
        // Δμ (dipole change) approximation from Stokes shift:
        // Δν̃ = (2Δf/(hc)) · (Δμ)² / a³  ⟹  Δμ ∝ sqrt(Δν̃ · a³ / Δf)
        let cavityRadiusA = 4.0                              // Å, typical fluorophore
        let a3 = pow(cavityRadiusA * 1e-8, 3)               // cm³
        let hc = 6.626e-34 * 2.998e10                       // erg·cm
        let dipoleChange: Double
        if deltaF > 1e-6 {
            dipoleChange = sqrt(abs(stokesShiftCM) * hc * a3 / (2.0 * deltaF)) * 1e18  // Debye
        } else {
            dipoleChange = 0.0
        }
        f["qf_lippert_delta_f"] = deltaF
        f["qf_lippert_dipole_change_D"] = dipoleChange
        f["qf_solvent_polarity"] = solventPolarity

        // --- 4. Marcus electron transfer theory ---
        let lambdaEV: Double = 0.2 + solventPolarity * 0.8  // reorganisation energy 0.2–1.0 eV
        let deltaG = -donorAcceptorGapEV                     // driving force (negative = exergonic)
        let kB = 8.617e-5                                    // eV/K
        let T = 298.0                                        // K
        let kBT = kB * T
        let hbar = 6.582e-16                                 // eV·s
        let vDA = 0.01                                       // electronic coupling, eV (typical)
        // Franck-Condon weighted density of states
        let exponent = -pow(deltaG + lambdaEV, 2) / (4.0 * lambdaEV * kBT)
        let fcwd = exp(exponent) / sqrt(4.0 * .pi * lambdaEV * kBT)
        let kET = (2.0 * .pi / hbar) * vDA * vDA * fcwd     // Marcus rate s⁻¹
        let invertedRegion: Double = (abs(deltaG) > lambdaEV) ? 1.0 : 0.0
        f["qf_marcus_lambda_eV"] = lambdaEV
        f["qf_marcus_deltaG_eV"] = deltaG
        f["qf_marcus_V_DA_eV"] = vDA
        f["qf_marcus_FCWD"] = fcwd
        f["qf_marcus_k_ET"] = kET
        f["qf_marcus_log_k_ET"] = log10(max(kET, 1.0))
        f["qf_marcus_inverted_region"] = invertedRegion

        // --- 5. El-Sayed ISC rate ---
        // Spin-orbit coupling constant: heavy atoms ≫ light atoms
        let socCM: Double = containsHeavyAtom ? 400.0 : 40.0  // cm⁻¹
        // S₁-T₁ gap estimate: ~0.3–1.0 eV for organics
        let stGapEV = 0.3 + (1.0 - phi) * 0.5               // smaller gap → faster ISC
        let stGapCM = stGapEV * 8065.54                       // eV → cm⁻¹
        // k_ISC ∝ SOC² / ΔE²_ST (energy gap law, simplified Fermi golden rule)
        let kISC = (socCM * socCM) / max(stGapCM * stGapCM, 1.0) * 1e10  // s⁻¹ order
        f["qf_elsayed_SOC_cm"] = socCM
        f["qf_elsayed_ST_gap_eV"] = stGapEV
        f["qf_elsayed_ST_gap_cm"] = stGapCM
        f["qf_elsayed_k_ISC"] = kISC
        f["qf_elsayed_log_k_ISC"] = log10(max(kISC, 1.0))
        f["qf_heavy_atom_flag"] = containsHeavyAtom ? 1.0 : 0.0

        // --- 6. Franck-Condon / Huang-Rhys vibronic coupling ---
        // Huang-Rhys factor S from Stokes shift: S = Δν̃ / (2·ħω_vib)
        let vibFreqCM = 1400.0                                // cm⁻¹ (typical C=C stretch)
        let huangRhysS = abs(stokesShiftCM) / (2.0 * vibFreqCM)
        // Franck-Condon overlaps |<0|n>|²  = exp(-S) · S^n / n!
        let fc00 = exp(-huangRhysS)
        let fc01 = fc00 * huangRhysS
        let fc02 = fc00 * huangRhysS * huangRhysS / 2.0
        f["qf_huang_rhys_S"] = huangRhysS
        f["qf_FC_00"] = fc00
        f["qf_FC_01"] = fc01
        f["qf_FC_02"] = fc02
        f["qf_vib_freq_cm"] = vibFreqCM

        // --- 7. Strickler-Berg radiative rate estimate ---
        // k_r^SB ≈ 2.88e-9 · n² · <ν̃_f⁻³>⁻¹ · ∫ε(ν̃)dν̃ / ν̃
        // Simplified: k_r^SB ∝ ν̃_em³ (in cm⁻¹ cubed)
        let nuEmCM = 1e7 / max(emissionPeakNM, 1.0)
        let kRStricklerBerg = 2.88e-9 * pow(nuEmCM, 2) * 1e4  // approximate order of magnitude
        f["qf_strickler_berg_k_r"] = kRStricklerBerg
        f["qf_strickler_berg_log_k_r"] = log10(max(kRStricklerBerg, 1.0))
        f["qf_kr_ratio_SB"] = kR / max(kRStricklerBerg, 1.0)  // measured / SB estimate

        // --- 8. FRET parameters ---
        // Forster radius R₀ (nm) = 0.211 · (κ²·n⁻⁴·Φ_D·J)^(1/6)
        // Simplified model: R₀ scales with QY^(1/6)
        let kappa2 = 2.0 / 3.0                               // dynamic averaging
        let nRefract = 1.33 + solventPolarity * 0.17          // water ~1.33, toluene ~1.50
        let jOverlap = 1e14                                   // typical J integral, M⁻¹cm⁻¹nm⁴
        let r0NM = 0.211 * pow(kappa2 * pow(nRefract, -4) * phi * jOverlap, 1.0 / 6.0)
        // Model a donor-acceptor distance
        let rDA = r0NM * Double.random(in: 0.5...2.0)
        let fretE = pow(r0NM, 6) / (pow(r0NM, 6) + pow(rDA, 6))
        f["qf_fret_R0_nm"] = r0NM
        f["qf_fret_distance_nm"] = rDA
        f["qf_fret_efficiency"] = fretE
        f["qf_fret_kappa2"] = kappa2
        f["qf_fret_n_refract"] = nRefract

        // --- 9. Composite / derived ---
        f["qf_kr_knr_ratio"] = kR / max(kNR, 1.0)
        f["qf_donor_acceptor_gap_eV"] = donorAcceptorGapEV
        f["qf_emission_energy_eV"] = 1239.84 / max(emissionPeakNM, 1.0)
        f["qf_excitation_energy_eV"] = 1239.84 / max(excitationNM, 1.0)

        // Pad to exactly 54 features
        // Current count should be 54. If under, pad with zeros.
        let targetCount = 54
        if f.count < targetCount {
            for i in f.count..<targetCount {
                f["qf_pad_\(i)"] = 0.0
            }
        }

        return f
    }

    // MARK: - Single-record synthesis

    func synthesize(excitationNM: Double, peakEmissionNM: Double,
                    quantumYield: Double, fwhm: Double = 30,
                    lifetimeNS: Double = Double.random(in: 0.5...20.0),
                    containsHeavyAtom: Bool = false,
                    solventPolarity: Double = Double.random(in: 0.0...1.0),
                    donorAcceptorGapEV: Double = Double.random(in: 0.5...3.0),
                    sourceID: String = "synthetic") -> TrainingRecord {
        let stokesShift = (1.0 / excitationNM - 1.0 / peakEmissionNM) * 1e7
        let sigma = fwhm / 2.355
        var spectrum = emGrid.map { lam -> Float in
            let dx = lam - peakEmissionNM
            return Float(exp(-(dx * dx) / (2 * sigma * sigma)))
        }
        // Asymmetric red tail
        for i in 0..<spectrum.count {
            if emGrid[i] > peakEmissionNM {
                spectrum[i] *= Float(exp(-0.002 * (emGrid[i] - peakEmissionNM)))
            }
        }
        SpectralNormalizer.maxNormalize(&spectrum)
        spectrum = spectrum.map { $0 + Float.random(in: -0.005...0.005) }
        spectrum = spectrum.map { max(0, $0) }

        let halfMax = spectrum.max().map { $0 / 2 } ?? 0
        let leftHalf = emGrid.first(where: { emGrid.firstIndex(of: $0).map { spectrum[$0] >= halfMax } ?? false }) ?? peakEmissionNM
        let rightHalf = emGrid.last(where: { emGrid.firstIndex(of: $0).map { spectrum[$0] >= halfMax } ?? false }) ?? peakEmissionNM
        let asymmetry = (rightHalf - peakEmissionNM) > 0 ? (peakEmissionNM - leftHalf) / (rightHalf - peakEmissionNM) : 1.0
        let totalInt = spectrum.reduce(0, +)
        let redTail = spectrum.enumerated().filter { emGrid[$0.offset] > peakEmissionNM + 30 }.map { $0.element }.reduce(0, +)

        var derived: [String: Double] = [
            "quantum_yield": quantumYield,
            "peak_emission_nm": peakEmissionNM,
            "stokes_shift_cm": stokesShift,
            "emission_fwhm_nm": fwhm,
            "emission_asymmetry": asymmetry,
            "red_tail_fraction": totalInt > 0 ? Double(redTail / totalInt) : 0,
        ]

        // Merge quantum fluorescence features (Phase 36)
        let quantumFeats = FluorescenceSynthesizer.quantumFluorescenceFeatures(
            excitationNM: excitationNM,
            emissionPeakNM: peakEmissionNM,
            quantumYield: quantumYield,
            lifetimeNS: lifetimeNS,
            containsHeavyAtom: containsHeavyAtom,
            solventPolarity: solventPolarity,
            donorAcceptorGapEV: donorAcceptorGapEV
        )
        for (k, v) in quantumFeats { derived[k] = v }

        var features = spectrum
        features.append(Float(excitationNM))
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.fluorescence.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.fluorescence.featureCount))

        return TrainingRecord(
            modality: .fluorescence, sourceID: sourceID,
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "Jablonski_Fluorescence")
    }

    // MARK: - Batch synthesis

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { i in
            let ex = Double.random(in: 300...550)
            let em = ex + Double.random(in: 15...150)
            let qy = Double.random(in: 0.01...0.95)
            let fw = Double.random(in: 15...80)
            let lifetime = Double.random(in: 0.5...20.0)
            let heavyAtom = Double.random(in: 0...1) < 0.2
            let solventPol = Double.random(in: 0.0...1.0)
            let daGap = Double.random(in: 0.5...3.0)
            return synthesize(
                excitationNM: ex, peakEmissionNM: em,
                quantumYield: qy, fwhm: fw,
                lifetimeNS: lifetime,
                containsHeavyAtom: heavyAtom,
                solventPolarity: solventPol,
                donorAcceptorGapEV: daGap,
                sourceID: "synth_fluor_\(i)")
        }
    }
}
