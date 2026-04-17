import Foundation

/// Small Angle Scattering Biological Data Bank (sasbdb.org) — SAXS/SANS profiles.
/// Species array should contain SASBDB accession IDs (e.g. "SASDA52", "SASDB23").
actor SASBDBSource: TrainingDataSourceProtocol {

    static let baseURL = "https://www.sasbdb.org/rest-api/entry/"

    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error> {
        AsyncThrowingStream { continuation in
            Task {
                for accession in species {
                    do {
                        guard let spectrum = try await self.fetchSASBDBEntry(accession: accession) else {
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

    // MARK: - Entry Fetch

    private func fetchSASBDBEntry(accession: String) async throws -> ReferenceSpectrum? {
        // Fetch the metadata JSON from the REST API
        let metaURLString = Self.baseURL + accession + "/"
        guard let metaURL = URL(string: metaURLString) else { return nil }

        let (metaData, metaResp) = try await URLSession.shared.data(from: metaURL)
        guard let metaHTTP = metaResp as? HTTPURLResponse,
              metaHTTP.statusCode == 200 else { return nil }

        // Parse metadata for structural parameters
        let profile = try SASBDBParser.parseAPIResponse(metaData)

        // If the API response included scattering data, use it
        if !profile.q.isEmpty {
            return makeSpectrum(from: profile, accession: accession)
        }

        // Otherwise fetch the experimental .dat file directly
        let datURLString = "https://www.sasbdb.org/media/\(accession)/\(accession).dat"
        guard let datURL = URL(string: datURLString) else { return nil }

        let (datData, datResp) = try await URLSession.shared.data(from: datURL)
        guard let datHTTP = datResp as? HTTPURLResponse,
              datHTTP.statusCode == 200 else { return nil }

        let datText = String(decoding: datData, as: UTF8.self)
        let datProfile = SASBDBParser.parseDatFile(datText, accession: accession)
        guard !datProfile.q.isEmpty else { return nil }

        return makeSpectrum(from: datProfile, accession: accession)
    }

    // MARK: - Spectrum Construction

    private nonisolated func makeSpectrum(
        from profile: SASBDBParser.SASProfile,
        accession: String
    ) -> ReferenceSpectrum {
        // Log-transform intensity for better numerical stability
        let logI = profile.intensity.map { $0 > 0 ? log10($0) : -10.0 }

        return ReferenceSpectrum(
            modality: .saxs,
            sourceID: "sasbdb_\(accession)",
            xValues: profile.q,
            yValues: logI,
            metadata: [
                "source": "SASBDB",
                "accession": accession,
                "rg_nm": String(format: "%.2f", profile.rg_nm),
                "dmax_nm": String(format: "%.2f", profile.dmax_nm),
                "mw_kda": String(format: "%.1f", profile.mw_kda),
                "point_count": "\(profile.q.count)"
            ]
        )
    }
}
