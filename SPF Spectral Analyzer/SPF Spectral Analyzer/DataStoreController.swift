import Foundation
import SwiftUI
import Combine
import SwiftData
import CloudKit
import AppKit

extension Notification.Name {
    static let cloudKitHistoryEvent = Notification.Name("cloudKitHistoryEvent")
}

enum CloudSyncPhase: String, Codable {
    case idle
    case preparing
    case migrating
    case uploading
    case resetting
    case downloading
    case completed
    case failed
}

struct CloudSyncState: Equatable {
    var phase: CloudSyncPhase = .idle
    var message: String = "Idle"
    var progress: Double = 0
    var transferredBytes: Int64 = 0
    var totalBytes: Int64 = 0
    var isActive: Bool = false
    var detail: String = ""
}

struct CloudSyncHistoryEntry: Identifiable, Codable, Equatable {
    let id: UUID
    let timestamp: Date
    let message: String
    let detail: String
    let phase: CloudSyncPhase

    init(message: String, detail: String, phase: CloudSyncPhase, timestamp: Date = Date()) {
        self.id = UUID()
        self.timestamp = timestamp
        self.message = message
        self.detail = detail
        self.phase = phase
    }
}

private actor CloudAvailabilityMonitor {
    static let shared = CloudAvailabilityMonitor()

    func run(controller: DataStoreController) async {
        var attempt = 0
        var delaySeconds: TimeInterval = 5
        while !Task.isCancelled {
            let shouldCheckAvailability = await MainActor.run {
                controller.cloudSyncEnabled && controller.storeMode == "local"
            }
            if !shouldCheckAvailability {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                continue
            }

            attempt += 1
            let currentAttempt = attempt
            let currentDelaySeconds = delaySeconds
            let statusMessage = "Checking iCloud availability (attempt \(currentAttempt))"
            await MainActor.run {
                controller.updateSyncState(
                    phase: .preparing,
                    message: statusMessage,
                    progress: 0,
                    detail: "Next retry in \(Int(currentDelaySeconds))s"
                )
                Instrumentation.log(
                    "CloudKit availability check",
                    area: .uiInteraction,
                    level: .info,
                    details: "attempt=\(currentAttempt) delay=\(Int(currentDelaySeconds))s"
                )
            }

            do {
                let status = try await CKContainer.default().accountStatus()
                if status == .available {
                    await MainActor.run {
                        controller.updateSyncState(phase: .completed, message: "iCloud available", progress: 1.0)
                    }
                    await controller.enableCloudSyncAndFullSync()
                    attempt = 0
                    delaySeconds = 5
                    continue
                } else {
                    let currentDelaySeconds = delaySeconds
                    await MainActor.run {
                        controller.updateSyncState(
                            phase: .idle,
                            message: "iCloud unavailable (\(status))",
                            progress: 0,
                            detail: "Next retry in \(Int(currentDelaySeconds))s"
                        )
                    }
                }
            } catch {
                let currentDelaySeconds = delaySeconds
                await MainActor.run {
                    controller.updateSyncState(
                        phase: .idle,
                        message: "iCloud check failed",
                        progress: 0,
                        detail: "\(error.localizedDescription) • Next retry in \(Int(currentDelaySeconds))s"
                    )
                }
            }

            let sleep = UInt64(delaySeconds * 1_000_000_000)
            try? await Task.sleep(nanoseconds: sleep)
            delaySeconds = min(delaySeconds * 2, 900)
        }
    }
}

private actor FileCleanupWorker {
    static let shared = FileCleanupWorker()

    func scheduleCleanup(urls: [URL], delaySeconds: TimeInterval, storePath: String) async {
        let sleep = UInt64(delaySeconds * 1_000_000_000)
        try? await Task.sleep(nanoseconds: sleep)
        for fileURL in urls where FileManager.default.fileExists(atPath: fileURL.path) {
            try? FileManager.default.removeItem(at: fileURL)
        }
        await MainActor.run {
            Instrumentation.log(
                "Deferred store cleanup complete",
                area: .processing,
                level: .info,
                details: "store=\(storePath)"
            )
        }
    }
}

