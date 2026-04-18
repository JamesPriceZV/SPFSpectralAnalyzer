import Foundation

actor TGASynthesizer {

    static let tempGrid: [Double] = stride(from: 300.0, through: 1300.0, by: 5.0).map { $0 }

    func synthesize(Ea_kJ: Double, logA: Double, n: Double = 1.0,
                    beta: Double = 10.0) -> TrainingRecord {
        let Ea = Ea_kJ * 1000.0
        let A = pow(10, logA)
        let R = 8.314

        var alpha = Array(repeating: 0.0, count: Self.tempGrid.count)
        var dAlpha = Array(repeating: 0.0, count: Self.tempGrid.count)
        var alphaVal = 0.0

        for (i, T) in Self.tempGrid.enumerated() {
            let rate = (A / beta) * exp(-Ea / (R * T)) * pow(max(1.0 - alphaVal, 1e-10), n)
            dAlpha[i] = rate
            alpha[i] = alphaVal
            if i + 1 < Self.tempGrid.count {
                alphaVal = min(alphaVal + rate * 5.0, 1.0)
            }
        }

        let onsetIdx = alpha.firstIndex(where: { $0 >= 0.05 }) ?? 0
        let onsetT = Self.tempGrid[onsetIdx]
        let peakIdx = dAlpha.indices.max(by: { dAlpha[$0] < dAlpha[$1] }) ?? 0
        let peakT = Self.tempGrid[peakIdx]

        var features = dAlpha.map { Float($0) }
        features.append(Float(Ea_kJ))
        features.append(Float(logA))
        features.append(Float(n))
        features.append(Float(beta))
        features.append(Float(onsetT))
        features.append(Float(peakT))
        while features.count < 214 { features.append(0) }
        features = Array(features.prefix(214))

        let targets: [String: Double] = [
            "activation_energy_kJ_mol": Ea_kJ,
            "onset_temp_K": onsetT,
            "peak_deriv_temp_K": peakT,
        ]

        return TrainingRecord(
            modality: .thermogravimetric,
            sourceID: "tga_Ea\(Int(Ea_kJ))_n\(String(format: "%.1f", n))",
            features: features, targets: targets,
            metadata: ["Ea_kJ": String(Ea_kJ), "beta": String(beta)])
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { _ in
            synthesize(Ea_kJ: Double.random(in: 50...300),
                       logA: Double.random(in: 5...20),
                       n: Double.random(in: 0.5...2.5),
                       beta: [5.0, 10.0, 20.0].randomElement()!)
        }
    }
}
