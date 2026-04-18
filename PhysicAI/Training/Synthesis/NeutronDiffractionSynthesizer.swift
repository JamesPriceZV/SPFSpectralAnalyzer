import Foundation

/// Neutron Diffraction PINN synthesizer.
/// Feature vector (1163): neutron powder pattern(1151) + 12 derived features.
/// Primary target: crystal_system
actor NeutronDiffractionSynthesizer {

    static let bCoh: [String: Double] = [
        "H": -3.7390, "D": 6.6710, "He": 3.2600, "Li": -1.9000,
        "Be": 7.7900, "B": 5.3000, "C": 6.6460, "N": 9.3600,
        "O": 5.8030, "F": 5.6540, "Na": 3.6300, "Mg": 5.3750,
        "Al": 3.4490, "Si": 4.1491, "P": 5.1300, "S": 2.8470,
        "Cl": 9.5770, "K": 3.6700, "Ca": 4.7000, "Ti": -3.4380,
        "V": -0.3824, "Cr": 3.6350, "Mn": -3.7300, "Fe": 9.4500,
        "Co": 2.4900, "Ni": 10.3000, "Cu": 7.7180, "Zn": 5.6800,
        "Ga": 7.2880, "Ge": 8.1850, "As": 6.5800, "Se": 7.9700,
        "Sr": 7.0200, "Y": 7.7500, "Zr": 7.1600, "Nb": 7.0540,
        "Mo": 6.7150, "Ru": 7.0300, "Rh": 5.8800, "Pd": 5.9100,
        "Ag": 5.9220, "Cd": 4.8700, "In": 4.0650, "Sn": 6.2250,
        "Sb": 5.5700, "I": 5.2800, "Cs": 5.4200, "Ba": 5.0700,
        "La": 8.2400, "Ce": 4.8400, "Pr": 4.5800, "Nd": 7.6900,
        "Gd": 6.5000, "Tb": 7.3800, "Dy": 1.6900, "Ho": 8.0100,
        "Yb": 1.2600, "Hf": 7.7700, "Ta": 6.9100, "W": 4.7550,
        "Re": 9.2000, "Ir": 10.600, "Pt": 9.6000, "Au": 7.6300,
        "Hg": 1.2692, "Tl": 8.7760, "Pb": 9.4050, "Bi": 8.5320,
        "U": 8.4170,
    ]

    static let lambda = 1.7959
    static let twoThetaGrid: [Double] = stride(from: 5.0, through: 120.05, by: 0.1).map { $0 }

    struct CrystalSite: Sendable {
        let element: String
        let x: Double; let y: Double; let z: Double
        let occupancy: Double
        let bIso: Double
    }

    struct UnitCell: Sendable {
        let a: Double; let b: Double; let c: Double
        let alpha: Double; let beta: Double; let gamma: Double
        let spaceGroupNumber: Int
        let sites: [CrystalSite]
        var volume: Double {
            let ar = alpha * .pi / 180; let br = beta * .pi / 180; let gr = gamma * .pi / 180
            return a*b*c*sqrt(1 - cos(ar)*cos(ar) - cos(br)*cos(br) - cos(gr)*cos(gr)
                               + 2*cos(ar)*cos(br)*cos(gr))
        }
    }

    func synthesizePattern(cell: UnitCell,
                            crystalliteSize: Double = Double.random(in: 30...500),
                            hBackground: Double = 0.02,
                            isDeuterated: Bool = false) -> TrainingRecord {

        var pattern = [Float](repeating: 0, count: Self.twoThetaGrid.count)
        let lambda = Self.lambda
        let hklList = generateHKL(cell: cell, lambdaAng: lambda)

        for (h, k, l) in hklList {
            guard let dHKL = dSpacingOrthoApprox(h: h, k: k, l: l, cell: cell),
                  dHKL > lambda / 2.0 else { continue }
            let sinT = lambda / (2.0 * dHKL)
            guard sinT <= 1.0 else { continue }
            let theta = asin(sinT)
            let tt = 2.0 * theta * 180.0 / .pi

            let F2 = abs(structureFactor(h: h, k: k, l: l, cell: cell,
                                          sinThetaOverLambda: sinT / lambda))
            guard F2 > 0.001 else { continue }

            let LP = 1.0 / (sinT * sinT * cos(theta))
            let mult = Double(multiplicityFactor(h: h, k: k, l: l))
            let Icalc = F2 * LP * mult

            let betaRad = (0.9 * lambda) / (crystalliteSize * cos(theta))
            let betaDeg = betaRad * 180.0 / .pi
            let sigma = betaDeg / 2.355

            for (i, t2) in Self.twoThetaGrid.enumerated() {
                let dx = t2 - tt
                pattern[i] += Float(Icalc * exp(-dx*dx/(2*sigma*sigma)))
            }
        }

        let bgLevel = isDeuterated ? 0.005 : hBackground
        pattern = pattern.map { $0 + Float(bgLevel + Double.random(in: 0...bgLevel*0.1)) }

        let maxI = pattern.max() ?? 1.0
        pattern = pattern.map { $0 / max(maxI, 1e-6) }

        let peakCount = countPeaks(pattern: pattern, threshold: 0.03)
        let (d1, d2) = topTwoDSpacings(pattern: pattern, lambda: lambda)

        var features = pattern
        features += [
            Float(peakCount), Float(d1), Float(d2), Float(bgLevel),
            isDeuterated ? 1 : 0, Float(lambda), Float(cell.volume),
            0, isDeuterated ? 1 : 0,
            Float(pattern.prefix(400).reduce(0, +) / max(pattern.suffix(750).reduce(0, +), 1e-6)),
            Float(estimateFWHM(pattern: pattern)), 0
        ]
        while features.count < 1163 { features.append(0) }
        features = Array(features.prefix(1163))

        let crystalSystem = crystalSystemFromSG(cell.spaceGroupNumber)
        let targets: [String: Double] = [
            "crystal_system": Double(crystalSystem.hashValue % 7),
            "unit_cell_vol_A3": cell.volume,
            "crystallite_size_nm": crystalliteSize / 10.0,
            "h_background": bgLevel,
        ]

        return TrainingRecord(
            modality: .neutronDiffraction,
            sourceID: "nd_synth_sg\(cell.spaceGroupNumber)",
            features: features, targets: targets,
            metadata: ["crystal_system": crystalSystem, "space_group": "\(cell.spaceGroupNumber)"],
            isComputedLabel: true,
            computationMethod: "Bragg_NeutronScatteringLengths")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let sampleCells: [UnitCell] = [
            .init(a: 5.64, b: 5.64, c: 5.64, alpha: 90, beta: 90, gamma: 90,
                  spaceGroupNumber: 225,
                  sites: [.init(element: "Na", x: 0, y: 0, z: 0, occupancy: 1, bIso: 0.4),
                          .init(element: "Cl", x: 0.5, y: 0.5, z: 0.5, occupancy: 1, bIso: 0.5)]),
            .init(a: 3.99, b: 3.99, c: 4.03, alpha: 90, beta: 90, gamma: 90,
                  spaceGroupNumber: 129,
                  sites: [.init(element: "Fe", x: 0, y: 0, z: 0, occupancy: 1, bIso: 0.5)]),
            .init(a: 5.24, b: 5.15, c: 7.24, alpha: 90, beta: 90, gamma: 90,
                  spaceGroupNumber: 62,
                  sites: [.init(element: "Ca", x: 0, y: 0, z: 0, occupancy: 1, bIso: 0.6),
                          .init(element: "C", x: 0.25, y: 0.25, z: 0, occupancy: 1, bIso: 0.8)]),
            .init(a: 4.91, b: 4.91, c: 5.40, alpha: 90, beta: 90, gamma: 120,
                  spaceGroupNumber: 154,
                  sites: [.init(element: "Si", x: 0.47, y: 0, z: 0, occupancy: 1, bIso: 0.35),
                          .init(element: "O", x: 0.41, y: 0.27, z: 0.12, occupancy: 1, bIso: 0.55)]),
        ]
        return (0..<count).map { _ in
            let cell = sampleCells.randomElement()!
            return synthesizePattern(cell: cell, isDeuterated: Double.random(in: 0...1) < 0.3)
        }
    }

    // MARK: - Crystallographic helpers

    private func generateHKL(cell: UnitCell, lambdaAng: Double) -> [(Int, Int, Int)] {
        var list: [(Int, Int, Int)] = []
        let hMax = Int(2.0 * cell.a / lambdaAng) + 2
        let kMax = Int(2.0 * cell.b / lambdaAng) + 2
        let lMax = Int(2.0 * cell.c / lambdaAng) + 2
        for h in -hMax...hMax {
            for k in -kMax...kMax {
                for l in 0...lMax {
                    if h == 0 && k == 0 && l == 0 { continue }
                    list.append((h, k, l))
                }
            }
        }
        return list
    }

    private func dSpacingOrthoApprox(h: Int, k: Int, l: Int, cell: UnitCell) -> Double? {
        let h2 = Double(h*h) / (cell.a*cell.a)
        let k2 = Double(k*k) / (cell.b*cell.b)
        let l2 = Double(l*l) / (cell.c*cell.c)
        let inv_d2 = h2 + k2 + l2
        guard inv_d2 > 1e-10 else { return nil }
        return 1.0 / sqrt(inv_d2)
    }

    private func structureFactor(h: Int, k: Int, l: Int,
                                  cell: UnitCell, sinThetaOverLambda: Double) -> Double {
        var sumRe = 0.0, sumIm = 0.0
        for site in cell.sites {
            guard let b = Self.bCoh[site.element] else { continue }
            let phase = 2.0 * Double.pi * (Double(h)*site.x + Double(k)*site.y + Double(l)*site.z)
            let dw = exp(-site.bIso * sinThetaOverLambda * sinThetaOverLambda)
            sumRe += site.occupancy * b * dw * cos(phase)
            sumIm += site.occupancy * b * dw * sin(phase)
        }
        return sumRe*sumRe + sumIm*sumIm
    }

    private func multiplicityFactor(h: Int, k: Int, l: Int) -> Int {
        let ah = abs(h), ak = abs(k), al = abs(l)
        if ah == ak && ak == al { return 8 }
        if ah == ak || ak == al || ah == al { return 24 }
        return 48
    }

    private func countPeaks(pattern: [Float], threshold: Float) -> Int {
        var count = 0
        for i in 1..<(pattern.count-1) {
            if pattern[i] > threshold && pattern[i] >= pattern[i-1] && pattern[i] >= pattern[i+1] {
                count += 1
            }
        }
        return count
    }

    private func topTwoDSpacings(pattern: [Float], lambda: Double) -> (Double, Double) {
        var peaks: [(Float, Double)] = []
        for i in 1..<(pattern.count-1) {
            if pattern[i] >= pattern[i-1] && pattern[i] >= pattern[i+1] && pattern[i] > 0.05 {
                let tt = Self.twoThetaGrid[i]
                let sinT = sin(tt * .pi / 360.0)
                let d = sinT > 1e-10 ? lambda / (2.0 * sinT) : 0
                peaks.append((pattern[i], d))
            }
        }
        peaks.sort { $0.0 > $1.0 }
        return (peaks.first?.1 ?? 0, peaks.dropFirst().first?.1 ?? 0)
    }

    private func estimateFWHM(pattern: [Float]) -> Double {
        guard let maxI = pattern.max(), maxI > 0.05 else { return 0 }
        let halfMax = maxI / 2.0
        var crossings = 0
        for i in 1..<pattern.count {
            if (pattern[i-1] < halfMax) != (pattern[i] < halfMax) { crossings += 1 }
        }
        return crossings > 0 ? Double(Self.twoThetaGrid.count) * 0.1 / Double(crossings) : 0
    }

    private func crystalSystemFromSG(_ spaceGroup: Int) -> String {
        switch spaceGroup {
        case 1...2: return "triclinic"
        case 3...15: return "monoclinic"
        case 16...74: return "orthorhombic"
        case 75...142: return "tetragonal"
        case 143...167: return "trigonal"
        case 168...194: return "hexagonal"
        case 195...230: return "cubic"
        default: return "unknown"
        }
    }
}
