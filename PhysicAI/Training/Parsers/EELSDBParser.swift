import Foundation

nonisolated enum EELSDBParser {

    struct EELSSpectrum: Sendable {
        let id: Int
        let element: String
        let edge: String
        let edgeOnsetEV: Double
        let energies: [Double]
        let intensities: [Double]
    }

    static func parseJSON(_ data: Data) throws -> [EELSSpectrum] {
        struct APIResult: Decodable {
            struct Entry: Decodable {
                let id: Int
                let title: String
                let edge: String?
                let onset: Double?
                let data: [[Double]]?
            }
            let results: [Entry]
        }
        let decoded = try JSONDecoder().decode(APIResult.self, from: data)
        return decoded.results.compactMap { entry in
            guard let pts = entry.data, pts.count >= 5 else { return nil }
            let energies = pts.map { $0[0] }
            let intensities = pts.map { $0.count > 1 ? $0[1] : 0 }
            let element = entry.title.components(separatedBy: " ").first ?? "?"
            return EELSSpectrum(
                id: entry.id, element: element, edge: entry.edge ?? "?",
                edgeOnsetEV: entry.onset ?? 0, energies: energies, intensities: intensities)
        }
    }
}
