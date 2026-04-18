import Foundation

/// Parser for MoNA (MassBank of North America) bulk JSON exports.
/// Handles both EI-MS and MS/MS spectra from MoNA REST API downloads.
nonisolated enum MoNAJSONParser {

    struct MoNASpectrum: Sendable {
        let id: String
        let compoundName: String
        let compoundClass: String
        let molecularFormula: String
        let precursorMZ: Double?
        let collisionEnergy: Double?
        let peaks: [(mz: Double, intensity: Double)]
        let metadata: [String: String]
    }

    enum ParseError: Error { case invalidJSON, noSpectra }

    /// Parse an array of MoNA spectra from JSON data.
    static func parse(data: Data) throws -> [MoNASpectrum] {
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            // Try single-object format
            if let single = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let s = parseEntry(single) { return [s] }
            }
            throw ParseError.invalidJSON
        }
        let results = jsonArray.compactMap { parseEntry($0) }
        guard !results.isEmpty else { throw ParseError.noSpectra }
        return results
    }

    private static func parseEntry(_ entry: [String: Any]) -> MoNASpectrum? {
        let id = entry["id"] as? String ?? ""
        let spectrum = entry["spectrum"] as? String ?? ""
        let peaks = parseSpectrumString(spectrum)
        guard !peaks.isEmpty else { return nil }

        // Extract compound info
        let compound = (entry["compound"] as? [[String: Any]])?.first ?? [:]
        let names = compound["names"] as? [[String: Any]] ?? []
        let compoundName = (names.first?["name"] as? String) ?? ""
        let classification = compound["classification"] as? [[String: Any]] ?? []
        let compoundClass = classification.first(where: { ($0["name"] as? String) == "class" })?["value"] as? String ?? ""

        // Extract metadata
        var meta: [String: String] = [:]
        let metaData = entry["metaData"] as? [[String: Any]] ?? []
        var formula = ""
        var precursor: Double?
        var ce: Double?
        for m in metaData {
            let name = m["name"] as? String ?? ""
            let value = m["value"]
            let strVal = (value as? String) ?? "\(value ?? "")"
            meta[name] = strVal
            if name == "molecular formula" { formula = strVal }
            if name == "precursor m/z" { precursor = Double(strVal) }
            if name == "collision energy" {
                // May have units like "35 eV"
                let digits = strVal.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
                ce = Double(digits)
            }
        }

        return MoNASpectrum(id: id, compoundName: compoundName, compoundClass: compoundClass,
                            molecularFormula: formula, precursorMZ: precursor, collisionEnergy: ce,
                            peaks: peaks, metadata: meta)
    }

    /// Parse "mz:intensity mz:intensity ..." spectrum string format.
    private static func parseSpectrumString(_ s: String) -> [(mz: Double, intensity: Double)] {
        s.split(separator: " ").compactMap { pair in
            let parts = pair.split(separator: ":")
            guard parts.count == 2, let mz = Double(parts[0]), let i = Double(parts[1]) else { return nil }
            return (mz: mz, intensity: i)
        }
    }
}
