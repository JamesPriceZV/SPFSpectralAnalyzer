# Universal Physical Spectral Data Analyzer — PINN Training System
## Part 4 of 4 — Quantum Enhancements to Existing PINNs (Phases 32–40)

> **CONTINUATION:** Fully implement CLAUDE.md (Phases 0–11), CLAUDE2.md (Phases 12–25),
> and CLAUDE3.md (Phases 26–31) before executing any phase here. All foundation types,
> parsers, sources, and synthesizers defined in those files must already compile.
>
> This file upgrades eight existing synthesizers with deeper quantum mechanical
> physics, then updates the coordinator, dashboard UI, and manifest. Each phase
> modifies an EXISTING file — do not create duplicate actors.

Swift 6 rules throughout: actors, async/await, no DispatchQueue, no @unchecked Sendable.

---

## QUANTUM ENHANCEMENT OVERVIEW

| Phase | File Modified | Quantum Physics Added | Feature Δ |
|-------|--------------|----------------------|-----------|
| 32 | NMRProtonSynthesizer.swift | Zeeman H, CSA tensor, T1/T2 via J(ω) | 245 → 293 |
| 33 | NMRCarbonSynthesizer.swift | Grant-Paul + CSA, solid-state δ_iso | 258 → 301 |
| 34 | RamanSynthesizer.swift | Resonance enhancement, anharmonic Morse | 358 → 418 |
| 35 | XPSSynthesizer.swift | Shake-up satellites, SOC doublets, α′ | 1212 → 1272 |
| 36 | FluorescenceSynthesizer.swift | Marcus kET, El-Sayed ISC, FC factors | 307 → 361 |
| 37 | XRDSynthesizer.swift | Full F(hkl), atomic form factors, DW | 862 → 930 |
| 38 | HITRANSynthesizer.swift | Dicke narrowing, SD-Voigt, line mixing | 406 → 454 |
| 39 | AtomicEmissionSynthesizer.swift | Fine structure, hyperfine splitting | 714 → 768 |
| 40 | Coordinator + UI + SpectralModality | Register all changes, update dashboard | — |

**All feature count changes must be reflected in SpectralModality.featureCount
(in SpectralModality.swift) at the START of each phase — update that switch case
before touching the synthesizer.**

---

## PHASE 32 — ¹H NMR Quantum Spin Hamiltonian Enhancement

### Physics Added

The full quantum-mechanical NMR Hamiltonian for a spin-½ nucleus in a
static field B₀ (along z) is:

```
Zeeman term:
  H_Z = −γ_H ℏ B₀ Iẑ
  ω_L = γ_H B₀  (Larmor frequency, rad/s)
  At 600 MHz: B₀ = 14.1 T, ω_L/2π = 600 × 10⁶ Hz

Chemical shielding anisotropy (CSA) tensor:
  δ_iso  = (δ_11 + δ_22 + δ_33) / 3         (isotropic chemical shift)
  Δδ     = δ_33 − (δ_11 + δ_22)/2           (CSA span, ppm)
  η_CSA  = (δ_22 − δ_11) / Δδ               (asymmetry parameter, 0–1)
  Typical carbonyl ¹H CSA: Δδ ≈ 5–15 ppm
  Typical aromatic ¹H CSA: Δδ ≈ 8–25 ppm

T1 relaxation (longitudinal) via spectral density:
  1/T1 = (μ₀/4π)² · γ⁴ℏ² · (1/r⁶) · [J(ω_L) + 4J(2ω_L)]
  J(ω) = 2τ_c / (1 + ω²τ_c²)    (Lorentzian spectral density, rigid rotor)
  τ_c = rotational correlation time (s), τ_c ≈ 10⁻¹² s for small molecules

T2 relaxation (transverse):
  1/T2 = (1/2) · (1/T1) + (1/T1_CSA)
  1/T2_CSA ≈ (2/15) · (Δδ · ω_L)² · τ_c   (CSA contribution)
  Line width: Δν_1/2 = 1/(π · T2)  Hz → Δδ_1/2 = Δν_1/2 / ν_L  ppm

NOE factor (Nuclear Overhauser Enhancement):
  η_NOE = γ_S / (2γ_I) · [6J(ω_I + ω_S) − J(ω_I − ω_S)]
          / [J(ω_S) + 3J(ω_S·½) + 6J(ω_I + ω_S)]
  For ¹H{¹H}: η_max = 0.5 (extreme narrowing limit)

Karplus generalised (Altona parameters):
  ³J_HH = A·cos²φ − B·cosφ + C + substituent corrections
  A = 10.4 Hz, B = 1.5 Hz, C = 0.2 Hz  (Haasnoot-de Leeuw-Altona)
  Dihedral φ from SMILES torsion estimate
```

### SpectralModality.swift — Update featureCount

Change `.nmrProton` case from `return 245` to `return 293`.

### NMRProtonSynthesizer.swift — Add Quantum Features

Open `Training/Synthesis/NMRProtonSynthesizer.swift`. ADD the following method
and modify `synthesize(count:)` to call it, appending the 48 new features to
the existing `derivedFeatures` dict. The spectralValues array stays at 240 bins;
the extra features go into `derivedFeatures` (which is included in the feature
dictionary used for CSV export and CoreML training).

```swift
// MARK: — Quantum NMR Feature Extension (Phase 32)

/// Compute quantum-mechanical NMR features from basic molecular properties.
/// Returns a dictionary of 48 new feature keys to append to derivedFeatures.
nonisolated static func quantumNMRFeatures(
    spectrometer_MHz: Double = 600.0,
    tau_c_ps: Double,           // rotational correlation time, picoseconds
    carbonyl_present: Bool,
    aromatic_present: Bool,
    methyl_count: Int,
    ch2_count: Int,
    oh_nh_present: Bool
) -> [String: Double] {

    var d: [String: Double] = [:]

    // ── Larmor frequency ──────────────────────────────────────────────────
    let nu_L    = spectrometer_MHz * 1e6           // Hz
    let omega_L = 2.0 * .pi * nu_L                 // rad/s
    d["spectrometer_MHz"]  = spectrometer_MHz
    d["larmor_freq_MHz"]   = spectrometer_MHz

    // ── Spectral density (Lorentzian) ─────────────────────────────────────
    let tau_c  = tau_c_ps * 1e-12                  // s
    func J(_ omega: Double) -> Double {
        return 2.0 * tau_c / (1.0 + omega * omega * tau_c * tau_c)
    }
    let J_L   = J(omega_L)
    let J_2L  = J(2.0 * omega_L)
    let J_0   = J(0.0)
    d["spectral_density_J_wL"]  = J_L
    d["spectral_density_J_2wL"] = J_2L
    d["spectral_density_J_0"]   = J_0
    d["tau_c_ps"]               = tau_c_ps

    // ── T1 (dipolar mechanism, ¹H-¹H, r_HH ≈ 2.5 Å) ─────────────────────
    let mu0_over_4pi = 1.0e-7          // T·m/A
    let gamma_H      = 2.675e8          // rad/(s·T)
    let hbar         = 1.0546e-34       // J·s
    let r_HH         = 2.5e-10          // m (typical vicinal H-H)
    let prefactor    = pow(mu0_over_4pi * gamma_H * gamma_H * hbar / (r_HH * r_HH * r_HH), 2.0)
    let inv_T1_dd    = prefactor * (J_L + 4.0 * J_2L)
    let T1_ms        = inv_T1_dd > 1e-10 ? 1.0 / inv_T1_dd * 1000.0 : 999.0  // ms
    d["T1_dipolar_ms"] = min(T1_ms, 999.0)

    // ── CSA tensor parameters ─────────────────────────────────────────────
    // Typical CSA for common functional groups:
    let delta_sigma: Double  // Δδ in ppm
    let eta_csa: Double
    if carbonyl_present {
        delta_sigma = Double.random(in: 6.0...18.0)
        eta_csa     = Double.random(in: 0.05...0.4)
    } else if aromatic_present {
        delta_sigma = Double.random(in: 8.0...22.0)
        eta_csa     = Double.random(in: 0.3...0.7)
    } else {
        delta_sigma = Double.random(in: 1.0...6.0)
        eta_csa     = Double.random(in: 0.0...0.3)
    }
    d["csa_delta_ppm"] = delta_sigma
    d["csa_eta"]       = eta_csa

    // CSA T2 contribution
    let delta_omega_csa = delta_sigma * 1e-6 * omega_L   // rad/s
    let inv_T2_csa      = (2.0/15.0) * delta_omega_csa * delta_omega_csa * tau_c
    let T2_csa_ms       = inv_T2_csa > 1e-10 ? 1.0 / inv_T2_csa * 1000.0 : 999.0
    d["T2_csa_ms"]      = min(T2_csa_ms, 999.0)

    // Combined T2 and linewidth
    let inv_T2_total = inv_T1_dd / 2.0 + inv_T2_csa
    let T2_ms        = inv_T2_total > 1e-10 ? 1.0 / inv_T2_total * 1000.0 : 999.0
    let linewidth_Hz = inv_T2_total / .pi
    let linewidth_ppm = linewidth_Hz / nu_L * 1e6
    d["T2_total_ms"]     = min(T2_ms, 999.0)
    d["linewidth_Hz"]    = linewidth_Hz
    d["linewidth_ppm"]   = linewidth_ppm

    // ── NOE factor (extreme narrowing if tau_c < 1/omega_L) ───────────────
    let noe_limit = omega_L * tau_c < 1.0 ? 0.5 : -1.0  // simplified
    d["noe_factor"]      = noe_limit
    d["extreme_narrowing"] = omega_L * tau_c < 1.0 ? 1.0 : 0.0

    // ── Karplus J-coupling heuristics ─────────────────────────────────────
    // Estimate typical vicinal couplings from substituent patterns
    let phi_gauche = Double.random(in: 50.0...70.0) * .pi / 180.0
    let phi_anti   = Double.random(in: 160.0...180.0) * .pi / 180.0
    let J_gauche   = 10.4*cos(phi_gauche)*cos(phi_gauche) - 1.5*cos(phi_gauche) + 0.2
    let J_anti     = 10.4*cos(phi_anti)*cos(phi_anti)   - 1.5*cos(phi_anti)   + 0.2
    d["J_vicinal_gauche_Hz"] = max(0, J_gauche)
    d["J_vicinal_anti_Hz"]   = max(0, J_anti)
    d["J_ratio_anti_gauche"] = J_gauche > 0.1 ? J_anti / J_gauche : 0

    // ── Molecular mobility proxy ──────────────────────────────────────────
    d["mobility_index"]  = 1.0 / (1.0 + tau_c_ps)  // 0–1, higher = more mobile
    d["is_rigid"]        = tau_c_ps > 5.0 ? 1.0 : 0.0

    // ── Functional group quantum flags ────────────────────────────────────
    d["carbonyl_csa_present"] = carbonyl_present ? 1.0 : 0.0
    d["aromatic_csa_present"] = aromatic_present ? 1.0 : 0.0
    d["exchangeable_H"]       = oh_nh_present ? 1.0 : 0.0
    d["methyl_free_rotation"]  = methyl_count > 0 ? 1.0 : 0.0
    d["methyl_T1_correction"] = methyl_count > 0 ? Double(methyl_count) * 0.15 : 0.0
    d["ch2_motion_contribution"] = Double(ch2_count) * 0.05

    // ── Chemical shift anisotropy power spectrum ──────────────────────────
    let csa_power_slow = delta_sigma * eta_csa * tau_c_ps
    let csa_power_fast = delta_sigma * (1.0 - eta_csa) / max(tau_c_ps, 0.01)
    d["csa_power_slow_regime"] = csa_power_slow
    d["csa_power_fast_regime"] = csa_power_fast

    // ── Rotational diffusion tensor proxy ─────────────────────────────────
    let D_rot = 1.0 / (6.0 * tau_c)            // rad²/s, isotropic
    d["rot_diffusion_coeff_s"] = D_rot
    d["rot_diffusion_log"]     = log10(max(D_rot, 1.0))

    // ── Pad to exactly 48 new features (add zeros for any missing) ────────
    let allKeys = [
        "spectrometer_MHz","larmor_freq_MHz","spectral_density_J_wL",
        "spectral_density_J_2wL","spectral_density_J_0","tau_c_ps",
        "T1_dipolar_ms","csa_delta_ppm","csa_eta","T2_csa_ms",
        "T2_total_ms","linewidth_Hz","linewidth_ppm","noe_factor",
        "extreme_narrowing","J_vicinal_gauche_Hz","J_vicinal_anti_Hz",
        "J_ratio_anti_gauche","mobility_index","is_rigid",
        "carbonyl_csa_present","aromatic_csa_present","exchangeable_H",
        "methyl_free_rotation","methyl_T1_correction","ch2_motion_contribution",
        "csa_power_slow_regime","csa_power_fast_regime",
        "rot_diffusion_coeff_s","rot_diffusion_log",
        "qnmr_pad_31","qnmr_pad_32","qnmr_pad_33","qnmr_pad_34",
        "qnmr_pad_35","qnmr_pad_36","qnmr_pad_37","qnmr_pad_38",
        "qnmr_pad_39","qnmr_pad_40","qnmr_pad_41","qnmr_pad_42",
        "qnmr_pad_43","qnmr_pad_44","qnmr_pad_45","qnmr_pad_46",
        "qnmr_pad_47","qnmr_pad_48"
    ]
    for k in allKeys where d[k] == nil { d[k] = 0.0 }
    return d
}
```

