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

    /// UUID of the associated `StoredFormulaCard`, if any.
    /// Plain UUID (not @Relationship) for CloudKit safety. Many datasets can share one card.
    var formulaCardID: UUID?

    /// Substrate plate type (ISO 24443): "pmma", "quartz", or "other".
    var plateType: String?

    /// Application quantity in mg, parsed from filename or manually entered.
    var applicationQuantityMg: Double?

    /// UV filter formulation category (see FormulationType enum for valid raw values).
    var formulationType: String?

    /// PMMA plate subtype: "moulded" or "sandblasted" (only meaningful when plateType == "pmma").
    var pmmaPlateSubtype: String?

    /// User-assigned post-irradiation override.
    /// - `nil`: Auto-detect from filename (default).
    /// - `true`: Manually marked as post-irradiation.
    /// - `false`: Manually marked as pre-irradiation.
    var isPostIrradiation: Bool?

    /// JPEG photo data captured from the camera analysis feature.
    @Attribute(.externalStorage)
    var cameraPhotoData: Data?

    /// JSON string of camera color analysis results.
    var cameraAnalysisJSON: String?

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
        instrumentID: UUID? = nil,
        plateType: String? = nil,
        applicationQuantityMg: Double? = nil,
        formulationType: String? = nil,
        pmmaPlateSubtype: String? = nil,
        formulaCardID: UUID? = nil,
        isPostIrradiation: Bool? = nil
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
        self.plateType = plateType
        self.applicationQuantityMg = applicationQuantityMg
        self.formulationType = formulationType
        self.pmmaPlateSubtype = pmmaPlateSubtype
        self.formulaCardID = formulaCardID
        self.isPostIrradiation = isPostIrradiation
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

    /// Typed substrate plate type.
    var substratePlateType: SubstratePlateType {
        get { plateType.flatMap { SubstratePlateType(rawValue: $0) } ?? .pmma }
        set { plateType = newValue.rawValue }
    }

    /// Typed formulation category.
    var formulationCategory: FormulationType {
        get { formulationType.flatMap { FormulationType(rawValue: $0) } ?? .unknown }
        set { formulationType = newValue.rawValue }
    }

    /// Typed PMMA plate subtype (only meaningful when plateType == "pmma").
    var pmmaSubtype: PMMAPlateSubtype {
        get { pmmaPlateSubtype.flatMap { PMMAPlateSubtype(rawValue: $0) } ?? .moulded }
        set { pmmaPlateSubtype = newValue.rawValue }
    }

    /// Resolves the effective post-irradiation status.
    /// Uses the manual override if set, otherwise auto-detects from the filename.
    var effectiveIsPostIrradiation: Bool {
        if let manual = isPostIrradiation { return manual }
        let lowered = fileName.lowercased()
        return lowered.contains("after incubation")
            || lowered.contains("post incubation")
            || lowered.contains("after incub")
    }

    /// Infer the spectral domain from the first stored spectrum's wavelength range.
    /// Returns nil if no spectra are stored or the domain cannot be determined.
    var inferredDomain: PINNDomain? {
        guard let firstSpectrum = spectraItems.first else { return nil }
        let xVals = firstSpectrum.xValues
        guard let minX = xVals.min(), let maxX = xVals.max() else { return nil }
        let range = maxX - minX

        // UV-Vis: typically 190-900nm
        if minX >= 190 && maxX <= 900 && range < 800 {
            return .uvVis
        }
        // FTIR: typically 400-4000 cm⁻¹
        if minX >= 400 && maxX >= 2000 {
            return .ftir
        }
        // NIR: 800-2500nm or 4000-12500 cm⁻¹
        if minX >= 800 && maxX <= 2500 {
            return .nir
        }
        // Raman: 100-4000 cm⁻¹ shift
        if minX >= 0 && maxX <= 4500 && range > 500 {
            return .raman
        }
        // Default to UV-Vis for this app's primary use case
        return .uvVis
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

