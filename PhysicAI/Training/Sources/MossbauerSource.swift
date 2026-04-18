import Foundation

actor MossbauerSource {

    static let zenodoFilesURL = URL(string:
        "https://zenodo.org/api/records/6362337/files")!

    func fetchSpectraMetadata() async throws -> [[String: Any]] {
        let (data, _) = try await URLSession.shared.data(from: Self.zenodoFilesURL)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["entries"] as? [[String: Any]]
        else { return [] }
        return entries
    }

    func fetchSpectrum(from fileEntry: [String: Any]) async throws -> MossbauerParser.MossbauerSpectrum {
        guard let links = fileEntry["links"] as? [String: String],
              let selfLink = links["self"],
              let url = URL(string: selfLink) else {
            throw URLError(.badURL)
        }
        let (data, _) = try await URLSession.shared.data(from: url)
        return try MossbauerParser.parseJSON(data)
    }
}
