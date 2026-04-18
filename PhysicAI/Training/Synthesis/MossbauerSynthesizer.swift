import Foundation

/// Mossbauer spectroscopy PINN synthesizer.
/// Feature vector (252): transmission at 241 velocity bins + 11 derived features.
/// Primary target: iron_oxidation_state
actor MossbauerSynthesizer {

    static let velGrid: [Double] = stride(from: -12.0, through: 12.0, by: 0.1).map { $0 }

    // MARK: - From Real Spectrum

    func makeRecord(from spec: MossbauerParser.MossbauerSpectrum) -> TrainingRecord {
        let tran = interpolateToGrid(xs: spec.velocity, ys: spec.transmission, grid: Self.velGrid)

        var features = tran.map { Float($0) }
        features += [
            Float(spec.isomerShift),
            Float(spec.quadSplitting),
            Float(spec.magField),
            Float(spec.lineWidth),
            Float(spec.temperature),
            Float(spec.magField > 0.5 ? 6 : spec.quadSplitting > 0.3 ? 2 : 1),
            Float(spec.magField > 0.5 ? 3.0 / 2.0 : 1.0),
            Float(1.0 - (tran.min() ?? 0.9)),
            Float(spec.isomerShift),
            spec.isomerShift < 0.6 ? 1 : 0,
            spec.isomerShift > 0.7 ? 1 : 0
        ]
        while features.count < 252 { features.append(0) }
        features = Array(features.prefix(252))

        let targets: [String: Double] = [
            "iron_oxidation_state": Double(spec.ironOxidationState),
            "is_mm_s": spec.isomerShift,
            "qs_mm_s": spec.quadSplitting,
            "bhf_T": spec.magField,
            "gamma_mm_s": spec.lineWidth,
            "temperature_K": spec.temperature,
        ]

        return TrainingRecord(
            modality: .mossbauer,
            sourceID: "mossbauer_\(spec.compoundName)",
            features: features, targets: targets,
            metadata: ["compound": spec.compoundName, "spin_state": spec.spinState],
            isComputedLabel: spec.ironOxidationState != 0,
            computationMethod: "Mossbauer_Lorentzian_Fit")
    }

    // MARK: - Synthetic Spectrum Generation

    func synthesize(isomerShift: Double, quadSplitting: Double,
                    magField: Double, lineWidth: Double,
                    temperature: Double, abundance: Double = 1.0) -> TrainingRecord {
        var tran = [Double](repeating: 1.0, count: Self.velGrid.count)

        if magField > 0.5 {
            let B_ref = 33.0
            let delta = magField / B_ref * 5.44
            let positions = [
                isomerShift - delta, isomerShift - delta * 0.6,
                isomerShift - delta * 0.2, isomerShift + delta * 0.2,
                isomerShift + delta * 0.6, isomerShift + delta
            ]
            let intensities = [3.0, 2.0, 1.0, 1.0, 2.0, 3.0]
            let total = intensities.reduce(0, +)
            for (pos, rel) in zip(positions, intensities) {
                addLorentzian(&tran, center: pos, area: abundance * rel / total, gamma: lineWidth)
            }
        } else if quadSplitting > 0.05 {
            let v1 = isomerShift - quadSplitting / 2.0
            let v2 = isomerShift + quadSplitting / 2.0
            addLorentzian(&tran, center: v1, area: abundance / 2.0, gamma: lineWidth)
            addLorentzian(&tran, center: v2, area: abundance / 2.0, gamma: lineWidth)
        } else {
            addLorentzian(&tran, center: isomerShift, area: abundance, gamma: lineWidth)
        }

        tran = tran.map { max(0, $0 + Double.random(in: -0.002...0.002)) }

        let oxState: Int
        if isomerShift < 0.55 { oxState = 3 }
        else if isomerShift > 0.70 { oxState = 2 }
        else { oxState = 0 }

        let spec = MossbauerParser.MossbauerSpectrum(
            compoundName: "synth", velocity: Self.velGrid, transmission: tran,
            temperature: temperature, isomerShift: isomerShift,
            quadSplitting: quadSplitting, magField: magField, lineWidth: lineWidth,
            ironOxidationState: oxState, spinState: "unknown")
        return makeRecord(from: spec)
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            let pattern = Int.random(in: 0...2)
            switch pattern {
            case 0:
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.85...1.35),
                    quadSplitting: Double.random(in: 1.0...3.2),
                    magField: 0, lineWidth: Double.random(in: 0.20...0.40),
                    temperature: Double.random(in: 77...300)))
            case 1:
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.25...0.55),
                    quadSplitting: Double.random(in: 0.0...0.9),
                    magField: 0, lineWidth: Double.random(in: 0.20...0.45),
                    temperature: Double.random(in: 77...300)))
            default:
                records.append(synthesize(
                    isomerShift: Double.random(in: 0.30...0.70),
                    quadSplitting: Double.random(in: -0.2...0.5),
                    magField: Double.random(in: 20.0...53.0),
                    lineWidth: Double.random(in: 0.22...0.35),
                    temperature: Double.random(in: 4...300)))
            }
        }
        return records
    }

    // MARK: - Helpers

    private func addLorentzian(_ tran: inout [Double], center: Double,
                                area: Double, gamma: Double) {
        let halfGamma = gamma / 2.0
        for (i, v) in Self.velGrid.enumerated() {
            let dv = v - center
            tran[i] -= area * (halfGamma * halfGamma) / (dv * dv + halfGamma * halfGamma)
        }
    }

    private func interpolateToGrid(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x -> Double in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x <= xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (xs[hi] - xs[lo]) > 1e-12 ? (x - xs[lo]) / (xs[hi] - xs[lo]) : 0
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