@MainActor
final class DataStoreController: ObservableObject {
    @Published private(set) var container: ModelContainer
    @Published private(set) var containerID = UUID()
    @Published private(set) var syncState = CloudSyncState()
    @Published private(set) var storeMode: String
    @Published private(set) var cloudSyncEnabled: Bool
    @Published private(set) var cloudKitUnavailable: Bool
    @Published private(set) var cloudKitUnavailableMessage: String
    @Published private(set) var syncHistory: [CloudSyncHistoryEntry] = []
    @Published private(set) var queuedActionMessage: String? = nil
    private var availabilityTask: Task<Void, Never>?
    private var lastStatusSignature: String?
    private var lastStatusUpdate: Date?
    private var pendingCloudSyncToggle: Bool?
    private var isApplyingPendingToggle = false
    private var isSwitchingStore = false

    private static let initCountLock = NSLock()
    private static var initCount = 0

    private let schema = Schema([StoredDataset.self, StoredSpectrum.self, StoredInstrument.self, Item.self] as [any PersistentModel.Type])

    #if DEBUG
    func runCloudKitSchemaInit() {
        let configuration = ModelConfiguration(
            "SchemaInit",
            schema: schema,
            url: Self.storeURL(kind: .cloud),
            allowsSave: false,
            cloudKitDatabase: .private(Self.cloudKitContainerIdentifier)
        )
        Shimadzu_Data_AnalyserApp.initializeCloudKitSchemaIfNeeded(schema: schema, configuration: configuration)
    }
    #endif

