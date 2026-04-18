import Foundation

/// Data source for Zenodo THz (terahertz) spectral datasets.
/// Fetches pharmaceutical and material THz absorption spectra from open-access records.
actor ZenodoTHzSource: TrainingDataSourceProtocol {

    static let baseURL = "https://zenodo.org/api/records/"

    /// Known Zenodo record IDs with THz spectral data.
    static let knownRecords = [
        "4106081",  // THz pharmaceutical dataset
        "5561549",  // THz spectroscopy data
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
                                let spectra = parseTHzData(fileData, filename: filename)
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

    private func parseTHzData(_ data: Data, filename: String) -> [ReferenceSpectrum] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
        guard lines.count > 1 else { return [] }

        // Try two-column format: frequency (THz), absorption
        var xVals: [Double] = []
        var yVals: [Double] = []
        for line in lines {
            let parts = line.split(whereSeparator: { $0 == "," || $0 == "\t" || $0 == " " })
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            if parts.count >= 2, let x = Double(parts[0]), let y = Double(parts[1]) {
                xVals.append(x)
                yVals.append(y)
            }
        }
        guard !xVals.isEmpty else { return [] }

        return [ReferenceSpectrum(
            modality: .terahertz,
            sourceID: "zenodo_thz_\(filename)",
            xValues: xVals,
            yValues: yVals,
            metadata: ["file": filename, "source": "Zenodo THz"]
        )]
    }
}
