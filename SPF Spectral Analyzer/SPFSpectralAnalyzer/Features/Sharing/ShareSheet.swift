import SwiftUI

/// Cross-platform share sheet that wraps UIActivityViewController (iOS) and
/// NSSharingServicePicker (macOS).

#if os(iOS)
/// iOS share sheet using UIActivityViewController.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    let excludedActivityTypes: [UIActivity.ActivityType]?

    init(items: [Any], excludedActivityTypes: [UIActivity.ActivityType]? = nil) {
        self.items = items
        self.excludedActivityTypes = excludedActivityTypes
    }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.excludedActivityTypes = excludedActivityTypes
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#if os(macOS)
import AppKit

/// macOS share sheet using NSSharingServicePicker presented as a popover.
struct ShareSheet: NSViewRepresentable {
    let items: [Any]

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Delay to allow the view to be placed in the hierarchy
        DispatchQueue.main.async {
            let picker = NSSharingServicePicker(items: items)
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
#endif

/// A share button that presents the platform share sheet.
struct ShareButton: View {
    let items: [Any]
    let label: String
    let systemImage: String

    @State private var showShareSheet = false

    init(items: [Any], label: String = "Share", systemImage: String = "square.and.arrow.up") {
        self.items = items
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View {
        Button {
            showShareSheet = true
        } label: {
            Label(label, systemImage: systemImage)
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(items: items)
        }
        #else
        .popover(isPresented: $showShareSheet) {
            ShareSheet(items: items)
                .frame(width: 1, height: 1) // NSSharingServicePicker manages its own UI
        }
        #endif
    }
}
