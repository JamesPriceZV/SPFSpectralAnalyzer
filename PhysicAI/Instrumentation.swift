import Foundation
import os
import Dispatch

enum InstrumentationArea: String, CaseIterable, Identifiable, Codable {
    case importParsing = "Import/Parsing"
    case processing = "Processing"
    case chartRendering = "Chart Rendering"
    case aiAnalysis = "AI Analysis"
    case export = "Export"
    case uiInteraction = "UI Interaction"
    case console = "Console"
    case mlTraining = "ML Training"

    var id: String { rawValue }

    var logCategory: String {
        switch self {
        case .importParsing:
            return "import"
        case .processing:
            return "processing"
        case .chartRendering:
            return "chart"
        case .aiAnalysis:
            return "ai"
        case .export:
            return "export"
        case .uiInteraction:
            return "ui"
        case .console:
            return "console"
        case .mlTraining:
            return "ml"
        }
    }
}

enum InstrumentationLevel: String, Codable {
    case error
    case warning
    case info

    var label: String {
        switch self {
        case .error:
            return "Error"
        case .warning:
            return "Warning"
        case .info:
            return "Verbose"
        }
    }
}

enum InstrumentationOutput: String {
    case inApp
    case console
    case file
    case osLog
}

// MARK: - Unified Log Entry

/// A single structured log entry used by all logging subsystems.
struct UnifiedLogEntry: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let timestamp: Date
    let area: InstrumentationArea
    let level: InstrumentationLevel
    let message: String
    /// Optional console stream tag (stdout/stderr) for console-captured entries.
    let consoleStream: String?

    nonisolated init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        area: InstrumentationArea,
        level: InstrumentationLevel,
        message: String,
        consoleStream: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.area = area
        self.level = level
        self.message = message
        self.consoleStream = consoleStream
    }
}

// MARK: - Unified Log Store

/// Central persistence for all log entries, replacing separate AI/Instrumentation/Console stores.
actor UnifiedLogStore {
    static let shared = UnifiedLogStore()

    private let storageKey = "unifiedLogEntriesData"
    private let maxEntries = 4000
    private var buffer: [UnifiedLogEntry] = []
    private var didLoad = false

    func append(_ entry: UnifiedLogEntry) {
        ensureLoaded()
        buffer.append(entry)
        if buffer.count > maxEntries {
            buffer.removeFirst(buffer.count - maxEntries)
        }
        persist()
        Task { @MainActor in
            NotificationCenter.default.post(name: .unifiedLog, object: entry)
        }
    }

    func loadAll() -> [UnifiedLogEntry] {
        ensureLoaded()
        return buffer
    }

    func clear() {
        buffer.removeAll()
        persist()
    }

    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        // Migrate from legacy stores on first load
        buffer = Self.migrateFromLegacyStores()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(buffer) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    /// One-time migration: load entries from the three legacy UserDefaults keys into a unified store.
    private nonisolated static func migrateFromLegacyStores() -> [UnifiedLogEntry] {
        let defaults = UserDefaults.standard

        // Check if unified store already has data
        if let existingData = defaults.data(forKey: "unifiedLogEntriesData"),
           let existing = try? JSONDecoder().decode([UnifiedLogEntry].self, from: existingData),
           !existing.isEmpty {
            return existing
        }

        var entries: [UnifiedLogEntry] = []

        // Migrate instrumentation logs
        if let data = defaults.data(forKey: "instrumentationLogEntriesData"),
           let payloads = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) {
            for p in payloads {
                let parsed = parseInstrumentationLine(p.message)
                entries.append(UnifiedLogEntry(
                    timestamp: p.timestamp,
                    area: parsed.area,
                    level: parsed.level,
                    message: parsed.message
                ))
            }
        }

        // Migrate AI logs
        if let data = defaults.data(forKey: "aiLogEntriesData"),
           let payloads = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) {
            for p in payloads {
                entries.append(UnifiedLogEntry(
                    timestamp: p.timestamp,
                    area: .aiAnalysis,
                    level: inferredLevel(for: p.message),
                    message: p.message
                ))
            }
        }

        // Migrate console logs
        if let data = defaults.data(forKey: "consoleLogEntriesData"),
           let payloads = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) {
            for p in payloads {
                let parsed = parseConsoleLine(p.message)
                entries.append(UnifiedLogEntry(
                    timestamp: p.timestamp,
                    area: .console,
                    level: inferredLevel(for: parsed.message),
                    message: parsed.message,
                    consoleStream: parsed.stream
                ))
            }
        }

        entries.sort { $0.timestamp < $1.timestamp }
        return entries
    }

    private nonisolated static func parseInstrumentationLine(_ line: String) -> (area: InstrumentationArea, level: InstrumentationLevel, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else {
            return (.uiInteraction, .info, trimmed)
        }
        let parts = trimmed.split(separator: "]", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            let levelToken = parts[0].replacingOccurrences(of: "[", with: "")
            let areaToken = parts[1].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
            let level: InstrumentationLevel
            switch levelToken.lowercased() {
            case "error":
                level = .error
            case "warning":
                level = .warning
            default:
                level = .info
            }
            let area = InstrumentationArea.allCases.first { $0.rawValue == areaToken } ?? .uiInteraction
            let message = trimmed.components(separatedBy: "] ").dropFirst(2).joined(separator: "] ")
            return (area, level, message.isEmpty ? trimmed : message)
        }
        return (.uiInteraction, .info, trimmed)
    }

    private nonisolated static func parseConsoleLine(_ line: String) -> (message: String, stream: String?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[stdout]") {
            return (trimmed.replacingOccurrences(of: "[stdout]", with: "").trimmingCharacters(in: .whitespaces), "stdout")
        }
        if trimmed.hasPrefix("[stderr]") {
            return (trimmed.replacingOccurrences(of: "[stderr]", with: "").trimmingCharacters(in: .whitespaces), "stderr")
        }
        return (trimmed, nil)
    }

    private nonisolated static func inferredLevel(for message: String) -> InstrumentationLevel {
        let lower = message.lowercased()
        if lower.contains("error") || lower.contains("failed") { return .error }
        if lower.contains("warning") { return .warning }
        return .info
    }
}

