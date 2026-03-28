import Foundation
import SwiftData

/// Classification role for a stored dataset.
enum DatasetRole: String, CaseIterable, Codable, Sendable {
    /// Reference dataset with a validated in-vivo SPF value.
    case reference
    /// Prototype sample under test.
    case prototype
}

/// Public SwiftData model for an imported spectral dataset.
///
/// Public API surface:
/// - public init(...) to construct datasets from other modules.
/// - public id to satisfy Identifiable on public @Model types (getter must be public).
/// - public fileName (read-only outside the module) for display/export.
/// - public spectraItems (read-only outside the module) to enumerate spectra.
///
/// All other properties are internal to encapsulate raw bytes/metadata and sync bookkeeping.
/// This keeps the API small and prevents accidental mutation from other modules while still
/// allowing read-only access to the essentials.
@Model
public final class StoredDataset {
    public var id: UUID = UUID()
    public internal(set) var fileName: String = ""
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
    /// ISO 23675 HDRS classification metadata (plate type, irradiation state, sample name, etc.)
    var hdrsMetadataJSON: Data?

    /// Dataset role: "reference" (known in-vivo SPF), "prototype" (sample under test), or nil (unclassified).
    var datasetRole: String?

    /// User-assigned validated in-vivo SPF value. Only meaningful when datasetRole == "reference".
    var knownInVivoSPF: Double?

    /// Persisted HDRS spectrum tags keyed by spectrum UUID, encoded as JSON.
    var hdrsTagsJSON: Data?

    /// UUID of the assigned `StoredInstrument`, if any.
    /// Stored as a plain UUID (not a @Relationship) to avoid CloudKit sync crash risk.
    var instrumentID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \StoredSpectrum.dataset)
    var spectra: [StoredSpectrum]?

    public internal(set) var spectraItems: [StoredSpectrum] {
        get { spectra ?? [] }
        set { spectra = newValue }
    }

    public init(
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
        archivedAt: Date? = nil,
        hdrsMetadataJSON: Data? = nil,
        datasetRole: String? = nil,
        knownInVivoSPF: Double? = nil,
        hdrsTagsJSON: Data? = nil,
        instrumentID: UUID? = nil
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
        self.hdrsMetadataJSON = hdrsMetadataJSON
        self.datasetRole = datasetRole
        self.knownInVivoSPF = knownInVivoSPF
        self.hdrsTagsJSON = hdrsTagsJSON
        self.instrumentID = instrumentID
    }

    var skippedDataSets: [String] {
        get { StoredDataset.decodeStringArray(from: skippedDataJSON) }
        set { skippedDataJSON = StoredDataset.encodeStringArray(newValue) }
    }

    var warnings: [String] {
        get { StoredDataset.decodeStringArray(from: warningsJSON) }
        set { warningsJSON = StoredDataset.encodeStringArray(newValue) }
    }

    /// Whether this dataset is a reference dataset with a known in-vivo SPF.
    var isReference: Bool { datasetRole == DatasetRole.reference.rawValue }

    /// Whether this dataset is explicitly classified as a prototype sample.
    var isPrototype: Bool { datasetRole == DatasetRole.prototype.rawValue }

    /// Decoded HDRS spectrum tags keyed by spectrum UUID.
    var hdrsSpectrumTags: [UUID: HDRSSpectrumTag] {
        get {
            guard let data = hdrsTagsJSON,
                  let tags = try? JSONDecoder().decode([UUID: HDRSSpectrumTag].self, from: data) else {
                return [:]
            }
            return tags
        }
        set {
            hdrsTagsJSON = try? JSONEncoder().encode(newValue)
        }
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

/// Public SwiftData model for a single spectrum within a dataset.
///
/// Public API surface:
/// - public init(...) to construct spectra from other modules.
/// - public id to satisfy Identifiable on public @Model types.
/// - public name and orderIndex (read-only outside the module) for labeling/ordering.
/// - public xValues and yValues expose decoded doubles for read-only access.
///
/// Raw storage (xData/yData), relationship links, and sync flags remain internal to encapsulate
/// persistence details and avoid accidental mutation from other modules.
@Model
public final class StoredSpectrum {
    public var id: UUID = UUID()
    var datasetID: UUID = UUID()
    public internal(set) var name: String = ""
    public internal(set) var orderIndex: Int = 0
    var xData: Data = Data()
    var yData: Data = Data()
    var isInvalid: Bool = false
    var invalidReason: String?
    var lastSyncedAt: Date?

    @Relationship
    var dataset: StoredDataset?

    public init(
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

    public var xValues: [Double] { SpectrumBinaryCodec.decodeDoubles(from: xData) }
    public var yValues: [Double] { SpectrumBinaryCodec.decodeDoubles(from: yData) }
}

