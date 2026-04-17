import Foundation

/// Fetches MS/MS spectral library data from the Global Natural Products Social (GNPS) platform.
/// Species are GNPS library spectrum IDs (e.g. "CCMSLIB00000001234").
actor GNPSSource: TrainingDataSourceProtocol {

    static let baseURL = "https://gnps.ucsd.edu/ProteoSAFe/SpectrumList"

    /// Direct JSON endpoint for individual spectra.
    private static let spectrumEndpoint = "https://gnps.ucsd.edu/ProteoSAFe/SpectrumCommentServlet"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for libraryID in species {
                    let cleaned = libraryID.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    var components = URLComponents(string: Self.spectrumEndpoint)
                    components?.queryItems = [
                        URLQueryItem(name: "SpectrumID", value: cleaned)
                    ]
                    guard let url = components?.url else { continue }

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

                        // GNPS returns peaks as "peaks_json" — a JSON string of [[mz, intensity], ...]
                        guard let peaksStr = json["peaks_json"] as? String,
                              let peaksData = peaksStr.data(using: .utf8),
                              let peaks = try JSONSerialization.jsonObject(with: peaksData) as? [[Double]] else {
                            continue
                        }

                        var mzValues: [Double] = []
                        var intensities: [Double] = []

                        for peak in peaks {
                            guard peak.count >= 2 else { continue }
                            mzValues.append(peak[0])
                            intensities.append(peak[1])
                        }

                        guard !mzValues.isEmpty else { continue }

                        // Normalise to max = 100
                        let maxI = intensities.max() ?? 1.0
                        let normIntensities = intensities.map { $0 / max(maxI, 1e-9) * 100.0 }

                        var metadata: [String: String] = [
                            "source": "gnps",
                            "library_id": cleaned
                        ]
                        if let name = json["Compound_Name"] as? String {
                            metadata["compound_name"] = name
                        }
                        if let adduct = json["Adduct"] as? String {
                            metadata["adduct"] = adduct
                        }
                        if let precursorMZ = json["Precursor_MZ"] as? String {
                            metadata["precursor_mz"] = precursorMZ
                        }

                        let spectrum = ReferenceSpectrum(
                            modality: .massSpecMSMS,
                            sourceID: "gnps_\(cleaned)",
                            xValues: mzValues,
                            yValues: normIntensities,
                            metadata: metadata
                        )
                        continuation.yield(spectrum)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }
}
