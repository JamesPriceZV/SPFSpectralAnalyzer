import Foundation
import Accelerate

actor RamanSynthesizer {

    private var mineralSpectra: [String: [Float]] = [:]
    private let grid = stride(from: 100.0, through: 3590.0, by: 10.0).map { $0 }

    func loadReference(mineral: String, shifts: [Double], intensities: [Double]) {
        let maxI = intensities.max() ?? 1.0
        let norm = intensities.map { $0 / max(maxI, 1e-9) }
        if let g = SpectralNormalizer.resampleToGrid(x: shifts, y: norm, grid: grid) {
            mineralSpectra[mineral] = g
        }
    }

    func synthesize(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        let keys = Array(mineralSpectra.keys)
        guard !keys.isEmpty else { return [] }
        for _ in 0..<count {
            let useMix = Double.random(in: 0...1) < 0.3
            let n = useMix ? 2 : 1
            let chosen = (0..<n).compactMap { _ in keys.randomElement() }
            var spectrum = [Float](repeating: 0, count: grid.count)
            let weights = (0..<n).map { _ in Float.random(in: 0.3...0.7) }
            let wSum = weights.reduce(0, +)
            for (mineral, w) in zip(chosen, weights) {
                if let ref = mineralSpectra[mineral] {
                    for i in 0..<grid.count { spectrum[i] += ref[i] * (w / wSum) }
                }
            }
            // Bose-Einstein thermal correction at 298 K
            let kTcm: Double = 207.2
            for i in 0..<grid.count {
                let nu = grid[i]
                let beCorr = Float(1.0 / (1.0 - exp(-nu / kTcm)))
                spectrum[i] *= beCorr
            }
            // Background + shot noise
            let bgSlope = Float.random(in: 0...0.0003)
            spectrum = spectrum.enumerated().map { i, v in
                max(0, v + bgSlope * Float(i) * 0.001 + Float.random(in: -0.01...0.01))
            }
            let derived = deriveFeatures(spectrum)
            var features = spectrum
            for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
            while features.count < SpectralModality.raman.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.raman.featureCount))
            let label = chosen.first ?? "unknown"
            records.append(TrainingRecord(
                modality: .raman, sourceID: "rruff_synth_\(label)",
                features: features, targets: derived,
                metadata: ["mineral": label],
                isComputedLabel: true, computationMethod: "BoseEinstein_Raman"))
        }
        return records
    }

    private func deriveFeatures(_ s: [Float]) -> [String: Double] {
        let a = s.map { Double($0) }
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 10
        }
        let peakIdx = s.enumerated().max(by: { $0.1 < $1.1 })?.0 ?? 0
        return [
            "d_band": integral(1300, 1400),
            "g_band": integral(1500, 1620),
            "d_g_ratio": integral(1300, 1400) / max(integral(1500, 1620), 1e-9),
            "fingerprint_integral": integral(200, 1200),
            "high_freq_integral": integral(2700, 3200),
            "peak_position_cm1": grid[peakIdx],
            "background_slope": Double(s.last ?? 0) - Double(s.first ?? 0),
        ]
    }
}
