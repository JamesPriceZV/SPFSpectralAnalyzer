import Foundation

/// GC Retention Index and HPLC Retention Time synthesizer.
actor ChromatographyRetentionSynthesizer {

    // MARK: - GC Kovats RI

    func synthesizeGC(mw: Double, logP: Double, carbonCount: Int,
                      aromaticRings: Int = 0, hbd: Int = 0, hba: Int = 0,
                      kovatsRI: Double) -> TrainingRecord {
        var features = buildDescriptors(mw: mw, logP: logP, carbonCount: carbonCount,
                                        aromaticRings: aromaticRings, hbd: hbd, hba: hba)
        features.append(Float(0))  // column_type: 0 = non-polar
        features.append(Float(150))  // temperature_C
        while features.count < SpectralModality.gcRetention.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.gcRetention.featureCount))

        let targets: [String: Double] = ["kovats_ri": kovatsRI]
        return TrainingRecord(
            modality: .gcRetention, sourceID: "synth_gc_ri\(Int(kovatsRI))",
            features: features, targets: targets, metadata: [:],
            isComputedLabel: true, computationMethod: "Kovats_LSER")
    }

    // MARK: - HPLC RT

    func synthesizeHPLC(mw: Double, logP: Double, carbonCount: Int,
                        aromaticRings: Int = 0, hbd: Int = 0, hba: Int = 0,
                        retentionTimeMin: Double, aqPct: Double = 50,
                        pH: Double = 3.0) -> TrainingRecord {
        var features = buildDescriptors(mw: mw, logP: logP, carbonCount: carbonCount,
                                        aromaticRings: aromaticRings, hbd: hbd, hba: hba)
        features.append(Float(aqPct))
        features.append(Float(0))  // MeCN
        features.append(Float(1))  // gradient
        features.append(Float(150))  // column mm
        features.append(Float(0.3))  // flow
        features.append(Float(pH))
        features.append(Float(10))  // ionic strength
        while features.count < SpectralModality.hplcRetention.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.hplcRetention.featureCount))

        let targets: [String: Double] = ["retention_time_min": retentionTimeMin]
        return TrainingRecord(
            modality: .hplcRetention, sourceID: "synth_hplc_rt\(String(format: "%.1f", retentionTimeMin))",
            features: features, targets: targets, metadata: [:],
            isComputedLabel: true, computationMethod: "MartinSynge_LFER")
    }

    // MARK: - Batch

    func synthesizeGCBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { _ in
            let c = Int.random(in: 5...25)
            let mw = Double(c * 14 + 2)
            let logP = Double.random(in: 0...8)
            let ri = 100.0 * Double(c) + Double.random(in: -50...50)
            return synthesizeGC(mw: mw, logP: logP, carbonCount: c, kovatsRI: ri)
        }
    }

    func synthesizeHPLCBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { _ in
            let mw = Double.random(in: 100...800)
            let logP = Double.random(in: -2...6)
            let rt = Double.random(in: 0.5...30)
            return synthesizeHPLC(mw: mw, logP: logP, carbonCount: Int.random(in: 3...30),
                                  retentionTimeMin: rt)
        }
    }

    // MARK: - Descriptor builder

    private func buildDescriptors(mw: Double, logP: Double, carbonCount: Int,
                                  aromaticRings: Int, hbd: Int, hba: Int) -> [Float] {
        var d: [Float] = []
        d.append(Float(mw))
        d.append(Float(logP))
        d.append(Float(carbonCount))
        d.append(Float(aromaticRings))
        d.append(Float(hbd))
        d.append(Float(hba))
        d.append(Float.random(in: 0...5))   // rotatable bonds
        d.append(Float.random(in: 0...1))   // sp3 fraction
        d.append(Float.random(in: 20...200)) // molar refractivity
        d.append(Float.random(in: 0...200))  // TPSA
        // Pad with random molecular fingerprint bits
        for _ in 0..<40 { d.append(Float.random(in: 0...1).rounded()) }
        return d
    }
}
