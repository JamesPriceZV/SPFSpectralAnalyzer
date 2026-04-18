import Foundation

// MARK: - Copilot Chat View Model

/// View model for the Copilot-style enterprise chat interface.
/// Routes queries through Graph Search / Copilot Retrieval API and presents
/// results as conversational message bubbles with citation cards.
@MainActor @Observable
final class CopilotChatViewModel {

    // MARK: - Types

    enum Scope: String, CaseIterable, Identifiable {
        case work = "Work"
        case web = "Web"
        var id: String { rawValue }
    }

    // MARK: - State

    var scope: Scope = .work
    var messages: [CopilotMessage] = []
    var inputText = ""
    var isSearching = false
    var errorMessage: String?

    let defaultSuggestions = [
        "Find UV-Vis test reports",
        "Latest documents from SharePoint",
        "Summarize team documentation",
        "Search for spectral analysis files"
    ]

    // MARK: - Auth

    let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Actions

    /// Send the current input text as a user message and search for results.
    func send() async {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        // Add user message
        let userMessage = CopilotMessage(
            role: .user,
            text: trimmed,
            citations: [],
            timestamp: Date()
        )
        messages.append(userMessage)
        inputText = ""
        isSearching = true
        errorMessage = nil

        switch scope {
        case .work:
            await searchWork(query: trimmed)
        case .web:
            // Web scope placeholder — show a message
            let webMessage = CopilotMessage(
                role: .copilot,
                text: "Web search is coming soon. Switch to Work scope to search your Microsoft 365 content.",
                citations: [],
                timestamp: Date()
            )
            messages.append(webMessage)
            isSearching = false
        }
    }

    /// Send a suggestion as a quick query.
    func sendSuggestion(_ suggestion: String) async {
        inputText = suggestion
        await send()
    }

    /// Clear the conversation.
    func clearConversation() {
        messages = []
        errorMessage = nil
    }

    // MARK: - Private

    private func searchWork(query: String) async {
        guard authManager.isSignedIn else {
            let signInMessage = CopilotMessage(
                role: .copilot,
                text: "Please sign in to Microsoft 365 to search enterprise content.",
                citations: [],
                timestamp: Date()
            )
            messages.append(signInMessage)
            isSearching = false
            return
        }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.retrievalScopesWithConnectors)

            // Search across all sources
            let citations = try await CopilotRetrievalService.retrieveFromMultipleSources(
                query: query,
                sources: Set(RetrievalDataSource.allCases),
                sitePathFilter: nil,
                maxResultsPerSource: 5,
                token: token
            )

            let responseText: String
            if citations.isEmpty {
                responseText = "I couldn't find any results for \"\(query)\". Try rephrasing your query or checking that the content exists in your Microsoft 365 environment."
            } else {
                responseText = "I found \(citations.count) relevant result\(citations.count == 1 ? "" : "s") for \"\(query)\"."
            }

            let copilotMessage = CopilotMessage(
                role: .copilot,
                text: responseText,
                citations: citations,
                timestamp: Date()
            )
            messages.append(copilotMessage)

            Instrumentation.log(
                "Copilot chat: \(citations.count) results for \"\(query)\"",
                area: .aiAnalysis, level: .info
            )
        } catch {
            errorMessage = error.localizedDescription
            let errorMsg = CopilotMessage(
                role: .copilot,
                text: "Something went wrong: \(error.localizedDescription)",
                citations: [],
                timestamp: Date()
            )
            messages.append(errorMsg)
        }

        isSearching = false
    }
}

// MARK: - Copilot Message

struct CopilotMessage: Identifiable, Sendable {
    let id = UUID()
    let role: Role
    let text: String
    let citations: [GroundingCitation]
    let timestamp: Date

    enum Role: Sendable {
        case user
        case copilot
    }
}
