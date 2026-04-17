import Foundation

/// Data source for the Cologne Database for Molecular Spectroscopy (CDMS).
/// Provides microwave/rotational spectroscopy catalog data for ~750 species.
actor CDMSSource: TrainingDataSourceProtocol {

    static let baseURL = "https://cdms.astro.uni-koeln.de/classic/entries/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for tag in species {
                    let encoded = tag.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? tag
                    guard let url = URL(string: "\(Self.baseURL)\(encoded)") else { continue }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        let text = String(decoding: data, as: UTF8.self)
                        let lines = CDMSParser.parseCatalog(text)
                        guard !lines.isEmpty else { continue }
                        let xValues = lines.map { $0.freqMHz / 1000.0 }  // Convert to GHz
                        let yValues = lines.map { pow(10.0, $0.logIntensity) }
                        let spectrum = ReferenceSpectrum(
                            modality: .microwaveRotational,
                            sourceID: "cdms_\(tag)",
                            xValues: xValues,
                            yValues: yValues,
                            metadata: ["species": tag, "source": "CDMS"]
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
