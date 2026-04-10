import Foundation
import UserNotifications

// MARK: - Teams Sync Monitor

/// Polls Microsoft Graph for new Teams content at regular intervals.
/// Posts local notifications when new messages are detected.
/// Modeled after the `CloudKitSyncMonitor` polling pattern.
@MainActor @Observable
final class TeamsSyncMonitor {
    static let shared = TeamsSyncMonitor()

    // MARK: - Observable State

    private(set) var isSyncing = false
    private(set) var lastSyncResult: TeamsSyncResult?
    private(set) var lastError: String?

    // MARK: - Configuration

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: M365Config.TeamsSyncKeys.syncEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: M365Config.TeamsSyncKeys.syncEnabled) }
    }

    var pollingIntervalMinutes: Double {
        get {
            let value = UserDefaults.standard.double(forKey: M365Config.TeamsSyncKeys.pollingIntervalMinutes)
            return value > 0 ? value : 5.0
        }
        set { UserDefaults.standard.set(newValue, forKey: M365Config.TeamsSyncKeys.pollingIntervalMinutes) }
    }

    var notificationsEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: M365Config.TeamsSyncKeys.notificationsEnabled) }
        set { UserDefaults.standard.set(newValue, forKey: M365Config.TeamsSyncKeys.notificationsEnabled) }
    }

    var lastSyncDate: Date? {
        let ts = UserDefaults.standard.double(forKey: M365Config.TeamsSyncKeys.lastSyncTimestamp)
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }

    // MARK: - Private

    private var pollingTask: Task<Void, Never>?
    private weak var authManager: MSALAuthManager?

    private init() {}

    // MARK: - Lifecycle

    /// Start polling if sync is enabled and user is signed in.
    func start(authManager: MSALAuthManager) {
        self.authManager = authManager
        guard isEnabled, authManager.isSignedIn else {
            stop()
            return
        }

        // Cancel any existing polling
        pollingTask?.cancel()

        pollingTask = Task { [weak self] in
            // Initial sync immediately
            await self?.performSyncCheck()

            // Then poll at the configured interval
            let interval = (self?.pollingIntervalMinutes ?? 5.0) * 60.0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                guard !Task.isCancelled else { break }
                await self?.performSyncCheck()
            }
        }

        Instrumentation.log(
            "Teams sync monitor started",
            area: .aiAnalysis, level: .info,
            details: "interval=\(pollingIntervalMinutes)min"
        )
    }

    /// Stop polling.
    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Manually trigger a sync (e.g., from Sync Now button).
    func syncNow() async {
        await performSyncCheck()
    }

    // MARK: - Sync Check

    private func performSyncCheck() async {
        guard !isSyncing, let authManager, authManager.isSignedIn else { return }

        isSyncing = true
        lastError = nil
        defer { isSyncing = false }

        do {
            let result = try await TeamsSyncService.performFullSync(authManager: authManager)
            lastSyncResult = result
            postNotificationIfNeeded(result: result)
        } catch {
            lastError = error.localizedDescription
            Instrumentation.log(
                "Teams sync failed",
                area: .aiAnalysis, level: .error,
                details: "error=\(error.localizedDescription)"
            )
        }
    }

    // MARK: - Notifications

    private func postNotificationIfNeeded(result: TeamsSyncResult) {
        guard notificationsEnabled, result.newMessageCount > 0 else { return }

        let content = UNMutableNotificationContent()
        content.title = "Microsoft Teams"
        let msgWord = result.newMessageCount == 1 ? "message" : "messages"
        if result.newFileCount > 0 {
            let fileWord = result.newFileCount == 1 ? "file" : "files"
            content.body = "\(result.newMessageCount) new \(msgWord) and \(result.newFileCount) new \(fileWord)"
        } else {
            content.body = "\(result.newMessageCount) new \(msgWord)"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "teams-sync-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
