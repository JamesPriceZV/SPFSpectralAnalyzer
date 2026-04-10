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

    /// Resolved SharePoint site info, cached after first successful resolution.
    var resolvedSite: SharePointSiteInfo?

    /// Whether site resolution is in progress.
    var isResolvingSite = false

    // MARK: - Site Browser State

    /// Whether the site browser popover is showing.
    var showSiteBrowser = false

    /// Available SharePoint sites from the tenant.
    var availableSites: [GraphSiteResponse] = []

    /// Whether site enumeration is in progress.
    var isLoadingSites = false

    /// Filter query for the site browser list.
    var siteFilterQuery: String = ""

    /// Filtered sites matching the search query.
    var filteredSites: [GraphSiteResponse] {
        if siteFilterQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return availableSites
        }
        let query = siteFilterQuery.lowercased()
        return availableSites.filter { site in
            (site.displayName?.lowercased().contains(query) ?? false) ||
            (site.name?.lowercased().contains(query) ?? false) ||
            (site.webUrl?.lowercased().contains(query) ?? false)
        }
    }

    // MARK: - Auth

    let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    /// When true, suppresses the onChange handler that clears resolvedSite.
    /// Set during programmatic updates to sharePointSitePath.
    var suppressSiteClear = false

    /// Invalidate the cached site resolution when the URL changes.
    func clearResolvedSite() {
        guard !suppressSiteClear else { return }
        resolvedSite = nil
    }

    /// Directly set the resolved site from a Browse Sites selection,
    /// bypassing Graph API re-resolution (which fails with hostname-only URLs).
    func directlySetResolvedSite(siteId: String, displayName: String, webUrl: String) {
        self.resolvedSite = SharePointSiteInfo(
            siteId: siteId,
            displayName: displayName,
            webUrl: webUrl
        )
        // Suppress the onChange handler from clearing the site we just set
        self.suppressSiteClear = true
        self.sharePointSitePath = webUrl
        self.suppressSiteClear = false
    }

    // MARK: - Site Enumeration

    /// Load available SharePoint sites from the tenant via Graph API search.
    func loadAvailableSites() async {
        guard !isLoadingSites else { return }
        // Only fetch if we haven't already cached sites
        guard availableSites.isEmpty else { return }

        isLoadingSites = true
        defer { isLoadingSites = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.retrievalScopes)
            availableSites = try await GraphUploadService.searchSites(query: "*", token: token)
        } catch {
            errorMessage = "Could not load sites: \(error.localizedDescription)"
        }
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
                let site = try await ensureResolvedSite(token: token)
                items = try await GraphUploadService.searchDriveItems(
                    query: trimmed,
                    siteId: site.siteId,
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

    /// Ensure we have a resolved site ID, resolving from user input if needed.
    private func ensureResolvedSite(token: String) async throws -> SharePointSiteInfo {
        if let site = resolvedSite { return site }

        let input = sharePointSitePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            throw GraphUploadError.invalidSharePointURL("(empty)")
        }

        isResolvingSite = true
        defer { isResolvingSite = false }

        let site = try await GraphUploadService.resolveSiteId(from: input, token: token)
        resolvedSite = site
        return site
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
                let site = try await ensureResolvedSite(token: token)
                items = try await GraphUploadService.listSharePointFolder(
                    siteId: site.siteId,
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
        } catch let authError as M365AuthError {
            errorMessage = "Authentication required: \(authError.localizedDescription)"
            items = []
        } catch {
            errorMessage = error.localizedDescription
            items = []
        }
    }
}
