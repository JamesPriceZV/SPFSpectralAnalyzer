# Universal Physical Spectral Data Analyzer — PINN Training System
## Part 1 of 2 — Architecture, Foundation, and Modalities 1–11

> **CONTINUATION:** Implementation of Phases 12–24 (atmospheric cross-sections,
> optical constants, USGS reflectance, EELS, SAXS, circular dichroism, microwave,
> TGA, THz, universal coordinator, UI, testing, manifest) is in **CLAUDE2.md**
> in this same directory. Read and execute it after completing Phase 11 here.

---

## CONCEPT EXPANSION

This app is a **universal physics-informed spectral data analysis platform**.
Its scope mirrors NIST's data-type organization across all major branches of
spectroscopy and physical measurement — not limited to UV-SPF.

**Design principles:**
- Every PINN model is grounded in a named, published physics law
- Every training dataset is freely and legally downloadable (no paywalled data)
- Model count is driven entirely by data availability — not UI slot count
- Feature vectors, targets, and physics equations are fully specified per modality
- All code is Swift 6, strict concurrency, async/await, no DispatchQueue

---

## COMPLETE MODALITY REGISTRY (25 PINNs)

| # | Modality | PINN Physics Law | Primary Free Data Source | Records |
|---|----------|-----------------|--------------------------|---------|
| 1 | UV-Vis Absorption | Beer-Lambert A=εcl; COLIPA SPF | NIST WebBook SRD 69; SDBS; MPI-Mainz | >10 000 |
| 2 | FTIR (Mid-IR) | Beer-Lambert A(ν̃)=Σcᵢεᵢ(ν̃) | NIST SRD 35 bulk; SDBS; RRUFF | >5 000 |
| 3 | Near-Infrared (NIR) | Overtone νₙ≈n·ν₀(1−χₑ(n+1)) | Zenodo splib; Mendeley; NIST WebBook | >3 000 |
| 4 | Raman | I∝(ν₀−νₘ)⁴·|∂α/∂Q|²·N | RRUFF (rruff.info/rruff.net); SDBS | >5 000 |
| 5 | Mass Spec EI | Isotope binomial; α-cleavage | NIST WebBook; MoNA; HMDB | >100 000 |
| 6 | MS/MS Tandem | CID fragmentation rules | MoNA 700K+; MassBank; GNPS | >700 000 |
| 7 | ¹H NMR | Shoolery δ; Karplus J | nmrshiftdb2; SDBS; HMDB | >53 000 |
| 8 | ¹³C NMR | HOSE code additive increments | nmrshiftdb2; SDBS; HMDB | >53 000 |
| 9 | Fluorescence | Jablonski; Φ=k_r/(k_r+k_nr) | FPbase REST API; PhotochemCAD | >800 |
| 10 | XRD Powder | Bragg nλ=2d·sinθ; Scherrer | COD 500K+ CIF; RRUFF; AMCSD | >500 000 |
| 11 | XPS | Photoelectric BE=hν−KE−φ | NIST SRD 20 (33K records) | >33 000 |
| 12 | Atomic Emission / OES | Rydberg; Boltzmann Iₖᵢ | NIST ASD (all elements, CSV) | >180 000 lines |
| 13 | LIBS | Saha-Boltzmann; Stark broadening | NIST ASD + plasma physics | Synthesized |
| 14 | GC Retention Index | Kovats RI = 100[n+(log tₓ−log tₙ)/Δ] | NIST WebBook GC-RI (SRD 1a) | >60 000 |
| 15 | HPLC Retention | Martin-Synge LFER log k=Σaᵢδᵢ | HMDB; PredRet | >100 000 |
| 16 | HITRAN Molecular Lines | Voigt profile; HITRAN S,γ,δ | HITRAN2024 (hitran.org, free reg.) | 61 molecules |
| 17 | Atmospheric UV/Vis | σ(λ,T) cross-sections; J-values | MPI-Mainz Spectral Atlas | ~800 species |
| 18 | USGS Reflectance | Kubelka-Munk F(R)=(1−R)²/2R | USGS splib07 (doi:10.5066/F7RR1WDJ) | >2 800 |
| 19 | Optical Constants | Sellmeier n²=1+ΣBᵢλ²/(λ²−Cᵢ) | refractiveindex.info (GitHub) | >1 000 |
| 20 | EELS | Core-loss ELNES; Kramers-Kronig | eelsdb.eu (ODbL, 290 spectra) | 290 |
| 21 | SAXS / SANS | Guinier I(q)=I₀exp(−q²Rg²/3) | SASBDB (sasbdb.org, free) | >5 000 |
| 22 | Circular Dichroism | Cotton effect Δε; Drude ORD | PCDDB (pcddb.cryst.bbk.ac.uk) | >1 800 |
| 23 | Microwave / Rotational | Rigid rotor E_J=hBJ(J+1) | CDMS (cdms.astro.uni-koeln.de) | ~750 species |
| 24 | Thermogravimetric (TGA) | Arrhenius ln(−dα/dT)=ln(A/β)−Ea/RT | NIST JANAF; Zenodo TGA datasets | >1 000 |
| 25 | Terahertz (THz) | Drude σ₁(ω)=σ₀/(1+ω²τ²); Lorentz | Zenodo THz pharma datasets | >500 |

**Total: 25 modalities, >1.6 million freely available spectra/records.**

---

## ARCHITECTURE

```
LAYER 1 — Data Acquisition (one actor per source)
  NISTWebBookSource  SDBSSource      RRUFFSource       CODSource
  MoNASource         MassBankEUSource GNPSSource       HMDBSource
  nmrshiftdb2Source  FPbaseSource    PhotochemCADSource NISTXPSSource
  NISTASDSource      MPIMainzSource  HITRANSource      USGSSource
  refractiveIndexSource  EELSDBSource  SASBDBSource   PCDDBSource
  CDMSSource         ZenodoNIRSource  ZenodoTHzSource
        |
        v  ReferenceSpectrum (raw, per modality)
LAYER 2 — Parsers
  JCAMPDXParser (UV, IR, Raman, NMR, MS)    CIFParser (XRD)
  RRUFFParser    MoNAJSONParser              NMRShiftDBParser
  HITRANParser   USGSTXTParser               EELSDBParser
  SASBDBParser   CDMSParser
        |
        v  structured ReferenceSpectrum
LAYER 3 — PINN Synthesizers (one actor per modality)
  BeerLambertSynthesizer (UV-Vis + FTIR + NIR)
  RamanSynthesizer        MassSpecEISynthesizer   MassSpecMSMSSynthesizer
  NMRProtonSynthesizer    NMRCarbonSynthesizer     FluorescenceSynthesizer
  XRDSynthesizer          XPSSynthesizer           AtomicEmissionSynthesizer
  LIBSSynthesizer         GCRetentionSynthesizer   HPLCSynthesizer
  HITRANSynthesizer       AtmosphericUVVisSynthesizer  USGSSynthesizer
  OpticalConstantsSynthesizer  EELSSynthesizer     SAXSSynthesizer
  CDSynthesizer           MicrowaveSynthesizer     TGASynthesizer
  THz Synthesizer
        |
        v  [TrainingRecord] (modality-tagged)
LAYER 4 — Training Data Store (SwiftData)
  StoredTrainingRecord    StoredReferenceSpectrum
        |
        v  curated dataset per modality
LAYER 5 — CoreML Training Bridge (macOS only)
  TrainingDataExporter -> CSV -> MLBoostedTreeRegressor / MLLogisticClassifier
  -> .mlpackage  (one per modality)
```

---

## FILE STRUCTURE

All paths relative to `PhysicAI/`:

