import Foundation

/// Fetches spectral data from the Human Metabolome Database (HMDB).
/// Covers NMR (1H, 13C), MS, MS/MS spectra, and HPLC retention data.
/// Species are HMDB IDs (e.g. "HMDB0000001").
actor HMDBSource: TrainingDataSourceProtocol {

    static let baseURL = "https://hmdb.ca/metabolites/"

    /// HMDB spectral data type endpoints.
    enum HMDBSpectrumType: String, CaseIterable, Sendable {
        case nmr1H  = "nmr_one_d"
        case nmr13C = "nmr_two_d"
        case msms   = "ms_ms"
        case ei     = "ei_ms"

        var modality: SpectralModality {
            switch self {
            case .nmr1H:  return .nmrProton
            case .nmr13C: return .nmrCarbon
            case .msms:   return .massSpecMSMS
            case .ei:     return .massSpecEI
            }
        }
    }

    /// Which spectrum types to fetch. Defaults to all.
    private let types: [HMDBSpectrumType]

    init(types: [HMDBSpectrumType] = HMDBSpectrumType.allCases) {
        self.types = types
    }

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        let specTypes = types
        return AsyncThrowingStream { continuation in
            Task {
                for hmdbID in species {
                    let cleaned = hmdbID.trimmingCharacters(in: .whitespaces)
                    guard !cleaned.isEmpty else { continue }

                    // Normalise to full HMDB ID format (HMDB00XXXXX)
                    let normalised: String
                    if cleaned.hasPrefix("HMDB") {
                        normalised = cleaned
                    } else {
                        normalised = "HMDB\(cleaned)"
                    }

                    for specType in specTypes {
                        // HMDB XML endpoint for spectral data
                        let urlString = "\(Self.baseURL)\(normalised).xml"
                        guard let url = URL(string: urlString) else { continue }

                        do {
                            let (data, response) = try await URLSession.shared.data(from: url)

                            if let http = response as? HTTPURLResponse, http.statusCode != 200 {
                                continue
                            }

                            // Parse relevant spectral peaks from the XML
                            let spectra = try Self.parseHMDBXML(data, hmdbID: normalised, type: specType)
                            for spectrum in spectra {
                                continuation.yield(spectrum)
                            }
                        } catch {
                            continue
                        }
                    }
                }
                continuation.finish()
            }
        }
    }

    /// Extracts spectral data from HMDB XML metabolite record.
    /// Returns spectra matching the requested type.
    private static func parseHMDBXML(_ data: Data, hmdbID: String, type: HMDBSpectrumType) throws -> [ReferenceSpectrum] {
        // HMDB XML contains <spectra> blocks with <spectrum> elements
        // Each spectrum has <peaks> with <peak> elements containing <mass-charge> and <intensity>
        // For NMR: <chemical-shift> and <intensity>

        let text = String(decoding: data, as: UTF8.self)
        var results: [ReferenceSpectrum] = []

        // Simple XML extraction for MS peaks
        // Find <ms-ms-spectrum> or <ei-ms-spectrum> blocks
        let spectrumTag: String
        switch type {
        case .nmr1H:  spectrumTag = "nmr-one-d-spectrum"
        case .nmr13C: spectrumTag = "nmr-two-d-spectrum"
        case .msms:   spectrumTag = "ms-ms-spectrum"
        case .ei:     spectrumTag = "ei-ms-spectrum"
        }

        let openTag = "<\(spectrumTag)>"
        let closeTag = "</\(spectrumTag)>"

        var searchStart = text.startIndex
        while let openRange = text.range(of: openTag, range: searchStart..<text.endIndex),
              let closeRange = text.range(of: closeTag, range: openRange.upperBound..<text.endIndex) {

            let block = String(text[openRange.lowerBound..<closeRange.upperBound])
            searchStart = closeRange.upperBound

            var xValues: [Double] = []
            var yValues: [Double] = []

            // Extract peaks: <mass-charge>X</mass-charge> <intensity>Y</intensity>
            // or for NMR: <chemical-shift>X</chemical-shift> <intensity>Y</intensity>
            let xTag = (type == .nmr1H || type == .nmr13C) ? "chemical-shift" : "mass-charge"

            var peakSearch = block.startIndex
            while let xOpen = block.range(of: "<\(xTag)>", range: peakSearch..<block.endIndex),
                  let xClose = block.range(of: "</\(xTag)>", range: xOpen.upperBound..<block.endIndex) {

                let xStr = String(block[xOpen.upperBound..<xClose.lowerBound])
                peakSearch = xClose.upperBound

                if let intOpen = block.range(of: "<intensity>", range: peakSearch..<block.endIndex),
                   let intClose = block.range(of: "</intensity>", range: intOpen.upperBound..<block.endIndex) {
                    let yStr = String(block[intOpen.upperBound..<intClose.lowerBound])
                    peakSearch = intClose.upperBound

                    if let x = Double(xStr.trimmingCharacters(in: .whitespaces)),
                       let y = Double(yStr.trimmingCharacters(in: .whitespaces)) {
                        xValues.append(x)
                        yValues.append(y)
                    }
                }
            }

            guard !xValues.isEmpty else { continue }

            results.append(ReferenceSpectrum(
                modality: type.modality,
                sourceID: "hmdb_\(hmdbID)_\(type.rawValue)",
                xValues: xValues,
                yValues: yValues,
                metadata: [
                    "source": "hmdb",
                    "hmdb_id": hmdbID,
                    "spectrum_type": type.rawValue
                ]
            ))
        }

        return results
    }
}
