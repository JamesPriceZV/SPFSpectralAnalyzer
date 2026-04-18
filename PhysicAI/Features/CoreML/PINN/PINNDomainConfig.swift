import Foundation

// MARK: - PINN Domain Identification

/// Spectral instrument domains supported by PINN-CoreML models.
/// Each domain maps to one or more SPC experiment type codes and has
/// domain-specific physics constraints embedded in the training loss function.
enum PINNDomain: String, CaseIterable, Identifiable, Codable, Sendable {
    case uvVis           = "UV-Vis"
    case ftir            = "FTIR"
    case raman           = "Raman"
    case massSpec        = "Mass Spec"
    case nmr             = "NMR"
    case fluorescence    = "Fluorescence"
    case xrd             = "XRD"
    case chromatography  = "Chromatography"
    case nir             = "NIR"
    case atomicEmission  = "Atomic Emission"
    case xps             = "XPS"
    case libs            = "LIBS"
    case hitran          = "HITRAN"
    case atmosphericUVVis = "Atmospheric UV/Vis"
    case usgsReflectance = "USGS Reflectance"
    case opticalConstants = "Optical Constants"
    case eels            = "EELS"
    case saxs            = "SAXS"
    case circularDichroism = "Circular Dichroism"
    case microwaveRotational = "Microwave/Rotational"
    case thermogravimetric = "TGA"
    case terahertz       = "THz"

    var id: String { rawValue }

    var displayName: String { rawValue }

    /// Canonical model filename base (e.g. "PINN_UVVis"), matching each domain model's `modelName`.
    /// Strips all non-alphanumeric characters from `rawValue`.
    var modelBaseName: String {
        "PINN_\(rawValue.filter { $0.isLetter || $0.isNumber })"
    }

