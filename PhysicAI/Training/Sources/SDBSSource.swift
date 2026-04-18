import Foundation

/// Fetches spectral data from the SDBS (Spectral Database for Organic Compounds)
/// operated by AIST Japan. Covers UV, IR, Raman, NMR, and Mass Spec.
/// Species are SDBS numbers (e.g. "1234").
actor SDBSSource: TrainingDataSourceProtocol {

    /// SDBS spectrum type codes used in their URL scheme.
    enum SDBSType: String, CaseIterable, Sendable {
        case ir    = "ir"
        case raman = "raman"
        case uv    = "uv"
        case nmr1h = "hnmr"
        case nmr13c = "cnmr"
        case ms    = "ms"

        var modality: SpectralModality {
            switch self {
            case .ir:     return .ftir
            case .raman:  return .raman
            case .uv:     return .uvVis
            case .nmr1h:  return .nmrProton
            case .nmr13c: return .nmrCarbon
            case .ms:     return .massSpecEI
            }
        }
    }

    static let baseURL = "https://sdbs.db.aist.go.jp/sdbs/cgi-bin/landingpage"

    /// Which spectrum types to fetch. Defaults to all.
    private let types: [SDBSType]

    init(types: [SDBSType] = SDBSType.allCases) {
        self.types = types
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let specTypes = types
        return AsyncThrowingStream { continuation in
            Task {
                for sdbsNo in species {
                    let cleaned = sdbsNo.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    for specType in specTypes {
                        // SDBS JCAMP endpoint pattern
                        var components = URLComponents(string: "https://sdbs.db.aist.go.jp/sdbs/cgi-bin/direct_frame_disp.cgi")
                        components?.queryItems = [
                            URLQueryItem(name: "sdbsno", value: cleaned),
                            URLQueryItem(name: "spectrum_type", value: specType.rawValue)
                        ]
                        guard let url = components?.url else { continue }

                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)

                            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                                continue
                            }

                            let text = String(decoding: data, as: UTF8.self)

                            // SDBS returns HTML pages; attempt to extract JCAMP block
                            guard let jcampRange = text.range(of: "##TITLE="),
                                  let endRange = text.range(of: "##END=", range: jcampRange.lowerBound..<text.endIndex) else {
                                continue
                            }

                            let jcampText = String(text[jcampRange.lowerBound...endRange.upperBound])
                            let spectrum = try JCAMPDXTrainingParser.parse(jcampText, modality: specType.modality)
                            var enriched = spectrum
                            enriched.metadata["sdbs_no"] = cleaned
                            enriched.metadata["source"] = "sdbs"
                            continuation.yield(enriched)
                        } catch {
                            continue
                        }
                    }
                }
                continuation.finish()
            }
        }
    }
}
