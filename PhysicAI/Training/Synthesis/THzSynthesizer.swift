import Foundation

actor THzSynthesizer {

    static let freqGrid: [Double] = stride(from: 0.1, through: 3.0, by: 0.01450).map { $0 }

    func synthesize(sigma0: Double, tau_ps: Double,
                    lorentzPeaks: [(nu0: Double, strength: Double, gamma: Double)],
                    sourceID: String = "synthetic") -> TrainingRecord {
        let tau_s = tau_ps * 1e-12

        var absorption = Self.freqGrid.map { nu_THz -> Double in
            let omega = 2 * .pi * nu_THz * 1e12
            let drudeAlpha = (sigma0 * omega * tau_s) / (1 + omega * omega * tau_s * tau_s)

            var lorentzAlpha = 0.0
            for peak in lorentzPeaks {
                let omega0 = 2 * .pi * peak.nu0 * 1e12
                let gamma  = 2 * .pi * peak.gamma * 1e12
                let denom  = (omega0 * omega0 - omega * omega) * (omega0 * omega0 - omega * omega) + omega * omega * gamma * gamma
                lorentzAlpha += peak.strength * omega * gamma / max(denom, 1e10)
            }
            return max(drudeAlpha + lorentzAlpha * 1e25, 0)
        }
        absorption = absorption.map { $0 + Double.random(in: -0.01...0.01) * ($0 + 0.1) }

        let peak1THz = lorentzPeaks.first?.nu0 ?? 0
        let gamma1 = lorentzPeaks.first?.gamma ?? 0

        var features = absorption.map { Float($0) }
        features.append(Float(sigma0))
        features.append(Float(tau_ps))
        features.append(Float(peak1THz))
        features.append(Float(gamma1))
        features.append(Float(lorentzPeaks.count))
        features.append(Float(absorption.max() ?? 0))
        features.append(Float(absorption.prefix(20).reduce(0, +) / 20.0))
        features.append(Float(absorption.suffix(20).reduce(0, +) / 20.0))
        while features.count < 208 { features.append(0) }
        features = Array(features.prefix(208))

        let targets: [String: Double] = [
            "drude_sigma0": sigma0,
            "drude_tau_ps": tau_ps,
            "lorentz_peak1_THz": peak1THz,
        ]

        return TrainingRecord(
            modality: .terahertz, sourceID: sourceID,
            features: features, targets: targets,
            metadata: ["sigma0": String(sigma0), "tau_ps": String(tau_ps)])
    }

    func synthesizeBatch(count: Int) -> [TrainingRecord] {
        (0..<count).map { i in
            let sigma0 = Double.random(in: 10...1000)
            let tau = Double.random(in: 0.01...2.0)
            let peaks: [(nu0: Double, strength: Double, gamma: Double)] = (0..<Int.random(in: 0...3)).map { _ in
                (nu0: Double.random(in: 0.3...2.8), strength: Double.random(in: 0.1...10), gamma: Double.random(in: 0.05...0.5))
            }
            return synthesize(sigma0: sigma0, tau_ps: tau, lorentzPeaks: peaks, sourceID: "thz_synth_\(i)")
        }
    }
}
