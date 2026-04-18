import SwiftUI

// MARK: - SharePoint Export View

/// Sheet view for exporting files and analysis results to SharePoint.
/// Presented as a modal from the Enterprise tab or AI analysis section.
struct SharePointExportView: View {
    let authManager: MSALAuthManager
    @Environment(\.dismiss) private var dismiss

    // Export configuration (read from UserDefaults)
    @AppStorage(M365Config.StorageKeys.exportConfigJSON) private var exportConfigJSON = ""

    // State
    @State private var exportConfig = SharePointExportConfig.default
    @State private var selectedExportType = ExportType.analysisResults
    @State private var customFileName = ""
    @State private var isUploading = false
    @State private var uploadProgress = 0.0
    @State private var uploadResult: UploadResult?
    @State private var exportError: String?

    /// The data to export, provided by the caller.
    var exportData: Data?
    /// Suggested file name for the export.
    var suggestedFileName: String?
    /// Analysis text for text-based export.
    var analysisText: String?

    var body: some View {
        NavigationStack {
            Form {
                // Status Section
                Section("M365 Account") {
                    if authManager.isSignedIn {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text("Signed In")
                                    .font(.subheadline.bold())
                                if let username = authManager.username {
                                    Text(username)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    } else {
                        Label("Sign in to Microsoft 365 in Settings to export.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                    }
                }

                // Export Type
                Section("Export Type") {
                    Picker("Type", selection: $selectedExportType) {
                        ForEach(ExportType.allCases) { type in
                            Label(type.displayName, systemImage: type.iconName)
                                .tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(selectedExportType.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Destination
                Section("Destination") {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Site")
                            .font(.caption.bold())
                        if exportConfig.destinationSitePath.isEmpty {
                            Text("Not configured — set in Settings > Enterprise")
                                .font(.caption)
                                .foregroundColor(.orange)
                        } else {
                            Text(exportConfig.destinationSitePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Folder")
                            .font(.caption.bold())
                        if exportConfig.destinationFolderPath.isEmpty {
                            Text("Root of document library")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text(exportConfig.destinationFolderPath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // File Name
                Section("File Name") {
                    TextField("File name", text: $customFileName)
                        .textFieldStyle(.roundedBorder)

                    if customFileName.isEmpty, let suggested = resolvedFileName {
                        Text("Will use: \(suggested)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Upload Progress / Result
                if isUploading {
                    Section("Uploading") {
                        VStack(spacing: 8) {
                            ProgressView(value: uploadProgress)
                                .progressViewStyle(.linear)
                            Text("\(Int(uploadProgress * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if let result = uploadResult {
                    Section("Result") {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            VStack(alignment: .leading) {
                                Text(result.fileName)
                                    .font(.subheadline.bold())
                                if let url = result.webUrl {
                                    Link("Open in SharePoint", destination: URL(string: url)!)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }

                if let exportError {
                    Section("Error") {
                        Label(exportError, systemImage: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Export to SharePoint")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") {
                        Task { await performUpload() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canUpload)
                }
            }
            .onAppear {
                loadExportConfig()
                if let suggestedFileName, customFileName.isEmpty {
                    customFileName = suggestedFileName
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    // MARK: - Computed

    private var canUpload: Bool {
        authManager.isSignedIn &&
        !isUploading &&
        !exportConfig.destinationSitePath.isEmpty &&
        exportDataToUpload != nil &&
        uploadResult == nil
    }

    private var resolvedFileName: String? {
        let template = exportConfig.namingTemplate
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        let dateString = dateFormatter.string(from: Date())

        var name = template
            .replacingOccurrences(of: "{date}", with: dateString)
            .replacingOccurrences(of: "{product}", with: "analysis")
            .replacingOccurrences(of: "{type}", with: selectedExportType.fileExtension)
            .replacingOccurrences(of: "{spf}", with: "")

        if !name.hasSuffix(".\(selectedExportType.fileExtension)") {
            name += ".\(selectedExportType.fileExtension)"
        }
        return name
    }

    private var exportDataToUpload: Data? {
        if let exportData { return exportData }
        if let analysisText {
            return analysisText.data(using: .utf8)
        }
        return nil
    }

    // MARK: - Actions

    private func loadExportConfig() {
        guard !exportConfigJSON.isEmpty,
              let data = exportConfigJSON.data(using: .utf8),
              let config = try? JSONDecoder().decode(SharePointExportConfig.self, from: data) else {
            return
        }
        exportConfig = config
    }

    private func performUpload() async {
        guard let data = exportDataToUpload else { return }

        isUploading = true
        uploadProgress = 0
        exportError = nil

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.exportScopes)
            let fileName = customFileName.isEmpty ? (resolvedFileName ?? "export.txt") : customFileName

            // Resolve SharePoint site ID from user-provided path/URL
            let site = try await GraphUploadService.resolveSiteId(
                from: exportConfig.destinationSitePath,
                token: token
            )

            let item = try await GraphUploadService.upload(
                fileData: data,
                fileName: fileName,
                siteId: site.siteId,
                folderPath: exportConfig.destinationFolderPath,
                token: token,
                onProgress: { progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                }
            )

            uploadResult = UploadResult(fileName: item.name, webUrl: item.webUrl)
            isUploading = false
            uploadProgress = 1.0
        } catch {
            exportError = error.localizedDescription
            isUploading = false
        }
    }
}

// MARK: - Supporting Types

extension SharePointExportView {
    enum ExportType: String, CaseIterable, Identifiable {
        case analysisResults = "results"
        case rawData = "raw"
        case report = "report"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .analysisResults: return "Results"
            case .rawData: return "Raw Data"
            case .report: return "Report"
            }
        }

        var iconName: String {
            switch self {
            case .analysisResults: return "doc.text"
            case .rawData: return "waveform"
            case .report: return "doc.richtext"
            }
        }

        var description: String {
            switch self {
            case .analysisResults: return "Export AI analysis results as a text file."
            case .rawData: return "Export raw spectral data (.csv)."
            case .report: return "Export a formatted analysis report."
            }
        }

        var fileExtension: String {
            switch self {
            case .analysisResults: return "txt"
            case .rawData: return "csv"
            case .report: return "txt"
            }
        }
    }

    struct UploadResult {
        let fileName: String
        let webUrl: String?
    }
}
