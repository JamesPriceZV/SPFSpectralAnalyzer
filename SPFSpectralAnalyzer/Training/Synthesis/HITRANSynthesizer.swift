import Foundation

actor HITRANSynthesizer {

    private let wnGrid = stride(from: 400.0, through: 4390.0, by: 10.0).map { $0 }

    func synthesize(lines: [HITRANParser.Line], moleculeID: Int,
                    temperature: Double = 296, pressure: Double = 1.0,
                    pathlength: Double = 1.0) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: wnGrid.count)

        for line in lines {
            // Temperature-scaled intensity (simplified)
            let S_T = line.intensity * exp(-line.lowerEnergy * 1.4388 * (1.0 / temperature - 1.0 / 296.0))
            let gamma_L = line.airHalfWidth * pressure * pow(296.0 / temperature, line.tempExponent)

            // Place on grid with Lorentzian profile
            if let idx = wnGrid.firstIndex(where: { $0 >= line.wavenumber }) {
                let window = min(10, wnGrid.count - idx)
                let startIdx = max(0, idx - 10)
                let endIdx = min(wnGrid.count - 1, idx + window)
                for j in startIdx...endIdx {
                    let dnu = wnGrid[j] - line.wavenumber
                    let lorentz = gamma_L / (.pi * (dnu * dnu + gamma_L * gamma_L))
                    spectrum[j] += Float(S_T * lorentz * pathlength)
                }
            }
        }

        let derived: [String: Double] = [
            "molecule_id": Double(moleculeID),
            "temperature_K": temperature,
            "pressure_atm": pressure,
            "pathlength_m": pathlength,
        ]

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.hitranMolecular.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.hitranMolecular.featureCount))

        return TrainingRecord(
            modality: .hitranMolecular, sourceID: "hitran_mol\(moleculeID)",
            features: features, targets: derived,
            metadata: ["molecule_id": String(moleculeID), "T_K": String(temperature)],
            isComputedLabel: true, computationMethod: "Voigt_HITRAN")
    }
}
