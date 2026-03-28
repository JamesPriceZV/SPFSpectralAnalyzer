import Foundation

enum SpectralYAxisMode: String, CaseIterable, Identifiable, Sendable {
    case absorbance = "Absorbance"
    case transmittance = "Transmittance"

    var id: String { rawValue }
}

// MARK: - SPF Calculation Method

/// The spectral weighting / formula used to compute in-vitro SPF from absorbance data.
enum SPFCalculationMethod: String, CaseIterable, Identifiable, Sendable {
    case colipa       = "COLIPA 2011"
    case iso23675     = "ISO 23675:2024"
    case mansur       = "Mansur (EE×I)"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colipa:   return "COLIPA 2011"
        case .iso23675: return "HDRS"
        case .mansur:   return "Mansur (EE×I)"
        }
    }

    var detailDescription: String {
        switch self {
        case .colipa:
            return "COLIPA in-vitro UVA Method (March 2011). Uses COLIPA erythemal action spectrum and UV source irradiance from 290–400 nm at 1 nm intervals. SPF = Σ(E·S) / Σ(E·S·T)."
        case .iso23675:
            return "HDRS — Hybrid Diffuse Reflectance Spectrophotometry (ISO 23675:2024). Uses CIE standard erythemal action spectrum (ISO/CIE 17166:2019) with mid-summer solar irradiance at 40°N, 290–400 nm. SPF = ∫E(λ)·I(λ)dλ / ∫E(λ)·I(λ)·T(λ)dλ."
        case .mansur:
            return "Mansur et al. (1986) simplified method. Uses pre-calculated EE×I normalized constants at 5 nm intervals from 290–320 nm. SPF = CF × Σ[EE(λ)×I(λ)×Abs(λ)]. Quick screening method."
        }
    }

    /// Wavelength range used by this method.
    var wavelengthRange: String {
        switch self {
        case .colipa:   return "290–400 nm"
        case .iso23675: return "290–400 nm"
        case .mansur:   return "290–320 nm"
        }
    }
}

struct SpectralMetrics: Sendable {
    let criticalWavelength: Double
    let uvaUvbRatio: Double
    let uvbArea: Double
    let uvaArea: Double
    let meanUVBTransmittance: Double
    let meanUVATransmittance: Double
    let peakAbsorbanceWavelength: Double  // λmax in 290–400 nm
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
        let meanUVAT = meanTransmittance(x: xValues, t: transmittance, range: uvaRange)
        let peakWL = peakAbsorbanceWavelength(x: xValues, y: absorbance, range: fullRange)

        return SpectralMetrics(
            criticalWavelength: critical,
            uvaUvbRatio: ratio,
            uvbArea: uvbArea,
            uvaArea: uvaArea,
            meanUVBTransmittance: meanT,
            meanUVATransmittance: meanUVAT,
            peakAbsorbanceWavelength: peakWL
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

    // MARK: - Unified SPF Calculation

    /// Calculates in-vitro SPF using the specified method.
    nonisolated static func spf(
        x: [Double], y: [Double],
        yAxisMode: SpectralYAxisMode,
        method: SPFCalculationMethod,
        correctionCoefficient: Double = 1.0
    ) -> Double? {
        switch method {
        case .colipa:
            return colipaSpf(x: x, y: y, yAxisMode: yAxisMode, correctionCoefficient: correctionCoefficient)
        case .iso23675:
            return iso23675Spf(x: x, y: y, yAxisMode: yAxisMode, correctionCoefficient: correctionCoefficient)
        case .mansur:
            return mansurSpf(x: x, y: y, yAxisMode: yAxisMode, correctionCoefficient: correctionCoefficient)
        }
    }

    @MainActor
    static func spf(
        for spectrum: ShimadzuSpectrum,
        yAxisMode: SpectralYAxisMode,
        method: SPFCalculationMethod,
        correctionCoefficient: Double = 1.0
    ) -> Double? {
        spf(x: spectrum.x, y: spectrum.y, yAxisMode: yAxisMode, method: method, correctionCoefficient: correctionCoefficient)
    }

    // MARK: - ISO 23675:2024 Double Plate Method

    /// Calculates SPF per ISO 23675:2024 using the CIE erythemal action spectrum
    /// (ISO/CIE 17166:2019) and reference solar spectral irradiance (mid-summer,
    /// 40°N latitude, 20° zenith angle, 0.305 cm ozone layer).
    /// SPF = ∫E(λ)·I(λ)dλ / ∫E(λ)·I(λ)·T(λ)dλ  from 290–400 nm.
    nonisolated static func iso23675Spf(
        x: [Double], y: [Double],
        yAxisMode: SpectralYAxisMode,
        correctionCoefficient: Double = 1.0
    ) -> Double? {
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

        // Iterate 290–400 nm at 1 nm using CIE erythemal action spectrum
        for wl in 290...400 {
            let wavelength = Double(wl)
            guard let a = interpolateAbsorbance(at: wavelength, x: xValues, y: corrected) else { return nil }
            let t = max(pow(10.0, -a), 0.0)

            let erythema = CIEErythemalSpectrum.erythema(at: wavelength)
            let solar = CIEErythemalSpectrum.solarIrradiance(at: wavelength)
            let weight = erythema * solar
            numerator += weight
            denominator += weight * t
        }

        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    // MARK: - Mansur Equation

    /// Calculates SPF using the Mansur et al. (1986) equation.
    /// SPF = CF × Σ[EE(λ) × I(λ) × Abs(λ)]  from 290–320 nm at 5 nm intervals.
    /// CF (correction factor) = 10.
    /// EE×I values are pre-calculated normalized constants (Sayre et al., 1979).
    nonisolated static func mansurSpf(
        x: [Double], y: [Double],
        yAxisMode: SpectralYAxisMode,
        correctionCoefficient: Double = 1.0
    ) -> Double? {
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

        // Mansur EE×I normalized constants (Sayre et al., 1979)
        let eeI: [(wavelength: Double, value: Double)] = [
            (290, 0.0150),
            (295, 0.0817),
            (300, 0.2874),
            (305, 0.3278),
            (310, 0.1864),
            (315, 0.0839),
            (320, 0.0180)
        ]

        let correctionFactor = 10.0
        var sum = 0.0

        for entry in eeI {
            guard let a = interpolateAbsorbance(at: entry.wavelength, x: xValues, y: corrected) else { return nil }
            sum += entry.value * a
        }

        return correctionFactor * sum
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

    /// Returns the wavelength (λmax) at which absorbance is highest within the given range.
    private nonisolated static func peakAbsorbanceWavelength(x: [Double], y: [Double], range: (Double, Double)) -> Double {
        let (minX, maxX) = range
        var peakWL = (minX + maxX) / 2.0
        var peakAbs = -Double.greatestFiniteMagnitude
        for i in 0..<x.count {
            if x[i] >= minX && x[i] <= maxX && y[i] > peakAbs {
                peakAbs = y[i]
                peakWL = x[i]
            }
        }
        return peakWL
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
