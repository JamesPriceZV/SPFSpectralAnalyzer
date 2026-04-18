import Foundation

/// Parser for nmrshiftdb2 data exports.
/// Handles SDF format with NMR shift assignment blocks.
nonisolated enum NMRShiftDBParser {

    struct NMRShiftRecord: Sendable {
        let compoundName: String
        let molecularFormula: String
        let nucleus: String           // "1H" or "13C"
        let shifts: [ChemicalShift]
        let solvent: String
        let frequency: Double         // MHz
    }

    struct ChemicalShift: Sendable {
        let ppm: Double
        let multiplicity: String      // "s", "d", "t", "q", "m", etc.
        let coupling: Double?         // Hz
        let assignment: String        // atom label
    }

    enum ParseError: Error { case invalidFormat, noShifts }

    /// Parse a single SDF record containing NMR shift data.
    static func parse(data: Data) throws -> [NMRShiftRecord] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidFormat
        }
        // SDF files can contain multiple records separated by "$$$$"
        let records = text.components(separatedBy: "$$$$")
        return records.compactMap { parseRecord($0) }
    }

    private static func parseRecord(_ block: String) -> NMRShiftRecord? {
        let lines = block.components(separatedBy: .newlines)
        guard lines.count > 4 else { return nil }

        let compoundName = lines[0].trimmingCharacters(in: .whitespaces)
        var formula = ""
        var nucleus = "1H"
        var solvent = "CDCl3"
        var frequency = 400.0
        var shifts: [ChemicalShift] = []

        var inShiftBlock = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // SDF property fields
            if trimmed.hasPrefix("> <MOLECULAR_FORMULA>") || trimmed.hasPrefix("> <Molecular Formula>") {
                // Next non-empty line is the value
                continue
            }
            if formula.isEmpty && trimmed.matches(of: /^[A-Z][A-Za-z0-9]+$/).count > 0 {
                formula = trimmed
            }

            // NMR shift data lines
            if trimmed.contains("Spectrum") && trimmed.contains("NMR") {
                nucleus = trimmed.contains("13C") ? "13C" : "1H"
                inShiftBlock = true
                continue
            }
            if trimmed.hasPrefix("> <") { inShiftBlock = false }
            if trimmed.contains("Solvent") { solvent = trimmed.replacingOccurrences(of: "Solvent:", with: "").trimmingCharacters(in: .whitespaces) }
            if trimmed.contains("Frequency") || trimmed.contains("MHz") {
                let digits = trimmed.components(separatedBy: CharacterSet(charactersIn: "0123456789.").inverted).joined()
                if let f = Double(digits), f > 50 { frequency = f }
            }

            // Parse shift lines: "ppm|multiplicity|coupling|assignment" or simple "ppm"
            if inShiftBlock {
                let parts = trimmed.split(separator: "|").map { String($0).trimmingCharacters(in: .whitespaces) }
                if let ppm = Double(parts.first ?? "") {
                    let mult = parts.count > 1 ? parts[1] : ""
                    let coup = parts.count > 2 ? Double(parts[2]) : nil
                    let assign = parts.count > 3 ? parts[3] : ""
                    shifts.append(ChemicalShift(ppm: ppm, multiplicity: mult, coupling: coup, assignment: assign))
                }
                // Also try comma-separated simple shift list
                if parts.count == 1 && trimmed.contains(",") {
                    let vals = trimmed.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    for v in vals {
                        shifts.append(ChemicalShift(ppm: v, multiplicity: "", coupling: nil, assignment: ""))
                    }
                }
            }
        }

        guard !shifts.isEmpty else { return nil }
        return NMRShiftRecord(compoundName: compoundName, molecularFormula: formula,
                              nucleus: nucleus, shifts: shifts, solvent: solvent, frequency: frequency)
    }
}
