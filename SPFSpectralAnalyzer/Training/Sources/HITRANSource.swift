import Foundation

/// HITRAN molecular spectroscopic database — line-by-line absorption parameters.
/// Species array should contain molecule names (e.g. "H2O", "CO2", "O3", "CH4").
/// Downloads .par files and parses using HITRANParser.
actor HITRANSource: TrainingDataSourceProtocol {

    static let baseURL = "https://hitran.org/lbl/"

    /// HITRAN molecule IDs for common species.
    private nonisolated static let moleculeIDs: [String: Int] = [
        "H2O": 1, "CO2": 2, "O3": 3, "N2O": 4, "CO": 5,
        "CH4": 6, "O2": 7, "NO": 8, "SO2": 9, "NO2": 10,
        "NH3": 11, "HNO3": 12, "OH": 13, "HF": 14, "HCl": 15,
        "HBr": 16, "HI": 17, "ClO": 18, "OCS": 19, "H2CO": 20,
        "HOCl": 21, "N2": 22, "HCN": 23, "CH3Cl": 24, "H2O2": 25,
        "C2H2": 26, "C2H6": 27, "PH3": 28, "COF2": 29, "SF6": 30,
        "H2S": 31, "HCOOH": 32, "HO2": 33, "O": 34, "ClONO2": 35,
        "NO+": 36, "HOBr": 37, "C2H4": 38, "CH3OH": 39, "CH3Br": 40,
        "CH3CN": 41, "CF4": 42, "C4H2": 43, "HC3N": 44, "H2": 45,
        "CS": 46, "SO3": 47, "C2N2": 48, "COCl2": 49
    ]

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for molecule in species {
                    guard let molID = Self.moleculeIDs[molecule.uppercased()] ??
                            Self.moleculeIDs[molecule] else { continue }
                    do {
                        // Fetch line data from HITRAN data access API
                        let urlString = "https://hitran.org/lbl/api/?iso_ids_list=\(molID)1"
                            + "&numin=400&numax=4400&fixwidth=0"
                        guard let url = URL(string: urlString) else { continue }
                        let (data, response) = try await URLSession.shared.data(from: url)
                        guard let http = response as? HTTPURLResponse,
                              http.statusCode == 200,
                              data.count > 100 else { continue }

                        // Parse using the HITRAN .par parser
                        let lines = try HITRANParser.parse(data: data)
                        guard !lines.isEmpty else { continue }

                        // Extract wavenumbers and intensities
                        let wavenumbers = lines.map { $0.wavenumber }
                        let intensities = lines.map { $0.intensity }

                        // Normalize intensities to max = 1.0
                        let maxI = intensities.max() ?? 1.0
                        let normI = intensities.map { $0 / max(maxI, 1e-30) }

                        let spectrum = ReferenceSpectrum(
                            modality: .hitranMolecular,
                            sourceID: "hitran_\(molecule)_\(molID)",
                            xValues: wavenumbers,
                            yValues: normI,
                            metadata: [
                                "source": "HITRAN",
                                "molecule": molecule,
                                "molecule_id": "\(molID)",
                                "line_count": "\(lines.count)",
                                "wavenumber_range": "400-4400 cm-1"
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
}
