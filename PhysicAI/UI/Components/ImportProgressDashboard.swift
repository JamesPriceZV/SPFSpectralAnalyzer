import SwiftUI

/// Compact mini-dashboard replacing the old drop zone.
/// Shows library summary when idle, live import progress when active,
/// and a completion/failure banner after import finishes.
struct ImportProgressDashboard: View {
    var progress: ImportProgress
    var datasetCount: Int
    var spectrumCount: Int

    /// Whether a drag-and-drop hover is active over this area.
    var dropTargeted: Bool = false

    var body: some View {
        Group {
            if progress.isActive {
                activeView
            } else if progress.isCompleted {
                completedView
            } else if progress.isFailed {
                failedView
            } else {
                idleView
            }
        }
        .frame(height: 72)
        .frame(maxWidth: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    dropTargeted ? Color.accentColor : Color.clear,
                    lineWidth: dropTargeted ? 2 : 0
                )
        )
        .animation(.easeInOut(duration: 0.25), value: progress.stage)
    }

    // MARK: - Idle

    private var idleView: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 20))
                .foregroundColor(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("Library")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.primary)
                Text("\(datasetCount) dataset\(datasetCount == 1 ? "" : "s") · \(spectrumCount) spectr\(spectrumCount == 1 ? "um" : "a")")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if dropTargeted {
                Label("Drop to import", systemImage: "arrow.down.doc.fill")
                    .font(.caption)
                    .foregroundColor(.accentColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Active (Parsing / Validating / Persisting)

    private var activeView: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 4) {
                Text(progress.stageLabel)
                    .font(.caption.weight(.medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: progress.overallProgress)
                    .tint(progress.tintColor)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Completed

    private var completedView: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20))
                .foregroundColor(.green)
            Text(progress.stageLabel)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                progress.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Failed

    private var failedView: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 20))
                .foregroundColor(.orange)
            Text(progress.stageLabel)
                .font(.caption.weight(.medium))
                .foregroundColor(.primary)
                .lineLimit(2)
            Spacer()
            Button {
                progress.reset()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundColor(.secondary.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Dismiss")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
