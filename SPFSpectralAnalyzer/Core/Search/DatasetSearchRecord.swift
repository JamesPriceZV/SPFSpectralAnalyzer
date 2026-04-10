import Foundation

/// Pre-computed, snapshot-safe search record for a `StoredDataset`.
///
/// Built once when the searchable text cache is populated, from fresh `@Query` results.
/// Does not reference SwiftData model objects, so it is safe to access during rapid
/// search filtering and UI row rendering even while CloudKit sync is active.
///
/// This struct captures **all** display fields needed by `storedDatasetRow`,
/// `archivedDatasetRow`, `storedDatasetPickerRow`, and `rebuildReferenceIndices`
/// so that those code paths never touch SwiftData model properties directly.
struct DatasetSearchRecord: SearchableRecord {
    let fileName: String
    let datasetRole: String?          // "reference", "prototype", or nil
    let knownInVivoSPF: Double?
    let importedAt: Date
    let fileHash: String?
    let sourcePath: String?
    let dataSetNames: [String]
    let directoryEntryNames: [String]
    let spectrumCount: Int
    let memo: String?
    let sourceInstrumentText: String?
    /// UUID of the assigned `StoredInstrument`, if any.
    let instrumentID: UUID?

    /// ISO 24443 substrate plate type raw value.
    let plateType: String?
    /// Application quantity in mg.
    let applicationQuantityMg: Double?
    /// Formulation category raw value.
    let formulationType: String?
    /// PMMA plate subtype raw value ("moulded" or "sandblasted").
    let pmmaPlateSubtype: String?
    /// UUID of the associated `StoredFormulaCard`, if any.
    let formulaCardID: UUID?
    /// User-assigned post-irradiation override (nil = auto-detect from filename).
    let isPostIrradiation: Bool?

    // MARK: - Display Fields (used by row views)

    /// Number of valid (non-invalid) spectra in the dataset.
    let validSpectrumCount: Int
    /// Whether this dataset is archived.
    let isArchived: Bool
    /// When the dataset was archived (nil if not archived).
    let archivedAt: Date?
    /// Whether this dataset has a camera photo attached.
    let hasCameraPhoto: Bool

    /// Pre-computed lowercased concatenation of all text fields for unqualified search.
    let allText: String

    init(
        fileName: String,
        datasetRole: String?,
        knownInVivoSPF: Double?,
        importedAt: Date,
        fileHash: String?,
        sourcePath: String?,
        dataSetNames: [String],
        directoryEntryNames: [String],
        spectrumCount: Int,
        memo: String?,
        sourceInstrumentText: String?,
        instrumentID: UUID? = nil,
        validSpectrumCount: Int? = nil,
        isArchived: Bool = false,
        archivedAt: Date? = nil,
        plateType: String? = nil,
        applicationQuantityMg: Double? = nil,
        formulationType: String? = nil,
        pmmaPlateSubtype: String? = nil,
        formulaCardID: UUID? = nil,
        hasCameraPhoto: Bool = false,
        isPostIrradiation: Bool? = nil
    ) {
        self.fileName = fileName
        self.datasetRole = datasetRole
        self.knownInVivoSPF = knownInVivoSPF
        self.importedAt = importedAt
        self.fileHash = fileHash
        self.sourcePath = sourcePath
        self.dataSetNames = dataSetNames
        self.directoryEntryNames = directoryEntryNames
        self.spectrumCount = spectrumCount
        self.memo = memo
        self.sourceInstrumentText = sourceInstrumentText
        self.instrumentID = instrumentID
        self.validSpectrumCount = validSpectrumCount ?? spectrumCount
        self.isArchived = isArchived
        self.archivedAt = archivedAt
        self.plateType = plateType
        self.applicationQuantityMg = applicationQuantityMg
        self.formulationType = formulationType
        self.pmmaPlateSubtype = pmmaPlateSubtype
        self.formulaCardID = formulaCardID
        self.hasCameraPhoto = hasCameraPhoto
        self.isPostIrradiation = isPostIrradiation

        // Build allText once for fast unqualified search
        var parts: [String] = []
        parts.append(fileName.lowercased())
        parts.append(contentsOf: dataSetNames.map { $0.lowercased() })
        parts.append(contentsOf: directoryEntryNames.map { $0.lowercased() })
        if let hash = fileHash { parts.append(hash.lowercased()) }
        if let path = sourcePath { parts.append(path.lowercased()) }
        if let memo, !memo.isEmpty { parts.append(memo.lowercased()) }
        if let inst = sourceInstrumentText, !inst.isEmpty { parts.append(inst.lowercased()) }
        if let role = datasetRole { parts.append(role.lowercased()) }
        self.allText = parts.joined(separator: "\n")
    }

    // MARK: - Convenience

    var isReference: Bool { datasetRole == DatasetRole.reference.rawValue }
    var isPrototype: Bool { datasetRole == DatasetRole.prototype.rawValue }

    /// Resolves the effective post-irradiation status.
    /// Uses the manual override if set, otherwise auto-detects from the filename.
    var effectiveIsPostIrradiation: Bool {
        if let manual = isPostIrradiation { return manual }
        return FilenameMetadataParser.parse(filename: fileName).isPostIrradiation
    }

