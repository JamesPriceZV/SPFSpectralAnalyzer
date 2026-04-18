#if os(iOS)
import UIKit
import UserNotifications
#if canImport(MSAL)
@preconcurrency import MSAL
#endif

final class iOSAppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let bundleId = Bundle.main.bundleIdentifier ?? "unknown"
        Instrumentation.log(
            "Provisioning context",
            area: .uiInteraction,
            level: .info,
            details: "bundleId=\(bundleId) platform=iOS"
        )
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
        application.registerForRemoteNotifications()
        CloudKitSyncMonitor.shared.configure()
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Instrumentation.log(
            "Remote notifications registered",
            area: .uiInteraction,
            level: .info,
            details: "tokenBytes=\(deviceToken.count)"
        )
        CloudKitSyncMonitor.shared.startPollingIfNeeded()
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Instrumentation.log(
            "Remote notifications registration failed",
            area: .uiInteraction,
            level: .warning,
            details: "error=\(error.localizedDescription)"
        )
        CloudKitSyncMonitor.shared.startPollingIfNeeded()
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any]
    ) async -> UIBackgroundFetchResult {
        CloudKitSyncMonitor.shared.handleRemoteNotification(userInfo as? [String: Any] ?? [:])
        return .newData
    }

    // MARK: - MSAL URL Handling

    // Note: On iOS 26+, URL handling is primarily through .onOpenURL in SwiftUI
    // scenes (ContentView+ChangeHandlers). This app delegate fallback is retained
    // for MSAL compatibility with older iOS flows. The SwiftUI handler is the
    // primary mechanism for MSAL redirect interception.
}
#endif
