import Foundation

/// Combined 1H and 13C NMR synthesizer.
actor NMRSynthesizer {

    private let shoolery: [String: Double] = [
        "carbonyl": 1.20, "hydroxyl": 1.74, "chloro": 2.53,
        "bromo": 2.33,    "phenyl": 1.85,   "vinyl": 1.32,
        "carboxyl": 0.97, "amine": 0.53,    "ether": 1.14,
        "nitro": 3.36,    "cyano": 1.05,    "fluorine": 1.55
    ]
    private let gridPPM1H = stride(from: 0.0, through: 11.95, by: 0.05).map { $0 }
    private let gridPPM13C = (0...249).map { Double($0) }
    private let lw = 0.05  // ppm Lorentzian FWHM

    // MARK: - 1H NMR

    func synthesizeProton(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            var s = [Float](repeating: 0, count: gridPPM1H.count)
            addPeak(&s, grid: gridPPM1H, center: 0.90, area: 3.0)
            addPeak(&s, grid: gridPPM1H, center: 1.25, area: Float.random(in: 4...20))

            let groups = Array(shoolery.keys.shuffled().prefix(Int.random(in: 1...3)))
            for g in groups {
                let shift = 1.25 + (shoolery[g] ?? 0)
                addPeak(&s, grid: gridPPM1H, center: shift, area: Float.random(in: 1...3))
            }
            s = s.map { $0 + Float.random(in: 0...0.002) }

            let a = s.map { Double($0) }
            let tot = a.reduce(0, +)
            let aroFrac = tot > 0 ? zip(gridPPM1H, a).filter { $0.0 >= 6.5 && $0.0 <= 8.5 }.map { $0.1 }.reduce(0, +) / tot : 0
            let aldPresent = (zip(gridPPM1H, a).filter { $0.0 > 9.0 }.map { $0.1 }.max() ?? 0) > 0.05 ? 1.0 : 0.0

            let derived: [String: Double] = [
                "aromatic_proton_fraction": aroFrac,
                "aldehyde_present": aldPresent,
            ]

            var features = s
            features.append(Float(aroFrac))
            features.append(Float(aldPresent))
            while features.count < SpectralModality.nmrProton.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.nmrProton.featureCount))

            records.append(TrainingRecord(
                modality: .nmrProton, sourceID: "synth_shoolery",
                features: features, targets: derived, metadata: ["groups": groups.joined(separator: ",")],
                isComputedLabel: true, computationMethod: "Shoolery_Karplus"))
        }
        return records
    }

    // MARK: - 13C NMR

    func synthesizeCarbon(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            var s = [Float](repeating: 0, count: gridPPM13C.count)
            let numPeaks = Int.random(in: 3...15)
            var peakPositions: [Double] = []
            for _ in 0..<numPeaks {
                let region = Int.random(in: 0...3)
                let ppm: Double
                switch region {
                case 0: ppm = Double.random(in: 0...50)     // aliphatic
                case 1: ppm = Double.random(in: 50...90)    // O-bearing
                case 2: ppm = Double.random(in: 110...160)  // aromatic
                default: ppm = Double.random(in: 165...220) // carbonyl
                }
                peakPositions.append(ppm)
                addPeak(&s, grid: gridPPM13C, center: ppm, area: Float.random(in: 0.5...2.0))
            }
            s = s.map { $0 + Float.random(in: 0...0.001) }

            let a = s.map { Double($0) }
            let tot = a.reduce(0, +)
            let aromatic = tot > 0 ? zip(gridPPM13C, a).filter { $0.0 >= 110 && $0.0 <= 160 }.map { $0.1 }.reduce(0, +) / tot : 0
            let carbonyl = peakPositions.filter { $0 >= 165 }.count

            let derived: [String: Double] = [
                "aromatic_fraction": aromatic,
                "carbonyl_count_est": Double(carbonyl),
                "unique_peaks_est": Double(numPeaks),
            ]

            var features = s
            for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
            while features.count < SpectralModality.nmrCarbon.featureCount { features.append(0) }
            features = Array(features.prefix(SpectralModality.nmrCarbon.featureCount))

            records.append(TrainingRecord(
                modality: .nmrCarbon, sourceID: "synth_grant_paul",
                features: features, targets: derived, metadata: [:],
                isComputedLabel: true, computationMethod: "GrantPaul_13C"))
        }
        return records
    }

    // MARK: - Helpers

    private func addPeak(_ s: inout [Float], grid: [Double], center: Double, area: Float) {
        for (i, ppm) in grid.enumerated() {
            let dx = ppm - center
            let lorentz = lw / (2 * .pi) / (dx * dx + (lw / 2) * (lw / 2))
            s[i] += area * Float(lorentz * 0.05)
        }
    }
}
