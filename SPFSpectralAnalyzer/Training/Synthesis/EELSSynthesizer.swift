import Foundation

actor EELSSynthesizer {

    static let grid: [Double] = stride(from: 0.0, through: 3000.0, by: 5.0).map { $0 }

    func synthesize(from spectrum: EELSDBParser.EELSSpectrum) -> TrainingRecord {
        let ints = interpolate(xs: spectrum.energies, ys: spectrum.intensities, grid: Self.grid)

        let plasmonRange = Self.grid.indices.filter { Self.grid[$0] <= 100 }
        let plasmonIdx = plasmonRange.max(by: { ints[$0] < ints[$1] }) ?? 0
        let plasmonEnergy = Self.grid[plasmonIdx]

        let edgeOnset = spectrum.edgeOnsetEV > 0 ? spectrum.edgeOnsetEV : detectEdgeOnset(ints: ints)

        let elementMap = ElementTable.symbolToZ
        let Z = Double(elementMap[spectrum.element] ?? 0)

        var features = ints.map { Float($0) }
        features.append(Float(plasmonEnergy))
        features.append(Float(edgeOnset))
        features.append(Float(Z))
        while features.count < 612 { features.append(0) }
        features = Array(features.prefix(612))

        let targets: [String: Double] = [
            "edge_onset_eV": edgeOnset,
            "plasmon_energy_eV": plasmonEnergy,
            "edge_element": Z,
        ]

        return TrainingRecord(
            modality: .eels, sourceID: "eelsdb_\(spectrum.id)",
            features: features, targets: targets,
            metadata: ["element": spectrum.element, "edge": spectrum.edge])
    }

    private func detectEdgeOnset(ints: [Double]) -> Double {
        let startIdx = Self.grid.firstIndex(where: { $0 > 100 }) ?? 0
        for i in startIdx..<(ints.count - 1) {
            if ints[i + 1] > ints[i] * 3.0 { return Self.grid[i] }
        }
        return 200.0
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}

/// Shared element symbol to atomic number mapping.
nonisolated enum ElementTable {
    static let symbolToZ: [String: Int] = {
        let symbols = ["H","He","Li","Be","B","C","N","O","F","Ne",
                       "Na","Mg","Al","Si","P","S","Cl","Ar","K","Ca",
                       "Sc","Ti","V","Cr","Mn","Fe","Co","Ni","Cu","Zn",
                       "Ga","Ge","As","Se","Br","Kr","Rb","Sr","Y","Zr",
                       "Nb","Mo","Tc","Ru","Rh","Pd","Ag","Cd","In","Sn",
                       "Sb","Te","I","Xe","Cs","Ba","La","Ce","Pr","Nd",
                       "Pm","Sm","Eu","Gd","Tb","Dy","Ho","Er","Tm","Yb",
                       "Lu","Hf","Ta","W","Re","Os","Ir","Pt","Au","Hg",
                       "Tl","Pb","Bi","Po","At","Rn","Fr","Ra","Ac","Th",
                       "Pa","U","Np","Pu"]
        return Dictionary(uniqueKeysWithValues: symbols.enumerated().map { ($1, $0 + 1) })
    }()
}