    /// Returns a copy with only the role and SPF fields changed, preserving all other data.
    /// Used by `setDatasetRole()` to update the cache without reading any model properties.
    func patching(datasetRole: String?, knownInVivoSPF: Double?) -> DatasetSearchRecord {
        DatasetSearchRecord(
            fileName: self.fileName,
            datasetRole: datasetRole,
            knownInVivoSPF: knownInVivoSPF,
            importedAt: self.importedAt,
            fileHash: self.fileHash,
            sourcePath: self.sourcePath,
            dataSetNames: self.dataSetNames,
            directoryEntryNames: self.directoryEntryNames,
            spectrumCount: self.spectrumCount,
            memo: self.memo,
            sourceInstrumentText: self.sourceInstrumentText,
            instrumentID: self.instrumentID,
            validSpectrumCount: self.validSpectrumCount,
            isArchived: self.isArchived,
            archivedAt: self.archivedAt,
            plateType: self.plateType,
            applicationQuantityMg: self.applicationQuantityMg,
            formulationType: self.formulationType,
            pmmaPlateSubtype: self.pmmaPlateSubtype,
            formulaCardID: self.formulaCardID,
            isPostIrradiation: self.isPostIrradiation
        )
    }

    func patching(instrumentID: UUID?) -> DatasetSearchRecord {
        DatasetSearchRecord(
            fileName: self.fileName,
            datasetRole: self.datasetRole,
            knownInVivoSPF: self.knownInVivoSPF,
            importedAt: self.importedAt,
            fileHash: self.fileHash,
            sourcePath: self.sourcePath,
            dataSetNames: self.dataSetNames,
            directoryEntryNames: self.directoryEntryNames,
            spectrumCount: self.spectrumCount,
            memo: self.memo,
            sourceInstrumentText: self.sourceInstrumentText,
            instrumentID: instrumentID,
            validSpectrumCount: self.validSpectrumCount,
            isArchived: self.isArchived,
            archivedAt: self.archivedAt,
            plateType: self.plateType,
            applicationQuantityMg: self.applicationQuantityMg,
            formulationType: self.formulationType,
            pmmaPlateSubtype: self.pmmaPlateSubtype,
            formulaCardID: self.formulaCardID,
            isPostIrradiation: self.isPostIrradiation
        )
    }

    func patching(formulaCardID: UUID?) -> DatasetSearchRecord {
        DatasetSearchRecord(
            fileName: self.fileName,
            datasetRole: self.datasetRole,
            knownInVivoSPF: self.knownInVivoSPF,
            importedAt: self.importedAt,
            fileHash: self.fileHash,
            sourcePath: self.sourcePath,
            dataSetNames: self.dataSetNames,
            directoryEntryNames: self.directoryEntryNames,
            spectrumCount: self.spectrumCount,
            memo: self.memo,
            sourceInstrumentText: self.sourceInstrumentText,
            instrumentID: self.instrumentID,
            validSpectrumCount: self.validSpectrumCount,
            isArchived: self.isArchived,
            archivedAt: self.archivedAt,
            plateType: self.plateType,
            applicationQuantityMg: self.applicationQuantityMg,
            formulationType: self.formulationType,
            pmmaPlateSubtype: self.pmmaPlateSubtype,
            formulaCardID: formulaCardID,
            isPostIrradiation: self.isPostIrradiation
        )
    }

    func patching(isPostIrradiation: Bool?) -> DatasetSearchRecord {
        DatasetSearchRecord(
            fileName: self.fileName,
            datasetRole: self.datasetRole,
            knownInVivoSPF: self.knownInVivoSPF,
            importedAt: self.importedAt,
            fileHash: self.fileHash,
            sourcePath: self.sourcePath,
            dataSetNames: self.dataSetNames,
            directoryEntryNames: self.directoryEntryNames,
            spectrumCount: self.spectrumCount,
            memo: self.memo,
            sourceInstrumentText: self.sourceInstrumentText,
            instrumentID: self.instrumentID,
            validSpectrumCount: self.validSpectrumCount,
            isArchived: self.isArchived,
            archivedAt: self.archivedAt,
            plateType: self.plateType,
            applicationQuantityMg: self.applicationQuantityMg,
            formulationType: self.formulationType,
            pmmaPlateSubtype: self.pmmaPlateSubtype,
            formulaCardID: self.formulaCardID,
            isPostIrradiation: isPostIrradiation
        )
    }

    // MARK: - SearchableRecord

    func values(for field: SearchField) -> [String]? {
        switch field {
        case .name, .file:
            return [fileName]
        case .role:
            return [datasetRole ?? "none"]
        case .spf:
            if let spf = knownInVivoSPF { return [String(spf)] }
            return nil
        case .date:
            return nil // handled by dateValue(for:)
        case .spectra:
            return nil // handled by numericValue(for:)
        case .memo:
            if let memo, !memo.isEmpty { return [memo] }
            return nil
        case .instrument:
            if let inst = sourceInstrumentText, !inst.isEmpty { return [inst] }
            return nil
        case .hash:
            if let hash = fileHash { return [hash] }
            return nil
        case .path:
            if let path = sourcePath { return [path] }
            return nil
        // Spectrum-only fields: not applicable to datasets
        case .tag, .plate, .irr, .sample:
            return nil
        }
    }

    func numericValue(for field: SearchField) -> Double? {
        switch field {
        case .spf:     return knownInVivoSPF
        case .spectra: return Double(spectrumCount)
        default:       return nil
        }
    }

    func dateValue(for field: SearchField) -> Date? {
        switch field {
        case .date: return importedAt
        default:    return nil
        }
    }
}