```
Training/
  Models/
    SpectralModality.swift
    ModalitySchemas.swift
    TrainingRecord.swift
    ReferenceSpectrum.swift
    TrainingDataManifest.swift
    StoredTrainingRecord.swift        <- SwiftData @Model
    StoredReferenceSpectrum.swift     <- SwiftData @Model
  Parsers/
    JCAMPDXParser.swift               <- universal JCAMP
    CIFParser.swift                   <- Crystallographic Information File
    RRUFFParser.swift
    MoNAJSONParser.swift
    NMRShiftDBParser.swift
    HITRANParser.swift
    USGSTXTParser.swift
    EELSDBParser.swift
    SASBDBParser.swift
    CDMSParser.swift
  Sources/
    TrainingDataSourceProtocol.swift
    NISTWebBookSource.swift
    SDBSSource.swift
    RRUFFSource.swift
    MoNASource.swift
    MassBankEuropeSource.swift
    GNPSSource.swift
    HMDBSource.swift
    nmrshiftdb2Source.swift
    FPbaseSource.swift
    PhotochemCADSource.swift
    CODSource.swift
    AMCSDSource.swift
    NISTXPSSource.swift
    NISTASDSource.swift
    MPIMainzSource.swift
    HITRANSource.swift
    USGSSource.swift
    refractiveIndexSource.swift
    EELSDBSource.swift
    SASBDBSource.swift
    PCDDBSource.swift
    CDMSSource.swift
    ZenodoNIRSource.swift
    ZenodoTHzSource.swift
  Synthesis/
    BeerLambertSynthesizer.swift      <- UV-Vis + FTIR + NIR
    RamanSynthesizer.swift
    MassSpecEISynthesizer.swift
    MassSpecMSMSSynthesizer.swift
    NMRProtonSynthesizer.swift
    NMRCarbonSynthesizer.swift
    FluorescenceSynthesizer.swift
    XRDSynthesizer.swift
    XPSSynthesizer.swift
    AtomicEmissionSynthesizer.swift
    LIBSSynthesizer.swift
    GCRetentionSynthesizer.swift
    HPLCSynthesizer.swift
    HITRANSynthesizer.swift
    AtmosphericUVVisSynthesizer.swift
    USGSSynthesizer.swift
    OpticalConstantsSynthesizer.swift
    EELSSynthesizer.swift
    SAXSSynthesizer.swift
    CDSynthesizer.swift
    MicrowaveSynthesizer.swift
    TGASynthesizer.swift
    THz Synthesizer.swift
    SpectralNormalizer.swift
    UVFilterLibrary.swift
  Curation/
    TrainingDataCoordinator.swift
    TrainingDataExporter.swift
    ManifestUpdateService.swift
  UI/
    TrainingDataDashboardView.swift
    ModalityTrainingCardView.swift
    ReferenceLibraryView.swift
    TrainingRecordAnnotationView.swift
```

---

## PHASE 0 — Foundation Types

### 0.1 — SpectralModality.swift

Create `Training/Models/SpectralModality.swift`:

```swift
import Foundation

/// Every distinct spectral technique with a trained PINN model.
/// Raw value = stable string key used in CSV headers, CoreML model names,
/// SwiftData storage, and GitHub manifest package IDs.
enum SpectralModality: String, CaseIterable, Codable, Sendable, Identifiable {
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
        case .ftir:                return "FTIR"
        case .nir:                 return "Near-Infrared (NIR)"
        case .raman:               return "Raman Scattering"
        case .massSpecEI:          return "Mass Spec (EI)"
        case .massSpecMSMS:        return "MS/MS (Tandem)"
        case .nmrProton:           return "¹H NMR"
        case .nmrCarbon:           return "¹³C NMR"
        case .fluorescence:        return "Fluorescence"
        case .xrdPowder:           return "XRD Powder"
        case .xps:                 return "X-ray Photoelectron (XPS)"
        case .eels:                return "Electron Energy Loss (EELS)"
        case .atomicEmission:      return "Atomic Emission (OES)"
        case .libs:                return "LIBS"
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
        case .uvVis:               return "Beer-Lambert A(λ)=ε(λ)·c·l; COLIPA SPF"
        case .ftir:                return "Beer-Lambert A(ν̃)=Σcᵢεᵢ(ν̃); functional group rules"
        case .nir:                 return "Overtone νₙ≈n·ν₀(1−χₑ(n+1)); Beer-Lambert"
        case .raman:               return "I_R ∝ (ν₀−νₘ)⁴|∂α/∂Q|²N; Stokes/Bose-Einstein"
        case .massSpecEI:          return "Isotope binomial P(¹³C)=0.011n; fragmentation rules"
        case .massSpecMSMS:        return "CID: α-cleavage, retro-Diels-Alder, McLafferty"
        case .nmrProton:           return "Shoolery δ=0.23+Σσᵢ; Karplus J=Acos²φ−Bcosφ+C"
        case .nmrCarbon:           return "HOSE code additive increments; Grant-Paul equation"
        case .fluorescence:        return "Jablonski S₁→S₀; Stokes shift; Φ=k_r/(k_r+k_nr)"
        case .xrdPowder:           return "Bragg nλ=2d·sinθ; Scherrer τ=Kλ/(β·cosθ)"
        case .xps:                 return "Photoelectric BE=hν−KE−φ; Koopmans' theorem"
        case .eels:                return "Core-loss onset=E_edge; ELNES; Kramers-Kronig"
        case .atomicEmission:      return "Rydberg 1/λ=RZ²(1/n₁²−1/n₂²); Boltzmann I_ki"
        case .libs:                return "Saha-Boltzmann; Stark broadening→nₑ; T from ratio"
        case .gcRetention:         return "Kovats RI=100[n+(log tₓ−log tₙ)/Δlog t]"
        case .hplcRetention:       return "Martin-Synge LFER: log k=c+eE+sS+aA+bB+lL"
        case .hitranMolecular:     return "Voigt profile S(T)·f(ν−ν₀,γ_D,γ_L); HITRAN params"
        case .atmosphericUVVis:    return "Beer-Lambert I=I₀exp(−σ(λ,T)·N·l); J-values"
        case .usgsReflectance:     return "Kubelka-Munk F(R)=(1−R)²/2R; continuum removal"
        case .opticalConstants:    return "Sellmeier n²=1+ΣBᵢλ²/(λ²−Cᵢ); Kramers-Kronig"
        case .saxs:                return "Guinier I(q)=I₀exp(−q²Rg²/3); Porod I∝q⁻⁴"
        case .circularDichroism:   return "Cotton effect Δε; Drude ORD; basis-spectrum decomp"
        case .microwaveRotational: return "Rigid rotor E_J=hBJ(J+1); centrifugal distortion"
        case .thermogravimetric:   return "Arrhenius; Coats-Redfern ln(−dα/dT)=ln(A/β)−Ea/RT"
        case .terahertz:           return "Drude σ₁(ω)=σ₀/(1+ω²τ²); Lorentz oscillator THz"
        }
    }

    /// Total feature vector size fed to the CoreML model.
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
}
```

### 0.2 — ModalitySchemas.swift

Create `Training/Models/ModalitySchemas.swift` — defines the canonical axis grid
for each modality's spectral feature bins:

