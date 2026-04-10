import Foundation

enum SpectrumValidation {
    struct ValidationResult {
        let reason: String
        let explanation: String
        let suggestion: String
    }

    static func invalidReason(x: [Double], y: [Double]) -> String? {
        return validate(x: x, y: y)?.reason
    }

    static func validate(x: [Double], y: [Double]) -> ValidationResult? {
        let count = min(x.count, y.count)

        guard count > 0 else {
            return ValidationResult(
                reason: "Empty axis data",
                explanation: "The spectrum contains no data points. The SPC file may be corrupted or the data set was empty during acquisition.",
                suggestion: "Re-export the file from the instrument software, or check if the correct data channel was selected during measurement."
            )
        }

        guard x.count == y.count else {
            return ValidationResult(
                reason: "Mismatched axis lengths (X: \(x.count), Y: \(y.count))",
                explanation: "The wavelength and intensity arrays have different numbers of points, which prevents spectral analysis.",
                suggestion: "This typically indicates a corrupted file. Try re-exporting from the instrument."
            )
        }

        for index in 0..<count {
            let xVal = x[index]
            let yVal = y[index]
            if !xVal.isFinite || !yVal.isFinite {
                let detail = !xVal.isFinite ? "wavelength" : "intensity"
                return ValidationResult(
                    reason: "Non-finite values in data (index \(index))",
                    explanation: "The spectrum contains NaN or infinite \(detail) values at data point \(index). This usually means the detector saturated or the instrument lost signal.",
                    suggestion: "Check sample positioning and instrument settings. If using high-absorbance samples, reduce the slit width or dilute the sample."
                )
            }
        }

        if count < 10 {
            return ValidationResult(
                reason: "Insufficient data points (\(count))",
                explanation: "The spectrum has only \(count) data points, which is too few for reliable spectral analysis or metrics calculation.",
                suggestion: "Increase the scan resolution in the instrument method settings. Typical UV spectra should have at least 100 points across 290–400 nm."
            )
        }

        let allSame = y.dropFirst().allSatisfy { $0 == y[0] }
        if allSame {
            return ValidationResult(
                reason: "Flat spectrum (constant intensity)",
                explanation: "All intensity values are identical (\(String(format: "%.4f", y[0]))). This may indicate a blank measurement, a saturated detector, or a transmission of zero.",
                suggestion: "Run a baseline/blank measurement first, then re-scan the sample. Check that the correct detector and wavelength range are configured."
            )
        }

        return nil
    }
}
