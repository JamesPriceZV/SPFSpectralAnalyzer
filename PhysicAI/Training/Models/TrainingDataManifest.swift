import Foundation

nonisolated struct TrainingDataManifest: Codable, Sendable {
    var version: String
    var generatedAt: Date
    var packages: [ModalityPackage]

    struct ModalityPackage: Codable, Sendable, Identifiable {
        var id: String          // SpectralModality.rawValue
        var version: String
        var recordCount: Int
        var downloadURL: String
        var sha256: String
        var sizeBytes: Int
        var physicsLaw: String
        var changelog: String

        var modality: SpectralModality? {
            SpectralModality(rawValue: id)
        }
    }
}
