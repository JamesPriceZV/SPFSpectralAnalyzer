import SwiftUI
import UniformTypeIdentifiers
import Combine

struct DiagnosticsConsoleView: View {
    @EnvironmentObject private var dataStoreController: DataStoreController
    @Environment(\.dismiss) private var dismiss

    @AppStorage("instrumentationOutputInApp") private var instrumentationOutputInApp = false
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

    @State private var logEntries: [DiagnosticsLogEntry] = []
    @State private var filteredEntries: [DiagnosticsLogEntry] = []
    @State private var pendingEntries: [DiagnosticsLogEntry] = []
    @State private var flushTask: Task<Void, Never>?
    @State private var filterTask: Task<Void, Never>?
    @AppStorage("diagnosticsStreamingPaused") private var isStreamingPaused = false
    @State private var streamWindowStart = Date()
    @State private var streamCount = 0
    @State private var searchText = ""
    @State private var selectedSeverities: Set<DiagnosticsSeverity> = [.error, .warning]
    @State private var selectedAreas: Set<String> = []
    @State private var selectedConsoleStreams: Set<ConsoleStream> = Set(ConsoleStream.allCases)
    @State private var showCopyToast = false
    @State private var isExporting = false

    private let maxVisibleEntries = 4000
    private let maxLiveEntriesPerSecond = 60

