import Foundation

actor XRDSynthesizer {

    struct DiffractionPeak: Sendable {
        let dSpacing: Double
        let relIntensity: Double
    }

    private let lambda = 1.5406  // Cu Ka1
    private let twoThetaGrid = stride(from: 5.0, through: 89.95, by: 0.1).map { $0 }

    func synthesizePattern(peaks: [DiffractionPeak],
                           crystalliteSize: Double = Double.random(in: 20...200),
                           eta: Double = 0.5) -> TrainingRecord {
        var pattern = [Float](repeating: 0, count: twoThetaGrid.count)
        for pk in peaks {
            let sinT = lambda / (2.0 * pk.dSpacing)
            guard sinT <= 1.0 else { continue }
            let theta = asin(sinT)
            let tt = 2.0 * theta * 180.0 / .pi
            let betaRad = (0.9 * lambda) / (crystalliteSize * cos(theta))
            let betaDeg = betaRad * 180.0 / .pi
            let sigma = betaDeg / 2.355
            for (i, t2) in twoThetaGrid.enumerated() {
                let dx = t2 - tt
                let gauss = exp(-(dx * dx) / (2 * sigma * sigma))
                let lorentz = 1.0 / (1.0 + (dx / (betaDeg / 2.0)) * (dx / (betaDeg / 2.0)))
                let pv = eta * lorentz + (1 - eta) * gauss
                pattern[i] += Float(pk.relIntensity / 100.0 * pv)
            }
        }
        for i in 0..<pattern.count {
            pattern[i] += Float.random(in: 0.001...0.006)
        }

        let peakCount = peaks.count
        let strongest = peaks.max(by: { $0.relIntensity < $1.relIntensity })
        let d100 = strongest?.dSpacing ?? 0
        let strongestTheta = d100 > 0 ? 2 * asin(lambda / (2 * d100)) * 180 / .pi : 0

        let derived: [String: Double] = [
            "peak_count": Double(peakCount),
            "strongest_peak_2theta": strongestTheta,
            "d100_spacing_ang": d100,
            "crystallite_size_nm": crystalliteSize / 10,
        ]

        var features = pattern
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.xrdPowder.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.xrdPowder.featureCount))

        return TrainingRecord(
            modality: .xrdPowder, sourceID: "synth_bragg",
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "Bragg_PseudoVoigt")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { _ in
            let numPeaks = Int.random(in: 3...20)
            let peaks = (0..<numPeaks).map { _ in
                DiffractionPeak(dSpacing: Double.random(in: 1.0...10.0),
                                relIntensity: Double.random(in: 5...100))
            }
            return synthesizePattern(peaks: peaks)
        }
    }
}
