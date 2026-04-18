import Foundation

/// Stateless validation helpers for spectral data.
enum ValidationService {

    static func invalidReason(for spectrum: ShimadzuSpectrum) -> String? {
        SpectrumValidation.invalidReason(x: spectrum.x, y: spectrum.y)
    }

    static func sanitizedSpectrum(_ spectrum: ShimadzuSpectrum) -> ShimadzuSpectrum? {
        let count = min(spectrum.x.count, spectrum.y.count)
        guard count > 0 else { return nil }
        var xVals: [Double] = []
        var yVals: [Double] = []
        xVals.reserveCapacity(count)
        yVals.reserveCapacity(count)
        for index in 0..<count {
            let xVal = spectrum.x[index]
            let yVal = spectrum.y[index]
            guard xVal.isFinite, yVal.isFinite else { continue }
            xVals.append(xVal)
            yVals.append(yVal)
        }
        guard !xVals.isEmpty else { return nil }
        return ShimadzuSpectrum(name: spectrum.name, x: xVals, y: yVals)
    }

    static func isValidSpectrum(_ spectrum: ShimadzuSpectrum) -> Bool {
        invalidReason(for: spectrum) == nil
    }

    static func validateHeader<T>(
        _ header: SDAMainHeader, spectra: [T],
        spectrumName: (T) -> String,
        xProvider: (T) -> [Double],
        yProvider: (T) -> [Double],
        logPrefix: String,
        logSink: ((String) -> Void)? = nil
    ) -> Int {
        var mismatches = 0
        let expectedPoints = Int(header.pointCount)

        func record(_ message: String) {
            Instrumentation.log(
                "SPC validation",
                area: .importParsing,
                level: .warning,
                details: message
            )
            logSink?(message)
        }

        if expectedPoints > 0 {
            for spectrum in spectra {
                let x = xProvider(spectrum)
                let y = yProvider(spectrum)
                let count = min(x.count, y.count)
                if count != expectedPoints {
                    mismatches += 1
                    record("\(logPrefix) spectrum=\(spectrumName(spectrum)) expected=\(expectedPoints) actual=\(count)")
                }
            }
        }

        if header.fileType.isMultiFile, spectra.count <= 1 {
            mismatches += 1
            record("\(logPrefix) spectra=\(spectra.count) flag=multifile")
        } else if !header.fileType.isMultiFile, spectra.count > 1 {
            mismatches += 1
            record("\(logPrefix) spectra=\(spectra.count) flag=single")
        }

        if !header.fileType.hasPerSubfileX, spectra.count > 1 {
            let referenceX = xProvider(spectra[0])
            for spectrum in spectra.dropFirst() {
                let currentX = xProvider(spectrum)
                if !axesMatch(referenceX, currentX) {
                    mismatches += 1
                    record("\(logPrefix) spectrum=\(spectrumName(spectrum)) xAxis=mismatch")
                    break
                }
            }
        }

        return mismatches
    }

    static func validateSPCHeaderConsistency(for parsed: ParsedFileResult) {
        guard let header = parsed.metadata.mainHeader else {
            Instrumentation.log(
                "SPC header missing",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent)"
            )
            return
        }

        let expectedPoints = Int(header.pointCount)
        if expectedPoints > 0 {
            for spectrum in parsed.rawSpectra {
                let count = min(spectrum.x.count, spectrum.y.count)
                if count != expectedPoints {
                    Instrumentation.log(
                        "SPC point count mismatch",
                        area: .importParsing,
                        level: .warning,
                        details: "file=\(parsed.url.lastPathComponent) spectrum=\(spectrum.name) expected=\(expectedPoints) actual=\(count)"
                    )
                }
            }
        }

        if header.fileType.isMultiFile, parsed.rawSpectra.count <= 1 {
            Instrumentation.log(
                "SPC multifile flag mismatch",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent) spectra=\(parsed.rawSpectra.count)"
            )
        } else if !header.fileType.isMultiFile, parsed.rawSpectra.count > 1 {
            Instrumentation.log(
                "SPC single-file flag mismatch",
                area: .importParsing,
                level: .warning,
                details: "file=\(parsed.url.lastPathComponent) spectra=\(parsed.rawSpectra.count)"
            )
        }

        if !header.fileType.hasPerSubfileX, parsed.rawSpectra.count > 1 {
            let firstX = parsed.rawSpectra.first?.x ?? []
            for spectrum in parsed.rawSpectra.dropFirst() {
                if spectrum.x != firstX {
                    Instrumentation.log(
                        "SPC X-axis mismatch",
                        area: .importParsing,
                        level: .warning,
                        details: "file=\(parsed.url.lastPathComponent) spectrum=\(spectrum.name)"
                    )
                    break
                }
            }
        }
    }

    static func axesMatch(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        if lhs.count != rhs.count { return false }
        guard let lhsFirst = lhs.first, let lhsLast = lhs.last,
              let rhsFirst = rhs.first, let rhsLast = rhs.last else {
            return false
        }
        let tolerance = 1e-6
        return abs(lhsFirst - rhsFirst) < tolerance && abs(lhsLast - rhsLast) < tolerance
    }
}
