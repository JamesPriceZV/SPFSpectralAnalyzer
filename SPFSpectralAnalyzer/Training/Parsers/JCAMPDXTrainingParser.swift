import Foundation

/// Universal JCAMP-DX parser for the Training subsystem.
/// Detects modality from ##DATA TYPE and returns a ReferenceSpectrum.
nonisolated enum JCAMPDXTrainingParser {

    enum ParseError: Error {
        case invalidEncoding
        case notFound
        case noXYData
    }

    static func detectModality(from headers: [String: String]) -> SpectralModality? {
        let dt = (headers["DATA TYPE"] ?? headers["DATATYPE"] ?? "").uppercased()
        switch dt {
        case let s where s.contains("NEAR INFRARED"):   return .nir
        case let s where s.contains("INFRARED"):        return .ftir
        case let s where s.contains("UV"):              return .uvVis
        case let s where s.contains("RAMAN"):           return .raman
        case let s where s.contains("NMR") && s.contains("1H"):  return .nmrProton
        case let s where s.contains("NMR") && s.contains("13C"): return .nmrCarbon
        case let s where s.contains("NMR"):             return .nmrProton
        case let s where s.contains("MASS"):            return .massSpecEI
        default:                                         return nil
        }
    }

    static func parse(_ text: String, modality: SpectralModality? = nil) throws -> ReferenceSpectrum {
        // Detect NIST "not found" page
        let prefix = String(text.prefix(512))
        if prefix.lowercased().contains("<html") || prefix.lowercased().contains("not found") {
            throw ParseError.notFound
        }

        // Parse headers
        var headers: [String: String] = [:]
        var xValues: [Double] = []
        var yValues: [Double] = []
        var inXYBlock = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Header LDR
            if trimmed.hasPrefix("##") {
                let eq = trimmed.dropFirst(2)
                if let eqIdx = eq.firstIndex(of: "=") {
                    let key = String(eq[eq.startIndex..<eqIdx]).trimmingCharacters(in: .whitespaces).uppercased()
                    let val = String(eq[eq.index(after: eqIdx)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = val
                }
                if trimmed.contains("XYDATA") || trimmed.contains("XYPOINTS") || trimmed.contains("PEAK TABLE") {
                    inXYBlock = true
                }
                if trimmed.hasPrefix("##END") {
                    inXYBlock = false
                }
                continue
            }

            // Parse XY data
            if inXYBlock {
                let parts = trimmed.replacingOccurrences(of: ",", with: " ")
                    .components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                // First number is X, rest are Y values (JCAMP DIFDUP/AFFN)
                guard let x0 = Double(parts.first ?? "") else { continue }
                if parts.count == 2, let y0 = Double(parts[1]) {
                    xValues.append(x0)
                    yValues.append(y0)
                } else if parts.count > 2 {
                    // Multiple Y values with X as first
                    let deltaX = headers["DELTAX"].flatMap(Double.init) ?? 1.0
                    for (j, yStr) in parts.dropFirst().enumerated() {
                        if let yVal = Double(yStr) {
                            xValues.append(x0 + Double(j) * deltaX)
                            yValues.append(yVal)
                        }
                    }
                }
            }
        }

        guard !xValues.isEmpty, xValues.count == yValues.count else {
            throw ParseError.noXYData
        }

        // Apply Y-factor if present
        if let yf = headers["YFACTOR"].flatMap(Double.init), yf != 0 {
            yValues = yValues.map { $0 * yf }
        }

        let detected = modality ?? detectModality(from: headers) ?? .uvVis
        let sourceID = headers["TITLE"] ?? headers["CAS REGISTRY NO"] ?? "unknown"

        return ReferenceSpectrum(
            modality: detected,
            sourceID: sourceID,
            xValues: xValues,
            yValues: yValues,
            metadata: headers.filter { ["TITLE", "CAS REGISTRY NO", "MOLFORM", "XUNITS", "YUNITS"].contains($0.key) }
        )
    }
}