    init() {
        #if DEBUG
        let initIndex: Int = {
            Self.initCountLock.lock()
            defer { Self.initCountLock.unlock() }
            Self.initCount += 1
            return Self.initCount
        }()
        Instrumentation.log(
            "DataStoreController init",
            area: .processing,
            level: .info,
            details: "count=\(initIndex) \(Instrumentation.threadContext())"
        )
        #endif
        let defaults = UserDefaults.standard
        let initialCloudSyncEnabled = defaults.bool(forKey: ICloudDefaultsKeys.syncEnabled)
        let initialCloudKitUnavailable = defaults.bool(forKey: ICloudDefaultsKeys.cloudKitUnavailable)
        let initialCloudKitMessage = defaults.string(forKey: ICloudDefaultsKeys.cloudKitUnavailableMessage) ?? ""

        let initialContainer: ModelContainer
        var resolvedStoreMode = "local"
        var resolvedUnavailable = initialCloudKitUnavailable
        var resolvedUnavailableMessage = initialCloudKitMessage
        do {
            initialContainer = try DataStoreController.makeContainer(
                schema: schema,
                useCloudSync: false,
                storeURL: Self.storeURL(kind: .local)
            )
            resolvedStoreMode = "local"
        } catch {
            initialContainer = (try? DataStoreController.makeContainer(schema: schema, useCloudSync: false, storeURL: Self.storeURL(kind: .local))) ?? {
                fatalError("Failed to create local model container: \(error)")
            }()
            resolvedStoreMode = "local"
            resolvedUnavailable = true
            let detail = Self.detailedErrorDescription(error)
            resolvedUnavailableMessage = "CloudKit is unavailable. The app is using local storage until CloudKit becomes available.\n\(detail)"
        }

        cloudSyncEnabled = initialCloudSyncEnabled
        cloudKitUnavailable = resolvedUnavailable
        cloudKitUnavailableMessage = resolvedUnavailableMessage
        storeMode = resolvedStoreMode
        container = initialContainer
        ICloudSyncCoordinator.shared.configure(container: container)
        syncHistory = loadSyncHistory()

        if initialCloudSyncEnabled {
            Task { await enableCloudSyncAndFullSync() }
        }

        refreshCloudKitAccountStatus()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.checkCloudAvailabilityAndMigrateIfNeeded()
            }
            Task { @MainActor [weak self] in
                self?.refreshCloudKitAccountStatus()
            }
        }

        if initialCloudSyncEnabled {
            startAvailabilityMonitor()
        }

        NotificationCenter.default.addObserver(
            forName: .cloudKitHistoryEvent,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self else { return }
            let message = notification.userInfo?["message"] as? String ?? "CloudKit event"
            let detail = notification.userInfo?["detail"] as? String ?? ""
            let phaseRaw = notification.userInfo?["phase"] as? String ?? CloudSyncPhase.completed.rawValue
            let phase = CloudSyncPhase(rawValue: phaseRaw) ?? .completed
            let progress = notification.userInfo?["progress"] as? Double ?? (phase == .completed ? 1.0 : 0)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.appendSyncHistory(message: message, detail: detail, phase: phase)
                self.updateSyncState(
                    phase: phase,
                    message: message,
                    progress: progress,
                    detail: detail
                )
            }
        }
    }

    private func refreshCloudKitAccountStatus() {
        let containerID = Self.cloudKitContainerIdentifier
        UserDefaults.standard.set(containerID, forKey: ICloudDefaultsKeys.cloudKitContainerIdentifier)
        #if DEBUG
        let envLabel = "development"
        #else
        let envLabel = "production"
        #endif
        UserDefaults.standard.set(envLabel, forKey: ICloudDefaultsKeys.cloudKitEnvironmentLabel)
        let statusKey = ICloudDefaultsKeys.cloudKitAccountStatus
        Task {
            let statusText: String
            do {
                let status = try await CKContainer.default().accountStatus()
                switch status {
                case .available: statusText = "available"
                case .noAccount: statusText = "noAccount"
                case .restricted: statusText = "restricted"
                case .couldNotDetermine: statusText = "couldNotDetermine"
                case .temporarilyUnavailable: statusText = "temporarilyUnavailable"
                @unknown default: statusText = "unknown"
                }
            } catch {
                statusText = "error: \(error.localizedDescription)"
            }
            await MainActor.run {
                UserDefaults.standard.set(statusText, forKey: statusKey)
            }
        }
    }

    @MainActor
    func setCloudSyncEnabled(_ enabled: Bool) {
        cloudSyncEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: ICloudDefaultsKeys.syncEnabled)
        if enabled {
            Task { await enableCloudSyncAndFullSync() }
            startAvailabilityMonitor()
        } else {
            stopAvailabilityMonitor()
            Task { await switchToLocal() }
        }
    }

    func enableCloudSyncAndFullSync() async {
        if storeMode == "cloudKit" {
            updateSyncState(phase: .completed, message: "iCloud sync enabled", progress: 1.0)
            return
        }
        guard !isSwitchingStore else { return }
        isSwitchingStore = true
        defer { isSwitchingStore = false }

        updateSyncState(phase: .preparing, message: "Preparing iCloud sync", progress: 0)
        let result = await switchToCloudContainer()
        switch result {
        case .success:
            updateSyncState(phase: .completed, message: "iCloud sync enabled", progress: 1.0)
        case .failure(let error):
            updateSyncState(phase: .failed, message: "iCloud sync failed", progress: 0, detail: error.localizedDescription)
        }
    }

    func autoMigrateIfNeeded() async {
        guard cloudSyncEnabled else { return }
        if storeMode == "local" {
            await enableCloudSyncAndFullSync()
        } else {
            updateCloudKitUnavailable(message: "")
        }
    }

    func checkCloudAvailabilityAndMigrateIfNeeded() async {
        guard cloudSyncEnabled, storeMode == "local" else { return }
        do {
            let status = try await CKContainer.default().accountStatus()
            if status == .available {
                await enableCloudSyncAndFullSync()
            }
        } catch {
            updateSyncState(phase: .idle, message: "Waiting for iCloud", progress: 0, detail: error.localizedDescription)
        }
    }

    private func startAvailabilityMonitor() {
        availabilityTask?.cancel()
        availabilityTask = Task { [weak self] in
            guard let self else { return }
            await CloudAvailabilityMonitor.shared.run(controller: self)
        }
    }

    private func stopAvailabilityMonitor() {
        availabilityTask?.cancel()
        availabilityTask = nil
    }

    func forceFullSync() async {
        guard cloudSyncEnabled else { return }
        updateSyncState(phase: .resetting, message: "Resetting local cache", progress: 0.2)
        await resetCloudLocalCache()
        updateSyncState(phase: .completed, message: "iCloud sync reset", progress: 1.0)
    }

    func noteLocalChange(bytes: Int64) {
        guard storeMode == "cloudKit" else { return }
        updateSyncState(phase: .uploading, message: "Uploading changes to iCloud", progress: 0.1)
        updateSyncState(
            phase: .uploading,
            message: "Uploading changes to iCloud",
            progress: 0.3,
            transferredBytes: bytes,
            totalBytes: max(bytes, 1)
        )
        updateSyncState(phase: .completed, message: "Changes queued for iCloud", progress: 1.0)
    }

    private func switchToLocal() async {
        if storeMode == "local" {
            updateSyncState(phase: .idle, message: "iCloud sync disabled", progress: 0)
            return
        }
        guard !isSwitchingStore else { return }
        isSwitchingStore = true
        defer { isSwitchingStore = false }

        do {
            let newContainer = try DataStoreController.makeContainer(
                schema: schema,
                useCloudSync: false,
                storeURL: Self.storeURL(kind: .local)
            )
            swapContainer(newContainer, mode: "local")
            updateSyncState(phase: .idle, message: "iCloud sync disabled", progress: 0)
        } catch {
            updateSyncState(phase: .failed, message: "Failed to switch to local", progress: 0, detail: error.localizedDescription)
        }
    }

    private func switchToCloudContainer() async -> Result<Void, Error> {
        if storeMode == "cloudKit" {
            return .success(())
        }
        do {
            let newContainer = try DataStoreController.makeContainer(
                schema: schema,
                useCloudSync: true,
                storeURL: Self.storeURL(kind: .cloud)
            )
            swapContainer(newContainer, mode: "cloudKit")
            updateCloudKitUnavailable(message: "")
            return .success(())
        } catch {
            let detail = Self.detailedErrorDescription(error)
            updateCloudKitUnavailable(
                message: "CloudKit is unavailable. The app is using local storage until CloudKit becomes available.\n\(detail)"
            )
            return .failure(error)
        }
    }

    private func migrateLocalDataToCloud() async -> Result<Void, Error> {
        do {
            let cloudContainer = try DataStoreController.makeContainer(
                schema: schema,
                useCloudSync: true,
                storeURL: Self.storeURL(kind: .cloud)
            )
            let result = await migrateLocalDataToCloud(sourceContainer: container, destinationContainer: cloudContainer)
            if case .success = result {
                swapContainer(cloudContainer, mode: "cloudKit")
            }
            return result
        } catch {
            return .failure(error)
        }
    }

    private func migrateLocalDataToCloud(
        sourceContainer: ModelContainer,
        destinationContainer: ModelContainer
    ) async -> Result<Void, Error> {
        let sourceContext = ModelContext(sourceContainer)
        let destinationContext = ModelContext(destinationContainer)

        do {
            let datasets = try sourceContext.fetch(FetchDescriptor<StoredDataset>())
            let totalBytes = estimateTotalBytes(datasets: datasets)
            updateSyncState(
                phase: .migrating,
                message: "Migrating local data to iCloud",
                progress: 0.0,
                transferredBytes: 0,
                totalBytes: totalBytes
            )

            var transferred: Int64 = 0
            for dataset in datasets {
                guard dataset.modelContext != nil else { continue }

                if try hasDataset(dataset, in: destinationContext) {
                    transferred += estimateDatasetBytes(dataset)
                    updateMigrationProgress(transferred: transferred, total: totalBytes)
                    continue
                }

                // Snapshot all source properties in one pass before creating
                // the destination objects, so we don't re-read from the source
                // model during the copy loop.
                let dsID = dataset.id
                let dsFileName = dataset.fileName
                let dsSourcePath = dataset.sourcePath
                let dsImportedAt = dataset.importedAt
                let dsFileHash = dataset.fileHash
                let dsFileData = dataset.fileData
                let dsMetadataJSON = dataset.metadataJSON
                let dsHeaderInfoData = dataset.headerInfoData
                let dsSkippedDataJSON = dataset.skippedDataJSON
                let dsWarningsJSON = dataset.warningsJSON
                let dsHdrsMetadataJSON = dataset.hdrsMetadataJSON
                let dsDatasetRole = dataset.datasetRole
                let dsKnownInVivoSPF = dataset.knownInVivoSPF
                let dsHdrsTagsJSON = dataset.hdrsTagsJSON
                let dsInstrumentID = dataset.instrumentID
                let sourceSpectra = dataset.spectraItems

                let newDataset = StoredDataset(
                    id: dsID,
                    fileName: dsFileName,
                    sourcePath: dsSourcePath,
                    importedAt: dsImportedAt,
                    lastSyncedAt: Date(),
                    fileHash: dsFileHash,
                    fileData: dsFileData,
                    metadataJSON: dsMetadataJSON,
                    headerInfoData: dsHeaderInfoData,
                    skippedDataJSON: dsSkippedDataJSON,
                    warningsJSON: dsWarningsJSON,
                    spectra: [],
                    hdrsMetadataJSON: dsHdrsMetadataJSON,
                    datasetRole: dsDatasetRole,
                    knownInVivoSPF: dsKnownInVivoSPF,
                    hdrsTagsJSON: dsHdrsTagsJSON,
                    instrumentID: dsInstrumentID
                )
                destinationContext.insert(newDataset)

                for spectrum in sourceSpectra {
                    guard spectrum.modelContext != nil else { continue }
                    let newSpectrum = StoredSpectrum(
                        id: spectrum.id,
                        datasetID: spectrum.datasetID,
                        name: spectrum.name,
                        orderIndex: spectrum.orderIndex,
                        xData: spectrum.xData,
                        yData: spectrum.yData,
                        isInvalid: spectrum.isInvalid,
                        invalidReason: spectrum.invalidReason,
                        lastSyncedAt: Date()
                    )
                    newSpectrum.dataset = newDataset
                    newDataset.spectraItems.append(newSpectrum)
                }

                transferred += estimateDatasetBytes(dataset)
                updateMigrationProgress(transferred: transferred, total: totalBytes)

                if transferred % (8 * 1024 * 1024) == 0 {
                    try? ObjCExceptionCatcher.try {
                        try? destinationContext.save()
                    }
                }
            }

            try? ObjCExceptionCatcher.try {
                try? destinationContext.save()
            }

            // Migrate StoredInstrument objects
            let instruments = (try? sourceContext.fetch(FetchDescriptor<StoredInstrument>())) ?? []
            for instrument in instruments {
                guard instrument.modelContext != nil else { continue }
                let newInstrument = StoredInstrument(
                    id: instrument.id,
                    manufacturer: instrument.manufacturer,
                    modelName: instrument.modelName,
                    serialNumber: instrument.serialNumber,
                    labNumber: instrument.labNumber,
                    locationAddress: instrument.locationAddress,
                    locationLatitude: instrument.locationLatitude,
                    locationLongitude: instrument.locationLongitude,
                    instrumentType: instrument.instrumentType,
                    createdAt: instrument.createdAt,
                    notes: instrument.notes
                )
                destinationContext.insert(newInstrument)
            }
            if !instruments.isEmpty {
                try? ObjCExceptionCatcher.try {
                    try? destinationContext.save()
                }
            }

            updateSyncState(phase: .completed, message: "Local data uploaded to iCloud", progress: 1.0)
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    private func resetCloudLocalCache() async {
        do {
            let oldStoreURL = Self.storeURL(kind: .cloud)
            let resetStoreURL = Self.storeURL(kind: .cloud, suffix: "reset-\(Int(Date().timeIntervalSince1970))")
            let freshContainer = try DataStoreController.makeContainer(
                schema: schema,
                useCloudSync: true,
                storeURL: resetStoreURL
            )
            swapContainer(freshContainer, mode: "cloudKit")
            scheduleStoreDeletion(oldStoreURL, after: 5)
        } catch {
            updateSyncState(phase: .failed, message: "Failed to reset local cache", progress: 0, detail: error.localizedDescription)
        }
    }

    private func swapContainer(_ newContainer: ModelContainer, mode: String) {
        Task { @MainActor in
            self.container = newContainer
            self.containerID = UUID()
            self.storeMode = mode
        }
        UserDefaults.standard.set(mode, forKey: ICloudDefaultsKeys.storeMode)
        ICloudSyncCoordinator.shared.configure(container: newContainer)
        if mode == "cloudKit" {
            updateCloudKitUnavailable(message: "")
        }
    }

    private func updateCloudKitUnavailable(message: String) {
        let isUnavailable = !message.isEmpty
        Task { @MainActor in
            self.cloudKitUnavailable = isUnavailable
            self.cloudKitUnavailableMessage = message
        }
        UserDefaults.standard.set(isUnavailable, forKey: ICloudDefaultsKeys.cloudKitUnavailable)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.cloudKitUnavailableMessage)
    }

    fileprivate func updateSyncState(
        phase: CloudSyncPhase,
        message: String,
        progress: Double,
        transferredBytes: Int64? = nil,
        totalBytes: Int64? = nil,
        detail: String = ""
    ) {
        let clampedProgress = min(max(progress, 0), 1)
        let signature = "\(phase.rawValue)|\(message)|\(detail)"
        let now = Date()
        let shouldRecord: Bool = {
            guard let lastSignature = lastStatusSignature, let lastUpdate = lastStatusUpdate else {
                return true
            }
            if signature != lastSignature { return true }
            return now.timeIntervalSince(lastUpdate) > 15
        }()
        if phase == .completed && (syncState.phase == .uploading || syncState.phase == .migrating) {
            UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "icloudLastPushTimestamp")
        }
        Task { @MainActor in
            self.syncState = CloudSyncState(
                phase: phase,
                message: message,
                progress: clampedProgress,
                transferredBytes: transferredBytes ?? self.syncState.transferredBytes,
                totalBytes: totalBytes ?? self.syncState.totalBytes,
                isActive: phase != .idle && phase != .completed,
                detail: detail
            )
        }
        UserDefaults.standard.set(phase != .idle && phase != .completed, forKey: ICloudDefaultsKeys.syncInProgress)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.lastSyncStatus)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: ICloudDefaultsKeys.lastSyncTimestamp)
        if shouldRecord {
            lastStatusSignature = signature
            lastStatusUpdate = now
            appendSyncHistory(message: message, detail: detail, phase: phase)
        }

        if phase == .completed || phase == .idle || phase == .failed {
            Task { @MainActor in
                applyPendingCloudSyncToggleIfNeeded()
            }
        }
    }

    private func queueCloudSyncToggle(_ enabled: Bool) {
        pendingCloudSyncToggle = enabled
        let action = enabled ? "enable" : "disable"
        let message = "Queued iCloud sync \(action)"
        Task { @MainActor in
            queuedActionMessage = message
        }
        appendSyncHistory(
            message: message,
            detail: "Will apply after current sync finishes.",
            phase: .preparing
        )
    }

    @MainActor
    func setQueuedActionMessage(_ message: String?) {
        queuedActionMessage = message
    }

    @MainActor
    private func applyPendingCloudSyncToggleIfNeeded() {
        guard let pending = pendingCloudSyncToggle, !syncState.isActive else { return }
        pendingCloudSyncToggle = nil
        queuedActionMessage = nil
        isApplyingPendingToggle = true
        setCloudSyncEnabled(pending)
        isApplyingPendingToggle = false
    }

    private func updateMigrationProgress(transferred: Int64, total: Int64) {
        let progress = total > 0 ? Double(transferred) / Double(total) : 0
        updateSyncState(
            phase: .migrating,
            message: "Migrating local data to iCloud",
            progress: progress,
            transferredBytes: transferred,
            totalBytes: total
        )
    }

    private func estimateTotalBytes(datasets: [StoredDataset]) -> Int64 {
        datasets.reduce(0) { $0 + estimateDatasetBytes($1) }
    }

    private func estimateDatasetBytes(_ dataset: StoredDataset) -> Int64 {
        guard dataset.modelContext != nil else { return 0 }
        var total: Int64 = 0
        total += Int64(dataset.fileData?.count ?? 0)
        total += Int64(dataset.metadataJSON?.count ?? 0)
        total += Int64(dataset.headerInfoData?.count ?? 0)
        total += Int64(dataset.skippedDataJSON?.count ?? 0)
        total += Int64(dataset.warningsJSON?.count ?? 0)
        // Use spectraItems directly here since this is called during
        // migration where the source context is stable (not CloudKit-backed).
        for spectrum in dataset.spectraItems {
            total += Int64(spectrum.xData.count + spectrum.yData.count)
        }
        return total
    }

    private func hasDataset(_ dataset: StoredDataset, in context: ModelContext) throws -> Bool {
        let datasetID = dataset.id
        let fileName = dataset.fileName
        let importedAt = dataset.importedAt

        if let fileHash = dataset.fileHash, !fileHash.isEmpty {
            let descriptor = FetchDescriptor<StoredDataset>(predicate: #Predicate {
                $0.id == datasetID || ($0.fileHash == fileHash && $0.fileName == fileName)
            })
            return try context.fetchCount(descriptor) > 0
        }

        let descriptor = FetchDescriptor<StoredDataset>(predicate: #Predicate {
            $0.id == datasetID || ($0.fileName == fileName && $0.importedAt == importedAt)
        })
        return try context.fetchCount(descriptor) > 0
    }

    private func scheduleStoreDeletion(_ url: URL, after delaySeconds: TimeInterval) {
        let basePath = url.path
        let urls = [
            url,
            URL(fileURLWithPath: basePath + "-shm"),
            URL(fileURLWithPath: basePath + "-wal")
        ]
        Instrumentation.log(
            "Deferred store cleanup scheduled",
            area: .processing,
            level: .warning,
            details: "store=\(url.path) delay=\(Int(delaySeconds))s"
        )
        Task {
            await FileCleanupWorker.shared.scheduleCleanup(urls: urls, delaySeconds: delaySeconds, storePath: url.path)
        }
    }

    private func appendSyncHistory(message: String, detail: String, phase: CloudSyncPhase) {
        let entry = CloudSyncHistoryEntry(message: message, detail: detail, phase: phase)
        Task { @MainActor in
            self.syncHistory.insert(entry, at: 0)
            if self.syncHistory.count > 100 {
                self.syncHistory.removeLast(self.syncHistory.count - 100)
            }
        }
        saveSyncHistory(entry)
    }

    private func saveSyncHistory(_ entry: CloudSyncHistoryEntry) {
        var entries = loadSyncHistory()
        entries.insert(entry, at: 0)
        if entries.count > 100 {
            entries = Array(entries.prefix(100))
        }
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: ICloudDefaultsKeys.syncStatusHistoryData)
        }
    }

    private static func detailedErrorDescription(_ error: Error) -> String {
        var lines: [String] = []
        var current: Error? = error
        var depth = 0
        while let currentError = current, depth < 5 {
            let nsError = currentError as NSError
            lines.append("Error: \(String(reflecting: currentError))")
            lines.append("Domain: \(nsError.domain) Code: \(nsError.code)")
            if let ckError = currentError as? CKError {
                lines.append("CKError code: \(ckError.code)")
                if let retryAfter = ckError.userInfo[CKErrorRetryAfterKey] {
                    lines.append("CKError retryAfter: \(retryAfter)")
                }
                if !ckError.userInfo.isEmpty {
                    lines.append("CKError userInfo: \(ckError.userInfo)")
                }
            }
            if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
                current = underlying
            } else {
                current = nil
            }
            depth += 1
        }
        return lines.joined(separator: " | ")
    }

    private func loadSyncHistory() -> [CloudSyncHistoryEntry] {
        guard let data = UserDefaults.standard.data(forKey: ICloudDefaultsKeys.syncStatusHistoryData),
              let entries = try? JSONDecoder().decode([CloudSyncHistoryEntry].self, from: data) else {
            return []
        }
        return entries
    }

    private static let cloudKitContainerIdentifier = "iCloud.com.zincoverde.SPFSpectralAnalyzer"
    private static let storeFilename = "SPFSpectralAnalyzer.store"
    private static let schemaInitQueue = DispatchQueue(label: "CloudKitSchemaInitGuard")
    private static var initializedSchemaStores = Set<String>()

    private enum StoreKind: String {
        case local
        case cloud
    }

    private static func storeURL(kind: StoreKind, suffix: String? = nil) -> URL {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "SPF Spectral Analyzer"
        let appDirectory = (baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(bundleID, isDirectory: true)
        if !FileManager.default.fileExists(atPath: appDirectory.path) {
            try? FileManager.default.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        }
        let filename: String
        if let suffix, !suffix.isEmpty {
            filename = "\(storeFilename).\(kind.rawValue).\(suffix)"
        } else {
            filename = "\(storeFilename).\(kind.rawValue)"
        }
        return appDirectory.appendingPathComponent(filename, isDirectory: false)
    }

    private static func shouldInitializeSchema(for storePath: String) -> Bool {
        schemaInitQueue.sync {
            if initializedSchemaStores.contains(storePath) {
                return false
            }
            initializedSchemaStores.insert(storePath)
            return true
        }
    }

    private static func makeContainer(schema: Schema, useCloudSync: Bool, storeURL: URL? = nil) throws -> ModelContainer {
        let cloudDatabase: ModelConfiguration.CloudKitDatabase = useCloudSync
            ? .private(cloudKitContainerIdentifier)
            : .none
        let resolvedStoreURL = storeURL ?? Self.storeURL(kind: useCloudSync ? .cloud : .local)
        let configuration = ModelConfiguration(
            "Main",
            schema: schema,
            url: resolvedStoreURL,
            allowsSave: true,
            cloudKitDatabase: cloudDatabase
        )
        let makeStart = CFAbsoluteTimeGetCurrent()
        Instrumentation.log(
            "ModelContainer creation start",
            area: .processing,
            level: .info,
            details: "cloudSync=\(useCloudSync) store=\(configuration.url.path) \(Instrumentation.threadContext())"
        )
        #if DEBUG
        let shouldAutoInitSchema = UserDefaults.standard.bool(forKey: "cloudKitSchemaInitOnLaunch")
        if useCloudSync && shouldAutoInitSchema && shouldInitializeSchema(for: configuration.url.path) {
            let schemaStart = CFAbsoluteTimeGetCurrent()
            Instrumentation.log(
                "CloudKit schema init dispatch",
                area: .processing,
                level: .info,
                details: "store=\(configuration.url.path) \(Instrumentation.threadContext())"
            )
            let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            if !isRunningTests {
                if Thread.isMainThread {
                    // Run schema init on the main actor without blocking launch.
                    Task { @MainActor in
                        Shimadzu_Data_AnalyserApp.initializeCloudKitSchemaIfNeeded(schema: schema, configuration: configuration)
                    }
                } else {
                    Shimadzu_Data_AnalyserApp.initializeCloudKitSchemaIfNeeded(schema: schema, configuration: configuration)
                }
            }
            let schemaDuration = CFAbsoluteTimeGetCurrent() - schemaStart
            Instrumentation.log(
                "CloudKit schema init dispatch complete",
                area: .processing,
                level: .info,
                details: "store=\(configuration.url.path) \(Instrumentation.threadContext())",
                duration: schemaDuration
            )
        }
        #endif
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let makeDuration = CFAbsoluteTimeGetCurrent() - makeStart
        Instrumentation.log(
            "ModelContainer creation complete",
            area: .processing,
            level: .info,
            details: "cloudSync=\(useCloudSync) store=\(configuration.url.path) \(Instrumentation.threadContext())",
            duration: makeDuration
        )
        return container
    }
}
