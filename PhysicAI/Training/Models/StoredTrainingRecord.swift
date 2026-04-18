import Foundation
import SwiftData

@Model
final class StoredTrainingRecord {
    var id: UUID = UUID()
    var modalityRaw: String = ""
    var sourceID: String = ""
    var createdAt: Date = Date()
    var featuresData: Data = Data()
    var targetsJSON: [String: Double] = [:]
    var metadataJSON: [String: String] = [:]
    var isComputedLabel: Bool = false
    var computationMethod: String?
    var qualityScore: Double = 1.0
    var annotationNotes: String? = nil
    var isExcluded: Bool = false

    init() {}

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
