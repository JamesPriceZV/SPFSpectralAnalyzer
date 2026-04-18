import Foundation

/// Fetches fluorescence and absorption spectra from the PhotochemCAD database (OMLC).
/// Contains ~250 fluorophore spectra with emission/absorption data and quantum yields.
/// Species are PhotochemCAD compound IDs (numeric strings, e.g. "1", "2", "42").
actor PhotochemCADSource: TrainingDataSourceProtocol {

    static let baseURL = "https://omlc.org/spectra/PhotochemCAD/data/"

    /// PhotochemCAD spectrum type.
    enum SpectrumType: String, Sendable {
        case absorption = "abs"
        case emission   = "em"

        var modality: SpectralModality {
            switch self {
            case .absorption: return .uvVis
            case .emission:   return .fluorescence
            }
        }

        var fileSuffix: String {
            switch self {
            case .absorption: return "-abs.txt"
            case .emission:   return "-ems.txt"
            }
        }
    }

    /// Which spectrum types to fetch. Defaults to emission (fluorescence).
    private let types: [SpectrumType]

    init(types: [SpectrumType] = [.emission, .absorption]) {
        self.types = types
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let specTypes = types
        return AsyncThrowingStream { continuation in
            Task {
                for compoundID in species {
                    let cleaned = compoundID.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    // PhotochemCAD compound IDs are zero-padded to 3 digits
                    let paddedID: String
                    if let num = Int(cleaned) {
                        paddedID = String(format: "%03d", num)
                    } else {
                        paddedID = cleaned
                    }

                    for specType in specTypes {
                        let urlString = "\(Self.baseURL)\(paddedID)\(specType.fileSuffix)"
                        guard let url = URL(string: urlString) else { continue }

                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)

                            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                                continue
                            }

                            let text = String(decoding: data, as: UTF8.self)
                            let spectrum = try Self.parsePhotochemCADText(
                                text, compoundID: paddedID, type: specType
                            )
                            continuation.yield(spectrum)
                        } catch {
                            continue
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Parses PhotochemCAD plain text tab-delimited spectral files.
    /// Format: two columns — wavelength (nm) and intensity (normalised or molar absorptivity).
    /// Lines starting with '#' or '%' are comments; first data row may be a header.
    private static func parsePhotochemCADText(
        _ text: String, compoundID: String, type: SpectrumType
    ) throws -> ReferenceSpectrum {
        var wavelengths: [Double] = []
        var intensities: [Double] = []

        let lines = text.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines, comments, headers
            if trimmed.isEmpty || trimmed.hasPrefix("#") || trimmed.hasPrefix("%") {
                continue
            }

            // Tab or space delimited
            let parts = trimmed.components(separatedBy: CharacterSet(charactersIn: "\t ,"))
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }

            guard parts.count >= 2,
                  let wl = Double(parts[0]),
                  let inten = Double(parts[1]) else { continue }

            // Sanity check: wavelength should be in plausible range
            guard wl >= 100 && wl <= 1200 else { continue }

            wavelengths.append(wl)
            intensities.append(inten)
        }

        guard !wavelengths.isEmpty, wavelengths.count == intensities.count else {
            throw NSError(domain: "PhotochemCADParser", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No spectral data for compound \(compoundID)"])
        }

        // Normalise emission to max = 1.0
        if type == .emission {
            let maxI = intensities.max() ?? 1.0
            intensities = intensities.map { $0 / max(maxI, 1e-9) }
        }

        return ReferenceSpectrum(
            modality: type.modality,
            sourceID: "photochemcad_\(compoundID)_\(type.rawValue)",
            xValues: wavelengths,
            yValues: intensities,
            metadata: [
                "source": "photochemcad",
                "compound_id": compoundID,
                "spectrum_type": type.rawValue
            ]
        )
    }
}
