import Foundation

/// Synthesizer for EI and MS/MS mass spectra.
actor MassSpecSynthesizer {

    private let mzGrid = (1...500).map { Double($0) }

    // MARK: - EI Mass Spec

    func synthesizeEI(molecularWeight: Double, fragments: [(mz: Int, relInt: Double)]) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: 500)
        let basePeak = fragments.max(by: { $0.relInt < $1.relInt })
        for frag in fragments {
            let idx = frag.mz - 1
            guard idx >= 0, idx < 500 else { continue }
            spectrum[idx] = Float(frag.relInt / max(basePeak?.relInt ?? 1, 1e-9))
        }
        // Add noise
        spectrum = spectrum.map { v in v > 0 ? v + Float.random(in: -0.01...0.01) : Float.random(in: 0...0.001) }
        spectrum = spectrum.map { max(0, $0) }

        let mw = Int(molecularWeight)
        let mPlus1Ratio = mw < 500 ? Double(spectrum[safe: mw] ?? 0) / max(Double(spectrum[safe: mw - 1] ?? 0), 1e-9) : 0
        let numPeaks = spectrum.filter { $0 > 0.05 }.count

        var derived: [String: Double] = [
            "molecular_ion_mz": molecularWeight,
            "base_peak_mz": Double(basePeak?.mz ?? 0),
            "m_plus_1_ratio": mPlus1Ratio,
            "num_peaks_above_5pct": Double(numPeaks),
            "mz_77_present": Double(spectrum[safe: 76] ?? 0) > 0.05 ? 1 : 0,
            "mz_91_present": Double(spectrum[safe: 90] ?? 0) > 0.05 ? 1 : 0,
            "mz_43_present": Double(spectrum[safe: 42] ?? 0) > 0.05 ? 1 : 0,
            "molecular_weight": molecularWeight,
        ]

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.massSpecEI.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.massSpecEI.featureCount))

        return TrainingRecord(
            modality: .massSpecEI, sourceID: "synth_ei_mw\(mw)",
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "IsotopePattern_EI")
    }

    // MARK: - MS/MS

    func synthesizeMSMS(precursorMZ: Double, fragments: [(mz: Int, relInt: Double)],
                        collisionEnergy: Double = 30) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: 500)
        let basePeak = fragments.max(by: { $0.relInt < $1.relInt })
        for frag in fragments {
            let idx = frag.mz - 1
            guard idx >= 0, idx < 500 else { continue }
            spectrum[idx] = Float(frag.relInt / max(basePeak?.relInt ?? 1, 1e-9))
        }
        spectrum = spectrum.map { max(0, $0 + Float.random(in: -0.005...0.005)) }

        let neutralLoss18 = spectrum[safe: max(0, Int(precursorMZ) - 19)] ?? 0
        let neutralLoss44 = spectrum[safe: max(0, Int(precursorMZ) - 45)] ?? 0
        let numFrags = spectrum.filter { $0 > 0.05 }.count

        let derived: [String: Double] = [
            "precursor_mz": precursorMZ,
            "collision_energy_ev": collisionEnergy,
            "neutral_loss_18": Double(neutralLoss18),
            "neutral_loss_44": Double(neutralLoss44),
            "num_fragments_above_5pct": Double(numFrags),
        ]

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.massSpecMSMS.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.massSpecMSMS.featureCount))

        return TrainingRecord(
            modality: .massSpecMSMS, sourceID: "synth_msms_prec\(Int(precursorMZ))",
            features: features, targets: derived, metadata: [:],
            isComputedLabel: true, computationMethod: "CID_MSMS")
    }
}

private extension Array where Element == Float {
    nonisolated subscript(safe index: Int) -> Float? {
        indices.contains(index) ? self[index] : nil
    }
}
