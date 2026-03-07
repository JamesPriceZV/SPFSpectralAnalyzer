//
//  Shimadzu_Data_AnalyserApp.swift
//  Shimadzu Data Analyser
//
//  Created by Zinco Verde, Inc. on 3/7/26.
//

import SwiftUI
import AppKit
import SwiftData
import CoreData

@main
struct Shimadzu_Data_AnalyserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var dataStoreController = DataStoreController()

    init() {
        AppIconRenderer.applyRuntimeIcon()
        ConsoleCapture.start()
    }

    private static let cloudKitContainerIdentifier = "iCloud.com.zincoverde.SPFSpectralAnalyzer"
    private static let schemaInitLock = NSLock()
    private static var schemaInitInFlight = false
    private static var schemaInitSucceeded = false
    private static var schemaInitContainer: NSPersistentCloudKitContainer?

    private static func makeModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        useCloudSync: Bool
    ) throws -> ModelContainer {
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let mode = useCloudSync ? "cloudKit" : "local"
            setStoreMode(mode)
            return container
        } catch {
            if let recovered = try? recoverModelContainer(
                schema: schema,
                configuration: configuration,
                useCloudSync: useCloudSync,
                error: error
            ) {
                return recovered
            }
            throw error
        }
    }

    private static func recoverModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        useCloudSync: Bool,
        error: Error
    ) throws -> ModelContainer {
        #if DEBUG
        print("Model container failed to load: \(error)")
        #endif

        deleteStoreFiles(at: configuration.url)

        if let container = try? ModelContainer(for: schema, configurations: [configuration]) {
            let mode = useCloudSync ? "cloudKit" : "local"
            setStoreMode(mode)
            return container
        }

        if useCloudSync {
            let localConfig = ModelConfiguration(cloudKitDatabase: .none)
            if let container = try? ModelContainer(for: schema, configurations: [localConfig]) {
                setStoreMode("local")
                UserDefaults.standard.set(
                    "CloudKit unavailable. Running with local storage.",
                    forKey: ICloudDefaultsKeys.lastSyncStatus
                )
                UserDefaults.standard.set(true, forKey: ICloudDefaultsKeys.cloudKitUnavailable)
                UserDefaults.standard.set(
                    "CloudKit is unavailable. The app is using local storage until CloudKit becomes available.",
                    forKey: ICloudDefaultsKeys.cloudKitUnavailableMessage
                )
                setStoreResetNotice(
                    "Local data was reset because the database failed to load. CloudKit is unavailable, so the app is running with local storage."
                )
                return container
            }
        }

        throw error
    }

    private static func deleteStoreFiles(at url: URL) {
        let basePath = url.path
        let urls = [
            url,
            URL(fileURLWithPath: basePath + "-shm"),
            URL(fileURLWithPath: basePath + "-wal")
        ]
        var deletedAny = false
        for url in urls where FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.removeItem(at: url)
            deletedAny = true
        }
        if deletedAny {
            setStoreResetNotice(
                "Local data was reset because the database failed to load. If iCloud sync is enabled, data will re-sync once CloudKit is available."
            )
        }
    }

    private static func setStoreResetNotice(_ message: String) {
        let now = Date()
        UserDefaults.standard.set(true, forKey: ICloudDefaultsKeys.storeResetOccurred)
        UserDefaults.standard.set(message, forKey: ICloudDefaultsKeys.storeResetMessage)
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: ICloudDefaultsKeys.storeResetTimestamp)
        appendStoreResetHistory(message, timestamp: now)
        Instrumentation.log(
            "SwiftData store reset",
            area: .uiInteraction,
            level: .warning,
            details: "message=\(message)"
        )
    }

    private static func appendStoreResetHistory(_ message: String, timestamp: Date) {
        let entry = StoreResetHistoryEntry(timestamp: timestamp, message: message)
        let defaults = UserDefaults.standard
        let existingData = defaults.data(forKey: ICloudDefaultsKeys.storeResetHistoryData) ?? Data()
        var entries = StoreResetHistoryEntry.decode(from: existingData)
        entries.insert(entry, at: 0)
        if entries.count > 20 {
            entries = Array(entries.prefix(20))
        }
        if let data = StoreResetHistoryEntry.encode(entries) {
            defaults.set(data, forKey: ICloudDefaultsKeys.storeResetHistoryData)
        }
    }

    private static func setStoreMode(_ mode: String) {
        UserDefaults.standard.set(mode, forKey: ICloudDefaultsKeys.storeMode)
        if mode == "cloudKit" {
            clearCloudKitUnavailableFlag()
        }
    }

    private static func clearCloudKitUnavailableFlag() {
        UserDefaults.standard.set(false, forKey: ICloudDefaultsKeys.cloudKitUnavailable)
        UserDefaults.standard.set("", forKey: ICloudDefaultsKeys.cloudKitUnavailableMessage)
    }

    var body: some Scene {
        WindowGroup {
            RootContentView()
                .environmentObject(dataStoreController)
        }
        .commands {
            DiagnosticsCommands()
            HelpCommands()
        }

        Window("Diagnostics Console", id: "diagnostics-console") {
            DiagnosticsConsoleView()
                .environmentObject(dataStoreController)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)

        Window("Help", id: "help") {
            HelpView()
        }
        .windowResizability(.contentSize)

        Settings {
            RootSettingsView()
                .environmentObject(dataStoreController)
        }
    }
    #if DEBUG
    static func initializeCloudKitSchemaIfNeeded(schema: Schema, configuration: ModelConfiguration) {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        schemaInitLock.lock()
        if schemaInitSucceeded {
            schemaInitLock.unlock()
            Instrumentation.log(
                "CloudKit schema init skipped",
                area: .processing,
                level: .info,
                details: "reason=already-completed \(Instrumentation.threadContext())"
            )
            return
        }
        if schemaInitInFlight {
            schemaInitLock.unlock()
            Instrumentation.log(
                "CloudKit schema init skipped",
                area: .processing,
                level: .info,
                details: "reason=in-flight \(Instrumentation.threadContext())"
            )
            return
        }
        schemaInitInFlight = true
        schemaInitLock.unlock()

        let containerIdentifier = configuration.cloudKitContainerIdentifier ?? cloudKitContainerIdentifier
        let storeURL = makeSchemaInitStoreURL()
        pruneSchemaInitStores(keeping: storeURL)
        let startTime = CFAbsoluteTimeGetCurrent()

        Instrumentation.log(
            "CloudKit schema init start",
            area: .processing,
            level: .info,
            details: "store=\(storeURL.path) container=\(containerIdentifier) \(Instrumentation.threadContext())"
        )

        do {
            try autoreleasepool {
                let description = NSPersistentStoreDescription(url: storeURL)
                let options = NSPersistentCloudKitContainerOptions(containerIdentifier: containerIdentifier)
                description.cloudKitContainerOptions = options
                description.shouldAddStoreAsynchronously = false

                guard let mom = NSManagedObjectModel.makeManagedObjectModel(for: schema) else {
                    Instrumentation.log(
                        "CloudKit schema init skipped",
                        area: .processing,
                        level: .warning,
                        details: "reason=missing-model \(Instrumentation.threadContext())"
                    )
                    return
                }

                let container = NSPersistentCloudKitContainer(name: "SPF Spectral Analyzer", managedObjectModel: mom)
                container.persistentStoreDescriptions = [description]
                container.loadPersistentStores { _, error in
                    if let error {
                        Instrumentation.log(
                            "CloudKit schema init load failed",
                            area: .processing,
                            level: .error,
                            details: "error=\(error.localizedDescription) \(Instrumentation.threadContext())"
                        )
                    }
                }
                try container.initializeCloudKitSchema()
                // Keep the container alive to avoid CoreData CloudKit internals racing store teardown.
                schemaInitLock.lock()
                schemaInitContainer = container
                schemaInitSucceeded = true
                schemaInitLock.unlock()
            }

            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Instrumentation.log(
                "CloudKit schema init complete",
                area: .processing,
                level: .info,
                details: "store=\(storeURL.path) \(Instrumentation.threadContext())",
                duration: duration
            )
        } catch {
            schemaInitLock.lock()
            schemaInitSucceeded = false
            schemaInitLock.unlock()
            let duration = CFAbsoluteTimeGetCurrent() - startTime
            Instrumentation.log(
                "CloudKit schema initialization failed",
                area: .processing,
                level: .error,
                details: "error=\(error.localizedDescription) \(Instrumentation.threadContext())",
                duration: duration
            )
        }

        schemaInitLock.lock()
        schemaInitInFlight = false
        schemaInitLock.unlock()
    }

    private static func makeSchemaInitStoreURL() -> URL {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let filename = "CloudKitSchemaInit-\(UUID().uuidString).sqlite"
        return tempDirectory.appendingPathComponent(filename)
    }

    private static func pruneSchemaInitStores(keeping storeURL: URL) {
        let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: tempDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        let keepBase = storeURL.lastPathComponent.replacingOccurrences(of: ".sqlite", with: "")
        for fileURL in contents {
            let filename = fileURL.lastPathComponent
            guard filename.hasPrefix("CloudKitSchemaInit-") else { continue }
            let baseName = filename.replacingOccurrences(of: ".sqlite", with: "")
                .replacingOccurrences(of: ".sqlite-shm", with: "")
                .replacingOccurrences(of: ".sqlite-wal", with: "")
            if baseName == keepBase {
                continue
            }
            try? FileManager.default.removeItem(at: fileURL)
        }
        Instrumentation.log(
            "CloudKit schema init temp cleanup",
            area: .processing,
            level: .info,
            details: "kept=\(storeURL.lastPathComponent) \(Instrumentation.threadContext())"
        )
    }
    #endif
}

private struct RootContentView: View {
    @EnvironmentObject private var dataStoreController: DataStoreController

    var body: some View {
        ContentView()
            .modelContainer(dataStoreController.container)
            .id(dataStoreController.containerID)
    }
}

private struct RootSettingsView: View {
    @EnvironmentObject private var dataStoreController: DataStoreController

    var body: some View {
        SettingsView()
            .modelContainer(dataStoreController.container)
            .id(dataStoreController.containerID)
    }
}

private struct DiagnosticsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .help) {
            Button("Diagnostics Console") {
                openWindow(id: "diagnostics-console")
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}

private struct HelpCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .help) {
            Button("Help") {
                openWindow(id: "help")
            }
            .keyboardShortcut("?", modifiers: .command)
        }
    }
}
