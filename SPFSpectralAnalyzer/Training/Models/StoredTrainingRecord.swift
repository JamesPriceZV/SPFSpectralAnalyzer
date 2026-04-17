import Foundation
import SwiftData

@Model
final class StoredTrainingRecord {
    var id: UUID
    var modalityRaw: String
    var sourceID: String
    var createdAt: Date
    var featuresData: Data
    var targetsJSON: [String: Double]
    var metadataJSON: [String: String]
    var isComputedLabel: Bool
    var computationMethod: String?

    init(from record: TrainingRecord) {
        self.id = record.id
        self.modalityRaw = record.modality.rawValue
        self.sourceID = record.sourceID
        self.createdAt = record.createdAt
        self.featuresData = record.features.withUnsafeBufferPointer { Data(buffer: $0) }
        self.targetsJSON = record.targets
        self.metadataJSON = record.metadata
        self.isComputedLabel = record.isComputedLabel
        self.computationMethod = record.computationMethod
    }
}