```swift
import Foundation

struct ModalityAxisSpec: Sendable {
    let axisLabel: String
    let axisUnit: String
    let axisValues: [Double]        // one value per spectral bin
    let featureNamePrefix: String   // e.g. "abs_" → columns abs_290, abs_291...

    static func make(for modality: SpectralModality) -> ModalityAxisSpec {
        switch modality {
        case .uvVis:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (290...400).map { Double($0) },
                         featureNamePrefix: "abs_")
        case .ftir:
            return .init(axisLabel: "Wavenumber (cm⁻¹)", axisUnit: "cm-1",
                         axisValues: stride(from: 400.0, through: 4000.0, by: 10.0).map { $0 },
                         featureNamePrefix: "abs_")
        case .nir:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 800.0, through: 2498.0, by: 2.0).map { $0 },
                         featureNamePrefix: "abs_")
        case .raman:
            return .init(axisLabel: "Raman Shift (cm⁻¹)", axisUnit: "cm-1",
                         axisValues: stride(from: 100.0, through: 3590.0, by: 10.0).map { $0 },
                         featureNamePrefix: "int_")
        case .massSpecEI, .massSpecMSMS:
            return .init(axisLabel: "m/z (Da)", axisUnit: "Da",
                         axisValues: (1...500).map { Double($0) },
                         featureNamePrefix: "mz_")
        case .nmrProton:
            return .init(axisLabel: "Chemical Shift ¹H (ppm)", axisUnit: "ppm",
                         axisValues: stride(from: 0.0, through: 11.95, by: 0.05).map { $0 },
                         featureNamePrefix: "d_")
        case .nmrCarbon:
            return .init(axisLabel: "¹³C Shift (ppm)", axisUnit: "ppm",
                         axisValues: (0...249).map { Double($0) },
                         featureNamePrefix: "c_")
        case .fluorescence:
            return .init(axisLabel: "Emission Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 300.0, through: 898.0, by: 2.0).map { $0 },
                         featureNamePrefix: "em_")
        case .xrdPowder:
            return .init(axisLabel: "2θ (°)", axisUnit: "deg",
                         axisValues: stride(from: 5.0, through: 89.95, by: 0.1).map { $0 },
                         featureNamePrefix: "xrd_")
        case .xps:
            return .init(axisLabel: "Binding Energy (eV)", axisUnit: "eV",
                         axisValues: (0...1199).map { Double($0) },
                         featureNamePrefix: "be_")
        case .eels:
            return .init(axisLabel: "Energy Loss (eV)", axisUnit: "eV",
                         axisValues: stride(from: 0.0, through: 2995.0, by: 5.0).map { $0 },
                         featureNamePrefix: "el_")
        case .atomicEmission, .libs:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (200...899).map { Double($0) },
                         featureNamePrefix: "em_")
        case .gcRetention, .hplcRetention:
            return .init(axisLabel: "Molecular Descriptor", axisUnit: "mixed",
                         axisValues: [],   // named columns, not axis bins
                         featureNamePrefix: "md_")
        case .hitranMolecular:
            return .init(axisLabel: "Wavenumber (cm⁻¹)", axisUnit: "cm-1",
                         axisValues: stride(from: 400.0, through: 4390.0, by: 10.0).map { $0 },
                         featureNamePrefix: "k_")
        case .atmosphericUVVis:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (150...799).map { Double($0) },
                         featureNamePrefix: "sigma_")
        case .usgsReflectance:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 350.0, through: 2500.0, by: 2.0).map { $0 },
                         featureNamePrefix: "refl_")
        case .opticalConstants:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 200.0, through: 5175.0, by: 25.0).map { $0 },
                         featureNamePrefix: "wl_")
        case .saxs:
            let logBins = stride(from: -3.0, through: 0.0, by: 0.015165)
                              .prefix(200).map { pow(10.0, $0) }
            return .init(axisLabel: "q (Å⁻¹)", axisUnit: "1/angstrom",
                         axisValues: Array(logBins),
                         featureNamePrefix: "Iq_")
        case .circularDichroism:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (180...299).map { Double($0) },
                         featureNamePrefix: "cd_")
        case .microwaveRotational:
            return .init(axisLabel: "Frequency (GHz)", axisUnit: "GHz",
                         axisValues: stride(from: 1.0, through: 996.0, by: 5.0).prefix(200).map { $0 },
                         featureNamePrefix: "f_")
        case .thermogravimetric:
            return .init(axisLabel: "Temperature (°C)", axisUnit: "degC",
                         axisValues: stride(from: 25.0, through: 1020.0, by: 5.0).prefix(200).map { $0 },
                         featureNamePrefix: "tga_")
        case .terahertz:
            return .init(axisLabel: "THz Frequency (THz)", axisUnit: "THz",
                         axisValues: stride(from: 0.1, through: 10.05, by: 0.05).prefix(200).map { $0 },
                         featureNamePrefix: "thz_")
        }
    }
}
```

### 0.3 — TrainingRecord.swift (modality-aware)

```swift
import Foundation

struct TrainingRecord: Sendable, Codable, Identifiable {
    var id: UUID = UUID()
    var modality: SpectralModality
    var sourceID: String
    var createdAt: Date = Date()
    var spectralValues: [Float]          // length = ModalityAxisSpec.axisValues.count
    var derivedFeatures: [String: Double]
    var primaryTarget: Double?
    var labelJSON: String?               // JSON for categorical / multi-label targets
    var isComputedLabel: Bool
    var computationMethod: String?

    func featureDictionary() -> [String: Double] {
        let spec = ModalityAxisSpec.make(for: modality)
        var d: [String: Double] = [:]
        for (i, axVal) in spec.axisValues.enumerated() where i < spectralValues.count {
            let key: String
            switch modality {
            case .nmrProton:
                key = "\(spec.featureNamePrefix)\(String(format: "%.2f", axVal).replacingOccurrences(of: ".", with: "p"))"
            default:
                key = "\(spec.featureNamePrefix)\(Int(axVal))"
            }
            d[key] = Double(spectralValues[i])
        }
        for (k, v) in derivedFeatures { d[k] = v }
        if let t = primaryTarget { d[modality.primaryTargetColumn] = t }
        return d
    }
}
```

### 0.4–0.5 — SwiftData Models

`StoredTrainingRecord` and `StoredReferenceSpectrum` from the original design
remain unchanged, but add `var modality: String` to both `@Model` classes.
Register both in the app's `ModelContainer` schema.

---

## PHASE 1 — Universal JCAMP-DX Parser

JCAMP-DX is the shared format for UV-Vis (NIST, SDBS, MPI-Mainz), FTIR (NIST SRD 35,
SDBS, RRUFF), Raman (SDBS), NMR (nmrshiftdb2, SDBS), and Mass Spec (NIST WebBook).

Extend the existing `JCAMPDXParser` to:

1. Detect modality from `##DATA TYPE` LDR:

```swift
nonisolated static func detectModality(from headers: [String: String]) -> SpectralModality? {
    let dt = (headers["DATA TYPE"] ?? headers["DATATYPE"] ?? "").uppercased()
    switch dt {
    case let s where s.contains("NEAR INFRARED"):   return .nir
    case let s where s.contains("INFRARED"):        return .ftir
    case let s where s.contains("UV"):              return .uvVis
    case let s where s.contains("RAMAN"):           return .raman
    case let s where s.contains("NMR") && s.contains("1H"):  return .nmrProton
    case let s where s.contains("NMR") && s.contains("13C"): return .nmrCarbon
    case let s where s.contains("NMR"):             return .nmrProton  // default 1H
    case let s where s.contains("MASS"):            return .massSpecEI
    default:                                         return nil
    }
}
```

2. Detect NIST "Not found" pages: check first 512 bytes for `<html` or `not found`.

3. Handle `##XUNITS= NANOMETERS` (UV-Vis) vs `##XUNITS= 1/CM` (IR/Raman) — convert
   all x-axes to the canonical unit for the detected modality before returning.

---

## PHASE 2A — UV-Vis PINN (Original, Enhanced)

**Data Sources:**
- NIST Chemistry WebBook SRD 69:
  `https://webbook.nist.gov/cgi/cbook.cgi?ID={CAS}&Type=UVVis-SPEC&Index=0&JCAMP=on`
- SDBS UV-Vis: `https://sdbs.db.aist.go.jp/sdbs/cgi-bin/direct_frame_disp.cgi?sdbsno={ID}`
- MPI-Mainz UV/Vis Spectral Atlas (atmospheric absorbers, free JCAMP-DX per compound):
  `https://uv-vis-spectral-atlas-mainz.org/uvvis/` — >800 species of atmospheric relevance

