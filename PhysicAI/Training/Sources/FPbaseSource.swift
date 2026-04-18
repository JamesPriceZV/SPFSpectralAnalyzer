import Foundation

/// Fetches fluorescent protein emission/excitation spectra from FPbase via its REST API.
/// Species are protein slugs (e.g. "egfp", "mcherry", "tdtomato").
actor FPbaseSource: TrainingDataSourceProtocol {

    static let baseURL = "https://www.fpbase.org/api/proteins/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for slug in species {
                    let cleaned = slug.trimmingCharacters(in: .whitespaces)
                        .lowercased()
                        .replacingOccurrences(of: " ", with: "-")
                    guard !cleaned.isEmpty else { continue }

                    // FPbase protein detail endpoint returns spectra data
                    let urlString = "\(Self.baseURL)\(cleaned)/?format=json"
                    guard let url = URL(string: urlString) else { continue }

                    do {
                        var request = URLRequest(url: url)
                        request.setValue("application/json", forHTTPHeaderField: "Accept")

                        let (data, response) = try await URLSession.shared.data(for: request)

                        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                            continue
                        }

                        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                            continue
                        }

                        let proteinName = json["name"] as? String ?? cleaned

                        // Extract quantum yield and other properties
                        var metadata: [String: String] = [
                            "source": "fpbase",
                            "protein_name": proteinName,
                            "slug": cleaned
                        ]

                        // FPbase returns states, each with spectra
                        guard let states = json["states"] as? [[String: Any]] else { continue }

                        for state in states {
                            if let qy = state["qy"] as? Double {
                                metadata["quantum_yield"] = String(qy)
                            }
                            if let exMax = state["ex_max"] as? Double {
                                metadata["excitation_max_nm"] = String(Int(exMax))
                            }
                            if let emMax = state["em_max"] as? Double {
                                metadata["emission_max_nm"] = String(Int(emMax))
                            }
                            if let extCoeff = state["ext_coeff"] as? Double {
                                metadata["extinction_coefficient"] = String(Int(extCoeff))
                            }

                            // Extract emission spectrum data from the spectra array
                            guard let spectra = state["spectra"] as? [[String: Any]] else { continue }

                            for specEntry in spectra {
                                let category = specEntry["category"] as? String ?? ""

                                // We want emission spectra
                                guard category.lowercased() == "em" else { continue }

                                guard let spectrumData = specEntry["data"] as? [[Double]] else { continue }

                                var wavelengths: [Double] = []
                                var intensities: [Double] = []

                                for point in spectrumData {
                                    guard point.count >= 2 else { continue }
                                    wavelengths.append(point[0])
                                    intensities.append(point[1])
                                }

                                guard !wavelengths.isEmpty else { continue }

                                // Normalise intensities to max = 1.0
                                let maxI = intensities.max() ?? 1.0
                                let normIntensities = intensities.map { $0 / max(maxI, 1e-9) }

                                let spectrum = ReferenceSpectrum(
                                    modality: .fluorescence,
                                    sourceID: "fpbase_\(cleaned)",
                                    xValues: wavelengths,
                                    yValues: normIntensities,
                                    metadata: metadata
                                )
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
}
