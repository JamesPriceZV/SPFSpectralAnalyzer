import SwiftUI
import UniformTypeIdentifiers

// MARK: - Filter Tab Presets

enum DiagnosticsFilterTab: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case errorsOnly = "Errors"
    case ai = "AI"
    case importParsing = "Import"
    case processing = "Processing"
    case export = "Export"
    case mlTraining = "ML Training"
    case console = "Console"

    nonisolated var id: String { rawValue }

    /// The area filter applied when this tab is active. Nil means show all areas.
    nonisolated var areaFilter: InstrumentationArea? {
        switch self {
        case .all, .errorsOnly: return nil
        case .ai: return .aiAnalysis
        case .importParsing: return .importParsing
        case .processing: return .processing
        case .export: return .export
        case .mlTraining: return .mlTraining
        case .console: return .console
        }
    }

    /// The severity filter applied when this tab is active. Nil means use user selection.
    nonisolated var severityFilter: Set<InstrumentationLevel>? {
        switch self {
        case .errorsOnly: return [.error]
        default: return nil
        }
    }
}

// MARK: - Diagnostics Console View

struct DiagnosticsConsoleView: View {
    @EnvironmentObject private var dataStoreController: DataStoreController
    @Environment(\.dismiss) private var dismiss

    @AppStorage("cloudKitSchemaInitOnLaunch") private var cloudKitSchemaInitOnLaunch = false

    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled = false
    @AppStorage("cloudKitUnavailable") private var cloudKitUnavailable = false
    @AppStorage("cloudKitUnavailableMessage") private var cloudKitUnavailableMessage = ""
    @AppStorage("icloudContainerIdentifier") private var icloudContainerIdentifier = ""
    @AppStorage("icloudAccountStatus") private var icloudAccountStatus = ""
    @AppStorage("icloudAccountStatusTimestamp") private var icloudAccountStatusTimestamp = 0.0
    @AppStorage("icloudDatabaseScope") private var icloudDatabaseScope = ""
    @AppStorage("icloudLastSyncReason") private var icloudLastSyncReason = ""
    @AppStorage("icloudLastPollTimestamp") private var icloudLastPollTimestamp = 0.0
    @AppStorage("icloudLastPushTimestamp") private var icloudLastPushTimestamp = 0.0
    @AppStorage("icloudLastSyncErrorDomain") private var icloudLastSyncErrorDomain = ""
    @AppStorage("icloudLastSyncErrorCode") private var icloudLastSyncErrorCode = 0
    @AppStorage("icloudLastSyncErrorDescription") private var icloudLastSyncErrorDescription = ""
    @AppStorage("icloudLastSyncStartTimestamp") private var icloudLastSyncStartTimestamp = 0.0
    @AppStorage("icloudLastSyncEndTimestamp") private var icloudLastSyncEndTimestamp = 0.0
    @AppStorage("icloudLastSyncDuration") private var icloudLastSyncDuration = 0.0

    @State private var logEntries: [UnifiedLogEntry] = []
    @State private var filteredEntries: [UnifiedLogEntry] = []
    @State private var filterTask: Task<Void, Never>?
    @AppStorage("diagnosticsStreamingPaused") private var isStreamingPaused = false
    @State private var searchText = ""
    @State private var selectedSeverities: Set<InstrumentationLevel> = [.error, .warning, .info]
    @State private var selectedTab: DiagnosticsFilterTab = .all
    @State private var showCopyToast = false
    @State private var isExporting = false

    private let maxVisibleEntries = 4000