**PINN Physics:** Beer-Lambert A(λ) = Σᵢ cᵢ·εᵢ(λ)·l + COLIPA 2011 SPF.
Full `BeerLambertSynthesizer` code is in the original Phase 2–3 from the
previous CLAUDE.md iteration. This phase adds `MPIMainzSource` to fetch
atmospheric UV absorbers (ozone, SO₂, NO₂, BrO, HCHO, etc.) as additional
training reference spectra broadening formulation coverage.

**Feature Vector (122):** `abs_290`…`abs_400` (111) + 7 spectral metrics + 4 aux.
**Target:** `spf` (Double)

---

## PHASE 2B — FTIR PINN

**Data Sources:**
- NIST SRD 35 (5,228 gas-phase IR spectra, bulk JCAMP-DX, free):
  `https://catalog.data.gov/dataset/nist-epa-gas-phase-infrared-database-jcamp-format-srd-35`
  Download: concatenated `SRD35.jdx` or individual files by CAS number
- NIST WebBook per-compound IR:
  `https://webbook.nist.gov/cgi/cbook.cgi?ID={CAS}&Type=IR-SPEC&JCAMP=on`
- SDBS IR: same hostname, `Type=IR`
- RRUFF IR spectra: `https://rruff.info/{mineral}` → IR data tab

**PINN Physics:**
```
A(ν̃) = Σᵢ cᵢ · εᵢ(ν̃) · l       Beer-Lambert in wavenumber space

Characteristic functional group bands:
  Carbonyl (C=O):    1680–1750 cm⁻¹  (ketone 1710–1720, ester 1730–1750, acid 1700–1725)
  O-H stretch:       2500–3600 cm⁻¹  (alcohol broad, acid very broad)
  N-H:               3200–3500 cm⁻¹  (primary amine 2 bands, secondary 1 band)
  C≡N:               2200–2260 cm⁻¹  (sharp, strong for nitriles)
  C=C aromatic:      1475–1600 cm⁻¹  (two bands, characteristic pattern)
  C-H sp3:           2850–2960 cm⁻¹  (asymmetric + symmetric stretch)
  C-H sp2/aromatic:  3000–3100 cm⁻¹
  C-O-C ether:       1000–1250 cm⁻¹  (strong C-O stretch)
  S=O sulfone:       1300–1350 and 1120–1160 cm⁻¹
  P=O:               1250–1310 cm⁻¹
  C-F:               1000–1400 cm⁻¹  (very strong)
```

**Feature Vector (371):**
- `abs_400`…`abs_4000` (360 bins at 10 cm⁻¹)
- `carbonyl_index` = A(1700)/A(1465) or 0 if denominator < 1e-6
- `crystallinity_index` = A(1430)/A(1110) (polymers)
- `aliphatic_index` = integral A(2850–2960 cm⁻¹) / 110
- `aromatic_fraction` = integral A(1475–1600 cm⁻¹) / total
- `amine_index` = integral A(3200–3500 cm⁻¹) / total
- `hydroxyl_index` = integral A(2500–3600 cm⁻¹) / total
- `carbonyl_position_cm1` = ν̃ at max A in 1680–1750 window
- `fingerprint_entropy` = Shannon entropy of A(600–1500 cm⁻¹) distribution
- `double_bond_region_integral` = integral A(1500–1700 cm⁻¹)
- `total_integrated_abs` = sum × 10 cm⁻¹
- `spectral_centroid_cm1` = Σ(ν̃·A)/ΣA

**Target:** `compound_class` (string: "alcohol", "ketone", "ester", "amine",
"amide", "ether", "alkane", "alkene", "aromatic", "carboxylic_acid", etc.)

**FTIRSynthesizer actor (key methods):**

```swift
actor FTIRSynthesizer {
    private var references: [String: [Float]] = [:]   // CAS -> 360-bin grid
    private let grid = stride(from: 400.0, through: 4000.0, by: 10.0).map { $0 }

    func loadReference(casNumber: String, rawWN: [Double], rawAbs: [Double]) {
        if let g = SpectralNormalizer.resampleToGrid(x: rawWN, y: rawAbs, grid: grid) {
            references[casNumber] = g
        }
    }

    func synthesize(count: Int) async -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        let keys = Array(references.keys)
        guard keys.count >= 2 else { return [] }
        for _ in 0..<count {
            let nComp = Int.random(in: 1...min(4, keys.count))
            let chosen = (0..<nComp).map { _ in keys.randomElement()! }
            let conc = (0..<nComp).map { _ in Float.random(in: 0.001...0.05) }
            var spectrum = [Float](repeating: 0, count: grid.count)
            for (cas, c) in zip(chosen, conc) {
                guard let ref = references[cas] else { continue }
                for i in 0..<grid.count { spectrum[i] += ref[i] * c }
            }
            spectrum = spectrum.map { max(0, $0 + Float.random(in: -0.001...0.001)) }
            let derived = deriveFTIRFeatures(spectrum)
            records.append(TrainingRecord(
                modality: .ftir, sourceID: "synth_beer_lambert_ftir",
                spectralValues: spectrum, derivedFeatures: derived,
                primaryTarget: nil, labelJSON: nil,
                isComputedLabel: true, computationMethod: "BeerLambert_FTIR"))
        }
        return records
    }

    private func deriveFTIRFeatures(_ s: [Float]) -> [String: Double] {
        let a = s.map { Double($0) }
        var d: [String: Double] = [:]
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 10
        }
        let carbWin = zip(grid, a).filter { $0.0 >= 1680 && $0.0 <= 1750 }.map { $0.1 }
        let methylWin = zip(grid, a).filter { $0.0 >= 1430 && $0.0 <= 1470 }.map { $0.1 }
        d["carbonyl_index"] = (methylWin.max() ?? 0) > 1e-6 ?
            (carbWin.max() ?? 0) / methylWin.max()! : 0
        d["aliphatic_index"] = integral(2850, 2960) / max(1e-9, a.reduce(0, +) * 10)
        d["aromatic_fraction"] = integral(1475, 1600) / max(1e-9, a.reduce(0, +) * 10)
        d["total_integrated_abs"] = a.reduce(0, +) * 10
        return d
    }
}
```

---

## PHASE 2C — NIR PINN

**Data Sources:**
- Zenodo NIR soil library: `https://zenodo.org/records/7586622`
  (2,106 samples, 1350–2550 nm, NeoSpectra handheld)
- Mendeley NIR soil: `https://data.mendeley.com/datasets/h8mht3jsbz/1`
- ISP NIR Spectral Library (6049 spectra):
  `https://ir-spectra.com/download/IS_NIR_Spectra.htm` (free download)
- NIST WebBook near-IR: same URL pattern as FTIR; filter `##XUNITS= NANOMETERS`
  and xrange 800–2500 nm

**PINN Physics:**
```
Anharmonic oscillator overtone positions:
  νₙ = n · ν₀ · (1 − χₑ(n+1))
  χₑ = anharmonicity constant
  C-H fundamental ν₀ ≈ 3000 cm⁻¹ (3333 nm):
    1st overtone 2 × 3000 × (1 − 2χₑ)  ≈ 5800 cm⁻¹ → 1724 nm
    2nd overtone ≈ 8600 cm⁻¹ → 1163 nm
  O-H fundamental ν₀ ≈ 3500 cm⁻¹ (2857 nm):
    1st overtone ≈ 6800 cm⁻¹ → 1471 nm
    2nd overtone ≈ 10100 cm⁻¹ → 990 nm
  N-H combination band ≈ 4800–5000 cm⁻¹ → 2000–2083 nm
  C=O combination ≈ 5000–5300 cm⁻¹ → 1887–2000 nm
```

**Feature Vector (860):**
- `abs_800`…`abs_2498` (850 bins at 2 nm)
- `oh_1st_overtone` = integral 1400–1450 nm
- `ch_1st_overtone` = integral 1650–1750 nm
- `oh_combination` = integral 1900–2000 nm
- `protein_band` = integral 2050–2200 nm
- `starch_band` = integral 2200–2320 nm
- `fat_band` = integral 2300–2350 nm
- `moisture_ratio` = oh_1st_overtone / total_integral
- `ch_oh_ratio` = ch_1st_overtone / max(oh_1st_overtone, 1e-9)
- `spectral_variance` = variance of 850 bins
- `total_integral` = sum of 850 bins × 2 nm