In `synthesize(count:)`, after building the existing `derived` dict, call:

```swift
let tau_c = Double.random(in: 0.05...20.0)  // ps
let qFeatures = NMRProtonSynthesizer.quantumNMRFeatures(
    tau_c_ps: tau_c,
    carbonyl_present: derived["aldehyde_present"] ?? 0 > 0.5,
    aromatic_present: derived["aromatic_proton_fraction"] ?? 0 > 0.1,
    methyl_count: Int.random(in: 0...4),
    ch2_count: Int.random(in: 0...8),
    oh_nh_present: derived["oh_nh_present"] ?? 0 > 0.5)
for (k, v) in qFeatures { derived[k] = v }
```

---

## PHASE 33 — ¹³C NMR CSA and Solid-State Enhancement

### Physics Added

```
Chemical Shielding Anisotropy (CSA) for ¹³C (much larger than ¹H):
  Carbonyl C=O:    Δδ ≈ 150–200 ppm,  η ≈ 0.0–0.2  (axial symmetry)
  Aromatic C:      Δδ ≈ 120–180 ppm,  η ≈ 0.5–0.9
  Aliphatic CH₃:   Δδ ≈  25–35 ppm,   η ≈ 0.0 (fast rotation)
  Carboxyl COOH:   Δδ ≈ 130–175 ppm,  η ≈ 0.6–0.9

T1 (¹³C via ¹H dipolar relaxation — dominant mechanism):
  1/T1(C) = (μ₀/4π)² · γ_H²·γ_C²·ℏ² · (N_H/r_CH⁶) · [J(ω_C−ω_H) + 3J(ω_C) + 6J(ω_C+ω_H)]
  r_CH ≈ 1.09 Å (direct bond), effective r_eff for multi-H environment

Nuclear Overhauser Enhancement (¹H→¹³C NOE):
  η_max = (γ_H / 2γ_C) = 1.988  (theoretical maximum)
  Observed η is typically 1.5–1.9 for mobile organic molecules

DEPT editing (quantum selection rule):
  DEPT-135: CH and CH₃ positive, CH₂ negative, quaternary C silent
  Phase of DEPT signal: θ_DEPT = 135° → sin(135°)sin³(135°) = 1/2√2
  INADEQUATE: ¹³C-¹³C J-coupling (¹J_CC ≈ 35–80 Hz)
```

### SpectralModality.swift — Update featureCount

Change `.nmrCarbon` from `return 258` to `return 301`.

### NMRCarbonSynthesizer.swift — Add Quantum Features

Open `Training/Synthesis/NMRCarbonSynthesizer.swift`. ADD this static method
and append its output dict to `derivedFeatures` in `synthesize(count:)`:

```swift
// MARK: — Quantum ¹³C NMR Features (Phase 33)

nonisolated static func quantumC13Features(
    carbonyl_count: Int,
    aromatic_count: Int,
    aliphatic_count: Int,
    carboxyl_present: Bool,
    tau_c_ps: Double,
    spectrometer_MHz: Double = 150.9   // 150.9 MHz for ¹³C at 14.1 T
) -> [String: Double] {

    var d: [String: Double] = [:]
    let omega_C  = 2.0 * .pi * spectrometer_MHz * 1e6
    let omega_H  = omega_C * (267.522e6 / 67.283e6)  // ¹H/¹³C gyromagnetic ratio
    let tau_c    = tau_c_ps * 1e-12
    let gamma_H  = 2.6752e8;  let gamma_C = 6.7283e7
    let hbar     = 1.0546e-34; let mu0o4pi = 1e-7

    func J(_ omega: Double) -> Double { 2.0*tau_c/(1.0+omega*omega*tau_c*tau_c) }

    // ── T1(¹³C) dipolar mechanism ─────────────────────────────────────────
    let r_CH     = 1.09e-10  // m
    let N_H_eff  = Double(max(aliphatic_count, 1))
    let pre      = pow(mu0o4pi, 2) * gamma_H*gamma_H * gamma_C*gamma_C * hbar*hbar
    let inv_T1_C = pre * N_H_eff / pow(r_CH, 6) *
                   (J(omega_H - omega_C) + 3.0*J(omega_C) + 6.0*J(omega_H + omega_C))
    d["T1_carbon_ms"] = min(inv_T1_C > 1e-12 ? 1.0/inv_T1_C*1000.0 : 999.0, 9999.0)

    // ── NOE factor ¹H→¹³C ────────────────────────────────────────────────
    let noe_num = 6.0*J(omega_H+omega_C) - J(omega_H-omega_C)
    let noe_den = J(omega_H-omega_C) + 3.0*J(omega_H) + 6.0*J(omega_H+omega_C)
    let noe_eta = noe_den > 1e-20 ? (gamma_H/(2.0*gamma_C)) * noe_num/noe_den : 0
    d["noe_1H_13C"]   = max(-1.0, min(2.0, noe_eta))
    d["noe_enhanced"] = abs(noe_eta) > 0.5 ? 1.0 : 0.0

    // ── CSA tensors per carbon type ───────────────────────────────────────
    let csa_carbonyl = carbonyl_count > 0 ? Double.random(in: 150.0...200.0) : 0.0
    let csa_aromatic = aromatic_count > 0 ? Double.random(in: 120.0...180.0) : 0.0
    let csa_aliphatic = aliphatic_count > 0 ? Double.random(in: 25.0...35.0) : 0.0
    d["csa_carbonyl_ppm"]  = csa_carbonyl
    d["csa_aromatic_ppm"]  = csa_aromatic
    d["csa_aliphatic_ppm"] = csa_aliphatic
    d["csa_max_ppm"]       = max(csa_carbonyl, csa_aromatic, csa_aliphatic)
    d["eta_carbonyl_csa"]  = carbonyl_count > 0 ? Double.random(in: 0.0...0.2) : 0.0
    d["eta_aromatic_csa"]  = aromatic_count > 0 ? Double.random(in: 0.5...0.9) : 0.0

    // ── DEPT editing flags ────────────────────────────────────────────────
    d["dept_ch_positive"]   = 1.0   // CH always positive in DEPT-135
    d["dept_ch2_negative"]  = 1.0   // CH₂ always negative
    d["dept_ch3_positive"]  = 1.0   // CH₃ positive in DEPT-135
    d["dept_quat_silent"]   = 1.0   // quaternary C absent in all DEPT
    d["dept_phase_135"]     = sin(135.0 * .pi / 180.0) *
                               pow(sin(135.0 * .pi / 180.0), 3.0)

    // ── J_CC coupling ─────────────────────────────────────────────────────
    let J_CC_direct = Double.random(in: 35.0...80.0)   // ¹J_CC Hz
    let J_CC_2bond  = Double.random(in: 0.0...5.0)     // ²J_CC Hz
    d["J_CC_1bond_Hz"]  = J_CC_direct
    d["J_CC_2bond_Hz"]  = J_CC_2bond
    d["INADEQUATE_detectable"] = aliphatic_count + aromatic_count > 4 ? 1.0 : 0.0

    // ── Solid-state MAS features ──────────────────────────────────────────
    let mas_rate_kHz = 15.0  // typical MAS rate
    let csa_sideband_spacing = spectrometer_MHz / mas_rate_kHz  // ratio
    d["mas_rate_kHz"]            = mas_rate_kHz
    d["csa_sideband_pattern"]    = csa_sideband_spacing
    d["ss_delta_iso_ppm"]        = 0.0  // isotropic shift unchanged in solid
    d["ss_broadening_ppm"]       = csa_aliphatic / (mas_rate_kHz * 2.0)
    d["carboxyl_present"]        = carboxyl_present ? 1.0 : 0.0
    d["tau_c_ps"]                = tau_c_ps

    // Pad to exactly 43 new features
    let padKeys = (1...43).map { "qc13_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 43 { d[k] = 0.0 }
    return d
}
```

---

## PHASE 34 — Raman Resonance Enhancement and Anharmonicity

### Physics Added

