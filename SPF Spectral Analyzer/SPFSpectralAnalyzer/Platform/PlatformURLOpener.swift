import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform URL opener.
/// Replaces NSWorkspace.shared.open / UIApplication.shared.open.
@MainActor
enum PlatformURLOpener {
    /// Opens the given URL using the platform's default handler.
    static func open(_ url: URL) {
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #elseif canImport(UIKit)
        UIApplication.shared.open(url)
        #endif
    }

    /// Opens the given URL in the default web browser.
    static func openInBrowser(_ url: URL) {
        open(url)
    }
}
