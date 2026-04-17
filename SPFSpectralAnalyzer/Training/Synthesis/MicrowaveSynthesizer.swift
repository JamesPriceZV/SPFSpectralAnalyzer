import Foundation

actor MicrowaveSynthesizer {

    static let freqGridGHz: [Double] = {
        let logMin = log10(1.0), logMax = log10(1000.0)
        return (0..<200).map { i in pow(10, logMin + Double(i) / 199.0 * (logMax - logMin)) }
    }()

    enum MWError: Error { case empty }

    func synthesize(from lines: [CDMSParser.CatalogLine],
                    speciesTag: String, T: Double = 300.0) throws -> TrainingRecord {
        guard !lines.isEmpty else { throw MWError.empty }

        var spectrum = Array(repeating: 0.0, count: Self.freqGridGHz.count)
        for line in lines {
            let freqGHz = line.freqMHz / 1000.0
            guard let idx = Self.freqGridGHz.firstIndex(where: { $0 >= freqGHz }) else { continue }
            let intensity = pow(10, line.logIntensity) * exp(-line.lowerEnergyPerCm * 1.4388 / T)
            spectrum[idx] += intensity
        }

        let sortedByInt = lines.sorted { abs($0.logIntensity) > abs($1.logIntensity) }
        let dominantFreqMHz = sortedByInt.first?.freqMHz ?? 0
        let bEstMHz = max(dominantFreqMHz / 4.0, 1000.0)

        let Qval = lines.map { Double($0.upperDegeneracy) * exp(-$0.lowerEnergyPerCm * 1.4388 / T) }.reduce(0, +)

        let maxInt = spectrum.max() ?? 1e-30
        let normSpectrum = spectrum.map { $0 / max(maxInt, 1e-30) }

        var features = normSpectrum.map { Float($0) }
        features.append(Float(bEstMHz))
        features.append(Float(Qval))
        features.append(Float(T))
        features.append(Float(lines.count))
        features.append(Float(dominantFreqMHz / 1000.0))
        features.append(Float(maxInt))
        while features.count < 212 { features.append(0) }
        features = Array(features.prefix(212))

        let targets: [String: Double] = [
            "rotational_constant_B_MHz": bEstMHz,
            "partition_Q_300K": Qval,
        ]

        return TrainingRecord(
            modality: .microwaveRotational, sourceID: "cdms_\(speciesTag)",
            features: features, targets: targets,
            metadata: ["species": speciesTag, "temperature_K": String(T)])
    }
}