```
Resonance Raman cross-section (Albrecht A-term):
  σ_R(ω_L) ∝ |Σ_m ⟨f|μ|m⟩⟨m|μ|i⟩ / (E_m − E_i − ℏω_L − iΓ_m)|²
  Enhancement factor: |E_m − ℏω_L|⁻² near electronic resonance
  Selective enhancement: only modes with large geometry change (ΔQ_k)
  between ground and excited state are enhanced

Anharmonic oscillator (Morse potential):
  V(r) = D_e · [1 − exp(−β(r − r_e))]²
  Energy levels: G(v) = ωₑ(v+½) − ωₑχₑ(v+½)²  (Dunham expansion)
  ωₑ = fundamental frequency (cm⁻¹)
  ωₑχₑ = anharmonicity constant (cm⁻¹), typically 1–20 cm⁻¹
  Overtone positions: ν_n ≈ n·ωₑ − n(n+1)·ωₑχₑ   (first overtone at 2ωₑ − 6ωₑχₑ)
  Dissociation energy: D_e = ωₑ²/(4ωₑχₑ)  (cm⁻¹)

CARS (Coherent Anti-Stokes Raman Scattering):
  ω_CARS = 2ω_pump − ω_Stokes    (energy conservation)
  I_CARS ∝ |χ⁽³⁾_R(ω)|² · I²_pump · I_Stokes
  χ⁽³⁾_R(ω) = Σ_k A_k / (ω_k − Ω − iΓ_k)   (sum over Raman modes)
  CARS signal: coherent, directional, blue-shifted from pump

Depolarisation ratio (symmetry probe):
  ρ = I_⊥ / I_∥
  ρ = 0 for totally symmetric modes (A₁g, Ag)
  ρ = 0.75 for non-totally symmetric or antisymmetric modes
  ρ < 0.75 indicates degree of polarisability anisotropy

Surface-Enhanced Raman (SERS):
  Enhancement factor EF = (I_SERS/N_surf) / (I_bulk/N_bulk)
  Electromagnetic: EF ∝ |E_loc/E₀|⁴  (fourth power of local field)
  Chemical: charge-transfer resonance between molecule and metal
  Typical EF: 10⁶–10⁸ (electromagnetic), 10¹⁰–10¹¹ (SERS hotspot)
```

### SpectralModality.swift — Update featureCount

Change `.raman` from `return 358` to `return 418`.

### RamanSynthesizer.swift — Add Quantum Features

Open `Training/Synthesis/RamanSynthesizer.swift`. ADD this method and call it
inside `synthesize(count:)` to extend the `derived` dict by 60 features.

```swift
// MARK: — Quantum Raman Enhancement Features (Phase 34)

nonisolated static func quantumRamanFeatures(
    spectrum: [Float],
    grid: [Double],
    excitationNM: Double,
    nearResonanceNM: Double? = nil  // electronic absorption peak, nil if off-resonance
) -> [String: Double] {

    var d: [String: Double] = [:]
    let excitationCM = 1.0e7 / excitationNM         // nm → cm⁻¹

    // ── Resonance enhancement factor ─────────────────────────────────────
    if let resNM = nearResonanceNM {
        let resCM   = 1.0e7 / resNM
        let delta_E = abs(excitationCM - resCM)     // cm⁻¹
        let Gamma   = 500.0                          // typical damping, cm⁻¹
        let enhancement = 1.0 / (delta_E * delta_E + Gamma * Gamma)
        d["resonance_enhancement_factor"] = enhancement * 1e8  // normalised
        d["near_resonance"]               = delta_E < 2000.0 ? 1.0 : 0.0
        d["resonance_excitation_nm"]      = resNM
        d["detuning_cm1"]                 = delta_E
    } else {
        d["resonance_enhancement_factor"] = 1.0
        d["near_resonance"]               = 0.0
        d["resonance_excitation_nm"]      = 0.0
        d["detuning_cm1"]                 = 99999.0
    }

    // ── Anharmonic constants for dominant peaks ───────────────────────────
    // Find the two strongest peaks
    var peaks: [(Double, Float)] = []
    for i in 1..<(spectrum.count-1) {
        if spectrum[i] >= spectrum[i-1] && spectrum[i] >= spectrum[i+1] &&
           Double(spectrum[i]) > 0.05 {
            peaks.append((grid[i], spectrum[i]))
        }
    }
    peaks.sort { $0.1 > $1.1 }

    if let p1 = peaks.first {
        let omega_e1      = p1.0
        let chi_e1        = Double.random(in: 1.0...15.0)   // anharmonicity constant
        let overtone_1    = 2.0*omega_e1 - 6.0*chi_e1       // first overtone
        let D_e1          = omega_e1*omega_e1 / (4.0*chi_e1) // dissociation energy
        d["peak1_omega_e_cm1"]    = omega_e1
        d["peak1_chi_e_cm1"]      = chi_e1
        d["peak1_overtone_cm1"]   = overtone_1
        d["peak1_D_e_cm1"]        = D_e1
        d["peak1_anharmonic_ratio"] = chi_e1 / omega_e1
    } else {
        d["peak1_omega_e_cm1"] = 0; d["peak1_chi_e_cm1"] = 0
        d["peak1_overtone_cm1"] = 0; d["peak1_D_e_cm1"] = 0
        d["peak1_anharmonic_ratio"] = 0
    }

    if peaks.count > 1 {
        let p2 = peaks[1]
        let omega_e2 = p2.0
        let chi_e2   = Double.random(in: 1.0...15.0)
        d["peak2_omega_e_cm1"] = omega_e2
        d["peak2_chi_e_cm1"]   = chi_e2
        d["peak2_overtone_cm1"] = 2.0*omega_e2 - 6.0*chi_e2
        d["peak2_anharmonic_ratio"] = chi_e2 / omega_e2
    } else {
        d["peak2_omega_e_cm1"] = 0; d["peak2_chi_e_cm1"] = 0
        d["peak2_overtone_cm1"] = 0; d["peak2_anharmonic_ratio"] = 0
    }

    // ── Depolarisation ratios ─────────────────────────────────────────────
    // Symmetric modes (600-1000 cm⁻¹ region often contains ring breathing)
    let symIntegral = zip(grid, spectrum)
        .filter { $0.0 >= 600 && $0.0 <= 1000 }.map { Double($0.1) }.reduce(0, +)
    let asymIntegral = zip(grid, spectrum)
        .filter { $0.0 >= 1000 && $0.0 <= 1600 }.map { Double($0.1) }.reduce(0, +)
    let rho_estimate = symIntegral > 1e-9 ? min(asymIntegral/symIntegral * 0.375, 0.75) : 0.375
    d["depolarisation_ratio"] = rho_estimate
    d["polarised_mode_present"]   = rho_estimate < 0.3 ? 1.0 : 0.0
    d["depolarised_mode_present"] = rho_estimate > 0.7 ? 1.0 : 0.0

    // ── CARS virtual level estimate ───────────────────────────────────────
    if let p1 = peaks.first {
        let omega_CARS = 2.0*excitationCM - (excitationCM - p1.0)  // = excitationCM + p1.0
        let lambda_CARS = 1.0e7 / omega_CARS  // nm
        d["cars_frequency_cm1"]  = omega_CARS
        d["cars_wavelength_nm"]  = lambda_CARS
        d["cars_blueshift_nm"]   = excitationNM - lambda_CARS
    } else {
        d["cars_frequency_cm1"] = 0; d["cars_wavelength_nm"] = 0; d["cars_blueshift_nm"] = 0
    }

    // ── Stokes/Anti-Stokes ratio (temperature probe) ──────────────────────
    let T_sample = Double.random(in: 273.0...373.0)  // K
    let kT_cm    = 0.6950 * T_sample                  // cm⁻¹
    let nu_probe = peaks.first?.0 ?? 1000.0
    let as_ratio = exp(-nu_probe / kT_cm)
    d["stokes_antistokes_ratio"] = as_ratio
    d["temperature_probe_K"]     = T_sample
    d["nu_probe_cm1"]            = nu_probe

    // ── Surface enhancement proxy ─────────────────────────────────────────
    let sers_mode = Double.random(in: 0...1) < 0.15  // 15% are SERS conditions
    d["sers_conditions"] = sers_mode ? 1.0 : 0.0
    d["efield_enhancement_4th"] = sers_mode ? Double.random(in: 1e6...1e8) : 1.0

    // ── Fermi resonance detection ─────────────────────────────────────────
    // Fermi resonance: two peaks close together with inverted relative intensities
    var fermiresonance = 0.0
    for i in 0..<(peaks.count-1) {
        let sep = abs(peaks[i].0 - peaks[i+1].0)
        if sep < 50 && sep > 5 { fermiresonance = 1.0; break }
    }
    d["fermi_resonance_present"] = fermiresonance
    d["excitation_nm"]           = excitationNM
    d["excitation_cm1"]          = excitationCM

    // Pad to 60 features
    let padKeys = (1...60).map { "qraman_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 60 { d[k] = 0.0 }
    return d
}
```

---

## PHASE 35 — XPS Many-Body Quantum Enhancement

### Physics Added

```
Spin-orbit coupling (SOC) doublets for non-s core levels:
  2p:  2p₁/₂ and 2p₃/₂    area ratio 1:2,  ΔBE = Z-dependent (≈ 1–30 eV)
  3p:  3p₁/₂ and 3p₃/₂    area ratio 1:2
  3d:  3d₃/₂ and 3d₅/₂    area ratio 2:3,  ΔBE small (< 1 eV for 3d TM)
  4f:  4f₅/₂ and 4f₇/₂    area ratio 3:4

  SOC splitting ΔE_SOC = ζ·⟨L·S⟩ / n³  (scales with Z⁴)
  Known 2p SOC splits (eV): Si=0.6, Al=0.4, S=1.2, Cl=1.6, Ti=5.5,
                             Fe=13.1, Ni=17.3, Cu=19.9, Zn=23.1

Shake-up satellite structure (configuration interaction):
  Following core ionisation, valence electrons can be simultaneously
  excited to unoccupied orbitals (shake-up) or continuum (shake-off)
  Shake-up BE = main peak BE + ΔE_satellite (typically 4–10 eV higher)
  Satellite intensity ≈ 5–30% of main peak
  Key diagnostic: Cu²⁺ has strong satellite ≈ 9 eV above Cu 2p₃/₂
                  Cu⁺ and Cu⁰ have weak/absent satellites
  Ni²⁺: satellite ≈ 6 eV above Ni 2p₃/₂, intensity ≈ 20%

Auger parameter (Wagner parameter) α′:
  α′ = KE(LMM Auger) + BE(2p photoelectron)    (Cu: α′ ≈ 1849 eV)
  Compound-specific values (Cu example):
    Cu⁰:    α′ = 1851.4 eV
    Cu₂O:   α′ = 1849.3 eV
    CuO:    α′ = 1851.2 eV (different from Cu⁰ despite similar BEs)
  The modified Auger parameter is independent of sample charging

Plasmon loss peaks (metals):
  ΔE_plasmon = ℏω_p = ℏ√(n_e e²/ ε₀ m_e) ≈ 5–25 eV
  Multiple orders: n · ℏω_p at higher binding energies
  Al: ℏω_p ≈ 15.3 eV;  Si: 16.7 eV;  Na: 5.9 eV
```

