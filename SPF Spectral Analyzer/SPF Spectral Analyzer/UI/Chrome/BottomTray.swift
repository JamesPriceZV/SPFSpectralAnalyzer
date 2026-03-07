import SwiftUI

extension ContentView {

    var bottomTray: some View {
        HStack(spacing: 12) {
            // Status message
            Text(analysis.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)

            if let warningMessage = analysis.warningMessage {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.caption2)
                    Text(warningMessage)
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                }
            }

            Spacer()

            // Spectrum count
            if !analysis.spectra.isEmpty {
                Text("\(displayedSpectra.count) spectra")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Cloud sync indicator
            Group {
                if icloudSyncInProgress {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: dataStoreController.cloudSyncEnabled
                        ? "icloud.fill" : "icloud.slash")
                        .font(.caption)
                        .foregroundColor(dataStoreController.cloudSyncEnabled
                            ? .green : .secondary)
                }
            }
            .help(icloudSyncInProgress ? "Syncing…"
                : dataStoreController.cloudSyncEnabled ? "iCloud: \(icloudLastSyncStatus)"
                : "iCloud sync disabled")

            // Diagnostics console button
            Button {
                openWindow(id: "diagnostics-console")
            } label: {
                Image(systemName: "ladybug")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open Diagnostics Console")

            // Instrument window button
            Button {
                openWindow(id: "instrument-control")
            } label: {
                Image(systemName: "dial.medium")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .help("Open Instrument Control")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(panelBackground)
    }

    var statusPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(analysis.statusMessage)
                .foregroundColor(.secondary)
            if let warningMessage = analysis.warningMessage {
                HStack(spacing: 8) {
                    Text(warningMessage)
                        .font(.caption)
                        .foregroundColor(.orange)
                    if !analysis.warningDetails.isEmpty {
                        Button("Details") { showWarningDetails = true }
                            .buttonStyle(.link)
                    }
                }
            }
            if !analysis.invalidItems.isEmpty {
                HStack(spacing: 8) {
                    Text("Invalid spectra: \(analysis.invalidItems.count)")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Button("View") { showInvalidDetails = true }
                        .buttonStyle(.link)
                }
            }
            if !analysis.spectra.isEmpty {
                Text("Spectra loaded: \(analysis.spectra.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if analysis.detectPeaks {
                Text("Peaks detected: \(analysis.peaks.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    var backgroundView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(.windowBackgroundColor),
                    Color(.windowBackgroundColor).opacity(0.92)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.blue.opacity(0.08))
                .frame(width: 420, height: 420)
                .offset(x: 280, y: -220)

            Circle()
                .fill(Color.orange.opacity(0.08))
                .frame(width: 360, height: 360)
                .offset(x: -260, y: 220)
        }
        .ignoresSafeArea()
    }

    var panelBackground: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(Color(.windowBackgroundColor).opacity(0.6))
    }

}