    private let instrumentationLogStorageKey = "instrumentationLogEntriesData"
    private let aiLogStorageKey = "aiLogEntriesData"
    private let consoleLogStorageKey = "consoleLogEntriesData"

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
        .onChange(of: selectedAreas) { _, _ in
            scheduleFilterUpdate()
        }
        .onChange(of: selectedConsoleStreams) { _, _ in
            scheduleFilterUpdate()
        }
        .onReceive(NotificationCenter.default.publisher(for: .instrumentationLog)) { notification in
            guard let line = notification.object as? String else { return }
            appendInstrumentationLine(line)
        }
        .onReceive(NotificationCenter.default.publisher(for: .aiLog)) { notification in
            guard let line = notification.object as? String else { return }
            appendAILine(line)
        }
        .onReceive(NotificationCenter.default.publisher(for: .consoleLog)) { notification in
            guard let line = notification.object as? String else { return }
            appendConsoleLine(line)
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

    private var diagnosticsSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Status")
                .font(.headline)
                .foregroundColor(diagnosticHeaderColor)
            Text("Storage: \(dataStoreController.storeMode.capitalized)")
                .font(.caption)
            Text("CloudKit enabled: \(icloudSyncEnabled ? "yes" : "no")")
                .font(.caption)
            Text("CloudKit unavailable: \(cloudKitUnavailable ? "yes" : "no")")
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

    private var filterBar: some View {
        HStack(spacing: 10) {
            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("diagnosticsSearchField")

            Menu("Severity") {
                ForEach(DiagnosticsSeverity.allCases, id: \.self) { severity in
                    Toggle(severity.label, isOn: Binding(get: {
                        selectedSeverities.contains(severity)
                    }, set: { isOn in
                        if isOn {
                            selectedSeverities.insert(severity)
                        } else {
                            selectedSeverities.remove(severity)
                        }
                    }))
                }
            }

            Menu("Area") {
                let areas = availableAreas()
                if areas.isEmpty {
                    Text("No areas")
                } else {
                    ForEach(areas, id: \.self) { area in
                        Toggle(area, isOn: Binding(get: {
                            selectedAreas.isEmpty || selectedAreas.contains(area)
                        }, set: { isOn in
                            if isOn {
                                selectedAreas.insert(area)
                            } else {
                                selectedAreas.remove(area)
                            }
                        }))
                    }
                }
            }

            Menu("Console") {
                ForEach(ConsoleStream.allCases, id: \.self) { stream in
                    Toggle(stream.label, isOn: Binding(get: {
                        selectedConsoleStreams.contains(stream)
                    }, set: { isOn in
                        if isOn {
                            selectedConsoleStreams.insert(stream)
                        } else {
                            selectedConsoleStreams.remove(stream)
                        }
                    }))
                }
            }

            Toggle("Pause streaming", isOn: $isStreamingPaused)

            Spacer()

            Button("Refresh") {
                Task { await reloadStoredLogs() }
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("diagnosticsRefreshButton")
        }
    }

    private var logList: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !instrumentationOutputInApp {
                Text("Enable In-App Logs in Settings for live instrumentation streaming.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
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
                                    .foregroundColor(entry.level.color)
                                Text(entry.area)
                                    .font(.caption2)
                                    .foregroundColor(diagnosticMetaColor)
                                Text(entry.source)
                                    .font(.caption2)
                                    .foregroundColor(diagnosticMetaColor)
                                if let stream = entry.consoleStream {
                                    Text(stream.label)
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

            #if DEBUG
            Toggle("Schema init on launch", isOn: $cloudKitSchemaInitOnLaunch)

            Button("Run Schema Init") {
                dataStoreController.runCloudKitSchemaInit()
            }
            #endif

            Spacer()

            Text("Entries: \(filteredEntries.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.bordered)
    }

    fileprivate nonisolated static func filteredLogs(
        from entries: [DiagnosticsLogEntry],
        searchText: String,
        severities: Set<DiagnosticsSeverity>,
        areas: Set<String>,
        consoleStreams: Set<ConsoleStream>
    ) -> [DiagnosticsLogEntry] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return entries.filter { entry in
            guard severities.contains(entry.level) else { return false }
            if !areas.isEmpty && !areas.contains(entry.area) {
                return false
            }
            if entry.source == "Console", let stream = entry.consoleStream {
                if !consoleStreams.contains(stream) {
                    return false
                }
            }
            if trimmed.isEmpty { return true }
            return entry.message.lowercased().contains(trimmed)
                || entry.area.lowercased().contains(trimmed)
                || entry.source.lowercased().contains(trimmed)
        }
    }

    private func reloadStoredLogs() async {
        let maxEntries = maxVisibleEntries
        let entries = await DiagnosticsLogWorker.shared.load(maxEntries: maxEntries)
        await MainActor.run {
            logEntries = entries
            scheduleFilterUpdate()
        }
    }


    private func appendInstrumentationLine(_ line: String) {
        let parsed = parseInstrumentationLine(line)
        let entry = DiagnosticsLogEntry(
            timestamp: Date(),
            source: "Instrumentation",
            area: parsed.area,
            level: parsed.level,
            message: parsed.message,
            consoleStream: nil
        )
        enqueueEntry(entry)
    }

    private func appendAILine(_ line: String) {
        let entry = DiagnosticsLogEntry(
            timestamp: Date(),
            source: "AI",
            area: "AI",
            level: inferredSeverity(for: line),
            message: line,
            consoleStream: nil
        )
        enqueueEntry(entry)
    }

    private func appendConsoleLine(_ line: String) {
        let parsed = parseConsoleLine(line)
        let entry = DiagnosticsLogEntry(
            timestamp: Date(),
            source: "Console",
            area: "Console",
            level: inferredSeverity(for: parsed.message),
            message: parsed.message,
            consoleStream: parsed.stream
        )
        enqueueEntry(entry)
    }

    private func parseConsoleLine(_ line: String) -> (message: String, stream: ConsoleStream?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[stdout]") {
            let message = trimmed.replacingOccurrences(of: "[stdout]", with: "").trimmingCharacters(in: .whitespaces)
            return (message, .stdout)
        }
        if trimmed.hasPrefix("[stderr]") {
            let message = trimmed.replacingOccurrences(of: "[stderr]", with: "").trimmingCharacters(in: .whitespaces)
            return (message, .stderr)
        }
        return (trimmed, nil)
    }

    private func enqueueEntry(_ entry: DiagnosticsLogEntry) {
        guard !isStreamingPaused else { return }

        let now = Date()
        if now.timeIntervalSince(streamWindowStart) >= 1.0 {
            streamWindowStart = now
            streamCount = 0
        }

        if streamCount >= maxLiveEntriesPerSecond {
            if !pendingEntries.isEmpty {
                pendingEntries.removeFirst()
            } else if !logEntries.isEmpty {
                logEntries.removeLast()
            }
        } else {
            streamCount += 1
        }

        pendingEntries.append(entry)
        if pendingEntries.count > maxVisibleEntries {
            pendingEntries.removeFirst(pendingEntries.count - maxVisibleEntries)
        }
        if flushTask == nil {
            flushTask = Task {
                try? await Task.sleep(nanoseconds: 200_000_000)
                await MainActor.run {
                    flushPendingEntries()
                }
            }
        }
    }

    private func flushPendingEntries() {
        guard !pendingEntries.isEmpty else {
            flushTask = nil
            return
        }
        logEntries = pendingEntries.reversed() + logEntries
        pendingEntries.removeAll(keepingCapacity: true)
        if logEntries.count > maxVisibleEntries {
            logEntries.removeLast(logEntries.count - maxVisibleEntries)
        }
        flushTask = nil
    }

    private func scheduleFilterUpdate() {
        filterTask?.cancel()
        let entries = logEntries
        let search = searchText
        let severities = selectedSeverities
        let areas = selectedAreas
        let consoleStreams = selectedConsoleStreams
        filterTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000)
            let filtered = await DiagnosticsLogWorker.shared.filter(
                entries: entries,
                searchText: search,
                severities: severities,
                areas: areas,
                consoleStreams: consoleStreams
            )
            await MainActor.run {
                filteredEntries = filtered
            }
        }
    }

    private func parseInstrumentationLine(_ line: String) -> (area: String, level: DiagnosticsSeverity, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else {
            return ("Instrumentation", .info, trimmed)
        }
        let parts = trimmed.split(separator: "]", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            let levelToken = parts[0].replacingOccurrences(of: "[", with: "")
            let areaToken = parts[1].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
            let level: DiagnosticsSeverity
            switch levelToken.lowercased() {
            case "error":
                level = .error
            case "warning":
                level = .warning
            default:
                level = .info
            }
            let message = trimmed.components(separatedBy: "] ").dropFirst(2).joined(separator: "] ")
            return (areaToken.isEmpty ? "Instrumentation" : areaToken, level, message)
        }
        return ("Instrumentation", .info, trimmed)
    }

    private func inferredSeverity(for message: String) -> DiagnosticsSeverity {
        let lower = message.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return .error
        }
        if lower.contains("warning") {
            return .warning
        }
        return .info
    }

