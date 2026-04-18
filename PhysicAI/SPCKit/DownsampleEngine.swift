// DownsampleEngine.swift
// SPCKit
//
// Largest-Triangle-Three-Buckets (LTTB) downsampling.
// Visually lossless: preserves all visually significant extrema.
// Target count = 2x chart pixel width (e.g. 2,732 for a 1,366px iPad display).

import Foundation

actor DownsampleEngine {
    static let shared = DownsampleEngine()
    private init() {}

    /// Returns at most `targetCount` (x, y) pairs from the input arrays.
    /// Preserves first and last points. Returns all points if n <= targetCount.
    nonisolated func lttb(
        xs: [Float], ys: [Float], targetCount: Int
    ) -> [(x: Float, y: Float)] {
        let n = xs.count
        guard n == ys.count else { return [] }
        guard n > targetCount, targetCount > 2 else {
            return zip(xs, ys).map { (x: $0, y: $1) }
        }

        let bucketSize = Double(n - 2) / Double(targetCount - 2)
        var result: [(x: Float, y: Float)] = []
        result.reserveCapacity(targetCount)
        result.append((x: xs[0], y: ys[0]))

        var a = 0    // index of last selected point

        for i in 0..<(targetCount - 2) {
            // Current bucket range
            let bucketStart = min(Int(Double(i + 1) * bucketSize) + 1, n - 1)
            let bucketEnd   = min(Int(Double(i + 2) * bucketSize) + 1, n)

            // Next bucket average (used for triangle area calculation)
            let nextStart = min(Int(Double(i + 2) * bucketSize) + 1, n - 1)
            let nextEnd   = min(Int(Double(i + 3) * bucketSize) + 1, n)
            var avgX: Float = 0, avgY: Float = 0
            let nextCount = nextEnd - nextStart
            guard nextCount > 0 else { break }
            for j in nextStart..<nextEnd { avgX += xs[j]; avgY += ys[j] }
            avgX /= Float(nextCount); avgY /= Float(nextCount)

            // Select point in current bucket with maximum triangle area
            var maxArea: Float = -1
            var selected = bucketStart
            let ax = xs[a], ay = ys[a]
            for j in bucketStart..<bucketEnd {
                let area = abs((ax - avgX) * (ys[j] - ay)
                             - (ax - xs[j]) * (avgY - ay)) * 0.5
                if area > maxArea { maxArea = area; selected = j }
            }
            result.append((x: xs[selected], y: ys[selected]))
            a = selected
        }
        result.append((x: xs[n - 1], y: ys[n - 1]))
        return result
    }
}
