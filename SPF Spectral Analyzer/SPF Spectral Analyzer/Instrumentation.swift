import Foundation
import os
import Dispatch

enum InstrumentationArea: String, CaseIterable, Identifiable {
    case importParsing = "Import/Parsing"
    case processing = "Processing"
    case chartRendering = "Chart Rendering"
    case aiAnalysis = "AI Analysis"
    case export = "Export"
    case uiInteraction = "UI Interaction"

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
        }
    }
}

enum InstrumentationLevel: String {
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

        var parts: [String] = ["[\(level.label)] [\(area.rawValue)] \(message)"]
        if let details, settings.enhancedDiagnostics || level == .info {
            parts.append(details)
        }
        if let payloadBytes, settings.enhancedDiagnostics || level == .info {
            parts.append("payloadBytes=\(payloadBytes)")
        }
        if let duration, settings.enhancedDiagnostics || level == .info {
            parts.append(String(format: "duration=%.3fs", duration))
        }
        let line = parts.joined(separator: " ")

        let shouldLogToOSLog = settings.outputs.contains(.osLog)
        let shouldLogToConsole = settings.outputs.contains(.console) && !shouldLogToOSLog

        if shouldLogToConsole {
            print(line)
        }

        if shouldLogToOSLog {
            let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "ShimadzuDataAnalyser", category: area.logCategory)
            switch level {
            case .error:
                logger.error("\(line, privacy: .public)")
            case .warning:
                logger.warning("\(line, privacy: .public)")
            case .info:
                logger.info("\(line, privacy: .public)")
            }
        }

        if settings.outputs.contains(.inApp) {
            Task { @MainActor in
                NotificationCenter.default.post(name: .instrumentationLog, object: line)
            }
        }

        if settings.outputs.contains(.file) {
            Task {
                await InstrumentationFileLogger.shared.append(line)
            }
        }
    }

}

actor InstrumentationFileLogger {
    static let shared = InstrumentationFileLogger()

    private let basePath = "/Users/zincoverdeinc./Library/CloudStorage/OneDrive-Personal/4_Xcode Projects/Shimadzu File Converter/SPF Spectral Analyzer"
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

extension Notification.Name {
    static let instrumentationLog = Notification.Name("InstrumentationLog")
}
