import Foundation

/// Parser for RRUFF mineral spectral data files.
/// Handles both Raman and XRD plain text exports from rruff.info.
nonisolated enum RRUFFParser {

    struct RRUFFSpectrum: Sendable {
        let rruffID: String           // e.g. "R050058"
        let mineralName: String
        let xValues: [Double]         // Raman shift (cm⁻¹) or 2θ (°)
        let yValues: [Double]         // intensity (arb. units)
        let metadata: [String: String]
    }

    enum ParseError: Error { case emptyData, noDataPoints }

    static func parse(data: Data) throws -> RRUFFSpectrum {
        guard let text = String(data: data, encoding: .utf8), !text.isEmpty else {
            throw ParseError.emptyData
        }
        let lines = text.components(separatedBy: .newlines)
        var rruffID = ""
        var mineralName = ""
        var meta: [String: String] = [:]
        var xVals: [Double] = []
        var yVals: [Double] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("##RRUFFID=") {
                rruffID = String(trimmed.dropFirst(10))
            } else if trimmed.hasPrefix("##NAMES=") {
                mineralName = String(trimmed.dropFirst(8))
            } else if trimmed.hasPrefix("##") && trimmed.contains("=") {
                let parts = trimmed.dropFirst(2).split(separator: "=", maxSplits: 1)
                if parts.count == 2 { meta[String(parts[0])] = String(parts[1]) }
            } else if trimmed.hasPrefix("X=") || trimmed.hasPrefix("Y=") {
                // "X= 147.54, 154.42, ..." or "Y= 7.8, 9.1, ..."
                let isX = trimmed.hasPrefix("X=")
                let valStr = String(trimmed.dropFirst(2))
                let values = valStr.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                if isX { xVals = values } else { yVals = values }
            } else {
                // Two-column numeric format: "147.54\t7.8" or "147.54  7.8"
                let parts = trimmed.split(whereSeparator: { $0 == "\t" || $0 == "," || $0 == " " })
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                if parts.count >= 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                    xVals.append(x)
                    yVals.append(y)
                }
            }
        }

        guard !xVals.isEmpty else { throw ParseError.noDataPoints }
        // Trim yVals to match xVals length
        let count = min(xVals.count, yVals.count)
        return RRUFFSpectrum(rruffID: rruffID, mineralName: mineralName,
                             xValues: Array(xVals.prefix(count)),
                             yValues: Array(yVals.prefix(count)),
                             metadata: meta)
    }
}
