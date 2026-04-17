import Foundation

actor FluorescenceSynthesizer {

    private let emGrid = stride(from: 300.0, through: 898.0, by: 2.0).map { $0 }

    func synthesize(excitationNM: Double, peakEmissionNM: Double,
                    quantumYield: Double, fwhm: Double = 30,
                    sourceID: String = "synthetic") -> TrainingRecord {
        let stokesShift = (1.0 / excitationNM - 1.0 / peakEmissionNM) * 1e7
        let sigma = fwhm / 2.355
        var spectrum = emGrid.map { lam -> Float in
            let dx = lam - peakEmissionNM
            return Float(exp(-(dx * dx) / (2 * sigma * sigma)))
        }
        // Asymmetric red tail
        for i in 0..<spectrum.count {
            if emGrid[i] > peakEmissionNM {
                spectrum[i] *= Float(exp(-0.002 * (emGrid[i] - peakEmissionNM)))
            }
        }
        SpectralNormalizer.maxNormalize(&spectrum)
        spectrum = spectrum.map { $0 + Float.random(in: -0.005...0.005) }
        spectrum = spectrum.map { max(0, $0) }

        let halfMax = spectrum.max().map { $0 / 2 } ?? 0
        let leftHalf = emGrid.first(where: { emGrid.firstIndex(of: $0).map { spectrum[$0] >= halfMax } ?? false }) ?? peakEmissionNM
        let rightHalf = emGrid.last(where: { emGrid.firstIndex(of: $0).map { spectrum[$0] >= halfMax } ?? false }) ?? peakEmissionNM
        let asymmetry = (rightHalf - peakEmissionNM) > 0 ? (peakEmissionNM - leftHalf) / (rightHalf - peakEmissionNM) : 1.0
        let totalInt = spectrum.reduce(0, +)
        let redTail = spectrum.enumerated().filter { emGrid[$0.offset] > peakEmissionNM + 30 }.map { $0.element }.reduce(0, +)

        let derived: [String: Double] = [
            "quantum_yield": quantumYield,
            "peak_emission_nm": peakEmissionNM,
            "stokes_shift_cm": stokesShift,
            "emission_fwhm_nm": fwhm,
            "emission_asymmetry": asymmetry,
            "red_tail_fraction": totalInt > 0 ? Double(redTail / totalInt) : 0,
        ]

        var features = spectrum
        features.append(Float(excitationNM))
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.fluorescence.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.fluorescence.featureCount))

        return TrainingRecord(
            modality: .fluorescence, sourceID: sourceID,
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "Jablonski_Fluorescence")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { i in
            let ex = Double.random(in: 300...550)
            let em = ex + Double.random(in: 15...150)
            let qy = Double.random(in: 0.01...0.95)
            let fw = Double.random(in: 15...80)
            return synthesize(excitationNM: ex, peakEmissionNM: em, quantumYield: qy, fwhm: fw,
                              sourceID: "synth_fluor_\(i)")
        }
    }
}
