import Foundation

/// NIST X-ray Photoelectron Spectroscopy Database SRD 20.
/// Species array should contain element names or compound names
/// (e.g. "Silicon", "Iron oxide", "Carbon").
actor NISTXPSSource: TrainingDataSourceProtocol {

    static let baseURL = "https://srdata.nist.gov/xps/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for query in species {
                    do {
                        let spectrum = try await self.fetchXPSEntry(query: query)
                        if let spectrum { continuation.yield(spectrum) }
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - XPS Entry Fetch

    private func fetchXPSEntry(query: String) async throws -> ReferenceSpectrum? {
        // Query the NIST XPS database search endpoint
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let searchURL = Self.baseURL + "EngElmSrch.aspx?EType=PE&Ession=All&CSOpt=Retri_ex_dat"
            + "&Ession2=All&ElemDataType=PE&NumComp=1&Rone=&Rone1=&FRange=1&VFrom1=&VTo1="
            + "&Rone2=&Element1=\(encoded)"
        guard let url = URL(string: searchURL) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        guard !text.lowercased().contains("no results"),
              !text.lowercased().contains("not found") else { return nil }

        // Parse binding energies and line identifiers from the response
        let entries = Self.parseXPSResponse(text, query: query)
        guard !entries.bindingEnergies.isEmpty else { return nil }

        return ReferenceSpectrum(
            modality: .xps,
            sourceID: "nist_xps_\(query.lowercased().replacingOccurrences(of: " ", with: "_"))",
            xValues: entries.bindingEnergies,
            yValues: entries.intensities,
            metadata: [
                "source": "NIST_SRD20",
                "query": query,
                "lines": entries.lineLabels.joined(separator: ";")
            ]
        )
    }

    // MARK: - Response Parsing

    private struct XPSEntries: Sendable {
        let bindingEnergies: [Double]
        let intensities: [Double]
        let lineLabels: [String]
    }

    private nonisolated static func parseXPSResponse(_ html: String, query: String) -> XPSEntries {
        var bindingEnergies: [Double] = []
        var intensities: [Double] = []
        var labels: [String] = []

        // Parse tabular data from the HTML response
        // Look for numeric binding energy values in table cells
        let lines = html.components(separatedBy: .newlines)
        for line in lines {
            let stripped = line.replacingOccurrences(of: "<[^>]+>", with: " ",
                                                     options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            let parts = stripped.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

            // Look for lines containing binding energy values (numeric, typically 50-1200 eV)
            for (i, part) in parts.enumerated() {
                if let be = Double(part), be >= 20.0, be <= 1200.0 {
                    // Check if preceded by a line label like "C 1s", "O 1s"
                    let label: String
                    if i >= 2 {
                        label = parts[i - 2] + " " + parts[i - 1]
                    } else if i >= 1 {
                        label = parts[i - 1]
                    } else {
                        label = query
                    }

                    if !bindingEnergies.contains(be) {
                        bindingEnergies.append(be)
                        intensities.append(1.0) // Relative intensity normalized later
                        labels.append(label)
                    }
                }
            }
        }

        // Assign approximate Scofield cross-section intensities
        let scofieldRelative: [String: Double] = [
            "1s": 1.0, "2s": 0.8, "2p": 1.5, "3s": 0.6,
            "3p": 1.0, "3d": 2.5, "4s": 0.4, "4p": 0.8,
            "4d": 2.0, "4f": 3.0
        ]
        let adjustedIntensities = labels.map { label -> Double in
            for (orbital, relI) in scofieldRelative {
                if label.contains(orbital) { return relI }
            }
            return 1.0
        }

        return XPSEntries(
            bindingEnergies: bindingEnergies,
            intensities: adjustedIntensities.isEmpty ? intensities : adjustedIntensities,
            lineLabels: labels
        )
    }
}
