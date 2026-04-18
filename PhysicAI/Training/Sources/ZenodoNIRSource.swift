import Foundation

/// Data source for Zenodo NIR spectral libraries.
/// Fetches near-infrared soil and material datasets from Zenodo open-access records.
actor ZenodoNIRSource: TrainingDataSourceProtocol {

    static let baseURL = "https://zenodo.org/api/records/"

    /// Known Zenodo record IDs with NIR spectral data.
    static let knownRecords = [
        "7586622",  // NeoSpectra NIR soil library
    ]

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                let recordIDs = species.isEmpty ? Self.knownRecords : species
                for recordID in recordIDs {
                    guard let url = URL(string: "\(Self.baseURL)\(recordID)") else { continue }
                    do {
                        let (data, _) = try await URLSession.shared.data(from: url)
                        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let files = json["files"] as? [[String: Any]] else { continue }
                        for file in files {
                            guard let links = file["links"] as? [String: Any],
                                  let downloadStr = links["self"] as? String,
                                  let downloadURL = URL(string: downloadStr),
                                  let filename = file["key"] as? String,
                                  filename.hasSuffix(".csv") || filename.hasSuffix(".txt") else { continue }
                            do {
                                let (fileData, _) = try await URLSession.shared.data(from: downloadURL)
                                let spectra = parseNIRCSV(fileData, filename: filename)
                                for s in spectra { continuation.yield(s) }
                            } catch {
                                continue
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

    private func parseNIRCSV(_ data: Data, filename: String) -> [ReferenceSpectrum] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        // First line = header with wavelength values
        let header = lines[0].split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
        let wavelengths = header.compactMap { Double($0) }
        guard !wavelengths.isEmpty else { return [] }

        var spectra: [ReferenceSpectrum] = []
        for i in 1..<lines.count {
            let values = lines[i].split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard values.count >= wavelengths.count else { continue }
            let yVals = Array(values.suffix(wavelengths.count))
            spectra.append(ReferenceSpectrum(
                modality: .nir,
                sourceID: "zenodo_nir_\(filename)_\(i)",
                xValues: wavelengths,
                yValues: yVals,
                metadata: ["file": filename, "row": "\(i)", "source": "Zenodo"]
            ))
        }
        return spectra
    }
}