**Target:** `moisture_pct`, `protein_pct`, `fat_pct` (from reference values in datasets)

---

## PHASE 3 — Raman PINN

**Data Sources:**
- RRUFF Project (primary source): `https://rruff.info/` and updated `https://rruff.net/`
  Individual mineral: `https://rruff.info/{Mineral}/display=default/R{ID}`
  File format: plain `.txt` with `X=` and `Y=` arrays
- SDBS Raman section: filter for Raman spectrum type

**RRUFF `.txt` format:**
```
##RRUFFID=R050058
X= 147.54, 154.42, 161.58, ...   (Raman shift, cm⁻¹)
Y= 7.8, 9.1, 12.4, ...           (intensity, arbitrary units)
##END=
```

**PINN Physics:**
```
Raman scattering intensity:
  I_R(νₘ) ∝ I₀ · (ν₀ − νₘ)⁴ · |∂α/∂Q|² · N · f(T)
  Stokes shift: Δν̃ = νₘ (molecular vibration frequency, cm⁻¹)
  Anti-Stokes correction: f(T) = [1 − exp(−hcνₘ/kT)]⁻¹  (Bose-Einstein)
  Fluorescence background: polynomial baseline B(ν̃) = Σ aₙν̃ⁿ
```

**Feature Vector (358):**
- `int_100`…`int_3500` (350 bins at 10 cm⁻¹, max-normalised)
- `d_band` = integral 1300–1400 cm⁻¹ (carbon D band)
- `g_band` = integral 1500–1620 cm⁻¹ (carbon G band)
- `d_g_ratio` = d_band / max(g_band, 1e-9)
- `fingerprint_integral` = integral 200–1200 cm⁻¹
- `high_freq_integral` = integral 2700–3200 cm⁻¹
- `peak_position_cm1` = wavenumber at global maximum
- `background_slope` = linear slope of the baseline
- `peak_fwhm_cm1` = FWHM of the strongest peak

**Target:** `mineral_class` (categorical, RRUFF mineral name)

```swift
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

    func synthesize(count: Int) async -> [TrainingRecord] {
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
            let kTcm = 207.2  // kT in cm⁻¹ at 298 K (kT = 0.02585 eV = 207.2 cm⁻¹)
            for i in 0..<grid.count {
                let nu = grid[i]
                let beCorr = Float(1.0 / (1.0 - exp(-nu / kTcm)))
                spectrum[i] *= beCorr
            }
            // Add fluorescence background + shot noise
            let bgSlope = Float.random(in: 0...0.0003)
            spectrum = spectrum.enumerated().map { i, v in
                max(0, v + bgSlope * Float(i) * 0.001 + Float.random(in: -0.01...0.01))
            }
            let derived = deriveRamanFeatures(spectrum)
            records.append(TrainingRecord(
                modality: .raman, sourceID: "rruff_synth_\(chosen.first ?? "?")",
                spectralValues: spectrum, derivedFeatures: derived,
                primaryTarget: nil,
                labelJSON: try? String(data: JSONEncoder().encode(chosen.first ?? "unknown"),
                                       encoding: .utf8),
                isComputedLabel: true, computationMethod: "BoseEinstein_Raman"))
        }
        return records
    }

    private func deriveRamanFeatures(_ s: [Float]) -> [String: Double] {
        let a = s.map { Double($0) }
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 10
        }
        let peakIdx = s.enumerated().max(by: { $0.1 < $1.1 })!.0
        return [
            "d_band":            integral(1300, 1400),
            "g_band":            integral(1500, 1620),
            "d_g_ratio":         integral(1300, 1400) / max(integral(1500, 1620), 1e-9),
            "fingerprint_integral": integral(200, 1200),
            "high_freq_integral":   integral(2700, 3200),
            "peak_position_cm1": grid[peakIdx],
            "background_slope":  Double(s.last ?? 0) - Double(s.first ?? 0),
        ]
    }
}
```

---

## PHASE 4A — EI Mass Spectrometry PINN

**Data Sources:**
- NIST Chemistry WebBook free EI-MS (JCAMP-MS format):
  `https://webbook.nist.gov/cgi/cbook.cgi?ID={CAS}&Type=Mass-Spec&JCAMP=on`
- MassBank of North America (MoNA) — bulk JSON download:
  `https://mona.fiehnlab.ucdavis.edu/rest/downloads`
  Select "MoNA-export-EI-Spectra.json.gz" (free, no login)
- HMDB MS: `https://hmdb.ca/system/downloads/current/hmdb_metabolites.zip`

**PINN Physics:**
```
Isotope pattern (binomial approximation):
  M+1 intensity (%) ≈ 1.1% × n_C + 0.36% × n_N + 0.015% × n_S + 0.012% × n_H
  M+2 intensity (%) ≈ (1.1% × n_C)² / 200 + 4.25% × n_S + 0.2% × n_O
  Chlorine: I(M+2)/I(M) ≈ 0.3249 per Cl atom
  Bromine:  I(M+2)/I(M) ≈ 0.9732 per Br atom

Nitrogen rule: M⁺ is odd → odd number of N atoms
α-Cleavage: bond adjacent to heteroatom / π-system cleaves preferentially
```

**Feature Vector (515):**
- `mz_1`…`mz_500` (500 bins, 1 Da, normalised to base peak = 1.0)
- `molecular_ion_mz`, `base_peak_mz`, `base_peak_fragment` (= MW − base_peak_mz)
- `m_plus_1_ratio`, `m_plus_2_ratio`
- `even_electron` (1 if MW even, 0 if odd — N-rule indicator)
- `num_peaks_above_5pct`, `high_mass_fragments`, `low_mass_fragments`
- `mz_77_present`, `mz_91_present`, `mz_43_present`, `mz_57_present`, `mz_105_present`
  (diagnostic ions for phenyl, tropylium, acetyl, tBu, benzoyl)
- `ring_dbe` = (2C + 2 + N − H − X)/2 (degree of unsaturation)

**Target:** `molecular_weight` (Double), `molecular_formula` (string), `compound_class`

---

## PHASE 4B — MS/MS Tandem PINN

**Data Sources:**
- MoNA MS/MS bulk JSON: `https://mona.fiehnlab.ucdavis.edu/rest/downloads`
  "MoNA-export-All-Spectra.json.gz" (700K+ spectra) — includes ClassyFire class
- MassBank Europe GitHub releases (versioned ZIP):
  `https://github.com/MassBank/MassBank-data/releases/latest` → `.zip`
  Contains individual `.txt` records with `PK$PEAK` arrays
- GNPS spectral libraries:
  `https://gnps.ucsd.edu/ProteoSAFe/libraries.jsp` → download individual libraries
- HMDB MS/MS: `https://hmdb.ca/spectra/ms_ms/list` (metabolite MS/MS, free)

**Feature Vector (507):** 500 m/z bins (1–500 Da) + `precursor_mz` +
`collision_energy_ev` + `fragment_coverage` (% m/z space with signal) +
`neutral_loss_18` (water loss), `neutral_loss_44` (CO₂ loss), `max_fragment_mz`,
`num_fragments_above_5pct`

**Target:** `compound_class` (ClassyFire level-2 class), `molecular_formula`

---

## PHASE 5A — ¹H NMR PINN

**Data Sources:**
- nmrshiftdb2 bulk download (SDF + NMReDATA, free, CC0):
  `https://nmrshiftdb.nmr.uni-koeln.de/nmrshiftdb/` → Download → All spectra SDF
  53,954 measured spectra, 44,909 structures
