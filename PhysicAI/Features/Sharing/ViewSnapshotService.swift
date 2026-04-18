import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Captures SwiftUI views as images for sharing.
///
/// Follows the `ChartSnapshotRenderer` pattern, using `ImageRenderer` to
/// produce platform-native images from arbitrary SwiftUI content.
enum ViewSnapshotService {

    /// Renders a SwiftUI view to a platform image at the specified size.
    @MainActor
    static func snapshot<V: View>(_ view: V, size: CGSize = CGSize(width: 1200, height: 800)) -> PlatformImage? {
        let renderer = ImageRenderer(content:
            view
                .frame(width: size.width, height: size.height)
                .background(Color.white)
        )
        renderer.scale = 2.0

        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }

    /// Renders a SwiftUI view to PNG data for sharing.
    @MainActor
    static func snapshotToPNG<V: View>(_ view: V, size: CGSize = CGSize(width: 1200, height: 800)) -> Data? {
        #if os(macOS)
        guard let image = snapshot(view, size: size),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        guard let image = snapshot(view, size: size) else { return nil }
        return image.pngData()
        #endif
    }
}
