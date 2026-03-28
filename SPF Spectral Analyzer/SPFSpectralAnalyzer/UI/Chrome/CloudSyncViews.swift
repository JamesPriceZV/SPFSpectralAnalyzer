import SwiftUI

extension ContentView {

    var iCloudStatusText: String {
        var lines: [String] = []
        let storageLabel = isLocalStore ? "Local storage" : "iCloud storage"
        lines.append("Storage: \(storageLabel)")

        if dataStoreController.syncState.isActive {
            lines.append("Sync: \(dataStoreController.syncState.message)")
            if dataStoreController.syncState.totalBytes > 0 {
                let percent = Int((dataStoreController.syncState.progress * 100).rounded())
                let transferred = ByteCountFormatter.string(
                    fromByteCount: dataStoreController.syncState.transferredBytes,
                    countStyle: .file
                )
                let total = ByteCountFormatter.string(
                    fromByteCount: dataStoreController.syncState.totalBytes,
                    countStyle: .file
                )
                lines.append("Progress: \(percent)% (\(transferred) / \(total))")
            } else {
                let percent = Int((dataStoreController.syncState.progress * 100).rounded())
                lines.append("Progress: \(percent)%")
            }
        } else if !dataStoreController.cloudSyncEnabled {
            lines.append("Sync: Off")
        } else if dataStoreController.cloudKitUnavailable {
            lines.append("CloudKit available: no")
        } else {
            lines.append("CloudKit available: yes")
            lines.append("Sync: \(icloudLastSyncStatus)")
        }

        if storeResetOccurred {
            lines.append("Notice: Storage was reset. See Settings for details.")
        }

        return lines.joined(separator: "\n")
    }