- SDBS ¹H NMR: ~35,000 spectra at `https://sdbs.db.aist.go.jp/`
- HMDB NMR 1D: `https://hmdb.ca/spectra/nmr_one_d/list`

**PINN Physics:**
```
Shoolery's rules (¹H δ relative to TMS):
  δ = δ_base + Σ σᵢ     (additive substituent contributions)
  δ_base = 0.23 ppm for −CH₃
  Example σ values:
    =O  (carbonyl adjacent):  +1.20
    −OH (alcohol):            +1.74
    −Cl:                      +2.53
    −Br:                      +2.33
    −Ph (phenyl):             +1.85
    −C=C- (vinyl):            +1.32
    −COOH:                    +0.97
    −NH₂:                     +0.53
    −O− (ether):              +1.14
    −NO₂:                     +3.36

Karplus equation (vicinal ³J_HH coupling):
  J = A·cos²(φ) − B·cos(φ) + C
  Haasnoot parameters: A=10.4, B=1.5, C=0.2 Hz
  φ = H−C−C−H dihedral angle
```

**Feature Vector (245):**
- `d_0.00`…`d_11.95` (240 bins at 0.05 ppm: column names use underscore for dot)
- `aromatic_proton_fraction` = integral 6.5–8.5 ppm / total
- `aldehyde_present` = 1 if max peak > 9.0 ppm exceeds threshold
- `oh_nh_present` = broad signal > 9.5 ppm
- `methyl_count_est` = integral 0.8–1.0 ppm / 3H
- `ch2_count_est` = integral 1.2–1.5 ppm / 2H

**Target:** `functional_group_vector` (JSON array, 12 booleans)

```swift
actor NMRProtonSynthesizer {
    private let shoolery: [String: Double] = [
        "carbonyl": 1.20, "hydroxyl": 1.74, "chloro": 2.53,
        "bromo": 2.33,    "phenyl": 1.85,   "vinyl": 1.32,
        "carboxyl": 0.97, "amine": 0.53,    "ether": 1.14,
        "nitro": 3.36,    "cyano": 1.05,    "fluorine": 1.55
    ]
    private let gridPPM = stride(from: 0.0, through: 11.95, by: 0.05).map { $0 }
    private let lw = 0.05  // ppm Lorentzian FWHM

    func synthesize(count: Int) async -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            var s = [Float](repeating: 0, count: gridPPM.count)
            addPeak(&s, center: 0.90, area: 3.0)       // CH₃ backbone
            addPeak(&s, center: 1.25, area: Float.random(in: 4...20))  // CH₂ chain

            let groups = Array(shoolery.keys.shuffled().prefix(Int.random(in: 1...3)))
            for g in groups {
                let shift = 1.25 + (shoolery[g] ?? 0)
                addPeak(&s, center: shift, area: Float.random(in: 1...3))
            }
            s = s.map { $0 + Float.random(in: 0...0.002) }

            var derived: [String: Double] = [:]
            let a = s.map { Double($0) }; let tot = a.reduce(0, +)
            derived["aromatic_proton_fraction"] = tot > 0 ?
                zip(gridPPM, a).filter { $0.0 >= 6.5 && $0.0 <= 8.5 }
                               .map { $0.1 }.reduce(0, +) / tot : 0
            derived["aldehyde_present"] = (zip(gridPPM, a)
                .filter { $0.0 > 9.0 }.map { $0.1 }.max() ?? 0) > 0.05 ? 1 : 0

            let lbl = try? String(data: JSONEncoder().encode(groups), encoding: .utf8)
            records.append(TrainingRecord(
                modality: .nmrProton, sourceID: "synth_shoolery",
                spectralValues: s, derivedFeatures: derived,
                primaryTarget: nil, labelJSON: lbl,
                isComputedLabel: true, computationMethod: "Shoolery_Karplus"))
        }
        return records
    }

    private func addPeak(_ s: inout [Float], center: Double, area: Float) {
        for (i, ppm) in gridPPM.enumerated() {
            let dx = ppm - center
            let lorentz = lw / (2 * .pi) / (dx*dx + (lw/2)*(lw/2))
            s[i] += area * Float(lorentz * 0.05)
        }
    }
}
```

---

## PHASE 5B — ¹³C NMR PINN

**Data Sources:** Same as Phase 5A (nmrshiftdb2, SDBS). Filter `##NUCLEUS= 13C`.

**PINN Physics:**
```
Grant-Paul additive increments (¹³C shifts for alkyl carbons):
  δ_C = δ_base + Σ Aᵢ·nᵢ
  A_α = +9.1 ppm (per α carbon), A_β = +9.4, A_γ = −2.5, A_δ = +0.3

Characteristic ¹³C regions:
  Carbonyl C=O:   165–220 ppm (aldehyde 195–205, ketone 205–220, ester 165–180)
  Aromatic C:     110–160 ppm
  Alkene C:        100–150 ppm
  Alkyne C:        60–90 ppm
  O-bearing C:     50–90 ppm (alcohols, ethers, esters)
  Aliphatic C:     0–50 ppm
```

**Feature Vector (258):** `c_0`…`c_249` (250 bins at 1 ppm) +
`carbonyl_count_est`, `aromatic_fraction`, `alkene_fraction`,
`oxygenated_fraction`, `aliphatic_fraction`, `unique_peaks_est`,
`symmetry_index`, `total_integral`

**Target:** `functional_group_vector`, `molecular_formula`

---

## PHASE 6 — Fluorescence PINN

**Data Sources:**
- FPbase REST API (no auth):
  List: `https://www.fpbase.org/api/proteins/?fields=name,excitation_max,emission_max,quantum_yield`
  Spectrum: `https://www.fpbase.org/api/spectra/{id}/` (returns JSON with wavelength + ex/em data)
  GraphQL: `https://www.fpbase.org/graphql/`
- PhotochemCAD (~250 fluorophore spectra, free download as tabular ASCII):
  `https://omlc.org/spectra/PhotochemCAD/`

**PINN Physics:**
```
Stokes shift (cm⁻¹):
  Δν̃ = (1/λ_ex − 1/λ_em) × 10⁷   (λ in nm)

Inner filter correction:
  I_corr = I_obs × 10^((A_ex + A_em) / 2)

Quantum yield:
  Φ = k_r / (k_r + k_nr + k_ISC + k_ET)
  k_r (radiative) ≈ 1/τ_rad ≈ 10⁸–10⁹ s⁻¹ for allowed transitions
  Φ > 0.9 requires k_nr << k_r

FRET efficiency (when donor–acceptor pair):
  E = R₀⁶ / (R₀⁶ + r⁶)
  R₀ (Förster radius) = 0.211 · (κ²·n⁻⁴·Φ_D·J)^(1/6) nm
```

**Feature Vector (307):**
- `em_300`…`em_898` (300 bins at 2 nm, normalised max=1)
- `excitation_nm` (1 scalar)
- `peak_emission_nm`, `stokes_shift_cm`, `emission_fwhm_nm`
- `emission_asymmetry` = (λ_em − λ_half_left)/(λ_half_right − λ_em)
- `red_tail_fraction` = integral (λ_em + 30 nm to 900 nm) / total

**Target:** `quantum_yield` (Double 0–1), `peak_emission_nm`, `stokes_shift_cm`

---

## PHASE 7 — XRD Powder PINN

**Data Sources:**
- Crystallography Open Database (COD, CC0):
  `https://www.crystallography.net/cod/` — bulk archive ~7 GB as `.tgz`
  Individual CIF: `https://www.crystallography.net/cod/{COD-ID}.cif`
  REST API: `https://www.crystallography.net/cod/optimade/`
- RRUFF XRD: `https://rruff.info/{mineral}` → XRD powder pattern tab
- AMCSD: `https://rruff.geo.arizona.edu/AMS/amcsd.php`

