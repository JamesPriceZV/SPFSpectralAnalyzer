import Foundation

/// Parser for HITRAN 160-character fixed-width .par format.
nonisolated enum HITRANParser {

    struct Line: Sendable {
        let moleculeID: Int
        let isotopeID: Int
        let wavenumber: Double
        let intensity: Double
        let einsteinA: Double
        let airHalfWidth: Double
        let selfHalfWidth: Double
        let lowerEnergy: Double
        let tempExponent: Double
        let airPressureShift: Double
    }

    enum ParseError: Error { case invalidEncoding }

    static func parse(data: Data) throws -> [Line] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }
        return text.components(separatedBy: "\n").compactMap { parseLine($0) }
    }

    private static func parseLine(_ raw: String) -> Line? {
        guard raw.count >= 100 else { return nil }
        func substr(_ a: Int, _ b: Int) -> String {
            let si = raw.index(raw.startIndex, offsetBy: a)
            let ei = raw.index(raw.startIndex, offsetBy: min(b, raw.count))
            return String(raw[si..<ei]).trimmingCharacters(in: .whitespaces)
        }
        guard let mol = Int(substr(0, 2)),
              let iso = Int(substr(2, 3)),
              let nu  = Double(substr(3, 15)),
              let s   = Double(substr(15, 25)) else { return nil }
        let a    = Double(substr(25, 35)) ?? 0
        let gAir = Double(substr(35, 40)) ?? 0
        let gSelf = Double(substr(40, 45)) ?? 0
        let eLow = Double(substr(45, 55)) ?? 0
        let n    = Double(substr(55, 59)) ?? 0.75
        let d    = Double(substr(59, 67)) ?? 0
        return Line(moleculeID: mol, isotopeID: iso, wavenumber: nu,
                    intensity: s, einsteinA: a, airHalfWidth: gAir,
                    selfHalfWidth: gSelf, lowerEnergy: eLow,
                    tempExponent: n, airPressureShift: d)
    }
}
