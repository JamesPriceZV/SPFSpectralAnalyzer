import Foundation

actor XPSSynthesizer {

    private let photonEnergy = 1486.6  // Al Ka eV
    private let beGrid = (0..<1200).map { Double($0) }
    private let coreLevelBE: [String: Double] = [
        "C1s": 284.8, "O1s": 532.0, "N1s": 400.0, "Si2p": 99.5,
        "Fe2p": 706.8, "Al2p": 72.8, "Ti2p": 453.8, "S2p": 164.0,
        "F1s": 686.0, "Cl2p": 199.0, "Cu2p": 932.7, "Zn2p": 1021.8
    ]
    private let scofield: [String: Double] = [
        "C1s": 1.00, "O1s": 2.93, "N1s": 1.80, "Si2p": 0.87,
        "Fe2p": 12.4, "Al2p": 0.54, "Ti2p": 7.90, "S2p": 1.68
    ]

    // MARK: - Quantum XPS Properties (Phase 35)

    /// Spin-orbit coupling splits for 2p levels (eV).
    /// The 2p3/2 peak is at the nominal coreLevelBE; the 2p1/2 sits higher by this amount.
    /// Intensity ratio 2p3/2 : 2p1/2 = 2 : 1 (from j-degeneracy).
    private let socSplit2p: [String: Double] = [
        "Si": 0.6, "Al": 0.4, "P": 0.9, "S": 1.2,
        "Cl": 1.6, "K": 2.7, "Ca": 3.5, "Ti": 5.5,
        "V": 6.9, "Cr": 8.1, "Mn": 11.0, "Fe": 13.1,
        "Co": 15.1, "Ni": 17.3, "Cu": 19.9, "Zn": 23.1
    ]

    /// Shake-up satellite parameters: (delta_BE in eV above main peak, relative intensity).
    /// Shake-up satellites arise from simultaneous photoionisation + valence excitation
    /// in transition metals with unpaired d-electrons.
    private let shakeUpParams: [String: (Double, Double)] = [
        "Cu": (9.0, 0.25), "Ni": (6.0, 0.20),
        "Co": (5.5, 0.15), "Fe": (6.0, 0.12),
        "Cr": (3.0, 0.08), "Mn": (4.0, 0.10)
    ]

    /// Wagner Auger parameter alpha-prime (eV) for chemical state identification.
    /// alpha' = KE(Auger) + BE(photoelectron)
    private let wagnerParam: [String: Double] = [
        "Cu": 1851.4, "Ni": 1843.9, "Zn": 2011.0,
        "Si": 1715.4, "Al": 1461.0, "Fe": 721.0
    ]

    /// Bulk plasmon loss energy hbar*omega_p (eV).
    /// Extrinsic losses appear as satellite peaks at BE + n * omega_p (n = 1, 2, ...).
    private let plasmonLoss: [String: Double] = [
        "Al": 15.3, "Si": 16.7, "Na": 5.9, "Mg": 10.6
    ]

    // MARK: - Synthesis

    func synthesizeSurface(elements: [(symbol: String, atomicPct: Double, oxidationState: Int)]) -> TrainingRecord {
        var spectrum = [Float](repeating: 0, count: 1200)
        for (el, pct, oxState) in elements {
            let baseKey = "\(el)1s"
            guard let baseBE = coreLevelBE[baseKey] ?? coreLevelBE["\(el)2p"] else { continue }
            let shift = oxidationShift(element: el, state: oxState)
            let be = baseBE + shift
            let sf = scofield[baseKey] ?? scofield["\(el)2p"] ?? 1.0
            let area = Float(pct * sf / 100.0)
            let sigma = 0.9
            for i in 0..<1200 {
                let dx = beGrid[i] - be
                spectrum[i] += area * Float(exp(-(dx * dx) / (2 * sigma * sigma)) / (sigma * 2.507))
            }
        }

        // Add quantum XPS features (SOC doublets, shake-up satellites, plasmon losses)
        let quantumFeatures = addQuantumXPSFeatures(spectrum: &spectrum, elements: elements)

        // Background noise
        for i in 0..<spectrum.count {
            spectrum[i] += Float.random(in: 0...0.0005)
        }

        let carbonPct = elements.first(where: { $0.symbol == "C" })?.atomicPct ?? 0
        var derived: [String: Double] = [
            "surface_carbon_pct": carbonPct,
            "total_signal_area": Double(spectrum.reduce(0, +)),
        ]

        // Merge quantum features into derived dict
        for (key, value) in quantumFeatures {
            derived[key] = value
        }

        var features = spectrum
        for (_, v) in derived.sorted(by: { $0.key < $1.key }) { features.append(Float(v)) }
        while features.count < SpectralModality.xps.featureCount { features.append(0) }
        features = Array(features.prefix(SpectralModality.xps.featureCount))

        return TrainingRecord(
            modality: .xps, sourceID: "synth_xps",
            features: features, targets: derived,
            metadata: ["elements": elements.map { $0.symbol }.joined(separator: ",")],
            isComputedLabel: true, computationMethod: "Photoelectric_XPS")
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        let elementSets: [[(String, Double, Int)]] = [
            [("C", 70, 0), ("O", 20, 0), ("N", 10, 0)],
            [("C", 50, 0), ("O", 30, 0), ("Si", 20, 4)],
            [("Fe", 40, 2), ("O", 40, 0), ("C", 20, 0)],
            [("Ti", 30, 4), ("O", 50, 0), ("C", 20, 0)],
            [("C", 90, 0), ("O", 5, 0), ("F", 5, 0)],
        ]
        return (0..<count).map { i in
            let base = elementSets[i % elementSets.count]
            let noisy = base.map { (s, p, o) in
                (symbol: s, atomicPct: p + Double.random(in: -5...5), oxidationState: o)
            }
            return synthesizeSurface(elements: noisy)
        }
    }

    // MARK: - Quantum XPS Features (Phase 35)

    /// Adds spin-orbit coupling doublet peaks, shake-up satellite peaks,
    /// and plasmon loss peaks to the spectrum. Returns a dictionary of 60
    /// quantum-derived feature values keyed by descriptive names.
    ///
    /// Physics background:
    /// - SOC: 2p levels split into 2p3/2 (main) and 2p1/2 with intensity ratio 2:1.
    /// - Shake-up: transition-metal 2p photoionisation excites a valence electron
    ///   simultaneously, producing a satellite at higher BE.
    /// - Plasmon: collective valence-electron oscillation in metals creates loss
    ///   features at BE + n * hbar*omega_p (n = 1, 2).
    /// - Wagner alpha-prime: Auger parameter for chemical-state fingerprinting.
    private func addQuantumXPSFeatures(
        spectrum: inout [Float],
        elements: [(symbol: String, atomicPct: Double, oxidationState: Int)]
    ) -> [String: Double] {
        var qf: [String: Double] = [:]
        let sigma = 0.9  // eV FWHM instrument broadening
        var totalShakeUpIntensity = 0.0
        var maxSOCSplit = 0.0
        var heavyElementPresent = 0.0

        for (el, pct, oxState) in elements {
            let sf = scofield["\(el)1s"] ?? scofield["\(el)2p"] ?? 1.0
            let area = pct * sf / 100.0

            // --- Spin-Orbit Coupling doublet peaks ---
            if let split = socSplit2p[el] {
                // The 2p1/2 component has 1/3 of total 2p intensity (ratio 2p3/2:2p1/2 = 2:1)
                let baseBE = coreLevelBE["\(el)2p"] ?? coreLevelBE["\(el)1s"]
                if let be = baseBE {
                    let shift = oxidationShift(element: el, state: oxState)
                    let peakBE = be + shift + split  // 2p1/2 is at higher BE
                    let peakArea = Float(area / 3.0)  // 1/3 of total 2p
                    for i in 0..<1200 {
                        let dx = beGrid[i] - peakBE
                        spectrum[i] += peakArea * Float(exp(-(dx * dx) / (2 * sigma * sigma)) / (sigma * 2.507))
                    }
                    qf["soc_split_\(el)_eV"] = split
                    qf["soc_2p12_area_\(el)"] = Double(peakArea)
                    qf["soc_2p12_position_\(el)"] = peakBE
                }
                if split > maxSOCSplit { maxSOCSplit = split }
                if split > 5.0 { heavyElementPresent = 1.0 }
            }

            // --- Shake-up satellite peaks ---
            if let (deltaE, relInt) = shakeUpParams[el] {
                let baseBE = coreLevelBE["\(el)2p"] ?? coreLevelBE["\(el)1s"]
                if let be = baseBE {
                    let shift = oxidationShift(element: el, state: oxState)
                    let satBE = be + shift + deltaE
                    let satArea = Float(area * relInt)
                    let satSigma = sigma * 1.5  // shake-ups are broader
                    for i in 0..<1200 {
                        let dx = beGrid[i] - satBE
                        spectrum[i] += satArea * Float(exp(-(dx * dx) / (2 * satSigma * satSigma)) / (satSigma * 2.507))
                    }
                    qf["shakeup_\(el)_deltaE"] = deltaE
                    qf["shakeup_\(el)_relint"] = relInt
                    qf["shakeup_\(el)_area"] = Double(satArea)
                    qf["shakeup_\(el)_position"] = satBE
                    totalShakeUpIntensity += Double(satArea)
                }
            }

            // --- Plasmon loss peaks (1st and 2nd order) ---
            if let omegaP = plasmonLoss[el] {
                let baseBE = coreLevelBE["\(el)2p"] ?? coreLevelBE["\(el)1s"]
                if let be = baseBE {
                    let shift = oxidationShift(element: el, state: oxState)
                    for order in 1...2 {
                        let lossBE = be + shift + Double(order) * omegaP
                        // Plasmon loss intensity decreases with order: ~0.15 for 1st, ~0.03 for 2nd
                        let lossRelInt = order == 1 ? 0.15 : 0.03
                        let lossArea = Float(area * lossRelInt)
                        let lossSigma = sigma * (1.0 + 0.3 * Double(order))  // broader for higher order
                        guard lossBE < 1200 else { continue }
                        for i in 0..<1200 {
                            let dx = beGrid[i] - lossBE
                            spectrum[i] += lossArea * Float(exp(-(dx * dx) / (2 * lossSigma * lossSigma)) / (lossSigma * 2.507))
                        }
                        qf["plasmon_\(el)_order\(order)_eV"] = omegaP * Double(order)
                        qf["plasmon_\(el)_order\(order)_area"] = Double(lossArea)
                    }
                    qf["plasmon_\(el)_omega_eV"] = omegaP
                }
            }

            // --- Wagner Auger parameter alpha-prime ---
            if let alphaPrime = wagnerParam[el] {
                qf["wagner_alpha_\(el)"] = alphaPrime
            }
        }

        // Aggregate quantum features
        qf["transition_metal_shakeup"] = totalShakeUpIntensity
        qf["max_soc_split_eV"] = maxSOCSplit
        qf["heavy_element_present"] = heavyElementPresent

        // Pad to exactly 60 quantum features by filling missing slots with zero
        let quantumFeatureCount = 60
        let currentCount = qf.count
        if currentCount < quantumFeatureCount {
            for i in 0..<(quantumFeatureCount - currentCount) {
                qf["qxps_pad_\(i)"] = 0.0
            }
        }

        return qf
    }

    // MARK: - Private Helpers

    private func oxidationShift(element: String, state: Int) -> Double {
        let shifts: [String: [Int: Double]] = [
            "C": [1: 1.5, 2: 3.0, 3: 4.2, 4: 5.0],
            "Fe": [2: 1.5, 3: 3.8],
            "Ti": [2: 1.0, 3: 2.5, 4: 4.0],
            "Si": [4: 3.9]
        ]
        return shifts[element]?[state] ?? 0.0
    }
}
