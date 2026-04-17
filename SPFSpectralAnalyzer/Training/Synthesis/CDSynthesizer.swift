import Foundation

actor CDSynthesizer {

    static let grid: [Double] = stride(from: 178.0, through: 298.0, by: 1.0).map { $0 }

    static let basisHelix: [Double] = {
        let g = stride(from: 178.0, through: 298.0, by: 1.0).map { $0 }
        return g.map { lam in
            gaussian(lam, centre: 193, sigma: 8, amp: 40000) +
            gaussian(lam, centre: 208, sigma: 6, amp: -33000) +
            gaussian(lam, centre: 222, sigma: 5, amp: -31000)
        }
    }()

    static let basisSheet: [Double] = {
        let g = stride(from: 178.0, through: 298.0, by: 1.0).map { $0 }
        return g.map { lam in
            gaussian(lam, centre: 198, sigma: 9, amp: -16000) +
            gaussian(lam, centre: 217, sigma: 7, amp: 3500)
        }
    }()

    static func gaussian(_ x: Double, centre: Double, sigma: Double, amp: Double) -> Double {
        amp * exp(-(x - centre) * (x - centre) / (2 * sigma * sigma))
    }

    func synthesize(helix: Double, sheet: Double, turn: Double,
                    accession: String = "synthetic") -> TrainingRecord {
        let coil = max(0, 1.0 - helix - sheet - turn)
        let basisCoil: [Double] = Self.grid.map { lam in
            Self.gaussian(lam, centre: 200, sigma: 15, amp: -5000)
        }
        let basisTurn: [Double] = Self.grid.map { lam in
            Self.gaussian(lam, centre: 205, sigma: 8, amp: 2500)
        }

        var spectrum = Self.grid.indices.map { i -> Double in
            helix * Self.basisHelix[i] + sheet * Self.basisSheet[i] +
            turn * basisTurn[i] + coil * basisCoil[i]
        }
        spectrum = spectrum.map { v in v + Double.random(in: -1...1) * 0.01 * abs(v) }

        let theta222 = spectrum[Self.grid.firstIndex(where: { $0 >= 222 }) ?? 44]

        var features = spectrum.map { Float($0) }
        features.append(Float(helix)); features.append(Float(sheet))
        features.append(Float(turn)); features.append(Float(coil))
        features.append(Float(theta222))
        features.append(Float(spectrum.min() ?? 0)); features.append(Float(spectrum.max() ?? 0))
        while features.count < 128 { features.append(0) }
        features = Array(features.prefix(128))

        let targets: [String: Double] = [
            "helix_fraction": helix, "sheet_fraction": sheet,
            "turn_fraction": turn, "ellipticity_at_222nm": theta222
        ]

        return TrainingRecord(
            modality: .circularDichroism, sourceID: accession,
            features: features, targets: targets,
            metadata: ["helix": String(helix), "sheet": String(sheet)])
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { i in
            let h = Double.random(in: 0...0.9)
            let s = Double.random(in: 0...(1.0 - h))
            let t = Double.random(in: 0...(1.0 - h - s))
            return synthesize(helix: h, sheet: s, turn: t, accession: "synth_\(i)")
        }
    }
}
