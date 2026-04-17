import Foundation

/// Protein Circular Dichroism Data Bank (pcddb.cryst.bbk.ac.uk) — CD spectra.
/// Species array should contain PCDDB IDs (e.g. "CD0000001", "CD0000025").
actor PCDDBSource: TrainingDataSourceProtocol {

    static let baseURL = "https://pcddb.cryst.bbk.ac.uk/deposit/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for pcddbID in species {
                    do {
                        guard let spectrum = try await self.fetchPCDDBEntry(id: pcddbID) else {
                            continue
                        }
                        continuation.yield(spectrum)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Entry Fetch

    private func fetchPCDDBEntry(id: String) async throws -> ReferenceSpectrum? {
        // PCDDB provides data at /deposit/{ID}/data endpoint
        let dataURLString = Self.baseURL + id + "/data"
        guard let url = URL(string: dataURLString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        guard !text.isEmpty,
              !text.lowercased().contains("not found"),
              !text.lowercased().contains("error") else { return nil }

        // Parse CD spectrum data (wavelength in nm, delta-epsilon in M-1 cm-1)
        let parsed = Self.parseCDData(text, id: id)
        guard !parsed.wavelengths.isEmpty else { return nil }

        // Also fetch metadata for secondary structure information
        var metadata: [String: String] = [
            "source": "PCDDB",
            "pcddb_id": id,
            "point_count": "\(parsed.wavelengths.count)"
        ]

        if let structInfo = try? await self.fetchMetadata(id: id) {
            metadata.merge(structInfo) { _, new in new }
        }

        return ReferenceSpectrum(
            modality: .circularDichroism,
            sourceID: "pcddb_\(id)",
            xValues: parsed.wavelengths,
            yValues: parsed.deltaEpsilon,
            metadata: metadata
        )
    }

    // MARK: - Metadata Fetch

    private func fetchMetadata(id: String) async throws -> [String: String] {
        let metaURLString = Self.baseURL + id + "/"
        guard let url = URL(string: metaURLString) else { return [:] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return [:] }

        let html = String(decoding: data, as: UTF8.self)
        return Self.extractMetadata(html)
    }

    // MARK: - CD Data Parsing

    private struct CDData: Sendable {
        let wavelengths: [Double]   // nm
        let deltaEpsilon: [Double]  // M-1 cm-1
    }

    private nonisolated static func parseCDData(_ text: String, id: String) -> CDData {
        var wavelengths: [Double] = []
        var deltaEpsilon: [Double] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip comments and headers
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.hasPrefix(";"),
                  !trimmed.lowercased().hasPrefix("wavelength") else { continue }

            // Parse whitespace or comma-separated wavelength and delta-epsilon
            let separator = trimmed.contains(",") ? "," : " "
            let parts: [String]
            if separator == "," {
                parts = trimmed.components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                parts = trimmed.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
            }

            guard parts.count >= 2,
                  let wl = Double(parts[0]),
                  let de = Double(parts[1]),
                  wl >= 170.0, wl <= 320.0 else { continue }

            wavelengths.append(wl)
            deltaEpsilon.append(de)
        }

        return CDData(wavelengths: wavelengths, deltaEpsilon: deltaEpsilon)
    }

    // MARK: - Metadata Extraction

    private nonisolated static func extractMetadata(_ html: String) -> [String: String] {
        var info: [String: String] = [:]

        // Extract protein name, secondary structure percentages from HTML
        let lines = html.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.replacingOccurrences(of: "<[^>]+>", with: " ",
                                                     options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let lower = stripped.lowercased()

            if lower.contains("protein") && lower.contains("name") {
                let parts = stripped.components(separatedBy: ":").dropFirst()
                if let name = parts.first?.trimmingCharacters(in: .whitespaces) {
                    info["protein_name"] = name
                }
            } else if lower.contains("alpha") && lower.contains("helix") {
                // Try to extract percentage
                if let pct = Self.extractPercentage(stripped) {
                    info["alpha_helix_pct"] = String(format: "%.1f", pct)
                }
            } else if lower.contains("beta") && lower.contains("sheet") {
                if let pct = Self.extractPercentage(stripped) {
                    info["beta_sheet_pct"] = String(format: "%.1f", pct)
                }
            } else if lower.contains("turn") {
                if let pct = Self.extractPercentage(stripped) {
                    info["turn_pct"] = String(format: "%.1f", pct)
                }
            }
        }

        return info
    }

    private nonisolated static func extractPercentage(_ text: String) -> Double? {
        // Find numeric values that look like percentages
        let parts = text.components(separatedBy: .whitespaces)
        for part in parts {
            let cleaned = part.replacingOccurrences(of: "%", with: "")
            if let val = Double(cleaned), val >= 0, val <= 100 {
                return val
            }
        }
        return nil
    }
}