// MARK: - Settings

struct InstrumentationSettings {
    let enabled: Bool
    let enhancedDiagnostics: Bool
    let areas: Set<InstrumentationArea>
    let outputs: Set<InstrumentationOutput>
    let levels: Set<InstrumentationLevel>

    static func current() -> InstrumentationSettings {
        let defaults = UserDefaults.standard
        let enabled = defaults.bool(forKey: "instrumentationEnabled")
        let enhanced = defaults.bool(forKey: "instrumentationEnhancedDiagnostics")

        var areas: Set<InstrumentationArea> = []
        if defaults.bool(forKey: "instrumentationAreaImportParsing") { areas.insert(.importParsing) }
        if defaults.bool(forKey: "instrumentationAreaProcessing") { areas.insert(.processing) }
        if defaults.bool(forKey: "instrumentationAreaChartRendering") { areas.insert(.chartRendering) }
        if defaults.bool(forKey: "instrumentationAreaAIAnalysis") { areas.insert(.aiAnalysis) }
        if defaults.bool(forKey: "instrumentationAreaExport") { areas.insert(.export) }
        if defaults.bool(forKey: "instrumentationAreaUI") { areas.insert(.uiInteraction) }
        if defaults.bool(forKey: "instrumentationAreaMLTraining") { areas.insert(.mlTraining) }

        var outputs: Set<InstrumentationOutput> = []
        if defaults.bool(forKey: "instrumentationOutputInApp") { outputs.insert(.inApp) }
        if defaults.bool(forKey: "instrumentationOutputConsole") { outputs.insert(.console) }
        if defaults.bool(forKey: "instrumentationOutputFile") { outputs.insert(.file) }
        if defaults.bool(forKey: "instrumentationOutputOSLog") { outputs.insert(.osLog) }

        var levels: Set<InstrumentationLevel> = []
        if defaults.bool(forKey: "instrumentationLevelErrors") { levels.insert(.error) }
        if defaults.bool(forKey: "instrumentationLevelWarnings") { levels.insert(.warning) }
        if defaults.bool(forKey: "instrumentationLevelVerbose") { levels.insert(.info) }

        return InstrumentationSettings(
            enabled: enabled,
            enhancedDiagnostics: enhanced,
            areas: areas,
            outputs: outputs,
            levels: levels
        )
    }
}

// MARK: - Instrumentation

enum Instrumentation {

    static func threadContext() -> String {
        let qos = qosClassName(qos_class_self())
        let isMain = Thread.isMainThread
        let name = Thread.current.name ?? ""
        let nameLabel = name.isEmpty ? "none" : name
        let threadLabel = isMain ? "main" : "bg"
        return "thread=\(threadLabel) qos=\(qos) name=\(nameLabel)"
    }

