import Foundation
import SwiftUI
import SwiftData
import Observation
import CryptoKit

// MARK: - Dataset Tab

enum DatasetTab: String, CaseIterable, Identifiable {
    case samples
    case references
    case archived

    var id: String { rawValue }
}

@MainActor @Observable
final class DatasetViewModel {

    // MARK: - Cross-ViewModel References

    var analysis: AnalysisViewModel
    var modelContext: ModelContext?
    var dataStoreController: DataStoreController?

    /// Called after spectra are loaded so the view can switch to .analysis mode.
    var onImportComplete: (() -> Void)?
    /// Called after spectra load to update the AI token estimate.
    var onSpectraLoaded: (() -> Void)?

    // MARK: - Import State

    var showImporter = false
    var appendOnImport = false
    var showStoredDatasetPicker = false

    // MARK: - Dataset Selection

    var datasetTab: DatasetTab = .samples

    /// Persists selections to disk on every mutation so they survive relaunch.
    var selectedStoredDatasetIDs: Set<UUID> {
        get { _selectedStoredDatasetIDs }
        set {
            _selectedStoredDatasetIDs = newValue
            Self.writeSelectedDatasetIDs(newValue)
        }
    }
    private var _selectedStoredDatasetIDs: Set<UUID> = []
    var storedDatasetPickerSelection: Set<UUID> = []
    var datasetDetailPopoverID: UUID?
    var datasetSearchText = ""
    var showDatasetSearchHelp = false

    // MARK: - Archive State

    var showArchivedDatasetSheet = false
    var archivedDatasetSelection: Set<UUID> = []
    var archivedSearchText = ""
    var showArchivedSearchHelp = false
    var showArchiveConfirmation = false
    var pendingArchiveDatasetIDs: Set<UUID> = []

    // MARK: - Delete State

    var pendingPermanentDeleteIDs: Set<UUID> = []
    var showPermanentDeleteSheet = false
    /// IDs pending direct permanent deletion from the active (non-archived) list.
    var pendingDirectDeleteIDs: Set<UUID> = []
    var showDirectDeleteConfirmation = false

    // MARK: - Duplicate Cleanup

    var showDuplicateCleanupConfirm = false
    var duplicateCleanupMessage = ""
    var duplicateCleanupTargetIDs: Set<UUID> = []

    // MARK: - Dataset Role Assignment

    var showReferenceSpfSheet = false
    var showSamplePlateTypeSheet = false
    var pendingRoleDatasetID: UUID?
    var pendingKnownSPF: Double = 30.0
    var pendingPlateType: SubstratePlateType = .pmma
    var pendingApplicationQuantityMg: Double? = nil
    var pendingFormulationType: FormulationType = .unknown
    var pendingPMMASubtype: PMMAPlateSubtype = .moulded
    var pendingHDRSPlateType: HDRSPlateType = .moulded
    var pendingFormulaCardID: UUID?
    /// nil = auto-detect, true = post-irradiation, false = pre-irradiation
    var pendingIrradiationOverride: Bool?

    // MARK: - Formula Card State
    var showFormulaCardImporter = false
    var showFormulaCardDetail = false
    var selectedFormulaCardID: UUID?
    /// Cache of all formula cards for picker and display.
    var formulaCards: [StoredFormulaCard] = []

    // MARK: - Data Version (triggers re-fetch in ContentView after local mutations)
    var dataVersion: Int = 0

    // MARK: - Instrument Assignment State
    var showAssignInstrumentSheet = false
    var pendingInstrumentAssignDatasetID: UUID?
    /// Cache of instrument display names keyed by instrument UUID.
    var instrumentCache: [UUID: String] = [:]

    // MARK: - Reference Filtering

    /// Dataset IDs the user has manually excluded from reference calibration.
    /// Synced from @AppStorage on ContentView at launch and on user changes.
    var excludedReferenceDatasetIDs: Set<UUID> = []

    // MARK: - Session Persistence Key

    private static let sessionDatasetIDsKey = "lastSessionDatasetIDs"

    static let storedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    // MARK: - Init

    init(analysis: AnalysisViewModel) {
        self.analysis = analysis
    }

    // MARK: - Computed Properties

    var effectivePermanentDeleteIDs: Set<UUID> {
        pendingPermanentDeleteIDs.isEmpty ? archivedDatasetSelection : pendingPermanentDeleteIDs
    }

    func archiveConfirmationTitle(storedDatasets: [StoredDataset]) -> String {
        let count = pendingArchiveDatasetIDs.count
        return count == 1 ? "Archive Stored Dataset?" : "Archive \(count) Stored Datasets?"
    }

    func archiveConfirmationMessage(storedDatasets: [StoredDataset]) -> String {
        let datasets = storedDatasets.filter { pendingArchiveDatasetIDs.contains($0.id) }
        let preview = datasetNamePreview(datasets)
        let base = "Archived datasets can be restored from the Archived Datasets window."
        if preview.isEmpty {
            return base
        }
        return "\(base)\n\n\(preview)"
    }

    func permanentDeleteConfirmationTitle(archivedDatasets: [StoredDataset]) -> String {
        let count = effectivePermanentDeleteIDs.count
        return count == 1 ? "Delete Archived Dataset?" : "Delete \(count) Archived Datasets?"
    }

    func permanentDeleteConfirmationMessage(archivedDatasets: [StoredDataset]) -> String {
        let datasets = archivedDatasets.filter { effectivePermanentDeleteIDs.contains($0.id) }
        let preview = datasetNamePreview(datasets)
        let base = "This permanently deletes the archived datasets and cannot be undone."
        if preview.isEmpty {
            return base
        }
        return "\(base)\n\n\(preview)"
    }

    /// Cached search records keyed by dataset ID to avoid accessing SwiftData model
    /// properties during rapid search filtering and UI rendering. CloudKit sync can
    /// invalidate model objects mid-iteration, causing a weak-reference fault (`brk #0x1`).
    ///
    /// **All** UI code paths that display dataset properties (row views, context menus,
    /// reference index rebuilds) must read from this cache instead of touching the model.
    private(set) var searchableRecordCache: [UUID: DatasetSearchRecord] = [:]
    /// The set of dataset IDs present when the cache was last rebuilt.
    private var cachedDatasetIDs: Set<UUID> = []

    // MARK: - Debounced Cache Rebuild Tasks

    /// Debounce task for coalescing rapid `@Query` refreshes triggered by CloudKit sync.
    private var cacheRebuildTask: Task<Void, Never>?
    private var archivedCacheRebuildTask: Task<Void, Never>?

    /// Debounced wrapper around `updateSearchableTextCache`. Coalesces rapid CloudKit-triggered
    /// `@Query` refreshes so the cache is only rebuilt once per quiet period.
    ///
    /// When CloudKit sync is active, the delay is extended to 3 seconds to allow the
    /// sync cycle to settle before we touch any model properties. Accessing model
    /// objects while `NSPersistentCloudKitContainer` is importing/exporting can hit
    /// an internal SwiftData precondition (`swift_weakLoadStrong` → `brk #0x1`)
    /// that cannot be caught.
    private var cacheRebuildSyncRetries = 0