    var body: some View {
        VStack(spacing: 16) {
            header

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    diagnosticsSummary
                    cloudKitSummary
                    storeSummary
                }
                .frame(width: 320)

                VStack(spacing: 12) {
                    tabBar
                    filterBar
                    logList
                    actionBar
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(minWidth: 980, minHeight: 640)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diagnosticsConsoleRoot")
        .onAppear {
            Task { await reloadStoredLogs() }
        }
        .onChange(of: logEntries) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: searchText) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: selectedSeverities) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: selectedTab) { _, _ in
            scheduleFilterUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .unifiedLog)) { notification in
            guard !isStreamingPaused else { return }
            guard let entry = notification.object as? UnifiedLogEntry else { return }
            logEntries.insert(entry, at: 0)
            if logEntries.count > maxVisibleEntries {
                logEntries.removeLast(logEntries.count - maxVisibleEntries)
            }
        }
        .overlay(alignment: .topTrailing) {
            if showCopyToast {
                Text("Copied")
                    .font(.caption)
                    .padding(8)
                    .background(.regularMaterial)
                    .cornerRadius(8)
                    .padding(12)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Text("Diagnostics Console")
                .font(.title2)
                .foregroundColor(diagnosticHeaderColor)
                .accessibilityIdentifier("diagnosticsConsoleTitle")
            Spacer()
            Button("Close") {
                dismiss()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Tab Bar

    private var tabBar: some View {
        HStack(spacing: 4) {
            ForEach(DiagnosticsFilterTab.allCases) { tab in
                Button(tab.rawValue) {
                    selectedTab = tab
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(selectedTab == tab ? diagnosticHeaderColor.opacity(0.2) : Color.clear)
                .foregroundColor(selectedTab == tab ? diagnosticHeaderColor : .secondary)
                .cornerRadius(6)
                .font(.caption)
            }
            Spacer()

            Text("\(filteredEntries.count) entries")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Summaries

    private var diagnosticsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.headline)
                .foregroundColor(diagnosticHeaderColor)
            Text("Storage: \(dataStoreController.storeMode.capitalized)")
                .font(.caption)
            Text("CloudKit Enabled: \(icloudSyncEnabled ? "Yes" : "No")")
                .font(.caption)
            Text("CloudKit Available: \(cloudKitUnavailable ? "No" : "Yes")")
                .font(.caption)
            if !cloudKitUnavailableMessage.isEmpty {
                Text(cloudKitUnavailableMessage)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(panelBackgroundColor)
        .cornerRadius(12)
    }

    private var cloudKitSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("iCloud / CloudKit")
                .font(.headline)
                .foregroundColor(diagnosticHeaderColor)
            summaryRow(label: "Container", value: icloudContainerIdentifier)
            summaryRow(label: "Database", value: icloudDatabaseScope)
            summaryRow(label: "Account", value: icloudAccountStatus)
            summaryRow(label: "Account time", value: formattedTimestamp(icloudAccountStatusTimestamp))
            summaryRow(label: "Last reason", value: icloudLastSyncReason)
            summaryRow(label: "Last poll", value: formattedTimestamp(icloudLastPollTimestamp))
            summaryRow(label: "Last push", value: formattedTimestamp(icloudLastPushTimestamp))
            summaryRow(label: "Sync start", value: formattedTimestamp(icloudLastSyncStartTimestamp))
            summaryRow(label: "Sync end", value: formattedTimestamp(icloudLastSyncEndTimestamp))
            summaryRow(label: "Sync duration", value: icloudLastSyncDuration > 0 ? String(format: "%.2fs", icloudLastSyncDuration) : "")
            if !icloudLastSyncErrorDomain.isEmpty || !icloudLastSyncErrorDescription.isEmpty {
                Text("Last error: \(icloudLastSyncErrorDomain) (\(icloudLastSyncErrorCode))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(icloudLastSyncErrorDescription)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(panelBackgroundColor)
        .cornerRadius(12)
    }

    private var storeSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Persistent Store")
                .font(.headline)
                .foregroundColor(diagnosticHeaderColor)
            let storeURL = persistentStoreURL()
            summaryRow(label: "Path", value: storeURL?.path ?? "")
            summaryRow(label: "Size", value: formattedFileSize(at: storeURL))
            summaryRow(label: "Last modified", value: formattedFileDate(at: storeURL))
        }
        .padding(10)
        .background(panelBackgroundColor)
        .cornerRadius(12)
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("diagnosticsSearchField")

            Menu("Severity") {
                ForEach([InstrumentationLevel.error, .warning, .info], id: \.self) { level in
                    Toggle(level.label, isOn: Binding(get: {
                        selectedSeverities.contains(level)
                    }, set: { isOn in
                        if isOn {
                            selectedSeverities.insert(level)
                        } else {
                            selectedSeverities.remove(level)
                        }
                    }))
                }
            }

            Toggle("Pause", isOn: $isStreamingPaused)

            Spacer()

            Button("Refresh") {
                Task { await reloadStoredLogs() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("diagnosticsRefreshButton")
        }
    }

    // MARK: - Log List

    private var logList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(filteredEntries) { entry in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formattedTimestamp(entry.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            HStack(spacing: 8) {
                                Text(entry.level.label)
                                    .font(.caption2)
                                    .foregroundColor(severityColor(entry.level))
                                Text(entry.area.rawValue)
                                    .font(.caption2)
                                    .foregroundColor(diagnosticMetaColor)
                                if let stream = entry.consoleStream {
                                    Text(stream)
                                        .font(.caption2)
                                        .foregroundColor(diagnosticMetaColor)
                                }
                            }
                            Text(entry.message)
                                .font(.caption)
                                .textSelection(.enabled)
                        }
                        .padding(8)
                        .background(panelBackgroundColor)
                        .cornerRadius(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .background(panelBackgroundColor)
        .cornerRadius(12)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button("Copy") {
                copyLogsToPasteboard()
            }
            .disabled(filteredEntries.isEmpty)
            .accessibilityIdentifier("diagnosticsCopyButton")

            Button("Export Excel") {
                Task { await exportLogsAsXlsx() }
            }
            .disabled(filteredEntries.isEmpty || isExporting)
            .accessibilityIdentifier("diagnosticsExportExcelButton")

            Button("Export JSON") {
                Task { await exportLogsAsJSON() }
            }
            .disabled(filteredEntries.isEmpty || isExporting)
            .accessibilityIdentifier("diagnosticsExportJSONButton")

            Button("Export CSV") {
                Task { await exportLogsAsCSV() }
            }
            .disabled(filteredEntries.isEmpty || isExporting)
            .accessibilityIdentifier("diagnosticsExportCSVButton")

            Button("Clear All") {
                Task {
                    await UnifiedLogStore.shared.clear()
                    logEntries.removeAll()
                }
            }
            .disabled(logEntries.isEmpty)

            #if DEBUG
            Toggle("Schema init on launch", isOn: $cloudKitSchemaInitOnLaunch)

            Button("Run Schema Init") {
                dataStoreController.runCloudKitSchemaInit()
            }
            #endif

            Spacer()
        }
        .buttonStyle(.bordered)
    }

    // MARK: - Data Loading & Filtering

    private func reloadStoredLogs() async {
        let entries = await UnifiedLogStore.shared.loadAll()
        await MainActor.run {
            logEntries = entries.reversed() // newest first
            scheduleFilterUpdate()
        }
    }

    private func scheduleFilterUpdate() {
        filterTask?.cancel()
        let entries = logEntries
        let search = searchText
        let severities = selectedSeverities
        let tab = selectedTab
        filterTask = Task.detached {
            let filtered = Self.applyFilters(
                entries: entries,
                searchText: search,
                severities: severities,
                tab: tab
            )
            await MainActor.run {
                filteredEntries = filtered
            }
        }
    }

    fileprivate nonisolated static func applyFilters(
        entries: [UnifiedLogEntry],
        searchText: String,
        severities: Set<InstrumentationLevel>,
        tab: DiagnosticsFilterTab
    ) -> [UnifiedLogEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tabSeverities = tab.severityFilter
        let tabArea = tab.areaFilter

        return entries.filter { entry in
            // Severity filter (tab overrides if present)
            let activeSeverities = tabSeverities ?? severities
            guard activeSeverities.contains(entry.level) else { return false }

            // Area filter from tab
            if let area = tabArea, entry.area != area { return false }

            // Search text
            if trimmed.isEmpty { return true }
            return entry.message.lowercased().contains(trimmed)
                || entry.area.rawValue.lowercased().contains(trimmed)
        }
    }

    // MARK: - Actions

    private func copyLogsToPasteboard() {
        let text = filteredEntries.map { entry in
            "\(formattedTimestamp(entry.timestamp)) [\(entry.level.label)] [\(entry.area.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
        PlatformPasteboard.copyString(text)
        showCopyToast = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            showCopyToast = false
        }
    }

    private func exportLogsAsXlsx() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let xlsx = UTType(filenameExtension: "xlsx") ?? .data
        guard let url = await savePanel(defaultName: "Diagnostics.xlsx", allowedTypes: [xlsx]) else { return }
        let header = ["Timestamp", "Area", "Severity", "Console Stream", "Message"]
        let rows = filteredEntries.map { entry in
            [
                formattedTimestamp(entry.timestamp),
                entry.area.rawValue,
                entry.level.label,
                entry.consoleStream ?? "",
                entry.message
            ]
        }
        do {
            try OOXMLWriter.writeXlsx(header: header, rows: rows, to: url)
        } catch {
            Instrumentation.log("Diagnostics export failed", area: .uiInteraction, level: .error, details: "error=\(error.localizedDescription)")
        }
    }

    private func exportLogsAsCSV() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let csv = UTType(filenameExtension: "csv") ?? .commaSeparatedText
        guard let url = await savePanel(defaultName: "Diagnostics.csv", allowedTypes: [csv]) else { return }

        var lines: [String] = ["Timestamp,Area,Severity,Console Stream,Message"]
        for entry in filteredEntries {
            let ts = formattedTimestamp(entry.timestamp)
            let area = entry.area.rawValue
            let severity = entry.level.label
            let stream = entry.consoleStream ?? ""
            // Escape double quotes and wrap fields that may contain commas/newlines
            let message = "\"" + entry.message.replacingOccurrences(of: "\"", with: "\"\"") + "\""
            lines.append("\(ts),\(area),\(severity),\(stream),\(message)")
        }

        do {
            let data = lines.joined(separator: "\n").data(using: .utf8) ?? Data()
            try data.write(to: url)
        } catch {
            Instrumentation.log("CSV export failed", area: .uiInteraction, level: .error, details: "error=\(error.localizedDescription)")
        }
    }

    private func exportLogsAsJSON() async {
        guard !isExporting else { return }
        isExporting = true
        defer { isExporting = false }

        let json = UTType.json
        guard let url = await savePanel(defaultName: "Diagnostics.json", allowedTypes: [json]) else { return }
        let payload = filteredEntries.map { entry in
            DiagnosticsLogExport(
                timestamp: entry.timestamp,
                area: entry.area.rawValue,
                severity: entry.level.rawValue,
                consoleStream: entry.consoleStream ?? "",
                message: entry.message
            )
        }
        do {
            let data = try JSONEncoder().encode(payload)
            try data.write(to: url)
        } catch {
            Instrumentation.log("Diagnostics export failed", area: .uiInteraction, level: .error, details: "error=\(error.localizedDescription)")
        }
    }

    @MainActor
    private func savePanel(defaultName: String, allowedTypes: [UTType]) async -> URL? {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = timestampedFileName(defaultName)
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let parentWindow = NSApplication.shared.keyWindow ?? NSApp.mainWindow
        guard let window = parentWindow else {
            let response = panel.runModal()
            return response == .OK ? panel.url : nil
        }

        return await withCheckedContinuation { continuation in
            panel.beginSheetModal(for: window) { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
        #else
        // iOS: return a temp URL; callers write data, then share via PlatformFileSaver in Phase 2
        let tempDir = FileManager.default.temporaryDirectory
        return tempDir.appendingPathComponent(timestampedFileName(defaultName))
        #endif
    }

    // MARK: - Formatting Helpers

    private func formattedTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
    }

    private func timestampedFileName(_ baseName: String) -> String {
        let trimmed = baseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return baseName }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())

        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else {
            return "\(trimmed)_\(stamp)"
        }
        let ext = parts.last ?? ""
        let name = parts.dropLast().joined(separator: ".")
        return "\(name)_\(stamp).\(ext)"
    }

    private func formattedTimestamp(_ timestamp: Double) -> String {
        guard timestamp > 0 else { return "" }
        return formattedTimestamp(Date(timeIntervalSince1970: timestamp))
    }

    private func formattedFileSize(at url: URL?) -> String {
        guard let url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return ""
        }
        return ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file)
    }

    private func formattedFileDate(at url: URL?) -> String {
        guard let url,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let date = attributes[.modificationDate] as? Date else {
            return ""
        }
        return formattedTimestamp(date)
    }

    private func persistentStoreURL() -> URL? {
        let baseDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let bundleID = Bundle.main.bundleIdentifier ?? "PhysicAI"
        let appDirectory = (baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(bundleID, isDirectory: true)
        return appDirectory.appendingPathComponent("PhysicAI.store", isDirectory: false)
    }

    private func summaryRow(label: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Text(label + ":")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(3)
                .truncationMode(.middle)
        }
    }

    private func severityColor(_ level: InstrumentationLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .yellow
        case .info: return .blue
        }
    }

    private var panelBackgroundColor: Color {
        Color.white.opacity(0.05)
    }

    private var diagnosticHeaderColor: Color {
        Color.purple
    }

    private var diagnosticMetaColor: Color {
        Color.purple.opacity(0.75)
    }
}