    private static func qosClassName(_ qos: qos_class_t) -> String {
        switch qos {
        case QOS_CLASS_USER_INTERACTIVE:
            return "user-interactive"
        case QOS_CLASS_USER_INITIATED:
            return "user-initiated"
        case QOS_CLASS_DEFAULT:
            return "default"
        case QOS_CLASS_UTILITY:
            return "utility"
        case QOS_CLASS_BACKGROUND:
            return "background"
        case QOS_CLASS_UNSPECIFIED:
            return "unspecified"
        default:
            return "unknown"
        }
    }

    static func log(
        _ message: String,
        area: InstrumentationArea,
        level: InstrumentationLevel,
        details: String? = nil,
        payloadBytes: Int? = nil,
        duration: TimeInterval? = nil
    ) {
        let settings = InstrumentationSettings.current()
        guard settings.enabled else { return }
        guard settings.areas.contains(area) else { return }
        guard settings.levels.contains(level) else { return }
        guard !settings.outputs.isEmpty else { return }

        var parts: [String] = [message]
        if let details, settings.enhancedDiagnostics || level == .info {
            parts.append(details)
        }
        if let payloadBytes, settings.enhancedDiagnostics || level == .info {
            parts.append("payloadBytes=\(payloadBytes)")
        }
        if let duration, settings.enhancedDiagnostics || level == .info {
            parts.append(String(format: "duration=%.3fs", duration))
        }
        let composedMessage = parts.joined(separator: " ")

        let formattedLine = "[\(level.label)] [\(area.rawValue)] \(composedMessage)"

        let shouldLogToOSLog = settings.outputs.contains(.osLog)
        let shouldLogToConsole = settings.outputs.contains(.console) && !shouldLogToOSLog

        if shouldLogToConsole {
            print(formattedLine)
        }

        if shouldLogToOSLog {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShimadzuDataAnalyser", category: area.logCategory)
            switch level {
            case .error:
                logger.error("\(formattedLine, privacy: .public)")
            case .warning:
                logger.warning("\(formattedLine, privacy: .public)")
            case .info:
                logger.info("\(formattedLine, privacy: .public)")
            }
        }

        // Persist to the unified log store
        let entry = UnifiedLogEntry(area: area, level: level, message: composedMessage)
        Task {
            await UnifiedLogStore.shared.append(entry)
        }

        if settings.outputs.contains(.file) {
            Task {
                await InstrumentationFileLogger.shared.append(formattedLine)
            }
        }
    }

}

// MARK: - File Logger

actor InstrumentationFileLogger {
    static let shared = InstrumentationFileLogger()

    private let basePath = "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/PhysicAI"
    private let sessionLogFilename: String
    private var didCleanupLogs = false

    init() {
        sessionLogFilename = Self.makeSessionLogFilename()
    }

    func append(_ line: String) {
        guard let url = logFileURL() else { return }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            if let data = (line + "\n").data(using: .utf8) {
                try handle.write(contentsOf: data)
            }
        } catch {
            return
        }
    }

    private static func makeSessionLogFilename() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "Instrumentation-\(formatter.string(from: Date())).log"
    }

    private func logFileURL() -> URL? {
        let fileManager = FileManager.default
        let dir = URL(fileURLWithPath: basePath, isDirectory: true)
        if !fileManager.fileExists(atPath: dir.path) {
            try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        if !didCleanupLogs {
            didCleanupLogs = true
            cleanupOldLogs(in: dir, keepLast: 20)
        }
        return dir.appendingPathComponent(sessionLogFilename)
    }

    private func cleanupOldLogs(in directory: URL, keepLast: Int) {
        let fileManager = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey, .isRegularFileKey]
        let urls = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsHiddenFiles]
        )) ?? []

        let logFiles: [(url: URL, date: Date)] = urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("Instrumentation-") && name.hasSuffix(".log") else { return nil }
            guard (try? url.resourceValues(forKeys: resourceKeys).isRegularFile) ?? false else { return nil }
            let values = try? url.resourceValues(forKeys: resourceKeys)
            let date = values?.contentModificationDate ?? values?.creationDate ?? Date.distantPast
            return (url, date)
        }

        guard logFiles.count > keepLast else { return }
        let sorted = logFiles.sorted { $0.date > $1.date }
        let toDelete = sorted.dropFirst(keepLast)
        for entry in toDelete {
            try? fileManager.removeItem(at: entry.url)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let instrumentationLog = Notification.Name("InstrumentationLog")
    static let unifiedLog = Notification.Name("UnifiedLog")
}
