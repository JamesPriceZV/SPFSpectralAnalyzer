import Foundation

// MARK: - Enterprise Search View Model

/// View model for the standalone Enterprise Search tab.
/// Orchestrates M365 authentication, Retrieval API queries, and result management.
@MainActor @Observable
final class EnterpriseSearchViewModel {
    // MARK: - State

    var query: String = ""
    var selectedDataSource: RetrievalDataSource = .sharePoint
    var sitePathFilter: String = ""
    var maxResults: Int = 10
    var isLoading = false
    var errorMessage: String?
    var citations: [GroundingCitation] = []
    var searchHistory: [String] = []

    // MARK: - Auth

    let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Search

    /// Execute a retrieval search against the selected M365 data source.
    func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a search query."
            return
        }

        guard authManager.isSignedIn else {
            errorMessage = "Sign in to Microsoft 365 to search enterprise content."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        // Track search history
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !searchHistory.contains(trimmedQuery) {
            searchHistory.insert(trimmedQuery, at: 0)
            if searchHistory.count > 20 { searchHistory.removeLast() }
        }

        do {
            // Determine required scopes
            let scopes = selectedDataSource == .externalItem
                ? M365Config.retrievalScopesWithConnectors
                : M365Config.retrievalScopes

            let token = try await authManager.acquireToken(scopes: scopes)

            let filter: String? = {
                guard selectedDataSource == .sharePoint,
                      !sitePathFilter.isEmpty else { return nil }
                return "path:\"\(sitePathFilter)\""
            }()

            let request = RetrievalRequest(
                queryString: trimmedQuery,
                dataSource: selectedDataSource,
                filterExpression: filter,
                resourceMetadata: ["title", "author"],
                maximumNumberOfResults: maxResults
            )

            let response = try await CopilotRetrievalService.retrieve(request, token: token)
            citations = response.hits.map { GroundingCitation(hit: $0, dataSource: selectedDataSource) }

            if citations.isEmpty {
                errorMessage = "No results found. Try adjusting your query or data source."
            }

            Instrumentation.log(
                "Enterprise search: \(citations.count) results from \(selectedDataSource.displayName)",
                area: .aiAnalysis, level: .info
            )
        } catch {
            errorMessage = error.localizedDescription
            citations = []
        }
    }

    /// Search across all enabled data sources in parallel.
    func searchAllSources() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter a search query."
            return
        }

        guard authManager.isSignedIn else {
            errorMessage = "Sign in to Microsoft 365 to search enterprise content."
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.retrievalScopesWithConnectors)

            citations = try await CopilotRetrievalService.retrieveFromMultipleSources(
                query: trimmedQuery,
                sources: Set(RetrievalDataSource.allCases),
                sitePathFilter: sitePathFilter.isEmpty ? nil : sitePathFilter,
                maxResultsPerSource: maxResults,
                token: token
            )

            if citations.isEmpty {
                errorMessage = "No results found across any data source."
            }
        } catch {
            errorMessage = error.localizedDescription
            citations = []
        }
    }

    /// Sign in to Microsoft 365.
    func signIn() async {
        do {
            _ = try await authManager.signIn(scopes: M365Config.retrievalScopes)
        } catch {
            errorMessage = "Sign-in failed: \(error.localizedDescription)"
        }
    }

    /// Sign out from Microsoft 365.
    func signOut() async {
        do {
            try await authManager.signOut()
            citations = []
            errorMessage = nil
        } catch {
            errorMessage = "Sign-out failed: \(error.localizedDescription)"
        }
    }

    /// Clear search results and errors.
    func clearResults() {
        citations = []
        errorMessage = nil
    }
}
