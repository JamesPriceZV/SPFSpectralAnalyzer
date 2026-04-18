import Foundation

/// Quantum Dot Photoluminescence PINN synthesizer.
/// Feature vector (280): PL spectrum(250) + 15 scalar descriptors + padding.
/// Primary target: peak_emission_nm
actor QuantumDotSynthesizer {

    struct QDMaterial: Sendable, Hashable {
        let code: Int
        let name: String
        let bulkGapEV: Double
        let mEff_e: Double
        let mEff_h: Double
        let epsilonR: Double
    }

    static let materials: [QDMaterial] = [
        QDMaterial(code: 0, name: "CdSe", bulkGapEV: 1.74, mEff_e: 0.13, mEff_h: 0.45, epsilonR: 10.6),
        QDMaterial(code: 1, name: "InP", bulkGapEV: 1.35, mEff_e: 0.08, mEff_h: 0.60, epsilonR: 12.5),
        QDMaterial(code: 2, name: "CdS", bulkGapEV: 2.42, mEff_e: 0.21, mEff_h: 0.80, epsilonR: 8.9),
        QDMaterial(code: 3, name: "ZnSe", bulkGapEV: 2.70, mEff_e: 0.17, mEff_h: 0.78, epsilonR: 9.1),
        QDMaterial(code: 4, name: "PbS", bulkGapEV: 0.41, mEff_e: 0.085, mEff_h: 0.085, epsilonR: 17.2),
        QDMaterial(code: 5, name: "CsPbBr3", bulkGapEV: 2.36, mEff_e: 0.15, mEff_h: 0.19, epsilonR: 4.1),
    ]

    static let plGrid: [Double] = stride(from: 400.0, through: 898.0, by: 2.0).map { $0 }

    private let hbar = 1.054571817e-34
    private let me = 9.1093837015e-31
    private let e0 = 1.602176634e-19
    private let eps0 = 8.8541878e-12
    private let hc_eVnm = 1239.8

    func brusShift(material: QDMaterial, radiusNM: Double) -> Double {
        let R = radiusNM * 1e-9
        let me_ = material.mEff_e * me
        let mh_ = material.mEff_h * me
        let KE = (hbar * hbar * Double.pi * Double.pi / (2.0 * R * R)) *
                 (1.0/me_ + 1.0/mh_) / e0
        let coulomb = 1.8 * e0 / (4.0 * Double.pi * eps0 * material.epsilonR * R * e0)
        return KE - coulomb
    }

    func synthesizeQD(material: QDMaterial, radiusNM: Double,
                      sizeDispersion: Double = 0.1, shellCode: Int = 1,
                      excitationNM: Double = 365.0) -> TrainingRecord {

        let brus = brusShift(material: material, radiusNM: radiusNM)
        let gapEV = material.bulkGapEV + max(brus, 0)
        let peakNM = hc_eVnm / gapEV
        let stokes = Double.random(in: 8...30)
        let emPeakNM = peakNM + stokes
        let fwhmNM = emPeakNM * sizeDispersion * 2.5 + 15.0

        let sigma = fwhmNM / 2.355
        var pl = Self.plGrid.map { nm -> Double in
            exp(-(nm - emPeakNM) * (nm - emPeakNM) / (2.0 * sigma * sigma))
        }
        let maxPL = pl.max() ?? 1.0
        pl = pl.map { $0 / max(maxPL, 1e-9) }
        pl = pl.map { max(0, $0 + Double.random(in: -0.005...0.005)) }

        let qyBase: Double = [0.6, 0.5, 0.55, 0.45, 0.35, 0.85][material.code]
        let qy = max(0.01, min(0.99, qyBase * (1 - sizeDispersion)))

        var features = pl.map { Float($0) }
        features += [
            Float(excitationNM), Float(material.code), Float(shellCode),
            Float(radiusNM), Float(material.bulkGapEV),
            Float(material.mEff_e), Float(material.mEff_h), Float(material.epsilonR),
            Float(brus), Float(gapEV), Float(emPeakNM),
            Float(fwhmNM), Float(stokes), Float(qy), Float(sizeDispersion)
        ]
        while features.count < 280 { features.append(0) }
        features = Array(features.prefix(280))

        let targets: [String: Double] = [
            "peak_emission_nm": emPeakNM,
            "brus_shift_eV": brus,
            "gap_eV": gapEV,
            "fwhm_nm": fwhmNM,
            "stokes_shift_nm": stokes,
            "quantum_yield": qy,
        ]

        return TrainingRecord(
            modality: .quantumDotPL,
            sourceID: "brus_\(material.name)_R\(String(format: "%.1f", radiusNM))nm",
            features: features, targets: targets,
            metadata: ["material": material.name, "shell_code": "\(shellCode)"],
            isComputedLabel: true,
            computationMethod: "Brus_QD_Confinement")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let radiiRanges: [Int: ClosedRange<Double>] = [
            0: 1.5...6.0, 1: 1.0...5.0, 2: 1.5...5.5,
            3: 1.5...5.0, 4: 2.0...8.0, 5: 2.0...6.0
        ]
        return (0..<count).map { _ in
            let mat = Self.materials.randomElement()!
            let range = radiiRanges[mat.code] ?? 1.5...6.0
            let R = Double.random(in: range)
            let disp = Double.random(in: 0.05...0.25)
            let shell = Int.random(in: 0...2)
            let ex = [365.0, 405.0, 450.0, 488.0].randomElement()!
            return synthesizeQD(material: mat, radiusNM: R,
                                sizeDispersion: disp, shellCode: shell, excitationNM: ex)
        }
    }
}
