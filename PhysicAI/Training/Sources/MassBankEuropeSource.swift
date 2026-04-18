import Foundation

/// Fetches mass spectra from MassBank Europe via their GitHub data repository.
/// Species are MassBank accession IDs (e.g. "MSBNK-RIKEN-PR100001").
actor MassBankEuropeSource: TrainingDataSourceProtocol {

    static let baseURL = "https://raw.githubusercontent.com/MassBank/MassBank-data/main/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for accession in species {
                    let cleaned = accession.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    // MassBank accession format: MSBNK-{contributor}-{id}
                    // File path: {contributor}/{accession}.txt
                    let parts = cleaned.components(separatedBy: "-")
                    guard parts.count >= 3 else { continue }
                    let contributor = parts[1]

                    let urlString = Self.baseURL + "\(contributor)/\(cleaned).txt"
                    guard let url = URL(string: urlString) else { continue }

                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)

                        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                            continue
                        }

                        let text = String(decoding: data, as: UTF8.self)
                        let spectrum = try Self.parseMassBankRecord(text, accession: cleaned)
                        continuation.yield(spectrum)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Parses a MassBank Europe `.txt` record file.
    /// Format has header fields (KEY: value) and PK$PEAK block with m/z, intensity, rel.int.
    private static func parseMassBankRecord(_ text: String, accession: String) throws -> ReferenceSpectrum {
        var metadata: [String: String] = ["source": "massbank_eu", "accession": accession]
        var mzValues: [Double] = []
        var intensities: [Double] = []
        var inPeakBlock = false

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Extract key metadata
            if trimmed.hasPrefix("CH$NAME:") {
                metadata["compound_name"] = String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("CH$FORMULA:") {
                metadata["formula"] = String(trimmed.dropFirst(11)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("CH$EXACT_MASS:") {
                metadata["exact_mass"] = String(trimmed.dropFirst(14)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("AC$MASS_SPECTROMETRY: MS_TYPE") {
                metadata["ms_type"] = String(trimmed.dropFirst(29)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("AC$MASS_SPECTROMETRY: COLLISION_ENERGY") {
                metadata["collision_energy"] = String(trimmed.dropFirst(38)).trimmingCharacters(in: .whitespaces)
            }

            // Detect peak block start
            if trimmed.hasPrefix("PK$PEAK:") {
                inPeakBlock = true
                continue
            }

            // End of record
            if trimmed == "//" {
                inPeakBlock = false
                continue
            }

            // Parse peak data: m/z, intensity, relative intensity
            if inPeakBlock {
                let parts = trimmed.components(separatedBy: .whitespaces)
                    .filter { !$0.isEmpty }
                guard parts.count >= 2,
                      let mz = Double(parts[0]),
                      let inten = Double(parts[1]) else { continue }
                mzValues.append(mz)
                intensities.append(inten)
            }
        }

        guard !mzValues.isEmpty, mzValues.count == intensities.count else {
            throw NSError(domain: "MassBankParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No peak data in record \(accession)"])
        }

        // Normalise to max = 100
        let maxI = intensities.max() ?? 1.0
        let normIntensities = intensities.map { $0 / max(maxI, 1e-9) * 100.0 }

        // Determine modality from MS_TYPE metadata
        let msType = metadata["ms_type"]?.uppercased() ?? ""
        let modality: SpectralModality = msType.contains("MS2") ? .massSpecMSMS : .massSpecEI

        return ReferenceSpectrum(
            modality: modality,
            sourceID: accession,
            xValues: mzValues,
            yValues: normIntensities,
            metadata: metadata
        )
    }
}
