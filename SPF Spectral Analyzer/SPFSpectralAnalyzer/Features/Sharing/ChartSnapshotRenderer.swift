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
    @MainActor
    static func renderChartToPNG<V: View>(_ chartView: V, size: CGSize = CGSize(width: 800, height: 500)) -> Data? {
        #if os(macOS)
        guard let image = renderChart(chartView, size: size),
              let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
        #else
        guard let image = renderChart(chartView, size: size) else { return nil }
        return image.pngData()
        #endif
    }
}
