import SwiftUI
import CloudKit

struct CloudSyncProgressView: View {
    let state: CloudSyncState

    @AppStorage("icloudLastPushTimestamp") private var lastPushTimestamp = 0.0
    @AppStorage("icloudLastPollTimestamp") private var lastPollTimestamp = 0.0
    @AppStorage("icloudLastSyncEndTimestamp") private var lastSyncEndTimestamp = 0.0
    @AppStorage("icloudLastSyncChangesDetected") private var lastSyncChangesDetected = false
    @AppStorage("icloudLastSyncErrorDomain") private var lastSyncErrorDomain = ""
    @AppStorage("icloudLastSyncErrorCode") private var lastSyncErrorCode = 0
    @State private var lastSampleTime: Date?
    @State private var lastSampleBytes: Int64 = 0
    @State private var emaBytesPerSecond: Double = 0

    private var percentText: String {
        let value = Int((state.progress * 100).rounded())
        return "\(value)%"
    }

    private var byteText: String {
        let total = state.totalBytes
        let transferred = state.transferredBytes
        guard total > 0 else { return "Calculating…" }
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        let transferredText = formatter.string(fromByteCount: transferred)
        let totalText = formatter.string(fromByteCount: total)
        let remaining = max(total - transferred, 0)
        let remainingText = formatter.string(fromByteCount: remaining)
        return "\(transferredText) / \(totalText) • \(remainingText) remaining"
    }

    private var timeRemainingText: String {
        let total = state.totalBytes
        let transferred = state.transferredBytes
        guard total > 0 else { return "Calculating…" }
        let remaining = max(total - transferred, 0)
        guard remaining > 0, emaBytesPerSecond > 0 else { return "Calculating…" }
        let seconds = Double(remaining) / emaBytesPerSecond
        return "~\(formatDuration(seconds)) left"
    }

    private var noChangesDetected: Bool {
        !state.isActive && lastSyncEndTimestamp > 0 && !lastSyncChangesDetected
    }

