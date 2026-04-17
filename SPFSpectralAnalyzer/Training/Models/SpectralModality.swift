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
        }
    }

    var featureCount: Int {
        switch self {
        case .uvVis:               return 122
        case .ftir:                return 371
        case .nir:                 return 860
        case .raman:               return 358
        case .massSpecEI:          return 515
        case .massSpecMSMS:        return 507
        case .nmrProton:           return 245
        case .nmrCarbon:           return 258
        case .fluorescence:        return 307
        case .xrdPowder:           return 862
        case .xps:                 return 1212
        case .eels:                return 612
        case .atomicEmission:      return 714
        case .libs:                return 716
        case .gcRetention:         return 52
        case .hplcRetention:       return 57
        case .hitranMolecular:     return 406
        case .atmosphericUVVis:    return 651
        case .usgsReflectance:     return 1086
        case .opticalConstants:    return 403
        case .saxs:                return 208
        case .circularDichroism:   return 128
        case .microwaveRotational: return 212
        case .thermogravimetric:   return 214
        case .terahertz:           return 208
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
        }
    }
}
