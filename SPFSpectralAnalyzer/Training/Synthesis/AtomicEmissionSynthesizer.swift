import Foundation

actor AtomicEmissionSynthesizer {

    private let grid = (200...899).map { Double($0) }
    private let kB_eV: Double = 8.617e-5

    struct EmissionLine: Sendable {
        let wavelengthNM: Double
        let Aki: Double
        let EkEV: Double
        let gk: Int
    }

    func synthesize(element: String, lines: [EmissionLine],
                    temperature: Double = 5000) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: grid.count)
        let Te = temperature * kB_eV
        let U = lines.map { Double($0.gk) * exp(-$0.EkEV / Te) }.reduce(0, +)
        guard U > 0 else {
            return emptyRecord(element: element)
        }

        for line in lines {
            let intensity = line.Aki * Double(line.gk) * exp(-line.EkEV / Te) / U
            if let idx = grid.firstIndex(where: { $0 >= line.wavelengthNM }) {
                let sigma = 0.3
                let window = min(5, grid.count - idx)
                let startIdx = max(0, idx - 5)
                let endIdx = min(grid.count - 1, idx + window)
                for j in startIdx...endIdx {
                    let d = grid[j] - line.wavelengthNM
                    spectrum[j] += Float(intensity * exp(-(d * d) / (2 * sigma * sigma)))
                }
            }
        }

        for i in 0..<spectrum.count {
            spectrum[i] += Float.random(in: 0...0.001)
        }

        let peakIdx = spectrum.enumerated().max(by: { $0.1 < $1.1 })?.0 ?? 0
        let derived: [String: Double] = [
            "plasma_temperature_est_K": temperature,
            "strongest_line_nm": grid[peakIdx],
            "total_integrated_emission": Double(spectrum.reduce(0, +)),
        ]

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.atomicEmission.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.atomicEmission.featureCount))

        return TrainingRecord(
            modality: .atomicEmission, sourceID: "synth_\(element)",
            features: features, targets: derived, metadata: ["element": element],
            isComputedLabel: true, computationMethod: "Boltzmann_OES")
    }

    private func emptyRecord(element: String) -> TrainingRecord {
        TrainingRecord(
            modality: .atomicEmission, sourceID: "synth_\(element)_empty",
            features: [Float](repeating: 0, count: SpectralModality.atomicEmission.featureCount),
            targets: [:], metadata: ["element": element])
    }
}
