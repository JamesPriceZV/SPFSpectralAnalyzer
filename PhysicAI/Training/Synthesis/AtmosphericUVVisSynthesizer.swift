import Foundation
import Accelerate

actor AtmosphericUVVisSynthesizer {

    static let lambdaGrid: [Double] = stride(from: 200.0, through: 800.0, by: 1.0).map { $0 }

    func synthesize(from spectrum: ReferenceSpectrum,
                    temperatures: [Double] = [220, 250, 273, 295, 320, 350]) -> [TrainingRecord] {
        guard spectrum.modality == .atmosphericUVVis else { return [] }

        let sigma0 = interpolateToGrid(xs: spectrum.xValues, ys: spectrum.yValues, grid: Self.lambdaGrid)
        guard sigma0.count == Self.lambdaGrid.count else { return [] }

        var records: [TrainingRecord] = []
        for T in temperatures {
            let dT = T - 295.0
            let sigmaT = sigma0.map { s in max(s + s * 0.001 * dT, 1e-30) }
            let peakIdx = sigmaT.indices.max(by: { sigmaT[$0] < sigmaT[$1] }) ?? 0
            let lambdaPeak = Self.lambdaGrid[peakIdx]

            let jValue = zip(Self.lambdaGrid, sigmaT).map { (lam, sig) in
                actinicFlux(nm: lam) * sig
            }.reduce(0, +)

            var features = sigmaT.map { Float($0) }
            features.append(Float(T))
            features.append(Float(lambdaPeak))
            features.append(Float(log10(max(sigmaT.max() ?? 1e-30, 1e-30))))
            features.append(Float(dT))
            while features.count < 651 { features.append(0) }
            features = Array(features.prefix(651))

            let targets: [String: Double] = [
                "log_sigma_peak": log10(max(sigmaT.max() ?? 1e-30, 1e-30)),
                "lambda_peak_nm": lambdaPeak,
                "j_value_clear_sky": jValue
            ]

            records.append(TrainingRecord(
                modality: .atmosphericUVVis, sourceID: spectrum.sourceID,
                features: features, targets: targets,
                metadata: ["temperature_K": String(T), "species": spectrum.sourceID]))
        }
        return records
    }

    private func actinicFlux(nm: Double) -> Double {
        guard nm >= 280 else { return 0 }
        return 1e13 * exp(-0.02 * (nm - 310) * (nm - 310) / (100 * 100))
    }

    private func interpolateToGrid(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2, xs.count == ys.count else { return Array(repeating: 0, count: grid.count) }
        return grid.map { x -> Double in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
