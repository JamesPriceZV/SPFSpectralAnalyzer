import Foundation

actor LIBSSynthesizer {

    static let grid: [Double] = stride(from: 200.0, through: 900.0, by: 1.0).map { $0 }
    static let kB_eV: Double = 8.617e-5

    func synthesize(elements: [(symbol: String, fraction: Double)],
                    Te_eV: Double, ne_cm3: Double,
                    lineDatabase: [String: [(lambda_nm: Double, Aki: Double, Ek_eV: Double, gk: Int)]]) -> TrainingRecord {

        var spectrum = Array(repeating: 0.0, count: Self.grid.count)

        for (symbol, fraction) in elements {
            guard let lines = lineDatabase[symbol] else { continue }
            let U = lines.map { Double($0.gk) * exp(-$0.Ek_eV / Te_eV) }.reduce(0, +)
            guard U > 0 else { continue }

            for line in lines {
                let intensity = fraction * line.Aki * Double(line.gk) * exp(-line.Ek_eV / Te_eV) / U
                let starkFWHM = 0.04 * (ne_cm3 / 1e16)

                if let idx = Self.grid.firstIndex(where: { $0 >= line.lambda_nm }) {
                    let window = max(3, Int(starkFWHM * 5))
                    let startIdx = max(0, idx - window)
                    let endIdx = min(Self.grid.count - 1, idx + window)
                    for j in startIdx...endIdx {
                        let d = Self.grid[j] - line.lambda_nm
                        let lorentz = (starkFWHM / 2) / (.pi * (d * d + (starkFWHM / 2) * (starkFWHM / 2)))
                        spectrum[j] += intensity * lorentz
                    }
                }
            }
        }

        // Bremsstrahlung continuum
        let bremss = Self.grid.map { lam -> Double in
            let hnu_eV = 1240.0 / lam
            return ne_cm3 * ne_cm3 * 1e-40 * exp(-hnu_eV / Te_eV)
        }
        spectrum = zip(spectrum, bremss).map { $0 + $1 }

        let elem1 = Double(ElementTable.symbolToZ[elements.first?.symbol ?? ""] ?? 0)
        let elem2 = elements.count > 1 ? Double(ElementTable.symbolToZ[elements[1].symbol] ?? 0) : 0

        var features = spectrum.map { Float($0) }
        features.append(Float(Te_eV))
        features.append(Float(log10(max(ne_cm3, 1))))
        features.append(Float(elem1))
        features.append(Float(elem2))
        features.append(Float(elements.first?.fraction ?? 0))
        features.append(Float(elements.count))
        while features.count < 716 { features.append(0) }
        features = Array(features.prefix(716))

        let targets: [String: Double] = [
            "electron_temp_eV": Te_eV,
            "electron_density_cm3": ne_cm3,
            "element_1": elem1,
        ]

        return TrainingRecord(
            modality: .libs,
            sourceID: "libs_\(elements.map { $0.symbol }.joined())",
            features: features, targets: targets,
            metadata: ["Te_eV": String(Te_eV)])
    }
}
