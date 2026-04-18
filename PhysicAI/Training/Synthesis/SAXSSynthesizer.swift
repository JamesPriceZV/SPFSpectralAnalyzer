import Foundation

actor SAXSSynthesizer {

    static let qGrid: [Double] = {
        let logMin = log10(0.001), logMax = log10(0.5)
        return (0..<200).map { i in pow(10, logMin + Double(i) / 199.0 * (logMax - logMin)) }
    }()

    enum SAXSError: Error { case insufficient }

    func synthesize(from profile: SASBDBParser.SASProfile) throws -> TrainingRecord {
        guard profile.q.count >= 5 else { throw SAXSError.insufficient }

        let logQ = profile.q.map { log10(max($0, 1e-10)) }
        let logI = profile.intensity.map { log10(max($0, 1e-30)) }
        let logQGrid = Self.qGrid.map { log10($0) }

        let logIGrid = interpolate(xs: logQ, ys: logI, grid: logQGrid)

        // Guinier fit
        let guinierRegion = 0..<min(20, logIGrid.count)
        let qs = guinierRegion.map { Self.qGrid[$0] }
        let lIs = guinierRegion.map { pow(10, logIGrid[$0]) }.map { log(max($0, 1e-30)) }
        let q2s = qs.map { $0 * $0 }
        let rg2 = max(linearSlope(xs: q2s, ys: lIs) * -3.0, 0)
        let rgFitted = sqrt(rg2)
        let rgNM = profile.rg_nm > 0 ? profile.rg_nm : rgFitted * 10

        let i0 = pow(10, logIGrid[0])

        var features = logIGrid.map { Float($0) }
        features.append(Float(rgNM))
        features.append(Float(profile.dmax_nm))
        features.append(Float(0))  // porod vol placeholder
        features.append(Float(profile.mw_kda))
        features.append(Float(0))  // porod invariant
        features.append(Float(i0))
        features.append(Float(rgFitted))
        features.append(Float(qs.first ?? 0))
        while features.count < 208 { features.append(0) }
        features = Array(features.prefix(208))

        let targets: [String: Double] = [
            "radius_of_gyration_nm": rgNM,
            "dmax_nm": profile.dmax_nm > 0 ? profile.dmax_nm : rgNM * 3.5,
            "mw_kda": profile.mw_kda
        ]

        return TrainingRecord(
            modality: .saxs, sourceID: profile.accession,
            features: features, targets: targets,
            metadata: ["accession": profile.accession])
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x <= xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }

    private func linearSlope(xs: [Double], ys: [Double]) -> Double {
        let n = Double(xs.count)
        guard n > 1 else { return 0 }
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        let num = zip(xs, ys).map { ($0 - mx) * ($1 - my) }.reduce(0, +)
        let den = xs.map { ($0 - mx) * ($0 - mx) }.reduce(0, +)
        return den > 1e-30 ? num / den : 0
    }
}
