import Foundation

/// Stateless helpers for computing chart caches and derived spectra.
enum CacheComputationService {

    static func computeAverageSpectrum(from spectra: [ShimadzuSpectrum]) -> ShimadzuSpectrum? {
        guard let first = spectra.first else { return nil }
        let count = spectra.count
        if count == 0 { return nil }

        var sum = Array(repeating: 0.0, count: first.y.count)
        for spectrum in spectra {
            let n = min(sum.count, spectrum.y.count)
            for i in 0..<n {
                sum[i] += spectrum.y[i]
            }
        }
        let avg = sum.map { $0 / Double(count) }
        return ShimadzuSpectrum(name: "Average", x: first.x, y: avg)
    }

    static func computeSeriesToPlot(
        from spectra: [ShimadzuSpectrum],
        overlayLimit: Int,
        palette: SpectrumPalette,
        pointProvider: (ShimadzuSpectrum) -> [SpectrumPoint]
    ) -> [SpectrumSeries] {
        let limited = spectra.prefix(overlayLimit)
        return limited.enumerated().map { index, spectrum in
            SpectrumSeries(
                name: spectrum.name,
                points: pointProvider(spectrum),
                color: palette.colors[index % palette.colors.count]
            )
        }
    }

    static func buildPoints(for spectrum: ShimadzuSpectrum, range: ClosedRange<Double>) -> [SpectrumPoint] {
        let count = min(spectrum.x.count, spectrum.y.count)
        var points: [SpectrumPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            let x = spectrum.x[index]
            let y = spectrum.y[index]
            guard x.isFinite, y.isFinite, range.contains(x) else { continue }
            points.append(SpectrumPoint(id: index, x: x, y: y))
        }
        return points
    }

    static func pointCacheKey(for spectrum: ShimadzuSpectrum, range: ClosedRange<Double>) -> String {
        let count = min(spectrum.x.count, spectrum.y.count)
        guard count > 0 else { return "\(spectrum.name)::empty" }
        let firstX = spectrum.x[0]
        let lastX = spectrum.x[count - 1]
        let firstY = spectrum.y[0]
        let lastY = spectrum.y[count - 1]
        return "\(spectrum.name)::\(count)::\(firstX)::\(lastX)::\(firstY)::\(lastY)::\(range.lowerBound)::\(range.upperBound)"
    }

    static func buildPointCache(
        plotSpectra: [ShimadzuSpectrum],
        averageSpectrum: ShimadzuSpectrum?,
        range: ClosedRange<Double>
    ) -> [String: [SpectrumPoint]] {
        var cache: [String: [SpectrumPoint]] = [:]
        for spectrum in plotSpectra {
            let key = pointCacheKey(for: spectrum, range: range)
            cache[key] = buildPoints(for: spectrum, range: range)
        }
        if let avg = averageSpectrum {
            let key = pointCacheKey(for: avg, range: range)
            cache[key] = buildPoints(for: avg, range: range)
        }
        return cache
    }
}
