import Foundation

/// Auger Electron Spectroscopy (AES) PINN synthesizer.
/// Feature vector (420): dN/dE derivative spectrum(400) + 18 derived + 2 padding.
/// Primary target: element_atomic_pct_json
actor AESSynthesizer {

    static let keGrid: [Double] = stride(from: 50.0, through: 2045.0, by: 5.0).map { $0 }

    struct AugerPeak: Sendable {
        let symbol: String
        let series: String
        let keNominal: Double
        let rsf: Double
        let bgContrib: Double
    }

    static let peaks: [AugerPeak] = [
        AugerPeak(symbol: "C", series: "KLL", keNominal: 272.0, rsf: 0.070, bgContrib: 1.0),
        AugerPeak(symbol: "O", series: "KVV", keNominal: 510.0, rsf: 0.500, bgContrib: 1.0),
        AugerPeak(symbol: "N", series: "KLL", keNominal: 379.0, rsf: 0.170, bgContrib: 0.8),
        AugerPeak(symbol: "Si", series: "LVV", keNominal: 92.0, rsf: 0.250, bgContrib: 0.8),
        AugerPeak(symbol: "Al", series: "KLL", keNominal: 1396.0, rsf: 0.070, bgContrib: 0.6),
        AugerPeak(symbol: "Fe", series: "LMM", keNominal: 703.0, rsf: 0.220, bgContrib: 0.9),
        AugerPeak(symbol: "Cu", series: "LMM", keNominal: 918.0, rsf: 0.260, bgContrib: 0.9),
        AugerPeak(symbol: "Zn", series: "LMM", keNominal: 992.0, rsf: 0.250, bgContrib: 0.8),
        AugerPeak(symbol: "Na", series: "KLL", keNominal: 990.0, rsf: 0.230, bgContrib: 0.6),
        AugerPeak(symbol: "Mg", series: "KLL", keNominal: 1186.0, rsf: 0.100, bgContrib: 0.7),
        AugerPeak(symbol: "S", series: "LVV", keNominal: 152.0, rsf: 0.540, bgContrib: 0.8),
        AugerPeak(symbol: "Ca", series: "LMM", keNominal: 292.0, rsf: 0.130, bgContrib: 0.7),
        AugerPeak(symbol: "Ti", series: "LMM", keNominal: 418.0, rsf: 0.580, bgContrib: 0.9),
        AugerPeak(symbol: "Cr", series: "LMM", keNominal: 489.0, rsf: 0.350, bgContrib: 0.9),
    ]

    func synthesizeSurface(presentElements: [(symbol: String, atomicPct: Double,
                                               chemicalState: String)],
                            primaryBeamKV: Double = 10.0) -> TrainingRecord {

        var N_E = [Double](repeating: 0.0, count: Self.keGrid.count)

        for (symbol, pct, state) in presentElements {
            guard let peak = Self.peaks.first(where: { $0.symbol == symbol }) else { continue }
            let shift: Double
            switch (symbol, state) {
            case ("C", "graphitic"): shift = 0
            case ("C", "diamond"): shift = -4.0
            case ("C", "oxide"): shift = +3.0
            case ("O", "oxide"): shift = -7.0
            case ("O", "hydroxide"): shift = 0
            case ("Si", "SiO2"): shift = -16.0
            case ("Cu", "Cu2O"): shift = -2.0
            case ("Cu", "CuO"): shift = -2.0
            case ("Fe", "Fe2O3"): shift = +7.0
            case ("Fe", "FeO"): shift = +3.0
            default: shift = 0
            }
            let kePeak = peak.keNominal + shift
            let sigma = 3.0
            let amp = pct / 100.0 * peak.rsf * 100.0
            for (i, ke) in Self.keGrid.enumerated() {
                let dx = ke - kePeak
                N_E[i] += amp * exp(-dx*dx/(2*sigma*sigma))
            }
        }

        let bgAmp = Double.random(in: 5...20)
        for (i, ke) in Self.keGrid.enumerated() {
            N_E[i] += bgAmp * exp(-ke / 300.0)
        }

        var dNdE = [Double](repeating: 0, count: Self.keGrid.count)
        for i in 1..<(Self.keGrid.count - 1) {
            dNdE[i] = (N_E[i+1] - N_E[i-1]) / (Self.keGrid[i+1] - Self.keGrid[i-1])
        }
        dNdE[0] = dNdE[1]; dNdE[Self.keGrid.count-1] = dNdE[Self.keGrid.count-2]

        let maxAbs = dNdE.map { abs($0) }.max() ?? 1.0
        dNdE = dNdE.map { $0 / max(maxAbs, 1e-9) }

        func findPeakNearKE(_ target: Double, window: Double = 30.0) -> Double {
            let candidates = zip(Self.keGrid, dNdE).filter { abs($0.0 - target) < window }
            return candidates.max(by: { abs($0.1) < abs($1.1) })?.0 ?? target
        }

        let cPos  = findPeakNearKE(272.0, window: 20)
        let oPos  = findPeakNearKE(510.0, window: 20)
        let siPos = findPeakNearKE(92.0, window: 20)
        let cuPos = findPeakNearKE(918.0, window: 20)
        let alPos = findPeakNearKE(1396.0, window: 20)
        let fePos = findPeakNearKE(703.0, window: 20)
        let znPos = findPeakNearKE(992.0, window: 20)

        let wAlphaC = cPos + 284.8
        let wAlphaSi = siPos + 99.5
        let wAlphaCu = cuPos + 932.7

        func ptpNear(_ target: Double, window: Double = 20.0) -> Double {
            let seg = zip(Self.keGrid, dNdE).filter { abs($0.0 - target) < window }.map { $0.1 }
            guard let mx = seg.max(), let mn = seg.min() else { return 0 }
            return mx - mn
        }

        let cPTP = ptpNear(272)
        let oPTP = ptpNear(510)

        var features = dNdE.map { Float($0) }
        features += [
            Float(cPos), Float(oPos), Float(siPos), Float(cuPos),
            Float(alPos), Float(fePos), Float(znPos),
            Float(wAlphaC), Float(wAlphaSi), Float(wAlphaCu),
            Float(cPTP), Float(oPTP),
            Float(oPTP > 1e-6 ? cPTP / oPTP : 0),
            Float(dNdE.map { abs($0) }.reduce(0, +)),
            Float(presentElements.count),
            Float(primaryBeamKV),
            Float((N_E.last ?? 0) - (N_E.first ?? 0)),
            0
        ]
        while features.count < 420 { features.append(0) }
        features = Array(features.prefix(420))

        let targets: [String: Double] = [
            "element_atomic_pct_json": presentElements.first?.atomicPct ?? 0,
            "primary_beam_kV": primaryBeamKV,
        ]

        return TrainingRecord(
            modality: .augerElectron,
            sourceID: "aes_synth_\(presentElements.map { $0.symbol }.joined(separator: "_"))",
            features: features, targets: targets,
            metadata: ["elements": presentElements.map { $0.symbol }.joined(separator: ",")],
            isComputedLabel: true,
            computationMethod: "AES_Auger_KE_Wagner")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let surfaces: [[(String, Double, String)]] = [
            [("C", 60, "graphitic"), ("O", 30, "oxide"), ("Si", 10, "SiO2")],
            [("C", 50, "oxide"), ("Fe", 30, "Fe2O3"), ("O", 20, "oxide")],
            [("Al", 70, "oxide"), ("O", 20, "oxide"), ("C", 10, "graphitic")],
            [("Cu", 80, "Cu2O"), ("O", 15, "oxide"), ("C", 5, "oxide")],
            [("Ti", 60, "oxide"), ("O", 30, "oxide"), ("C", 10, "graphitic")],
        ]
        return (0..<count).map { _ in
            let s = surfaces.randomElement()!
            return synthesizeSurface(
                presentElements: s.map { ($0.0, $0.1 + Double.random(in: -5...5), $0.2) })
        }
    }
}
