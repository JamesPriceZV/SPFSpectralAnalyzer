import Foundation

nonisolated enum SASBDBParser {

    struct SASProfile: Sendable {
        let accession: String
        let rg_nm: Double
        let dmax_nm: Double
        let mw_kda: Double
        let q: [Double]
        let intensity: [Double]
        let error: [Double]
    }

    static func parseAPIResponse(_ data: Data) throws -> SASProfile {
        struct Entry: Decodable {
            let code: String
            let rg: Double?
            let dmax: Double?
            let mw_kda: Double?
            let fits: [[Double]]?
        }
        let entry = try JSONDecoder().decode(Entry.self, from: data)
        let pts = entry.fits ?? []
        return SASProfile(
            accession: entry.code,
            rg_nm: entry.rg ?? 0,
            dmax_nm: entry.dmax ?? 0,
            mw_kda: entry.mw_kda ?? 0,
            q: pts.map { $0.count > 0 ? $0[0] : 0 },
            intensity: pts.map { $0.count > 1 ? $0[1] : 0 },
            error: pts.map { $0.count > 2 ? $0[2] : 0 })
    }

    static func parseDatFile(_ text: String, accession: String) -> SASProfile {
        var q: [Double] = [], I: [Double] = [], sig: [Double] = []
        for line in text.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }
            let parts = t.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if parts.count >= 3,
               let qv = Double(parts[0]), let iv = Double(parts[1]), let sv = Double(parts[2]),
               iv > 0 {
                q.append(qv); I.append(iv); sig.append(sv)
            }
        }
        return SASProfile(accession: accession, rg_nm: 0, dmax_nm: 0, mw_kda: 0,
                          q: q, intensity: I, error: sig)
    }
}