    var iCloudCondensedErrorText: String? {
        let message = dataStoreController.cloudKitUnavailableMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return nil }
        return message.components(separatedBy: .newlines).first
    }

    var shouldShowSyncStatusBar: Bool {
        dataStoreController.syncState.isActive
            || !dataStoreController.syncHistory.isEmpty
            || dataStoreController.queuedActionMessage != nil
            || dataStoreController.cloudSyncEnabled
            || icloudLastSyncTimestamp > 0
    }

    var syncStatusMessage: String {
        if let latest = dataStoreController.syncHistory.first {
            return latest.message
        }
        return dataStoreController.syncState.message
    }

    var syncEnabledLabel: String {
        dataStoreController.cloudSyncEnabled ? "On" : "Off"
    }

    var cloudKitAccountSummary: String {
        let defaults = UserDefaults.standard
        let account = defaults.string(forKey: ICloudDefaultsKeys.cloudKitAccountStatus) ?? "unknown"
        let containerID = defaults.string(forKey: ICloudDefaultsKeys.cloudKitContainerIdentifier) ?? "unknown"
        let env = defaults.string(forKey: ICloudDefaultsKeys.cloudKitEnvironmentLabel) ?? "unknown"
        return "Account: \(account) • Env: \(env) • Container: \(containerID)"
    }

    var lastSyncTimestampText: String {
        guard icloudLastSyncTimestamp > 0 else { return "Never" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: Date(timeIntervalSince1970: icloudLastSyncTimestamp))
    }

    var lastSyncStatusLabel: String {
        icloudSyncInProgress ? "In progress" : icloudLastSyncStatus
    }

    var lastSyncTriggerLabel: String {
        let trimmed = icloudLastSyncTrigger.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    /// Compact single-line sync status that stays out of the way.
    /// Clicking expands to the full sync status bar with controls.
    var compactSyncStatusBar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    syncPanelExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    if dataStoreController.cloudKitUnavailable {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("CloudKit unavailable")
                            .font(.caption)
                            .foregroundColor(.orange)
                    } else if dataStoreController.syncState.isActive {
                        ProgressView()
                            .controlSize(.mini)
                        Text(dataStoreController.syncState.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if dataStoreController.cloudSyncEnabled && isLocalStore {
                        Image(systemName: "externaldrive")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Text("Local storage (migration pending)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if dataStoreController.cloudSyncEnabled {
                        Image(systemName: "icloud")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("iCloud: \(lastSyncStatusLabel)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("Sync disabled")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: syncPanelExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(syncPanelExpanded ? "Collapse sync panel" : "Expand sync panel")

            if syncPanelExpanded {
                Divider()
                    .padding(.horizontal, 8)
                syncStatusBarExpanded
            }
        }
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.06))
        )
    }

    /// Full expanded sync panel with details and controls.
    private var syncStatusBarExpanded: some View {
        VStack(alignment: .leading, spacing: 6) {
            if dataStoreController.cloudKitUnavailable {
                HStack(spacing: 12) {
                    Text(dataStoreController.cloudKitUnavailableMessage.isEmpty
                         ? "CloudKit is unavailable. The app is using local storage."
                         : dataStoreController.cloudKitUnavailableMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Enable iCloud Sync") {
                        dataStoreController.setCloudSyncEnabled(true)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(dataStoreController.cloudSyncEnabled && !dataStoreController.cloudKitUnavailable)
                    #if os(macOS)
                    SettingsLink {
                        Text("Settings")
                    }
                    .buttonStyle(.link)
                    #endif
                }
            } else if dataStoreController.cloudSyncEnabled && isLocalStore {
                Text("iCloud sync is enabled but this session is using local storage. Migration will start automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if dataStoreController.syncState.isActive {
                CloudSyncProgressView(state: dataStoreController.syncState)
                    .frame(minHeight: 48)
            }

            if shouldShowSyncStatusBar {
                Text("Enabled: \(syncEnabledLabel) • Last: \(lastSyncStatusLabel) • \(lastSyncTimestampText) • Trigger: \(lastSyncTriggerLabel)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(cloudKitAccountSummary)
                    .font(.caption2)
                    .foregroundColor(.secondary)

                if let queuedMessage = dataStoreController.queuedActionMessage {
                    Text(queuedMessage)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Sync Now") {
                        datasets.requestCloudSync(reason: "manual")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                    Button("Force Upload") {
                        datasets.requestForceUpload(reason: "manual")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                    Spacer()

                    Button("Copy Status") {
                        copyICloudStatusDetails()
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .controlSize(.small)
                }
            }
        }
        .padding(10)
    }

    var syncStatusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("iCloud Sync")
                    .font(.caption)
                    .foregroundColor(.secondary)

                progressToggleButton()

                Spacer()
                if dataStoreController.queuedActionMessage != nil {
                    Text("Queued")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.trailing, 6)
                } else {
                    Text(syncStatusMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .padding(.trailing, 6)
                }
            }
            Text("Enabled: \(syncEnabledLabel) • Last: \(lastSyncStatusLabel) • \(lastSyncTimestampText) • Trigger: \(lastSyncTriggerLabel)")
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(cloudKitAccountSummary)
                .font(.caption2)
                .foregroundColor(.secondary)

            let queuedMessage = dataStoreController.queuedActionMessage ?? " "
            Text(queuedMessage)
                .font(.caption2)
                .foregroundColor(.secondary)
                .opacity(dataStoreController.queuedActionMessage == nil ? 0 : 1)

            HStack {
                Button("Sync Now") {
                    datasets.requestCloudSync(reason: "manual")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                Button("Force Upload") {
                    datasets.requestForceUpload(reason: "manual")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(!dataStoreController.cloudSyncEnabled || icloudSyncInProgress)

                Spacer()
            }

            if !icloudProgressCollapsed {
                CloudSyncProgressView(state: dataStoreController.syncState)
                    .frame(minHeight: 96)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    @ViewBuilder
    func progressToggleButton() -> some View {
        let label = Image(systemName: icloudProgressCollapsed ? "chevron.down" : "chevron.up")
            .font(.caption)
        let button = Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                icloudProgressCollapsed.toggle()
            }
        } label: {
            label
        }
        .accessibilityLabel(icloudProgressCollapsed ? "Show progress" : "Hide progress")
        .controlSize(.small)

        if #available(macOS 15.0, *) {
            button.buttonStyle(.glass(.clear))
        } else {
            button.buttonStyle(.bordered)
        }
    }

    func copyICloudStatusDetails() {
        var lines: [String] = []
        let defaults = UserDefaults.standard
        lines.append("Storage: \(isLocalStore ? "Local" : "iCloud")")
        lines.append("CloudKit enabled: \(dataStoreController.cloudSyncEnabled ? "yes" : "no")")
        lines.append("CloudKit unavailable: \(dataStoreController.cloudKitUnavailable ? "yes" : "no")")
        if let account = defaults.string(forKey: ICloudDefaultsKeys.cloudKitAccountStatus), !account.isEmpty {
            lines.append("CloudKit account: \(account)")
        }
        if let containerID = defaults.string(forKey: ICloudDefaultsKeys.cloudKitContainerIdentifier), !containerID.isEmpty {
            lines.append("CloudKit container: \(containerID)")
        }
        if let env = defaults.string(forKey: ICloudDefaultsKeys.cloudKitEnvironmentLabel), !env.isEmpty {
            lines.append("CloudKit environment: \(env)")
        }
        if !dataStoreController.cloudKitUnavailableMessage.isEmpty {
            lines.append("Unavailable message: \(dataStoreController.cloudKitUnavailableMessage)")
        }
        if !dataStoreController.syncState.isActive,
           defaults.double(forKey: "icloudLastSyncEndTimestamp") > 0,
           defaults.bool(forKey: "icloudLastSyncChangesDetected") == false {
            lines.append("Sync: No changes to sync")
        } else {
            lines.append("Sync status: \(iCloudStatusText)")
        }
        if dataStoreController.syncState.isActive {
            let percent = Int((dataStoreController.syncState.progress * 100).rounded())
            let transferred = ByteCountFormatter.string(fromByteCount: dataStoreController.syncState.transferredBytes, countStyle: .file)
            let total = ByteCountFormatter.string(fromByteCount: dataStoreController.syncState.totalBytes, countStyle: .file)
            lines.append("Sync progress: \(percent)% (\(transferred) / \(total))")
            if !dataStoreController.syncState.detail.isEmpty {
                lines.append("Sync detail: \(dataStoreController.syncState.detail)")
            }
        }
        if !dataStoreController.syncHistory.isEmpty {
            let formatter = DatasetViewModel.storedDateFormatter
            lines.append("Sync history (latest 5):")
            for entry in dataStoreController.syncHistory.prefix(5) {
                let stamp = formatter.string(from: entry.timestamp)
                let detail = entry.detail.isEmpty ? "" : " • \(entry.detail)"
                lines.append("History: \(stamp) • \(entry.message)\(detail)")
            }
        }
        PlatformPasteboard.copyString(lines.joined(separator: "\n"))
    }

    var cloudKitBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: "icloud.slash")
                    .font(.title3)
                    .foregroundColor(.orange)
                Text(dataStoreController.cloudKitUnavailableMessage.isEmpty
                     ? "CloudKit is unavailable. The app is using local storage until it becomes available."
                     : dataStoreController.cloudKitUnavailableMessage
                )
                .font(.caption)
                .foregroundColor(.secondary)
                Spacer()
                Button("Enable iCloud Sync") {
                    dataStoreController.setCloudSyncEnabled(true)
                }
                .buttonStyle(.bordered)
                .disabled(dataStoreController.cloudSyncEnabled && !dataStoreController.cloudKitUnavailable)
                .accessibilityIdentifier("retryCloudKitBannerButton")
                #if os(macOS)
                SettingsLink {
                    Text("Settings")
                }
                .buttonStyle(.link)
                #endif
            }

            if dataStoreController.syncState.isActive {
                VStack(alignment: .leading, spacing: 6) {
                    Text(dataStoreController.syncState.message)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    CloudSyncProgressView(state: dataStoreController.syncState)
                }
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    func cloudKitProgressBanner(state: CloudSyncState) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "icloud.and.arrow.up")
                .font(.title3)
                .foregroundColor(.accentColor)
            VStack(alignment: .leading, spacing: 6) {
                Text(state.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                CloudSyncProgressView(state: state)
            }
            Spacer()
            #if os(macOS)
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.link)
            #endif
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

    var localStoreBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .font(.title3)
                .foregroundColor(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("Local storage in use")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("iCloud sync is enabled, but this session is still using local storage. Migration will start automatically.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            #if os(macOS)
            SettingsLink {
                Text("Settings")
            }
            .buttonStyle(.link)
            #endif
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.08))
        )
    }

}
