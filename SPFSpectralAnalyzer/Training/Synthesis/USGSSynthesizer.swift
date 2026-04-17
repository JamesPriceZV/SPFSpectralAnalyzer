import Foundation

actor USGSSynthesizer {

    static let grid: [Double] = stride(from: 350.0, through: 2500.0, by: 2.0).map { $0 }

    func synthesize(from parsed: USGSTXTParser.USGSSpectrum) -> TrainingRecord {
        let R = interpolate(xs: parsed.wavelengths, ys: parsed.reflectances, grid: Self.grid)

        // Kubelka-Munk
        let kmValues = R.map { r -> Double in
            let rc = max(r, 0.001)
            return (1 - rc) * (1 - rc) / (2 * rc)
        }

        // Simplified continuum removal
        let Rcr = R.enumerated().map { (i, r) in
            let hull = max(R.max() ?? 1, 0.001)
            return r / hull
        }

        let minIdx = Rcr.indices.min(by: { Rcr[$0] < Rcr[$1] }) ?? 0
        let bandDepth = 1.0 - Rcr[minIdx]
        let bandCentre = Self.grid[minIdx]
        let slope = linearSlope(xs: Self.grid, ys: R)

        var features = R.map { Float($0) }
        features.append(Float(kmValues.reduce(0, +) / Double(kmValues.count)))
        features.append(Float(bandDepth))
        features.append(Float(bandCentre))
        features.append(Float(slope))
        while features.count < 1086 { features.append(0) }
        features = Array(features.prefix(1086))

        let targets: [String: Double] = [
            "band_depth_primary": bandDepth,
            "band_centre_nm": bandCentre,
            "km_k_over_s": kmValues.max() ?? 0,
            "continuum_slope": slope
        ]

        return TrainingRecord(
            modality: .usgsReflectance, sourceID: parsed.name,
            features: features, targets: targets,
            metadata: ["material": parsed.name])
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }

    private func linearSlope(xs: [Double], ys: [Double]) -> Double {
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).map(*).reduce(0, +)
        let sumX2 = xs.map { $0 * $0 }.reduce(0, +)
        return (n * sumXY - sumX * sumY) / max(n * sumX2 - sumX * sumX, 1e-30)
    }
}
