import Foundation

/// Fetches UV-Vis, IR, and Mass Spec JCAMP-DX spectra from the NIST Chemistry WebBook.
/// Species are CAS registry numbers (e.g. "50-00-0" for formaldehyde).
actor NISTWebBookSource: TrainingDataSourceProtocol {

    /// Spectrum types available from the WebBook.
    enum SpectrumType: String, CaseIterable, Sendable {
        case uvVis   = "UVVis-SPEC"
        case ir      = "IR-SPEC"
        case masSpec = "Mass-Spec"

        var modality: SpectralModality {
            switch self {
            case .uvVis:   return .uvVis
            case .ir:      return .ftir
            case .masSpec: return .massSpecEI
            }
        }
    }

    static let baseURL = "https://webbook.nist.gov/cgi/cbook.cgi"

    /// Which spectrum types to request per CAS number. Defaults to all three.
    private let types: [SpectrumType]

    init(types: [SpectrumType] = SpectrumType.allCases) {
        self.types = types
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let spectrumTypes = types
        return AsyncThrowingStream { continuation in
            Task {
                for cas in species {
                    let cleaned = cas.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    for specType in spectrumTypes {
                        var components = URLComponents(string: Self.baseURL)
                        components?.queryItems = [
                            URLQueryItem(name: "ID", value: cleaned),
                            URLQueryItem(name: "Type", value: specType.rawValue),
                            URLQueryItem(name: "JCAMP", value: "on")
                        ]
                        guard let url = components?.url else { continue }

                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)

                            // Skip non-200 responses
                            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                                continue
                            }

                            let text = String(decoding: data, as: UTF8.self)
                            let spectrum = try JCAMPDXTrainingParser.parse(text, modality: specType.modality)
                            var enriched = spectrum
                            enriched.metadata["cas"] = cleaned
                            enriched.metadata["source"] = "nist_webbook"
                            continuation.yield(enriched)
                        } catch {
                            // Gracefully skip failed downloads
                            continue
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
}