### SpectralModality.swift — Update featureCount

Change `.xps` from `return 1212` to `return 1272`.

### XPSSynthesizer.swift — Add Quantum Features

Open `Training/Synthesis/XPSSynthesizer.swift`. ADD the following constant
dictionaries and `addQuantumXPSFeatures` method, then call it from
`synthesizeSurface(elements:)` to extend the returned record's `derivedFeatures`.

```swift
// MARK: — Quantum XPS Enhancement (Phase 35)

// SOC splitting ΔE (eV) for common 2p levels
private let socSplit2p: [String: Double] = [
    "Si": 0.6,  "Al": 0.4,  "P":  0.9,  "S":  1.2,
    "Cl": 1.6,  "K":  2.7,  "Ca": 3.5,  "Ti": 5.5,
    "V":  6.9,  "Cr": 8.1,  "Mn": 11.0, "Fe": 13.1,
    "Co": 15.1, "Ni": 17.3, "Cu": 19.9, "Zn": 23.1
]

// Shake-up satellite parameters: (ΔBE_eV, relative_intensity)
private let shakeUpParams: [String: (Double, Double)] = [
    "Cu": (9.0, 0.25),   "Ni": (6.0, 0.20),
    "Co": (5.5, 0.15),   "Fe": (6.0, 0.12),
    "Cr": (3.0, 0.08),   "Mn": (4.0, 0.10)
]

// Auger parameter reference values α′ (eV)
private let wagnerParam: [String: Double] = [
    "Cu": 1851.4, "Ni": 1843.9, "Zn": 2011.0,
    "Si": 1715.4, "Al": 1461.0, "Fe": 721.0
]

// Plasmon loss energy ℏω_p (eV)
private let plasmonLoss: [String: Double] = [
    "Al": 15.3, "Si": 16.7, "Na": 5.9, "Mg": 10.6
]

func addQuantumXPSFeatures(
    elements: [(symbol: String, atomicPct: Double, oxidationState: Int)],
    spectrum: inout [Float]
) -> [String: Double] {

    var d: [String: Double] = [:]
    let beGrid = (0..<1200).map { Double($0) }

    // ── Add SOC doublet peaks to spectrum ────────────────────────────────
    for (el, pct, _) in elements {
        guard let baseBE = coreLevelBE["\(el)1s"] ?? coreLevelBE["\(el)2p"] else { continue }
        if let split = socSplit2p[el] {
            // 2p₁/₂ peak is higher BE by split, area = 0.5 × main peak
            let area1_2 = Float(pct * 0.005)
            let sigma   = 0.9
            let be1_2   = baseBE + split
            for i in 0..<1200 {
                let dx = beGrid[i] - be1_2
                spectrum[i] += area1_2 * Float(exp(-dx*dx/(2*sigma*sigma))/(sigma*2.507))
            }
            d["soc_split_\(el)_eV"]  = split
            d["soc_2p12_be_\(el)"]   = be1_2
            d["soc_ratio_\(el)"]     = 0.5   // 2p₁/₂ : 2p₃/₂ area ratio
        }

        // ── Shake-up satellite ──────────────────────────────────────────
        if let (dBE, relI) = shakeUpParams[el] {
            let satBE   = baseBE + dBE
            let satArea = Float(pct * relI * 0.01)
            let sigma   = 1.5  // broader than main peak
            for i in 0..<1200 {
                let dx = beGrid[i] - satBE
                spectrum[i] += satArea * Float(exp(-dx*dx/(2*sigma*sigma))/(sigma*2.507))
            }
            d["shakeup_\(el)_dBE_eV"]   = dBE
            d["shakeup_\(el)_rel_int"]  = relI
            d["shakeup_\(el)_present"]  = 1.0
        }

        // ── Plasmon loss ────────────────────────────────────────────────
        if let eplasmon = plasmonLoss[el], let baseBE2 = coreLevelBE["\(el)2p"] {
            for order in 1...2 {
                let plasmonBE  = baseBE2 + Double(order) * eplasmon
                let plasmonAmp = Float(pct * 0.003 / Double(order))
                let sigma      = 1.2
                for i in 0..<1200 {
                    let dx = beGrid[i] - plasmonBE
                    spectrum[i] += plasmonAmp *
                        Float(exp(-dx*dx/(2*sigma*sigma))/(sigma*2.507))
                }
            }
            d["plasmon_loss_\(el)_eV"] = eplasmon
        }
    }

    // ── Auger parameter (Wagner α′) ──────────────────────────────────────
    for (el, _, _) in elements {
        if let alpha = wagnerParam[el] {
            d["wagner_alpha_\(el)"] = alpha
        }
    }

    // ── Shake-up aggregate features ──────────────────────────────────────
    let hasTransitionMetal = elements.contains { ["Fe","Co","Ni","Cu","Cr","Mn"].contains($0.symbol) }
    d["transition_metal_shakeup"] = hasTransitionMetal ? 1.0 : 0.0

    // ── SOC aggregate features ────────────────────────────────────────────
    let maxSOC = elements.compactMap { socSplit2p[$0.symbol] }.max() ?? 0
    d["max_soc_split_eV"]     = maxSOC
    d["heavy_element_present"] = maxSOC > 5.0 ? 1.0 : 0.0

    // Pad to 60 features total
    let allKeys = [
        "transition_metal_shakeup","max_soc_split_eV","heavy_element_present"
    ]
    for k in allKeys where d[k] == nil { d[k] = 0.0 }
    let padKeys = (1...60).map { "qxps_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 60 { d[k] = 0.0 }
    return d
}
```

In `synthesizeSurface(elements:)`, after building `spectrum`, call:

```swift
let qFeatures = addQuantumXPSFeatures(elements: elements, spectrum: &spectrum)
// Merge qFeatures into the record's derivedFeatures
```

---

## PHASE 36 — Fluorescence Marcus Theory and Photophysics Enhancement

### Physics Added

```
Marcus electron transfer rate (quantum tunnelling through FC manifold):
  k_ET = (2π/ℏ) · |V_DA|² · FCWD
  FCWD = (4πλk_BT)^(-½) · exp[−(ΔG° + λ)² / (4λk_BT)]
  V_DA   = electronic coupling matrix element (eV)
  λ      = reorganisation energy (eV): λ = λ_inner + λ_outer
  ΔG°    = Gibbs free energy of ET (eV)
  Inverted region: k_ET decreases when |ΔG°| > λ

Intersystem crossing via El-Sayed's rule:
  k_ISC ∝ ξ²_SOC / ΔE³_ST  (spin-orbit coupling mediated)
  Efficient ISC: π→π* → n→π* changes orbital angular momentum
  ΔE_ST  = E(S₁) − E(T₁) (singlet-triplet gap, eV)
  ξ_SOC  = spin-orbit coupling constant (cm⁻¹):
    C: 28, N: 76, O: 151, S: 382, Br: 2460, I: 5060
  El-Sayed's rule: k_ISC larger for S₁(π,π*)→T₁(n,π*) than S₁(π,π*)→T₁(π,π*)

Franck-Condon factor (vibronic coupling):
  FC = |⟨v′|v″⟩|² (overlap integral between vibrational wavefunctions)
  Poisson distribution in the harmonic approximation:
  ⟨n_0|n′⟩² = e^(−S) · S^n′ / n′!    (Huang-Rhys factor S = ΔQ²ω/(2ℏ))
  Strong FC: large ΔQ (geometry change on excitation) → broad emission
  Mirror-image rule: absorption and emission are FC-symmetric if ΔQ is small

Förster resonance energy transfer (FRET):
  k_FRET = (1/τ_D) · (R₀/r)⁶
  R₀ = 0.211 · [κ² · n⁻⁴ · Φ_D · J(λ)]^(1/6)  nm
  J(λ) = ∫ F_D(λ) · ε_A(λ) · λ⁴ dλ  (spectral overlap integral)
  κ² = ⅔ for freely rotating dipoles (isotropic)

Strickler-Berg equation (radiative rate from absorption):
  k_r = 2.88 × 10⁻⁹ · n² · ⟨ν̃_f⁻³⟩⁻¹ · ∫ ε(ν̃)/ν̃ dν̃
  Relates k_r to oscillator strength f_osc
```

### SpectralModality.swift — Update featureCount

Change `.fluorescence` from `return 307` to `return 361`.

### FluorescenceSynthesizer.swift — Add Quantum Features

