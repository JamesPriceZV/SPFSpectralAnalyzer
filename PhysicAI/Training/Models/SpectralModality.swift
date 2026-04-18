import Foundation

/// Every distinct spectral technique with a trained PINN model.
/// Raw value = stable string key used in CSV headers, CoreML model names,
/// SwiftData storage, and GitHub manifest package IDs.
nonisolated enum SpectralModality: String, CaseIterable, Codable, Sendable, Identifiable {
    case uvVis               = "uv_vis"
    case ftir                = "ftir"
    case nir                 = "nir"
    case raman               = "raman"
    case massSpecEI          = "mass_spec_ei"
    case massSpecMSMS        = "mass_spec_msms"
    case nmrProton           = "nmr_1h"
    case nmrCarbon           = "nmr_13c"
    case fluorescence        = "fluorescence"
    case xrdPowder           = "xrd_powder"
    case xps                 = "xps"
    case eels                = "eels"
    case atomicEmission      = "atomic_emission"
    case libs                = "libs"
    case gcRetention         = "gc_retention"
    case hplcRetention       = "hplc_retention"
    case hitranMolecular     = "hitran"
    case atmosphericUVVis    = "atmospheric_uv_vis"
    case usgsReflectance     = "usgs_reflectance"
    case opticalConstants    = "optical_constants"
    case saxs                = "saxs"
    case circularDichroism   = "circular_dichroism"
    case microwaveRotational = "microwave_rotational"
    case thermogravimetric   = "tga"
    case terahertz           = "thz"

    // ── Quantum Mechanics Layer (Phase 26) ──────────────────────────────
    case dftQuantumChem      = "dft_qm"
    case mossbauer           = "mossbauer"
    case quantumDotPL        = "qd_pl"
    case augerElectron       = "aes"
    case neutronDiffraction  = "neutron_diffraction"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uvVis:               return "UV-Vis Absorption"
        case .ftir:                return "FTIR Mid-Infrared"
        case .nir:                 return "Near-Infrared (NIR)"
        case .raman:               return "Raman Scattering"
        case .massSpecEI:          return "Mass Spec (EI)"
        case .massSpecMSMS:        return "MS/MS (Tandem)"
        case .nmrProton:           return "\u{00B9}H NMR"
        case .nmrCarbon:           return "\u{00B9}\u{00B3}C NMR"
        case .fluorescence:        return "Fluorescence"
        case .xrdPowder:           return "XRD Powder Diffraction"
        case .xps:                 return "X-ray Photoelectron (XPS)"
        case .eels:                return "EELS"
        case .atomicEmission:      return "Atomic Emission (OES)"
        case .libs:                return "LIBS Plasma"
        case .gcRetention:         return "GC Retention Index"
        case .hplcRetention:       return "HPLC Retention"
        case .hitranMolecular:     return "HITRAN Molecular Lines"
        case .atmosphericUVVis:    return "Atmospheric UV/Vis"
        case .usgsReflectance:     return "USGS Reflectance"
        case .opticalConstants:    return "Optical Constants (n, k)"
        case .saxs:                return "SAXS / SANS"
        case .circularDichroism:   return "Circular Dichroism"
        case .microwaveRotational: return "Microwave / Rotational"
        case .thermogravimetric:   return "Thermogravimetric (TGA)"
        case .terahertz:           return "Terahertz (THz)"
        case .dftQuantumChem:      return "DFT / Quantum Chemistry"
        case .mossbauer:           return "Mössbauer Spectroscopy"
        case .quantumDotPL:        return "Quantum Dot Photoluminescence"
        case .augerElectron:       return "Auger Electron Spectroscopy (AES)"
        case .neutronDiffraction:  return "Neutron Diffraction"
        }
    }

    var pinnPhysicsLaw: String {
        switch self {
        case .uvVis:               return "Beer-Lambert A=ecl; COLIPA SPF"
        case .ftir:                return "Beer-Lambert A(v)=Sum ci*ei(v); functional group rules"
        case .nir:                 return "Overtone vn=n*v0(1-Xe(n+1)); Beer-Lambert"
        case .raman:               return "I_R proportional to (v0-vm)^4|da/dQ|^2*N; Bose-Einstein"
        case .massSpecEI:          return "Isotope binomial P(13C)=0.011n; fragmentation rules"
        case .massSpecMSMS:        return "CID: alpha-cleavage, retro-Diels-Alder, McLafferty"
        case .nmrProton:           return "Shoolery d=0.23+Sum(si); Karplus J=Acos2phi-Bcosphi+C"
        case .nmrCarbon:           return "HOSE code additive increments; Grant-Paul equation"
        case .fluorescence:        return "Jablonski S1->S0; Stokes shift; QY=kr/(kr+knr)"
        case .xrdPowder:           return "Bragg nL=2d*sinT; Scherrer t=KL/(B*cosT)"
        case .xps:                 return "Photoelectric BE=hv-KE-phi; Koopmans' theorem"
        case .eels:                return "Core-loss onset=E_edge; ELNES; Kramers-Kronig"
        case .atomicEmission:      return "Rydberg 1/L=RZ^2(1/n1^2-1/n2^2); Boltzmann I_ki"
        case .libs:                return "Saha-Boltzmann; Stark broadening->ne; T from ratio"
        case .gcRetention:         return "Kovats RI=100[n+(log tx-log tn)/Dlog t]"
        case .hplcRetention:       return "Martin-Synge LFER: log k=c+eE+sS+aA+bB+lL"
        case .hitranMolecular:     return "Voigt profile S(T)*f(v-v0,gD,gL); HITRAN params"
        case .atmosphericUVVis:    return "Beer-Lambert I=I0*exp(-sigma(L,T)*N*l); J-values"
        case .usgsReflectance:     return "Kubelka-Munk F(R)=(1-R)^2/2R; continuum removal"
        case .opticalConstants:    return "Sellmeier n^2=1+Sum(Bi*L^2/(L^2-Ci)); Kramers-Kronig"
        case .saxs:                return "Guinier I(q)=I0*exp(-q^2*Rg^2/3); Porod I~q^-4"
        case .circularDichroism:   return "Cotton effect De; Drude ORD; basis-spectrum decomp"
        case .microwaveRotational: return "Rigid rotor E_J=hBJ(J+1); centrifugal distortion"
        case .thermogravimetric:   return "Arrhenius; Coats-Redfern ln(-da/dT)=ln(A/b)-Ea/RT"
        case .terahertz:           return "Drude s1(w)=s0/(1+w^2*t^2); Lorentz oscillator THz"
        case .dftQuantumChem:      return "Kohn-Sham DFT [-1/2*nabla^2+v_eff]psi=eps*psi; HOMO-LUMO gap"
        case .mossbauer:           return "f=exp(-Eg^2<x^2>/hbar^2c^2); IS=a|psi(0)|^2; QS=eQVzz"
        case .quantumDotPL:        return "Brus dE=hbar^2*pi^2/2R^2*(1/me*+1/mh*)-1.8e^2/eR"
        case .augerElectron:       return "KE(ABC)=E_A-E_B-E_C-U_eff; Wagner alpha'=KE+BE"
        case .neutronDiffraction:  return "F_N(hkl)=Sum b_j*exp(2pi*i*h*rj)*DW; b_coh isotope-specific"
        }
    }

    var featureCount: Int {
        switch self {
        case .uvVis:               return 122
        case .ftir:                return 371
        case .nir:                 return 860
        case .raman:               return 418   // Phase 34: +60 quantum features
        case .massSpecEI:          return 515
        case .massSpecMSMS:        return 507
        case .nmrProton:           return 293   // Phase 32: +48 quantum features
        case .nmrCarbon:           return 301   // Phase 33: +43 quantum features
        case .fluorescence:        return 361   // Phase 36: +54 quantum features
        case .xrdPowder:           return 930   // Phase 37: +68 quantum features
        case .xps:                 return 1272  // Phase 35: +60 quantum features
        case .eels:                return 612
        case .atomicEmission:      return 768   // Phase 39: +54 quantum features
        case .libs:                return 770   // Phase 39: +54 quantum features
        case .gcRetention:         return 52
        case .hplcRetention:       return 57
        case .hitranMolecular:     return 454   // Phase 38: +48 quantum features
        case .atmosphericUVVis:    return 651
        case .usgsReflectance:     return 1086
        case .opticalConstants:    return 403
        case .saxs:                return 208
        case .circularDichroism:   return 128
        case .microwaveRotational: return 212
        case .thermogravimetric:   return 214
        case .terahertz:           return 208
        case .dftQuantumChem:      return 380
        case .mossbauer:           return 252
        case .quantumDotPL:        return 280
        case .augerElectron:       return 420
        case .neutronDiffraction:  return 1163
        }
    }

    var primaryTargetColumn: String {
        switch self {
        case .uvVis:               return "spf"
        case .ftir:                return "compound_class"
        case .nir:                 return "moisture_pct"
        case .raman:               return "mineral_class"
        case .massSpecEI:          return "molecular_weight"
        case .massSpecMSMS:        return "compound_class"
        case .nmrProton:           return "functional_group_vector"
        case .nmrCarbon:           return "functional_group_vector"
        case .fluorescence:        return "quantum_yield"
        case .xrdPowder:           return "crystal_system"
        case .xps:                 return "surface_carbon_pct"
        case .eels:                return "element_present"
        case .atomicEmission:      return "element_present"
        case .libs:                return "plasma_temperature_K"
        case .gcRetention:         return "kovats_ri"
        case .hplcRetention:       return "retention_time_min"
        case .hitranMolecular:     return "molecule_id"
        case .atmosphericUVVis:    return "photolysis_J_value"
        case .usgsReflectance:     return "mineral_class"
        case .opticalConstants:    return "bandgap_eV"
        case .saxs:                return "rg_nm"
        case .circularDichroism:   return "alpha_helix_pct"
        case .microwaveRotational: return "rotational_constant_B_GHz"
        case .thermogravimetric:   return "decomp_temp_C"
        case .terahertz:           return "compound_class"
        case .dftQuantumChem:      return "homo_lumo_gap_eV"
        case .mossbauer:           return "iron_oxidation_state"
        case .quantumDotPL:        return "peak_emission_nm"
        case .augerElectron:       return "element_atomic_pct_json"
        case .neutronDiffraction:  return "crystal_system"
        }
    }

    var modelPackageName: String { "\(rawValue)_pinn.mlpackage" }

    var systemImage: String {
        switch self {
        case .uvVis, .atmosphericUVVis: return "sun.max.fill"
        case .ftir, .nir:               return "waveform.path"
        case .raman:                    return "sparkles"
        case .massSpecEI, .massSpecMSMS: return "chart.bar.xaxis"
        case .nmrProton, .nmrCarbon:    return "atom"
        case .fluorescence:             return "lightbulb.fill"
        case .xrdPowder:                return "circle.hexagongrid.fill"
        case .xps, .eels:               return "bolt.fill"
        case .atomicEmission, .libs:    return "flame.fill"
        case .gcRetention, .hplcRetention: return "flask.fill"
        case .hitranMolecular, .microwaveRotational: return "antenna.radiowaves.left.and.right"
        case .usgsReflectance:          return "mountain.2.fill"
        case .opticalConstants:         return "camera.filters"
        case .saxs:                     return "dot.radiowaves.right"
        case .circularDichroism:        return "arrow.triangle.2.circlepath"
        case .thermogravimetric:        return "thermometer.medium"
        case .terahertz:                return "waveform"
        case .dftQuantumChem:           return "function"
        case .mossbauer:                return "wave.3.right"
        case .quantumDotPL:             return "circle.dotted.circle"
        case .augerElectron:            return "bolt.trianglebadge.exclamationmark"
        case .neutronDiffraction:       return "circle.hexagongrid"
        }
    }

    var primaryDataSource: String {
        switch self {
        case .uvVis:              return "NIST WebBook / SDBS"
        case .ftir:               return "NIST SRD 35 / RRUFF"
        case .nir:                return "Zenodo / NIST WebBook"
        case .raman:              return "RRUFF / SDBS"
        case .massSpecEI:         return "NIST WebBook / MoNA"
        case .massSpecMSMS:       return "MoNA 700K / GNPS"
        case .nmrProton:          return "nmrshiftdb2 / SDBS"
        case .nmrCarbon:          return "nmrshiftdb2 / SDBS"
        case .fluorescence:       return "FPbase / PhotochemCAD"
        case .xrdPowder:          return "COD 500K+ CIF"
        case .xps:                return "NIST SRD 20"
        case .eels:               return "eelsdb.eu (ODbL)"
        case .atomicEmission:     return "NIST ASD"
        case .libs:               return "NIST ASD + synthesis"
        case .gcRetention:        return "NIST WebBook GC-RI"
        case .hplcRetention:      return "HMDB / PredRet"
        case .hitranMolecular:    return "HITRAN 2024"
        case .atmosphericUVVis:   return "MPI-Mainz Atlas"
        case .usgsReflectance:    return "USGS splib07"
        case .opticalConstants:   return "refractiveindex.info"
        case .saxs:               return "SASBDB"
        case .circularDichroism:  return "PCDDB"
        case .microwaveRotational: return "CDMS Cologne"
        case .thermogravimetric:  return "NIST JANAF / Zenodo"
        case .terahertz:          return "Zenodo THz datasets"
        case .dftQuantumChem:     return "QM9 / PubChemQC"
        case .mossbauer:          return "Zenodo / ISEDB"
        case .quantumDotPL:       return "Zenodo QD libraries"
        case .augerElectron:      return "NIST SRD 29"
        case .neutronDiffraction: return "ILL / Zenodo / COD"
        }
    }
}
