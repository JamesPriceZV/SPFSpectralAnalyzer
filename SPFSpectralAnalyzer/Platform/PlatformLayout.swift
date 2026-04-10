import SwiftUI

/// Cross-platform replacement for HSplitView.
/// On macOS: uses HSplitView with resizable panes.
/// On iOS: uses HStack (iPad) or VStack (iPhone) for appropriate layout.
struct PlatformHSplit<Content: View>: View {
    @ViewBuilder let content: () -> Content

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    var body: some View {
        #if os(macOS)
        HSplitView {
            content()
        }
        #else
        if horizontalSizeClass == .compact {
            VStack(spacing: 0) {
                content()
            }
        } else {
            HStack(spacing: 0) {
                content()
            }
        }
        #endif
    }
}

/// Convenience function matching the HSplitView { } call-site pattern.
func platformHSplit<Content: View>(@ViewBuilder content: @escaping () -> Content) -> some View {
    PlatformHSplit(content: content)
}
