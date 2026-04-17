import Foundation

actor XPSSynthesizer {

    private let photonEnergy = 1486.6  // Al Ka eV
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

    func synthesizeSurface(elements: [(symbol: String, atomicPct: Double, oxidationState: Int)]) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: 1200)
        for (el, pct, oxState) in elements {
            let baseKey = "\(el)1s"
            guard let baseBE = coreLevelBE[baseKey] ?? coreLevelBE["\(el)2p"] else { continue }
            let shift = oxidationShift(element: el, state: oxState)
            let be = baseBE + shift
            let sf = scofield[baseKey] ?? scofield["\(el)2p"] ?? 1.0
            let area = Float(pct * sf / 100.0)
            let sigma = 0.9
            for i in 0..<1200 {
                let dx = beGrid[i] - be
                spectrum[i] += area * Float(exp(-(dx * dx) / (2 * sigma * sigma)) / (sigma * 2.507))
            }
        }
        // Background noise
        for i in 0..<spectrum.count {
            spectrum[i] += Float.random(in: 0...0.0005)
        }

        let carbonPct = elements.first(where: { $0.symbol == "C" })?.atomicPct ?? 0
        let derived: [String: Double] = [
            "surface_carbon_pct": carbonPct,
            "total_signal_area": Double(spectrum.reduce(0, +)),
        ]

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.xps.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.xps.featureCount))

        return TrainingRecord(
            modality: .xps, sourceID: "synth_xps",
            features: features, targets: derived,
            metadata: ["elements": elements.map { $0.symbol }.joined(separator: ",")],
            isComputedLabel: true, computationMethod: "Photoelectric_XPS")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let elementSets: [[(String, Double, Int)]] = [
            [("C", 70, 0), ("O", 20, 0), ("N", 10, 0)],
            [("C", 50, 0), ("O", 30, 0), ("Si", 20, 4)],
            [("Fe", 40, 2), ("O", 40, 0), ("C", 20, 0)],
            [("Ti", 30, 4), ("O", 50, 0), ("C", 20, 0)],
            [("C", 90, 0), ("O", 5, 0), ("F", 5, 0)],
        ]
        return (0..<count).map { i in
            let base = elementSets[i % elementSets.count]
            let noisy = base.map { (s, p, o) in
                (symbol: s, atomicPct: p + Double.random(in: -5...5), oxidationState: o)
            }
            return synthesizeSurface(elements: noisy)
        }
    }

    private func oxidationShift(element: String, state: Int) -> Double {
        let shifts: [String: [Int: Double]] = [
            "C": [1: 1.5, 2: 3.0, 3: 4.2, 4: 5.0],
            "Fe": [2: 1.5, 3: 3.8],
            "Ti": [2: 1.0, 3: 2.5, 4: 4.0],
            "Si": [4: 3.9]
        ]
        return shifts[element]?[state] ?? 0.0
    }
}
