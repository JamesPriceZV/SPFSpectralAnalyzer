import Foundation
import SwiftData

actor TrainingDataExporter {

    let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func export(modality: SpectralModality, to url: URL) async throws {
        let context = ModelContext(modelContainer)
        let modalityRaw = modality.rawValue
        let descriptor = FetchDescriptor<StoredTrainingRecord>(
            predicate: #Predicate { $0.modalityRaw == modalityRaw }
        )
        let records = try context.fetch(descriptor)
        guard !records.isEmpty else { throw ExportError.noRecords }

        let schema = ModalitySchemas.spec(for: modality)
        var csv = schema.featureLabels.joined(separator: ",")
        csv += "," + schema.targetLabels.joined(separator: ",") + "\n"

        for record in records {
            let featureStr = record.featuresData
                .withUnsafeBytes { ptr in
                    let bound = ptr.bindMemory(to: Float.self)
                    return bound.prefix(schema.featureCount)
                        .map { String($0) }
                        .joined(separator: ",")
                }
            let targetStr = schema.targetLabels.map { label in
                String(record.targetsJSON[label] ?? 0)
            }.joined(separator: ",")
            csv += featureStr + "," + targetStr + "\n"
        }

        try csv.write(to: url, atomically: true, encoding: .utf8)
    }

    func exportAll(to directory: URL) async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for modality in SpectralModality.allCases {
            let fileURL = directory.appendingPathComponent("\(modality.rawValue)_training.csv")
            try await export(modality: modality, to: fileURL)
        }
    }

    enum ExportError: Error {
        case noRecords
    }
}