    func debouncedUpdateSearchableTextCache(from storedDatasets: [StoredDataset]) {
        cacheRebuildTask?.cancel()
        cacheRebuildTask = Task { @MainActor [weak self] in
            let syncActive = UserDefaults.standard.bool(forKey: "icloudSyncInProgress")
            let delay: UInt64 = syncActive ? 2_000_000_000 : 50_000_000 // 2s during sync, 50ms otherwise
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }

            // Re-check sync state after the delay. If still syncing, retry up to
            // 3 times then proceed anyway — the ObjCExceptionCatcher in buildSearchRecord
            // protects against NSExceptions from faulted objects.
            let stillSyncing = UserDefaults.standard.bool(forKey: "icloudSyncInProgress")
            if stillSyncing && self.cacheRebuildSyncRetries < 3 {
                self.cacheRebuildSyncRetries += 1
                self.debouncedUpdateSearchableTextCache(from: storedDatasets)
                return
            }

            self.cacheRebuildSyncRetries = 0
            self.updateSearchableTextCache(from: storedDatasets)
        }
    }

    private var archivedCacheRebuildSyncRetries = 0

    /// Debounced wrapper around `updateArchivedSearchableTextCache`.
    func debouncedUpdateArchivedSearchableTextCache(from archivedDatasets: [StoredDataset]) {
        archivedCacheRebuildTask?.cancel()
        archivedCacheRebuildTask = Task { @MainActor [weak self] in
            let syncActive = UserDefaults.standard.bool(forKey: "icloudSyncInProgress")
            let delay: UInt64 = syncActive ? 2_000_000_000 : 50_000_000
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled, let self else { return }

            let stillSyncing = UserDefaults.standard.bool(forKey: "icloudSyncInProgress")
            if stillSyncing && self.archivedCacheRebuildSyncRetries < 3 {
                self.archivedCacheRebuildSyncRetries += 1
                self.debouncedUpdateArchivedSearchableTextCache(from: archivedDatasets)
                return
            }

            self.archivedCacheRebuildSyncRetries = 0
            self.updateArchivedSearchableTextCache(from: archivedDatasets)
        }
    }

    /// Incrementally updates the searchable record cache from the given datasets.
    ///
    /// Only builds records for datasets that are **new** (not yet cached). Existing
    /// entries are preserved and stale entries (no longer in `storedDatasets`) are pruned.
    /// This minimizes the number of SwiftData model property accesses during CloudKit sync
    /// activity, where touching an invalidated model object crashes with `brk #0x1`.
    func updateSearchableTextCache(from storedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        // Re-fetch non-archived datasets through the store coordinator —
        // @Query results passed via storedDatasets may contain objects
        // invalidated by CloudKit sync, causing brk #0x1 on property access.
        let predicate = #Predicate<StoredDataset> { !$0.isArchived }
        let freshDatasets: [StoredDataset]
        do {
            freshDatasets = try ctx.fetch(FetchDescriptor<StoredDataset>(predicate: predicate))
        } catch { return }
        let currentIDs = Set(freshDatasets.map { $0.id })
        guard currentIDs != cachedDatasetIDs else { return }

        // Only build records for IDs we haven't seen before
        let newIDs = currentIDs.subtracting(cachedDatasetIDs)
        let removedIDs = cachedDatasetIDs.subtracting(currentIDs)

        // Prune removed entries
        for id in removedIDs {
            searchableRecordCache.removeValue(forKey: id)
        }

        // Build records for newly appeared datasets only
        if !newIDs.isEmpty {
            let datasetsToProcess = freshDatasets.filter { newIDs.contains($0.id) }
            // Batch spectrum counts in two queries instead of 2 per dataset,
            // dramatically reducing SwiftData round-trips for large libraries.
            let spectrumCounts = batchSpectrumCounts(for: newIDs, context: ctx)
            for dataset in datasetsToProcess {
                if let record = buildSearchRecord(for: dataset, spectrumCounts: spectrumCounts) {
                    searchableRecordCache[dataset.id] = record
                }
            }
        }

        cachedDatasetIDs = currentIDs
    }

    /// Fetches total and valid spectrum counts for a batch of dataset IDs in bulk.
    /// Returns a dictionary mapping dataset ID → (total, valid).
    private func batchSpectrumCounts(
        for datasetIDs: Set<UUID>,
        context: ModelContext
    ) -> [UUID: (total: Int, valid: Int)] {
        // Fetch all spectra for the given dataset IDs in one query
        let allSpectra: [StoredSpectrum]
        do {
            allSpectra = try context.fetch(FetchDescriptor<StoredSpectrum>())
        } catch {
            return [:]
        }
        var result: [UUID: (total: Int, valid: Int)] = [:]
        for spectrum in allSpectra {
            guard datasetIDs.contains(spectrum.datasetID) else { continue }
            var entry = result[spectrum.datasetID, default: (total: 0, valid: 0)]
            entry.total += 1
            if !spectrum.isInvalid {
                entry.valid += 1
            }
            result[spectrum.datasetID] = entry
        }
        return result
    }

    /// Patches specific fields on an existing cache entry without reading any model properties.
    /// Used by `setDatasetRole()` to update the cache safely during CloudKit sync.
    func patchCacheEntry(for datasetID: UUID, datasetRole: String?, knownInVivoSPF: Double?) {
        guard let existing = searchableRecordCache[datasetID] else { return }
        searchableRecordCache[datasetID] = existing.patching(
            datasetRole: datasetRole,
            knownInVivoSPF: knownInVivoSPF
        )
    }

    func filteredStoredDatasets(from storedDatasets: [StoredDataset]) -> [StoredDataset] {
        let query = SearchQuery.parse(datasetSearchText)
        guard !query.isEmpty else { return storedDatasets }
        return storedDatasets.filter { dataset in
            guard let record = searchableRecordCache[dataset.id] else { return true }
            return query.matches(record)
        }
    }

    /// Returns filtered dataset IDs using only the cache — safe against
    /// CloudKit sync invalidating SwiftData model objects mid-render.
    func filteredDatasetIDs(from ids: [UUID]) -> [UUID] {
        let query = SearchQuery.parse(datasetSearchText)
        guard !query.isEmpty else { return ids }
        return ids.filter { id in
            guard let record = searchableRecordCache[id] else { return true }
            return query.matches(record)
        }
    }

    /// Cached search records for archived datasets.
    private(set) var archivedSearchableRecordCache: [UUID: DatasetSearchRecord] = [:]
    private var cachedArchivedDatasetIDs: Set<UUID> = []

    /// Incrementally updates the archived searchable record cache.
    func updateArchivedSearchableTextCache(from archivedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        // Re-fetch archived datasets through the store coordinator —
        // @Query results may contain objects invalidated by CloudKit sync.
        let predicate = #Predicate<StoredDataset> { $0.isArchived }
        let freshDatasets: [StoredDataset]
        do {
            freshDatasets = try ctx.fetch(FetchDescriptor<StoredDataset>(predicate: predicate))
        } catch { return }
        let currentIDs = Set(freshDatasets.map { $0.id })
        guard currentIDs != cachedArchivedDatasetIDs else { return }

        let newIDs = currentIDs.subtracting(cachedArchivedDatasetIDs)
        let removedIDs = cachedArchivedDatasetIDs.subtracting(currentIDs)

        for id in removedIDs {
            archivedSearchableRecordCache.removeValue(forKey: id)
        }

        if !newIDs.isEmpty {
            let datasetsToProcess = freshDatasets.filter { newIDs.contains($0.id) }
            let spectrumCounts = batchSpectrumCounts(for: newIDs, context: ctx)
            for dataset in datasetsToProcess {
                if let record = buildSearchRecord(for: dataset, spectrumCounts: spectrumCounts) {
                    archivedSearchableRecordCache[dataset.id] = record
                }
            }
        }

        cachedArchivedDatasetIDs = currentIDs
    }

    func filteredArchivedDatasets(from archivedDatasets: [StoredDataset]) -> [StoredDataset] {
        let query = SearchQuery.parse(archivedSearchText)
        guard !query.isEmpty else { return archivedDatasets }
        return archivedDatasets.filter { dataset in
            guard let record = archivedSearchableRecordCache[dataset.id] else { return true }
            return query.matches(record)
        }
    }

    /// Returns filtered archived dataset IDs using only the cache — safe against
    /// CloudKit sync invalidating SwiftData model objects mid-render.
    func filteredArchivedDatasetIDs(from ids: [UUID]) -> [UUID] {
        let query = SearchQuery.parse(archivedSearchText)
        guard !query.isEmpty else { return ids }
        return ids.filter { id in
            guard let record = archivedSearchableRecordCache[id] else { return true }
            return query.matches(record)
        }
    }

    /// Build a `DatasetSearchRecord` from a live `StoredDataset`.
    ///
    /// Returns nil if the model's context has been invalidated by CloudKit sync,
    /// or if any property access triggers a fault on a deallocated backing object.
    ///
    /// Spectrum counts are obtained via a `FetchDescriptor` query instead of
    /// traversing the `spectraItems` relationship. Relationship traversal loads all
    /// spectrum objects into memory and can trigger `swift_weakLoadStrong → brk #0x1`
    /// if CloudKit sync has invalidated the backing store. A predicate-based fetch
    /// goes through the coordinator which handles concurrent access safely.
    private func buildSearchRecord(
        for dataset: StoredDataset,
        spectrumCounts: [UUID: (total: Int, valid: Int)]? = nil
    ) -> DatasetSearchRecord? {
        guard let ctx = modelContext else { return nil }

        // Re-fetch the dataset through a predicate query to get a valid object.
        // The @Query-provided reference may be invalidated by CloudKit sync between
        // delivery and property access. Predicate fetches go through the store
        // coordinator which returns nil for deleted rows instead of trapping with
        // _SD_get_current_context_tsd → brk #0x1.
        let dsID = dataset.id
        let dsPredicate = #Predicate<StoredDataset> { $0.id == dsID }
        guard let fresh = (try? ctx.fetch(FetchDescriptor<StoredDataset>(predicate: dsPredicate)))?.first else { return nil }

        // Use pre-computed counts if available (batch path), otherwise query per-dataset
        let spectrumCount: Int
        let validSpectrumCount: Int
        if let counts = spectrumCounts?[dsID] {
            spectrumCount = counts.total
            validSpectrumCount = counts.valid
        } else {
            let predicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
            let totalDescriptor = FetchDescriptor<StoredSpectrum>(predicate: predicate)
            let validPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID && !$0.isInvalid }
            let validDescriptor = FetchDescriptor<StoredSpectrum>(predicate: validPredicate)
            spectrumCount = (try? ctx.fetchCount(totalDescriptor)) ?? 0
            validSpectrumCount = (try? ctx.fetchCount(validDescriptor)) ?? 0
        }

        var result: DatasetSearchRecord?
        do {
            try ObjCExceptionCatcher.try {
                let metadata = DatasetPersistenceService.decodedMetadata(for: fresh)
                let header = metadata?.mainHeader
                result = DatasetSearchRecord(
                    fileName: fresh.fileName,
                    datasetRole: fresh.datasetRole,
                    knownInVivoSPF: fresh.knownInVivoSPF,
                    importedAt: fresh.importedAt,
                    fileHash: fresh.fileHash,
                    sourcePath: fresh.sourcePath,
                    dataSetNames: metadata?.dataSetNames ?? [],
                    directoryEntryNames: metadata?.directoryEntryNames ?? [],
                    spectrumCount: spectrumCount,
                    memo: header?.memo,
                    sourceInstrumentText: header?.sourceInstrumentText,
                    instrumentID: fresh.instrumentID,
                    validSpectrumCount: validSpectrumCount,
                    isArchived: fresh.isArchived,
                    archivedAt: fresh.archivedAt,
                    plateType: fresh.plateType,
                    applicationQuantityMg: fresh.applicationQuantityMg,
                    formulationType: fresh.formulationType,
                    pmmaPlateSubtype: fresh.pmmaPlateSubtype,
                    formulaCardID: fresh.formulaCardID,
                    hasCameraPhoto: fresh.cameraPhotoData != nil,
                    isPostIrradiation: fresh.isPostIrradiation
                )
            }
        } catch {
            Instrumentation.log(
                "buildSearchRecord caught NSException",
                area: .processing,
                level: .error,
                details: "datasetID=\(dsID) error=\(error.localizedDescription)"
            )
            return nil
        }
        return result
    }

    // MARK: - Dataset Helpers

    func decodedMetadata(for dataset: StoredDataset) -> ShimadzuSPCMetadata? {
        DatasetPersistenceService.decodedMetadata(for: dataset)
    }

    func datasetUniquenessKey(fileHash: String?, sourcePath: String?) -> String? {
        DatasetPersistenceService.datasetUniquenessKey(fileHash: fileHash, sourcePath: sourcePath)
    }

    func datasetNamePreview(_ datasets: [StoredDataset]) -> String {
        guard !datasets.isEmpty else { return "" }
        // Read filenames from cache only — never fall back to model properties
        // which can be invalidated by CloudKit sync.
        let preview = datasets.lazy.prefix(3).map { dataset -> String in
            if let record = self.searchableRecordCache[dataset.id] ?? self.archivedSearchableRecordCache[dataset.id] {
                return record.fileName
            }
            return dataset.id.uuidString
        }.joined(separator: ", ")
        let remainder = datasets.count - 3
        if remainder > 0 {
            return "\(preview) (+\(remainder) more)"
        }
        return preview
    }

    func sha256Hex(_ data: Data) -> String {
        DatasetPersistenceService.sha256Hex(data)
    }

    // MARK: - Import & Load

    func handleImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            Instrumentation.log("Import selection confirmed", area: .uiInteraction, level: .info, details: "files=\(urls.count)")
            let shouldAppend = appendOnImport
            appendOnImport = false
            Task { await loadSpectra(from: urls, append: shouldAppend) }
        case .failure(let error):
            Instrumentation.log("Import failed", area: .uiInteraction, level: .warning, details: "error=\(error.localizedDescription)")
            appendOnImport = false
            analysis.errorMessage = error.localizedDescription
        }
    }

    func loadSpectra(from urls: [URL], append: Bool) async {
        let started = Date()
        Instrumentation.log("Import started", area: .importParsing, level: .info, details: "files=\(urls.count) append=\(append)")

        let parseResult = await SpectrumParsingWorker.shared.parse(urls: urls)

        let loaded = parseResult.loaded
        let failures = parseResult.failures
        let skippedTotal = parseResult.skippedTotal
        let filesWithSkipped = parseResult.filesWithSkipped
        let warnings = parseResult.warnings
        let parsedFiles = parseResult.parsedFiles

        await MainActor.run {
            var validSpectra: [ShimadzuSpectrum] = []
            var parsedInvalidItems: [InvalidSpectrumItem] = []
            var invalidCounts: [String: Int] = [:]
            // Map spectrum UUID → source fileName for dataset ID tagging after persist
            var spectrumSourceFile: [UUID: String] = [:]
            validSpectra.reserveCapacity(loaded.count)

            for spectrum in loaded {
                if let reason = SpectrumValidation.invalidReason(x: spectrum.x, y: spectrum.y) {
                    parsedInvalidItems.append(
                        InvalidSpectrumItem(
                            spectrum: ShimadzuSpectrum(name: spectrum.name, x: spectrum.x, y: spectrum.y),
                            fileName: spectrum.fileName,
                            reason: reason
                        )
                    )
                    invalidCounts[spectrum.fileName, default: 0] += 1
                } else {
                    let s = ShimadzuSpectrum(name: spectrum.name, x: spectrum.x, y: spectrum.y)
                    spectrumSourceFile[s.id] = spectrum.fileName
                    validSpectra.append(s)
                }
            }

            let invalidWarnings = invalidCounts
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key): flagged \($0.value) invalid spectra" }
            let combinedWarnings = warnings + invalidWarnings

            let wasEmpty = analysis.spectra.isEmpty
            updateActiveMetadata(from: parsedFiles, append: append)
            let fileNameToDatasetID = persistParsedFiles(parsedFiles)

            // Tag each spectrum with its source dataset ID for session tracking
            for spectrum in validSpectra {
                if let fileName = spectrumSourceFile[spectrum.id],
                   let dsID = fileNameToDatasetID[fileName] {
                    spectrum.sourceDatasetID = dsID
                }
            }

            let newDatasetIDs = Array(fileNameToDatasetID.values)
            if append {
                analysis.spectra.append(contentsOf: validSpectra)
                var existingIDs = Self.readSessionDatasetIDs()
                for id in newDatasetIDs where !existingIDs.contains(id) {
                    existingIDs.append(id)
                }
                Self.writeSessionDatasetIDs(existingIDs)
            } else {
                analysis.spectra = validSpectra
                Self.writeSessionDatasetIDs(newDatasetIDs)
                analysis.selectedSpectrumIndex = 0
            }

            analysis.alignedSpectra = []
            analysis.processedSpectra = []
            analysis.pointCache = [:]

            if append {
                // Keep existing selection, add new spectra indices
                let oldCount = analysis.spectra.count - validSpectra.count
                let newIndices = Set(oldCount..<analysis.spectra.count)
                analysis.selectedSpectrumIndices = analysis.selectedSpectrumIndices
                    .filter { $0 >= 0 && $0 < analysis.spectra.count }
                    .union(newIndices)
                if wasEmpty, !analysis.spectra.isEmpty {
                    analysis.selectedSpectrumIndex = 0
                } else {
                    analysis.selectedSpectrumIndex = min(max(analysis.selectedSpectrumIndex, 0), max(analysis.spectra.count - 1, 0))
                }
            } else if !analysis.spectra.isEmpty {
                // Select ALL loaded spectra so they appear in charts and calculations
                analysis.selectedSpectrumIndices = Set(0..<analysis.spectra.count)
            }

            analysis.updatePeaks()
            analysis.applyAlignmentIfNeeded()

            if analysis.spectra.isEmpty {
                analysis.statusMessage = "No spectra found."
            } else if append, !validSpectra.isEmpty {
                analysis.statusMessage = "Added \(validSpectra.count) spectra (total \(analysis.spectra.count))."
            } else {
                analysis.statusMessage = "Loaded \(analysis.spectra.count) spectra."
            }

            if !analysis.includeInvalidInPlots {
                analysis.selectedInvalidItemIDs.removeAll()
            }

            if skippedTotal > 0 {
                let message = append
                    ? "Skipped \(skippedTotal) dataset(s) while adding."
                    : "Skipped \(skippedTotal) dataset(s) across \(filesWithSkipped) file(s)."
                analysis.warningMessage = message
            } else {
                analysis.warningMessage = nil
            }

            if append, !combinedWarnings.isEmpty {
                analysis.warningDetails.append(contentsOf: combinedWarnings)
            } else {
                analysis.warningDetails = combinedWarnings
            }

            if append, !parsedInvalidItems.isEmpty {
                analysis.invalidItems.append(contentsOf: parsedInvalidItems)
            } else {
                analysis.invalidItems = parsedInvalidItems
            }

            if !failures.isEmpty {
                analysis.errorMessage = failures.joined(separator: "\n")
            }

            if !analysis.spectra.isEmpty {
                onImportComplete?()
            }

            onSpectraLoaded?()

            // Trigger ContentView re-fetch since new datasets were persisted
            dataVersion += 1

            let duration = Date().timeIntervalSince(started)
            Instrumentation.log(
                "Import completed",
                area: .importParsing,
                level: .info,
                details: "loaded=\(validSpectra.count) failures=\(failures.count) skipped=\(skippedTotal)",
                duration: duration
            )
            if !failures.isEmpty {
                Instrumentation.log("Import failures", area: .importParsing, level: .warning, details: "count=\(failures.count)")
            }
            if skippedTotal > 0 {
                Instrumentation.log("Datasets skipped", area: .importParsing, level: .warning, details: "count=\(skippedTotal) files=\(filesWithSkipped)")
            }
        }
    }

    func updateActiveMetadata(from parsedFiles: [ParsedFileResult], append: Bool) {
        guard !append else { return }
        if parsedFiles.count == 1 {
            analysis.activeMetadata = parsedFiles[0].metadata
            analysis.activeMetadataSource = parsedFiles[0].url.lastPathComponent
        } else {
            analysis.activeMetadata = nil
            analysis.activeMetadataSource = parsedFiles.isEmpty ? nil : "Multiple files loaded"
        }
    }

    // Note: The StoredDataset overload of updateActiveMetadata was removed.
    // loadStoredDataset() now sets analysis.activeMetadata from its snapshot,
    // avoiding model property access after CloudKit sync may invalidate objects.

    // MARK: - Validation

    func validateStoredDatasetSelection(storedDatasets: [StoredDataset]) {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            analysis.statusMessage = "Select stored dataset(s) to validate."
            return
        }
        analysis.validationLogEntries.removeAll()
        for dataset in datasets {
            validateStoredDataset(dataset, appendLog: true)
        }
        analysis.statusMessage = "Header validation complete for \(datasets.count) dataset(s)."
    }

    func validateStoredDataset(_ dataset: StoredDataset, appendLog: Bool = false) {
        guard let ctx = modelContext else { return }
        // Re-fetch dataset by ID to get a fresh reference from the store coordinator.
        let dsID = dataset.id
        let dsPredicate = #Predicate<StoredDataset> { $0.id == dsID }
        guard let fresh = (try? ctx.fetch(FetchDescriptor<StoredDataset>(predicate: dsPredicate)))?.first else { return }
        // === SNAPSHOT: read all model data upfront in a single pass ===
        let fileName = fresh.fileName
        let metadataJSON = fresh.metadataJSON

        // Fetch spectra by predicate instead of traversing the spectraItems
        // relationship, which loads all spectrum objects and can fault during
        // CloudKit sync (swift_weakLoadStrong → brk #0x1).
        let predicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
        var descriptor = FetchDescriptor<StoredSpectrum>(predicate: predicate)
        descriptor.sortBy = [SortDescriptor(\StoredSpectrum.orderIndex)]
        let fetchedSpectra = (try? ctx.fetch(descriptor)) ?? []

        // Snapshot spectra into value types so we never touch model objects again
        struct SpectrumValidationSnapshot {
            let name: String
            let orderIndex: Int
            let xData: Data
            let yData: Data
        }
        let spectraSnapshots = fetchedSpectra
            .map { SpectrumValidationSnapshot(name: $0.name, orderIndex: $0.orderIndex, xData: $0.xData, yData: $0.yData) }

        // === From here, ONLY use locals — never touch `dataset` or `spectraItems` again ===

        let metadata: ShimadzuSPCMetadata? = {
            guard let data = metadataJSON else { return nil }
            return try? JSONDecoder().decode(ShimadzuSPCMetadata.self, from: data)
        }()
        guard let header = metadata?.mainHeader else {
            Instrumentation.log(
                "SPC header missing",
                area: .importParsing,
                level: .warning,
                details: "file=\(fileName)"
            )
            analysis.statusMessage = "No SPC header found for \(fileName)."
            return
        }

        if !appendLog {
            analysis.validationLogEntries.removeAll()
        }
        let xFetcher: (SpectrumValidationSnapshot) -> [Double] = { SpectrumBinaryCodec.decodeDoubles(from: $0.xData) }
        let yFetcher: (SpectrumValidationSnapshot) -> [Double] = { SpectrumBinaryCodec.decodeDoubles(from: $0.yData) }
        let mismatchCount = validateHeader(
            header, spectra: spectraSnapshots,
            spectrumName: { $0.name },
            xProvider: xFetcher,
            yProvider: yFetcher,
            logPrefix: "file=\(fileName)",
            logSink: { [weak self] message in
                self?.analysis.validationLogEntries.append(ValidationLogEntry(timestamp: Date(), message: message))
            }
        )

        if !appendLog {
            analysis.statusMessage = "Header validation complete (mismatches: \(mismatchCount))."
        }
    }

    func validateLoadedSpectra(activeHeader: SDAMainHeader?) {
        guard !analysis.spectra.isEmpty else {
            analysis.statusMessage = "No loaded spectra to validate."
            return
        }
        guard let header = activeHeader else {
            analysis.statusMessage = "No SPC header available for loaded spectra."
            return
        }

        analysis.validationLogEntries.removeAll()
        let xFetcher: (ShimadzuSpectrum) -> [Double] = { $0.x }
        let yFetcher: (ShimadzuSpectrum) -> [Double] = { $0.y }
        let mismatchCount = validateHeader(
            header, spectra: analysis.spectra,
            spectrumName: { $0.name },
            xProvider: xFetcher,
            yProvider: yFetcher,
            logPrefix: "loaded",
            logSink: { [weak self] message in
                self?.analysis.validationLogEntries.append(ValidationLogEntry(timestamp: Date(), message: message))
            }
        )
        analysis.statusMessage = "Loaded header validation complete (mismatches: \(mismatchCount))."
    }

    func axesMatch(_ lhs: [Double], _ rhs: [Double]) -> Bool {
        ValidationService.axesMatch(lhs, rhs)
    }

    func validateHeader<T>(
        _ header: SDAMainHeader, spectra: [T],
        spectrumName: (T) -> String,
        xProvider: (T) -> [Double],
        yProvider: (T) -> [Double],
        logPrefix: String,
        logSink: ((String) -> Void)? = nil
    ) -> Int {
        ValidationService.validateHeader(
            header, spectra: spectra,
            spectrumName: spectrumName,
            xProvider: xProvider,
            yProvider: yProvider,
            logPrefix: logPrefix,
            logSink: logSink
        )
    }

    static func validateSPCHeaderConsistency(for parsed: ParsedFileResult) {
        ValidationService.validateSPCHeaderConsistency(for: parsed)
    }

    // MARK: - Persistence

    @discardableResult
    func persistParsedFiles(_ parsedFiles: [ParsedFileResult]) -> [String: UUID] {
        guard let modelContext, !parsedFiles.isEmpty else { return [:] }
        return DatasetPersistenceService.persistParsedFiles(
            parsedFiles,
            modelContext: modelContext,
            dataStoreController: dataStoreController
        )
    }

    // MARK: - Dataset CRUD Operations

    func loadStoredDatasetSelection(append: Bool, storedDatasets: [StoredDataset]) {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            analysis.statusMessage = "Select stored dataset(s) to load."
            return
        }

        // Snapshot ALL datasets upfront in a single pass before any mutations.
        // This prevents accessing model properties after CloudKit sync may have
        // invalidated them between iterations.
        let snapshots = datasets.compactMap { snapshotForLoad($0) }

        if append {
            for snap in snapshots {
                loadStoredDatasetFromSnapshot(snap, append: true)
            }
        } else if let first = snapshots.first {
            loadStoredDatasetFromSnapshot(first, append: false)
            for snap in snapshots.dropFirst() {
                loadStoredDatasetFromSnapshot(snap, append: true)
            }
        }

        if datasets.count > 1 {
            analysis.statusMessage = "Loaded \(analysis.spectra.count) spectra from \(datasets.count) datasets."
        }
    }

    func loadStoredDatasetPickerSelection(append: Bool, storedDatasets: [StoredDataset]) {
        Instrumentation.log(
            "Picker load requested",
            area: .importParsing, level: .info,
            details: "append=\(append) selectionCount=\(storedDatasetPickerSelection.count) storedCount=\(storedDatasets.count)"
        )

        let datasets = storedDatasets.filter { storedDatasetPickerSelection.contains($0.id) }
        guard !datasets.isEmpty else {
            Instrumentation.log(
                "Picker load: no matching datasets",
                area: .importParsing, level: .warning,
                details: "selection=\(storedDatasetPickerSelection.map(\.uuidString))"
            )
            analysis.statusMessage = "Select stored datasets to load."
            return
        }

        // Snapshot ALL datasets upfront in a single pass before any mutations.
        let snapshots = datasets.compactMap { snapshotForLoad($0) }

        Instrumentation.log(
            "Picker load: snapshots ready",
            area: .importParsing, level: .info,
            details: "datasets=\(datasets.count) totalSpectra=\(snapshots.reduce(0) { $0 + $1.spectra.count })"
        )

        let spectraBefore = analysis.spectra.count

        let multiLoad = snapshots.count > 1
        if append {
            for snap in snapshots {
                loadStoredDatasetFromSnapshot(snap, append: true, skipCacheRebuild: multiLoad)
            }
        } else if let first = snapshots.first {
            loadStoredDatasetFromSnapshot(first, append: false, skipCacheRebuild: multiLoad)
            for snap in snapshots.dropFirst() {
                loadStoredDatasetFromSnapshot(snap, append: true, skipCacheRebuild: multiLoad)
            }
        }

        // When loading multiple datasets, do a single cache rebuild after all are loaded.
        if multiLoad {
            analysis.updatePeaks()
            analysis.applyAlignmentIfNeeded()
        }

        Instrumentation.log(
            "Picker load complete",
            area: .importParsing, level: .info,
            details: "spectraBefore=\(spectraBefore) spectraAfter=\(analysis.spectra.count) datasets=\(datasets.count)"
        )

        if datasets.count > 1 {
            analysis.statusMessage = "Loaded \(analysis.spectra.count) spectra from \(datasets.count) datasets."
        }
    }

    // MARK: - Dataset Load Snapshot

    /// Value-type snapshot of everything needed from a `StoredDataset` for loading.
    /// Created synchronously in a single pass to minimize the window during which
    /// SwiftData model properties are accessed. After this snapshot is created,
    /// no further model property access is needed.
    private struct DatasetLoadSnapshot {
        let id: UUID
        let fileName: String
        let metadataJSON: Data?
        let isReference: Bool
        let knownInVivoSPF: Double?
        let hdrsSpectrumTags: [UUID: HDRSSpectrumTag]
        let skippedDataSets: [String]
        let warnings: [String]
        struct SpectrumSnapshot {
            let id: UUID
            let name: String
            let orderIndex: Int
            let xData: Data
            let yData: Data
            let isInvalid: Bool
            let invalidReason: String?
        }
        let spectra: [SpectrumSnapshot]
    }

    /// Snapshots all data from a `StoredDataset` into value types in a single pass.
    /// Must be called when the model object is known to be valid (e.g., from a fresh `@Query`
    /// result during a user-initiated action). After this returns, no model access is needed.
    private func snapshotForLoad(_ dataset: StoredDataset) -> DatasetLoadSnapshot? {
        guard let ctx = modelContext else { return nil }
        // Re-fetch the dataset by ID through the store coordinator to get a fresh
        // reference that won't trap if CloudKit sync invalidated the original.
        let dsID = dataset.id
        let dsPredicate = #Predicate<StoredDataset> { $0.id == dsID }
        guard let fresh = (try? ctx.fetch(FetchDescriptor<StoredDataset>(predicate: dsPredicate)))?.first else { return nil }

        let spectraPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
        let spectraItems = (try? ctx.fetch(FetchDescriptor<StoredSpectrum>(predicate: spectraPredicate))) ?? []

        Instrumentation.log(
            "Snapshot created",
            area: .importParsing, level: .info,
            details: "datasetID=\(fresh.id) file=\(fresh.fileName) spectraCount=\(spectraItems.count)"
        )
        let spectraSnapshots = spectraItems
            .sorted { $0.orderIndex < $1.orderIndex }
            .map { spectrum in
                DatasetLoadSnapshot.SpectrumSnapshot(
                    id: spectrum.id,
                    name: spectrum.name,
                    orderIndex: spectrum.orderIndex,
                    xData: spectrum.xData,
                    yData: spectrum.yData,
                    isInvalid: spectrum.isInvalid,
                    invalidReason: spectrum.invalidReason
                )
            }
        return DatasetLoadSnapshot(
            id: fresh.id,
            fileName: fresh.fileName,
            metadataJSON: fresh.metadataJSON,
            isReference: fresh.isReference,
            knownInVivoSPF: fresh.knownInVivoSPF,
            hdrsSpectrumTags: fresh.hdrsSpectrumTags,
            skippedDataSets: fresh.skippedDataSets,
            warnings: fresh.warnings,
            spectra: spectraSnapshots
        )
    }

    func loadStoredDataset(_ dataset: StoredDataset, append: Bool) {
        // Snapshot once, then delegate to snapshot-based load.
        guard let snap = snapshotForLoad(dataset) else { return }
        loadStoredDatasetFromSnapshot(snap, append: append)
    }

    /// Loads spectra and metadata from a pre-built snapshot. No SwiftData model access.
    /// When `skipCacheRebuild` is true, the caller is responsible for calling
    /// `analysis.updatePeaks()` and cache rebuilds after all datasets are loaded.
    private func loadStoredDatasetFromSnapshot(_ snap: DatasetLoadSnapshot, append: Bool, skipCacheRebuild: Bool = false) {
        Instrumentation.log(
            "Loading snapshot",
            area: .importParsing, level: .info,
            details: "file=\(snap.fileName) append=\(append) snapshotSpectra=\(snap.spectra.count) currentSpectra=\(analysis.spectra.count)"
        )

        let metadata: ShimadzuSPCMetadata? = {
            guard let data = snap.metadataJSON else { return nil }
            return try? JSONDecoder().decode(ShimadzuSPCMetadata.self, from: data)
        }()
        if !append {
            analysis.activeMetadata = metadata
            analysis.activeMetadataSource = snap.fileName
        }

        var validSpectra: [ShimadzuSpectrum] = []
        var loadedInvalidItems: [InvalidSpectrumItem] = []

        for stored in snap.spectra {
            let spectrum = ShimadzuSpectrum(name: stored.name, xData: stored.xData, yData: stored.yData)
            spectrum.sourceDatasetID = snap.id
            if stored.isInvalid {
                let reason = stored.invalidReason ?? "Invalid spectrum"
                loadedInvalidItems.append(
                    InvalidSpectrumItem(
                        spectrum: spectrum,
                        fileName: snap.fileName,
                        reason: reason
                    )
                )
            } else {
                validSpectra.append(spectrum)
            }
        }

        let wasEmpty = analysis.spectra.isEmpty
        if append {
            analysis.spectra.append(contentsOf: validSpectra)
            Self.appendSessionDatasetID(snap.id)

            if !snap.hdrsSpectrumTags.isEmpty {
                for (spectrumID, tag) in snap.hdrsSpectrumTags {
                    analysis.hdrsSpectrumTags[spectrumID] = tag
                }
            }
        } else {
            analysis.spectra = validSpectra
            Self.writeSessionDatasetIDs([snap.id])
            analysis.selectedSpectrumIndex = 0
            analysis.hdrsSpectrumTags.removeAll()

            for (spectrumID, tag) in snap.hdrsSpectrumTags {
                analysis.hdrsSpectrumTags[spectrumID] = tag
            }
        }

        Instrumentation.log(
            "Snapshot spectra loaded",
            area: .importParsing, level: .info,
            details: "file=\(snap.fileName) valid=\(validSpectra.count) invalid=\(loadedInvalidItems.count) totalNow=\(analysis.spectra.count)"
        )

        analysis.alignedSpectra = []
        analysis.processedSpectra = []
        analysis.pointCache = [:]

        if append {
            // Keep existing selection, add new spectra indices
            let oldCount = analysis.spectra.count - validSpectra.count
            let newIndices = Set(oldCount..<analysis.spectra.count)
            analysis.selectedSpectrumIndices = analysis.selectedSpectrumIndices
                .filter { $0 >= 0 && $0 < analysis.spectra.count }
                .union(newIndices)
            if wasEmpty, !analysis.spectra.isEmpty {
                analysis.selectedSpectrumIndex = 0
            } else {
                analysis.selectedSpectrumIndex = min(max(analysis.selectedSpectrumIndex, 0), max(analysis.spectra.count - 1, 0))
            }
        } else if !analysis.spectra.isEmpty {
            // Select ALL loaded spectra so they appear in charts and calculations
            analysis.selectedSpectrumIndices = Set(0..<analysis.spectra.count)
        }

        if !skipCacheRebuild {
            analysis.updatePeaks()
            analysis.applyAlignmentIfNeeded()
        }

        if analysis.spectra.isEmpty {
            analysis.statusMessage = "No spectra found."
        } else if append, !validSpectra.isEmpty {
            analysis.statusMessage = "Added \(validSpectra.count) spectra from stored dataset."
        } else {
            analysis.statusMessage = "Loaded \(analysis.spectra.count) spectra from stored dataset."
        }

        if !analysis.includeInvalidInPlots {
            analysis.selectedInvalidItemIDs.removeAll()
        }

        let skippedCount = snap.skippedDataSets.count
        if skippedCount > 0 {
            analysis.warningMessage = append
                ? "Skipped \(skippedCount) dataset(s) while adding."
                : "Skipped \(skippedCount) dataset(s) in stored file."
        } else {
            analysis.warningMessage = nil
        }

        let warningLines = snap.warnings.map { "\(snap.fileName): \($0)" }
        if append {
            analysis.warningDetails.append(contentsOf: warningLines)
        } else {
            analysis.warningDetails = warningLines
        }

        if append {
            analysis.invalidItems.append(contentsOf: loadedInvalidItems)
        } else {
            analysis.invalidItems = loadedInvalidItems
        }
        analysis.selectedInvalidItemIDs = []

        if !analysis.spectra.isEmpty {
            onImportComplete?()
        }

        onSpectraLoaded?()
    }

    // MARK: - Direct Reference Calibration Resolution

    /// Resolves reference calibration data directly from the datastore WITHOUT loading
    /// spectra into `analysis.spectra`. Queries `searchableRecordCache` for all non-archived
    /// reference datasets with known SPF, filters by user exclusions, reads spectral data
    /// from StoredDataset objects, and returns calibration snapshots ready for
    /// `SpectralMetricsWorker.compute()`.
    func resolveReferenceCalibrationData(
        storedDatasets: [StoredDataset]
    ) -> [(labelSPF: Double, name: String, x: [Double], y: [Double])] {
        // 1. Query cache for all non-archived, non-excluded reference datasets
        //    that have an *explicitly set* knownInVivoSPF.
        //    We deliberately do NOT infer SPF from filenames — numbers in
        //    filenames can represent sample weight, batch IDs, project codes,
        //    etc., leading to wildly incorrect calibration.
        let allReferenceEntries = searchableRecordCache.filter { (id, record) in
            record.isReference
            && !record.isArchived
            && !excludedReferenceDatasetIDs.contains(id)
        }

        var resolvedEntries: [(id: UUID, record: DatasetSearchRecord, effectiveSPF: Double)] = []
        for (id, record) in allReferenceEntries {
            if let explicit = record.knownInVivoSPF, explicit > 0 {
                resolvedEntries.append((id: id, record: record, effectiveSPF: explicit))
            }
        }

        if resolvedEntries.isEmpty {
            let withExplicit = allReferenceEntries.filter { ($0.value.knownInVivoSPF ?? 0) > 0 }.count
            let totalRefs = allReferenceEntries.count
            Instrumentation.log(
                "Reference resolution: no eligible entries",
                area: .processing, level: .warning,
                details: "cacheSize=\(searchableRecordCache.count) isReference=\(totalRefs) withExplicitSPF=\(withExplicit) storedDatasets=\(storedDatasets.count) excludedIDs=\(excludedReferenceDatasetIDs.count) hint=Tag reference datasets with verified in-vivo SPF values in Data Management."
            )
            return []
        }

        // 2. Build calibration lookups entirely from cache — no model property
        //    access on storedDatasets, which may contain objects invalidated by
        //    CloudKit sync (brk #0x1 on property access).
        //    The searchableRecordCache already contains fileName for each dataset.
        var calibrationSnapshots: [(labelSPF: Double, name: String, x: [Double], y: [Double])] = []

        let refLookups: [(dsID: UUID, effectiveSPF: Double, displayName: String)] = resolvedEntries.map { entry in
            (dsID: entry.id, effectiveSPF: entry.effectiveSPF, displayName: entry.record.fileName)
        }

        guard let ctx = modelContext else { return calibrationSnapshots }

        for entry in refLookups {
            let dsID = entry.dsID
            let spectrumPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
            var descriptor = FetchDescriptor<StoredSpectrum>(predicate: spectrumPredicate)
            descriptor.sortBy = [SortDescriptor(\StoredSpectrum.orderIndex)]

            let spectra: [StoredSpectrum]
            do {
                var captured: [StoredSpectrum] = []
                try ObjCExceptionCatcher.try {
                    captured = (try? ctx.fetch(descriptor)) ?? []
                }
                spectra = captured
            } catch {
                Instrumentation.log(
                    "Reference spectra fetch fault",
                    area: .processing, level: .warning,
                    details: "datasetID=\(dsID) error=\(error.localizedDescription)"
                )
                continue
            }

            for stored in spectra {
                guard stored.modelContext != nil, !stored.isInvalid else { continue }
                let x = SpectrumBinaryCodec.decodeDoubles(from: stored.xData)
                let y = SpectrumBinaryCodec.decodeDoubles(from: stored.yData)
                guard !x.isEmpty, x.count == y.count else { continue }
                let spectrumLabel = stored.name.isEmpty ? entry.displayName : stored.name
                calibrationSnapshots.append((labelSPF: entry.effectiveSPF, name: spectrumLabel, x: x, y: y))
            }
        }

        Instrumentation.log(
            "Resolved reference calibration data",
            area: .processing,
            level: .info,
            details: "datasets=\(refLookups.count) spectra=\(calibrationSnapshots.count) excluded=\(excludedReferenceDatasetIDs.count)"
        )

        return calibrationSnapshots
    }

    /// Attempts to infer the label SPF from the dataset's file name or spectrum/dataset names.
    /// Looks for common patterns like "SPF 50", "50 commercial", "cetaphil 40", etc.
    private static func inferSPFFromNames(record: DatasetSearchRecord) -> Double? {
        // Try SPFLabelStore first for known product matches
        if let match = SPFLabelStore.matchLabel(for: record.fileName) {
            return match.spf
        }
        // Also try individual dataset names
        for name in record.dataSetNames {
            if let match = SPFLabelStore.matchLabel(for: name) {
                return match.spf
            }
        }
        // Fallback: extract a plausible SPF number from the filename.
        // Look for patterns like " 50 ", "SPF50", "SPF 30", or a bare number
        // that's a common SPF value (10, 15, 20, 25, 30, 40, 50, 60, 70, 100).
        return extractSPFNumber(from: record.fileName)
            ?? record.dataSetNames.lazy.compactMap({ extractSPFNumber(from: $0) }).first
    }

    /// Extracts a plausible SPF value from a string by looking for numeric tokens
    /// that match common SPF values (10–100).
    private static func extractSPFNumber(from text: String) -> Double? {
        let commonSPFValues: Set<Int> = [10, 15, 20, 25, 30, 40, 50, 60, 70, 100]
        // Tokenize: replace non-alphanumeric chars with spaces, split on spaces
        let cleaned = text.unicodeScalars.map {
            CharacterSet.decimalDigits.contains($0) ? Character($0) : " "
        }
        let tokens = String(cleaned)
            .split(whereSeparator: { $0 == " " })
            .compactMap { Int($0) }

        // Return the first token that looks like a common SPF value
        for value in tokens {
            if commonSPFValues.contains(value) {
                return Double(value)
            }
        }
        return nil
    }

    /// Returns (total, included) counts of reference datasets for display in the inspector.
    /// Counts any non-archived reference dataset that has an explicit or inferable SPF.
    var referenceDatasetSummary: (total: Int, included: Int) {
        let all = searchableRecordCache.filter { (_, record) in
            record.isReference
            && !record.isArchived
            && (record.knownInVivoSPF != nil || Self.inferSPFFromNames(record: record) != nil)
        }
        let included = all.filter { !excludedReferenceDatasetIDs.contains($0.key) }
        return (total: all.count, included: included.count)
    }

    /// Returns all reference dataset records for display in the filter popover,
    /// sorted by filename. Includes datasets with explicit or inferred SPF.
    var allReferenceDatasetRecords: [(id: UUID, record: DatasetSearchRecord, effectiveSPF: Double?)] {
        searchableRecordCache
            .filter { (_, record) in
                record.isReference && !record.isArchived
            }
            .map { (id, record) in
                let spf = record.knownInVivoSPF ?? Self.inferSPFFromNames(record: record)
                return (id: id, record: record, effectiveSPF: spf)
            }
            .sorted { $0.record.fileName.localizedCaseInsensitiveCompare($1.record.fileName) == .orderedAscending }
    }

    // MARK: - Dataset Role & SPF Assignment

    /// Updates the role and known in-vivo SPF for a stored dataset.
    /// Assigns a role (and optional known in-vivo SPF for references) to a dataset.
    ///
    /// Patches the searchable-record cache first for immediate UI feedback,
    /// then mutates the model object directly — autosave persists the change.
    func setDatasetRole(
        _ role: DatasetRole?,
        knownInVivoSPF: Double?,
        for datasetID: UUID,
        storedDatasets: [StoredDataset]
    ) {
        let roleRawValue = role?.rawValue
        let spfValue = (role == .reference) ? knownInVivoSPF : nil

        // Patch the cache FIRST so the UI renders from safe value types.
        patchCacheEntry(for: datasetID, datasetRole: roleRawValue, knownInVivoSPF: spfValue)

        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        do {
            try ObjCExceptionCatcher.try {
                dataset.datasetRole = roleRawValue
                dataset.knownInVivoSPF = spfValue
            }
        } catch {
            Instrumentation.log(
                "setDatasetRole caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        dataStoreController?.noteLocalChange(bytes: 64)
        dataVersion += 1
    }

    /// Saves ISO 24443 metadata (plate type, application quantity, formulation type) for a dataset.
    func setDatasetMetadata(
        plateType: SubstratePlateType,
        pmmaPlateSubtype: PMMAPlateSubtype?,
        applicationQuantityMg: Double?,
        formulationType: FormulationType,
        for datasetID: UUID,
        storedDatasets: [StoredDataset]
    ) {
        let subtypeRaw = (plateType == .pmma) ? (pmmaPlateSubtype ?? .moulded).rawValue : nil

        // 1. Patch the cache so UI updates immediately.
        if var existing = searchableRecordCache[datasetID] {
            existing = DatasetSearchRecord(
                fileName: existing.fileName,
                datasetRole: existing.datasetRole,
                knownInVivoSPF: existing.knownInVivoSPF,
                importedAt: existing.importedAt,
                fileHash: existing.fileHash,
                sourcePath: existing.sourcePath,
                dataSetNames: existing.dataSetNames,
                directoryEntryNames: existing.directoryEntryNames,
                spectrumCount: existing.spectrumCount,
                memo: existing.memo,
                sourceInstrumentText: existing.sourceInstrumentText,
                instrumentID: existing.instrumentID,
                validSpectrumCount: existing.validSpectrumCount,
                isArchived: existing.isArchived,
                archivedAt: existing.archivedAt,
                plateType: plateType.rawValue,
                applicationQuantityMg: applicationQuantityMg,
                formulationType: formulationType.rawValue,
                pmmaPlateSubtype: subtypeRaw,
                formulaCardID: existing.formulaCardID,
                isPostIrradiation: existing.isPostIrradiation
            )
            searchableRecordCache[datasetID] = existing
        }

        // 2. Mutate the model object directly — autosave persists the change.
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        do {
            try ObjCExceptionCatcher.try {
                dataset.plateType = plateType.rawValue
                dataset.applicationQuantityMg = applicationQuantityMg
                dataset.formulationType = formulationType.rawValue
                dataset.pmmaPlateSubtype = subtypeRaw
            }
        } catch {
            Instrumentation.log(
                "setDatasetMetadata caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        dataStoreController?.noteLocalChange(bytes: 64)
        dataVersion += 1
    }

    /// Sets or clears the manual post-irradiation override for a dataset.
    /// Pass `nil` to revert to auto-detection from the filename.
    func setIrradiationStatus(
        _ isPostIrradiation: Bool?,
        for datasetID: UUID,
        storedDatasets: [StoredDataset]
    ) {
        // 1. Patch the cache so UI updates immediately.
        if let existing = searchableRecordCache[datasetID] {
            searchableRecordCache[datasetID] = existing.patching(isPostIrradiation: isPostIrradiation)
        }

        // 2. Mutate the model object directly — autosave persists the change.
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        do {
            try ObjCExceptionCatcher.try {
                dataset.isPostIrradiation = isPostIrradiation
            }
        } catch {
            Instrumentation.log(
                "setIrradiationStatus caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        dataStoreController?.noteLocalChange(bytes: 16)
        dataVersion += 1
    }

    /// Associates a formula card with a prototype sample dataset.
    /// Follows the same cache-first + ObjCExceptionCatcher pattern as setDatasetMetadata.
    func setFormulaCard(
        id formulaCardID: UUID?,
        for datasetID: UUID,
        storedDatasets: [StoredDataset]
    ) {
        // 1. Patch the cache so UI updates immediately.
        if let existing = searchableRecordCache[datasetID] {
            searchableRecordCache[datasetID] = existing.patching(formulaCardID: formulaCardID)
        }

        // 2. Mutate the model object.
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        do {
            try ObjCExceptionCatcher.try {
                dataset.formulaCardID = formulaCardID
            }
        } catch {
            Instrumentation.log(
                "setFormulaCard caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        dataStoreController?.noteLocalChange(bytes: 16)
        dataVersion += 1
    }

    /// Handles the result of a formula card file import.
    /// Creates a new StoredFormulaCard with the file data and sets it as the pending card.
    func handleFormulaCardImport(result: Result<[URL], Error>) {
        guard let ctx = modelContext else { return }

        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let didAccess = url.startAccessingSecurityScopedResource()
            defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

            guard let fileData = try? Data(contentsOf: url) else {
                Instrumentation.log(
                    "handleFormulaCardImport: failed to read file data",
                    area: .processing, level: .error,
                    details: "url=\(url.lastPathComponent)"
                )
                return
            }

            let fileExtension = url.pathExtension.lowercased()
            let fileName = url.lastPathComponent

            let card = StoredFormulaCard(
                name: url.deletingPathExtension().lastPathComponent,
                sourceFileData: fileData,
                sourceFileName: fileName,
                sourceFileType: fileExtension
            )

            do {
                try ObjCExceptionCatcher.try {
                    ctx.insert(card)
                }
            } catch {
                Instrumentation.log(
                    "handleFormulaCardImport: insert caught NSException",
                    area: .processing, level: .error,
                    details: "error=\(error.localizedDescription)"
                )
                return
            }

            pendingFormulaCardID = card.id
            formulaCards.append(card)
            dataStoreController?.noteLocalChange(bytes: Int64(fileData.count))
            dataVersion += 1

        case .failure(let error):
            Instrumentation.log(
                "handleFormulaCardImport failed",
                area: .processing, level: .error,
                details: "error=\(error.localizedDescription)"
            )
        }
    }

    /// Persists HDRS spectrum tags back to their parent StoredDataset.
    func persistHDRSTags(for datasetID: UUID, storedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        // Fetch spectrum IDs by predicate instead of traversing the spectraItems
        // relationship, which loads all spectrum objects and can fault during sync.
        let predicate = #Predicate<StoredSpectrum> { $0.datasetID == datasetID }
        let spectra = (try? ctx.fetch(FetchDescriptor<StoredSpectrum>(predicate: predicate))) ?? []
        let datasetSpectrumIDs = Set(spectra.compactMap { $0.modelContext != nil ? $0.id : nil })
        let relevantTags = analysis.hdrsSpectrumTags.filter { datasetSpectrumIDs.contains($0.key) }

        dataset.hdrsSpectrumTags = relevantTags

        dataStoreController?.noteLocalChange(bytes: Int64(relevantTags.count * 64))
        dataVersion += 1
    }

    /// Persists HDRS classification metadata (plate type) for a stored dataset.
    func setDatasetHDRSMetadata(
        plateType: HDRSPlateType,
        for datasetID: UUID,
        storedDatasets: [StoredDataset]
    ) {
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        let metadata = DatasetHDRSMetadata(plateType: plateType)

        do {
            try ObjCExceptionCatcher.try {
                dataset.hdrsMetadataJSON = try? JSONEncoder().encode(metadata)
            }
        } catch {
            Instrumentation.log(
                "setDatasetHDRSMetadata caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        dataStoreController?.noteLocalChange(bytes: 32)
        dataVersion += 1
    }

    // MARK: - Instrument Assignment

    /// Assigns an instrument to a single dataset.
    func assignInstrument(_ instrumentID: UUID, to datasetID: UUID, storedDatasets: [StoredDataset]) {
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }),
              dataset.modelContext != nil else { return }

        do {
            try ObjCExceptionCatcher.try {
                dataset.instrumentID = instrumentID
            }
        } catch {
            Instrumentation.log(
                "assignInstrument caught NSException",
                area: .processing, level: .error,
                details: "datasetID=\(datasetID) error=\(error.localizedDescription)"
            )
            return
        }

        // Update search record cache
        if let existing = searchableRecordCache[datasetID] {
            searchableRecordCache[datasetID] = existing.patching(instrumentID: instrumentID)
        }

        dataStoreController?.noteLocalChange(bytes: 16)
        dataVersion += 1
    }

    /// Assigns an instrument to all datasets from the same source directory.
    func assignInstrumentToBatch(_ instrumentID: UUID, for datasetID: UUID, storedDatasets: [StoredDataset]) {
        guard let record = searchableRecordCache[datasetID],
              let path = record.sourcePath, !path.isEmpty else {
            assignInstrument(instrumentID, to: datasetID, storedDatasets: storedDatasets)
            return
        }

        let directory = (path as NSString).deletingLastPathComponent
        guard !directory.isEmpty else {
            assignInstrument(instrumentID, to: datasetID, storedDatasets: storedDatasets)
            return
        }

        // Collect sibling IDs from the cache (no model property access).
        let siblingIDs = storedDatasets.compactMap { dataset -> UUID? in
            guard let dPath = searchableRecordCache[dataset.id]?.sourcePath else { return nil }
            let dDir = (dPath as NSString).deletingLastPathComponent
            return dDir == directory ? dataset.id : nil
        }

        var assignedCount = 0
        for id in siblingIDs {
            guard let dataset = storedDatasets.first(where: { $0.id == id }),
                  dataset.modelContext != nil else { continue }

            do {
                try ObjCExceptionCatcher.try {
                    MainActor.assumeIsolated {
                        dataset.instrumentID = instrumentID
                    }
                }
                assignedCount += 1
            } catch {
                Instrumentation.log(
                    "assignInstrument caught NSException",
                    area: .processing, level: .error,
                    details: "datasetID=\(id) error=\(error.localizedDescription)"
                )
                continue
            }

            // Update search record cache
            if let existing = searchableRecordCache[id] {
                searchableRecordCache[id] = existing.patching(instrumentID: instrumentID)
            }
        }

        dataStoreController?.noteLocalChange(bytes: Int64(16 * assignedCount))
        dataVersion += 1

        Instrumentation.log(
            "Batch instrument assignment",
            area: .processing, level: .info,
            details: "instrumentID=\(instrumentID) datasets=\(siblingIDs.count) directory=\(directory)"
        )
    }

    /// Updates the instrument display name cache from a list of instruments.
    func updateInstrumentCache(from instruments: [StoredInstrument]) {
        guard let ctx = modelContext else { return }
        // Re-fetch instruments through the store coordinator —
        // @Query results may contain objects invalidated by CloudKit sync.
        let freshInstruments: [StoredInstrument]
        do {
            freshInstruments = try ctx.fetch(FetchDescriptor<StoredInstrument>())
        } catch { return }
        var cache: [UUID: String] = [:]
        for instrument in freshInstruments {
            cache[instrument.id] = instrument.displayName
        }
        instrumentCache = cache
    }

    // MARK: - Session Restore

    /// File URL for session dataset IDs — survives crashes because we write
    /// atomically to disk, unlike UserDefaults which buffers in memory.
    private static var sessionFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastSessionDatasetIDs.json")
    }

    static func readSessionDatasetIDs() -> [UUID] {
        // Try file-based storage first (crash-safe)
        if let data = try? Data(contentsOf: sessionFileURL),
           let idStrings = try? JSONDecoder().decode([String].self, from: data) {
            let ids = idStrings.compactMap { UUID(uuidString: $0) }
            if !ids.isEmpty {
                print("[SessionRestore] Read \(ids.count) IDs from file.")
                return ids
            }
        }
        // Fall back to UserDefaults for backward compatibility
        if let jsonString = UserDefaults.standard.string(forKey: sessionDatasetIDsKey),
           let data = jsonString.data(using: .utf8),
           let idStrings = try? JSONDecoder().decode([String].self, from: data) {
            let ids = idStrings.compactMap { UUID(uuidString: $0) }
            if !ids.isEmpty {
                print("[SessionRestore] Read \(ids.count) IDs from UserDefaults (legacy).")
                // Migrate to file-based storage
                writeSessionDatasetIDs(ids)
                return ids
            }
        }
        return []
    }

    static func writeSessionDatasetIDs(_ ids: [UUID]) {
        guard !ids.isEmpty else {
            try? FileManager.default.removeItem(at: sessionFileURL)
            UserDefaults.standard.removeObject(forKey: sessionDatasetIDsKey)
            print("[SessionSave] Cleared saved session IDs.")
            return
        }
        let idStrings = ids.map { $0.uuidString }
        if let json = try? JSONEncoder().encode(idStrings) {
            // Write atomically to file — survives crashes
            do {
                try json.write(to: sessionFileURL, options: .atomic)
                print("[SessionSave] Saved \(ids.count) dataset IDs to file.")
            } catch {
                print("[SessionSave] File write failed: \(error.localizedDescription)")
            }
            // Also write to UserDefaults as backup
            if let jsonString = String(data: json, encoding: .utf8) {
                UserDefaults.standard.set(jsonString, forKey: sessionDatasetIDsKey)
            }
        }
    }

    static func appendSessionDatasetID(_ id: UUID) {
        var ids = readSessionDatasetIDs()
        guard !ids.contains(id) else { return }
        ids.append(id)
        writeSessionDatasetIDs(ids)
    }

    /// Rewrite the session file to contain only dataset IDs that still have at
    /// least one spectrum loaded.  Call this after removing spectra.
    static func syncSessionDatasetIDs(from spectra: [ShimadzuSpectrum]) {
        let activeIDs = spectra.compactMap(\.sourceDatasetID)
        // Preserve original ordering from the session file
        let activeSet = Set(activeIDs)
        let currentIDs = readSessionDatasetIDs()
        let pruned = currentIDs.filter { activeSet.contains($0) }
        if pruned.count != currentIDs.count {
            writeSessionDatasetIDs(pruned)
            print("[SessionSave] Synced session IDs: \(currentIDs.count) → \(pruned.count)")
        }
    }

    // MARK: - Selection Persistence

    /// File URL for persisting which datasets are selected (checked) in the left panel.
    private static var selectionFileURL: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("lastSelectedDatasetIDs.json")
    }

    static func readSelectedDatasetIDs() -> Set<UUID> {
        guard let data = try? Data(contentsOf: selectionFileURL),
              let idStrings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
        let ids = Set(idStrings.compactMap { UUID(uuidString: $0) })
        if !ids.isEmpty {
            print("[SelectionRestore] Read \(ids.count) selected IDs from file.")
        }
        return ids
    }

    static func writeSelectedDatasetIDs(_ ids: Set<UUID>) {
        guard !ids.isEmpty else {
            try? FileManager.default.removeItem(at: selectionFileURL)
            return
        }
        let idStrings = ids.map { $0.uuidString }
        if let json = try? JSONEncoder().encode(idStrings) {
            try? json.write(to: selectionFileURL, options: .atomic)
        }
    }

    func restoreLastSession(storedDatasets: [StoredDataset]) {
        let savedIDs = Self.readSessionDatasetIDs()
        guard !savedIDs.isEmpty else {
            print("[SessionRestore] No saved session IDs found.")
            return
        }

        print("[SessionRestore] Attempting to restore \(savedIDs.count) datasets: \(savedIDs)")
        print("[SessionRestore] storedDatasets has \(storedDatasets.count) datasets.")

        let datasetMap = Dictionary(uniqueKeysWithValues: storedDatasets.map { ($0.id, $0) })
        let datasetsToRestore = savedIDs.compactMap { datasetMap[$0] }

        guard !datasetsToRestore.isEmpty else {
            if storedDatasets.isEmpty {
                // storedDatasets may not be populated yet (e.g. @Query hasn't
                // delivered). Do NOT clear saved IDs — the caller should retry
                // once data is available.
                print("[SessionRestore] storedDatasets is empty — deferring restore (IDs preserved).")
            } else {
                // storedDatasets is populated but none match — the saved
                // datasets were likely deleted. Clear stale IDs.
                print("[SessionRestore] None of the saved IDs matched stored datasets — clearing stale IDs.")
                Self.writeSessionDatasetIDs([])
            }
            return
        }

        guard let ctx = modelContext else {
            print("[SessionRestore] No modelContext available — cannot query spectra safely.")
            return
        }

        // Build snapshots using FetchDescriptor queries instead of relationship
        // traversal.  This avoids the `swift_weakLoadStrong → brk #0x1` crash
        // that can occur when CloudKit sync invalidates model objects between
        // the `@Query` result and the property access.
        var snapshots: [DatasetLoadSnapshot] = []
        for dataset in datasetsToRestore {
            let dsID = dataset.id
            // Re-fetch by ID to get a fresh reference from the store coordinator.
            let dsPredicate = #Predicate<StoredDataset> { $0.id == dsID }
            guard let fresh = (try? ctx.fetch(FetchDescriptor<StoredDataset>(predicate: dsPredicate)))?.first else {
                print("[SessionRestore] Dataset \(dsID) no longer in store — skipping.")
                continue
            }
            let spectrumPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
            var descriptor = FetchDescriptor<StoredSpectrum>(predicate: spectrumPredicate)
            descriptor.sortBy = [SortDescriptor(\StoredSpectrum.orderIndex)]

            let fetched: [StoredSpectrum]
            do {
                var captured: [StoredSpectrum] = []
                try ObjCExceptionCatcher.try {
                    captured = (try? ctx.fetch(descriptor)) ?? []
                }
                fetched = captured
            } catch {
                print("[SessionRestore] Spectra fetch fault for \(fresh.fileName): \(error.localizedDescription)")
                continue
            }

            let spectraSnapshots = fetched
                .filter { $0.modelContext != nil && !$0.isInvalid || $0.isInvalid }
                .map { spectrum in
                    DatasetLoadSnapshot.SpectrumSnapshot(
                        id: spectrum.id,
                        name: spectrum.name,
                        orderIndex: spectrum.orderIndex,
                        xData: spectrum.xData,
                        yData: spectrum.yData,
                        isInvalid: spectrum.isInvalid,
                        invalidReason: spectrum.invalidReason
                    )
                }

            guard !spectraSnapshots.isEmpty else {
                print("[SessionRestore] No spectra found for dataset \(fresh.fileName) — skipping.")
                continue
            }

            snapshots.append(DatasetLoadSnapshot(
                id: fresh.id,
                fileName: fresh.fileName,
                metadataJSON: fresh.metadataJSON,
                isReference: fresh.isReference,
                knownInVivoSPF: fresh.knownInVivoSPF,
                hdrsSpectrumTags: fresh.hdrsSpectrumTags,
                skippedDataSets: fresh.skippedDataSets,
                warnings: fresh.warnings,
                spectra: spectraSnapshots
            ))
        }

        guard !snapshots.isEmpty else {
            print("[SessionRestore] No datasets could be restored (all spectra queries failed).")
            return
        }

        loadStoredDatasetFromSnapshot(snapshots[0], append: false, skipCacheRebuild: true)
        for snap in snapshots.dropFirst() {
            loadStoredDatasetFromSnapshot(snap, append: true, skipCacheRebuild: true)
        }

        print("[SessionRestore] Restored \(snapshots.count) datasets, \(analysis.spectra.count) spectra total.")

        if snapshots.count == 1 {
            analysis.statusMessage = "Restored \(analysis.spectra.count) spectra from last session."
        } else {
            analysis.statusMessage = "Restored \(analysis.spectra.count) spectra from \(snapshots.count) datasets."
        }
    }

    /// Returns true if datasets were restored, false if none found.
    func restoreLastSessionOrShowDataManagement(storedDatasets: [StoredDataset]) -> Bool {
        let savedIDs = Self.readSessionDatasetIDs()
        guard !savedIDs.isEmpty else {
            print("[SessionRestore] No saved session IDs found.")
            return false
        }
        restoreLastSession(storedDatasets: storedDatasets)
        return !analysis.spectra.isEmpty
    }

    func deleteStoredDatasetSelection(storedDatasets: [StoredDataset]) {
        let datasets = storedDatasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            analysis.statusMessage = "Select stored dataset(s) to archive."
            return
        }
        pendingArchiveDatasetIDs = Set(datasets.map { $0.id })
        showArchiveConfirmation = true
    }

    /// Re-parses a stored dataset from its cached `fileData` using the current parser,
    /// replacing stale spectra with freshly parsed X/Y data.
    func reparseDataset(_ datasetID: UUID, storedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else {
            analysis.statusMessage = "No model context available."
            return
        }
        guard let dataset = storedDatasets.first(where: { $0.id == datasetID }) else {
            analysis.statusMessage = "Dataset not found."
            return
        }
        guard let fileData = dataset.fileData, !fileData.isEmpty else {
            analysis.statusMessage = "No source file data stored for this dataset. Re-import from the original file."
            return
        }

        let fileName = dataset.fileName

        // Re-parse using the appropriate parser
        let parseResult: ShimadzuSPCParseResult
        do {
            if GalacticSPCParser.canParse(fileData) {
                // Write to a temporary file since the parser expects a URL
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try fileData.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                let parser = try GalacticSPCParser(fileURL: tempURL)
                parseResult = try parser.extractSpectraResult()
            } else {
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
                try fileData.write(to: tempURL)
                defer { try? FileManager.default.removeItem(at: tempURL) }
                let parser = try ShimadzuSPCParser(fileURL: tempURL)
                parseResult = try parser.extractSpectraResult()
            }
        } catch {
            analysis.statusMessage = "Re-parse failed: \(error.localizedDescription)"
            return
        }

        // Delete old spectra
        let spectraPredicate = #Predicate<StoredSpectrum> { $0.datasetID == datasetID }
        if let oldSpectra = try? ctx.fetch(FetchDescriptor<StoredSpectrum>(predicate: spectraPredicate)) {
            for spectrum in oldSpectra {
                ctx.delete(spectrum)
            }
        }

        // Create new spectra from re-parsed data
        let newSpectra = parseResult.spectra.enumerated().map { index, raw in
            let displayName = ContentView.sampleDisplayName(
                from: URL(fileURLWithPath: fileName),
                spectrumName: raw.name,
                index: index,
                total: parseResult.spectra.count
            )
            let reason = SpectrumValidation.invalidReason(x: raw.x, y: raw.y)
            return StoredSpectrum(
                datasetID: datasetID,
                name: displayName,
                orderIndex: index,
                xData: SpectrumBinaryCodec.encodeDoubles(raw.x),
                yData: SpectrumBinaryCodec.encodeDoubles(raw.y),
                isInvalid: reason != nil,
                invalidReason: reason
            )
        }

        // Update dataset metadata
        let metadataJSON = try? JSONEncoder().encode(parseResult.metadata)
        dataset.metadataJSON = metadataJSON
        dataset.headerInfoData = parseResult.headerInfoData
        dataset.spectra = newSpectra
        for spectrum in newSpectra {
            spectrum.dataset = dataset
            ctx.insert(spectrum)
        }

        // Unload old spectra from analysis if they were loaded
        analysis.unloadSpectra(forDatasetID: datasetID)

        let specCount = newSpectra.count
        analysis.statusMessage = "Re-parsed \(fileName): \(specCount) spectra updated."
        Instrumentation.log(
            "Dataset re-parsed",
            area: .importParsing, level: .info,
            details: "file=\(fileName) spectra=\(specCount)"
        )
    }

    func prepareDuplicateCleanup(storedDatasets: [StoredDataset], archivedDatasets: [StoredDataset]) {
        let allDatasets = storedDatasets + archivedDatasets
        guard allDatasets.count > 1 else {
            analysis.statusMessage = "No duplicates detected."
            return
        }

        // Read from cache to avoid touching model properties during CloudKit sync.
        let allCaches = searchableRecordCache.merging(archivedSearchableRecordCache) { a, _ in a }

        var duplicates: [StoredDataset] = []
        var seenKeys = Set<String>()
        // Sort by importedAt from cache
        let sorted = allDatasets.sorted { a, b in
            let aDate = allCaches[a.id]?.importedAt ?? .distantPast
            let bDate = allCaches[b.id]?.importedAt ?? .distantPast
            return aDate < bDate
        }
        for dataset in sorted {
            let record = allCaches[dataset.id]
            guard let key = datasetUniquenessKey(fileHash: record?.fileHash, sourcePath: record?.sourcePath) else {
                continue
            }
            if seenKeys.contains(key) {
                duplicates.append(dataset)
            } else {
                seenKeys.insert(key)
            }
        }

        guard !duplicates.isEmpty else {
            analysis.statusMessage = "No duplicates detected."
            return
        }

        duplicateCleanupTargetIDs = Set(duplicates.map { $0.id })
        let preview = datasetNamePreview(duplicates)
        let base = "This will permanently delete \(duplicates.count) duplicate stored dataset(s)."
        duplicateCleanupMessage = preview.isEmpty ? base : "\(base)\n\n\(preview)"
        showDuplicateCleanupConfirm = true
    }

    func removeDuplicateDatasets(storedDatasets: [StoredDataset], archivedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        let targetIDs = duplicateCleanupTargetIDs
        let datasets = (storedDatasets + archivedDatasets).filter { targetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            duplicateCleanupTargetIDs.removeAll()
            duplicateCleanupMessage = ""
            return
        }

        // Capture preview BEFORE delete (from cache — no model access)
        let preview = datasetNamePreview(datasets)
        let count = datasets.count

        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            ctx.delete(dataset)
        }

        let details = preview.isEmpty ? "count=\(count)" : "count=\(count) names=\(preview)"
        Instrumentation.log("Duplicate stored datasets deleted", area: .uiInteraction, level: .warning, details: details)
        analysis.statusMessage = "Removed \(count) duplicate dataset(s)."

        requestCloudSync(reason: "datasetDuplicateCleanup")

        duplicateCleanupTargetIDs.removeAll()
        duplicateCleanupMessage = ""
    }

    func archivePendingDatasets(storedDatasets: [StoredDataset]) {
        let targetIDs = pendingArchiveDatasetIDs
        let datasets = storedDatasets.filter { targetIDs.contains($0.id) }
        guard !datasets.isEmpty else {
            pendingArchiveDatasetIDs.removeAll()
            return
        }
        // Capture preview BEFORE mutation (from cache — no model access)
        let preview = datasetNamePreview(datasets)
        let count = datasets.count

        let now = Date()
        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            dataset.isArchived = true
            dataset.archivedAt = now
        }

        let details = preview.isEmpty ? "count=\(count)" : "count=\(count) names=\(preview)"
        Instrumentation.log("Stored datasets archived", area: .uiInteraction, level: .info, details: details)
        analysis.statusMessage = "Archived \(count) stored dataset(s)."

        requestCloudSync(reason: "datasetArchive")
        dataVersion += 1

        pendingArchiveDatasetIDs.removeAll()
        selectedStoredDatasetIDs.removeAll()
    }

    func restoreArchivedSelection(archivedDatasets: [StoredDataset]) {
        let datasets = archivedDatasets.filter { archivedDatasetSelection.contains($0.id) }
        guard !datasets.isEmpty else { return }
        // Capture preview BEFORE mutation (from cache — no model access)
        let preview = datasetNamePreview(datasets)
        let count = datasets.count

        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            dataset.isArchived = false
            dataset.archivedAt = nil
        }

        let details = preview.isEmpty ? "count=\(count)" : "count=\(count) names=\(preview)"
        Instrumentation.log("Stored datasets restored", area: .uiInteraction, level: .info, details: details)
        analysis.statusMessage = "Restored \(count) archived dataset(s)."

        requestCloudSync(reason: "datasetRestore")
        dataVersion += 1

        archivedDatasetSelection.removeAll()
    }

    func requestPermanentDeleteSelection() {
        let ids = archivedDatasetSelection
        guard !ids.isEmpty else { return }
        pendingPermanentDeleteIDs = ids
        showPermanentDeleteSheet = true
    }

    /// Request permanent deletion of active (non-archived) datasets directly.
    /// Shows a confirmation dialog before deleting.
    func requestPermanentDeleteFromActive(ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        pendingDirectDeleteIDs = ids
        showDirectDeleteConfirmation = true
    }

    func directDeleteConfirmationTitle() -> String {
        let count = pendingDirectDeleteIDs.count
        return count == 1 ? "Delete Dataset?" : "Delete \(count) Datasets?"
    }

    func directDeleteConfirmationMessage() -> String {
        let names = pendingDirectDeleteIDs.compactMap { id in
            searchableRecordCache[id]?.fileName ?? archivedSearchableRecordCache[id]?.fileName
        }
        let preview = names.prefix(3).joined(separator: ", ")
        let remainder = names.count - 3
        let nameText = remainder > 0 ? "\(preview) (+\(remainder) more)" : preview
        let base = "This permanently deletes the dataset and all its spectra. This cannot be undone."
        return nameText.isEmpty ? base : "\(base)\n\n\(nameText)"
    }

    /// Permanently delete active datasets without archiving first.
    func permanentlyDeleteActiveDatasets(storedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        let ids = pendingDirectDeleteIDs
        let datasets = storedDatasets.filter { ids.contains($0.id) }
        guard !datasets.isEmpty else {
            pendingDirectDeleteIDs.removeAll()
            return
        }
        let preview = datasetNamePreview(datasets)
        let count = datasets.count

        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            ctx.delete(dataset)
        }

        // Remove from selection
        for id in ids {
            selectedStoredDatasetIDs.remove(id)
        }

        let details = preview.isEmpty ? "count=\(count)" : "count=\(count) names=\(preview)"
        Instrumentation.log("Active datasets permanently deleted", area: .uiInteraction, level: .warning, details: details)
        analysis.statusMessage = "Permanently deleted \(count) dataset(s)."

        requestCloudSync(reason: "datasetDelete")
        dataVersion += 1

        pendingDirectDeleteIDs.removeAll()
    }

    func deleteArchivedDatasets(archivedDatasets: [StoredDataset]) {
        guard let ctx = modelContext else { return }
        let ids = effectivePermanentDeleteIDs
        let datasets = archivedDatasets.filter { ids.contains($0.id) }
        guard !datasets.isEmpty else {
            pendingPermanentDeleteIDs.removeAll()
            return
        }
        // Capture preview BEFORE delete (from cache — no model access)
        let preview = datasetNamePreview(datasets)
        let count = datasets.count

        for dataset in datasets {
            guard dataset.modelContext != nil else { continue }
            ctx.delete(dataset)
        }

        let details = preview.isEmpty ? "count=\(count)" : "count=\(count) names=\(preview)"
        Instrumentation.log("Archived datasets deleted", area: .uiInteraction, level: .warning, details: details)
        analysis.statusMessage = "Deleted \(count) archived dataset(s)."

        requestCloudSync(reason: "datasetDelete")
        dataVersion += 1

        pendingPermanentDeleteIDs.removeAll()
        archivedDatasetSelection.removeAll()
    }

    // MARK: - Cloud Sync

    func requestCloudSync(reason: String) {
        guard let dataStoreController else { return }
        analysis.statusMessage = "iCloud sync requested (\(reason))."
        Instrumentation.log("Requesting iCloud sync", area: .uiInteraction, level: .warning, details: "reason=\(reason)")
        Task {
            let result = await ICloudSyncCoordinator.shared.performBackupNow(reason: reason)
            if reason == "manual" && dataStoreController.cloudSyncEnabled {
                let uploadResult = await ICloudSyncCoordinator.shared.forceCloudKitUpload()
                analysis.statusMessage = "iCloud sync result (\(reason)): \(result). Force upload: \(uploadResult)."
            } else {
                analysis.statusMessage = "iCloud sync result (\(reason)): \(result)."
            }
            Instrumentation.log(
                "iCloud sync result",
                area: .uiInteraction,
                level: .warning,
                details: "reason=\(reason) result=\(result)"
            )
        }
    }

    func requestForceUpload(reason: String) {
        analysis.statusMessage = "iCloud force upload requested (\(reason))."
        Instrumentation.log("Requesting CloudKit force upload", area: .uiInteraction, level: .warning, details: "reason=\(reason)")
        Task {
            let result = await ICloudSyncCoordinator.shared.forceCloudKitUpload()
            analysis.statusMessage = "iCloud force upload result (\(reason)): \(result)."
            Instrumentation.log(
                "CloudKit force upload result",
                area: .uiInteraction,
                level: .warning,
                details: "reason=\(reason) result=\(result)"
            )
        }
    }
}