// MARK: - Export Model

struct DiagnosticsLogExport: Codable {
    let timestamp: Date
    let area: String
    let severity: String
    let consoleStream: String
    let message: String
}

// MARK: - Legacy Types (kept for backward compatibility)

struct DiagnosticsLogEntry: Identifiable, Hashable, Sendable {
    let id = UUID()
    let timestamp: Date
    let source: String
    let area: String
    let level: DiagnosticsSeverity
    let message: String
    let consoleStream: ConsoleStream?
}

enum ConsoleStream: String, CaseIterable, Hashable, Sendable {
    case stdout
    case stderr

    var label: String {
        switch self {
        case .stdout:
            return "stdout"
        case .stderr:
            return "stderr"
        }
    }
}

enum DiagnosticsSeverity: String, CaseIterable, Hashable, Sendable {
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
            return "Info"
        }
    }

    var color: Color {
        switch self {
        case .error:
            return .red
        case .warning:
            return .yellow
        case .info:
            return .blue
        }
    }

    static func fromLabel(_ label: String) -> DiagnosticsSeverity {
        switch label.lowercased() {
        case "error":
            return .error
        case "warning":
            return .warning
        default:
            return .info
        }
    }
}

extension Notification.Name {
    static let aiLog = Notification.Name("AILog")
}
