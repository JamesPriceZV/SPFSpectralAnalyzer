import Foundation

actor LIBSSynthesizer {

    static let grid: [Double] = stride(from: 200.0, through: 900.0, by: 1.0).map { $0 }
    static let kB_eV: Double = 8.617e-5

    // MARK: - Synthesize (single)

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

        // Phase 39: Compute quantum emission features via shared method
        let spectrumFloat = spectrum.map { Float($0) }
        let temperature_K = Te_eV / Self.kB_eV  // Convert eV to Kelvin
        let elementSymbols = elements.map { $0.symbol }
        let quantumFeats = AtomicEmissionSynthesizer.quantumEmissionFeatures(
            spectrum: spectrumFloat, grid: Self.grid,
            temperature: temperature_K, elements: elementSymbols)

        var features = spectrumFloat
        features.append(Float(Te_eV))
        features.append(Float(log10(max(ne_cm3, 1))))
        features.append(Float(elem1))
        features.append(Float(elem2))
        features.append(Float(elements.first?.fraction ?? 0))
        features.append(Float(elements.count))

        // Append quantum features in sorted key order for deterministic layout
        for (_, v) in quantumFeats.sorted(by: { $0.key < $1.key }) {
            features.append(Float(v))
        }

        let targetCount = SpectralModality.libs.featureCount
        while features.count < targetCount { features.append(0) }
        features = Array(features.prefix(targetCount))

        var targets: [String: Double] = [
            "electron_temp_eV": Te_eV,
            "electron_density_cm3": ne_cm3,
            "element_1": elem1,
        ]
        // Merge quantum features into targets for downstream access
        for (k, v) in quantumFeats { targets[k] = v }

        return TrainingRecord(
            modality: .libs,
            sourceID: "libs_\(elements.map { $0.symbol }.joined())",
            features: features, targets: targets,
            metadata: ["Te_eV": String(Te_eV)])
    }

    // MARK: - Batch Synthesis

    /// Generates a batch of random LIBS training records with randomised
    /// multi-element compositions, plasma temperatures, and electron densities.
    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        // Representative line databases for common LIBS elements
        let lineDB: [String: [(lambda_nm: Double, Aki: Double, Ek_eV: Double, gk: Int)]] = [
            "Fe": [
                (371.9, 1.62e7, 3.332, 11), (373.5, 9.02e6, 3.369, 9),
                (374.6, 5.40e6, 3.396, 7),  (385.9, 9.69e6, 3.211, 9),
                (404.6, 8.62e6, 4.549, 9),  (438.4, 5.00e7, 3.686, 7),
            ],
            "Ca": [
                (393.4, 1.47e8, 3.151, 4),  (396.8, 1.40e8, 3.123, 2),
                (422.7, 2.18e8, 2.933, 3),  (445.5, 8.70e7, 4.680, 7),
            ],
            "Na": [
                (589.0, 6.16e7, 2.104, 4),  (589.6, 6.14e7, 2.102, 2),
                (330.2, 2.84e6, 3.754, 2),
            ],
            "Mg": [
                (285.2, 4.91e8, 4.346, 3),  (383.8, 1.61e8, 5.946, 3),
                (518.4, 5.61e7, 5.108, 5),
            ],
            "Al": [
                (309.3, 7.40e7, 4.022, 4),  (394.4, 4.93e7, 3.143, 2),
                (396.2, 9.80e7, 3.143, 4),
            ],
            "Si": [
                (251.6, 1.68e8, 4.930, 3),  (288.2, 2.17e8, 5.082, 5),
            ],
            "K": [
                (766.5, 3.87e7, 1.617, 4),  (769.9, 3.82e7, 1.610, 2),
            ],
            "H": [
                (656.28, 4.41e7, 12.088, 18), (486.13, 8.42e6, 12.749, 32),
            ],
            "Ti": [
                (334.9, 5.60e7, 3.697, 9),  (336.1, 4.08e7, 3.687, 7),
                (337.3, 2.60e7, 3.685, 5),  (365.3, 2.88e7, 3.444, 11),
            ],
            "Cu": [
                (324.8, 1.39e8, 3.817, 4),  (327.4, 1.37e8, 3.786, 2),
                (510.6, 2.00e6, 3.817, 4),
            ],
            "Li": [
                (670.8, 3.69e7, 1.848, 6),  (610.4, 3.37e5, 3.834, 10),
            ],
            "Ba": [
                (553.5, 1.19e8, 2.239, 3),  (455.4, 1.10e8, 2.722, 5),
            ],
        ]

        let allElements = Array(lineDB.keys)
        var records: [TrainingRecord] = []
        records.reserveCapacity(count)

        for _ in 0..<count {
            // Random number of elements (1-4)
            let nElem = Int.random(in: 1...min(4, allElements.count))
            let chosen = Array(allElements.shuffled().prefix(nElem))
            var fractions = chosen.map { _ in Double.random(in: 0.05...0.5) }
            let fracSum = fractions.reduce(0, +)
            fractions = fractions.map { $0 / fracSum }  // Normalise to sum=1

            let elements = zip(chosen, fractions).map { (symbol: $0.0, fraction: $0.1) }
            let Te_eV = Double.random(in: 0.3...3.0)
            let ne_cm3 = pow(10.0, Double.random(in: 15...18))

            records.append(synthesize(elements: elements, Te_eV: Te_eV,
                                      ne_cm3: ne_cm3, lineDatabase: lineDB))
        }
        return records
    }
}
