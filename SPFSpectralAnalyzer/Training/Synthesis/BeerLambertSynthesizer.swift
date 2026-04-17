import Foundation
import Accelerate

/// Beer-Lambert synthesizer for UV-Vis, FTIR, and NIR modalities.
actor BeerLambertSynthesizer {

    private var uvVisRefs: [String: [Float]] = [:]
    private var ftirRefs: [String: [Float]] = [:]
    private var nirRefs: [String: [Float]] = [:]

    private let uvVisGrid = (290...400).map { Double($0) }
    private let ftirGrid = stride(from: 400.0, through: 4000.0, by: 10.0).map { $0 }
    private let nirGrid = stride(from: 800.0, through: 2498.0, by: 2.0).map { $0 }

    // MARK: - Load references

    func loadUVVisReference(id: String, rawNM: [Double], rawAbs: [Double]) {
        if let g = SpectralNormalizer.resampleToGrid(x: rawNM, y: rawAbs, grid: uvVisGrid) {
            uvVisRefs[id] = g
        }
    }

    func loadFTIRReference(id: String, rawWN: [Double], rawAbs: [Double]) {
        if let g = SpectralNormalizer.resampleToGrid(x: rawWN, y: rawAbs, grid: ftirGrid) {
            ftirRefs[id] = g
        }
    }

    func loadNIRReference(id: String, rawNM: [Double], rawAbs: [Double]) {
        if let g = SpectralNormalizer.resampleToGrid(x: rawNM, y: rawAbs, grid: nirGrid) {
            nirRefs[id] = g
        }
    }

    // MARK: - UV-Vis synthesis

    func synthesizeUVVis(count: Int) -> [TrainingRecord] {
        synthesizeMixtures(refs: uvVisRefs, grid: uvVisGrid, modality: .uvVis, count: count,
                           deriveFeatures: deriveUVVisFeatures)
    }

    private func deriveUVVisFeatures(_ s: [Float], _ grid: [Double]) -> [String: Double] {
        let a = s.map { Double($0) }
        let total = a.reduce(0, +)
        let centroid = total > 0 ? zip(grid, a).map { $0.0 * $0.1 }.reduce(0, +) / total : 0
        return [
            "spectral_centroid_nm": centroid,
            "total_integrated_abs": total,
            "peak_abs": Double(s.max() ?? 0),
            "abs_ratio_290_320": (a.first ?? 0) / max(a.count > 30 ? a[30] : 1, 1e-9),
        ]
    }

    // MARK: - FTIR synthesis

    func synthesizeFTIR(count: Int) -> [TrainingRecord] {
        synthesizeMixtures(refs: ftirRefs, grid: ftirGrid, modality: .ftir, count: count,
                           deriveFeatures: deriveFTIRFeatures)
    }

    private func deriveFTIRFeatures(_ s: [Float], _ grid: [Double]) -> [String: Double] {
        let a = s.map { Double($0) }
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 10
        }
        let total = a.reduce(0, +) * 10
        let carbWin = zip(grid, a).filter { $0.0 >= 1680 && $0.0 <= 1750 }.map { $0.1 }
        let methylWin = zip(grid, a).filter { $0.0 >= 1430 && $0.0 <= 1470 }.map { $0.1 }
        return [
            "carbonyl_index": (methylWin.max() ?? 0) > 1e-6 ? (carbWin.max() ?? 0) / methylWin.max()! : 0,
            "aliphatic_index": integral(2850, 2960) / max(total, 1e-9),
            "aromatic_fraction": integral(1475, 1600) / max(total, 1e-9),
            "hydroxyl_index": integral(2500, 3600) / max(total, 1e-9),
            "total_integrated_abs": total,
            "fingerprint_entropy": SpectralNormalizer.shannonEntropy(
                zip(grid, a).filter { $0.0 >= 600 && $0.0 <= 1500 }.map { $0.1 }
            ),
        ]
    }

    // MARK: - NIR synthesis

    func synthesizeNIR(count: Int) -> [TrainingRecord] {
        synthesizeMixtures(refs: nirRefs, grid: nirGrid, modality: .nir, count: count,
                           deriveFeatures: deriveNIRFeatures)
    }

    private func deriveNIRFeatures(_ s: [Float], _ grid: [Double]) -> [String: Double] {
        let a = s.map { Double($0) }
        func integral(_ lo: Double, _ hi: Double) -> Double {
            zip(grid, a).filter { $0.0 >= lo && $0.0 <= hi }.map { $0.1 }.reduce(0, +) * 2
        }
        let total = integral(800, 2498)
        return [
            "oh_1st_overtone": integral(1400, 1450),
            "ch_1st_overtone": integral(1650, 1750),
            "oh_combination": integral(1900, 2000),
            "protein_band": integral(2050, 2200),
            "moisture_ratio": integral(1400, 1450) / max(total, 1e-9),
            "total_integral": total,
        ]
    }

    // MARK: - Generic mixture synthesis

    private func synthesizeMixtures(
        refs: [String: [Float]], grid: [Double], modality: SpectralModality, count: Int,
        deriveFeatures: ([Float], [Double]) -> [String: Double]
    ) -> [TrainingRecord] {
        let keys = Array(refs.keys)
        guard keys.count >= 1 else { return [] }
        var records: [TrainingRecord] = []
        for _ in 0..<count {
            let nComp = Int.random(in: 1...min(4, keys.count))
            let chosen = (0..<nComp).compactMap { _ in keys.randomElement() }
            let conc = (0..<nComp).map { _ in Float.random(in: 0.001...0.05) }
            var spectrum = [Float](repeating: 0, count: grid.count)
            for (id, c) in zip(chosen, conc) {
                guard let ref = refs[id] else { continue }
                for i in 0..<min(grid.count, ref.count) { spectrum[i] += ref[i] * c }
            }
            spectrum = spectrum.map { max(0, $0 + Float.random(in: -0.001...0.001)) }
            let derived = deriveFeatures(spectrum, grid)
            var features = spectrum
            for (_, v) in derived.sorted(by: { $0.key < $1.key }) {
                features.append(Float(v))
            }
            while features.count < modality.featureCount { features.append(0) }
            features = Array(features.prefix(modality.featureCount))
            records.append(TrainingRecord(
                modality: modality, sourceID: "synth_beer_lambert",
                features: features, targets: derived, metadata: [:],
                isComputedLabel: true, computationMethod: "BeerLambert"))
        }
        return records
    }
}
