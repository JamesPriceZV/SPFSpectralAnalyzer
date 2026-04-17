import SwiftUI
import SwiftData

/// Displays a consolidated status view of all active and recent jobs:
/// PINN training data downloads, ML model training, and CreateML training.
/// Each domain card supports initiating downloads and training with progress.
struct JobsDownloadsView: View {
    @State private var downloader = TrainingDataDownloader.shared
    @State private var mlService = MLTrainingService.shared
    @State private var pinnService = PINNPredictionService.shared

    /// Per-domain training managers, created on demand.
    @State private var trainingManagers: [PINNDomain: PINNTrainingManager] = [:]

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                #if os(macOS)
                // Active downloads
                downloadSection

                Divider()

                // Training data on disk + actions
                trainingDataSection
                #else
                // iOS: show model sync status only
                iOSModelStatusSection
                #endif

                Spacer()
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Jobs & Downloads", systemImage: "square.and.arrow.down.on.square")
                .font(.title2.bold())

            #if os(iOS)
            Text("PINN models are trained on Mac and synced to this device via iCloud.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    Task { await pinnService.loadModels() }
                } label: {
                    Label("Refresh Models", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(pinnService.isLoading)
            }
            .padding(.top, 4)
            #else
            Text("Training data downloads and model training status across all PINN domains.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Global actions
            HStack(spacing: 12) {
                Button {
                    Task { await downloader.downloadAllDomains() }
                } label: {
                    Label("Download All Domains", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(downloader.status.isActive)

                Button {
                    let result = PINNScriptInstaller.installAllScripts()
                    if !result.errors.isEmpty {
                        Instrumentation.log(
                            "Script install errors",
                            area: .mlTraining, level: .warning,
                            details: result.errors.joined(separator: "; ")
                        )
                    }
                } label: {
                    Label("Install All Scripts", systemImage: "arrow.down.doc")
                }
                .controlSize(.small)
            }
            .padding(.top, 4)
            #endif
        }
    }

    // MARK: - Downloads (macOS only)

    #if os(macOS)
    private var downloadSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Downloads")
                .font(.headline)

            if downloader.sourceStatuses.isEmpty && !downloader.status.isActive {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.green)
                    Text("No active downloads")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
            } else {
                // Overall status
                switch downloader.status {
                case .idle:
                    EmptyView()
                case .downloading(let source, let progress):
                    downloadProgressRow(
                        name: source,
                        progress: progress,
                        icon: "arrow.down.circle.fill",
                        color: .blue
                    )
                case .staging(let source):
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Staging: \(source)")
                            .font(.subheadline)
                    }
                case .completed(let count):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text("\(count) files downloaded")
                            .font(.subheadline)
                    }
                case .failed(let msg):
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(msg)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                // Per-source statuses
                if !downloader.sourceStatuses.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(
                            downloader.sourceStatuses.sorted(by: { $0.key < $1.key }),
                            id: \.key
                        ) { name, sourceStatus in
                            sourceStatusRow(name: name, status: sourceStatus)
                        }
                    }
                    .padding(.leading, 8)
                }
            }
        }
    }

    private func downloadProgressRow(name: String, progress: Double, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(name)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: progress)
                .tint(color)
        }
    }

    @ViewBuilder
    private func sourceStatusRow(name: String, status: TrainingDataDownloader.SourceStatus) -> some View {
        HStack(spacing: 8) {
            switch status {
            case .pending:
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .downloading(let bytes, let total):
                ProgressView()
                    .controlSize(.mini)
                    .frame(width: 16)
                Text(name)
                    .font(.caption)
                if let total, total > 0 {
                    Text(formatBytes(bytes) + " / " + formatBytes(total))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            case .completed(let size):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption)
                    .frame(width: 16)
                Text(name)
                    .font(.caption)
                Text(formatBytes(size))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .failed(let msg):
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
                    .frame(width: 16)
                Text(name)
                    .font(.caption)
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    // MARK: - Training Data on Disk (macOS)

    private var trainingDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Data")
                .font(.headline)

            // Read loadVersion to pick up model status changes
            let _ = pinnService.registry.loadVersion

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 10) {
                ForEach(PINNDomain.allCases) { domain in
                    domainCard(domain)
                }
            }
        }
    }

    private func domainCard(_ domain: PINNDomain) -> some View {
        let files = TrainingDataDownloader.downloadedFiles(for: domain)
        let totalSize = files.reduce(Int64(0)) { sum, url in
            sum + (Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0))
        }
        let scriptInstalled = FileManager.default.fileExists(
            atPath: PINNTrainingManager.scriptsDirectory
                .appendingPathComponent(PINNScriptInstaller.scriptFilename(for: domain)).path
        )
        let modelStatus = pinnService.registry.models[domain]?.status ?? .notTrained
        let manager = trainingManagers[domain]
        let isTraining = manager?.status.isActive ?? false

        return VStack(alignment: .leading, spacing: 6) {
            // Domain header with model status badge
            HStack(spacing: 6) {
                Image(systemName: domain.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text(domain.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                modelStatusBadge(modelStatus)
            }

            // File count and size
            HStack(spacing: 12) {
                Label("\(files.count) files", systemImage: "doc")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if totalSize > 0 {
                    Text(formatBytes(totalSize))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Script status (macOS only — scripts can't execute on iOS)
            #if os(macOS)
            HStack(spacing: 6) {
                Circle()
                    .fill(scriptInstalled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(scriptInstalled ? "Script ready" : "Script not installed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            #endif

            // Training progress (if active) or last training summary
            if let mgr = manager {
                trainingStatusRow(mgr)
                // Show last training metrics if available
                if !mgr.trainingHistory.isEmpty, !mgr.status.isActive {
                    trainingMetricsSummary(mgr)
                }
            }

            // Action buttons
            HStack(spacing: 8) {
                Button {
                    Task { await downloader.downloadAllSources(for: domain) }
                } label: {
                    Label("Download", systemImage: "arrow.down.circle")
                }
                .font(.caption)
                .controlSize(.mini)
                .disabled(downloader.status.isActive)

                #if os(macOS)
                Button {
                    Task { await startTraining(for: domain) }
                } label: {
                    Label("Train", systemImage: "cpu")
                }
                .font(.caption)
                .controlSize(.mini)
                .disabled(files.isEmpty || isTraining || !scriptInstalled)
                #endif
            }
            .padding(.top, 2)
        }
        .padding(10)
        #if compiler(>=6.2)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        #else
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        #endif
    }
    #endif // os(macOS) — end of download/training data sections

    @ViewBuilder
    private func modelStatusBadge(_ status: PINNModelStatus) -> some View {
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption2)
                .foregroundStyle(.green)
        case .loading:
            HStack(spacing: 2) {
                ProgressView().controlSize(.mini)
                Text("Loading").font(.caption2).foregroundStyle(.orange)
            }
        case .notTrained:
            Text("--")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2)
                .foregroundStyle(.red)
                .lineLimit(1)
        }
    }

    #if os(macOS)
    @ViewBuilder
    private func trainingStatusRow(_ manager: PINNTrainingManager) -> some View {
        switch manager.status {
        case .training(let progress, let epoch, let total):
            VStack(alignment: .leading, spacing: 2) {
                ProgressView(value: progress)
                    .tint(.blue)
                Text("Epoch \(epoch)/\(total)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        case .exportingData:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Exporting data...").font(.caption2).foregroundStyle(.secondary)
            }
        case .converting:
            HStack(spacing: 4) {
                ProgressView().controlSize(.mini)
                Text("Converting...").font(.caption2).foregroundStyle(.secondary)
            }
        case .completed(let d):
            Label("\(d.displayName) complete", systemImage: "checkmark.circle.fill")
                .font(.caption2).foregroundStyle(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption2).foregroundStyle(.red)
                .lineLimit(2)
        default:
            EmptyView()
        }
    }

    /// Compact training metrics summary for completed training runs.
    private func trainingMetricsSummary(_ manager: PINNTrainingManager) -> some View {
        let history = manager.trainingHistory
        let lastMetric = history.last
        let epochCount = history.count

        return VStack(alignment: .leading, spacing: 2) {
            if let last = lastMetric {
                HStack(spacing: 8) {
                    Text("Epochs: \(epochCount)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Data: \(String(format: "%.4f", last.dataLoss))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Physics: \(String(format: "%.4f", last.physicsLoss))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Warn if loss diverged
                if epochCount > 10, let early = history.dropFirst(5).first,
                   last.dataLoss > early.dataLoss * 2 {
                    Label("Loss diverged — try lower learning rate", systemImage: "exclamationmark.triangle")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
            }
        }
    }
    #endif // os(macOS) — end of training status/metrics

    // MARK: - iOS Model Status

    #if os(iOS)
    private var iOSModelStatusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let _ = pinnService.registry.loadVersion

            HStack {
                Text("PINN Model Status")
                    .font(.headline)
                Spacer()
                Text("\(pinnService.readyModelCount)/\(PINNDomain.allCases.count) ready")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if pinnService.isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Checking iCloud for models…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12)
            ], spacing: 10) {
                ForEach(PINNDomain.allCases) { domain in
                    iOSDomainCard(domain)
                }
            }

            if pinnService.readyModelCount == 0 {
                VStack(alignment: .leading, spacing: 6) {
                    Divider()
                    Label("No models available", systemImage: "info.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Train PINN models on your Mac, then they sync automatically via iCloud. Tap Refresh Models to check for updates.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, 4)
            }
        }
    }

    private func iOSDomainCard(_ domain: PINNDomain) -> some View {
        let modelStatus = pinnService.registry.models[domain]?.status ?? .notTrained

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: domain.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text(domain.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                modelStatusBadge(modelStatus)
            }

            // Show sync hint for models not yet available
            switch modelStatus {
            case .ready:
                Text("Model loaded and ready for predictions")
                    .font(.caption2)
                    .foregroundStyle(.green)
            case .loading:
                Text("Downloading from iCloud…")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            case .notTrained:
                Text("Train on Mac to enable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            case .error(let msg):
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(10)
        #if compiler(>=6.2)
        .glassEffect(.regular, in: .rect(cornerRadius: 10))
        #else
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        #endif
    }
    #endif

    // MARK: - Training

    #if os(macOS)
    private func startTraining(for domain: PINNDomain) async {
        // Get or create a training manager for this domain
        let manager: PINNTrainingManager
        if let existing = trainingManagers[domain] {
            manager = existing
        } else {
            let newManager = PINNTrainingManager()
            trainingManagers[domain] = newManager
            manager = newManager
        }

        // Install scripts
        _ = PINNScriptInstaller.installAllScripts()

        // Gather training data
        let gathered = PINNDataExportService.gatherAllTrainingData(for: domain, modelContext: modelContext)

        guard gathered.entries.count >= 2 else {
            manager.status = .failed("Not enough training data (\(gathered.entries.count) entries)")
            return
        }

        do {
            let export = PINNDataExportService.TrainingDataExport(
                domain: domain.rawValue,
                exportDate: Date(),
                entryCount: gathered.entries.count,
                entries: gathered.entries
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(export)
            try PINNDataExportService.saveToTrainingDirectory(data: data, domain: domain)

            // Use domain-specific learning rates to avoid divergence.
            // UV-Vis with large Figshare datasets needs a lower rate.
            let lr: Double = switch domain {
            case .uvVis, .raman, .nmr: 0.0001
            case .chromatography: 0.00005
            default: 0.0003
            }

            await manager.train(
                domain: domain,
                referenceData: data,
                epochs: 500,
                learningRate: lr
            )

            if case .completed = manager.status {
                await pinnService.loadModels()
            }
        } catch {
            manager.status = .failed("Data prep failed: \(error.localizedDescription)")
        }
    }
    #endif

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
