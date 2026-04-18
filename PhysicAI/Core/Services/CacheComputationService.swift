import Foundation

/// Stateless helpers for computing chart caches and derived spectra.
enum CacheComputationService {

    // MARK: - Average Spectrum

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

    // MARK: - Series Computation

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

    // MARK: - Point Building with LTTB Downsampling

    /// Maximum points to render per spectrum in the chart.
    /// Beyond this, LTTB downsampling is applied to preserve visual fidelity.
    static let defaultDownsampleTarget = 500

    static func buildPoints(
        for spectrum: ShimadzuSpectrum,
        range: ClosedRange<Double>,
        downsampleTarget: Int = defaultDownsampleTarget
    ) -> [SpectrumPoint] {
        let count = min(spectrum.x.count, spectrum.y.count)
        var points: [SpectrumPoint] = []
        points.reserveCapacity(count)

        for index in 0..<count {
            let x = spectrum.x[index]
            let y = spectrum.y[index]
            guard x.isFinite, y.isFinite, range.contains(x) else { continue }
            points.append(SpectrumPoint(id: index, x: x, y: y))
        }

        if points.count > downsampleTarget {
            return lttbDownsample(points, to: downsampleTarget)
        }
        return points
    }

    // MARK: - Stable Cache Keys

    /// Cache key uses spectrum identity + point count + rounded range bounds.
    /// Rounding to 0.1 nm prevents cache thrashing on sub-pixel zoom/pan changes.
    static func pointCacheKey(for spectrum: ShimadzuSpectrum, range: ClosedRange<Double>) -> String {
        let count = min(spectrum.x.count, spectrum.y.count)
        guard count > 0 else { return "\(spectrum.id)::empty" }
        let lo = (range.lowerBound * 10).rounded() / 10
        let hi = (range.upperBound * 10).rounded() / 10
        return "\(spectrum.id)::\(count)::\(lo)::\(hi)"
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

    // MARK: - LTTB (Largest-Triangle-Three-Buckets) Downsampling

    /// Downsamples a sorted array of points to `targetCount` while preserving
    /// visual shape. O(n) time complexity. First and last points are always kept.
    static func lttbDownsample(_ points: [SpectrumPoint], to targetCount: Int) -> [SpectrumPoint] {
        let n = points.count
        guard n > targetCount, targetCount >= 3 else { return points }

        var result: [SpectrumPoint] = []
        result.reserveCapacity(targetCount)

        // Always keep the first point
        result.append(points[0])

        let bucketCount = targetCount - 2
        let bucketSize = Double(n - 2) / Double(bucketCount)

        var prevSelectedIndex = 0

        for bucket in 0..<bucketCount {
            let bucketStart = Int(Double(bucket) * bucketSize) + 1
            let bucketEnd = min(Int(Double(bucket + 1) * bucketSize) + 1, n - 1)

            // Compute average of the *next* bucket for the triangle area calculation
            let nextBucketStart = bucketEnd
            let nextBucketEnd = min(Int(Double(bucket + 2) * bucketSize) + 1, n - 1)
            var avgX = 0.0, avgY = 0.0
            let nextCount = max(nextBucketEnd - nextBucketStart, 1)
            for i in nextBucketStart..<min(nextBucketEnd, n) {
                avgX += points[i].x
                avgY += points[i].y
            }
            avgX /= Double(nextCount)
            avgY /= Double(nextCount)

            // Find the point in this bucket that forms the largest triangle
            // with the previously selected point and the next bucket average
            let prevX = points[prevSelectedIndex].x
            let prevY = points[prevSelectedIndex].y
            var maxArea = -1.0
            var bestIndex = bucketStart

            for i in bucketStart..<bucketEnd {
                let area = abs(
                    (prevX - avgX) * (points[i].y - prevY) -
                    (prevX - points[i].x) * (avgY - prevY)
                )
                if area > maxArea {
                    maxArea = area
                    bestIndex = i
                }
            }

            result.append(points[bestIndex])
            prevSelectedIndex = bestIndex
        }

        // Always keep the last point
        result.append(points[n - 1])
        return result
    }
}
