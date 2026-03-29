import Foundation

/// Stateless parser that extracts ISO 24443 metadata from SPC filenames.
///
/// Filename patterns observed in sample data:
/// - `File_260207_131047.CVS 50 15.2 mg tio2 zno2 combospc.spc`
/// - `File_260217_125906.Neutragena 30 Zno2+Tio2 14.5 mgspc.spc`
/// - `File_260226_143812. 50 commercial formula spc.spc`
/// - `File_260226_154029. 50 commercial formula after incubation spc.spc`
enum FilenameMetadataParser {

    /// Result of parsing a single filename.
    struct ParsedMetadata: Sendable {
        var applicationQuantityMg: Double?
        var formulationType: FormulationType
        var plateType: SubstratePlateType
        var isPostIrradiation: Bool
        var inferredLabelSPF: Double?
    }

    /// Parses metadata from a SPC filename.
    static func parse(filename: String) -> ParsedMetadata {
        let lowered = filename.lowercased()

        let applicationQty = parseApplicationQuantity(from: lowered)
        let formulationType = parseFormulationType(from: lowered)
        let isPostIrradiation = parsePostIrradiation(from: lowered)
        let inferredSPF = parseInferredSPF(from: lowered)

        return ParsedMetadata(
            applicationQuantityMg: applicationQty,
            formulationType: formulationType,
            plateType: .pmma,  // Default: all lab samples use PMMA on SolidSpec-3700i
            isPostIrradiation: isPostIrradiation,
            inferredLabelSPF: inferredSPF
        )
    }

    // MARK: - Application Quantity

    /// Extracts application mass in mg from the filename.
    /// Matches patterns like "14.5 mg", "15.2mg", "14.5 mgspc", "15 mf" (typo for mg).
    private static func parseApplicationQuantity(from lowered: String) -> Double? {
        // Pattern: a decimal number followed by optional whitespace and "m" + [g/f/h] (handling typos)
        // Must not be preceded by a digit (to avoid matching partial numbers)
        let pattern = #"(?<!\d)(\d+\.?\d*)\s*m[gfh]"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: lowered, range: NSRange(lowered.startIndex..., in: lowered)),
              let range = Range(match.range(at: 1), in: lowered) else {
            return nil
        }
        return Double(lowered[range])
    }

    // MARK: - Formulation Type

    /// Infers formulation type from UV filter keywords in the filename.
    private static func parseFormulationType(from lowered: String) -> FormulationType {
        let hasTiO2 = lowered.contains("tio2")
        let hasZnO = lowered.contains("zno")
        let hasCombo = lowered.contains("combo") || lowered.contains("combination")

        if hasCombo {
            // Explicit "combo" label — treat as Combination (Mineral + Organic)
            return .combination
        }
        if hasTiO2 || hasZnO {
            return .mineral
        }
        // No mineral filter keywords — could be organic or unknown
        // Commercial formulas likely contain organic UV filters
        if lowered.contains("commercial formula") {
            return .combination  // Commercial sunscreens typically combine both
        }
        return .unknown
    }

    // MARK: - Post-Irradiation

    /// Detects post-irradiation (post-incubation) state from the filename.
    private static func parsePostIrradiation(from lowered: String) -> Bool {
        lowered.contains("after incubation")
        || lowered.contains("post incubation")
        || lowered.contains("after incub")
    }

    // MARK: - Inferred Label SPF

    /// Attempts to extract a label SPF value from the filename.
    ///
    /// Looks for a number (10–100) that appears after a brand name or at the start
    /// of the descriptor portion (after the timestamp prefix).
    /// Avoids matching the mg value or timestamp digits.
    private static func parseInferredSPF(from lowered: String) -> Double? {
        // Strip the timestamp prefix: "file_YYMMDD_HHMMSS." or similar
        let descriptor: String
        if let dotIndex = lowered.firstIndex(of: ".") {
            descriptor = String(lowered[lowered.index(after: dotIndex)...])
        } else {
            descriptor = lowered
        }

        // Skip blank/control files
        if descriptor.contains("blank") || descriptor.contains("glycerin control") {
            return nil
        }

        // Pattern: look for SPF-like numbers (2-digit, typically 10-100)
        // appearing before "mg" or before filter keywords or "commercial" or "in house"
        // Must be preceded by a space/start or a letter, and NOT be the mg value
        let patterns: [String] = [
            // "Brand NN" pattern: word characters then space then 2-digit number
            #"(?:cvs|cetaphil|cerva|cerave|neutragena|neutrogena)\s+(\d{2,3})\b"#,
            // "NN commercial formula" or "NN in house formula" or "NN (rerun)"
            #"^\s*(\d{2,3})\s+(?:commercial|in\s+house|\(rerun\))"#,
            // Standalone 2-digit number at start of descriptor (e.g., " 24 15.8 mg...")
            // The SPF is the first number, mg value is the second
            #"^\s*(\d{2,3})\s+\d"#,
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: descriptor, range: NSRange(descriptor.startIndex..., in: descriptor)),
                  let range = Range(match.range(at: 1), in: descriptor),
                  let value = Double(descriptor[range]) else {
                continue
            }
            // Sanity check: SPF values are typically 2–100
            if value >= 2 && value <= 100 {
                return value
            }
        }

        return nil
    }
}
