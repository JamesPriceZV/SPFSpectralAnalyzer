import Foundation

nonisolated struct ModalityAxisSpec: Sendable {
    let axisLabel: String
    let axisUnit: String
    let axisValues: [Double]
    let featureNamePrefix: String

    var featureLabels: [String] {
        axisValues.map { v in
            "\(featureNamePrefix)\(Int(v))"
        }
    }

    static func make(for modality: SpectralModality) -> ModalityAxisSpec {
        switch modality {
        case .uvVis:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (290...400).map { Double($0) },
                         featureNamePrefix: "abs_")
        case .ftir:
            return .init(axisLabel: "Wavenumber (cm-1)", axisUnit: "cm-1",
                         axisValues: stride(from: 400.0, through: 4000.0, by: 10.0).map { $0 },
                         featureNamePrefix: "abs_")
        case .nir:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 800.0, through: 2498.0, by: 2.0).map { $0 },
                         featureNamePrefix: "abs_")
        case .raman:
            return .init(axisLabel: "Raman Shift (cm-1)", axisUnit: "cm-1",
                         axisValues: stride(from: 100.0, through: 3590.0, by: 10.0).map { $0 },
                         featureNamePrefix: "int_")
        case .massSpecEI, .massSpecMSMS:
            return .init(axisLabel: "m/z (Da)", axisUnit: "Da",
                         axisValues: (1...500).map { Double($0) },
                         featureNamePrefix: "mz_")
        case .nmrProton:
            return .init(axisLabel: "Chemical Shift (ppm)", axisUnit: "ppm",
                         axisValues: stride(from: 0.0, through: 11.95, by: 0.05).map { $0 },
                         featureNamePrefix: "d_")
        case .nmrCarbon:
            return .init(axisLabel: "13C Shift (ppm)", axisUnit: "ppm",
                         axisValues: (0...249).map { Double($0) },
                         featureNamePrefix: "c_")
        case .fluorescence:
            return .init(axisLabel: "Emission Wavelength (nm)", axisUnit: "nm",
                         axisValues: stride(from: 300.0, through: 898.0, by: 2.0).map { $0 },
                         featureNamePrefix: "em_")
        case .xrdPowder:
            return .init(axisLabel: "2theta (deg)", axisUnit: "deg",
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
                         axisValues: [],
                         featureNamePrefix: "md_")
        case .hitranMolecular:
            return .init(axisLabel: "Wavenumber (cm-1)", axisUnit: "cm-1",
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
            return .init(axisLabel: "q (1/A)", axisUnit: "1/angstrom",
                         axisValues: Array(logBins),
                         featureNamePrefix: "Iq_")
        case .circularDichroism:
            return .init(axisLabel: "Wavelength (nm)", axisUnit: "nm",
                         axisValues: (180...299).map { Double($0) },
                         featureNamePrefix: "cd_")
        case .microwaveRotational:
            return .init(axisLabel: "Frequency (GHz)", axisUnit: "GHz",
                         axisValues: Array(stride(from: 1.0, through: 996.0, by: 5.0).prefix(200)),
                         featureNamePrefix: "f_")
        case .thermogravimetric:
            return .init(axisLabel: "Temperature (degC)", axisUnit: "degC",
                         axisValues: Array(stride(from: 25.0, through: 1020.0, by: 5.0).prefix(200)),
                         featureNamePrefix: "tga_")
        case .terahertz:
            return .init(axisLabel: "THz Frequency (THz)", axisUnit: "THz",
                         axisValues: Array(stride(from: 0.1, through: 10.05, by: 0.05).prefix(200)),
                         featureNamePrefix: "thz_")
        }
    }
}

nonisolated enum ModalitySchemas {
    struct Spec: Sendable {
        let featureLabels: [String]
        let targetLabels: [String]
        let featureCount: Int
    }

    static func spec(for modality: SpectralModality) -> Spec {
        let axis = ModalityAxisSpec.make(for: modality)
        return Spec(
            featureLabels: axis.featureLabels,
            targetLabels: [modality.primaryTargetColumn],
            featureCount: modality.featureCount
        )
    }
}
