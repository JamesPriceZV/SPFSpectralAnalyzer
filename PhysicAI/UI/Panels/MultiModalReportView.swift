import SwiftUI

/// Displays a Multi-Modal Ensemble Analysis report with per-domain results,
/// cross-domain insights, and export controls.
struct MultiModalReportView: View {
    let report: MultiModalReport
    let authManager: MSALAuthManager

    @Environment(\.dismiss) private var dismiss
    @State private var exportError: String?
    @State private var exportSuccess: String?
    @State private var isUploading = false
    @State private var uploadProgress = 0.0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    domainResultsSection
                    crossDomainSection
                    consistencySection
                    recommendationsSection
                    risksSection
                    exportStatusSection
                }
                .padding()
            }
            .navigationTitle("Multi-Modal Report")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if os(macOS)
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        exportLocally()
                    } label: {
                        Label("Save Locally", systemImage: "arrow.down.doc")
                    }

                    if authManager.isSignedIn {
                        Button {
                            Task { await uploadToSharePoint() }
                        } label: {
                            Label("Upload to SharePoint", systemImage: "icloud.and.arrow.up")
                        }
                        .disabled(isUploading)
                    }
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                #endif
            }
        }
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 500)
        #endif
    }

    // MARK: - Header

    private var headerSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                Text(report.sampleName)
                    .font(.title2.bold())

                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .foregroundColor(.secondary)
                    Text(report.generatedAt, style: .date)
                    Text("at")
                        .foregroundColor(.secondary)
                    Text(report.generatedAt, style: .time)
                }
                .font(.subheadline)

                // Domain badges
                HStack(spacing: 6) {
                    ForEach(report.domainResults) { result in
                        Label(result.domain.displayName, systemImage: result.domain.iconName)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.accentColor.opacity(0.12))
                            .cornerRadius(6)
                    }
                }
            }
        } label: {
            Label("Combined Multi-Modal Analysis", systemImage: "rectangle.split.3x1")
                .font(.subheadline.bold())
        }
    }

    // MARK: - Domain Results

    private var domainResultsSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(report.domainResults) { result in
                    domainResultCard(result)
                    if result.id != report.domainResults.last?.id {
                        Divider()
                    }
                }
            }
        } label: {
            Label("Domain Results", systemImage: "cpu")
                .font(.subheadline.bold())
        }
    }

    private func domainResultCard(_ result: MultiModalReport.DomainResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: result.domain.iconName)
                    .foregroundColor(.accentColor)
                Text(result.domain.displayName)
                    .font(.subheadline.bold())
                Spacer()
                physicsScoreBadge(result.prediction.physicsConsistencyScore)
            }

            HStack(spacing: 16) {
                LabeledContent(result.prediction.primaryLabel) {
                    Text(result.prediction.formatted)
                        .monospacedDigit()
                        .font(.subheadline.bold())
                }

                if result.prediction.confidenceLow > 0 {
                    LabeledContent("Confidence") {
                        Text("\(String(format: "%.1f", result.prediction.confidenceLow)) – \(String(format: "%.1f", result.prediction.confidenceHigh))")
                            .monospacedDigit()
                            .font(.caption)
                    }
                }
            }

            if !result.keyFindings.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(result.keyFindings, id: \.self) { finding in
                        HStack(alignment: .top, spacing: 4) {
                            Text("•")
                            Text(finding)
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func physicsScoreBadge(_ score: Double) -> some View {
        let color: Color = score >= 0.8 ? .green : score >= 0.5 ? .orange : .red
        HStack(spacing: 3) {
            Image(systemName: "atom")
                .font(.caption2)
            Text("\(String(format: "%.0f%%", score * 100))")
                .font(.caption.monospacedDigit())
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(color.opacity(0.12))
        .cornerRadius(4)
    }

    // MARK: - Cross-Domain Insights

    private var crossDomainSection: some View {
        GroupBox {
            if report.crossDomainInsights.isEmpty {
                Text("No cross-domain insights available.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.crossDomainInsights, id: \.self) { insight in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "lightbulb.fill")
                                .foregroundColor(.yellow)
                                .font(.caption)
                            Text(insight)
                                .font(.caption)
                        }
                    }
                }
            }
        } label: {
            Label("Cross-Domain Insights", systemImage: "arrow.triangle.merge")
                .font(.subheadline.bold())
        }
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        GroupBox {
            Text(report.consistencyAssessment)
                .font(.caption)
        } label: {
            Label("Consistency Assessment", systemImage: "checkmark.shield")
                .font(.subheadline.bold())
        }
    }

    // MARK: - Recommendations

    @ViewBuilder
    private var recommendationsSection: some View {
        if !report.recommendations.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.recommendations, id: \.self) { rec in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                            Text(rec)
                                .font(.caption)
                        }
                    }
                }
            } label: {
                Label("Recommendations", systemImage: "checkmark.circle")
                    .font(.subheadline.bold())
            }
        }
    }

    // MARK: - Risks

    @ViewBuilder
    private var risksSection: some View {
        if !report.risks.isEmpty {
            GroupBox {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(report.risks, id: \.self) { risk in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                                .font(.caption)
                            Text(risk)
                                .font(.caption)
                        }
                    }
                }
            } label: {
                Label("Risks & Limitations", systemImage: "exclamationmark.triangle")
                    .font(.subheadline.bold())
            }
        }
    }

    // MARK: - Export Status

    @ViewBuilder
    private var exportStatusSection: some View {
        if isUploading {
            HStack(spacing: 8) {
                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
                Text("Uploading...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }

        if let success = exportSuccess {
            Label(success, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        }

        if let error = exportError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        }
    }

    // MARK: - Actions

    #if os(macOS)
    private func exportLocally() {
        exportError = nil
        exportSuccess = nil
        do {
            if let url = try MultiModalExportService.exportLocally(report) {
                exportSuccess = "Saved to \(url.lastPathComponent)"
            }
        } catch {
            exportError = "Export failed: \(error.localizedDescription)"
        }
    }
    #endif

    private func uploadToSharePoint() async {
        guard authManager.isSignedIn else {
            exportError = "Sign in to Microsoft 365 first."
            return
        }

        exportError = nil
        exportSuccess = nil
        isUploading = true
        uploadProgress = 0

        do {
            let token = try await authManager.acquireToken(
                scopes: M365Config.exportScopes
            )

            // Read export config from UserDefaults
            let configJSON = UserDefaults.standard.string(forKey: M365Config.StorageKeys.exportConfigJSON) ?? ""
            let exportConfig = (try? JSONDecoder().decode(SharePointExportConfig.self, from: Data(configJSON.utf8)))
                ?? .default

            let sitePath = exportConfig.destinationSitePath
            let folderPath = exportConfig.destinationFolderPath.isEmpty
                ? "PhysicAI/Reports"
                : exportConfig.destinationFolderPath

            guard !sitePath.isEmpty else {
                exportError = "Configure SharePoint export destination in Settings."
                isUploading = false
                return
            }

            // Resolve site ID from the configured site path
            let siteInfo = try await GraphUploadService.resolveSiteId(
                from: sitePath,
                token: token
            )
            let siteId = siteInfo.siteId

            _ = try await MultiModalExportService.uploadToSharePoint(
                report,
                siteId: siteId,
                folderPath: folderPath,
                token: token,
                onProgress: { progress in
                    Task { @MainActor in
                        uploadProgress = progress
                    }
                }
            )

            exportSuccess = "Uploaded to SharePoint successfully"
        } catch {
            exportError = "Upload failed: \(error.localizedDescription)"
        }

        isUploading = false
    }
}
