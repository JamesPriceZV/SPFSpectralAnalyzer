import Foundation

actor OpticalConstantsSynthesizer {

    static let gridNM: [Double] = stride(from: 200.0, through: 1100.0, by: 4.5).map { $0 }

    func synthesize(from data: RefractiveIndexYAMLParser.OpticalData) -> TrainingRecord {
        let gridUM = Self.gridNM.map { $0 / 1000.0 }
        let nGrid = interpolate(xs: data.wavelengths_um, ys: data.n, grid: gridUM)
        let kGrid = interpolate(xs: data.wavelengths_um, ys: data.k, grid: gridUM)

        let idx589 = Self.gridNM.firstIndex(where: { $0 >= 589.0 }) ?? 86
        let nD = nGrid[min(idx589, nGrid.count - 1)]
        let kD = kGrid[min(idx589, kGrid.count - 1)]

        let idxF = Self.gridNM.firstIndex(where: { $0 >= 486.0 }) ?? 0
        let idxC = Self.gridNM.firstIndex(where: { $0 >= 656.0 }) ?? 0
        let nF = nGrid[min(idxF, nGrid.count - 1)]
        let nC = nGrid[min(idxC, nGrid.count - 1)]
        let abbe = abs(nF - nC) > 1e-6 ? (nD - 1.0) / abs(nF - nC) : 0
        let b1 = nD * nD - 1.0

        var features = nGrid.map { Float($0) } + kGrid.map { Float($0) }
        features.append(Float(nD))
        features.append(Float(abbe))
        features.append(Float(kD))
        while features.count < 403 { features.append(0) }
        features = Array(features.prefix(403))

        let targets: [String: Double] = [
            "n_at_589nm": nD,
            "k_at_589nm": kD,
            "abbe_number": abbe,
            "sellmeier_B1": b1,
        ]

        return TrainingRecord(
            modality: .opticalConstants, sourceID: data.material,
            features: features, targets: targets,
            metadata: ["material": data.material])
    }

    private func interpolate(xs: [Double], ys: [Double], grid: [Double]) -> [Double] {
        guard xs.count >= 2 else { return Array(repeating: 1.5, count: grid.count) }
        return grid.map { x in
            guard let hi = xs.firstIndex(where: { $0 >= x }), hi > 0 else {
                return x < xs[0] ? ys[0] : (ys.last ?? 0)
            }
            let lo = hi - 1
            let t = (x - xs[lo]) / (xs[hi] - xs[lo])
            return ys[lo] + t * (ys[hi] - ys[lo])
        }
    }
}
