import Foundation

enum SpectralYAxisMode: String, CaseIterable, Identifiable, Sendable {
    case absorbance = "Absorbance"
    case transmittance = "Transmittance"

    var id: String { rawValue }
}

struct SpectralMetrics: Sendable {
    let criticalWavelength: Double
    let uvaUvbRatio: Double
    let uvbArea: Double
    let uvaArea: Double
    let meanUVBTransmittance: Double
}

struct SpectralMetricsCalculator {
    @MainActor
    static func metrics(for spectrum: ShimadzuSpectrum, yAxisMode: SpectralYAxisMode) -> SpectralMetrics? {
        metrics(x: spectrum.x, y: spectrum.y, yAxisMode: yAxisMode)
    }

    nonisolated static func metrics(x: [Double], y: [Double], yAxisMode: SpectralYAxisMode) -> SpectralMetrics? {
        let count = min(x.count, y.count)
        guard count > 2 else { return nil }

        var xValues = Array(x.prefix(count))
        var yValues = Array(y.prefix(count))
        if let first = xValues.first, let last = xValues.last, first > last {
            xValues.reverse()
            yValues.reverse()
        }

        let absorbance: [Double]
        let transmittance: [Double]

        switch yAxisMode {
        case .absorbance:
            absorbance = yValues
            transmittance = transmittanceFromAbsorbance(y: yValues)
        case .transmittance:
            transmittance = yValues
            absorbance = absorbanceFromTransmittance(y: yValues)
        }

        let uvbRange = (290.0, 320.0)
        let uvaRange = (320.0, 400.0)
        let fullRange = (290.0, 400.0)

        let uvbArea = integrateAbsorbance(x: xValues, y: absorbance, range: uvbRange)
        let uvaArea = integrateAbsorbance(x: xValues, y: absorbance, range: uvaRange)
        let totalArea = integrateAbsorbance(x: xValues, y: absorbance, range: fullRange)
        let ratio = uvbArea == 0 ? 0 : (uvaArea / uvbArea)
        let critical = criticalWavelength(x: xValues, y: absorbance, totalArea: totalArea)

        let meanT = meanTransmittance(x: xValues, t: transmittance, range: uvbRange)

        return SpectralMetrics(
            criticalWavelength: critical,
            uvaUvbRatio: ratio,
            uvbArea: uvbArea,
            uvaArea: uvaArea,
            meanUVBTransmittance: meanT
        )
    }

    private nonisolated static func transmittanceFromAbsorbance(y: [Double]) -> [Double] {
        return y.map { value in
            pow(10.0, -value)
        }
    }

    private nonisolated static func absorbanceFromTransmittance(y: [Double]) -> [Double] {
        return y.map { value in
            let t = max(value, 1.0e-9)
            return -log10(t)
        }
    }

    private nonisolated static func integrateAbsorbance(x: [Double], y: [Double], range: (Double, Double)) -> Double {
        let (minX, maxX) = range
        var area = 0.0
        for i in 1..<x.count {
            let x0 = x[i - 1]
            let x1 = x[i]
            if x1 < minX || x0 > maxX { continue }

            let xa = max(x0, minX)
            let xb = min(x1, maxX)
            if xb <= xa { continue }

            let y0 = y[i - 1]
            let y1 = y[i]
            let t = (xa - x0) / (x1 - x0)
            let ya = y0 + (y1 - y0) * t
            let t2 = (xb - x0) / (x1 - x0)
            let yb = y0 + (y1 - y0) * t2
            area += 0.5 * (ya + yb) * (xb - xa)
        }
        return area
    }

    private nonisolated static func criticalWavelength(x: [Double], y: [Double], totalArea: Double) -> Double {
        if totalArea <= 0 { return 0 }
        var cumulative = 0.0
        let target = totalArea * 0.9

        for i in 1..<x.count {
            let x0 = x[i - 1]
            let x1 = x[i]
            if x1 < 290 || x0 > 400 { continue }

            let xa = max(x0, 290)
            let xb = min(x1, 400)
            if xb <= xa { continue }

            let y0 = y[i - 1]
            let y1 = y[i]
            let t = (xa - x0) / (x1 - x0)
            let ya = y0 + (y1 - y0) * t
            let t2 = (xb - x0) / (x1 - x0)
            let yb = y0 + (y1 - y0) * t2
            let segment = 0.5 * (ya + yb) * (xb - xa)

            if cumulative + segment >= target {
                let remaining = target - cumulative
                if segment <= 0 { return xb }
                let fraction = remaining / segment
                return xa + (xb - xa) * fraction
            }

            cumulative += segment
        }

        return 0
    }

    @MainActor
    static func colipaSpf(for spectrum: ShimadzuSpectrum, yAxisMode: SpectralYAxisMode, correctionCoefficient: Double = 1.0) -> Double? {
        colipaSpf(x: spectrum.x, y: spectrum.y, yAxisMode: yAxisMode, correctionCoefficient: correctionCoefficient)
    }

    nonisolated static func colipaSpf(x: [Double], y: [Double], yAxisMode: SpectralYAxisMode, correctionCoefficient: Double = 1.0) -> Double? {
        let count = min(x.count, y.count)
        guard count > 2 else { return nil }

        var xValues = Array(x.prefix(count))
        var yValues = Array(y.prefix(count))
        if let first = xValues.first, let last = xValues.last, first > last {
            xValues.reverse()
            yValues.reverse()
        }

        let absorbance: [Double]
        switch yAxisMode {
        case .absorbance:
            absorbance = yValues
        case .transmittance:
            absorbance = absorbanceFromTransmittance(y: yValues)
        }

        let corrected = absorbance.map { $0 * correctionCoefficient }
        var numerator = 0.0
        var denominator = 0.0

        for datum in ColipaSpectralData.data {
            let wl = Double(datum.wavelength)
            guard let a = interpolateAbsorbance(at: wl, x: xValues, y: corrected) else { return nil }
            let t = max(pow(10.0, -a), 0.0)
            let weight = datum.erythema * datum.uvSsr
            numerator += weight
            denominator += weight * t
        }

        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    private nonisolated static func meanTransmittance(x: [Double], t: [Double], range: (Double, Double)) -> Double {
        let (minX, maxX) = range
        var sum = 0.0
        var count = 0
        for i in 0..<x.count {
            if x[i] >= minX && x[i] <= maxX {
                sum += t[i]
                count += 1
            }
        }
        return count == 0 ? 0 : sum / Double(count)
    }

    private nonisolated static func interpolateAbsorbance(at wavelength: Double, x: [Double], y: [Double]) -> Double? {
        guard let first = x.first, let last = x.last, wavelength >= first, wavelength <= last else { return nil }
        for i in 1..<x.count {
            let x0 = x[i - 1]
            let x1 = x[i]
            if wavelength < x0 || wavelength > x1 { continue }
            let y0 = y[i - 1]
            let y1 = y[i]
            let t = (wavelength - x0) / (x1 - x0)
            return y0 + (y1 - y0) * t
        }
        return nil
    }
}
