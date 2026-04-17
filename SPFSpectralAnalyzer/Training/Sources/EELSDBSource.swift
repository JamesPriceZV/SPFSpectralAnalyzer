import Foundation

/// EELS Data Base (eelsdb.eu) — electron energy-loss spectra.
/// Species array should contain spectrum IDs (e.g. "1", "25", "100") or
/// element names (e.g. "Ti", "Fe", "C") for search queries.
actor EELSDBSource: TrainingDataSourceProtocol {

    static let baseURL = "https://eelsdb.eu/api/spectrum/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for query in species {
                    do {
                        // Determine if query is a numeric ID or element name
                        if let _ = Int(query) {
                            // Fetch by direct spectrum ID
                            if let spectrum = try await self.fetchByID(query) {
                                continuation.yield(spectrum)
                            }
                        } else {
                            // Search by element name
                            let spectra = try await self.searchByElement(query)
                            for spectrum in spectra {
                                continuation.yield(spectrum)
                            }
                        }
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - Fetch by ID

    private func fetchByID(_ spectrumID: String) async throws -> ReferenceSpectrum? {
        let urlString = Self.baseURL + spectrumID + "/"
        guard let url = URL(string: urlString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        return Self.parseSingleSpectrum(data, spectrumID: spectrumID)
    }

    // MARK: - Search by Element

    private func searchByElement(_ element: String) async throws -> [ReferenceSpectrum] {
        let encoded = element.addingPercentEncoding(
            withAllowedCharacters: .urlQueryAllowed) ?? element
        let urlString = Self.baseURL + "?title=\(encoded)&format=json"
        guard let url = URL(string: urlString) else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return [] }

        // Parse the search results using EELSDBParser
        let parsed = try EELSDBParser.parseJSON(data)
        return parsed.map { entry in
            ReferenceSpectrum(
                modality: .eels,
                sourceID: "eelsdb_\(entry.id)",
                xValues: entry.energies,
                yValues: entry.intensities,
                metadata: [
                    "source": "eelsdb.eu",
                    "spectrum_id": "\(entry.id)",
                    "element": entry.element,
                    "edge": entry.edge,
                    "onset_eV": String(format: "%.1f", entry.edgeOnsetEV)
                ]
            )
        }
    }

    // MARK: - Single Spectrum Parsing

    private nonisolated static func parseSingleSpectrum(_ data: Data, spectrumID: String) -> ReferenceSpectrum? {
        struct SpectrumEntry: Decodable {
            let id: Int?
            let title: String?
            let edge: String?
            let onset: Double?
            let data: [[Double]]?
        }

        guard let entry = try? JSONDecoder().decode(SpectrumEntry.self, from: data),
              let points = entry.data, points.count >= 5 else { return nil }

        let energies = points.map { $0[0] }
        let intensities = points.map { $0.count > 1 ? $0[1] : 0.0 }
        let element = (entry.title ?? "?").components(separatedBy: " ").first ?? "?"

        return ReferenceSpectrum(
            modality: .eels,
            sourceID: "eelsdb_\(spectrumID)",
            xValues: energies,
            yValues: intensities,
            metadata: [
                "source": "eelsdb.eu",
                "spectrum_id": spectrumID,
                "element": element,
                "edge": entry.edge ?? "?",
                "onset_eV": String(format: "%.1f", entry.onset ?? 0)
            ]
        )
    }
}
