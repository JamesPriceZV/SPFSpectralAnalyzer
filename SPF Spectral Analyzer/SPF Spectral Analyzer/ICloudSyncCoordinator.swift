import Foundation
import SwiftData
import AppKit
import CoreData

enum ICloudDefaultsKeys {
    static let syncEnabled = "icloudSyncEnabled"
    static let settingsSyncEnabled = "icloudSettingsSyncEnabled"
    static let autoBackupEnabled = "icloudAutoBackupEnabled"
    static let backupOnClose = "icloudBackupOnClose"
    static let backupIntervalHours = "icloudBackupIntervalHours"
    static let lastBackupTimestamp = "icloudLastBackupTimestamp"
    static let lastBackupStatus = "icloudLastBackupStatus"
    static let lastBackupSizeBytes = "icloudLastBackupSizeBytes"
    static let lastRestoreTimestamp = "icloudLastRestoreTimestamp"
    static let lastRestoreStatus = "icloudLastRestoreStatus"
    static let syncInProgress = "icloudSyncInProgress"
    static let lastSyncTimestamp = "icloudLastSyncTimestamp"
    static let lastSyncStatus = "icloudLastSyncStatus"
    static let lastSyncTrigger = "icloudLastSyncTrigger"
    static let syncStatusHistoryData = "icloudSyncStatusHistoryData"
    static let storeResetOccurred = "swiftDataStoreResetOccurred"
    static let storeResetMessage = "swiftDataStoreResetMessage"
    static let storeResetTimestamp = "swiftDataStoreResetTimestamp"
    static let storeResetHistoryData = "swiftDataStoreResetHistory"
    static let cloudKitUnavailable = "cloudKitUnavailable"
    static let cloudKitUnavailableMessage = "cloudKitUnavailableMessage"
    static let cloudKitAccountStatus = "cloudKitAccountStatus"
    static let cloudKitContainerIdentifier = "cloudKitContainerIdentifier"
    static let cloudKitEnvironmentLabel = "cloudKitEnvironmentLabel"
    static let storeMode = "swiftDataStoreMode"
    static let migrateOnRelaunch = "icloudMigrateOnRelaunch"
    static let skipBackupOnCloseOnce = "icloudSkipBackupOnCloseOnce"
}

final class ICloudSyncCoordinator {
    static let shared = ICloudSyncCoordinator()

    private var container: ModelContainer?
    private var backupTimer: Timer?
    private var kvsObserver: NSObjectProtocol?
    private var terminateObserver: NSObjectProtocol?
    private var cloudKitEventObserver: NSObjectProtocol?
    private var remoteChangeObserver: NSObjectProtocol?

    private init() {}

    func configure(container: ModelContainer) {
        self.container = container
        startObserversIfNeeded()
        scheduleBackupTimerIfNeeded()
    }

