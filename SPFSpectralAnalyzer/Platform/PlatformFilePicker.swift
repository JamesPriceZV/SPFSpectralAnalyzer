import SwiftUI
import UniformTypeIdentifiers

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// Cross-platform file save abstraction.
/// On macOS: presents NSSavePanel.
/// On iOS: writes to temp directory and presents a share sheet / document picker.
@MainActor
enum PlatformFileSaver {

    /// Presents a save panel (macOS) or share sheet (iOS) for the given data.
    /// Returns the URL where the file was saved, or nil if cancelled.
    static func save(
        defaultName: String,
        allowedTypes: [UTType],
        data: Data,
        directoryKey: String? = nil
    ) async -> URL? {
        #if canImport(AppKit)
        return saveWithPanel(
            defaultName: defaultName,
            allowedTypes: allowedTypes,
            data: data,
            directoryKey: directoryKey
        )
        #elseif canImport(UIKit)
        return await saveWithShareSheet(
            defaultName: defaultName,
            data: data
        )
        #endif
    }

    /// Presents a save panel (macOS) or share sheet (iOS) for a file at the given URL.
    /// Returns the final destination URL, or nil if cancelled.
    static func saveFile(
        at sourceURL: URL,
        defaultName: String,
        allowedTypes: [UTType],
        directoryKey: String? = nil
    ) async -> URL? {
        #if canImport(AppKit)
        return saveFileWithPanel(
            at: sourceURL,
            defaultName: defaultName,
            allowedTypes: allowedTypes,
            directoryKey: directoryKey
        )
        #elseif canImport(UIKit)
        return await shareFile(at: sourceURL)
        #endif
    }

    /// Returns the current user's full name (for report metadata).
    static var currentUserFullName: String {
        #if canImport(AppKit)
        return NSFullUserName()
        #elseif canImport(UIKit)
        return UIDevice.current.name
        #endif
    }

    // MARK: - macOS Implementation

    #if canImport(AppKit)
    private static func saveWithPanel(
        defaultName: String,
        allowedTypes: [UTType],
        data: Data,
        directoryKey: String?
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let directoryKey,
           let path = UserDefaults.standard.string(forKey: directoryKey) {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            try data.write(to: url)
            if let directoryKey {
                UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: directoryKey)
            }
            return url
        } catch {
            return nil
        }
    }

    private static func saveFileWithPanel(
        at sourceURL: URL,
        defaultName: String,
        allowedTypes: [UTType],
        directoryKey: String?
    ) -> URL? {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = defaultName
        panel.allowedContentTypes = allowedTypes
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        if let directoryKey,
           let path = UserDefaults.standard.string(forKey: directoryKey) {
            panel.directoryURL = URL(fileURLWithPath: path)
        }
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.copyItem(at: sourceURL, to: url)
            if let directoryKey {
                UserDefaults.standard.set(url.deletingLastPathComponent().path, forKey: directoryKey)
            }
            return url
        } catch {
            return nil
        }
    }
    #endif

    // MARK: - iOS Implementation

    #if canImport(UIKit)

    /// Wraps `UIDocumentPickerViewController` for SwiftUI presentation with
    /// full control over sheet sizing (unlike `.fileImporter`).
    struct DocumentPickerView: UIViewControllerRepresentable {
        let contentTypes: [UTType]
        let allowsMultipleSelection: Bool
        let onCompletion: (Result<[URL], any Error>) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }

        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let picker = UIDocumentPickerViewController(forOpeningContentTypes: contentTypes)
            picker.allowsMultipleSelection = allowsMultipleSelection
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

        final class Coordinator: NSObject, UIDocumentPickerDelegate {
            let onCompletion: (Result<[URL], any Error>) -> Void

            init(onCompletion: @escaping (Result<[URL], any Error>) -> Void) {
                self.onCompletion = onCompletion
            }

            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                onCompletion(.success(urls))
            }

            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                onCompletion(.failure(CancellationError()))
            }
        }
    }

    private static func saveWithShareSheet(
        defaultName: String,
        data: Data
    ) async -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(defaultName)
        do {
            try data.write(to: tempURL)
        } catch {
            return nil
        }
        return await shareFile(at: tempURL)
    }

    private static func shareFile(at url: URL) async -> URL? {
        guard let windowScene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first,
              let rootVC = windowScene.windows.first?.rootViewController else {
            return nil
        }
        return await withCheckedContinuation { continuation in
            let activityVC = UIActivityViewController(
                activityItems: [url],
                applicationActivities: nil
            )
            activityVC.completionWithItemsHandler = { _, completed, _, _ in
                continuation.resume(returning: completed ? url : nil)
            }
            if let popover = activityVC.popoverPresentationController {
                popover.sourceView = rootVC.view
                popover.sourceRect = CGRect(x: rootVC.view.bounds.midX, y: rootVC.view.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
            rootVC.present(activityVC, animated: true)
        }
    }
    #endif
}