    private var phaseText: String {
        switch state.phase {
        case .idle:
            return "Idle"
        case .preparing:
            return "Preparing"
        case .migrating:
            return "Migrating"
        case .uploading:
            return "Uploading"
        case .resetting:
            return "Resetting"
        case .downloading:
            return "Downloading"
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }

    private var knowledgeLine: String {
        let message = state.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if !humanReadableError.isEmpty {
            return "Sync needs attention"
        }
        if !state.isActive && noChangesDetected {
            return "iCloud is up to date"
        }
        if state.phase == .uploading || state.phase == .migrating {
            return "Uploading your changes to iCloud…"
        }
        if state.phase == .downloading {
            return "Downloading updates from iCloud…"
        }
        if state.phase == .preparing {
            return "Preparing iCloud sync…"
        }
        if state.phase == .failed {
            return "Sync failed"
        }
        if state.phase == .completed {
            return "iCloud is up to date"
        }
        if message.isEmpty {
            return "iCloud is idle"
        }
        return message
    }

    private var humanReadableError: String {
        guard !lastSyncErrorDomain.isEmpty, lastSyncErrorCode != 0 else { return "" }
        if lastSyncErrorDomain == "NSCocoaErrorDomain", lastSyncErrorCode == 134407 {
            return "Error: Sync canceled (store was reset or removed)"
        }
        if lastSyncErrorDomain == "NSCocoaErrorDomain", lastSyncErrorCode == 134060 {
            return "Error: Store is corrupt or incompatible"
        }
        if lastSyncErrorDomain == "NSCocoaErrorDomain", lastSyncErrorCode == 134050 {
            return "Error: Migration required"
        }
        if lastSyncErrorDomain == "NSCocoaErrorDomain", lastSyncErrorCode == 134100 {
            return "Error: Model mismatch (schema changed)"
        }

        if lastSyncErrorDomain == CKErrorDomain, let code = CKError.Code(rawValue: lastSyncErrorCode) {
            switch code {
            case .accountTemporarilyUnavailable:
                return "Error: iCloud account temporarily unavailable"
            case .alreadyShared:
                return "Error: Record already shared"
            case .assetFileModified:
                return "Error: Asset modified during save"
            case .assetFileNotFound:
                return "Error: Asset file not found"
            case .assetNotAvailable:
                return "Error: Asset not available"
            case .badContainer:
                return "Error: Unknown or unauthorized container"
            case .badDatabase:
                return "Error: Invalid database"
            case .batchRequestFailed:
                return "Error: Batch request failed"
            case .changeTokenExpired:
                return "Error: Change token expired"
            case .constraintViolation:
                return "Error: Unique constraint violation"
            case .incompatibleVersion:
                return "Error: App version not supported"
            case .internalError:
                return "Error: Internal CloudKit error"
            case .invalidArguments:
                return "Error: Invalid request arguments"
            case .limitExceeded:
                return "Error: Request size limit exceeded"
            case .managedAccountRestricted:
                return "Error: Managed account restriction"
            case .missingEntitlement:
                return "Error: Missing CloudKit entitlement"
            case .networkFailure:
                return "Error: Network available, CloudKit unreachable"
            case .networkUnavailable:
                return "Error: Network unavailable"
            case .notAuthenticated:
                return "Error: Not authenticated to iCloud"
            case .operationCancelled:
                return "Error: Operation canceled"
            case .partialFailure:
                return "Error: Partial failure (some items failed)"
            case .participantMayNeedVerification:
                return "Error: Participant needs verification"
            case .permissionFailure:
                return "Error: Permission failure"
            case .quotaExceeded:
                return "Error: iCloud storage quota exceeded"
            case .referenceViolation:
                return "Error: Missing reference target"
            case .requestRateLimited:
                return "Error: Request rate limited"
            case .serverRecordChanged:
                return "Error: Server record changed"
            case .serverRejectedRequest:
                return "Error: Server rejected request"
            case .serverResponseLost:
                return "Error: Server response lost"
            case .serviceUnavailable:
                return "Error: CloudKit service unavailable"
            case .tooManyParticipants:
                return "Error: Too many share participants"
            case .unknownItem:
                return "Error: Record not found"
            case .userDeletedZone:
                return "Error: User deleted zone"
            case .zoneBusy:
                return "Error: Zone busy"
            case .zoneNotFound:
                return "Error: Zone not found"
            case .resultsTruncated:
                return "Error: Query results truncated"
            default:
                return "Error: CloudKit error (\(lastSyncErrorCode))"
            }
        }

        return "Error: \(lastSyncErrorDomain) (\(lastSyncErrorCode))"
    }

    private func formattedTimestamp(_ value: Double) -> String {
        guard value > 0 else { return "never" }
        let date = Date(timeIntervalSince1970: value)
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func formatDuration(_ seconds: Double) -> String {
        let clamped = max(0, Int(seconds.rounded()))
        let mins = clamped / 60
        let secs = clamped % 60
        if mins > 0 {
            return "\(mins)m \(secs)s"
        }
        return "\(secs)s"
    }

    private func updateSpeedEstimate(for newBytes: Int64) {
        let now = Date()
        if let lastTime = lastSampleTime {
            let dt = now.timeIntervalSince(lastTime)
            let delta = newBytes - lastSampleBytes
            if dt > 0.5, delta > 0 {
                let speed = Double(delta) / dt
                let alpha = 0.2
                if emaBytesPerSecond == 0 {
                    emaBytesPerSecond = speed
                } else {
                    emaBytesPerSecond = (alpha * speed) + ((1 - alpha) * emaBytesPerSecond)
                }
            }
        }
        lastSampleTime = now
        lastSampleBytes = newBytes
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(knowledgeLine)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Upload to iCloud")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(uploadStatusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ProgressView(value: uploadProgress)
                    .progressViewStyle(.linear)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Download from iCloud")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(downloadStatusText)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                ProgressView(value: downloadProgress)
                    .progressViewStyle(.linear)
            }

            if !humanReadableError.isEmpty {
                Text(humanReadableError)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
            }
        }
        .onChange(of: state.transferredBytes) { _, newValue in
            updateSpeedEstimate(for: newValue)
        }
    }

    private var uploadProgress: Double {
        switch state.phase {
        case .uploading, .migrating:
            return state.progress
        case .completed:
            return noChangesDetected ? 1.0 : state.progress
        default:
            return 0
        }
    }

    private var downloadProgress: Double {
        switch state.phase {
        case .downloading:
            return state.progress
        case .completed:
            return noChangesDetected ? 1.0 : 0
        default:
            return 0
        }
    }

    private var uploadStatusText: String {
        if state.phase == .uploading || state.phase == .migrating {
            return "\(percentText) • \(byteText) • \(timeRemainingText)"
        }
        if !state.isActive && noChangesDetected {
            return "Up to date"
        }
        return "Idle"
    }

    private var downloadStatusText: String {
        if state.phase == .downloading {
            return "\(percentText) • \(byteText) • \(timeRemainingText)"
        }
        if !state.isActive && noChangesDetected {
            return "Up to date"
        }
        return "Idle"
    }
}
