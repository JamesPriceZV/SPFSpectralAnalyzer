import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif

extension ContentView {

    nonisolated static func sampleDisplayName(from url: URL, spectrumName: String, index: Int, total: Int) -> String {
        let trimmed = spectrumName.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        let isGeneric = trimmed.isEmpty || lower.hasPrefix("dataset") || lower.hasPrefix("data set")

        let baseName = url.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines)
        var name = isGeneric ? baseName : trimmed

        if total > 1 {
            name += " #\(index + 1)"
        }

        return name
    }

    @ViewBuilder
    func glassGroup<Content: View>(spacing: CGFloat = 12, @ViewBuilder content: () -> Content) -> some View {
        if #available(macOS 15.0, *) {
            GlassEffectContainer(spacing: spacing) {
                content()
            }
        } else {
            content()
        }
    }

    // MARK: - Reference Exclusion Persistence

    /// Computed bridge between the JSON @AppStorage and the Set<UUID> used by DatasetViewModel.
    var excludedReferenceIDs: Set<UUID> {
        get {
            guard let data = excludedReferenceIDsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return Set(strings.compactMap { UUID(uuidString: $0) })
        }
        nonmutating set {
            let strings = newValue.map { $0.uuidString }
            if let data = try? JSONEncoder().encode(strings),
               let json = String(data: data, encoding: .utf8) {
                excludedReferenceIDsJSON = json
            }
        }
    }

    /// Syncs the persisted exclusion set to the DatasetViewModel and triggers a rebuild.
    func syncExcludedReferencesToViewModel() {
        datasets.excludedReferenceDatasetIDs = excludedReferenceIDs
    }

    var aiPromptPreset: AIPromptPreset {
        get { AIPromptPreset(rawValue: aiPromptPresetRawValue) ?? .summary }
        nonmutating set { aiPromptPresetRawValue = newValue.rawValue }
    }

    var effectiveAIPrompt: String {
        if aiVM.useCustomPrompt {
            let trimmed = aiVM.customPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                return trimmed
            }
        }
        return aiPromptPreset.template
    }

    var aiDefaultScope: AISelectionScope {
        get { AISelectionScope(rawValue: aiDefaultScopeRawValue) ?? .selected }
        nonmutating set { aiDefaultScopeRawValue = newValue.rawValue }
    }

    var effectiveAIScope: AISelectionScope {
        aiVM.scopeOverride ?? aiDefaultScope
    }

    var aiProviderPreference: AIProviderPreference {
        get { AIProviderPreference(rawValue: aiProviderPreferenceRawValue) ?? .auto }
        nonmutating set { aiProviderPreferenceRawValue = newValue.rawValue }
    }

    var hasAPIKey: Bool {
        KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) != nil
    }

    var activeMetadataFromSelection: ShimadzuSPCMetadata? {
        // Use the metadata already set during `loadStoredDataset()` instead of decoding
        // from the model on every render. Reading `dataset.metadataJSON` during CloudKit
        // sync can trigger `swift_weakLoadStrong` → crash.
        return analysis.activeMetadata
    }

    var activeHeader: SPCMainHeader? {
        activeMetadataFromSelection?.mainHeader
    }

    var activeHeaderFileName: String? {
        // Read from cache instead of model to avoid CloudKit sync weak-reference crash.
        if let id = storedDatasets.first(where: { datasets.selectedStoredDatasetIDs.contains($0.id) })?.id,
           let record = datasets.searchableRecordCache[id] {
            return record.fileName
        }
        return analysis.activeMetadataSource
    }

    var aiCanRunAnalysis: Bool {
        guard aiEnabled else { return false }
        // On-device AI doesn't need API key/endpoint
        if aiProviderPreference == .onDevice || aiProviderPreference == .auto {
            if aiVM.providerManager.isOnDeviceAvailable { return true }
        }
        // OpenAI needs API key + endpoint + model
        if aiProviderPreference == .openAI || aiProviderPreference == .auto {
            return hasAPIKey && !aiOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !aiOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return false
    }

    func isStructuredOutputSupported(_ model: String) -> Bool {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized.isEmpty { return false }
        if normalized.hasPrefix("gpt-4o-mini") { return true }
        if normalized.hasPrefix("gpt-4o") { return true }
        return false
    }

    func savePanel(defaultName: String, allowedTypes: [UTType], directoryKey: SaveDirectoryKey) -> URL? {
        #if canImport(AppKit)
        let panel = NSSavePanel()
        panel.nameFieldStringValue = timestampedFileName(defaultName)
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        if let directory = lastSaveDirectoryURL(for: directoryKey) {
            panel.directoryURL = directory
        }
        if panel.runModal() == .OK, let url = panel.url {
            storeLastSaveDirectory(from: url, key: directoryKey)
            return url
        }
        return nil
        #else
        return nil // iOS: Phase 2 will migrate callers to PlatformFileSaver
        #endif
    }

    func timestampedFileName(_ baseName: String) -> String {
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

    enum SaveDirectoryKey: String {
        case analysisExports = "lastSaveDirectory.analysisExports"
        case aiReports = "lastSaveDirectory.aiReports"
        case aiLogs = "lastSaveDirectory.aiLogs"
        case instrumentationLogs = "lastSaveDirectory.instrumentationLogs"
        case validationLogs = "lastSaveDirectory.validationLogs"
    }

    /// Resolve the auto-save directory: last-used → Downloads → temp.
    func autoSaveDirectoryURL(for key: SaveDirectoryKey) -> URL {
        lastSaveDirectoryURL(for: key)
            ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
    }

    func lastSaveDirectoryURL(for key: SaveDirectoryKey) -> URL? {
        guard let path = UserDefaults.standard.string(forKey: key.rawValue) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func storeLastSaveDirectory(from url: URL, key: SaveDirectoryKey) {
        let directory = url.deletingLastPathComponent()
        UserDefaults.standard.set(directory.path, forKey: key.rawValue)
    }

    func sanitizeCSVField(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return value
    }

    func formatBytes(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    func metadataSummaryLines(_ metadata: ShimadzuSPCMetadata?) -> [String] {
        guard let metadata else { return ["Metadata: unavailable"] }
        var lines: [String] = []
        lines.append("File Size: \(formatBytes(metadata.fileSizeBytes))")
        lines.append("Header Bytes: \(metadata.headerInfoByteCount)")
        if let header = metadata.mainHeader {
            lines.append("Experiment: \(header.experimentType) • X: \(header.xUnit) • Y: \(header.yUnit)")
        }
        let preview = metadata.dataSetNames.prefix(3).joined(separator: ", ")
        if !preview.isEmpty {
            let extra = max(0, metadata.dataSetNames.count - 3)
            lines.append("Datasets: \(preview)\(extra > 0 ? " +\(extra) more" : "")")
        }
        return lines
    }

    func metadataDetailLines(_ metadata: ShimadzuSPCMetadata?) -> [String] {
        guard let metadata else { return ["Metadata: unavailable"] }
        var lines: [String] = []
        lines.append("File: \(metadata.fileName)")
        lines.append("File Size: \(formatBytes(metadata.fileSizeBytes))")
        lines.append("Header Bytes: \(metadata.headerInfoByteCount)")
        lines.append("Datasets: \(metadata.dataSetNames.joined(separator: ", "))")
        lines.append("Directory Entries: \(metadata.directoryEntryNames.joined(separator: ", "))")

        if let header = metadata.mainHeader {
            lines.append("SPC Version: \(header.spcVersion)")
            lines.append("File Type Flags: \(header.fileTypeFlags) (\(header.fileType))")
            lines.append("Experiment Type: \(header.experimentTypeCode) (\(header.experimentType))")
            lines.append("Y Exponent: \(header.yExponent)")
            lines.append("Point Count: \(header.pointCount)")
            lines.append(String(format: "First X: %.6f", header.firstX))
            lines.append(String(format: "Last X: %.6f", header.lastX))
            lines.append("Subfile Count: \(header.subfileCount)")
            lines.append("X Units: \(header.xUnitsCode) (\(header.xUnit))")
            lines.append("Y Units: \(header.yUnitsCode) (\(header.yUnit))")
            lines.append("Z Units: \(header.zUnitsCode) (\(header.zUnit))")
            lines.append("Posting Disposition: \(header.postingDisposition)")
            lines.append("Compressed Date: \(spcDateString(header.compressedDate))")
            lines.append("Resolution: \(header.resolutionText)")
            lines.append("Instrument: \(header.sourceInstrumentText)")
            lines.append("Peak Point #: \(header.peakPointNumber)")
            lines.append("Memo: \(header.memo)")
            lines.append("Custom Axis Combined: \(header.customAxisCombined)")
            lines.append("Custom Axis X: \(header.customAxisX)")
            lines.append("Custom Axis Y: \(header.customAxisY)")
            lines.append("Custom Axis Z: \(header.customAxisZ)")
            lines.append("Log Block Offset: \(header.logBlockOffset)")
            lines.append("File Modification Flag: \(header.fileModificationFlag)")
            lines.append("Processing Code: \(header.processingCode)")
            lines.append("Calibration Level + 1: \(header.calibrationLevelPlusOne)")
            lines.append("Submethod Injection #: \(header.subMethodInjectionNumber)")
            lines.append(String(format: "Concentration Factor: %.6f", header.concentrationFactor))
            lines.append("Method File: \(header.methodFile)")
            lines.append(String(format: "Z Subfile Increment: %.6f", header.zSubfileIncrement))
            lines.append("W Plane Count: \(header.wPlaneCount)")
            lines.append(String(format: "W Plane Increment: %.6f", header.wPlaneIncrement))
            lines.append("W Units: \(header.wAxisUnitsCode) (\(header.wUnit))")
        } else {
            lines.append("SPC Header: unavailable")
        }

        return lines
    }

    func spcDateString(_ date: SPCCompressedDate) -> String {
        if date.year == 0 && date.month == 0 && date.day == 0 && date.hour == 0 && date.minute == 0 {
            return "Unknown"
        }
        return String(format: "%04d-%02d-%02d %02d:%02d", date.year, date.month, date.day, date.hour, date.minute)
    }

}