    func scheduleBackupTimerIfNeeded() {
        backupTimer?.invalidate()
        backupTimer = nil

        guard isAutoBackupEnabled else { return }
        let hours = max(0.25, backupIntervalHours)
        let interval = hours * 3600.0
        backupTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task {
                _ = await self?.performBackupNow(reason: "scheduled")
            }
        }
    }

    func performBackupNow(reason: String = "manual") async -> String {
        setLastSyncTrigger(reason)
        Instrumentation.log(
            "Backup requested",
            area: .uiInteraction,
            level: .warning,
            details: "reason=\(reason) syncEnabled=\(isSyncEnabled)"
        )
        guard isSyncEnabled else {
            updateBackupStatus(message: "iCloud sync is disabled")
            Instrumentation.log("Backup skipped", area: .uiInteraction, level: .warning, details: "reason=sync disabled")
            return "iCloud sync is disabled"
        }
        updateSyncStatus(message: "Sync in progress")
        guard let container else {
            updateSyncStatus(message: "Sync failed")
            updateBackupStatus(message: "iCloud sync unavailable")
            Instrumentation.log("Backup skipped", area: .uiInteraction, level: .warning, details: "reason=container unavailable")
            return "iCloud sync unavailable"
        }

        if isSettingsSyncEnabled {
            pushDefaultsToICloud()
        }

        do {
            let context = ModelContext(container)
            try context.save()
        } catch {
            updateSyncStatus(message: "Sync failed")
            updateBackupStatus(message: "Backup save failed: \(error.localizedDescription)")
            Instrumentation.log("Backup failed", area: .uiInteraction, level: .error, details: error.localizedDescription)
            return "Backup save failed"
        }

        if let size = try? estimateBackupSize(container: container) {
            UserDefaults.standard.set(size, forKey: ICloudDefaultsKeys.lastBackupSizeBytes)
        }

        updateBackupStatus(message: "Backup requested (\(reason))")
        updateSyncStatus(message: "Last sync: Backup")
        Instrumentation.log("Backup queued", area: .uiInteraction, level: .warning, details: "reason=\(reason)")
        return "Backup requested"
    }

    func forceCloudKitUpload() async -> String {
        let storeMode = UserDefaults.standard.string(forKey: ICloudDefaultsKeys.storeMode) ?? "unknown"
        Instrumentation.log(
            "Force CloudKit upload requested",
            area: .uiInteraction,
            level: .warning,
            details: "storeMode=\(storeMode)"
        )
        if storeMode != "cloudKit" {
            updateSyncStatus(message: "Force upload skipped (store mode: \(storeMode))")
            updateBackupStatus(message: "Force upload skipped: store mode \(storeMode)")
            Instrumentation.log(
                "Force CloudKit upload skipped",
                area: .uiInteraction,
                level: .warning,
                details: "reason=storeMode \(storeMode)"
            )
            return "Force upload skipped: store mode \(storeMode)"
        }
        guard isSyncEnabled else {
            updateSyncStatus(message: "iCloud sync is disabled")
            return "iCloud sync is disabled"
        }
        updateSyncStatus(message: "Sync in progress")
        guard let container else {
            updateSyncStatus(message: "Sync failed")
            updateBackupStatus(message: "iCloud sync unavailable")
            return "iCloud sync unavailable"
        }

        do {
            let context = ModelContext(container)
            let datasets = try context.fetch(FetchDescriptor<StoredDataset>())
            let now = Date()
            for dataset in datasets {
                dataset.lastSyncedAt = now
                for spectrum in dataset.spectraItems {
                    spectrum.lastSyncedAt = now
                }
            }
            try context.save()
            updateSyncStatus(message: "Last sync: Forced upload")
            updateBackupStatus(message: "Forced CloudKit upload queued")
            Instrumentation.log("Forced CloudKit upload", area: .uiInteraction, level: .warning, details: "datasets=\(datasets.count)")
            return "Forced upload queued"
        } catch {
            updateSyncStatus(message: "Sync failed")
            updateBackupStatus(message: "Forced upload failed: \(error.localizedDescription)")
            return "Forced upload failed"
        }
    }

    func performRestoreNow() async -> String {
        guard isSyncEnabled else {
            updateRestoreStatus(message: "iCloud sync is disabled")
            return "iCloud sync is disabled"
        }
        updateSyncStatus(message: "Sync in progress")

        if isSettingsSyncEnabled {
            pullDefaultsFromICloud()
        }

        if let container {
            let context = ModelContext(container)
            var descriptor = FetchDescriptor<StoredDataset>()
            descriptor.fetchLimit = 1
            _ = try? context.fetch(descriptor)
        }

        updateRestoreStatus(message: "Restore requested")
        updateSyncStatus(message: "Last sync: Restore")
        return "Restore requested"
    }

    func resetLocalStoreForRestore() async -> String {
        guard isSyncEnabled else {
            updateRestoreStatus(message: "iCloud sync is disabled")
            return "iCloud sync is disabled"
        }
        guard let storeURL = modelStoreURL() else {
            updateRestoreStatus(message: "Local store URL unavailable")
            return "Local store URL unavailable"
        }

        let basePath = storeURL.path
        let urlsToDelete = [
            storeURL,
            URL(fileURLWithPath: basePath + "-shm"),
            URL(fileURLWithPath: basePath + "-wal")
        ]

        do {
            for url in urlsToDelete {
                if FileManager.default.fileExists(atPath: url.path) {
                    try FileManager.default.removeItem(at: url)
                }
            }
            updateRestoreStatus(message: "Local store reset. Relaunch to restore.")
            updateSyncStatus(message: "Local store reset")
            return "Local store reset"
        } catch {
            updateRestoreStatus(message: "Reset failed: \(error.localizedDescription)")
            return "Reset failed"
        }
    }

    func pushDefaultsToICloud() {
        let kvs = NSUbiquitousKeyValueStore.default
        let domain = appDefaultsDomain()
        for (key, value) in domain where isSupported(value) {
            guard isAllowedICloudKey(key) else {
                Instrumentation.log(
                    "Skipped iCloud defaults key",
                    area: .processing,
                    level: .warning,
                    details: "key=\(key)"
                )
                continue
            }
            kvs.set(value, forKey: key)
        }
        kvs.synchronize()
    }

    func pullDefaultsFromICloud() {
        let kvs = NSUbiquitousKeyValueStore.default
        kvs.synchronize()
        var domain = appDefaultsDomain()
        for (key, value) in kvs.dictionaryRepresentation where isSupported(value) {
            domain[key] = value
        }
        if let bundleID = Bundle.main.bundleIdentifier {
            UserDefaults.standard.setPersistentDomain(domain, forName: bundleID)
        }
        UserDefaults.standard.synchronize()
    }

    private func startObserversIfNeeded() {
        if kvsObserver == nil {
            kvsObserver = NotificationCenter.default.addObserver(
                forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: NSUbiquitousKeyValueStore.default,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isSettingsSyncEnabled else { return }
                    self.pullDefaultsFromICloud()
                }
            }
        }

        if cloudKitEventObserver == nil {
            cloudKitEventObserver = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: nil,
                queue: .main
            ) { notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event else { return }
                let typeLabel: String = {
                    switch event.type {
                    case .setup: return "setup"
                    case .import: return "import"
                    case .export: return "export"
                    @unknown default: return "other"
                    }
                }()
                let basePhase: CloudSyncPhase = {
                    switch event.type {
                    case .export: return .uploading
                    case .import: return .downloading
                    case .setup: return .preparing
                    @unknown default: return .preparing
                    }
                }()
                var details: [String] = []
                details.append("type=\(typeLabel)")
                details.append("store=\(event.storeIdentifier)")
                details.append("start=\(event.startDate)")
                if let endDate = event.endDate {
                    details.append("end=\(endDate)")
                } else {
                    details.append("end=nil")
                }
                if let error = event.error {
                    details.append("error=\(error.localizedDescription)")
                }
                let message = "CloudKit event: \(typeLabel)"
                let detail = details.joined(separator: " ")
                let logLevel: InstrumentationLevel = event.error == nil ? .info : .warning
                let phase: CloudSyncPhase
                let progress: Double
                if let _ = event.error {
                    phase = .failed
                    progress = 0
                } else if event.endDate != nil {
                    phase = .completed
                    progress = 1.0
                } else {
                    phase = basePhase
                    progress = 0.2
                }
                Task { @MainActor in
                    Instrumentation.log(
                        "CloudKit event",
                        area: .processing,
                        level: logLevel,
                        details: detail
                    )
                    NotificationCenter.default.post(
                        name: .cloudKitHistoryEvent,
                        object: nil,
                        userInfo: [
                            "message": message,
                            "detail": detail,
                            "phase": phase.rawValue,
                            "progress": progress
                        ]
                    )
                }
            }
        }

        if remoteChangeObserver == nil {
            remoteChangeObserver = NotificationCenter.default.addObserver(
                forName: .NSPersistentStoreRemoteChange,
                object: nil,
                queue: .main
            ) { notification in
                var details: [String] = []
                if let storeURL = notification.userInfo?[NSPersistentStoreURLKey] as? URL {
                    details.append("storeURL=\(storeURL.path)")
                }
                let detail = details.joined(separator: " ")
                Task { @MainActor in
                    Instrumentation.log(
                        "Persistent store remote change",
                        area: .processing,
                        level: .info,
                        details: detail
                    )
                    NotificationCenter.default.post(
                        name: .cloudKitHistoryEvent,
                        object: nil,
                        userInfo: [
                            "message": "CloudKit remote change",
                            "detail": detail,
                            "phase": CloudSyncPhase.completed.rawValue
                        ]
                    )
                }
            }
        }

        if terminateObserver == nil {
            let skipBackupOnCloseOnceKey = ICloudDefaultsKeys.skipBackupOnCloseOnce
            let backupOnCloseKey = ICloudDefaultsKeys.backupOnClose
            terminateObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.willTerminateNotification,
                object: nil,
                queue: nil
            ) { [weak self] _ in
                let defaults = UserDefaults.standard
                if defaults.bool(forKey: skipBackupOnCloseOnceKey) {
                    defaults.set(false, forKey: skipBackupOnCloseOnceKey)
                    print("[iCloud] willTerminate: backup skipped (skipBackupOnCloseOnce)")
                    return
                }
                let shouldBackupOnClose = defaults.bool(forKey: backupOnCloseKey)
                guard let self, shouldBackupOnClose else {
                    print("[iCloud] willTerminate: backup skipped (disabled)")
                    return
                }
                print("[iCloud] willTerminate: backup requested (onClose)")
                Task {
                    _ = await self.performBackupNow(reason: "onClose")
                }
            }
        }
    }

    private func estimateBackupSize(container: ModelContainer) throws -> Int64 {
        let context = ModelContext(container)
        let datasets = try context.fetch(FetchDescriptor<StoredDataset>())
        var total: Int64 = 0
        for dataset in datasets {
            total += Int64(dataset.fileData?.count ?? 0)
            total += Int64(dataset.metadataJSON?.count ?? 0)
            total += Int64(dataset.headerInfoData?.count ?? 0)
            total += Int64(dataset.skippedDataJSON?.count ?? 0)
            total += Int64(dataset.warningsJSON?.count ?? 0)
            for spectrum in dataset.spectraItems {
                total += Int64(spectrum.xData.count)
                total += Int64(spectrum.yData.count)
            }
        }
        return total
    }

    private var isSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: ICloudDefaultsKeys.syncEnabled)
    }

    private var isSettingsSyncEnabled: Bool {
        UserDefaults.standard.bool(forKey: ICloudDefaultsKeys.settingsSyncEnabled)
    }

    private var isAutoBackupEnabled: Bool {
        UserDefaults.standard.bool(forKey: ICloudDefaultsKeys.autoBackupEnabled)
    }

    private var shouldBackupOnClose: Bool {
        UserDefaults.standard.bool(forKey: ICloudDefaultsKeys.backupOnClose)
    }

    private var backupIntervalHours: Double {
        let value = UserDefaults.standard.double(forKey: ICloudDefaultsKeys.backupIntervalHours)
        return value == 0 ? 6.0 : value
    }

    private func modelStoreURL() -> URL? {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "SPF Spectral Analyzer"
        let appDirectory = (baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(bundleID, isDirectory: true)
        return appDirectory.appendingPathComponent("SPFSpectralAnalyzer.store", isDirectory: false)
    }

    private func appDefaultsDomain() -> [String: Any] {
        guard let bundleID = Bundle.main.bundleIdentifier,
              let domain = UserDefaults.standard.persistentDomain(forName: bundleID) else {
            return [:]
        }
        return domain
    }

    private func isSupported(_ value: Any) -> Bool {
        switch value {
        case is String, is NSNumber, is Data, is Date, is Bool:
            return true
        default:
            return false
        }
    }

    private func isAllowedICloudKey(_ key: String) -> Bool {
        let maxKeyLength = 128
        if key.utf16.count > maxKeyLength {
            return false
        }
        if key.hasPrefix("NSWindow Frame") || key.hasPrefix("NSNavLastRootDirectory") {
            return false
        }

        let allowedExactKeys: Set<String> = [
            "spfDisplayMode",
            "toolbarShowLabels"
        ]
        if allowedExactKeys.contains(key) {
            return true
        }

        let allowedPrefixes: [String] = [
            "ai",
            "icloud",
            "instrumentation",
            "swiftDataStore"
        ]
        for prefix in allowedPrefixes where key.hasPrefix(prefix) {
            return true
        }
        return false
    }

    private func updateBackupStatus(message: String) {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: ICloudDefaultsKeys.lastBackupTimestamp)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.lastBackupStatus)
    }

    private func updateRestoreStatus(message: String) {
        let now = Date().timeIntervalSince1970
        UserDefaults.standard.set(now, forKey: ICloudDefaultsKeys.lastRestoreTimestamp)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.lastRestoreStatus)
    }

    private func setLastSyncTrigger(_ reason: String) {
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(normalized, forKey: ICloudDefaultsKeys.lastSyncTrigger)
    }

    func updateSyncStatus(message: String) {
        let now = Date().timeIntervalSince1970
        let isInProgress = message.lowercased().contains("in progress")
        UserDefaults.standard.set(isInProgress, forKey: ICloudDefaultsKeys.syncInProgress)
        UserDefaults.standard.set(now, forKey: ICloudDefaultsKeys.lastSyncTimestamp)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.lastSyncStatus)
    }
}
