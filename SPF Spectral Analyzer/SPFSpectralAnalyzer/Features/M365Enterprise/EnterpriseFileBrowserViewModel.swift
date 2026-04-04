import Foundation

// MARK: - Enterprise File Browser View Model

/// View model for browsing OneDrive and SharePoint file systems via Microsoft Graph.
/// Supports folder navigation with breadcrumb path, file search, and source switching.
@MainActor @Observable
final class EnterpriseFileBrowserViewModel {
    // MARK: - Types

    /// Represents a segment in the navigation breadcrumb.
    struct PathEntry: Identifiable, Sendable {
        let id: String
        let name: String
    }

    /// Which drive source to browse.
    enum DriveSource: String, CaseIterable, Identifiable, Sendable {
        case oneDrive = "OneDrive"
        case sharePoint = "SharePoint"
        var id: String { rawValue }
    }

    // MARK: - State

    var items: [GraphDriveItem] = []
    var pathStack: [PathEntry] = []
    var isLoading = false
    var errorMessage: String?
    var searchQuery: String = ""
    var selectedSource: DriveSource = .oneDrive
    var sharePointSitePath: String = ""

    // MARK: - Auth

    let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Navigation

    /// Load the root folder of the selected source.
    func loadRoot() async {
        pathStack = []
        await loadCurrentFolder()
    }

    /// Navigate into a subfolder.
    func navigateInto(folder: GraphDriveItem) async {
        guard folder.isFolder else { return }
        pathStack.append(PathEntry(id: folder.id, name: folder.name))
        await loadCurrentFolder()
    }

    /// Navigate to a specific breadcrumb entry (pop back to it).
    func navigateToPathEntry(_ entry: PathEntry) async {
        if let index = pathStack.firstIndex(where: { $0.id == entry.id }) {
            pathStack = Array(pathStack.prefix(through: index))
        }
        await loadCurrentFolder()
    }

    /// Navigate up one level.
    func navigateUp() async {
        guard !pathStack.isEmpty else { return }
        pathStack.removeLast()
        await loadCurrentFolder()
    }

    /// Search files within the current drive source.
    func search() async {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await loadCurrentFolder()
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.retrievalScopes)

            switch selectedSource {
            case .oneDrive:
                items = try await GraphUploadService.searchDriveItems(
                    query: trimmed,
                    token: token
                )
            case .sharePoint:
                let sitePath = resolvedSitePath
                guard !sitePath.isEmpty else {
                    errorMessage = "Enter a SharePoint site path to search."
                    return
                }
                items = try await GraphUploadService.searchDriveItems(
                    query: trimmed,
                    sitePath: sitePath,
                    token: token
                )
            }

            if items.isEmpty {
                errorMessage = "No files found for \"\(trimmed)\"."
            }
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }

    /// Refresh the current folder listing.
    func refresh() async {
        await loadCurrentFolder()
    }

    // MARK: - Private

    private var currentFolderItemId: String? {
        pathStack.last?.id
    }

    private var resolvedSitePath: String {
        sharePointSitePath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadCurrentFolder() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.retrievalScopes)

            switch selectedSource {
            case .oneDrive:
                items = try await GraphUploadService.listOneDriveFolder(
                    folderItemId: currentFolderItemId,
                    token: token
                )
            case .sharePoint:
                let sitePath = resolvedSitePath
                guard !sitePath.isEmpty else {
                    errorMessage = "Enter a SharePoint site path to browse."
                    items = []
                    return
                }
                items = try await GraphUploadService.listSharePointFolder(
                    sitePath: sitePath,
                    folderItemId: currentFolderItemId,
                    token: token
                )
            }

            // Sort: folders first, then files, each group alphabetically
            items.sort { lhs, rhs in
                if lhs.isFolder != rhs.isFolder {
                    return lhs.isFolder
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }
}
