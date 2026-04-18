import Foundation

/// NIST Atomic Spectra Database — emission line data for all elements.
/// Species array should contain element symbols (e.g. "Fe", "Ca", "Na", "H").
actor NISTASDSource: TrainingDataSourceProtocol {

    static let baseURL = "https://physics.nist.gov/cgi-bin/ASD/lines1.pl"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for element in species {
                    let encoded = element.addingPercentEncoding(
                        withAllowedCharacters: .urlQueryAllowed) ?? element
                    let query = "?spectra=\(encoded)"
                        + "&low_w=200&high_w=900&unit=1"
                        + "&format=2&line_out=0&en_unit=0&output=0"
                        + "&bibrefs=1&page_size=15&show_obs_wl=1"
                        + "&show_calc_wl=1&unc_out=1&order_out=0"
                        + "&max_low_enrg=&show_av=2&max_upp_enrg="
                        + "&tsb_value=0&min_str=&A_out=1&intens_out=on"
                        + "&allowed_out=1&forbid_out=1"
                        + "&no_spaces=1&submit=Retrieve+Data"
                    guard let url = URL(string: Self.baseURL + query) else { continue }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else { continue }
                        let text = String(decoding: data, as: UTF8.self)
                        guard !text.lowercased().contains("no lines found"),
                              !text.lowercased().contains("no data") else { continue }

                        let parsed = Self.parseASDResponse(text, element: element)
                        guard !parsed.wavelengths.isEmpty else { continue }

                        let spectrum = ReferenceSpectrum(
                            modality: .atomicEmission,
                            sourceID: "nist_asd_\(element)",
                            xValues: parsed.wavelengths,
                            yValues: parsed.intensities,
                            metadata: [
                                "source": "NIST_ASD",
                                "element": element,
                                "line_count": "\(parsed.wavelengths.count)",
                                "wavelength_range_nm": "200-900"
                            ]
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

    // MARK: - ASD Response Parsing

    private struct ASDLines: Sendable {
        let wavelengths: [Double]
        let intensities: [Double]
    }

    private nonisolated static func parseASDResponse(_ text: String, element: String) -> ASDLines {
        var wavelengths: [Double] = []
        var intensities: [Double] = []

        // NIST ASD CSV format with no_spaces option:
        // obs_wl_air(nm)|intens|Aki(s^-1)|Ei(cm-1)|Ek(cm-1)|...
        let lines = text.components(separatedBy: .newlines)
        var headerParsed = false
        var wlCol = 0
        var intCol = 1
        var akiCol = 2

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Detect and skip HTML tags
            if trimmed.contains("<") && trimmed.contains(">") { continue }

            let separator: String
            if trimmed.contains("|") {
                separator = "|"
            } else if trimmed.contains("\t") {
                separator = "\t"
            } else if trimmed.contains(",") {
                separator = ","
            } else {
                continue
            }

            let parts = trimmed.components(separatedBy: separator)
                .map { $0.trimmingCharacters(in: .whitespaces) }

            // Parse header row to find column indices
            if !headerParsed {
                for (i, col) in parts.enumerated() {
                    let lower = col.lowercased()
                    if lower.contains("obs_wl") || lower.contains("ritz_wl") || lower.contains("wavelength") {
                        wlCol = i
                    } else if lower.contains("intens") {
                        intCol = i
                    } else if lower.contains("aki") || lower.contains("a_ki") {
                        akiCol = i
                    }
                }
                headerParsed = true
                // If this line has no numeric data, treat as header and continue
                if parts.count > wlCol, Double(parts[wlCol]) == nil {
                    continue
                }
            }

            guard parts.count > max(wlCol, intCol) else { continue }

            // Parse wavelength — strip any non-numeric characters except decimal point
            let wlStr = parts[wlCol].filter { $0.isNumber || $0 == "." || $0 == "-" }
            guard let wl = Double(wlStr), wl >= 200.0, wl <= 900.0 else { continue }

            // Parse intensity — may be numeric or contain letters (e.g. "500c")
            let intStr = parts[intCol].filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "e" || $0 == "E" || $0 == "+" }
            var intensity = Double(intStr) ?? 0

            // If intensity is zero, try using Einstein A coefficient as proxy
            if intensity < 1e-30, parts.count > akiCol {
                let akiStr = parts[akiCol].filter { $0.isNumber || $0 == "." || $0 == "-" || $0 == "e" || $0 == "E" || $0 == "+" }
                intensity = Double(akiStr) ?? 0
            }

            guard intensity > 0 else { continue }

            wavelengths.append(wl)
            intensities.append(intensity)
        }

        // Normalize intensities to max = 1000
        let maxI = intensities.max() ?? 1.0
        let normI = intensities.map { $0 / maxI * 1000.0 }

        return ASDLines(wavelengths: wavelengths, intensities: normI)
    }
}
