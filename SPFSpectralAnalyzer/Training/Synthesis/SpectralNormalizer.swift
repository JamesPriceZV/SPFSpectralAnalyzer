import Foundation
import Accelerate

nonisolated enum SpectralNormalizer {

    /// Resample arbitrary (x, y) data onto a uniform grid via linear interpolation.
    static func resampleToGrid(x: [Double], y: [Double], grid: [Double]) -> [Float]? {
        guard x.count >= 2, x.count == y.count else { return nil }
        return grid.map { gx -> Float in
            guard let hi = x.firstIndex(where: { $0 >= gx }), hi > 0 else {
                return gx <= x[0] ? Float(y[0]) : Float(y.last ?? 0)
            }
            let lo = hi - 1
            let t = (gx - x[lo]) / (x[hi] - x[lo])
            return Float(y[lo] + t * (y[hi] - y[lo]))
        }
    }

    /// Max-normalize a float array so that the peak value = 1.
    static func maxNormalize(_ values: inout [Float]) {
        guard let mx = values.max(), mx > 0 else { return }
        var divisor = mx
        let count = Int32(values.count)
        vDSP_vsdiv(values, 1, &divisor, &values, 1, vDSP_Length(count))
    }

    /// Shannon entropy of a spectrum bin distribution.
    static func shannonEntropy(_ values: [Double]) -> Double {
        let total = values.reduce(0, +)
        guard total > 0 else { return 0 }
        var entropy = 0.0
        for v in values where v > 0 {
            let p = v / total
            entropy -= p * log2(p)
        }
        return entropy
    }

    /// Integral of y over x (trapezoidal).
    static func integrate(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count >= 2 else { return 0 }
        var sum = 0.0
        for i in 1..<x.count {
            sum += 0.5 * (y[i] + y[i-1]) * (x[i] - x[i-1])
        }
        return sum
    }
}
