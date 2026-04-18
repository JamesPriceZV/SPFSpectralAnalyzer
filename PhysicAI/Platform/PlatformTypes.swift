import SwiftUI

#if canImport(AppKit)
import AppKit
public typealias PlatformColor = NSColor
public typealias PlatformFont = NSFont
public typealias PlatformImage = NSImage
public typealias PlatformApplication = NSApplication
#elseif canImport(UIKit)
import UIKit
public typealias PlatformColor = UIColor
public typealias PlatformFont = UIFont
public typealias PlatformImage = UIImage
public typealias PlatformApplication = UIApplication
#endif

// MARK: - Platform Notification Names

/// Cross-platform equivalent of NSApplication.didBecomeActiveNotification / UIApplication.didBecomeActiveNotification.
var platformDidBecomeActiveNotification: Notification.Name {
    #if canImport(AppKit)
    NSApplication.didBecomeActiveNotification
    #elseif canImport(UIKit)
    UIApplication.didBecomeActiveNotification
    #endif
}

/// Cross-platform equivalent of NSApplication.willTerminateNotification / UIApplication.willTerminateNotification.
var platformWillTerminateNotification: Notification.Name {
    #if canImport(AppKit)
    NSApplication.willTerminateNotification
    #elseif canImport(UIKit)
    UIApplication.willTerminateNotification
    #endif
}
