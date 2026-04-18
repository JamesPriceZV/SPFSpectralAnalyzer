import Foundation

#if canImport(AppKit)
import AppKit

/// Cross-platform presentation anchor for MSAL interactive sign-in on macOS.
public typealias PlatformViewController = NSViewController

enum PresentationAnchorProvider {
    @MainActor
    static func currentViewController() -> NSViewController? {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return nil }
        return window.contentViewController
    }

    @MainActor
    static func currentWindow() -> NSWindow? {
        NSApp.keyWindow ?? NSApp.mainWindow
    }
}

#elseif canImport(UIKit)
import UIKit

/// Cross-platform presentation anchor for MSAL interactive sign-in on iOS.
public typealias PlatformViewController = UIViewController

enum PresentationAnchorProvider {
    @MainActor
    static func currentViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else {
            return nil
        }
        return topViewController(root)
    }

    private static func topViewController(_ root: UIViewController) -> UIViewController {
        if let nav = root as? UINavigationController, let visible = nav.visibleViewController {
            return topViewController(visible)
        }
        if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
            return topViewController(selected)
        }
        if let presented = root.presentedViewController {
            return topViewController(presented)
        }
        return root
    }
}

#endif