    /// Filename-safe name for training scripts (e.g. "train_pinn_uv-vis.py").
    /// Lowercased with spaces and slashes replaced by underscores.
    var scriptBaseName: String {
        rawValue.lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    var iconName: String {
        switch self {
        case .uvVis:          return "sun.max.fill"
        case .ftir:           return "waveform"
        case .raman:          return "wave.3.left"
        case .massSpec:       return "atom"
        case .nmr:            return "gyroscope"
        case .fluorescence:   return "sparkle"
        case .xrd:            return "diamond.fill"
        case .chromatography: return "chart.xyaxis.line"
        case .nir:            return "waveform.path"
        case .atomicEmission: return "bolt.fill"
        case .xps:                 return "rays"
        case .libs:                return "bolt.horizontal.fill"
        case .hitran:              return "wind"
        case .atmosphericUVVis:    return "cloud.sun.fill"
        case .usgsReflectance:     return "mountain.2.fill"
        case .opticalConstants:    return "eyeglasses"
        case .eels:                return "circle.dotted"
        case .saxs:                return "circle.hexagongrid"
        case .circularDichroism:   return "arrow.trianglehead.2.clockwise.rotate.90"
        case .microwaveRotational: return "antenna.radiowaves.left.and.right"
        case .thermogravimetric:   return "flame.fill"
        case .terahertz:           return "wave.3.right"
        }
    }

    /// Human-readable description of the physics constraints this PINN embeds.
    var physicsDescription: String {
        switch self {
        case .uvVis:
            return "Beer-Lambert law (A=εcl), SPF Diffey integral, spectral smoothness, concentration non-negativity"
        case .ftir:
            return "Beer-Lambert (wavenumber domain), functional group frequency constraints, mass conservation"
        case .raman:
            return "Multi-agent spectral decomposition, background smoothness, Raman shift selection rules"
        case .massSpec:
            return "Isotope distribution (natural abundance), mass conservation, fragmentation rules"
        case .nmr:
            return "Bloch equation residuals, J-coupling patterns, Kramers-Kronig relation"
        case .fluorescence:
            return "Stokes shift constraint, mirror-image rule, Kasha's rule, quantum yield consistency"
        case .xrd:
            return "Bragg's law (nλ=2d sinθ), systematic absences, structure factor, Debye-Waller"
        case .chromatography:
            return "ED/LKM transport PDE (∂c/∂t + u·∂c/∂z + F·∂q/∂t = D·∂²c/∂z²), Langmuir isotherm"
        case .nir:
            return "Modified Beer-Lambert for diffuse reflectance, Kubelka-Munk corrections, overtone relationships"
        case .atomicEmission:
            return "Boltzmann distribution for excited states, transition selection rules"
        case .xps:
            return "Photoelectric BE=hv-KE-phi, Koopmans' theorem, Scofield cross-sections"
        case .libs:
            return "Saha-Boltzmann plasma diagnostics, Stark broadening for electron density"
        case .hitran:
            return "Voigt line profile S(T)*f(v-v0,gamma_D,gamma_L), HITRAN line parameters"
        case .atmosphericUVVis:
            return "Beer-Lambert with temperature-dependent cross-sections, photolysis J-values"
        case .usgsReflectance:
            return "Kubelka-Munk F(R)=(1-R)^2/2R, continuum removal for mineral identification"
        case .opticalConstants:
            return "Sellmeier n^2=1+Sum(Bi*lambda^2/(lambda^2-Ci)), Kramers-Kronig relations"
        case .eels:
            return "Core-loss ELNES onset=E_edge, Kramers-Kronig transform for dielectric function"
        case .saxs:
            return "Guinier I(q)=I0*exp(-q^2*Rg^2/3), Porod law I~q^-4 for surface scattering"
        case .circularDichroism:
            return "Cotton effect delta-epsilon, basis-spectrum decomposition for secondary structure"
        case .microwaveRotational:
            return "Rigid rotor E_J=hBJ(J+1), centrifugal distortion for molecular geometry"
        case .thermogravimetric:
            return "Arrhenius kinetics, Coats-Redfern: ln(-d_alpha/dT)=ln(A/beta)-Ea/RT"
        case .terahertz:
            return "Drude sigma1(w)=sigma0/(1+w^2*tau^2), Lorentz oscillator model"
        }
    }

    /// Key peer-reviewed references for this domain's PINN architecture.
    var references: [PINNReference] {
        switch self {
        case .uvVis:
            return [
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks: A deep learning framework for solving forward and inverse problems involving nonlinear partial differential equations. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                ),
                PINNReference(
                    "Karniadakis et al. (2021). Physics-informed machine learning. Nature Reviews Physics, 3(6), 422–440.",
                    url: "https://doi.org/10.1038/s42254-021-00314-5"
                ),
                PINNReference(
                    "Diffey & Robson (1989). A new substrate to measure sunscreen protection factors throughout the ultraviolet spectrum. J. Society of Cosmetic Chemists, 40, 127–133.",
                    url: "https://pubmed.ncbi.nlm.nih.gov/11537882/"
                ),
                PINNReference(
                    "COLIPA (2011). In vitro method for the determination of the UVA protection factor and critical wavelength values of sunscreen products. European Cosmetic Association.",
                    url: "https://www.cosmeticseurope.eu/files/4214/6407/8024/2011_-_In_vitro_UV_Protection_Method.pdf"
                ),
                PINNReference(
                    "ISO 24443:2021. Determination of sunscreen UVA photoprotection in vitro. International Organization for Standardization.",
                    url: "https://www.iso.org/standard/76990.html"
                ),
                PINNReference(
                    "Perkampus (1992). UV-VIS Spectroscopy and Its Applications. Springer-Verlag.",
                    url: "https://doi.org/10.1007/978-3-642-77477-5"
                )
            ]
        case .ftir:
            return [
                PINNReference(
                    "Griffiths & de Haseth (2007). Fourier Transform Infrared Spectrometry, 2nd ed. Wiley-Interscience.",
                    url: "https://doi.org/10.1002/047010631X"
                ),
                PINNReference(
                    "Stuart (2004). Infrared Spectroscopy: Fundamentals and Applications. Wiley.",
                    url: "https://doi.org/10.1002/0470011149"
                ),
                PINNReference(
                    "Smith (2011). Fundamentals of Fourier Transform Infrared Spectroscopy, 2nd ed. CRC Press.",
                    url: "https://doi.org/10.1201/b10777"
                ),
                PINNReference(
                    "Larkin (2011). Infrared and Raman Spectroscopy: Principles and Spectral Interpretation. Elsevier.",
                    url: "https://doi.org/10.1016/C2010-0-68479-3"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .raman:
            return [
                PINNReference(
                    "Long (2002). The Raman Effect: A Unified Treatment of the Theory of Raman Scattering by Molecules. Wiley.",
                    url: "https://doi.org/10.1002/0470845767"
                ),
                PINNReference(
                    "McCreery (2000). Raman Spectroscopy for Chemical Analysis. Wiley-Interscience.",
                    url: "https://doi.org/10.1002/0471721646"
                ),
                PINNReference(
                    "Ferraro, Nakamoto & Brown (2003). Introductory Raman Spectroscopy, 2nd ed. Academic Press.",
                    url: "https://doi.org/10.1016/B978-012254105-6/50004-4"
                ),
                PINNReference(
                    "Zhang et al. (2019). Deep learning for Raman spectroscopy: A review. Analytica Chimica Acta, 1058, 48–57.",
                    url: "https://doi.org/10.1016/j.aca.2019.01.002"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .massSpec:
            return [
                PINNReference(
                    "McLafferty & Turecek (1993). Interpretation of Mass Spectra, 4th ed. University Science Books.",
                    url: "https://www.worldcat.org/title/27897482"
                ),
                PINNReference(
                    "Gross (2017). Mass Spectrometry: A Textbook, 3rd ed. Springer International.",
                    url: "https://doi.org/10.1007/978-3-319-54398-7"
                ),
                PINNReference(
                    "Kind & Fiehn (2007). Seven Golden Rules for heuristic filtering of molecular formulas. BMC Bioinformatics, 8, 105.",
                    url: "https://doi.org/10.1186/1471-2105-8-105"
                ),
                PINNReference(
                    "de Hoffmann & Stroobant (2007). Mass Spectrometry: Principles and Applications, 3rd ed. Wiley.",
                    url: "https://doi.org/10.1002/mas.20247"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .nmr:
            return [
                PINNReference(
                    "Claridge (2016). High-Resolution NMR Techniques in Organic Chemistry, 3rd ed. Elsevier.",
                    url: "https://doi.org/10.1016/C2013-0-19117-9"
                ),
                PINNReference(
                    "Keeler (2010). Understanding NMR Spectroscopy, 2nd ed. Wiley.",
                    url: "https://www.wiley.com/en-us/Understanding+NMR+Spectroscopy%2C+2nd+Edition-p-9780470746080"
                ),
                PINNReference(
                    "Levitt (2008). Spin Dynamics: Basics of Nuclear Magnetic Resonance, 2nd ed. Wiley.",
                    url: "https://www.wiley.com/en-us/Spin+Dynamics%3A+Basics+of+Nuclear+Magnetic+Resonance%2C+2nd+Edition-p-9780470511176"
                ),
                PINNReference(
                    "Qu et al. (2020). Accelerated NMR spectroscopy with deep learning. Angewandte Chemie Int. Ed., 59(26), 10297–10300.",
                    url: "https://doi.org/10.1002/anie.201908162"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .fluorescence:
            return [
                PINNReference(
                    "Lakowicz (2006). Principles of Fluorescence Spectroscopy, 3rd ed. Springer.",
                    url: "https://doi.org/10.1007/978-0-387-46312-4"
                ),
                PINNReference(
                    "Valeur & Berberan-Santos (2012). Molecular Fluorescence: Principles and Applications, 2nd ed. Wiley-VCH.",
                    url: "https://doi.org/10.1002/9783527650002"
                ),
                PINNReference(
                    "Murphy et al. (2013). Fluorescence spectroscopy and multi-way techniques: PARAFAC. Analytical Methods, 5, 6557–6566.",
                    url: "https://doi.org/10.1039/C3AY41160E"
                ),
                PINNReference(
                    "Stedmon & Bro (2008). Characterizing dissolved organic matter fluorescence with parallel factor analysis. Limnology and Oceanography: Methods, 6, 572–579.",
                    url: "https://doi.org/10.4319/lom.2008.6.572"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .xrd:
            return [
                PINNReference(
                    "Rietveld (1969). A profile refinement method for nuclear and magnetic structures. J. Applied Crystallography, 2, 65–71.",
                    url: "https://doi.org/10.1107/S0021889869006558"
                ),
                PINNReference(
                    "Le Bail, Duroy & Fourquet (1988). Ab-initio structure determination of LiSbWO6 by X-ray powder diffraction. Materials Research Bulletin, 23(3), 447–452.",
                    url: "https://doi.org/10.1016/0025-5408(88)90019-0"
                ),
                PINNReference(
                    "Cullity & Stock (2001). Elements of X-Ray Diffraction, 3rd ed. Prentice Hall.",
                    url: "https://www.worldcat.org/title/44684891"
                ),
                PINNReference(
                    "Pecharsky & Zavalij (2009). Fundamentals of Powder Diffraction and Structural Characterization of Materials, 2nd ed. Springer.",
                    url: "https://doi.org/10.1007/978-0-387-09579-0"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .chromatography:
            return [
                PINNReference(
                    "van Deemter, Zuiderweg & Klinkenberg (1956). Longitudinal diffusion and resistance to mass transfer as causes of nonideality in chromatography. Chemical Engineering Science, 5(6), 271–289.",
                    url: "https://doi.org/10.1016/0009-2509(56)80003-1"
                ),
                PINNReference(
                    "Guiochon, Felinger, Shirazi & Katti (2006). Fundamentals of Preparative and Nonlinear Chromatography, 2nd ed. Academic Press.",
                    url: "https://doi.org/10.1016/B978-012370537-2/50030-8"
                ),
                PINNReference(
                    "Snyder, Kirkland & Dolan (2010). Introduction to Modern Liquid Chromatography, 3rd ed. Wiley.",
                    url: "https://doi.org/10.1002/9780470508183"
                ),
                PINNReference(
                    "Zou et al. (2024). Physics-informed neural networks for chromatographic process modeling. J. Chromatography A, 1719, 464737.",
                    url: "https://doi.org/10.1016/j.chroma.2024.464737"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .nir:
            return [
                PINNReference(
                    "Burns & Ciurczak (2007). Handbook of Near-Infrared Analysis, 3rd ed. CRC Press.",
                    url: "https://doi.org/10.1201/9781420007374"
                ),
                PINNReference(
                    "Rinnan, van den Berg & Engelsen (2009). Review of the most common pre-processing techniques for near-infrared spectra. TrAC Trends in Analytical Chemistry, 28(10), 1201–1222.",
                    url: "https://doi.org/10.1016/j.trac.2009.07.007"
                ),
                PINNReference(
                    "Siesler, Ozaki, Kawata & Heise (2002). Near-Infrared Spectroscopy: Principles, Instruments, Applications. Wiley-VCH.",
                    url: "https://doi.org/10.1002/9783527612666"
                ),
                PINNReference(
                    "Pasquini (2003). Near infrared spectroscopy: fundamentals, practical aspects and analytical applications. J. Brazilian Chemical Society, 14(2), 198–219.",
                    url: "https://doi.org/10.1590/S0103-50532003000200006"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .atomicEmission:
            return [
                PINNReference(
                    "NIST Atomic Spectra Database (ver. 5.11). National Institute of Standards and Technology.",
                    url: "https://www.nist.gov/pml/atomic-spectra-database"
                ),
                PINNReference(
                    "Cremers & Radziemski (2013). Handbook of Laser-Induced Breakdown Spectroscopy, 2nd ed. Wiley.",
                    url: "https://doi.org/10.1002/9781118567371"
                ),
                PINNReference(
                    "Ingle & Crouch (1988). Spectrochemical Analysis. Prentice Hall.",
                    url: "https://www.worldcat.org/title/16714196"
                ),
                PINNReference(
                    "Noll (2012). Laser-Induced Breakdown Spectroscopy: Fundamentals and Applications. Springer.",
                    url: "https://doi.org/10.1007/978-3-642-20668-9"
                ),
                PINNReference(
                    "Raissi, Perdikaris & Karniadakis (2019). Physics-informed neural networks. J. Computational Physics, 378, 686–707.",
                    url: "https://doi.org/10.1016/j.jcp.2018.10.045"
                )
            ]
        case .xps:
            return [
                PINNReference(
                    "Moulder et al. (1992). Handbook of X-ray Photoelectron Spectroscopy. Perkin-Elmer.",
                    url: "https://www.worldcat.org/title/28388301"
                ),
                PINNReference(
                    "NIST X-ray Photoelectron Spectroscopy Database SRD 20.",
                    url: "https://srdata.nist.gov/xps/"
                )
            ]
        case .libs:
            return [
                PINNReference(
                    "Cremers & Radziemski (2013). Handbook of Laser-Induced Breakdown Spectroscopy, 2nd ed. Wiley.",
                    url: "https://doi.org/10.1002/9781118567371"
                ),
                PINNReference(
                    "Noll (2012). Laser-Induced Breakdown Spectroscopy: Fundamentals and Applications. Springer.",
                    url: "https://doi.org/10.1007/978-3-642-20668-9"
                )
            ]
        case .hitran:
            return [
                PINNReference(
                    "Gordon et al. (2022). The HITRAN2020 molecular spectroscopic database. JQSRT, 277, 107949.",
                    url: "https://doi.org/10.1016/j.jqsrt.2021.107949"
                ),
                PINNReference(
                    "Rothman et al. (2013). The HITRAN2012 molecular spectroscopic database. JQSRT, 130, 4–50.",
                    url: "https://doi.org/10.1016/j.jqsrt.2013.07.002"
                )
            ]
        case .atmosphericUVVis:
            return [
                PINNReference(
                    "Keller-Rudek et al. (2013). The MPI-Mainz UV/VIS Spectral Atlas. Earth System Science Data, 5(2), 365–373.",
                    url: "https://doi.org/10.5194/essd-5-365-2013"
                )
            ]
        case .usgsReflectance:
            return [
                PINNReference(
                    "Kokaly et al. (2017). USGS Spectral Library Version 7. USGS Data Series 1035.",
                    url: "https://doi.org/10.3133/ds1035"
                ),
                PINNReference(
                    "Clark et al. (2007). USGS Digital Spectral Library splib06a. USGS Digital Data Series 231.",
                    url: "https://doi.org/10.3133/ds231"
                )
            ]
        case .opticalConstants:
            return [
                PINNReference(
                    "Polyanskiy (2024). Refractive index database. refractiveindex.info.",
                    url: "https://refractiveindex.info"
                )
            ]
        case .eels:
            return [
                PINNReference(
                    "Egerton (2011). Electron Energy-Loss Spectroscopy in the Electron Microscope, 3rd ed. Springer.",
                    url: "https://doi.org/10.1007/978-1-4419-9583-4"
                ),
                PINNReference(
                    "Verbeeck & Van Aert (2004). Model based quantification of EELS spectra. Ultramicroscopy, 101, 207–224.",
                    url: "https://doi.org/10.1016/j.ultramic.2004.06.004"
                )
            ]
        case .saxs:
            return [
                PINNReference(
                    "Guinier & Fournet (1955). Small-Angle Scattering of X-Rays. Wiley.",
                    url: "https://www.worldcat.org/title/1322975"
                ),
                PINNReference(
                    "Kikhney et al. (2020). SASBDB: Towards an automatically curated SAS data repository. Protein Science, 29, 66–75.",
                    url: "https://doi.org/10.1002/pro.3731"
                )
            ]
        case .circularDichroism:
            return [
                PINNReference(
                    "Greenfield (2006). Using circular dichroism spectra to estimate protein secondary structure. Nature Protocols, 1(6), 2876–2890.",
                    url: "https://doi.org/10.1038/nprot.2006.202"
                ),
                PINNReference(
                    "Whitmore & Wallace (2008). Protein secondary structure analyses from circular dichroism spectroscopy. Biopolymers, 89(5), 392–400.",
                    url: "https://doi.org/10.1002/bip.20853"
                )
            ]
        case .microwaveRotational:
            return [
                PINNReference(
                    "Gordy & Cook (1984). Microwave Molecular Spectra. Wiley-Interscience.",
                    url: "https://doi.org/10.1002/9780470142813"
                ),
                PINNReference(
                    "Muller et al. (2005). The Cologne Database for Molecular Spectroscopy (CDMS). J. Molecular Structure, 742, 215–227.",
                    url: "https://doi.org/10.1016/j.molstruc.2005.01.027"
                )
            ]
        case .thermogravimetric:
            return [
                PINNReference(
                    "Coats & Redfern (1964). Kinetic parameters from thermogravimetric data. Nature, 201, 68–69.",
                    url: "https://doi.org/10.1038/201068a0"
                ),
                PINNReference(
                    "Vyazovkin et al. (2011). ICTAC Kinetics Committee recommendations. Thermochimica Acta, 520, 1–19.",
                    url: "https://doi.org/10.1016/j.tca.2011.03.034"
                )
            ]
        case .terahertz:
            return [
                PINNReference(
                    "Jepsen et al. (2011). Terahertz spectroscopy and imaging – Modern techniques and applications. Laser & Photonics Reviews, 5(1), 124–166.",
                    url: "https://doi.org/10.1002/lpor.201000011"
                ),
                PINNReference(
                    "Naftaly et al. (2007). Terahertz time-domain spectroscopy for material characterization. Proceedings of the IEEE, 95(8), 1658–1665.",
                    url: "https://doi.org/10.1109/JPROC.2007.898835"
                )
            ]
        }
    }

    /// The SPC experiment type codes that map to this domain.
    var spcExperimentTypeCodes: [UInt8] {
        switch self {
        case .uvVis:          return [6]        // UV-VIS Spectrum
        case .ftir:           return [4]        // FT-IR/FT-NIR/FT-Raman Spectrum or Igram
        case .raman:          return [10]       // Raman Spectrum
        case .massSpec:       return [8]        // Mass Spectrum
        case .nmr:            return [9]        // NMR Spectrum or FID
        case .fluorescence:   return [11]       // Fluorescence Spectrum
        case .xrd:            return [7]        // X-ray Diffraction Spectrum
        case .chromatography: return [1, 2, 3, 13] // GC, General, HPLC, Diode Array
        case .nir:            return [5]        // NIR Spectrum
        case .atomicEmission: return [12]       // Atomic Spectrum
        case .xps:                 return [14]  // X-ray Photoelectron Spectrum
        case .libs:                return [15]  // LIBS Spectrum
        case .hitran:              return [16]  // HITRAN Molecular Lines
        case .atmosphericUVVis:    return [17]  // Atmospheric UV/Vis Cross-Section
        case .usgsReflectance:     return [18]  // USGS Reflectance
        case .opticalConstants:    return [19]  // Optical Constants (n,k)
        case .eels:                return [20]  // Electron Energy Loss Spectrum
        case .saxs:                return [21]  // Small-Angle Scattering
        case .circularDichroism:   return [22]  // Circular Dichroism
        case .microwaveRotational: return [23]  // Microwave Rotational
        case .thermogravimetric:   return [24]  // Thermogravimetric Analysis
        case .terahertz:           return [25]  // Terahertz Spectrum
        }
    }

    /// Human-readable SPC experiment type code descriptions for this domain.
    var spcExperimentTypeDescriptions: [(code: UInt8, name: String)] {
        spcExperimentTypeCodes.map { code in
            let name: String
            switch code {
            case 0:  name = "General SPC"
            case 1:  name = "Gas Chromatogram"
            case 2:  name = "General Chromatogram"
            case 3:  name = "HPLC Chromatogram"
            case 4:  name = "FT-IR/FT-NIR/FT-Raman Spectrum or Igram"
            case 5:  name = "NIR Spectrum"
            case 6:  name = "UV-VIS Spectrum"
            case 7:  name = "X-ray Diffraction Spectrum"
            case 8:  name = "Mass Spectrum"
            case 9:  name = "NMR Spectrum or FID"
            case 10: name = "Raman Spectrum"
            case 11: name = "Fluorescence Spectrum"
            case 12: name = "Atomic Spectrum"
            case 13: name = "Diode Array Chromatogram"
            case 14: name = "X-ray Photoelectron Spectrum"
            case 15: name = "LIBS Spectrum"
            case 16: name = "HITRAN Molecular Lines"
            case 17: name = "Atmospheric UV/Vis Cross-Section"
            case 18: name = "USGS Reflectance Spectrum"
            case 19: name = "Optical Constants (n, k)"
            case 20: name = "Electron Energy Loss Spectrum"
            case 21: name = "Small-Angle Scattering"
            case 22: name = "Circular Dichroism Spectrum"
            case 23: name = "Microwave Rotational Spectrum"
            case 24: name = "Thermogravimetric Analysis"
            case 25: name = "Terahertz Spectrum"
            default: name = "Unknown (code \(code))"
            }
            return (code, name)
        }
    }

    /// A training data source with name, description, and optional URL.
    struct TrainingDataSource: Sendable {
        let name: String
        let description: String
        let url: URL?
        let isLicensed: Bool

        /// Display label combining name and description.
        var displayLabel: String {
            "\(name) (\(description))"
        }
    }

    /// Legacy plain-text data sources (backward compatibility).
    var trainingDataSources: [String] {
        trainingDataSourcesWithURLs.map(\.displayLabel)
    }

    /// Training data sources with verified, downloadable URLs for each domain.
    /// URLs point to direct data file downloads where available (not landing pages).
    /// Format note: Figshare uses /ndownloader/articles/ for ZIP bundles;
    ///              Zenodo uses /records/{id}/files/{name}?download=1 for direct files.
    var trainingDataSourcesWithURLs: [TrainingDataSource] {
        switch self {
        case .uvVis:
            return [
                TrainingDataSource(
                    name: "UV/Vis Absorption Spectra Dataset",
                    description: "18,309 spectra, 8,488 compounds, ZIP bundle (Figshare)",
                    url: URL(string: "https://figshare.com/ndownloader/articles/7619672/versions/2"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "DB for Chromophore",
                    description: "20,236 data points, 7,016 chromophores, ZIP bundle (Figshare)",
                    url: URL(string: "https://figshare.com/ndownloader/articles/12045567/versions/3"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Benzene UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C71432&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Naphthalene UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C91203&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Toluene UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C108883&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Acetone UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67641&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Phenol UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C108952&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Styrene UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C100425&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Aniline UV",
                    description: "JCAMP-DX UV absorption spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C62533&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "User Reference Datasets",
                    description: "your imported SPC files with knownInVivoSPF values",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .ftir:
            return [
                TrainingDataSource(
                    name: "NIST WebBook — Ethanol IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C64175&Index=1&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Acetone IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67641&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Methanol IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67561&Index=1&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Benzene IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C71432&Index=1&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Toluene IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C108883&Index=1&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Water IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C7732185&Index=1&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Chloroform IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67663&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Acetic Acid IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C64197&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Isopropanol IR",
                    description: "JCAMP-DX spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67630&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF — Mineral Infrared ZIP",
                    description: "937 mineral infrared spectra, bulk TXT download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/infrared/RAW.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST/EPA Gas-Phase IR (SRD 35)",
                    description: "5,228 IR spectra — requires manual download from NIST",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .raman:
            return [
                TrainingDataSource(
                    name: "RRUFF Raman — LR (All) ZIP",
                    description: "7,764+ low-resolution mineral Raman spectra, bulk TXT download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/raman/LR-Raman.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF Raman — Excellent Unoriented ZIP",
                    description: "highest quality unoriented Raman spectra, bulk TXT download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/raman/excellent_unoriented.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF Raman — Excellent Oriented ZIP",
                    description: "highest quality oriented single-crystal Raman spectra",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/raman/excellent_oriented.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF Raman — Fair Unoriented ZIP",
                    description: "fair quality unoriented Raman spectra",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/raman/fair_unoriented.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "KnowItAll Raman Library",
                    description: "Bio-Rad/Wiley, 25,000+ spectra",
                    url: URL(string: "https://sciencesolutions.wiley.com/knowitall-spectroscopy-software/"),
                    isLicensed: true
                )
            ]
        case .massSpec:
            return [
                TrainingDataSource(
                    name: "MoNA — LC-MS/MS Spectra (SDF)",
                    description: "1.2M+ LC-MS spectra, direct SDF download",
                    url: URL(string: "https://mona.fiehnlab.ucdavis.edu/rest/downloads/retrieve/03d5a22c-c1e1-4101-ac70-9a4eae437ef5"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "MoNA — GC-MS Spectra",
                    description: "GC-MS spectra — visit mona.fiehnlab.ucdavis.edu/downloads",
                    url: nil,
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "GNPS2 Reference Libraries (JSON)",
                    description: "2.9M MS/MS spectra — browse gnps2.org to select libraries",
                    url: nil,
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Ethanol MS",
                    description: "JCAMP-DX mass spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C64175&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Acetone MS",
                    description: "JCAMP-DX mass spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67641&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Benzene MS",
                    description: "JCAMP-DX mass spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C71432&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Caffeine MS",
                    description: "JCAMP-DX mass spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C58082&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Aspirin MS",
                    description: "JCAMP-DX mass spectrum, direct download",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C50782&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST Mass Spectral Library",
                    description: "350,000+ spectra (commercial)",
                    url: URL(string: "https://www.nist.gov/srd/nist-standard-reference-database-1a"),
                    isLicensed: true
                )
            ]
        case .nmr:
            return [
                TrainingDataSource(
                    name: "nmrshiftdb2 — Full SD with Signals",
                    description: "53,954 measured spectra, direct SD file download",
                    url: URL(string: "https://sourceforge.net/projects/nmrshiftdb2/files/data/nmrshiftdb2withsignals.sd/download"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "nmrshiftdb2 — NMReData",
                    description: "NMReData format with full spectral assignments",
                    url: URL(string: "https://sourceforge.net/projects/nmrshiftdb2/files/data/nmrshiftdb2.nmredata.sd/download"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "BMRB — Amino Acid Shifts (TXT)",
                    description: "protein chemical shift statistics, full dataset",
                    url: URL(string: "https://bmrb.io/ftp/pub/bmrb/statistics/chem_shifts/full/statful_prot.txt"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "BMRB — Nucleotide Shifts (TXT)",
                    description: "nucleic acid chemical shift statistics",
                    url: URL(string: "https://bmrb.io/ftp/pub/bmrb/statistics/chem_shifts/full/statful_dna.txt"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "BMRB — Filtered Amino Acid Shifts",
                    description: "curated protein shifts — visit bmrb.io/ref_info/stats.php",
                    url: nil,
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "nmrshiftdb2 — SD File (no signals)",
                    description: "structure data with chemical shifts, SD format",
                    url: URL(string: "https://sourceforge.net/projects/nmrshiftdb2/files/data/nmrshiftdb2.sd/download"),
                    isLicensed: false
                )
            ]
        case .fluorescence:
            return [
                TrainingDataSource(
                    name: "FPbase — Fluorescent Proteins (CSV)",
                    description: "1,000+ fluorescent protein spectra, direct CSV download",
                    url: URL(string: "https://www.fpbase.org/api/proteins/?format=csv"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "DB for Chromophore — Fluorescence",
                    description: "20,236 emission/PLQY/lifetime data points, ZIP bundle",
                    url: URL(string: "https://figshare.com/ndownloader/articles/12045567/versions/3"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "FPbase — Fluorescent Protein Spectra (CSV)",
                    description: "1,000+ excitation/emission spectra, direct CSV download",
                    url: URL(string: "https://www.fpbase.org/api/spectra/?format=csv"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Anthracene UV/Fluorescence",
                    description: "JCAMP-DX UV spectrum for fluorescent reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C120127&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Pyrene UV/Fluorescence",
                    description: "JCAMP-DX UV spectrum for fluorescent reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C129000&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Fluorescein UV",
                    description: "JCAMP-DX UV spectrum for common fluorescent dye",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C2321073&Index=0&Type=UVVis"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "PhotochemCAD Spectra",
                    description: "552 absorption + fluorescence spectra — manual download",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .xrd:
            return [
                TrainingDataSource(
                    name: "RRUFF — Powder XRD Raw ZIP",
                    description: "powder diffraction patterns (XY raw), bulk TXT download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/powder/XY_RAW.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF — Powder XRD Processed ZIP",
                    description: "processed powder diffraction patterns, bulk TXT download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/powder/XY_Processed.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF — DIF Powder XRD ZIP",
                    description: "DIF format powder diffraction data, bulk download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/powder/DIF.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RRUFF — Refinement Data ZIP",
                    description: "refinement data for crystal structures, bulk download",
                    url: URL(string: "https://www.rruff.net/zipped_data_files/powder/Refinement_Data.zip"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "COD — Bulk MySQL Archive",
                    description: "450,000+ crystal structures — multi-GB SQL dump, manual download",
                    url: nil,
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "COD — CIF Tarball (Inorganic)",
                    description: "inorganic crystal structures — multi-GB tar.gz, manual download",
                    url: nil,
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "ICDD PDF-4+",
                    description: "450,000+ entries (commercial)",
                    url: URL(string: "https://www.icdd.com/pdf-4/"),
                    isLicensed: true
                )
            ]
        case .chromatography:
            return [
                TrainingDataSource(
                    name: "METLIN SMRT Dataset",
                    description: "80,038 HPLC retention times, ZIP bundle (Figshare)",
                    url: URL(string: "https://figshare.com/ndownloader/articles/8038913/versions/6"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "RepoRT — Retention Time Dataset (Figshare)",
                    description: "85,000+ retention times, 56 systems, CSV",
                    url: URL(string: "https://figshare.com/ndownloader/articles/20399695/versions/2"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Ethanol GC-MS",
                    description: "JCAMP-DX mass spectrum for GC reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C64175&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Hexane GC-MS",
                    description: "JCAMP-DX mass spectrum for GC reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C110543&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Methanol GC-MS",
                    description: "JCAMP-DX mass spectrum for GC reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67561&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Dichloromethane GC-MS",
                    description: "JCAMP-DX mass spectrum for GC reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C75092&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Chloroform GC-MS",
                    description: "JCAMP-DX mass spectrum for GC reference compound",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C67663&Index=0&Type=Mass"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "User SPC Chromatogram Imports",
                    description: "your imported SPC files",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .nir:
            return [
                TrainingDataSource(
                    name: "OSSL NeoSpectra NIR CSV (Google Cloud)",
                    description: "direct gzipped CSV, no auth needed",
                    url: URL(string: "https://storage.googleapis.com/soilspec4gg-public/neospectra_nir_v1.2.csv.gz"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "OSSL VisNIR CSV (Google Cloud)",
                    description: "65,000+ VisNIR scans, direct gzipped CSV",
                    url: URL(string: "https://storage.googleapis.com/soilspec4gg-public/ossl_visnir_v1.2.csv.gz"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "OSSL MIR CSV (Google Cloud)",
                    description: "mid-infrared soil spectra, direct gzipped CSV",
                    url: URL(string: "https://storage.googleapis.com/soilspec4gg-public/ossl_mir_v1.2.csv.gz"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "Kaolinite NIR (NIST WebBook JCAMP-DX)",
                    description: "sample NIR spectrum for validation",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C1318742&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Polyethylene IR/NIR",
                    description: "JCAMP-DX spectrum, polymer reference",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C9002884&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Polystyrene IR/NIR",
                    description: "JCAMP-DX spectrum, polymer reference",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C9003536&Index=0&Type=IR"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST WebBook — Glucose IR/NIR",
                    description: "JCAMP-DX spectrum, sugar reference for food NIR",
                    url: URL(string: "https://webbook.nist.gov/cgi/cbook.cgi?JCAMP=C50997&Index=0&Type=IR"),
                    isLicensed: false
                )
            ]
        case .atomicEmission:
            return [
                TrainingDataSource(
                    name: "NIST ASD — Fe I Lines (CSV)",
                    description: "Iron emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Fe+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — H I Lines (CSV)",
                    description: "Hydrogen emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=H+I&limits_type=0&low_w=100&upp_w=2000&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Na I Lines (CSV)",
                    description: "Sodium emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Na+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Ca I Lines (CSV)",
                    description: "Calcium emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Ca+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Cu I Lines (CSV)",
                    description: "Copper emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Cu+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Mg I Lines (CSV)",
                    description: "Magnesium emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Mg+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — O I Lines (CSV)",
                    description: "Oxygen emission lines, direct CSV from ASD API",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=O+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Ar I Lines (CSV)",
                    description: "Argon emission lines (calibration standard), direct CSV",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Ar+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                ),
                TrainingDataSource(
                    name: "NIST ASD — Hg I Lines (CSV)",
                    description: "Mercury emission lines (calibration standard), direct CSV",
                    url: URL(string: "https://physics.nist.gov/cgi-bin/ASD/lines1.pl?spectra=Hg+I&limits_type=0&low_w=200&upp_w=900&unit=1&de=0&format=3&line_out=0&remove_js=on&no_js=on&en_unit=0&output=0&bibrefs=1&show_obs_wl=1&show_calc_wl=1&unc_out=1&order_out=0&show_av=2&intens_out=on&allowed_out=1&forbid_out=1&conf_out=on&term_out=on&enrg_out=on&J_out=on&submit=Retrieve+Data"),
                    isLicensed: false
                )
            ]
        case .xps:
            return [
                TrainingDataSource(
                    name: "NIST XPS Database SRD 20",
                    description: "33,000+ XPS records — browse srdata.nist.gov/xps",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .libs:
            return [
                TrainingDataSource(
                    name: "NIST ASD — LIBS Elements",
                    description: "Uses same NIST ASD data as Atomic Emission with plasma parameters",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .hitran:
            return [
                TrainingDataSource(
                    name: "HITRAN2024 Line-by-Line",
                    description: "61 molecules, registration required — hitran.org",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .atmosphericUVVis:
            return [
                TrainingDataSource(
                    name: "MPI-Mainz UV/Vis Spectral Atlas",
                    description: "~800 atmospheric species, free JCAMP-DX",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .usgsReflectance:
            return [
                TrainingDataSource(
                    name: "USGS Spectral Library splib07",
                    description: "2,800+ spectra, free download",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .opticalConstants:
            return [
                TrainingDataSource(
                    name: "refractiveindex.info Database (GitHub ZIP)",
                    description: "1,000+ materials, CC0 YAML data, full repository archive",
                    url: URL(string: "https://github.com/polyanskiy/refractiveindex.info-database/archive/refs/heads/main.zip"),
                    isLicensed: false
                )
            ]
        case .eels:
            return [
                TrainingDataSource(
                    name: "EELS Database (eelsdb.eu)",
                    description: "290 spectra, ODbL license",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .saxs:
            return [
                TrainingDataSource(
                    name: "SASBDB (sasbdb.org)",
                    description: "5,000+ SAXS/SANS profiles, free",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .circularDichroism:
            return [
                TrainingDataSource(
                    name: "PCDDB (pcddb.cryst.bbk.ac.uk)",
                    description: "1,800+ CD spectra, free",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .microwaveRotational:
            return [
                TrainingDataSource(
                    name: "CDMS (cdms.astro.uni-koeln.de)",
                    description: "~750 species, free catalog",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .thermogravimetric:
            return [
                TrainingDataSource(
                    name: "NIST JANAF Thermochemical Tables",
                    description: "Thermodynamic data — manual download",
                    url: nil,
                    isLicensed: false
                )
            ]
        case .terahertz:
            return [
                TrainingDataSource(
                    name: "Zenodo THz Pharma Datasets",
                    description: "500+ THz spectra — search Zenodo",
                    url: nil,
                    isLicensed: false
                )
            ]
        }
    }

    /// Recommended PINN architecture for this domain.
    var architectureDescription: String {
        let fourier = fourierEncodingConfig
        let fourierSuffix = fourier.isEnabled
            ? ", Fourier features (\(fourier.numFrequencies) freq, σ=\(String(format: "%.1f", fourier.sigma)))"
            : ""
        let mlpType = useModifiedMLP ? "Modified MLP" : "MLP"
        let layerStr = hiddenLayers.map(String.init).joined(separator: "-")
        let ensemble = ensembleConfig
        let ensembleSuffix = ensemble.isEnabled ? ", \(ensemble.numHeads)-head ensemble" : ""
        let act = activation.displayName

        let physicsNote: String
        switch self {
        case .uvVis:          physicsNote = "ReLoBRaLo loss balancing"
        case .ftir:           physicsNote = "Beer-Lambert + peak position constraints"
        case .raman:          physicsNote = "background + concentration decomposition"
        case .massSpec:       physicsNote = "inverse PINN with trainable fragmentation"
        case .nmr:            physicsNote = "Bloch equation PDE residuals"
        case .fluorescence:   physicsNote = "emission + component concentration"
        case .xrd:            physicsNote = "Bragg's law + structure factor constraints"
        case .chromatography: physicsNote = "ED transport PDE + Langmuir isotherm"
        case .nir:            physicsNote = "modified Beer-Lambert + Kubelka-Munk"
        case .atomicEmission:      physicsNote = "Boltzmann distribution loss"
        case .xps:                 physicsNote = "photoelectric equation + Scofield cross-sections"
        case .libs:                physicsNote = "Saha-Boltzmann + Stark broadening"
        case .hitran:              physicsNote = "Voigt profile + temperature scaling"
        case .atmosphericUVVis:    physicsNote = "Beer-Lambert with sigma(lambda,T)"
        case .usgsReflectance:     physicsNote = "Kubelka-Munk + continuum removal"
        case .opticalConstants:    physicsNote = "Sellmeier + Kramers-Kronig"
        case .eels:                physicsNote = "core-loss onset + Kramers-Kronig"
        case .saxs:                physicsNote = "Guinier + Porod law"
        case .circularDichroism:   physicsNote = "Cotton effect + basis decomposition"
        case .microwaveRotational: physicsNote = "rigid rotor + centrifugal distortion"
        case .thermogravimetric:   physicsNote = "Arrhenius + Coats-Redfern"
        case .terahertz:           physicsNote = "Drude + Lorentz oscillator"
        }

        return "\(hiddenLayers.count)-layer \(mlpType) (\(layerStr)), \(act), \(physicsNote)\(fourierSuffix)\(ensembleSuffix)"
    }

    /// Optional physics constraints that users can toggle on/off for training.
    var availablePhysicsConstraints: [PhysicsConstraintOption] {
        switch self {
        case .uvVis:
            return [
                PhysicsConstraintOption(id: "beer_lambert", name: "Beer-Lambert Law", equation: "A(\u{03BB}) = \u{03B5}cl", description: "Absorbance is proportional to concentration and path length", isDefault: true),
                PhysicsConstraintOption(id: "spf_integral", name: "SPF Diffey Integral", equation: "SPF = \u{222B}E\u{00B7}S / \u{222B}E\u{00B7}S\u{00B7}10^(-A)", description: "SPF calculated from erythemal action spectrum weighted transmittance", isDefault: true),
                PhysicsConstraintOption(id: "non_negativity", name: "Non-negativity", equation: "A(\u{03BB}) \u{2265} 0", description: "Absorbance values must be non-negative", isDefault: true),
                PhysicsConstraintOption(id: "spectral_smoothness", name: "Spectral Smoothness", equation: "\u{2016}\u{2202}A/\u{2202}\u{03BB}\u{2016}\u{00B2} penalty", description: "Penalizes jagged or noisy spectral predictions", isDefault: true),
                PhysicsConstraintOption(id: "photostability_decay", name: "Photostability Decay", equation: "A(t) = A\u{2080}\u{00B7}exp(-kt)", description: "Optional time-dependent UV filter degradation modeling", isDefault: false)
            ]
        case .ftir:
            return [
                PhysicsConstraintOption(id: "beer_lambert", name: "Beer-Lambert Law", equation: "A(\u{03BD}) = \u{03B5}(\u{03BD})\u{00B7}c\u{00B7}l", description: "Absorbance proportional to concentration in wavenumber domain", isDefault: true),
                PhysicsConstraintOption(id: "spectral_decomposition", name: "Spectral Decomposition", equation: "I = \u{03A3} c\u{1D62}\u{00B7}S\u{1D62}", description: "Spectrum decomposes into pure component spectra", isDefault: true),
                PhysicsConstraintOption(id: "peak_position", name: "Peak Position Constraints", equation: "Functional group \u{03BD} ranges", description: "Enforce known functional group frequency ranges", isDefault: true),
                PhysicsConstraintOption(id: "mass_conservation", name: "Mass Conservation", equation: "\u{03A3}c\u{1D62} = const", description: "Total concentration remains constant during analysis", isDefault: false)
            ]
        case .raman:
            return [
                PhysicsConstraintOption(id: "spectral_reconstruction", name: "Spectral Reconstruction", equation: "I(\u{03BB}) = \u{03A3} c\u{2C7}\u{00B7}I\u{2080}\u{2C7}(\u{03BB}) + I\u{2095}(\u{03BB})", description: "Observed spectrum is sum of component spectra plus background", isDefault: true),
                PhysicsConstraintOption(id: "background_smoothness", name: "Background Smoothness", equation: "\u{2016}\u{2202}I\u{2095}/\u{2202}\u{03BB}\u{2016}\u{00B2} penalty", description: "Fluorescence background should be smooth", isDefault: true),
                PhysicsConstraintOption(id: "concentration_non_neg", name: "Concentration Non-negativity", equation: "c\u{2C7} \u{2265} 0", description: "Component concentrations must be non-negative", isDefault: true),
                PhysicsConstraintOption(id: "shift_selection_rules", name: "Raman Shift Selection Rules", equation: "\u{0394}\u{03BD} selection rules", description: "Enforce allowed Raman transition selection rules", isDefault: false)
            ]
        case .massSpec:
            return [
                PhysicsConstraintOption(id: "isotope_distribution", name: "Isotope Distribution", equation: "Natural abundance patterns", description: "Isotope patterns follow binomial/Poisson distribution", isDefault: true),
                PhysicsConstraintOption(id: "mass_conservation", name: "Mass Conservation", equation: "\u{03A3}m\u{1DA0}\u{1D63}\u{1D43}\u{1D4D} = m\u{209A}\u{2090}\u{1D63}\u{2091}\u{2099}\u{209C}", description: "Fragment masses sum to parent ion mass", isDefault: true),
                PhysicsConstraintOption(id: "fragmentation_rules", name: "Fragmentation Rules", equation: "Bond dissociation energies", description: "Fragmentation follows known chemical bond dissociation patterns", isDefault: true),
                PhysicsConstraintOption(id: "charge_conservation", name: "Charge Conservation", equation: "\u{03A3}z = const", description: "Total charge is conserved during fragmentation", isDefault: false)
            ]
        case .nmr:
            return [
                PhysicsConstraintOption(id: "bloch_equations", name: "Bloch Equations", equation: "dM/dt = \u{03B3}(M \u{00D7} B) - R\u{00B7}(M - M\u{2080})", description: "Magnetization dynamics govern NMR signal evolution", isDefault: true),
                PhysicsConstraintOption(id: "chemical_shift", name: "Chemical Shift Correlation", equation: "\u{03B4} ~ electron density", description: "Chemical shifts correlate with electronic shielding constants", isDefault: true),
                PhysicsConstraintOption(id: "j_coupling", name: "J-Coupling Patterns", equation: "Pascal's triangle splitting", description: "Spin-spin coupling follows predictable multiplet patterns", isDefault: true),
                PhysicsConstraintOption(id: "kramers_kronig", name: "Kramers-Kronig Relation", equation: "Re[\u{03C7}] \u{2194} Im[\u{03C7}]", description: "Real and imaginary parts of susceptibility are related", isDefault: false)
            ]
        case .fluorescence:
            return [
                PhysicsConstraintOption(id: "stokes_shift", name: "Stokes Shift", equation: "\u{03BB}\u{2091}\u{2098} > \u{03BB}\u{2091}\u{2093}", description: "Emission wavelength is always longer than excitation wavelength", isDefault: true),
                PhysicsConstraintOption(id: "mirror_image", name: "Mirror-Image Rule", equation: "Abs(\u{03BD}) \u{2248} mirror Em(\u{03BD})", description: "Absorption and emission spectra are approximately mirror images", isDefault: true),
                PhysicsConstraintOption(id: "kashas_rule", name: "Kasha's Rule", equation: "Em from S\u{2081} only", description: "Emission occurs from lowest excited singlet state regardless of excitation", isDefault: true),
                PhysicsConstraintOption(id: "quantum_yield", name: "Quantum Yield Consistency", equation: "0 \u{2264} \u{03A6} \u{2264} 1", description: "Quantum yield bounded between 0 and 1", isDefault: false)
            ]
        case .xrd:
            return [
                PhysicsConstraintOption(id: "braggs_law", name: "Bragg's Law", equation: "n\u{03BB} = 2d\u{00B7}sin\u{03B8}", description: "Diffraction peak positions correspond to valid d-spacings", isDefault: true),
                PhysicsConstraintOption(id: "systematic_absences", name: "Systematic Absences", equation: "Space group rules", description: "Space group symmetry determines forbidden reflections", isDefault: true),
                PhysicsConstraintOption(id: "structure_factor", name: "Structure Factor", equation: "F(hkl) = \u{03A3}f\u{2C7}\u{00B7}exp(2\u{03C0}i\u{00B7}r\u{2C7}\u{00B7}G)", description: "Intensities from atomic form factors and positions", isDefault: true),
                PhysicsConstraintOption(id: "debye_waller", name: "Debye-Waller Factor", equation: "exp(-B\u{00B7}sin\u{00B2}\u{03B8}/\u{03BB}\u{00B2})", description: "Thermal vibration attenuation of diffraction intensities", isDefault: false)
            ]
        case .chromatography:
            return [
                PhysicsConstraintOption(id: "transport_pde", name: "Transport PDE", equation: "\u{2202}c/\u{2202}t + u\u{00B7}\u{2202}c/\u{2202}z = D\u{00B7}\u{2202}\u{00B2}c/\u{2202}z\u{00B2}", description: "Equilibrium-dispersive model for column mass transport", isDefault: true),
                PhysicsConstraintOption(id: "langmuir_isotherm", name: "Langmuir Isotherm", equation: "q = q\u{209B}\u{00B7}K\u{00B7}c / (1 + K\u{00B7}c)", description: "Nonlinear adsorption isotherm for overloaded conditions", isDefault: true),
                PhysicsConstraintOption(id: "mass_balance", name: "Mass Balance", equation: "\u{222B}c\u{00B7}dt = m\u{1D62}\u{2099}\u{2C7}\u{2091}\u{1D9C}\u{209C}\u{2091}\u{1D48}", description: "Total mass eluted equals mass injected", isDefault: true),
                PhysicsConstraintOption(id: "van_deemter", name: "van Deemter Equation", equation: "H = A + B/u + Cu", description: "Plate height depends on flow rate (eddy, diffusion, mass transfer)", isDefault: false)
            ]
        case .nir:
            return [
                PhysicsConstraintOption(id: "modified_beer_lambert", name: "Modified Beer-Lambert", equation: "A = log(1/R)", description: "Beer-Lambert adapted for diffuse reflectance measurements", isDefault: true),
                PhysicsConstraintOption(id: "kubelka_munk", name: "Kubelka-Munk", equation: "f(R) = (1-R)\u{00B2}/2R", description: "Relates reflectance to absorption and scattering coefficients", isDefault: true),
                PhysicsConstraintOption(id: "overtone_relationships", name: "Overtone Relationships", equation: "\u{03BD}\u{2099} \u{2248} n\u{00B7}\u{03BD}\u{2081}", description: "NIR overtone bands appear at approximate multiples of fundamental frequency", isDefault: true),
                PhysicsConstraintOption(id: "combination_bands", name: "Combination Bands", equation: "\u{03BD} = \u{03BD}\u{2090} + \u{03BD}\u{2095}", description: "Combination band positions from sum of fundamental frequencies", isDefault: false)
            ]
        case .atomicEmission:
            return [
                PhysicsConstraintOption(id: "boltzmann_distribution", name: "Boltzmann Distribution", equation: "I \u{221D} gA\u{00B7}exp(-E/kT)", description: "Excited state populations follow Boltzmann statistics", isDefault: true),
                PhysicsConstraintOption(id: "transition_selection", name: "Transition Selection Rules", equation: "\u{0394}l = \u{00B1}1", description: "Allowed electric dipole transitions follow angular momentum rules", isDefault: true),
                PhysicsConstraintOption(id: "self_absorption", name: "Self-Absorption Correction", equation: "I\u{2092}\u{2095}\u{209B} = I\u{2080}\u{00B7}(1-exp(-\u{03BA}l))", description: "Correct for reabsorption at high concentrations", isDefault: false)
            ]
        case .xps:
            return [
                PhysicsConstraintOption(id: "photoelectric", name: "Photoelectric Equation", equation: "BE = h\u{03BD} - KE - \u{03C6}", description: "Binding energy from kinetic energy and photon energy", isDefault: true),
                PhysicsConstraintOption(id: "scofield_cross_sections", name: "Scofield Cross-Sections", equation: "\u{03C3}(h\u{03BD})", description: "Relative photoionisation cross-sections for quantification", isDefault: true)
            ]
        case .libs:
            return [
                PhysicsConstraintOption(id: "saha_boltzmann", name: "Saha-Boltzmann", equation: "n\u{2091}/n\u{2080} = f(T, n\u{2091})", description: "Ionisation equilibrium for plasma temperature diagnostics", isDefault: true),
                PhysicsConstraintOption(id: "stark_broadening", name: "Stark Broadening", equation: "\u{0394}\u{03BB} \u{221D} n\u{2091}", description: "Line broadening proportional to electron density", isDefault: true)
            ]
        case .hitran:
            return [
                PhysicsConstraintOption(id: "voigt_profile", name: "Voigt Line Profile", equation: "V(\u{03BD}; \u{03B3}_D, \u{03B3}_L)", description: "Convolution of Doppler and pressure broadening", isDefault: true),
                PhysicsConstraintOption(id: "temperature_scaling", name: "Temperature Scaling", equation: "S(T) = S(T\u{2080})\u{00B7}Q(T\u{2080})/Q(T)\u{00B7}...", description: "Line intensity temperature dependence from partition function", isDefault: true)
            ]
        case .atmosphericUVVis:
            return [
                PhysicsConstraintOption(id: "beer_lambert_atm", name: "Beer-Lambert (Atmospheric)", equation: "I = I\u{2080}exp(-\u{03C3}Nl)", description: "Atmospheric extinction via cross-sections", isDefault: true),
                PhysicsConstraintOption(id: "temp_dependent_sigma", name: "Temperature-Dependent \u{03C3}", equation: "\u{03C3}(\u{03BB},T)", description: "Cross-sections vary with atmospheric temperature", isDefault: true)
            ]
        case .usgsReflectance:
            return [
                PhysicsConstraintOption(id: "kubelka_munk", name: "Kubelka-Munk", equation: "F(R) = (1-R)\u{00B2}/2R", description: "Relates reflectance to absorption and scattering", isDefault: true),
                PhysicsConstraintOption(id: "continuum_removal", name: "Continuum Removal", equation: "R' = R/R_hull", description: "Normalize reflectance to convex hull for feature extraction", isDefault: true)
            ]
        case .opticalConstants:
            return [
                PhysicsConstraintOption(id: "sellmeier", name: "Sellmeier Equation", equation: "n\u{00B2} = 1 + \u{03A3}B\u{1D62}\u{03BB}\u{00B2}/(\u{03BB}\u{00B2}-C\u{1D62})", description: "Refractive index dispersion from resonance wavelengths", isDefault: true),
                PhysicsConstraintOption(id: "kramers_kronig_opt", name: "Kramers-Kronig", equation: "n \u{2194} k", description: "Real and imaginary refractive index are related by KK transform", isDefault: true)
            ]
        case .eels:
            return [
                PhysicsConstraintOption(id: "core_loss_onset", name: "Core-Loss Onset", equation: "E = E_edge", description: "Edge onset corresponds to elemental core-level binding energy", isDefault: true),
                PhysicsConstraintOption(id: "kramers_kronig_eels", name: "Kramers-Kronig", equation: "\u{03B5}\u{2081} \u{2194} \u{03B5}\u{2082}", description: "Dielectric function components related by KK transform", isDefault: true)
            ]
        case .saxs:
            return [
                PhysicsConstraintOption(id: "guinier", name: "Guinier Approximation", equation: "I(q) = I\u{2080}exp(-q\u{00B2}Rg\u{00B2}/3)", description: "Low-q regime gives radius of gyration", isDefault: true),
                PhysicsConstraintOption(id: "porod", name: "Porod Law", equation: "I(q) \u{221D} q\u{207B}\u{2074}", description: "High-q regime indicates sharp interfaces", isDefault: true)
            ]
        case .circularDichroism:
            return [
                PhysicsConstraintOption(id: "cotton_effect", name: "Cotton Effect", equation: "\u{0394}\u{03B5} = \u{03B5}_L - \u{03B5}_R", description: "Differential absorption of left/right circularly polarised light", isDefault: true),
                PhysicsConstraintOption(id: "basis_decomposition", name: "Basis Spectrum Decomposition", equation: "CD = \u{03A3}f\u{1D62}\u{00B7}CD\u{1D62}", description: "CD spectrum as linear combination of secondary structure basis spectra", isDefault: true)
            ]
        case .microwaveRotational:
            return [
                PhysicsConstraintOption(id: "rigid_rotor", name: "Rigid Rotor", equation: "E_J = hBJ(J+1)", description: "Rotational energy levels from moment of inertia", isDefault: true),
                PhysicsConstraintOption(id: "centrifugal_distortion", name: "Centrifugal Distortion", equation: "E_J = hBJ(J+1) - hDJ\u{00B2}(J+1)\u{00B2}", description: "Correction for non-rigid molecular rotation", isDefault: true)
            ]
        case .thermogravimetric:
            return [
                PhysicsConstraintOption(id: "arrhenius", name: "Arrhenius Kinetics", equation: "k = A\u{00B7}exp(-Ea/RT)", description: "Temperature-dependent decomposition rate constant", isDefault: true),
                PhysicsConstraintOption(id: "coats_redfern", name: "Coats-Redfern", equation: "ln(-d\u{03B1}/dT) = ln(A/\u{03B2}) - Ea/RT", description: "Model-fitting method for activation energy determination", isDefault: true)
            ]
        case .terahertz:
            return [
                PhysicsConstraintOption(id: "drude", name: "Drude Model", equation: "\u{03C3}\u{2081}(\u{03C9}) = \u{03C3}\u{2080}/(1+\u{03C9}\u{00B2}\u{03C4}\u{00B2})", description: "Free-carrier conductivity in THz regime", isDefault: true),
                PhysicsConstraintOption(id: "lorentz_thz", name: "Lorentz Oscillator", equation: "\u{03B5}(\u{03C9}) = \u{03B5}\u{221E} + \u{03A3}S\u{1D62}/(\u{03C9}\u{1D62}\u{00B2}-\u{03C9}\u{00B2}-i\u{03B3}\u{1D62}\u{03C9})", description: "Phonon/vibrational mode dielectric response", isDefault: true)
            ]
        }
    }
}

// MARK: - Fourier Feature Encoding Configuration

/// Configuration for Fourier feature encoding of spectral inputs.
/// Mapping raw inputs through sin/cos at multiple frequencies eliminates spectral
/// bias and lets the MLP resolve sharp absorption peaks and fine spectral structure.
/// Reference: Tancik et al. (2020), "Fourier Features Let Networks Learn High Frequency
/// Functions in Low Dimensional Domains", NeurIPS.
struct FourierEncodingConfig: Sendable, Equatable {
    /// Number of random Fourier frequencies. Output dimension = 2 × numFrequencies per spatial input.
    let numFrequencies: Int
    /// Standard deviation of the random frequency matrix B ~ N(0, sigma²).
    /// Higher values capture finer spectral detail; lower values suit broad features.
    let sigma: Double
    /// Whether Fourier encoding is enabled for this domain.
    let isEnabled: Bool

    static let disabled = FourierEncodingConfig(numFrequencies: 0, sigma: 0, isEnabled: false)
}

extension PINNDomain {
    /// Recommended Fourier feature encoding configuration per domain.
    /// Domains with sharp spectral features (FTIR, NMR, Atomic Emission) use more
    /// frequencies and higher sigma; domains with broad smooth spectra (UV-Vis,
    /// Fluorescence) use fewer frequencies and lower sigma.
    var fourierEncodingConfig: FourierEncodingConfig {
        switch self {
        case .uvVis:
            return FourierEncodingConfig(numFrequencies: 32, sigma: 4.0, isEnabled: true)
        case .ftir:
            return FourierEncodingConfig(numFrequencies: 128, sigma: 10.0, isEnabled: true)
        case .raman:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 8.0, isEnabled: true)
        case .massSpec:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 6.0, isEnabled: true)
        case .nmr:
            return FourierEncodingConfig(numFrequencies: 128, sigma: 10.0, isEnabled: true)
        case .fluorescence:
            return FourierEncodingConfig(numFrequencies: 32, sigma: 4.0, isEnabled: true)
        case .xrd:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 8.0, isEnabled: true)
        case .chromatography:
            return FourierEncodingConfig(numFrequencies: 48, sigma: 6.0, isEnabled: true)
        case .nir:
            return FourierEncodingConfig(numFrequencies: 128, sigma: 10.0, isEnabled: true)
        case .atomicEmission:
            return FourierEncodingConfig(numFrequencies: 96, sigma: 10.0, isEnabled: true)
        case .xps:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 6.0, isEnabled: true)
        case .libs:
            return FourierEncodingConfig(numFrequencies: 96, sigma: 10.0, isEnabled: true)
        case .hitran:
            return FourierEncodingConfig(numFrequencies: 128, sigma: 10.0, isEnabled: true)
        case .atmosphericUVVis:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 6.0, isEnabled: true)
        case .usgsReflectance:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 8.0, isEnabled: true)
        case .opticalConstants:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 8.0, isEnabled: true)
        case .eels:
            return FourierEncodingConfig(numFrequencies: 64, sigma: 8.0, isEnabled: true)
        case .saxs:
            return FourierEncodingConfig(numFrequencies: 48, sigma: 6.0, isEnabled: true)
        case .circularDichroism:
            return FourierEncodingConfig(numFrequencies: 32, sigma: 4.0, isEnabled: true)
        case .microwaveRotational:
            return FourierEncodingConfig(numFrequencies: 96, sigma: 10.0, isEnabled: true)
        case .thermogravimetric:
            return FourierEncodingConfig(numFrequencies: 32, sigma: 4.0, isEnabled: true)
        case .terahertz:
            return FourierEncodingConfig(numFrequencies: 48, sigma: 6.0, isEnabled: true)
        }
    }
}

// MARK: - Modified MLP / Residual Connection Configuration

/// Whether the generated PINN uses a Modified MLP with skip connections.
/// The Modified MLP (Wang et al. 2021) concatenates encoded inputs into every
/// hidden layer and adds residual connections where dimensions match, dramatically
/// improving gradient flow during PINN training.
extension PINNDomain {
    /// Whether this domain should use the Modified MLP architecture.
    /// Disabled for domains that already have bespoke architectures (XRD f-PICNN,
    /// Chromatography LKM-PINN) which have their own residual strategies.
    var useModifiedMLP: Bool {
        switch self {
        case .xrd:            return false  // f-PICNN has its own NCU residual layers
        case .chromatography: return false  // LKM-PINN has its own multi-network design
        default:              return true
        }
    }
}

// MARK: - Adaptive Activation Function Configuration

/// Activation function choices for PINN hidden layers.
/// Adaptive variants have a learnable scaling parameter `a` per layer, allowing
/// each layer to find its optimal nonlinearity steepness (Jagtap et al. 2020).
enum PINNActivation: String, CaseIterable, Sendable {
    case adaptiveTanh = "adaptive_tanh"
    case adaptiveGELU = "adaptive_gelu"
    case tanh         = "tanh"
    case gelu         = "gelu"

    var displayName: String {
        switch self {
        case .adaptiveTanh: return "Adaptive Tanh"
        case .adaptiveGELU: return "Adaptive GELU"
        case .tanh:         return "Tanh"
        case .gelu:         return "GELU"
        }
    }
}

extension PINNDomain {
    /// Recommended activation function per domain.
    /// Adaptive Tanh is the default — it preserves the smoothness needed for physics
    /// gradients while allowing 2-5x faster convergence. Deeper networks (Chromatography)
    /// may benefit from Adaptive GELU's smoother gradient landscape.
    var activation: PINNActivation {
        switch self {
        case .chromatography: return .adaptiveGELU  // 12-layer LKM-PINN benefits from GELU smoothness
        default:              return .adaptiveTanh
        }
    }
}

// MARK: - Hidden Layer Width Configuration

extension PINNDomain {
    /// Optimized hidden layer widths per domain.
    /// Wider networks suit domains with complex, overlapping spectral features
    /// (FTIR functional groups, NMR multiplets). Narrower networks suffice for
    /// domains with broad smooth spectra (UV-Vis, Fluorescence) or discrete
    /// outputs (Atomic Emission), reducing overfitting risk on smaller datasets.
    // Note: new domains not listed here use the default `adaptiveTanh` via the default case above.

    var hiddenLayers: [Int] {
        switch self {
        case .uvVis:          return [256, 192, 128, 64]   // Broad smooth spectra, Beer-Lambert
        case .ftir:           return [512, 384, 256, 128]  // Thousands of wavenumber points, overlapping functional groups
        case .raman:          return [512, 256, 192, 96]   // Fluorescence background + sharp Raman modes
        case .massSpec:       return [256, 192, 128, 64]   // Discrete m/z peaks, regular isotope patterns
        case .nmr:            return [512, 384, 256, 128]  // Complex multiplet patterns, J-coupling
        case .fluorescence:   return [256, 128, 128, 64]   // Broad emission bands, simple Stokes shift
        case .xrd:            return [384, 256, 128, 64]   // Sharp Bragg peaks, systematic d-spacings
        case .chromatography: return [384, 256, 192, 96]   // Transport PDE residuals, Langmuir isotherm
        case .nir:            return [512, 256, 192, 96]   // Overtone bands — broader than FTIR fundamentals
        case .atomicEmission: return [256, 128, 96, 48]    // Discrete lines, straightforward Boltzmann distribution
        case .xps:                 return [384, 256, 128, 64]   // Wide BE range, multiple core-level peaks
        case .libs:                return [256, 192, 128, 64]   // Similar to atomic emission + plasma params
        case .hitran:              return [512, 384, 256, 128]  // Dense molecular line spectra
        case .atmosphericUVVis:    return [256, 192, 128, 64]   // Broad cross-section features
        case .usgsReflectance:     return [384, 256, 192, 96]   // Wide wavelength range, absorption features
        case .opticalConstants:    return [256, 192, 128, 64]   // Smooth dispersion curves
        case .eels:                return [256, 192, 128, 64]   // Core-loss edge features
        case .saxs:                return [256, 128, 128, 64]   // Smooth scattering profiles
        case .circularDichroism:   return [256, 128, 128, 64]   // Broad CD bands
        case .microwaveRotational: return [256, 128, 96, 48]    // Discrete rotational lines
        case .thermogravimetric:   return [256, 128, 128, 64]   // Smooth mass loss curves
        case .terahertz:           return [256, 128, 128, 64]   // Broad THz absorption features
        }
    }
}

// MARK: - Gradient-Enhanced Training Configuration

/// Configuration for gradient-enhanced training.
/// Supervises the model's input-output Jacobian against known derivative information
/// from physics (e.g., Beer-Lambert slope, peak profile shapes), providing "free"
/// additional training signal beyond the standard data + physics losses.
struct GradientTrainingConfig: Sendable, Equatable {
    /// Whether gradient-enhanced training is enabled.
    let isEnabled: Bool
    /// Weight of the gradient loss relative to data/physics losses.
    /// Typical range: 0.05–0.2. Fed into ReLoBRaLo as a third loss term.
    let weight: Double

    static let disabled = GradientTrainingConfig(isEnabled: false, weight: 0)
}

extension PINNDomain {
    /// Recommended gradient-enhanced training configuration per domain.
    /// Enabled for domains where derivative information is physically meaningful:
    /// - UV-Vis: Beer-Lambert slope dA/dc = εl
    /// - FTIR/NIR: Lorentzian/Gaussian peak profile derivatives
    /// - NMR: Bloch equation ∂M/∂t from relaxation
    /// - Chromatography: van Deemter dH/du
    /// Disabled for domains where gradient signal is noisy or less informative.
    var gradientTrainingConfig: GradientTrainingConfig {
        switch self {
        case .uvVis:          return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .ftir:           return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .raman:          return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .massSpec:       return GradientTrainingConfig(isEnabled: false, weight: 0)  // Discrete m/z — derivatives less meaningful
        case .nmr:            return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .fluorescence:   return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .xrd:            return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .chromatography: return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .nir:            return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .atomicEmission: return GradientTrainingConfig(isEnabled: false, weight: 0)  // Discrete lines — derivatives less meaningful
        case .xps:                 return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .libs:                return GradientTrainingConfig(isEnabled: false, weight: 0)
        case .hitran:              return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .atmosphericUVVis:    return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .usgsReflectance:     return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .opticalConstants:    return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .eels:                return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .saxs:                return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .circularDichroism:   return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        case .microwaveRotational: return GradientTrainingConfig(isEnabled: false, weight: 0)
        case .thermogravimetric:   return GradientTrainingConfig(isEnabled: true, weight: 0.1)
        case .terahertz:           return GradientTrainingConfig(isEnabled: true, weight: 0.05)
        }
    }
}

// MARK: - Ensemble / Multi-Head Output Configuration

/// Configuration for multi-head ensemble output.
/// The shared backbone feeds N independent linear heads; at inference the mean
/// reduces variance while inter-head standard deviation serves as an OOD detector.
/// Reference: Lakshminarayanan et al. (2017), NeurIPS.
struct PINNEnsembleConfig: Sendable, Equatable {
    /// Whether multi-head ensemble output is enabled.
    let isEnabled: Bool
    /// Number of independent output heads sharing the backbone trunk.
    let numHeads: Int

    static let disabled = PINNEnsembleConfig(isEnabled: false, numHeads: 1)
}

extension PINNDomain {
    /// Recommended ensemble configuration per domain.
    /// Most domains use 5 heads for robust uncertainty estimation.
    /// Discrete-output domains (Mass Spec, Atomic Emission) use 3 heads
    /// since their outputs are inherently less smooth.
    var ensembleConfig: PINNEnsembleConfig {
        switch self {
        case .massSpec:       return PINNEnsembleConfig(isEnabled: true, numHeads: 3)
        case .atomicEmission:      return PINNEnsembleConfig(isEnabled: true, numHeads: 3)
        case .libs:                return PINNEnsembleConfig(isEnabled: true, numHeads: 3)
        case .microwaveRotational: return PINNEnsembleConfig(isEnabled: true, numHeads: 3)
        default:                   return PINNEnsembleConfig(isEnabled: true, numHeads: 5)
        }
    }
}

/// A peer-reviewed reference with an optional DOI or URL link.
struct PINNReference: Identifiable, Sendable {
    let id = UUID()
    let citation: String
    let url: String?

    init(_ citation: String, url: String? = nil) {
        self.citation = citation
        self.url = url
    }
}

/// Represents an optional physics constraint that users can toggle for PINN training.
struct PhysicsConstraintOption: Identifiable, Sendable {
    let id: String
    let name: String
    let equation: String
    let description: String
    let isDefault: Bool
}

// MARK: - Domain Mapping

/// Maps SPC experiment type codes to PINN domains.
enum PINNDomainMapping {
    /// Reverse lookup: experiment type code → PINN domain.
    static func domain(for experimentTypeCode: UInt8) -> PINNDomain? {
        for domain in PINNDomain.allCases {
            if domain.spcExperimentTypeCodes.contains(experimentTypeCode) {
                return domain
            }
        }
        return nil
    }
}

// MARK: - Model Status

/// Status of a PINN domain model's lifecycle.
enum PINNModelStatus: Equatable, Sendable {
    case notTrained
    case loading
    case ready
    case error(String)

    var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    var label: String {
        switch self {
        case .notTrained: return "Not Trained"
        case .loading:    return "Loading"
        case .ready:      return "Ready"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}

// MARK: - Normalization Parameters

/// Z-score normalization parameters saved alongside a trained PINN model.
/// Used to normalize inputs and denormalize outputs at inference time.
struct PINNNormalizationParams: Codable, Sendable {
    /// Per-feature means for input normalization (length = input_dim).
    let xMean: [Double]
    /// Per-feature standard deviations for input normalization (length = input_dim).
    let xStd: [Double]
    /// Target mean for output denormalization.
    let yMean: Double
    /// Target standard deviation for output denormalization.
    let yStd: Double

    enum CodingKeys: String, CodingKey {
        case xMean = "X_mean"
        case xStd = "X_std"
        case yMean = "y_mean"
        case yStd = "y_std"
    }

    /// Normalize a feature vector: (x - mean) / std.
    func normalizeInput(_ features: [Double]) -> [Double] {
        guard features.count == xMean.count else { return features }
        return zip(zip(features, xMean), xStd).map { args in
            let ((val, mean), std) = args
            return (val - mean) / std
        }
    }

    /// Denormalize a model output: prediction * y_std + y_mean.
    func denormalizeOutput(_ value: Double) -> Double {
        value * yStd + yMean
    }

    /// Load normalization params from the standard location next to a model.
    /// Returns nil if the file doesn't exist (e.g., pre-normalization model).
    static func load(modelName: String) -> PINNNormalizationParams? {
        let normURL = PINNModelRegistry.modelDirectory
            .appendingPathComponent("\(modelName)_normalization.json")
        guard FileManager.default.fileExists(atPath: normURL.path),
              let data = try? Data(contentsOf: normURL),
              let params = try? JSONDecoder().decode(PINNNormalizationParams.self, from: data) else {
            return nil
        }
        return params
    }
}

// MARK: - Prediction Input/Output

/// Input metadata for a PINN prediction request.
struct PINNInputMetadata: Sendable {
    let experimentTypeCode: UInt8?
    let instrumentID: UUID?
    let plateType: SubstratePlateType?
    let applicationQuantityMg: Double?
    let formulationType: FormulationType?
    let isPostIrradiation: Bool
}

/// Result of a PINN model prediction.
struct PINNPredictionResult: Sendable, Equatable {
    /// The primary predicted value (e.g., SPF, concentration, retention time).
    /// When ensemble is active, this is the mean across heads.
    let primaryValue: Double
    /// Label for the primary value (e.g., "SPF", "Concentration (mg/L)").
    let primaryLabel: String
    /// Lower bound of conformal prediction interval.
    let confidenceLow: Double
    /// Upper bound of conformal prediction interval.
    let confidenceHigh: Double
    /// Optional per-wavelength or per-channel decomposition.
    let decomposition: [String: [Double]]?
    /// Score (0-1) indicating how well the prediction satisfies physics constraints.
    let physicsConsistencyScore: Double
    /// The domain this prediction applies to.
    let domain: PINNDomain
    /// Standard deviation across ensemble heads (0 if single-head).
    /// High values indicate the input may be out-of-distribution.
    let ensembleStd: Double
    /// Raw per-head predictions (empty if single-head).
    let headValues: [Double]

    /// Whether the ensemble disagrees enough to flag OOD concern.
    /// Uses a relative threshold: std / |mean| > 0.15 (15% coefficient of variation).
    var isOutOfDistribution: Bool {
        guard ensembleStd > 0, headValues.count > 1 else { return false }
        let cv = ensembleStd / max(abs(primaryValue), 1e-8)
        return cv > 0.15
    }

    /// Formatted display string.
    var formatted: String {
        if confidenceLow > 0 && confidenceHigh > 0 {
            return String(format: "%.1f (%.1f–%.1f)", primaryValue, confidenceLow, confidenceHigh)
        }
        return String(format: "%.1f", primaryValue)
    }
}