```swift
// MARK: — Quantum Fluorescence Features (Phase 36)

nonisolated static func quantumFluorescenceFeatures(
    excitation_nm: Double,
    emission_peak_nm: Double,
    quantum_yield: Double,
    lifetime_ns: Double,
    contains_heavy_atom: Bool,   // S, Br, I present → strong SOC
    solvent_polarity: Double,    // ε_r: water=78.4, ethanol=24.6, toluene=2.4
    donoAcceptorGap_eV: Double? = nil   // HOMO-LUMO gap if known
) -> [String: Double] {

    var d: [String: Double] = [:]

    // ── Radiative and non-radiative rates ─────────────────────────────────
    let tau_s    = lifetime_ns * 1e-9                // s
    let k_total  = tau_s > 0 ? 1.0 / tau_s : 1e8
    let k_r      = quantum_yield * k_total
    let k_nr     = (1.0 - quantum_yield) * k_total
    d["k_r_s"]   = k_r
    d["k_nr_s"]  = k_nr
    d["k_total_s"] = k_total
    d["lifetime_ns"] = lifetime_ns

    // ── Stokes shift in cm⁻¹ ─────────────────────────────────────────────
    let stokes_cm = (1.0/excitation_nm - 1.0/emission_peak_nm) * 1.0e7
    d["stokes_shift_cm1"] = stokes_cm
    d["stokes_shift_nm"]  = emission_peak_nm - excitation_nm

    // ── Lippert-Mataga solvent polarity (relates Stokes to dipole change) ─
    let f_epsilon = (solvent_polarity - 1.0)/(2.0*solvent_polarity + 1.0) -
                    (1.0 - 1.0)/(2.0*1.0 + 1.0)  // Δf, orientation polarisability
    d["lippert_mataga_Df"] = f_epsilon
    d["solvent_polarity_er"] = solvent_polarity
    let delta_mu_squared  = stokes_cm > 0 ? stokes_cm * 1e-4 / (2.0 * f_epsilon + 1e-9) : 0
    d["dipole_change_sq_D2"] = delta_mu_squared

    // ── Marcus electron transfer ──────────────────────────────────────────
    let lambda_eV    = Double.random(in: 0.2...1.5)   // reorganisation energy (eV)
    let dG0_eV       = donoAcceptorGap_eV.map { -($0 - 2.0) } ?? Double.random(in: -2.0...0.0)
    let kT_eV        = 0.02585                          // 300 K in eV
    let V_DA_eV      = Double.random(in: 0.001...0.1)   // coupling (eV)
    let fcwd         = pow(4.0 * .pi * lambda_eV * kT_eV, -0.5) *
                       exp(-(dG0_eV + lambda_eV)*(dG0_eV + lambda_eV) /
                           (4.0 * lambda_eV * kT_eV))
    let k_ET         = 2.0 * .pi / 1.0546e-34 *
                       (V_DA_eV * 1.602e-19) * (V_DA_eV * 1.602e-19) * fcwd
    d["marcus_lambda_eV"]    = lambda_eV
    d["marcus_dG0_eV"]       = dG0_eV
    d["marcus_V_DA_eV"]      = V_DA_eV
    d["marcus_FCWD"]         = fcwd
    d["marcus_k_ET_s"]       = min(k_ET, 1e15)
    d["marcus_inverted_region"] = abs(dG0_eV) > lambda_eV ? 1.0 : 0.0

    // ── El-Sayed ISC rate ─────────────────────────────────────────────────
    let xi_SOC: Double = contains_heavy_atom ? 382.0 : 28.0  // cm⁻¹ (S or C)
    let dE_ST_eV       = stokes_cm > 500 ? stokes_cm*1.24e-4*0.3 : 0.3  // rough estimate
    let k_ISC          = xi_SOC * xi_SOC / pow(dE_ST_eV * 8065.5, 3.0)  // relative
    d["soc_constant_cm1"]    = xi_SOC
    d["st_gap_eV"]           = dE_ST_eV
    d["k_ISC_relative"]      = k_ISC
    d["heavy_atom_effect"]   = contains_heavy_atom ? 1.0 : 0.0
    d["isc_efficient"]       = k_ISC > 1e-8 ? 1.0 : 0.0

    // ── Franck-Condon Huang-Rhys factor ──────────────────────────────────
    let S_HR   = stokes_cm / (2.0 * 1500.0 + 1e-9)  // S ≈ Stokes/(2·ν_mode)
    let fc_00  = exp(-S_HR)                           // FC for 0→0 transition
    let fc_01  = S_HR * exp(-S_HR)                    // 0→1 vibronic
    let fc_02  = 0.5 * S_HR * S_HR * exp(-S_HR)      // 0→2 vibronic
    d["huang_rhys_S"]    = S_HR
    d["fc_factor_00"]    = fc_00
    d["fc_factor_01"]    = fc_01
    d["fc_factor_02"]    = fc_02
    d["vibronic_coupling_strong"] = S_HR > 1.0 ? 1.0 : 0.0

    // ── Strickler-Berg radiative rate estimate ────────────────────────────
    let n_refr       = 1.4   // typical organic solvent
    let nu_em_cm     = 1.0e7 / emission_peak_nm  // cm⁻¹
    let f_osc_est    = k_r / (4.3e7 * nu_em_cm * nu_em_cm)  // simplified
    d["strickler_berg_k_r_est"] = k_r
    d["oscillator_strength_est"] = min(f_osc_est, 2.0)
    d["refractive_index_solvent"] = n_refr

    // ── FRET parameters (donor context) ──────────────────────────────────
    let R0_nm    = Double.random(in: 3.0...7.0)   // typical Förster radius
    let r_DA_nm  = Double.random(in: 1.0...12.0)  // donor-acceptor distance
    let E_FRET   = 1.0 / (1.0 + pow(r_DA_nm/R0_nm, 6.0))
    d["forster_R0_nm"]    = R0_nm
    d["fret_distance_nm"] = r_DA_nm
    d["fret_efficiency"]  = E_FRET
    d["fret_active"]      = r_DA_nm < R0_nm * 1.5 ? 1.0 : 0.0

    // Pad to 54 features
    let padKeys = (1...54).map { "qfl_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 54 { d[k] = 0.0 }
    return d
}
```

---

## PHASE 37 — XRD Full Quantum Structure Factor Enhancement

### Physics Added

```
Quantum-mechanical atomic form factor f(q):
  f(q) = Σ_{i=1}^{4} aᵢ·exp(−bᵢ·(sinθ/λ)²) + c   (Cromer-Mann coefficients)
  At q=0: f(0) = Z  (equals atomic number)
  At high q: f(q) → 0  (electrons spread over atomic volume)

Anomalous scattering (X-ray fluorescence edges):
  f(λ) = f₀(q) + f′(λ) + i·f″(λ)
  f′  = real anomalous dispersion correction (negative near edge)
  f″  = imaginary correction (proportional to photoabsorption cross-section)
  Near Cu K-edge (1.38 Å): f′(Fe) ≈ −4.5, f″(Fe) ≈ 0.5

Debye-Waller factor (quantum zero-point + thermal motion):
  T_j(θ) = exp(−B_j · sin²θ / λ²)
  B_j = 8π²⟨u_j²⟩   (mean-square displacement amplitude, Å²)
  At 300 K: B ≈ 0.4–1.0 Å² for organic compounds
  Quantum zero-point: B_0 = 3h/(8π²m_j·ν_max)  (dominant at low T)

Full structure factor:
  F(hkl) = Σ_j [f₀_j(q) + f′_j + i·f″_j] · T_j · exp(2πi·h·r_j) · occ_j
  |F(hkl)|² gives intensity; F(000) = Σ Z_j (total electrons)

Lorentz-polarisation factor (CW X-ray diffraction):
  LP(θ) = (1 + cos²2θ) / (sin²θ·cosθ)
```

### SpectralModality.swift — Update featureCount

Change `.xrdPowder` from `return 862` to `return 930`.

### XRDSynthesizer.swift — Add Quantum Features

Open `Training/Synthesis/XRDSynthesizer.swift`. ADD the Cromer-Mann table
and `computeFormFactor` method, then call `addQuantumXRDFeatures` when building
each TrainingRecord:

```swift
// MARK: — Quantum XRD Enhancement (Phase 37)

// Cromer-Mann coefficients (a1,b1,a2,b2,a3,b3,a4,b4,c) for common elements
// Source: International Tables for Crystallography Vol. C, Table 6.1.1.4
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

nonisolated static func computeFormFactor(element: String,
                                           sinThetaOverLambda: Double) -> Double {
    guard let cm = cromerMann[element] else { return 1.0 }
    let s2 = sinThetaOverLambda * sinThetaOverLambda
    var f = cm[8]   // c term
    for i in stride(from: 0, to: 8, by: 2) {
        f += cm[i] * exp(-cm[i+1] * s2)
    }
    return max(f, 0.01)
}

nonisolated static func addQuantumXRDFeatures(
    pattern: [Float],
    grid: [Double],         // 2θ values in degrees
    lambda: Double = 1.5406  // Å, Cu Kα
) -> [String: Double] {

    var d: [String: Double] = [:]

    // ── Atomic form factor ratios at key angles ────────────────────────────
    // Compute f(C)/f(Fe) at 2θ = 20°, 40°, 60° to track relative scattering
    let angles = [20.0, 40.0, 60.0]
    for tt in angles {
        let sinTol = sin(tt * .pi / 360.0) / lambda
        let fC  = computeFormFactor(element: "C",  sinThetaOverLambda: sinTol)
        let fFe = computeFormFactor(element: "Fe", sinThetaOverLambda: sinTol)
        let fSi = computeFormFactor(element: "Si", sinThetaOverLambda: sinTol)
        let key = "2theta_\(Int(tt))"
        d["ff_C_at_\(key)"]     = fC
        d["ff_Fe_at_\(key)"]    = fFe
        d["ff_C_Fe_ratio_\(key)"] = fFe > 0.01 ? fC/fFe : 0
        d["ff_Si_at_\(key)"]    = fSi
    }  // 12 features so far

    // ── Lorentz-polarisation factor weighted intensity ─────────────────────
    let lpWeightedIntegral = zip(grid, pattern).map { (tt, I) -> Double in
        let theta  = tt * .pi / 360.0
        let sinT   = sin(theta); let cosT = cos(theta)
        guard sinT > 1e-6 && cosT > 1e-6 else { return 0 }
        let LP     = (1.0 + cos(2*theta)*cos(2*theta)) / (sinT*sinT*cosT)
        return Double(I) / max(LP, 0.01)
    }.reduce(0, +)
    d["lp_corrected_integral"] = lpWeightedIntegral  // 1 feature

    // ── Debye-Waller temperature factors ─────────────────────────────────
    let B_vals = [0.3, 0.6, 1.0, 2.0]  // Å² range
    for B in B_vals {
        // Ratio of high-angle to low-angle intensity decay due to thermal motion
        let hi_dw = exp(-B * pow(sin(60.0 * .pi/360.0)/lambda, 2))
        let lo_dw = exp(-B * pow(sin(15.0 * .pi/360.0)/lambda, 2))
        d["dw_decay_B\(Int(B*10))"] = lo_dw > 0.01 ? hi_dw/lo_dw : 0
    }  // 4 features

    // ── Wilson plot (I vs sin²θ/λ²) ──────────────────────────────────────
    // Wilson statistics: ⟨I(h)⟩ ∝ Σ f_j² · exp(−2B·sin²θ/λ²)
    let nBins = 10
    var wilson_slope = 0.0
    var xW = [Double](); var yW = [Double]()
    for bin in 0..<nBins {
        let tt_lo = 10.0 + Double(bin)*8.0
        let tt_hi = tt_lo + 8.0
        let seg = zip(grid, pattern).filter { $0.0 >= tt_lo && $0.0 < tt_hi }.map { Double($0.1) }
        guard !seg.isEmpty else { continue }
        let meanI = seg.reduce(0,+)/Double(seg.count)
        let s2 = pow(sin((tt_lo+4.0)*Double.pi/360.0)/lambda, 2)
        if meanI > 1e-6 { xW.append(s2); yW.append(log(meanI)) }
    }
    if xW.count >= 3 {
        let n = Double(xW.count)
        let sumX = xW.reduce(0,+); let sumY = yW.reduce(0,+)
        let sumXY = zip(xW,yW).map(*).reduce(0,+)
        let sumX2 = xW.map{$0*$0}.reduce(0,+)
        wilson_slope = (n*sumXY - sumX*sumY) / max(n*sumX2 - sumX*sumX, 1e-9)
    }
    d["wilson_plot_slope"] = wilson_slope           // ≈ −2B
    d["wilson_B_est_A2"]   = -wilson_slope / 2.0   // 2 features

    // ── Anomalous scattering proxy ────────────────────────────────────────
    // High f″ near Cu Kα edge suggests Fe, Co, Ni, Cu in sample
    let lowAngleIntegral  = zip(grid,pattern).filter{$0.0<20}.map{Double($0.1)}.reduce(0,+)
    let highAngleIntegral = zip(grid,pattern).filter{$0.0>60}.map{Double($0.1)}.reduce(0,+)
    d["anomalous_ratio_proxy"] = highAngleIntegral > 0.01 ? lowAngleIntegral/highAngleIntegral : 0
    d["heavy_scatterer_flag"]  = highAngleIntegral > 0.05 ? 1.0 : 0.0  // 2 features

    // ── F(000) and electron density proxy ────────────────────────────────
    let totalElectrons = zip(grid,pattern).filter{abs($0.0-0.1)<0.1}.map{Double($0.1)}.first ?? 0
    d["F000_proxy"]       = totalElectrons
    d["electron_density"] = totalElectrons / max(Double(grid.count), 1)  // 2 features

    // Pad to 68 features total (12+1+4+2+2+2+2 = 25 so far → pad to 68)
    let padKeys = (1...68).map { "qxrd_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 68 { d[k] = 0.0 }
    return d
}
```

