import Foundation

enum BaselineMethod: String, CaseIterable, Identifiable {
    case none = "None"
    case minSubtract = "Min Subtract"
    case poly3 = "Poly Fit (3)"

    var id: String { rawValue }
}

enum NormalizationMethod: String, CaseIterable, Identifiable {
    case none = "None"
    case minMax = "Min-Max"
    case area = "Area"
    case peak = "Peak"

    var id: String { rawValue }
}

struct PeakPoint: Identifiable {
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

        var result = Array(repeating: 0.0, count: y.count)
        var sum = 0.0
        var count = 0

        for i in 0..<y.count {
            sum += y[i]
            count += 1
            if i >= win {
                sum -= y[i - win]
                count -= 1
            }

            if i >= win - 1 {
                let center = i - half
                result[center] = sum / Double(count)
            }
        }

        for i in 0..<half {
            result[i] = result[half]
        }
        for i in (y.count - half)..<y.count {
            result[i] = result[y.count - half - 1]
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

        var a = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        var b = Array(repeating: 0.0, count: n)

        var xPowers = Array(repeating: 0.0, count: 2 * degree + 1)
        for xi in x {
            var value = 1.0
            for k in 0..<xPowers.count {
                xPowers[k] += value
                value *= xi
            }
        }

        for row in 0..<n {
            for col in 0..<n {
                a[row][col] = xPowers[row + col]
            }
        }

        for i in 0..<x.count {
            var value = 1.0
            for row in 0..<n {
                b[row] += y[i] * value
                value *= x[i]
            }
        }

        return solveLinearSystem(a: a, b: b)
    }

    private static func savitzkyGolayCoefficients(window: Int, order: Int) -> [Double] {
        if window < 5 || order < 1 { return [] }
        let half = window / 2
        let cols = order + 1
        let rows = window

        var a = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        for i in 0..<rows {
            let k = Double(i - half)
            var value = 1.0
            for j in 0..<cols {
                a[i][j] = value
                value *= k
            }
        }

        let ata = multiply(transpose(a), a)
        guard let ataInv = invert(ata) else { return [] }
        let at = transpose(a)
        let b = multiply(ataInv, at)

        if b.isEmpty { return [] }
        return b[0]
    }

    private static func transpose(_ m: [[Double]]) -> [[Double]] {
        guard let first = m.first else { return [] }
        var result = Array(repeating: Array(repeating: 0.0, count: m.count), count: first.count)
        for i in 0..<m.count {
            for j in 0..<first.count {
                result[j][i] = m[i][j]
            }
        }
        return result
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        guard let bFirst = b.first else { return [] }
        let rows = a.count
        let cols = bFirst.count
        let inner = b.count

        var result = Array(repeating: Array(repeating: 0.0, count: cols), count: rows)
        for i in 0..<rows {
            for k in 0..<inner {
                let aik = a[i][k]
                if abs(aik) < 1.0e-12 { continue }
                for j in 0..<cols {
                    result[i][j] += aik * b[k][j]
                }
            }
        }
        return result
    }

    private static func invert(_ matrix: [[Double]]) -> [[Double]]? {
        let n = matrix.count
        if n == 0 || matrix[0].count != n { return nil }

        var a = matrix
        var inv = Array(repeating: Array(repeating: 0.0, count: n), count: n)
        for i in 0..<n { inv[i][i] = 1.0 }

        for i in 0..<n {
            var maxRow = i
            var maxVal = abs(a[i][i])
            for row in (i + 1)..<n {
                if abs(a[row][i]) > maxVal {
                    maxVal = abs(a[row][i])
                    maxRow = row
                }
            }

            if maxVal < 1.0e-12 { return nil }
            if maxRow != i {
                a.swapAt(i, maxRow)
                inv.swapAt(i, maxRow)
            }

            let pivot = a[i][i]
            for col in 0..<n {
                a[i][col] /= pivot
                inv[i][col] /= pivot
            }

            for row in 0..<n where row != i {
                let factor = a[row][i]
                if abs(factor) < 1.0e-12 { continue }
                for col in 0..<n {
                    a[row][col] -= factor * a[i][col]
                    inv[row][col] -= factor * inv[i][col]
                }
            }
        }

        return inv
    }

    private static func solveLinearSystem(a: [[Double]], b: [Double]) -> [Double] {
        let n = b.count
        var a = a
        var b = b

        for i in 0..<n {
            var maxRow = i
            var maxVal = abs(a[i][i])
            for row in (i + 1)..<n {
                if abs(a[row][i]) > maxVal {
                    maxVal = abs(a[row][i])
                    maxRow = row
                }
            }

            if maxVal < 1.0e-12 { return [] }
            if maxRow != i {
                a.swapAt(i, maxRow)
                b.swapAt(i, maxRow)
            }

            let pivot = a[i][i]
            for col in i..<n {
                a[i][col] /= pivot
            }
            b[i] /= pivot

            for row in 0..<n where row != i {
                let factor = a[row][i]
                if abs(factor) < 1.0e-12 { continue }
                for col in i..<n {
                    a[row][col] -= factor * a[i][col]
                }
                b[row] -= factor * b[i]
            }
        }

        return b
    }
}