**PINN Physics:**
```
Bragg's law:     2θ = 2 · arcsin(nλ / 2d)   with λ = 1.5406 Å (Cu Kα₁)
Scherrer eq:     β = Kλ / (τ·cosθ)           K = 0.9, β in radians
Structure factor: |F(hkl)|² = |Σ fⱼ · exp(2πi(hxⱼ+kyⱼ+lzⱼ))|²
Pseudo-Voigt:    PV(x) = η·L(x) + (1−η)·G(x),  η ≈ 0.5 (typical)
```

**Feature Vector (862):**
- `xrd_50`…`xrd_890` (850 bins at 0.1° 2θ, 5–90°)
- `peak_count`, `strongest_peak_2theta`, `d100_spacing_ang`,
  `peak_width_fwhm_deg`, `background_level`, `pattern_complexity`,
  `high_angle_fraction`, `low_angle_peaks`, `crystallinity_ratio`,
  `unit_cell_vol_est_A3`, `amorphous_hump`, `peak_density_per100deg`

**Target:** `crystal_system` (7 classes), `crystallite_size_nm`

```swift
actor XRDSynthesizer {
    struct DiffractionPeak: Sendable {
        let dSpacing: Double      // Å
        let relIntensity: Double  // 0–100
    }
    private let lambda = 1.5406  // Cu Kα₁ Å
    private let twoThetaGrid = stride(from: 5.0, through: 89.95, by: 0.1).map { $0 }

    func synthesizePattern(peaks: [DiffractionPeak],
                           crystalliteSize: Double = Double.random(in: 20...200),
                           eta: Double = 0.5) -> [Float] {
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
                let gauss = exp(-(dx*dx) / (2*sigma*sigma))
                let lorentz = 1.0 / (1.0 + (dx/(betaDeg/2.0))*(dx/(betaDeg/2.0)))
                let pv = eta * lorentz + (1 - eta) * gauss
                pattern[i] += Float(pk.relIntensity / 100.0 * pv)
            }
        }
        for i in 0..<pattern.count {
            pattern[i] += Float.random(in: 0.001...0.006)  // background
        }
        return pattern
    }
}
```

---

## PHASE 8 — Atomic Emission / OES PINN

**Data Sources:**
- NIST Atomic Spectra Database (ASD) — free, all elements:
  Lines form (CSV output):
  `https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra={El}&low_w=200&high_w=900&unit=1&format=2&line_out=0&en_unit=0&output=0&bibrefs=1&page_size=15&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&max_low_enrg=&show_av=2&max_upp_enrg=&tsb_value=0&min_str=&A_out=1&intens_out=on&allowed_out=1&forbid_out=1&no_spaces=1&submit=Retrieve+Data`
  Replace `{El}` with element symbol. Returns observed wavelengths + A_ki + E_k.

**PINN Physics:**
```
Boltzmann intensity (optically thin plasma):
  I_ki = (hcA_ki·g_k·N) / (4π·U(T)) · exp(−E_k / kT)
  U(T) = Σᵢ gᵢ · exp(−Eᵢ/kT)       (partition function)

Plasma temperature from two-line method:
  T = (E₂ − E₁) / k · 1/[ln(I₁A₂g₂λ₁ / I₂A₁g₁λ₂)]

Voigt profile broadening:
  γ_D = (ν₀/c) · √(2kT·ln2 / m)    (Doppler half-width)
  γ_L ≈ A_ki / (4π)                  (natural half-width)
```

**Feature Vector (714):**
- `em_200`…`em_899` (700 bins at 1 nm)
- `plasma_temperature_est_K`, `strongest_line_nm`, `element_count_est`,
  `alkali_indicator`, `calcium_indicator`, `iron_indicator`,
  `hydrogen_balmer_alpha`, `ionized_fraction_est`, `continuum_level`,
  `total_integrated_emission`, `spectral_entropy`,
  `peak_density_per100nm`, `line_background_ratio`, `strongest_line_intensity`

**Target:** `element_present` (JSON multi-label), `plasma_temperature_K`

---

## PHASE 9A — GC Retention Index PINN

**Data Sources:**
- NIST WebBook GC-RI (free subset via WebBook, bulk via SRD 1a):
  Per-compound: `https://webbook.nist.gov/cgi/cbook.cgi?ID={CAS}&Type=RI&Mask=2000`
  SRD 1a contains >60,000 Kovats RI values on standard non-polar columns
- NIST AMDIS / NIST MS Search includes RI data free with registration

**PINN Physics:**
```
Kovats Retention Index (isothermal):
  I = 100n + 100 · [log t_R(x) − log t_R(n)] / [log t_R(n+1) − log t_R(n)]

Abraham's LSER (log k prediction on non-polar column):
  log k = c + eE + sS + aA + bB + lL
  E = excess molar refraction, S = dipolarity/polarisability
  A = H-bond acidity, B = H-bond basicity, L = log L¹⁶
```

**Feature Vector (52):** 50 molecular descriptors + `column_type` + `temperature_C`
Descriptors: `mw`, `logp`, `tpsa`, `hbd`, `hba`, `rotatable_bonds`,
`aromatic_rings`, `aliphatic_rings`, `sp3_fraction`, `molar_refractivity`,
`carbon_count`, `nitrogen_count`, `oxygen_count`, `sulfur_count`,
`halogen_count`, `double_bond_count`, `triple_bond_count`,
`ring_count`, `complexity_score`, `mcgowan_volume`,
Abraham: `E_excess`, `S_dipolar`, `A_hb_acidity`, `B_hb_basicity`,
`L_hexadecane`, `V_mcgowan`, plus 24 molecular fingerprint bits (PubChem substructure).

**Target:** `kovats_ri` (Double)

---

## PHASE 9B — HPLC Retention PINN

**Data Sources:**
- HMDB retention times (reversed-phase C18):
  `https://hmdb.ca/spectra/c_ms/list` → includes LC method + RT
- PredRet: `https://predret.org/` (free, thousands of HPLC RT values)
- RepoRT Zenodo dataset: `https://zenodo.org/record/5143070` (HILIC + RP data)

**Feature Vector (57):** Same 50 molecular descriptors + `mobile_phase_aq_pct`,
`mobile_phase_org_type` (0=MeCN, 1=MeOH), `gradient_type` (0=isocratic, 1=gradient),
`column_length_mm`, `flow_rate_ml_min`, `ph_aq_phase`, `ionic_strength_mM`

**Target:** `retention_time_min` (Double)

---

## PHASE 10 — XPS PINN

**Data Sources:**
- NIST XPS Database SRD 20 (free, >33,000 records):
  Online: `https://srdata.nist.gov/xps/`
  REST API: `https://srdata.nist.gov/xps/api/`
  Bulk: `https://catalog.data.gov/dataset/nist-x-ray-photoelectron-spectroscopy-database-srd-20`

**PINN Physics:**
```
Photoelectric equation:
  BE = hν − KE − φ_sp
  hν = Al Kα = 1486.6 eV (or Mg Kα = 1253.6 eV)
  φ_sp = spectrometer work function (~4.5 eV)

Koopmans' theorem: BE ≈ −ε_i (Hartree-Fock orbital energy)
Chemical shift (charge potential model):
  ΔBE ≈ k·Δq + ΔV_M
  Δq = change in atomic charge, ΔV_M = Madelung potential

Scofield photoionisation cross-sections at 1486.6 eV (relative to C 1s = 1.00):
  O 1s: 2.93,  N 1s: 1.80,  Si 2p: 0.87,  Fe 2p: 12.4
  Al 2p: 0.54, Ti 2p: 7.9,  S 2p: 1.68,   F 1s: 4.43
  Cl 2p: 2.28, Cu 2p: 21.1, Zn 2p: 22.0
```

**Feature Vector (1212):**
- `be_0`…`be_1199` (1200 bins at 1 eV, 0–1199 eV)
- `c1s_position`, `o1s_position`, `n1s_present`, `si2p_present`,
  `carbon_oxygen_ratio`, `surface_carbon_pct`, `oxidized_carbon_pct`,
  `c_sp2_pct`, `oxide_present`, `hydroxide_present`,
  `shirley_bg_area`, `total_signal_area`