    private func availableAreas() -> [String] {
        let areas = Set(logEntries.map { $0.area })
        return areas.sorted()
    }

    private func copyLogsToPasteboard() {
        let text = filteredEntries.map { entry in
            "\(formattedTimestamp(entry.timestamp)) [\(entry.level.label)] [\(entry.area)] \(entry.message)"
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
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
        let header = ["Timestamp", "Source", "Area", "Severity", "Console Stream", "Message"]
        let rows = filteredEntries.map { entry in
            [
                formattedTimestamp(entry.timestamp),
                entry.source,
                entry.area,
                entry.level.label,
                entry.consoleStream?.label ?? "",
                entry.message
            ]
        }
        do {
            try OOXMLWriter.writeXlsx(header: header, rows: rows, to: url)
        } catch {
            Instrumentation.log("Diagnostics export failed", area: .uiInteraction, level: .error, details: "error=\(error.localizedDescription)")
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
                source: entry.source,
                area: entry.area,
                severity: entry.level.rawValue,
                consoleStream: entry.consoleStream?.rawValue ?? "",
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
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
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
    }

    private func formattedTimestamp(_ timestamp: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: timestamp)
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
        let bundleID = Bundle.main.bundleIdentifier ?? "SPF Spectral Analyzer"
        let appDirectory = (baseDirectory ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent(bundleID, isDirectory: true)
        return appDirectory.appendingPathComponent("SPFSpectralAnalyzer.store", isDirectory: false)
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

struct DiagnosticsLogLoader {
    nonisolated static func loadInstrumentationLogs() -> [DiagnosticsLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "instrumentationLogEntriesData"),
              let payload = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) else {
            return []
        }
        return payload.map { payload in
            let parsed = parseInstrumentationLine(payload.message)
            return DiagnosticsLogEntry(
                timestamp: payload.timestamp,
                source: "Instrumentation",
                area: parsed.area,
                level: parsed.level,
                message: parsed.message,
                consoleStream: nil
            )
        }
    }

    nonisolated static func loadAILogs() -> [DiagnosticsLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "aiLogEntriesData"),
              let payload = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) else {
            return []
        }
        return payload.map { payload in
            DiagnosticsLogEntry(
                timestamp: payload.timestamp,
                source: "AI",
                area: "AI",
                level: inferredSeverity(for: payload.message),
                message: payload.message,
                consoleStream: nil
            )
        }
    }

