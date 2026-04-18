import Foundation

/// USGS Spectral Library splib07 — mineral and material reflectance spectra.
/// Species array should contain mineral/material names (e.g. "Quartz", "Calcite",
/// "Kaolinite", "Montmorillonite").
actor USGSSource: TrainingDataSourceProtocol {

    static let baseURL = "https://crustal.usgs.gov/speclab/QueryAll07a.php"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for mineral in species {
                    do {
                        let spectra = try await self.fetchUSGSSpectra(mineral: mineral)
                        for spectrum in spectra {
                            continuation.yield(spectrum)
                        }
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - USGS Fetch

    private func fetchUSGSSpectra(mineral: String) async throws -> [ReferenceSpectrum] {
        let encoded = mineral.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? mineral
        let searchURL = Self.baseURL + "?search=\(encoded)"
        guard let url = URL(string: searchURL) else { return [] }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return [] }

        let html = String(decoding: data, as: UTF8.self)
        guard !html.lowercased().contains("no results"),
              !html.lowercased().contains("not found") else { return [] }

        // Extract links to individual spectrum files from the search results page
        let spectrumURLs = Self.extractSpectrumURLs(html, mineral: mineral)
        var results: [ReferenceSpectrum] = []

        for specURL in spectrumURLs.prefix(10) {
            guard let fileURL = URL(string: specURL) else { continue }
            do {
                let (fileData, fileResp) = try await URLSession.shared.data(from: fileURL)
                guard let fileHTTP = fileResp as? HTTPURLResponse,
                      fileHTTP.statusCode == 200 else { continue }
                let text = String(decoding: fileData, as: UTF8.self)

                let parsed = try USGSTXTParser.parse(text)
                let spectrum = ReferenceSpectrum(
                    modality: .usgsReflectance,
                    sourceID: "usgs_\(mineral.lowercased().replacingOccurrences(of: " ", with: "_"))",
                    xValues: parsed.wavelengths,
                    yValues: parsed.reflectances,
                    metadata: [
                        "source": "USGS_splib07",
                        "mineral": mineral,
                        "name": parsed.name
                    ]
                )
                results.append(spectrum)
            } catch {
                continue
            }
        }

        return results
    }

    // MARK: - URL Extraction

    private nonisolated static func extractSpectrumURLs(_ html: String, mineral: String) -> [String] {
        var urls: [String] = []

        // Look for links to .txt spectrum files in the HTML
        let lines = html.components(separatedBy: .newlines)
        for line in lines {
            // Extract href values containing spectrum file paths
            let parts = line.components(separatedBy: "href=\"")
            for part in parts.dropFirst() {
                guard let endQuote = part.firstIndex(of: "\"") else { continue }
                let href = String(part[part.startIndex..<endQuote])
                if href.hasSuffix(".txt") || href.contains("splib07") {
                    let fullURL: String
                    if href.hasPrefix("http") {
                        fullURL = href
                    } else if href.hasPrefix("/") {
                        fullURL = "https://crustal.usgs.gov" + href
                    } else {
                        fullURL = "https://crustal.usgs.gov/speclab/" + href
                    }
                    urls.append(fullURL)
                }
            }
        }

        return urls
    }
}
