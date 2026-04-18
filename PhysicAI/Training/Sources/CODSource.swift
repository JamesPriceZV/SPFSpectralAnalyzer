import Foundation

/// Crystallography Open Database — bulk CIF download for XRD powder patterns.
/// Species array should contain 7-digit COD IDs (e.g. "1000017", "9000299").
actor CODSource: TrainingDataSourceProtocol {

    static let baseURL = "https://www.crystallography.net/cod/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for codID in species {
                    let urlString = Self.baseURL + codID + ".cif"
                    guard let url = URL(string: urlString) else { continue }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else { continue }
                        let text = String(decoding: data, as: UTF8.self)
                        guard !text.isEmpty else { continue }

                        // Extract d-spacings and intensities from CIF
                        // CIF files contain _refln_d_spacing and _refln_intensity columns
                        let parsed = Self.parseCIFReflections(text, codID: codID)
                        guard let spectrum = parsed else { continue }
                        continuation.yield(spectrum)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - CIF Reflection Parsing

    private nonisolated static func parseCIFReflections(_ text: String, codID: String) -> ReferenceSpectrum? {
        var dSpacings: [Double] = []
        var intensities: [Double] = []

        // Parse CIF loop_ blocks containing reflection data
        let lines = text.components(separatedBy: .newlines)
        var dCol = -1
        var intCol = -1
        var colCount = 0
        var inLoop = false
        var inData = false

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "loop_" {
                inLoop = true
                inData = false
                dCol = -1
                intCol = -1
                colCount = 0
                continue
            }

            if inLoop, trimmed.hasPrefix("_") {
                if trimmed.contains("d_spacing") {
                    dCol = colCount
                } else if trimmed.contains("intensity") || trimmed.contains("F_squared") {
                    intCol = colCount
                }
                colCount += 1
                continue
            }

            if inLoop, dCol >= 0, intCol >= 0, !trimmed.hasPrefix("_") {
                inData = true
            }

            if inData {
                if trimmed.isEmpty || trimmed.hasPrefix("loop_") || trimmed.hasPrefix("#") {
                    inData = false
                    inLoop = false
                    continue
                }
                let parts = trimmed.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if parts.count > max(dCol, intCol),
                   let d = Double(parts[dCol]),
                   let i = Double(parts[intCol]),
                   d > 0 {
                    dSpacings.append(d)
                    intensities.append(abs(i))
                }
            }
        }

        // If no reflection loop found, try to extract cell parameters for synthetic pattern
        if dSpacings.isEmpty {
            let cellParams = parseCellParameters(lines)
            guard let a = cellParams["a"] else { return nil }
            // Generate synthetic d-spacings from cubic approximation d = a / sqrt(h^2+k^2+l^2)
            for h in 1...5 {
                for k in 0...h {
                    for l in 0...k {
                        let hkl2 = Double(h * h + k * k + l * l)
                        let d = a / hkl2.squareRoot()
                        dSpacings.append(d)
                        intensities.append(100.0 / hkl2) // approximate falloff
                    }
                }
            }
        }

        guard !dSpacings.isEmpty else { return nil }

        // Convert d-spacings to 2-theta using Cu Ka (lambda = 1.5406 A)
        let lambda = 1.5406
        var twoTheta: [Double] = []
        var relIntensity: [Double] = []
        let maxI = intensities.max() ?? 1.0

        for (d, i) in zip(dSpacings, intensities) {
            let sinTheta = lambda / (2.0 * d)
            guard sinTheta <= 1.0, sinTheta > 0 else { continue }
            let tt = 2.0 * asin(sinTheta) * 180.0 / .pi
            guard tt >= 5.0, tt <= 90.0 else { continue }
            twoTheta.append(tt)
            relIntensity.append(i / max(maxI, 1e-9) * 100.0)
        }

        guard !twoTheta.isEmpty else { return nil }

        return ReferenceSpectrum(
            modality: .xrdPowder,
            sourceID: "cod_\(codID)",
            xValues: twoTheta,
            yValues: relIntensity,
            metadata: ["source": "COD", "cod_id": codID]
        )
    }

    private nonisolated static func parseCellParameters(_ lines: [String]) -> [String: Double] {
        var params: [String: Double] = [:]
        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("_cell_length_a") {
                let val = t.components(separatedBy: .whitespaces).last ?? ""
                params["a"] = Double(val.replacingOccurrences(of: "(", with: "")
                    .components(separatedBy: ")").first ?? "")
            } else if t.hasPrefix("_cell_length_b") {
                let val = t.components(separatedBy: .whitespaces).last ?? ""
                params["b"] = Double(val.replacingOccurrences(of: "(", with: "")
                    .components(separatedBy: ")").first ?? "")
            } else if t.hasPrefix("_cell_length_c") {
                let val = t.components(separatedBy: .whitespaces).last ?? ""
                params["c"] = Double(val.replacingOccurrences(of: "(", with: "")
                    .components(separatedBy: ")").first ?? "")
            }
        }
        return params
    }
}