    nonisolated static func loadConsoleLogs() -> [DiagnosticsLogEntry] {
        guard let data = UserDefaults.standard.data(forKey: "consoleLogEntriesData"),
              let payload = try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: data) else {
            return []
        }
        return payload.map { payload in
            let parsed = parseConsoleLine(payload.message)
            return DiagnosticsLogEntry(
                timestamp: payload.timestamp,
                source: "Console",
                area: "Console",
                level: inferredSeverity(for: parsed.message),
                message: parsed.message,
                consoleStream: parsed.stream
            )
        }
    }

    nonisolated private static func parseInstrumentationLine(_ line: String) -> (area: String, level: DiagnosticsSeverity, message: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("[") else {
            return ("Instrumentation", .info, trimmed)
        }
        let parts = trimmed.split(separator: "]", maxSplits: 2, omittingEmptySubsequences: true)
        if parts.count >= 2 {
            let levelToken = parts[0].replacingOccurrences(of: "[", with: "")
            let areaToken = parts[1].replacingOccurrences(of: "[", with: "").trimmingCharacters(in: .whitespaces)
            let level: DiagnosticsSeverity
            switch levelToken.lowercased() {
            case "error":
                level = .error
            case "warning":
                level = .warning
            default:
                level = .info
            }
            let message = trimmed.components(separatedBy: "] ").dropFirst(2).joined(separator: "] ")
            return (areaToken.isEmpty ? "Instrumentation" : areaToken, level, message)
        }
        return ("Instrumentation", .info, trimmed)
    }

    nonisolated private static func parseConsoleLine(_ line: String) -> (message: String, stream: ConsoleStream?) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("[stdout]") {
            let message = trimmed.replacingOccurrences(of: "[stdout]", with: "").trimmingCharacters(in: .whitespaces)
            return (message, .stdout)
        }
        if trimmed.hasPrefix("[stderr]") {
            let message = trimmed.replacingOccurrences(of: "[stderr]", with: "").trimmingCharacters(in: .whitespaces)
            return (message, .stderr)
        }
        return (trimmed, nil)
    }

    nonisolated private static func inferredSeverity(for message: String) -> DiagnosticsSeverity {
        let lower = message.lowercased()
        if lower.contains("error") || lower.contains("failed") {
            return .error
        }
        if lower.contains("warning") {
            return .warning
        }
        return .info
    }
}

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

private actor DiagnosticsLogWorker {
    static let shared = DiagnosticsLogWorker()

    func load(maxEntries: Int) -> [DiagnosticsLogEntry] {
        var items: [DiagnosticsLogEntry] = []
        items.append(contentsOf: DiagnosticsLogLoader.loadInstrumentationLogs())
        items.append(contentsOf: DiagnosticsLogLoader.loadAILogs())
        items.append(contentsOf: DiagnosticsLogLoader.loadConsoleLogs())
        items.sort { $0.timestamp > $1.timestamp }
        if items.count > maxEntries {
            return Array(items.prefix(maxEntries))
        }
        return items
    }

    func filter(
        entries: [DiagnosticsLogEntry],
        searchText: String,
        severities: Set<DiagnosticsSeverity>,
        areas: Set<String>,
        consoleStreams: Set<ConsoleStream>
    ) -> [DiagnosticsLogEntry] {
        DiagnosticsConsoleView.filteredLogs(
            from: entries,
            searchText: searchText,
            severities: severities,
            areas: areas,
            consoleStreams: consoleStreams
        )
    }
}

struct DiagnosticsLogExport: Codable {
    let timestamp: Date
    let source: String
    let area: String
    let severity: String
    let consoleStream: String
    let message: String
}


extension Notification.Name {
    static let aiLog = Notification.Name("AILog")
}
