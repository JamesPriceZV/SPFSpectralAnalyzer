import SwiftUI
import Charts
#if canImport(AppKit)
import AppKit
#endif

/// Renders a chart view as an image for sharing purposes.
enum ChartSnapshotRenderer {

    /// Renders a SwiftUI view to a platform image at the specified size.
    /// Uses `ImageRenderer` which is available on macOS 13+ and iOS 16+.
    @MainActor
    static func renderChart<V: View>(_ chartView: V, size: CGSize = CGSize(width: 800, height: 500)) -> PlatformImage? {
        let renderer = ImageRenderer(content:
            chartView
                .frame(width: size.width, height: size.height)
                .padding()
                .background(Color.white)
        )

        renderer.scale = 2.0 // Retina quality

        #if os(macOS)
        return renderer.nsImage
        #else
        return renderer.uiImage
        #endif
    }

    /// Renders a chart to PNG data for sharing.
    /// Image capture runs on MainActor; PNG encoding runs on a background thread.
    @MainActor
    static func renderChartToPNG<V: View>(_ chartView: V, size: CGSize = CGSize(width: 800, height: 500)) async -> Data? {
        // Step 1: Capture image on MainActor (ImageRenderer requires it)
        guard let image = renderChart(chartView, size: size) else { return nil }

        // Step 2: Encode to PNG off the main thread
        return await Task.detached(priority: .userInitiated) {
            #if os(macOS)
            guard let tiffData = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData) else { return nil as Data? }
            return bitmap.representation(using: .png, properties: [:])
            #else
            return image.pngData()
            #endif
        }.value
    }
}
