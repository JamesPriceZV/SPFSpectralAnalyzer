import Foundation

struct CalibrationSample: Sendable {
    let labelSPF: Double
    let metrics: SpectralMetrics
}

struct CalibrationResult: Sendable {
    let coefficients: [Double]
    let r2: Double
    let rmse: Double
    let sampleCount: Int
    let featureNames: [String]

    func predict(metrics: SpectralMetrics) -> Double {
        let features = [
            1.0,
            metrics.uvbArea,
            metrics.uvaArea,
            metrics.criticalWavelength,
            metrics.uvaUvbRatio,
            metrics.meanUVBTransmittance
        ]
        let logSpf = zip(coefficients, features).map(*).reduce(0, +)
        return max(exp(logSpf), 0.0)
    }
}

nonisolated struct SPFCalibration {
    static func build(samples: [CalibrationSample]) -> CalibrationResult? {
        guard samples.count >= 2 else { return nil }

        let featureNames = [
            "Intercept",
            "UVB Area",
            "UVA Area",
            "Critical WL",
            "UVA/UVB",
            "Mean UVB T"
        ]

        let x = samples.map { sample in
            [
                1.0,
                sample.metrics.uvbArea,
                sample.metrics.uvaArea,
                sample.metrics.criticalWavelength,
                sample.metrics.uvaUvbRatio,
                sample.metrics.meanUVBTransmittance
            ]
        }
        let y = samples.map { log(max($0.labelSPF, 1.0e-6)) }

        guard let coefficients = solveLeastSquares(x: x, y: y) else { return nil }

        let predictions = x.map { row in
            let logSpf = zip(coefficients, row).map(*).reduce(0, +)
            return exp(logSpf)
        }

        let r2 = rSquared(actual: samples.map { $0.labelSPF }, predicted: predictions)
        let rmse = rootMeanSquaredError(actual: samples.map { $0.labelSPF }, predicted: predictions)

        return CalibrationResult(
            coefficients: coefficients,
            r2: r2,
            rmse: rmse,
            sampleCount: samples.count,
            featureNames: featureNames
        )
    }

    private static func solveLeastSquares(x: [[Double]], y: [Double]) -> [Double]? {
        guard let xT = transpose(x) else { return nil }
        let xTx = multiply(xT, x)
        guard let xTxInv = invert(xTx) else { return nil }
        let xTy = multiply(xT, y)
        let coeffs = multiply(xTxInv, xTy)
        return coeffs
    }

    private static func transpose(_ m: [[Double]]) -> [[Double]]? {
        guard let first = m.first else { return nil }
        var result = Array(repeating: Array(repeating: 0.0, count: m.count), count: first.count)
        for i in 0..<m.count {
            for j in 0..<first.count {
                result[j][i] = m[i][j]
            }
        }
        return result
    }

    private static func multiply(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        let rows = a.count
        let cols = b.first?.count ?? 0
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

    private static func multiply(_ a: [[Double]], _ b: [Double]) -> [Double] {
        let rows = a.count
        let cols = a.first?.count ?? 0
        var result = Array(repeating: 0.0, count: rows)
        for i in 0..<rows {
            var sum = 0.0
            for j in 0..<cols {
                sum += a[i][j] * b[j]
            }
            result[i] = sum
        }
        return result
    }

    private static func invert(_ matrix: [[Double]]) -> [[Double]]? {
        let n = matrix.count
        guard n > 0 && matrix[0].count == n else { return nil }

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

    private static func rSquared(actual: [Double], predicted: [Double]) -> Double {
        guard actual.count == predicted.count, actual.count > 1 else { return 0 }
        let mean = actual.reduce(0, +) / Double(actual.count)
        var ssTot = 0.0
        var ssRes = 0.0
        for i in 0..<actual.count {
            ssTot += pow(actual[i] - mean, 2)
            ssRes += pow(actual[i] - predicted[i], 2)
        }
        return ssTot == 0 ? 0 : (1.0 - ssRes / ssTot)
    }

    private static func rootMeanSquaredError(actual: [Double], predicted: [Double]) -> Double {
        guard actual.count == predicted.count, !actual.isEmpty else { return 0 }
        let mse = zip(actual, predicted).map { pow($0 - $1, 2) }.reduce(0, +) / Double(actual.count)
        return sqrt(mse)
    }
}
