import Foundation

/// Parser for Crystallographic Information File (.cif) format.
/// Extracts unit cell parameters and diffraction peak data from COD / AMCSD files.
nonisolated enum CIFParser {

    struct CrystalData: Sendable {
        let chemicalName: String
        let spaceGroup: String
        let a: Double, b: Double, c: Double           // unit cell lengths (Å)
        let alpha: Double, beta: Double, gamma: Double // unit cell angles (°)
        let cellVolume: Double                          // Å³
        let dSpacings: [Double]                         // Å (from _refln_d_spacing or computed)
        let hklIntensities: [(h: Int, k: Int, l: Int, intensity: Double)]
    }

    enum ParseError: Error { case invalidFormat, missingCellParams }

    static func parse(data: Data) throws -> CrystalData {
        guard let text = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidFormat
        }
        let lines = text.components(separatedBy: .newlines)
        var tags: [String: String] = [:]
        var hklRows: [(h: Int, k: Int, l: Int, intensity: Double)] = []
        var dSpacings: [Double] = []
        var inLoop = false
        var loopHeaders: [String] = []
        var loopDataLines: [[String]] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("loop_") {
                if inLoop { processLoop(headers: loopHeaders, data: loopDataLines, hkl: &hklRows, dSpacings: &dSpacings) }
                inLoop = true; loopHeaders = []; loopDataLines = []
            } else if trimmed.hasPrefix("_") && inLoop && !trimmed.contains(" ") {
                loopHeaders.append(trimmed.lowercased())
            } else if inLoop && !trimmed.isEmpty && !trimmed.hasPrefix("_") && !trimmed.hasPrefix("#") {
                if trimmed.hasPrefix("loop_") || trimmed.hasPrefix("data_") {
                    processLoop(headers: loopHeaders, data: loopDataLines, hkl: &hklRows, dSpacings: &dSpacings)
                    inLoop = trimmed.hasPrefix("loop_")
                    loopHeaders = []; loopDataLines = []
                } else {
                    let tokens = tokenize(trimmed)
                    if !tokens.isEmpty { loopDataLines.append(tokens) }
                }
            } else if trimmed.hasPrefix("_") && !inLoop {
                let parts = trimmed.split(separator: " ", maxSplits: 1)
                if parts.count == 2 {
                    tags[String(parts[0]).lowercased()] = String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                }
            } else if !trimmed.hasPrefix("_") && inLoop && trimmed.isEmpty {
                processLoop(headers: loopHeaders, data: loopDataLines, hkl: &hklRows, dSpacings: &dSpacings)
                inLoop = false
            }
        }
        if inLoop { processLoop(headers: loopHeaders, data: loopDataLines, hkl: &hklRows, dSpacings: &dSpacings) }

        let a = parseNumeric(tags["_cell_length_a"]) ?? 0
        let b = parseNumeric(tags["_cell_length_b"]) ?? 0
        let c = parseNumeric(tags["_cell_length_c"]) ?? 0
        let al = parseNumeric(tags["_cell_angle_alpha"]) ?? 90
        let be = parseNumeric(tags["_cell_angle_beta"]) ?? 90
        let ga = parseNumeric(tags["_cell_angle_gamma"]) ?? 90
        let vol = parseNumeric(tags["_cell_volume"]) ?? (a * b * c)
        let name = tags["_chemical_name_mineral"] ?? tags["_chemical_name_common"] ?? tags["_chemical_formula_sum"] ?? "Unknown"
        let sg = tags["_symmetry_space_group_name_h-m"] ?? tags["_space_group_name_h-m_alt"] ?? "P1"

        return CrystalData(chemicalName: name, spaceGroup: sg,
                           a: a, b: b, c: c, alpha: al, beta: be, gamma: ga,
                           cellVolume: vol, dSpacings: dSpacings, hklIntensities: hklRows)
    }

    private static func processLoop(headers: [String], data: [[String]],
                                     hkl: inout [(h: Int, k: Int, l: Int, intensity: Double)],
                                     dSpacings: inout [Double]) {
        let hIdx = headers.firstIndex(of: "_refln_index_h")
        let kIdx = headers.firstIndex(of: "_refln_index_k")
        let lIdx = headers.firstIndex(of: "_refln_index_l")
        let iIdx = headers.firstIndex(of: "_refln_intensity_meas") ?? headers.firstIndex(of: "_refln_f_squared_meas")
        let dIdx = headers.firstIndex(of: "_refln_d_spacing")

        for row in data {
            if let hi = hIdx, let ki = kIdx, let li = lIdx,
               hi < row.count, ki < row.count, li < row.count,
               let h = Int(row[hi]), let k = Int(row[ki]), let l = Int(row[li]) {
                let intensity = (iIdx != nil && iIdx! < row.count) ? (Double(row[iIdx!]) ?? 0) : 1.0
                hkl.append((h: h, k: k, l: l, intensity: intensity))
            }
            if let di = dIdx, di < row.count, let d = Double(row[di]) {
                dSpacings.append(d)
            }
        }
    }

    private static func tokenize(_ line: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inQuote = false
        var quoteChar: Character = "'"
        for ch in line {
            if inQuote {
                if ch == quoteChar { inQuote = false; tokens.append(current); current = "" }
                else { current.append(ch) }
            } else if ch == "'" || ch == "\"" {
                quoteChar = ch; inQuote = true
            } else if ch == " " || ch == "\t" {
                if !current.isEmpty { tokens.append(current); current = "" }
            } else { current.append(ch) }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    private static func parseNumeric(_ s: String?) -> Double? {
        guard let s else { return nil }
        // CIF numbers may have (uncertainty) suffix like "5.432(3)"
        let cleaned = s.replacingOccurrences(of: "\\(\\d+\\)", with: "", options: .regularExpression)
        return Double(cleaned)
    }
}