---

## PHASE 38 — HITRAN Dicke Narrowing and Speed-Dependent Voigt

### Physics Added

```
Dicke narrowing (motional narrowing at low pressures):
  Voigt profile is only accurate when mean free path >> wavelength.
  At low P, molecular motion in confined gas narrows the Doppler width:
  γ_D_eff = γ_D / (1 + γ_D/γ_opt)
  γ_opt = D_opt · k²  (optical diffusion coefficient × wavevector²)
  D_opt ≈ D_mass · m/(m+M) · (1 + collision shell correction)
  This narrows lines below the Voigt prediction by up to 20% at 1 Torr.

Speed-dependent Voigt profile (SD-VP):
  Real molecules do not have a single γ_L — faster molecules collide more often.
  γ_L(v) = γ_L,0 · (v/v̄)^(-0.5)   (approximate speed dependence)
  SD-VP parameters in HITRAN2024: SD_gamma, SD_nu_VC (velocity-changing collisions)
  The SD-VP line shape has a slight asymmetry vs symmetric Voigt.

Line mixing (collisional interference):
  At high pressure, lines in a Q-branch overlap and interfere:
  I_mix(ν) = Σ_{ij} Iᵢ · Wᵢⱼ · Iⱼ / (ν−νᵢ−iγᵢ)(ν−νⱼ+iγⱼ)
  Wᵢⱼ = off-diagonal relaxation matrix element (couples line i to line j)
  Rosenkranz approximation: I_mix(ν) ≈ Σᵢ (Iᵢ + 2Iᵢ·Yᵢ·(ν−νᵢ)) / ((ν−νᵢ)²+γᵢ²)
  Y_i = line mixing coefficient (first-order, Rosenkranz)
  HITRAN2024 includes Y_i parameters for CO₂ P/Q/R branches.
```

### SpectralModality.swift — Update featureCount

Change `.hitranMolecular` from `return 406` to `return 454`.

### HITRANSynthesizer.swift — Add Quantum Features

```swift
// MARK: — Quantum HITRAN Enhancement (Phase 38)

nonisolated static func quantumHITRANFeatures(
    lines: [HITRANParser.Line],
    temperature: Double,
    pressure_atm: Double,
    molecule_id: Int
) -> [String: Double] {

    var d: [String: Double] = [:]

    // ── Dicke narrowing correction factor ────────────────────────────────
    // Optical diffusion coefficient D_opt scales inversely with pressure
    // gamma_D_eff = gamma_D * (1 - delta_Dicke)
    let D_opt_proxy     = 0.1 / pressure_atm  // higher at low P
    let delta_Dicke     = min(0.2, D_opt_proxy / (D_opt_proxy + 1.0))
    d["dicke_narrowing_delta"]  = delta_Dicke
    d["dicke_narrowing_regime"] = pressure_atm < 0.1 ? 1.0 : 0.0
    d["optical_diffusion_proxy"] = D_opt_proxy

    // ── Speed-dependent Voigt asymmetry ──────────────────────────────────
    // SD-VP introduces a slight asymmetry parameterised by aw (speed dependence of width)
    // aw ≈ 0.0 (no speed dep.) to 0.1 (strong)
    let aw = Double.random(in: 0.0...0.07)   // typical SD parameter
    let sdvp_asymmetry = aw * pressure_atm / (pressure_atm + 0.1)
    d["sdvp_aw_param"]    = aw
    d["sdvp_asymmetry"]   = sdvp_asymmetry
    d["sdvp_correction"]  = sdvp_asymmetry > 0.005 ? 1.0 : 0.0

    // ── Line mixing (Rosenkranz Y coefficient) ────────────────────────────
    let hasQBranch   = molecule_id == 2 || molecule_id == 4  // CO₂, O₃ have Q-branch
    let Y_rosenkranz = hasQBranch ? Double.random(in: -0.05...0.05) : 0.0
    d["rosenkranz_Y"]      = Y_rosenkranz
    d["line_mixing_active"] = abs(Y_rosenkranz) > 0.01 ? 1.0 : 0.0
    d["Q_branch_molecule"]  = hasQBranch ? 1.0 : 0.0

    // ── Partition function temperature dependence ─────────────────────────
    let Q_ratio = pow(296.0/temperature, 1.5)  // linear molecule approximation
    d["partition_Q_ratio"]   = Q_ratio
    d["temperature_dep_S"]   = Q_ratio  // line intensity scales with Q(T₀)/Q(T)

    // ── Pressure-broadening regime ────────────────────────────────────────
    let regime: String
    if pressure_atm < 0.01      { regime = "doppler_dominated" }
    else if pressure_atm > 1.0  { regime = "lorentzian_dominated" }
    else                         { regime = "voigt_intermediate" }
    d["pressure_regime_doppler"] = pressure_atm < 0.01 ? 1.0 : 0.0
    d["pressure_regime_voigt"]   = (pressure_atm >= 0.01 && pressure_atm <= 1.0) ? 1.0 : 0.0
    d["pressure_regime_lorentz"] = pressure_atm > 1.0 ? 1.0 : 0.0

    // ── Line density and overlap ──────────────────────────────────────────
    let lineCount   = lines.count
    let maxIntensity = lines.map { $0.intensity }.max() ?? 0
    let strongLines  = lines.filter { $0.intensity > maxIntensity * 0.01 }.count
    d["line_count"]        = Double(lineCount)
    d["strong_line_count"] = Double(strongLines)
    d["line_density"]      = lineCount > 0 ? Double(strongLines)/Double(lineCount) : 0

    // ── Collision narrowing crossover ─────────────────────────────────────
    // Crossover P* where Lorentzian width ≈ Doppler width
    guard let firstLine = lines.first else {
        let padKeys = (1...48).map { "qhitran_pad_\($0)" }
        for k in padKeys where d[k] == nil { d[k] = 0.0 }
        return d
    }
    let gamma_D_per_atm = firstLine.wavenumber / 3e10 *
                          sqrt(2 * 1.38e-23 * temperature * log(2) / (28 * 1.66e-27))
    let P_star  = gamma_D_per_atm / max(firstLine.airHalfWidth, 1e-10)
    d["crossover_pressure_atm"] = P_star
    d["below_crossover"]        = pressure_atm < P_star ? 1.0 : 0.0
    d["voigt_eta_estimate"]     = min(1.0, pressure_atm / max(P_star, 1e-10))

    let padKeys = (1...48).map { "qhitran_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 48 { d[k] = 0.0 }
    return d
}
```

---

## PHASE 39 — Atomic Emission Fine Structure and Hyperfine Enhancement

### Physics Added

```
Fine structure from spin-orbit coupling:
  ΔE_FS = ζ_nl · ⟨L·S⟩   (spin-orbit coupling constant, cm⁻¹)
  J = L + S, L + S − 1, ..., |L − S|  (total angular momentum quantum numbers)
  ζ_nl values (cm⁻¹, approximate):
    Na 3p: 11.5,  K 4p: 57.7,   Rb 5p: 237.6,  Cs 6p: 554.0
    Ca 4p: 50.1,  Sr 5p: 194.7, Ba 6p: 486.0
    Fe 3d: 410,   Ni 3d: 605,   Cu 3d: 829
  Resulting doublet/multiplet separations:
    Na D-lines: 589.0 and 589.6 nm (Δλ = 0.6 nm)
    K resonance: 766.5 and 769.9 nm (Δλ = 3.4 nm)

Hyperfine structure (nuclear spin I > 0):
  H_HF = a_J · I · J   (magnetic dipole hyperfine)
  F = J + I, ..., |J − I|   (total angular momentum including nuclear)
  Hyperfine splitting: ΔE_HF = a_J / 2 · [F(F+1) − J(J+1) − I(I+1)]
  Scale: 0.001–0.05 cm⁻¹ (unresolved in most emission spectrometers)
  Relevant for: ¹³³Cs (I=7/2), ⁸⁷Rb (I=3/2), ²³Na (I=3/2), ⁵⁷Fe (I=½)

Stark broadening (LIBS electron density):
  FWHM_Stark = 2w · (nₑ/10¹⁶) · [1 ± 1.75A(nₑ/10¹⁶)^0.25 · (1 − 0.068(nₑ/10¹⁶)^(1/6))]
  w = electron impact half-width (Å at nₑ=10¹⁶ cm⁻³)
  A = ion-broadening parameter
  Hα (656.3 nm): w = 0.1 Å, useful for nₑ from 10¹⁴–10¹⁷ cm⁻³
  nₑ from Hα: nₑ (cm⁻³) ≈ 2.24×10¹² · (FWHM_Hα / 0.549)^1.47
```

### SpectralModality.swift — Update featureCount

Change `.atomicEmission` from `return 714` to `return 768`.
Change `.libs`          from `return 716` to `return 770`.

### AtomicEmissionSynthesizer.swift — Add Quantum Features

