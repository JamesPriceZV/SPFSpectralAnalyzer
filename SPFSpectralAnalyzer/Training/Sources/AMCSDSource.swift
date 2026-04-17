import Foundation

/// American Mineralogist Crystal Structure Database — CIF downloads for XRD.
/// Species array should contain AMCSD IDs (e.g. "0000001", "0019517").
actor AMCSDSource: TrainingDataSourceProtocol {

    static let baseURL = "https://rruff.geo.arizona.edu/AMS/xtal_data/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for amcsdID in species {
                    let urlString = Self.baseURL + "CIFfiles/" + amcsdID + ".cif"
                    guard let url = URL(string: urlString) else { continue }
                    do {
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200 else { continue }
                        let text = String(decoding: data, as: UTF8.self)
                        guard !text.isEmpty,
                              !text.lowercased().contains("not found") else { continue }

                        guard let spectrum = Self.parseCIFToDiffraction(text, amcsdID: amcsdID) else {
                            continue
                        }
                        continuation.yield(spectrum)
                    } catch {
                        continue
                    }
                }
                continuation.finish()
            }
        }
    }

    // MARK: - CIF to Diffraction Pattern

    private nonisolated static func parseCIFToDiffraction(_ text: String, amcsdID: String) -> ReferenceSpectrum? {
        let lines = text.components(separatedBy: .newlines)

        // Extract cell parameters
        var a: Double?, b: Double?, c: Double?
        var mineralName = "unknown"

        for line in lines {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("_cell_length_a") {
                a = Self.extractCIFNumber(t)
            } else if t.hasPrefix("_cell_length_b") {
                b = Self.extractCIFNumber(t)
            } else if t.hasPrefix("_cell_length_c") {
                c = Self.extractCIFNumber(t)
            } else if t.hasPrefix("_chemical_name_mineral") || t.hasPrefix("_chemical_name_common") {
                let parts = t.components(separatedBy: .whitespaces)
                if parts.count >= 2 {
                    mineralName = parts.dropFirst().joined(separator: " ")
                        .replacingOccurrences(of: "'", with: "")
                        .trimmingCharacters(in: .whitespaces)
                }
            }
        }

        guard let cellA = a else { return nil }
        let cellB = b ?? cellA
        let cellC = c ?? cellA

        // Generate d-spacings from cell parameters (orthorhombic approximation)
        let lambda = 1.5406 // Cu Ka in Angstroms
        var twoTheta: [Double] = []
        var intensities: [Double] = []

        for h in 0...6 {
            for k in 0...6 {
                for l in 0...6 {
                    guard h + k + l > 0 else { continue }
                    let invD2 = pow(Double(h) / cellA, 2) +
                                pow(Double(k) / cellB, 2) +
                                pow(Double(l) / cellC, 2)
                    let d = 1.0 / invD2.squareRoot()
                    let sinTheta = lambda / (2.0 * d)
                    guard sinTheta > 0, sinTheta <= 1.0 else { continue }
                    let tt = 2.0 * asin(sinTheta) * 180.0 / .pi
                    guard tt >= 5.0, tt <= 90.0 else { continue }
                    // Approximate intensity with multiplicity and Lorentz factor
                    let multiplicity = Self.multiplicity(h: h, k: k, l: l)
                    let lorentzPol = 1.0 / (sin(tt * .pi / 360.0) * sin(tt * .pi / 180.0))
                    twoTheta.append(tt)
                    intensities.append(Double(multiplicity) * abs(lorentzPol))
                }
            }
        }

        guard !twoTheta.isEmpty else { return nil }

        // Normalize intensities to max = 100
        let maxI = intensities.max() ?? 1.0
        let normI = intensities.map { $0 / maxI * 100.0 }

        return ReferenceSpectrum(
            modality: .xrdPowder,
            sourceID: "amcsd_\(amcsdID)",
            xValues: twoTheta,
            yValues: normI,
            metadata: [
                "source": "AMCSD",
                "amcsd_id": amcsdID,
                "mineral": mineralName,
                "cell_a": String(format: "%.4f", cellA),
                "cell_b": String(format: "%.4f", cellB),
                "cell_c": String(format: "%.4f", cellC)
            ]
        )
    }

    private nonisolated static func extractCIFNumber(_ line: String) -> Double? {
        guard let valStr = line.components(separatedBy: .whitespaces).last else { return nil }
        // CIF numbers may have uncertainty in parentheses e.g. "5.4321(12)"
        let cleaned = valStr.components(separatedBy: "(").first ?? valStr
        return Double(cleaned)
    }

    private nonisolated static func multiplicity(h: Int, k: Int, l: Int) -> Int {
        let indices = [h, k, l].sorted()
        if indices[0] == 0 && indices[1] == 0 { return 6 }
        if indices[0] == 0 { return 24 }
        if indices[0] == indices[1] && indices[1] == indices[2] { return 8 }
        if indices[0] == indices[1] || indices[1] == indices[2] { return 24 }
        return 48
    }
}
