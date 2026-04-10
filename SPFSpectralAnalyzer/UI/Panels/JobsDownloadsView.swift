import SwiftUI

/// Displays a consolidated status view of all active and recent jobs:
/// PINN training data downloads, ML model training, and CreateML training.
struct JobsDownloadsView: View {
    @State private var downloader = TrainingDataDownloader.shared
    @State private var mlService = MLTrainingService.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection

                // Active downloads
                downloadSection

                Divider()

                // Training data on disk
                trainingDataSection

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

            Text("Training data downloads and model training status across all PINN domains.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Downloads

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

    // MARK: - Training Data on Disk

    private var trainingDataSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Training Data")
                .font(.headline)

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

        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: domain.iconName)
                    .foregroundStyle(.blue)
                    .frame(width: 20)
                Text(domain.displayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
            }

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

            HStack(spacing: 6) {
                Circle()
                    .fill(scriptInstalled ? Color.green : Color.orange)
                    .frame(width: 6, height: 6)
                Text(scriptInstalled ? "Script ready" : "Script not installed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
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

    // MARK: - Helpers

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