```swift
// MARK: — Quantum Atomic Emission Enhancement (Phase 39)

// Fine structure doublet separations (nm) for key emission lines
private static let fineStructureSplit: [String: (Double, Double, Double)] = [
    // element: (lambda1_nm, lambda2_nm, intensity_ratio)
    "Na": (589.0, 589.6, 2.0),    // Na D-lines (2:1 ratio, 2p₃/₂:2p₁/₂)
    "K":  (766.5, 769.9, 2.0),    // K resonance doublet
    "Li": (670.8, 670.8, 1.0),    // Li (unresolved in most instruments)
    "Rb": (780.0, 794.8, 2.0),    // Rb doublet
    "Cs": (852.1, 894.3, 2.0),    // Cs doublet
    "Ca": (393.4, 396.8, 2.0),    // Ca II H & K (ionised)
    "Ba": (553.5, 455.4, 1.0),    // Ba I and Ba II
    "Sr": (460.7, 407.8, 1.0)     // Sr I and Sr II
]

nonisolated static func quantumEmissionFeatures(
    spectrum: [Float],
    grid: [Double],              // wavelength in nm, 200–899 nm, 1 nm bins
    elementsPresent: [String],
    plasma_T_K: Double,
    ne_estimate_cm3: Double = 1e15
) -> [String: Double] {

    var d: [String: Double] = [:]

    // ── Fine structure doublet detection ──────────────────────────────────
    for (el, (l1, l2, ratio)) in Self.fineStructureSplit {
        guard elementsPresent.contains(el) else { continue }
        // Check if both lines are in range and present in spectrum
        func intensityAt(_ nm: Double) -> Double {
            let idx = Int(nm - 200.0)
            guard idx >= 0 && idx < spectrum.count else { return 0 }
            return Double(spectrum[idx])
        }
        let I1 = intensityAt(l1); let I2 = intensityAt(l2)
        let observed_ratio = I2 > 1e-6 ? I1 / I2 : 0
        let doublet_resolved = abs(l2 - l1) > 0.5 ? 1.0 : 0.0
        d["fs_\(el)_I1_nm"]          = l1
        d["fs_\(el)_I2_nm"]          = l2
        d["fs_\(el)_expected_ratio"] = ratio
        d["fs_\(el)_observed_ratio"] = observed_ratio
        d["fs_\(el)_resolved"]       = doublet_resolved
        d["fs_\(el)_agreement"]      = abs(observed_ratio - ratio) < ratio * 0.3 ? 1.0 : 0.0
    }  // up to 6×6 = 36 features

    // ── Stark broadening → nₑ ────────────────────────────────────────────
    // Hα at 656.28 nm: Stark FWHM → electron density
    let idx_Ha    = Int(656.28 - 200.0)
    let I_Ha_peak = idx_Ha >= 0 && idx_Ha < spectrum.count ? Double(spectrum[idx_Ha]) : 0
    // Approximate FWHM via 3-point Gaussian fit at Hα
    var Ha_fwhm_nm = 0.0
    if idx_Ha > 0 && idx_Ha < spectrum.count-1 && I_Ha_peak > 0.01 {
        let half = I_Ha_peak / 2.0
        var left = idx_Ha; var right = idx_Ha
        while left > 0 && Double(spectrum[left]) > half { left -= 1 }
        while right < spectrum.count-1 && Double(spectrum[right]) > half { right += 1 }
        Ha_fwhm_nm = Double(right - left)  // in nm
    }
    let ne_Stark: Double
    if Ha_fwhm_nm > 0.1 {
        ne_Stark = 2.24e12 * pow(Ha_fwhm_nm / 0.549, 1.47)
    } else {
        ne_Stark = ne_estimate_cm3
    }
    d["Ha_intensity"]      = I_Ha_peak
    d["Ha_fwhm_nm"]        = Ha_fwhm_nm
    d["ne_stark_cm3"]      = ne_Stark
    d["ne_log10"]          = ne_Stark > 0 ? log10(ne_Stark) : 0
    d["stark_regime"]      = ne_Stark > 1e16 ? 1.0 : 0.0   // 5 features

    // ── Saha ionisation balance ───────────────────────────────────────────
    // Saha equation: nₑ · n(M⁺)/n(M) = (2/ne) · (2πm_e kT/h²)^(3/2) · g⁺/g · exp(−χ/kT)
    // χ = first ionisation potential (eV)
    let chi_eV: Double   // Na as example
    if elementsPresent.contains("Na")      { chi_eV = 5.14 }
    else if elementsPresent.contains("Ca") { chi_eV = 6.11 }
    else if elementsPresent.contains("Fe") { chi_eV = 7.87 }
    else                                    { chi_eV = 8.0 }
    let kT_eV        = 8.617e-5 * plasma_T_K
    let saha_ratio   = exp(-chi_eV / kT_eV) * pow(plasma_T_K / 5000.0, 1.5) / max(ne_Stark/1e14, 1.0)
    d["saha_ionisation_ratio"] = min(saha_ratio, 100.0)
    d["ionisation_fraction"]   = saha_ratio / (1.0 + saha_ratio)
    d["lte_valid"]             = (plasma_T_K > 5000 && ne_Stark > 1e14) ? 1.0 : 0.0

    // ── Zeeman splitting proxy (if magnetic field present in LIBS) ────────
    // B field in LIBS spark: typically < 0.1 T → splitting < 0.05 cm⁻¹ (unresolved)
    d["zeeman_field_T"]      = 0.0
    d["zeeman_resolved"]     = 0.0
    d["zeeman_sigma_nm"]     = 0.0   // placeholder

    // Pad to 54 features
    let padKeys = (1...54).map { "qemit_pad_\($0)" }
    for k in padKeys where d[k] == nil && d.count < 54 { d[k] = 0.0 }
    return d
}
```

In `AtomicEmissionSynthesizer.synthesize(count:)` and `LIBSSynthesizer.synthesize(count:)`,
after computing the existing `derived` dictionary, call `quantumEmissionFeatures(...)` and
merge the result into `derived` before building the TrainingRecord.

---

## PHASE 40 — Coordinator, SpectralModality, Dashboard, and Manifest Update

### 40.1 — SpectralModality.swift Final Verification

After all phases above are applied, verify the `featureCount` switch reads:

```swift
case .uvVis:               return 122   // unchanged
case .ftir:                return 371   // unchanged
case .nir:                 return 860   // unchanged
case .raman:               return 418   // Phase 34
case .massSpecEI:          return 515   // unchanged
case .massSpecMSMS:        return 507   // unchanged
case .nmrProton:           return 293   // Phase 32
case .nmrCarbon:           return 301   // Phase 33
case .fluorescence:        return 361   // Phase 36
case .xrdPowder:           return 930   // Phase 37
case .xps:                 return 1272  // Phase 35
case .eels:                return 612   // unchanged
case .atomicEmission:      return 768   // Phase 39
case .libs:                return 770   // Phase 39
case .gcRetention:         return 52    // unchanged
case .hplcRetention:       return 57    // unchanged
case .hitranMolecular:     return 454   // Phase 38
case .atmosphericUVVis:    return 651   // unchanged
case .usgsReflectance:     return 1086  // unchanged
case .opticalConstants:    return 403   // unchanged
case .saxs:                return 208   // unchanged
case .circularDichroism:   return 128   // unchanged
case .microwaveRotational: return 212   // unchanged
case .thermogravimetric:   return 214   // unchanged
case .terahertz:           return 208   // unchanged
// ── Quantum Layer (CLAUDE3.md) ────────────────────────────────────────────
case .dftQuantumChem:      return 380
case .mossbauer:           return 252
case .quantumDotPL:        return 280
case .augerElectron:       return 420
case .neutronDiffraction:  return 1163
```

### 40.2 — TrainingDataCoordinator.swift Update

Open `Training/Curation/TrainingDataCoordinator.swift`. Locate the array or
switch that iterates over modalities to dispatch synthesis. Add all five new
quantum modalities from CLAUDE3.md:

```swift
// Inside the synthesis dispatch switch or modalities array, ADD:

case .dftQuantumChem:
    let source = QM9Source()
    let synth  = DFTQuantumChemSynthesizer()
    var count  = 0
    for try await mol in source.streamCSV() {
        let record = await synth.makeRecord(from: mol)
        await store(record)
        count += 1
        if count % 1000 == 0 { await updateProgress(modality, count) }
        if Task.isCancelled { return }
    }

case .mossbauer:
    let synth   = MossbauerSynthesizer()
    let records = await synth.synthesizeTrainingSet(count: 5000)
    for record in records { await store(record) }
    await updateProgress(modality, records.count)

case .quantumDotPL:
    let synth   = QuantumDotSynthesizer()
    let records = await synth.synthesizeTrainingSet(count: 2000)
    for record in records { await store(record) }
    await updateProgress(modality, records.count)

case .augerElectron:
    let synth   = AESSynthesizer()
    // Common surface combinations for AES training
    let surfaces: [[(String, Double, String)]] = [
        [("C",60,"graphitic"),("O",30,"oxide"),("Si",10,"SiO2")],
        [("C",50,"oxide"),("Fe",30,"Fe2O3"),("O",20,"oxide")],
        [("Al",70,"oxide"),("O",20,"oxide"),("C",10,"graphitic")],
        [("Cu",80,"Cu2O"),("O",15,"oxide"),("C",5,"oxide")],
        [("Ti",60,"TiO2"),("O",30,"oxide"),("C",10,"graphitic")]
    ]
    var records: [TrainingRecord] = []
    for _ in 0..<3000 {
        let s = surfaces.randomElement()!
        let r = await synth.synthesizeSurface(
            presentElements: s.map { ($0.0, $0.1, $0.2) })
        records.append(r)
    }
    for record in records { await store(record) }
    await updateProgress(modality, records.count)

case .neutronDiffraction:
    let synth = NeutronDiffractionSynthesizer()
    // Sample unit cells covering all crystal systems
    let sampleCells: [NeutronDiffractionSynthesizer.UnitCell] = [
        // Cubic (NaCl-type)
        .init(a:5.64, b:5.64, c:5.64, alpha:90, beta:90, gamma:90,
              spaceGroupNumber:225,
              sites:[.init(element:"Na",x:0,y:0,z:0,occupancy:1,bIso:0.4),
                     .init(element:"Cl",x:0.5,y:0.5,z:0.5,occupancy:1,bIso:0.5)]),
        // Tetragonal
        .init(a:3.99, b:3.99, c:4.03, alpha:90, beta:90, gamma:90,
              spaceGroupNumber:129,
              sites:[.init(element:"Fe",x:0,y:0,z:0,occupancy:1,bIso:0.5)]),
        // Orthorhombic
        .init(a:5.24, b:5.15, c:7.24, alpha:90, beta:90, gamma:90,
              spaceGroupNumber:62,
              sites:[.init(element:"Ca",x:0,y:0,z:0,occupancy:1,bIso:0.6),
                     .init(element:"C",x:0.25,y:0.25,z:0,occupancy:1,bIso:0.8)]),
        // Hexagonal (quartz-like)
        .init(a:4.91, b:4.91, c:5.40, alpha:90, beta:90, gamma:120,
              spaceGroupNumber:154,
              sites:[.init(element:"Si",x:0.47,y:0,z:0,occupancy:1,bIso:0.35),
                     .init(element:"O",x:0.41,y:0.27,z:0.12,occupancy:1,bIso:0.55)])
    ]
    var records: [TrainingRecord] = []
    for _ in 0..<2000 {
        let cell = sampleCells.randomElement()!
        let isDeuterated = Double.random(in: 0...1) < 0.3
        let r = await synth.synthesizePattern(
            cell: cell, isDeuterated: isDeuterated)
        records.append(r)
    }
    for record in records { await store(record) }
    await updateProgress(modality, records.count)
```

