import Foundation
import Accelerate

enum BaselineMethod: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case minSubtract = "Min Subtract"
    case poly3 = "Poly Fit (3)"

    var id: String { rawValue }
}

enum NormalizationMethod: String, CaseIterable, Identifiable, Sendable {
    case none = "None"
    case minMax = "Min-Max"
    case area = "Area"
    case peak = "Peak"

    var id: String { rawValue }
}

struct PeakPoint: Identifiable, Sendable {
    let id: Int
    let x: Double
    let y: Double
}

nonisolated struct SpectraProcessing {
    static func axesMatch(_ a: [Double], _ b: [Double], tolerance: Double = 1.0e-6) -> Bool {
        if a.count != b.count { return false }
        for i in 0..<a.count {
            if abs(a[i] - b[i]) > tolerance { return false }
        }
        return true
    }

    static func resampleLinear(x: [Double], y: [Double], onto newX: [Double]) -> [Double] {
        guard x.count == y.count, x.count > 1 else { return [] }

        var xVals = x
        var yVals = y
        if xVals.count >= 2, xVals[0] > xVals[1] {
            xVals.reverse()
            yVals.reverse()
        }

        var result: [Double] = []
        result.reserveCapacity(newX.count)

        var j = 0
        for target in newX {
            if target <= xVals[0] {
                result.append(yVals[0])
                continue
            }
            if target >= xVals[xVals.count - 1] {
                result.append(yVals[yVals.count - 1])
                continue
            }

            while j < xVals.count - 2 && xVals[j + 1] < target {
                j += 1
            }

            let x0 = xVals[j]
            let x1 = xVals[j + 1]
            let y0 = yVals[j]
            let y1 = yVals[j + 1]

            let t = (target - x0) / (x1 - x0)
            let yInterp = y0 + (y1 - y0) * t
            result.append(yInterp)
        }

        return result
    }

    static func movingAverage(y: [Double], window: Int) -> [Double] {
        guard y.count > 2 else { return y }
        let win = max(3, window | 1)
        let half = win / 2
        let n = y.count

        // vDSP convolution with uniform kernel for sliding window average
        let sumCount = n - win + 1
        guard sumCount > 0 else { return y }
        let kernel = Array(repeating: 1.0 / Double(win), count: win)
        var averaged = Array(repeating: 0.0, count: sumCount)
        vDSP_convD(y, 1, kernel, 1, &averaged, 1, vDSP_Length(sumCount), vDSP_Length(win))

        // Build full result with edge padding
        var result = Array(repeating: 0.0, count: n)
        for i in 0..<sumCount {
            result[i + half] = averaged[i]
        }
        for i in 0..<half {
            result[i] = result[half]
        }
        for i in (n - half)..<n {
            result[i] = result[n - half - 1]
        }
        return result
    }

    static func savitzkyGolay(y: [Double], window: Int, polynomialOrder: Int) -> [Double] {
        guard y.count > 2 else { return y }
        let win = max(5, window | 1)
        let order = min(polynomialOrder, win - 1)
        let half = win / 2

        let coefficients = savitzkyGolayCoefficients(window: win, order: order)
        if coefficients.isEmpty { return y }

        var result = Array(repeating: 0.0, count: y.count)
        for i in 0..<y.count {
            var acc = 0.0
            for j in -half...half {
                let idx = min(max(i + j, 0), y.count - 1)
                let c = coefficients[j + half]
                acc += c * y[idx]
            }
            result[i] = acc
        }
        return result
    }

    static func applyBaseline(y: [Double], x: [Double], method: BaselineMethod) -> [Double] {
        switch method {
        case .none:
            return y
        case .minSubtract:
            guard let minVal = y.min() else { return y }
            return y.map { $0 - minVal }
        case .poly3:
            let coeffs = polynomialFit(x: x, y: y, degree: 3)
            if coeffs.isEmpty { return y }
            return zip(x, y).map { (xi, yi) in
                yi - evaluatePolynomial(coeffs, x: xi)
            }
        }
    }

    static func applyNormalization(y: [Double], x: [Double], method: NormalizationMethod) -> [Double] {
        switch method {
        case .none:
            return y
        case .minMax:
            guard let minVal = y.min(), let maxVal = y.max(), maxVal != minVal else { return y }
            return y.map { ($0 - minVal) / (maxVal - minVal) }
        case .area:
            let area = trapezoidArea(x: x, y: y)
            if area == 0 { return y }
            return y.map { $0 / area }
        case .peak:
            guard let maxVal = y.max(), maxVal != 0 else { return y }
            return y.map { $0 / maxVal }
        }
    }

    static func detectPeaks(x: [Double], y: [Double], minHeight: Double, minDistance: Int) -> [PeakPoint] {
        guard x.count == y.count, x.count > 2 else { return [] }
        let distance = max(1, minDistance)
        var peaks: [PeakPoint] = []

        var lastIndex = -distance
        for i in 1..<(y.count - 1) {
            if i - lastIndex < distance { continue }
            let prev = y[i - 1]
            let curr = y[i]
            let next = y[i + 1]
            if curr >= minHeight && curr > prev && curr > next {
                peaks.append(PeakPoint(id: i, x: x[i], y: curr))
                lastIndex = i
            }
        }
        return peaks
    }

    private static func trapezoidArea(x: [Double], y: [Double]) -> Double {
        guard x.count == y.count, x.count > 1 else { return 0 }
        var area = 0.0
        for i in 1..<x.count {
            let dx = x[i] - x[i - 1]
            area += 0.5 * (y[i] + y[i - 1]) * dx
        }
        return area
    }

    private static func evaluatePolynomial(_ coeffs: [Double], x: Double) -> Double {
        var result = 0.0
        var power = 1.0
        for c in coeffs {
            result += c * power
            power *= x
        }
        return result
    }

    private static func polynomialFit(x: [Double], y: [Double], degree: Int) -> [Double] {
        guard x.count == y.count, x.count > degree else { return [] }
        let n = degree + 1

        // Build normal equations: A * coeffs = b
        // A[row][col] = sum(x^(row+col)), b[row] = sum(y * x^row)
        var xPowers = Array(repeating: 0.0, count: 2 * degree + 1)
        for xi in x {
            var value = 1.0
            for k in 0..<xPowers.count {
                xPowers[k] += value
                value *= xi
            }
        }

        // Column-major flat matrix for LAPACK
        var a = Array(repeating: 0.0, count: n * n)
        for row in 0..<n {
            for col in 0..<n {
                a[col * n + row] = xPowers[row + col]  // column-major
            }
        }

        var b = Array(repeating: 0.0, count: n)
        for i in 0..<x.count {
            var value = 1.0
            for row in 0..<n {
                b[row] += y[i] * value
                value *= x[i]
            }
        }

        // Solve via Accelerate linear algebra
        var N = Int32(n)
        var nrhs: Int32 = 1
        var lda = N
        var ldb = N
        var ipiv = Array(repeating: Int32(0), count: n)
        var info: Int32 = 0
        dgesv_(&N, &nrhs, &a, &lda, &ipiv, &b, &ldb, &info)
        guard info == 0 else { return [] }
        return b
    }

    private static func savitzkyGolayCoefficients(window: Int, order: Int) -> [Double] {
        if window < 5 || order < 1 { return [] }
        let half = window / 2
        let cols = order + 1
        let rows = window

        // Build Vandermonde matrix A (column-major for LAPACK)
        var a = Array(repeating: 0.0, count: rows * cols)
        for i in 0..<rows {
            let k = Double(i - half)
            var value = 1.0
            for j in 0..<cols {
                a[j * rows + i] = value  // column-major
                value *= k
            }
        }

        // Solve least-squares for each unit vector e_0 = [1,0,...,0]
        // to get the smoothing coefficients (first row of pseudoinverse)
        // We solve A * x = e_i for i=0 only (smoothing = 0th derivative)
        var rhs = Array(repeating: 0.0, count: rows)
        rhs[half] = 1.0  // identity column for center point

        var m = Int32(rows)
        var n = Int32(cols)
        var nrhs: Int32 = 1
        var lda = m
        var ldb = m
        var info: Int32 = 0

        // Query workspace size
        var trans = Int8(UInt8(ascii: "N"))
        var workQuery = 0.0
        var lwork: Int32 = -1
        dgels_(&trans, &m, &n, &nrhs, &a, &lda, &rhs, &ldb, &workQuery, &lwork, &info)
        lwork = Int32(workQuery)
        var work = Array(repeating: 0.0, count: Int(lwork))
        dgels_(&trans, &m, &n, &nrhs, &a, &lda, &rhs, &ldb, &work, &lwork, &info)
        guard info == 0 else { return [] }

        // rhs[0..<cols] now holds the least-squares coefficients.
        // Reconstruct smoothing weights: multiply Vandermonde by coefficients.
        // Rebuild Vandermonde (dgels_ overwrites a)
        var vandermonde = Array(repeating: 0.0, count: rows * cols)
        for i in 0..<rows {
            let k = Double(i - half)
            var value = 1.0
            for j in 0..<cols {
                vandermonde[j * rows + i] = value
                value *= k
            }
        }
        let coeffs = Array(rhs[0..<cols])
        var weights = Array(repeating: 0.0, count: rows)
        // weights = Vandermonde * coeffs
        cblas_dgemv(CblasColMajor, CblasNoTrans, Int32(rows), Int32(cols),
                    1.0, vandermonde, Int32(rows), coeffs, 1, 0.0, &weights, 1)
        return weights
    }


}
