import Foundation

/// refractiveindex.info — optical constants (n, k) database.
/// Species array should contain material names (e.g. "Si", "SiO2", "Au", "Ag",
/// "TiO2", "GaAs"). Downloads CSV data and parses wavelength, n, k columns.
actor RefractiveIndexSource: TrainingDataSourceProtocol {

    /// GitHub raw base URL for the refractiveindex.info open database (CC0).
    /// The old `data_csv.php` endpoint returned HTTP 410 (Gone) as of early 2026.
    static let baseURL = "https://raw.githubusercontent.com/polyanskiy/refractiveindex.info-database/main/database/data/"

    /// Maps common material names to GitHub YAML file paths (relative to baseURL).
    /// Format: "{shelf}/{material}/nk/{author}.yml" for tabulated nk data.
    private nonisolated static let materialPaths: [String: String] = [
        "Si":      "main/Si/nk/Aspnes.yml",
        "SiO2":    "main/SiO2/nk/Franta.yml",
        "Au":      "main/Au/nk/Johnson.yml",
        "Ag":      "main/Ag/nk/Johnson.yml",
        "Al":      "main/Al/nk/Hagemann.yml",
        "Cu":      "main/Cu/nk/Johnson.yml",
        "TiO2":    "main/TiO2/nk/Devore-o.yml",
        "GaAs":    "main/GaAs/nk/Aspnes.yml",
        "Ge":      "main/Ge/nk/Aspnes.yml",
        "InP":     "main/InP/nk/Aspnes.yml",
        "ZnO":     "main/ZnO/nk/Bond-o.yml",
        "BK7":     "glass/optical/SCHOTT/nk/N-BK7.yml",
        "MgF2":    "main/MgF2/nk/Dodge-o.yml",
        "CaF2":    "main/CaF2/nk/Malitson.yml",
        "ZnSe":    "main/ZnSe/nk/Connolly.yml",
        "Al2O3":   "main/Al2O3/nk/Malitson-o.yml",
        "Diamond": "main/C/nk/Phillip.yml",
        "Water":   "main/H2O/nk/Hale.yml",
        "GaN":     "main/GaN/nk/Barker-o.yml",
        "ITO":     "other/mixed crystals/In2O3-SnO2/nk/Konig.yml"
    ]

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for material in species {
                    do {
                        guard let spectrum = try await self.fetchOpticalConstants(material: material) else {
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

    // MARK: - Optical Constants Fetch

    private func fetchOpticalConstants(material: String) async throws -> ReferenceSpectrum? {
        // Look up the known GitHub YAML path or construct one from a convention
        let relativePath: String
        if let known = Self.materialPaths[material] {
            relativePath = known
        } else {
            // Try a default nk path: main/{material}/nk/{material}.yml
            let encoded = material.addingPercentEncoding(
                withAllowedCharacters: .urlPathAllowed) ?? material
            relativePath = "main/\(encoded)/nk/\(encoded).yml"
        }

        let urlString = Self.baseURL + relativePath
        guard let url = URL(string: urlString) else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse,
              http.statusCode == 200 else { return nil }

        let text = String(decoding: data, as: UTF8.self)
        guard text.count > 20,
              !text.lowercased().contains("404:"),
              !text.lowercased().contains("not found") else { return nil }

        // GitHub serves YAML files — parse tabulated nk data
        if text.contains("type: tabulated") {
            let parsed = try RefractiveIndexYAMLParser.parse(text, material: material)
            // Convert wavelengths from um to nm for consistency
            let wlNm = parsed.wavelengths_um.map { $0 * 1000.0 }
            return ReferenceSpectrum(
                modality: .opticalConstants,
                sourceID: "refractiveindex_\(material.lowercased())",
                xValues: wlNm,
                yValues: parsed.n,
                metadata: [
                    "source": "refractiveindex.info (GitHub)",
                    "material": material,
                    "data_type": "nk",
                    "k_values": parsed.k.map { String(format: "%.6f", $0) }.joined(separator: ","),
                    "wavelength_unit": "nm"
                ]
            )
        }

        // Fallback: try CSV parsing in case a non-YAML response slips through
        let parsed = Self.parseCSV(text, material: material)
        guard !parsed.wavelengths.isEmpty else { return nil }

        return ReferenceSpectrum(
            modality: .opticalConstants,
            sourceID: "refractiveindex_\(material.lowercased())",
            xValues: parsed.wavelengths,
            yValues: parsed.n,
            metadata: [
                "source": "refractiveindex.info (GitHub)",
                "material": material,
                "data_type": "nk",
                "point_count": "\(parsed.wavelengths.count)",
                "wavelength_unit": "nm"
            ]
        )
    }

    // MARK: - CSV Parsing

    private struct OpticalCSV: Sendable {
        let wavelengths: [Double]  // nm
        let n: [Double]
        let k: [Double]
    }

    private nonisolated static func parseCSV(_ text: String, material: String) -> OpticalCSV {
        var wavelengths: [Double] = []
        var nValues: [Double] = []
        var kValues: [Double] = []

        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty,
                  !trimmed.hasPrefix("#"),
                  !trimmed.lowercased().hasPrefix("wl") else { continue }

            let parts = trimmed.components(separatedBy: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 2,
                  let wl = Double(parts[0]),
                  let n = Double(parts[1]) else { continue }

            // Wavelength may be in um — convert to nm if < 100
            let wlNm = wl < 100.0 ? wl * 1000.0 : wl
            wavelengths.append(wlNm)
            nValues.append(n)
            kValues.append(parts.count >= 3 ? (Double(parts[2]) ?? 0) : 0)
        }

        return OpticalCSV(wavelengths: wavelengths, n: nValues, k: kValues)
    }
}