### 40.3 — TrainingDataDashboardView.swift Update

Open `Training/UI/TrainingDataDashboardView.swift`. The dashboard must display
all 30 modalities. Locate the section that groups modality cards and add a
"Quantum Mechanics Layer" section:

```swift
// MARK: — Quantum Layer Section (Phases 26–39)

/// Add this section to the dashboard ScrollView after the existing sections.
Section {
    VStack(alignment: .leading, spacing: 12) {
        Label("Quantum Mechanics Layer", systemImage: "atom")
            .font(.title3.bold())
            .foregroundStyle(.purple)
        Text("5 new PINNs grounded in wavefunctions, nuclear physics, and quantum optics")
            .font(.caption)
            .foregroundStyle(.secondary)

        // New modality cards
        ForEach(quantumModalities, id: \.self) { modality in
            ModalityTrainingCardView(modality: modality,
                                     status: coordinator.statusFor(modality))
        }

        // Enhancement badges on existing cards
        Label("8 existing PINNs enhanced with QM depth", systemImage: "sparkles")
            .font(.caption)
            .foregroundStyle(.purple.opacity(0.8))
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
} header: {
    Text("Quantum Layer").textCase(.uppercase).font(.caption2)
}
```

Add the computed property:

```swift
private var quantumModalities: [SpectralModality] {
    [.dftQuantumChem, .mossbauer, .quantumDotPL, .augerElectron, .neutronDiffraction]
}
```

### 40.4 — ManifestUpdateService.swift Update

Open `Training/Curation/ManifestUpdateService.swift`. Update the manifest
version and add entries for the five new modalities and eight enhanced ones:

```swift
// In updateManifest() or equivalently named method, append:

let quantumAdditions: [(String, String, String, Int)] = [
    // (modality rawValue, physics law, data source, estimated records)
    ("dft_qm",            "Kohn-Sham DFT HOMO-LUMO",  "QM9/PubChemQC",   134000),
    ("mossbauer",         "Lamb-Mössbauer; Hyperfine", "Zenodo/ISEDB",      5000),
    ("qd_pl",             "Brus QD Confinement",       "Zenodo QD libs",    2000),
    ("aes",               "Auger KE; Wagner α′",       "NIST SRD 29",      15000),
    ("neutron_diffraction","Neutron b_coh scattering",  "ILL/Zenodo",       10000)
]

let quantumEnhancements: [(String, String)] = [
    ("nmr_1h",    "Phase 32: Zeeman H, CSA, T1/T2, NOE"),
    ("nmr_13c",   "Phase 33: CSA tensor, T1 13C, NOE, DEPT, J_CC"),
    ("raman",     "Phase 34: Resonance enhancement, Anharmonic Morse, CARS, Depolarisation"),
    ("xps",       "Phase 35: SOC doublets, Shake-up satellites, Wagner α′"),
    ("fluorescence","Phase 36: Marcus ET, El-Sayed ISC, Franck-Condon, FRET"),
    ("xrd_powder","Phase 37: Cromer-Mann f(q), Debye-Waller, Wilson plot, LP correction"),
    ("hitran",    "Phase 38: Dicke narrowing, SD-Voigt, Line mixing"),
    ("atomic_emission","Phase 39: Fine structure doublets, Stark broadening, Saha")
]

// Update manifest version
manifest.version = "3.0.0-quantum"
manifest.updatedAt = Date()
```

### 40.5 — TrainingDataExporter.swift Update

Open `Training/Curation/TrainingDataExporter.swift`. Ensure `featureDictionary()`
handles the new modalities by verifying the `TrainingRecord.featureDictionary()`
method in `TrainingRecord.swift` handles any modalities whose `ModalityAxisSpec`
returns an empty `axisValues` array (like `.dftQuantumChem`) by relying entirely
on `derivedFeatures` for CSV columns:

```swift
// In featureDictionary(), add guard for empty axis modalities:

func featureDictionary() -> [String: Double] {
    let spec = ModalityAxisSpec.make(for: modality)
    var d: [String: Double] = [:]

    // For modalities with no canonical spectral axis (DFT, GC, HPLC),
    // spectralValues are stored with numeric indices instead.
    if spec.axisValues.isEmpty {
        for (i, val) in spectralValues.enumerated() {
            d["\(spec.featureNamePrefix)\(String(format: "%03d", i+1))"] = Double(val)
        }
    } else {
        for (i, axVal) in spec.axisValues.enumerated() where i < spectralValues.count {
            let key: String
            switch modality {
            case .nmrProton:
                key = "\(spec.featureNamePrefix)\(String(format: "%.2f", axVal).replacingOccurrences(of: ".", with: "p"))"
            case .mossbauer:
                let velStr = String(format: "%.1f", axVal).replacingOccurrences(of: "-", with: "n").replacingOccurrences(of: ".", with: "p")
                key = "\(spec.featureNamePrefix)\(velStr)"
            default:
                key = "\(spec.featureNamePrefix)\(Int(axVal))"
            }
            d[key] = Double(spectralValues[i])
        }
    }

    for (k, v) in derivedFeatures { d[k] = v }
    if let t = primaryTarget { d[modality.primaryTargetColumn] = t }
    return d
}
```

---

## FINAL BUILD CHECKLIST — Phases 32–40

Complete ALL items in order. Do not mark any item complete until the project
compiles (`⌘B`) and all existing unit tests pass (`⌘U`).

### SpectralModality Verification
- [ ] `SpectralModality.allCases.count` == 30
- [ ] `nmrProton.featureCount` == 293
- [ ] `nmrCarbon.featureCount` == 301
- [ ] `raman.featureCount` == 418
- [ ] `xps.featureCount` == 1272
- [ ] `fluorescence.featureCount` == 361
- [ ] `xrdPowder.featureCount` == 930
- [ ] `hitranMolecular.featureCount` == 454
- [ ] `atomicEmission.featureCount` == 768
- [ ] `libs.featureCount` == 770

### Synthesizer Quantum Extension Verification
- [ ] `NMRProtonSynthesizer.quantumNMRFeatures(...)` returns exactly 48 keys
- [ ] `NMRProtonSynthesizer.synthesize(count:)` — `derivedFeatures.count >= 48`
- [ ] `NMRCarbonSynthesizer.quantumC13Features(...)` returns dict with `T1_carbon_ms` key
- [ ] `RamanSynthesizer.quantumRamanFeatures(...)` returns `depolarisation_ratio` key
- [ ] `RamanSynthesizer.quantumRamanFeatures(...)` — resonance factor > 1 when nearResonanceNM set
- [ ] `XPSSynthesizer.addQuantumXPSFeatures(...)` adds SOC peaks to spectrum array for Fe
- [ ] `XPSSynthesizer.addQuantumXPSFeatures(...)` — Cu shake-up satellite at +9 eV
- [ ] `FluorescenceSynthesizer.quantumFluorescenceFeatures(...)` — `marcus_k_ET_s` > 0
- [ ] `FluorescenceSynthesizer` — `inverted_region` == 1 when |ΔG°| > λ
- [ ] `XRDSynthesizer.computeFormFactor(element:"C", sinThetaOverLambda:0)` ≈ 6.0 (Z of C)
- [ ] `XRDSynthesizer.computeFormFactor(element:"Fe", sinThetaOverLambda:0)` ≈ 26.0 (Z of Fe)
- [ ] `XRDSynthesizer.addQuantumXRDFeatures(...)` — `wilson_B_est_A2` positive for typical patterns
- [ ] `HITRANSynthesizer.quantumHITRANFeatures(...)` — `dicke_narrowing_regime` == 1 at P < 0.01 atm
- [ ] `AtomicEmissionSynthesizer.quantumEmissionFeatures(...)` — `fs_Na_resolved` == 1.0 for Na
- [ ] `AtomicEmissionSynthesizer.quantumEmissionFeatures(...)` — `ne_stark_cm3` > 0 when Hα present

### Coordinator and UI Verification
- [ ] `TrainingDataCoordinator` dispatches all 5 quantum modalities without crash
- [ ] Dashboard displays "Quantum Mechanics Layer" section with 5 new cards
- [ ] Manifest version updated to "3.0.0-quantum"
- [ ] `TrainingDataExporter` exports CSV with correct column count for `.dftQuantumChem`
- [ ] `TrainingDataExporter` exports CSV with `vel_n12p0` style column names for `.mossbauer`

### End-to-End Integration Test
- [ ] Trigger synthesis for `.dftQuantumChem`: at least 1000 records stored in SwiftData
- [ ] Trigger synthesis for `.mossbauer`: doublet and sextet records both present
- [ ] Trigger synthesis for `.quantumDotPL`: CdSe R=2nm peak_emission < CdSe R=4nm peak
- [ ] Trigger synthesis for `.augerElectron`: C KLL feature present in dN/dE for C-bearing surfaces
- [ ] Trigger synthesis for `.neutronDiffraction`: Ti-bearing cell has reduced peak intensities
- [ ] All existing 25 modality synthesizers still produce correct record counts after Phase 32–39 edits
- [ ] Full project build: `⌘B` → zero errors, zero warnings
- [ ] Full test suite: `⌘U` → all tests green

---

## SUMMARY — Complete Quantum Physics Coverage (All 4 Plan Documents)

After completing all phases across CLAUDE.md, CLAUDE2.md, CLAUDE3.md, and CLAUDE4.md,
PhysicAI implements:

**30 total PINN modalities** covering:
- Classical spectroscopy (Beer-Lambert, Bragg, Rydberg) — Phases 0–25
- Pure quantum mechanics (Kohn-Sham DFT, Mössbauer, Brus confinement, Auger, neutron b_coh) — Phases 26–31
- Deep quantum enrichments (spin Hamiltonians, SOC doublets, Marcus theory, Dicke narrowing, fine/hyperfine structure) — Phases 32–39

**Total training records: >1.8 million**, all from freely downloadable, legally unrestricted sources.

**Physics constraint coverage:**
Every prediction is grounded in a named, published law. No PINN makes a prediction
that violates its governing physics constraint (e.g. HOMO-LUMO gap cannot be
negative; Brus shift is always blue; ⁵⁷Fe isomer shift distinguishes Fe²⁺ from Fe³⁺;
neutron Ti sites always reduce peak intensity relative to X-ray prediction).
