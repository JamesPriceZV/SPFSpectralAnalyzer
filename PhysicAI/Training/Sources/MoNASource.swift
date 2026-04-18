import Foundation

/// Fetches mass spectra from MassBank of North America (MoNA) via its REST API.
/// Species are compound names or InChIKey strings.
actor MoNASource: TrainingDataSourceProtocol {

    static let baseURL = "https://mona.fiehnlab.ucdavis.edu/rest/spectra/search"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for query in species {
                    let cleaned = query.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    // Determine if query is an InChIKey (27 chars, two dashes)
                    let isInChIKey = cleaned.count == 27
                        && cleaned.filter({ $0 == "-" }).count == 2

                    let rsqlQuery: String
                    if isInChIKey {
                        rsqlQuery = "compound.metaData=q='name==\"InChIKey\" and value==\"\(cleaned)\"'"
                    } else {
                        rsqlQuery = "compound.names=q='name=match=\".*\(cleaned).*\"'"
                    }

                    var components = URLComponents(string: Self.baseURL)
                    components?.queryItems = [
                        URLQueryItem(name: "query", value: rsqlQuery),
                        URLQueryItem(name: "size", value: "10")
                    ]
                    guard let url = components?.url else { continue }

                    do {
                        var request = URLRequest(url: url)
                        request.setValue("application/json", forHTTPHeaderField: "Accept")

                        let (data, response) = try await URLSession.shared.data(for: request)

                        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                            continue
                        }

                        // Parse the JSON array of spectra
                        guard let results = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                            continue
                        }

                        for entry in results {
                            guard let spectrumStr = entry["spectrum"] as? String else { continue }

                            // MoNA spectrum format: "mz:intensity mz:intensity ..."
                            var mzValues: [Double] = []
                            var intensities: [Double] = []

                            for pair in spectrumStr.components(separatedBy: " ") {
                                let parts = pair.components(separatedBy: ":")
                                guard parts.count == 2,
                                      let mz = Double(parts[0]),
                                      let inten = Double(parts[1]) else { continue }
                                mzValues.append(mz)
                                intensities.append(inten)
                            }

                            guard !mzValues.isEmpty else { continue }

                            // Normalise intensities to max = 100
                            let maxI = intensities.max() ?? 1.0
                            let normIntensities = intensities.map { $0 / max(maxI, 1e-9) * 100.0 }

                            // Extract metadata
                            var metadata: [String: String] = ["source": "mona"]
                            if let compound = entry["compound"] as? [[String: Any]],
                               let first = compound.first {
                                if let names = first["names"] as? [[String: Any]],
                                   let firstName = names.first?["name"] as? String {
                                    metadata["compound_name"] = firstName
                                }
                                if let inchiKey = first["inchiKey"] as? String {
                                    metadata["inchi_key"] = inchiKey
                                }
                            }

                            // Detect EI vs MS/MS from metadata
                            let modality: SpectralModality
                            if let metaArray = entry["metaData"] as? [[String: Any]] {
                                let hasMS2 = metaArray.contains { m in
                                    let name = (m["name"] as? String ?? "").lowercased()
                                    let value = (m["value"] as? String ?? "").lowercased()
                                    return name.contains("ms level") && value.contains("ms2")
                                }
                                modality = hasMS2 ? .massSpecMSMS : .massSpecEI
                            } else {
                                modality = .massSpecEI
                            }

                            let monaID = entry["id"] as? String ?? "mona_\(UUID().uuidString.prefix(8))"

                            let spectrum = ReferenceSpectrum(
                                modality: modality,
                                sourceID: monaID,
                                xValues: mzValues,
                                yValues: normIntensities,
                                metadata: metadata
                            )
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
}
