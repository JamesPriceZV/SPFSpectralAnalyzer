import Foundation

/// Fetches Raman and XRD powder diffraction spectra from the RRUFF mineral database.
/// Species are mineral names (e.g. "Quartz", "Calcite").
actor RRUFFSource: TrainingDataSourceProtocol {

    /// RRUFF data type to request.
    enum RRUFFType: String, Sendable {
        case raman = "raman"
        case xrd   = "xrd"

        var modality: SpectralModality {
            switch self {
            case .raman: return .raman
            case .xrd:   return .xrdPowder
            }
        }
    }

    static let baseURL = "https://www.rruff.net/zipped_data_files/"

    /// Bulk ZIP URLs for each data type (verified 2026-04-17).
    private nonisolated static let bulkZIPURLs: [RRUFFType: [URL]] = [
        .raman: [
            URL(string: "https://www.rruff.net/zipped_data_files/raman/LR-Raman.zip")!,
            URL(string: "https://www.rruff.net/zipped_data_files/raman/excellent_unoriented.zip")!
        ],
        .xrd: [
            URL(string: "https://www.rruff.net/zipped_data_files/powder/XY_RAW.zip")!,
            URL(string: "https://www.rruff.net/zipped_data_files/powder/XY_Processed.zip")!
        ]
    ]

    /// Which data types to fetch. Defaults to Raman only.
    private let types: [RRUFFType]

    init(types: [RRUFFType] = [.raman]) {
        self.types = types
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let dataTypes = types
        let speciesSet = Set(species.map { $0.trimmingCharacters(in: .whitespaces).lowercased() })
        return AsyncThrowingStream { continuation in
            Task {
                for dataType in dataTypes {
                    guard let urls = Self.bulkZIPURLs[dataType] else { continue }
                    for zipURL in urls {
                        do {
                            let (data, response) = try await URLSession.shared.data(from: zipURL)
                            guard let http = response as? HTTPURLResponse,
                                  (200...299).contains(http.statusCode) else { continue }

                            // Extract ZIP to temp and parse individual TXT files
                            let tempDir = FileManager.default.temporaryDirectory
                                .appendingPathComponent("rruff_\(UUID().uuidString)")
                            try FileManager.default.createDirectory(at: tempDir,
                                                                    withIntermediateDirectories: true)
                            let zipPath = tempDir.appendingPathComponent("data.zip")
                            try data.write(to: zipPath)

                            let proc = Process()
                            proc.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
                            proc.arguments = ["-xk", zipPath.path, tempDir.path]
                            try proc.run()
                            proc.waitUntilExit()

                            let files = (try? FileManager.default
                                .contentsOfDirectory(at: tempDir, includingPropertiesForKeys: nil)) ?? []
                            for file in files where file.pathExtension == "txt" {
                                let mineral = file.deletingPathExtension().lastPathComponent
                                    .components(separatedBy: "__").first ?? file.deletingPathExtension().lastPathComponent
                                // If species list is non-empty, filter to requested minerals
                                if !speciesSet.isEmpty,
                                   !speciesSet.contains(mineral.lowercased()) { continue }
                                do {
                                    let text = try String(contentsOf: file, encoding: .utf8)
                                    let spectrum = try Self.parseRRUFFText(text, mineral: mineral, type: dataType)
                                    continuation.yield(spectrum)
                                } catch {
                                    continue
                                }
                            }
                            try? FileManager.default.removeItem(at: tempDir)
                        } catch {
                            continue
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Parses RRUFF plain-text format with X= and Y= arrays or tab-delimited columns.
    private static func parseRRUFFText(_ text: String, mineral: String, type: RRUFFType) throws -> ReferenceSpectrum {
        var xValues: [Double] = []
        var yValues: [Double] = []

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip comment/header lines
            if trimmed.isEmpty || trimmed.hasPrefix("##") || trimmed.hasPrefix("#") {
                continue
            }

            // Tab or comma delimited: X, Y
            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: ",\t "))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            if parts.count >= 2,
               let x = Double(parts[0]),
               let y = Double(parts[1]) {
                xValues.append(x)
                yValues.append(y)
            }
        }

        guard !xValues.isEmpty, xValues.count == yValues.count else {
            throw NSError(domain: "RRUFFParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No XY data found for \(mineral)"])
        }

        return ReferenceSpectrum(
            modality: type.modality,
            sourceID: "rruff_\(mineral.lowercased())",
            xValues: xValues,
            yValues: yValues,
            metadata: [
                "mineral": mineral,
                "source": "rruff",
                "data_type": type.rawValue
            ]
        )
    }
}
