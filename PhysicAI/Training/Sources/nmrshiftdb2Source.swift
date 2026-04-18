import Foundation

/// Fetches NMR chemical shift spectra from nmrshiftdb2 (Cologne).
/// The database provides both 1H and 13C NMR shift data in NMReDATA/SDF/JCAMP formats.
/// Species are nmrshiftdb2 molecule IDs (numeric strings, e.g. "10043607").
actor nmrshiftdb2Source: TrainingDataSourceProtocol {

    static let baseURL = "https://nmrshiftdb.nmr.uni-koeln.de/nmrshiftdb/"

    /// NMR nucleus to request.
    enum Nucleus: String, Sendable {
        case proton  = "1H"
        case carbon  = "13C"

        var modality: SpectralModality {
            switch self {
            case .proton: return .nmrProton
            case .carbon: return .nmrCarbon
            }
        }
    }

    /// Which nuclei to fetch. Defaults to both.
    private let nuclei: [Nucleus]

    init(nuclei: [Nucleus] = [.proton, .carbon]) {
        self.nuclei = nuclei
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let requestedNuclei = nuclei
        return AsyncThrowingStream { continuation in
            Task {
                for moleculeID in species {
                    let cleaned = moleculeID.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    for nucleus in requestedNuclei {
                        // nmrshiftdb2 JCAMP download endpoint
                        let urlString = "\(Self.baseURL)download.do?molid=\(cleaned)&type=jcamp&nucleus=\(nucleus.rawValue)"
                        guard let url = URL(string: urlString) else { continue }

                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)

                            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                                continue
                            }

                            let text = String(decoding: data, as: UTF8.self)

                            // Skip empty or error responses
                            guard text.contains("##TITLE=") || text.contains("##XYDATA=") else {
                                continue
                            }

                            let spectrum = try JCAMPDXTrainingParser.parse(text, modality: nucleus.modality)
                            var enriched = spectrum
                            enriched.metadata["molecule_id"] = cleaned
                            enriched.metadata["nucleus"] = nucleus.rawValue
                            enriched.metadata["source"] = "nmrshiftdb2"
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
