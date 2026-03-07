import Foundation
import SwiftData

@Model
final class StoredDataset {
    var id: UUID = UUID()
    var fileName: String = ""
    var sourcePath: String?
    var importedAt: Date = Date()
    var lastSyncedAt: Date?
    var fileHash: String?
    var fileData: Data?
    var metadataJSON: Data?
    var headerInfoData: Data?
    var skippedDataJSON: Data?
    var warningsJSON: Data?
    var isArchived: Bool = false
    var archivedAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \StoredSpectrum.dataset)
    var spectra: [StoredSpectrum]?

    var spectraItems: [StoredSpectrum] {
        get { spectra ?? [] }
        set { spectra = newValue }
    }

    init(
        id: UUID = UUID(),
        fileName: String,
        sourcePath: String?,
        importedAt: Date = Date(),
        lastSyncedAt: Date? = nil,
        fileHash: String?,
        fileData: Data?,
        metadataJSON: Data?,
        headerInfoData: Data?,
        skippedDataJSON: Data?,
        warningsJSON: Data?,
        spectra: [StoredSpectrum]? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.sourcePath = sourcePath
        self.importedAt = importedAt
        self.lastSyncedAt = lastSyncedAt
        self.fileHash = fileHash
        self.fileData = fileData
        self.metadataJSON = metadataJSON
        self.headerInfoData = headerInfoData
        self.skippedDataJSON = skippedDataJSON
        self.warningsJSON = warningsJSON
        self.spectra = spectra
        self.isArchived = isArchived
        self.archivedAt = archivedAt
    }

    var skippedDataSets: [String] {
        get { StoredDataset.decodeStringArray(from: skippedDataJSON) }
        set { skippedDataJSON = StoredDataset.encodeStringArray(newValue) }
    }

    var warnings: [String] {
        get { StoredDataset.decodeStringArray(from: warningsJSON) }
        set { warningsJSON = StoredDataset.encodeStringArray(newValue) }
    }

    private static func encodeStringArray(_ values: [String]) -> Data? {
        guard let data = try? JSONEncoder().encode(values) else { return nil }
        return data
    }

    private static func decodeStringArray(from data: Data?) -> [String] {
        guard let data, let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }
}

@Model
final class StoredSpectrum {
    var id: UUID = UUID()
    var datasetID: UUID = UUID()
    var name: String = ""
    var orderIndex: Int = 0
    var xData: Data = Data()
    var yData: Data = Data()
    var isInvalid: Bool = false
    var invalidReason: String?
    var lastSyncedAt: Date?

    @Relationship var dataset: StoredDataset?

    init(
        id: UUID = UUID(),
        datasetID: UUID,
        name: String,
        orderIndex: Int,
        xData: Data,
        yData: Data,
        isInvalid: Bool,
        invalidReason: String?,
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.datasetID = datasetID
        self.name = name
        self.orderIndex = orderIndex
        self.xData = xData
        self.yData = yData
        self.isInvalid = isInvalid
        self.invalidReason = invalidReason
        self.lastSyncedAt = lastSyncedAt
    }

    var xValues: [Double] { SpectrumBinaryCodec.decodeDoubles(from: xData) }
    var yValues: [Double] { SpectrumBinaryCodec.decodeDoubles(from: yData) }
}