**Target:** `surface_carbon_pct` (Double), plus multi-output JSON for
`element_atomic_pct` dict and `oxidation_state` dict per element

```swift
actor XPSSynthesizer {
    private let photonEnergy = 1486.6   // Al Kα eV
    private let beGrid = (0..<1200).map { Double($0) }
    private let coreLevelBE: [String: Double] = [
        "C1s": 284.8, "O1s": 532.0, "N1s": 400.0, "Si2p": 99.5,
        "Fe2p": 706.8, "Al2p": 72.8, "Ti2p": 453.8, "S2p": 164.0,
        "F1s": 686.0, "Cl2p": 199.0, "Cu2p": 932.7, "Zn2p": 1021.8
    ]
    private let scofield: [String: Double] = [
        "C1s": 1.00, "O1s": 2.93, "N1s": 1.80, "Si2p": 0.87,
        "Fe2p": 12.4, "Al2p": 0.54, "Ti2p": 7.90, "S2p": 1.68
    ]

    func synthesizeSurface(elements: [(symbol: String, atomicPct: Double,
                                       oxidationState: Int)]) -> [Float] {
        var spectrum = [Float](repeating: 0, count: 1200)
        for (el, pct, oxState) in elements {
            let baseKey = "\(el)1s"
            guard let baseBE = coreLevelBE[baseKey] ?? coreLevelBE["\(el)2p"] else { continue }
            let shift = oxidationShift(element: el, state: oxState)
            let be = baseBE + shift
            let sf = scofield[baseKey] ?? scofield["\(el)2p"] ?? 1.0
            let area = Float(pct * sf / 100.0)
            let sigma = 0.9   // eV FWHM instrument
            for i in 0..<1200 {
                let dx = beGrid[i] - be
                spectrum[i] += area * Float(exp(-(dx*dx)/(2*sigma*sigma))/(sigma*2.507))
            }
        }
        return spectrum
    }

    private func oxidationShift(element: String, state: Int) -> Double {
        let shifts: [String: [Int: Double]] = [
            "C":  [1: 1.5, 2: 3.0, 3: 4.2, 4: 5.0],
            "Fe": [2: 1.5, 3: 3.8],
            "Ti": [2: 1.0, 3: 2.5, 4: 4.0],
            "Si": [4: 3.9]
        ]
        return shifts[element]?[state] ?? 0.0
    }
}
```

---

## PHASE 11 — HITRAN Molecular Lines PINN

**Data Sources:**
- HITRAN2024 (free, registration required):
  `https://hitran.org/lbl/` — line-by-line parameters per molecule
  `https://hitran.org/data/` — partition functions, supplementary
  Format: HITRAN 160-character `.par` format
  Contains: 61 molecules, 156 isotopologues, millions of transitions

**PINN Physics:**
```
Absorption coefficient simulation:
  k(ν, T, P) = Σ_lines S(T) · f_Voigt(ν − ν₀; γ_D(T), γ_L(T,P))

Temperature-scaled line intensity:
  S(T) = S(T₀) · Q(T₀)/Q(T) · exp(−hcE''/k·(1/T−1/T₀))
                             · [1−exp(−hcν₀/kT)] / [1−exp(−hcν₀/kT₀)]
  T₀ = 296 K (HITRAN reference temperature)

Doppler half-width (Gaussian):
  γ_D(T) = (ν₀/c) · √(2kT ln2 / m_molecular)

Lorentzian half-width (pressure):
  γ_L(T,P) = (T₀/T)^n_air · (γ_air·P_air + γ_self·P_self)

Voigt profile: numerical convolution via Faddeeva function approximation
  V(ν; γ_D, γ_L) = Re[w(z)]/√π·γ_D   where z = (ν + iγ_L)/γ_D
```

**Feature Vector (406):**
- Simulated k(ν) at 400 wavenumber bins (10 cm⁻¹ spacing, 400–4390 cm⁻¹)
- 6 simulation condition features:
  `temperature_K`, `pressure_atm`, `pathlength_m`,
  `concentration_ppmv`, `molecule_id`, `isotopologue_id`

**Target:** `molecule_id` (int), `temperature_K` (Double)

**HITRANParser — 160-character fixed-width `.par` format:**
```swift
enum HITRANParser {
    struct Line: Sendable {
        let moleculeID: Int        // chars 1-2
        let isotopeID: Int         // char 3
        let wavenumber: Double     // chars 4-15  (cm⁻¹)
        let intensity: Double      // chars 16-25 (cm⁻¹/mol·cm⁻²)
        let einsteinA: Double      // chars 26-35
        let airHalfWidth: Double   // chars 36-40 (cm⁻¹/atm)
        let selfHalfWidth: Double  // chars 41-45
        let lowerEnergy: Double    // chars 46-55 (cm⁻¹)
        let tempExponent: Double   // chars 56-59
        let airPressureShift: Double // chars 60-67
    }

    nonisolated static func parse(data: Data) throws -> [Line] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParserError.invalidEncoding
        }
        return text.components(separatedBy: "\n").compactMap { parseLine($0) }
    }

    private nonisolated static func parseLine(_ raw: String) -> Line? {
        guard raw.count >= 100 else { return nil }
        func substr(_ a: Int, _ b: Int) -> String {
            let si = raw.index(raw.startIndex, offsetBy: a)
            let ei = raw.index(raw.startIndex, offsetBy: min(b, raw.count))
            return String(raw[si..<ei]).trimmingCharacters(in: .whitespaces)
        }
        guard let mol = Int(substr(0, 2)),
              let iso = Int(substr(2, 3)),
              let nu  = Double(substr(3, 15)),
              let s   = Double(substr(15, 25)) else { return nil }
        let a    = Double(substr(25, 35)) ?? 0
        let gAir = Double(substr(35, 40)) ?? 0
        let gSelf = Double(substr(40, 45)) ?? 0
        let eLow = Double(substr(45, 55)) ?? 0
        let n    = Double(substr(55, 59)) ?? 0.75
        let d    = Double(substr(59, 67)) ?? 0
        return Line(moleculeID: mol, isotopeID: iso, wavenumber: nu,
                    intensity: s, einsteinA: a, airHalfWidth: gAir,
                    selfHalfWidth: gSelf, lowerEnergy: eLow,
                    tempExponent: n, airPressureShift: d)
    }
}
```

---

## Build Checklist — Part 1 (Phases 0–11)

Verify each item compiles and passes a unit assertion before moving to CLAUDE2.md:

- [ ] `SpectralModality` — all 25 cases compile, `featureCount` non-zero for each
- [ ] `ModalityAxisSpec.make(for:)` — correct axis length for every case
- [ ] `TrainingRecord.featureDictionary()` — column count equals modality.featureCount
- [ ] `StoredTrainingRecord` and `StoredReferenceSpectrum` have `modality: String` field
- [ ] `JCAMPDXParser.detectModality(from:)` — non-nil for UV/IR/Raman/NMR/MS headers
- [ ] `FTIRSynthesizer.synthesize(count:)` — `spectralValues.count == 360`
- [ ] `RamanSynthesizer` — Bose-Einstein correction applied, no negative values
- [ ] `NMRProtonSynthesizer.addPeak` — Lorentzian peaks placed on 240-bin grid
- [ ] `XRDSynthesizer.synthesizePattern` — pseudo-Voigt peaks at correct Bragg 2θ
- [ ] `XPSSynthesizer.synthesizeSurface` — Gaussian peaks at correct core-level BEs
- [ ] `HITRANParser.parse(data:)` — first-line molecule ID parsed correctly
- [ ] ModelContainer schema — both new @Model types registered
- [ ] Project builds without errors or warnings (`⌘B`)

---

**→ Continue with CLAUDE2.md for Phases 12–24**
