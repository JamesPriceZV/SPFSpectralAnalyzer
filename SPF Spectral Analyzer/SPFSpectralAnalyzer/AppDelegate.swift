#if os(macOS)
import AppKit
import Security
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let entitlementsSnapshotLoggedKey = "EntitlementsSnapshotLogged"

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        let apsEnvironment = apsEnvironmentValue()
        Instrumentation.log(
            "Provisioning context",
            area: .uiInteraction,
            level: .info,
            details: "bundleId=\(bundleId) aps=\(apsEnvironment)"
        )
        logEntitlementsSnapshotIfNeeded(bundleId: bundleId)
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
            let errorText = error?.localizedDescription ?? "none"
            Task { @MainActor in
                Instrumentation.log(
                    "Notification authorization",
                    area: .uiInteraction,
                    level: granted ? .info : .warning,
                    details: "granted=\(granted) error=\(errorText)"
                )
            }
        }
        NSApplication.shared.registerForRemoteNotifications()
        CloudKitSyncMonitor.shared.configure()

        // Open the main window at maximum (zoomed) size by default.
        DispatchQueue.main.async {
            if let window = NSApplication.shared.windows.first(where: { $0.isVisible }) {
                window.zoom(nil)
            }
        }
    }

    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Instrumentation.log(
            "Remote notifications registered",
            area: .uiInteraction,
            level: .info,
            details: "tokenBytes=\(deviceToken.count)"
        )
        CloudKitSyncMonitor.shared.startPollingIfNeeded()
    }

    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Instrumentation.log(
            "Remote notifications registration failed",
            area: .uiInteraction,
            level: .warning,
            details: "error=\(error.localizedDescription)"
        )
        CloudKitSyncMonitor.shared.startPollingIfNeeded()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        CloudKitSyncMonitor.shared.handleRemoteNotification(userInfo)
    }

    func applicationWillTerminate(_ notification: Notification) {
        print("[App] applicationWillTerminate")
    }

    private func apsEnvironmentValue() -> String {
        entitlementStringValue("com.apple.developer.aps-environment") ?? "unknown"
    }

    private func logEntitlementsSnapshotIfNeeded(bundleId: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: entitlementsSnapshotLoggedKey) else { return }

        let aps = apsEnvironmentValue()
        let iCloudContainers = entitlementArrayValue("com.apple.developer.icloud-container-identifiers")
        let iCloudServices = entitlementArrayValue("com.apple.developer.icloud-services")
        let iCloudEnvironment = entitlementStringValue("com.apple.developer.icloud-container-environment") ?? "unknown"

        let details = "bundleId=\(bundleId) aps=\(aps) icloudContainers=\(iCloudContainers.joined(separator: ",")) icloudServices=\(iCloudServices.joined(separator: ",")) icloudEnv=\(iCloudEnvironment)"
        Instrumentation.log(
            "Entitlements snapshot",
            area: .uiInteraction,
            level: .info,
            details: details
        )
        defaults.set(true, forKey: entitlementsSnapshotLoggedKey)
    }

    private func entitlementStringValue(_ key: String) -> String? {
        guard let task = SecTaskCreateFromSelf(nil) else { return nil }
        return SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? String
    }

    private func entitlementArrayValue(_ key: String) -> [String] {
        guard let task = SecTaskCreateFromSelf(nil) else { return [] }
        if let values = SecTaskCopyValueForEntitlement(task, key as CFString, nil) as? [String] {
            return values
        }
        return []
    }

}
#endif
