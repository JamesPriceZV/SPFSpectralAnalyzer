import Foundation

nonisolated enum USGSTXTParser {

    struct USGSSpectrum: Sendable {
        let name: String
        let wavelengths: [Double]  // nm
        let reflectances: [Double] // 0-1
    }

    enum ParseError: Error { case insufficientData }

    static func parse(_ text: String) throws -> USGSSpectrum {
        var name = "unknown"
        var wavelengths: [Double] = []
        var reflectances: [Double] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("Name:") {
                name = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                continue
            }
            guard !trimmed.isEmpty, !trimmed.hasPrefix(";"), !trimmed.hasPrefix("#") else { continue }
            let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 2,
               let w = Double(parts[0]),
               let r = Double(parts[1]),
               r > -0.1 {
                wavelengths.append(w * 1000.0) // um -> nm
                reflectances.append(max(r, 0.001))
            }
        }
        guard wavelengths.count > 10 else { throw ParseError.insufficientData }
        return USGSSpectrum(name: name, wavelengths: wavelengths, reflectances: reflectances)
    }
}
