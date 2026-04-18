import Foundation

actor MPIMainzSource: TrainingDataSourceProtocol {

    static let baseURL = "https://uv-vis-spectral-atlas-mainz.org/jcamp/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for name in species {
                    let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
                    guard let url = URL(string: Self.baseURL + encoded + ".jdx") else { continue }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let raw = String(decoding: data, as: UTF8.self)
                        let spectrum = try JCAMPDXTrainingParser.parse(raw, modality: .atmosphericUVVis)
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
