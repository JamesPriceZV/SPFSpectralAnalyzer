import Foundation

// MARK: - Teams View Model

/// View model for Microsoft Teams integration.
/// Manages teams, channels, chats, and messaging via Microsoft Graph.
@MainActor @Observable
final class TeamsViewModel {

    // MARK: - State

    var teams: [TeamsTeam] = []
    var channels: [TeamsChannel] = []
    var chats: [TeamsChat] = []
    var messages: [TeamsChatMessage] = []

    var selectedTeam: TeamsTeam?
    var selectedChannel: TeamsChannel?
    var selectedChat: TeamsChat?

    var composeText: String = ""
    var isLoading = false
    var isSending = false
    var errorMessage: String?

    /// Which list to show in the sidebar.
    enum SidebarMode: String, CaseIterable, Identifiable {
        case teams = "Teams"
        case chats = "Chats"
        var id: String { rawValue }
    }

    var sidebarMode: SidebarMode = .teams

    // MARK: - Sync State

    var isSyncEnabled: Bool {
        get { TeamsSyncMonitor.shared.isEnabled }
        set { TeamsSyncMonitor.shared.isEnabled = newValue }
    }

    var isSyncing: Bool { TeamsSyncMonitor.shared.isSyncing }
    var lastSyncDate: Date? { TeamsSyncMonitor.shared.lastSyncDate }
    var syncError: String? { TeamsSyncMonitor.shared.lastError }

    // MARK: - Auth

    let authManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
    }

    // MARK: - Sync Controls

    /// Toggle sync on or off.
    func toggleSync() {
        isSyncEnabled.toggle()
        if isSyncEnabled {
            TeamsSyncMonitor.shared.start(authManager: authManager)
        } else {
            TeamsSyncMonitor.shared.stop()
        }
    }

    /// Manually trigger a sync.
    func syncNow() async {
        await TeamsSyncMonitor.shared.syncNow()
        // Refresh displayed data from cache
        loadFromCacheIfEnabled()
    }

    /// Load cached files for a given source.
    func cachedFilesForSource(sourceType: String, sourceGraphId: String) -> [CachedTeamsFile] {
        guard isSyncEnabled else { return [] }
        return TeamsSyncService.loadCachedFiles(sourceType: sourceType, sourceGraphId: sourceGraphId)
    }

    /// Populate display arrays from the local cache.
    private func loadFromCacheIfEnabled() {
        guard isSyncEnabled else { return }
        let cachedTeams = TeamsSyncService.loadCachedTeams()
        if !cachedTeams.isEmpty { teams = cachedTeams }
        let cachedChats = TeamsSyncService.loadCachedChats()
        if !cachedChats.isEmpty { chats = cachedChats }
        if let team = selectedTeam {
            let cachedChannels = TeamsSyncService.loadCachedChannels(teamGraphId: team.id)
            if !cachedChannels.isEmpty { channels = cachedChannels }
        }
    }

    // MARK: - Load Teams & Channels

    /// Fetch teams the signed-in user has joined.
    /// When sync is enabled, loads cached data first for instant display.
    func loadTeams() async {
        // Load from cache first for instant display
        if isSyncEnabled {
            let cached = TeamsSyncService.loadCachedTeams()
            if !cached.isEmpty { teams = cached }
        }

        guard authManager.isSignedIn else {
            if teams.isEmpty {
                errorMessage = "Sign in to Microsoft 365 to use Teams."
            }
            return
        }

        isLoading = teams.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            teams = try await GraphTeamsService.listJoinedTeams(accessToken: token)
            Instrumentation.log(
                "Teams: loaded \(teams.count) joined teams",
                area: .aiAnalysis, level: .info
            )
        } catch {
            // If we have cached data, show it with a note
            if teams.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Using cached data. \(error.localizedDescription)"
            }
        }
    }

    /// Fetch channels for a specific team.
    func loadChannels(for team: TeamsTeam) async {
        selectedTeam = team
        selectedChannel = nil
        messages = []

        // Load from cache first
        if isSyncEnabled {
            let cached = TeamsSyncService.loadCachedChannels(teamGraphId: team.id)
            if !cached.isEmpty { channels = cached }
        }

        isLoading = channels.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            channels = try await GraphTeamsService.listChannels(teamId: team.id, accessToken: token)
        } catch {
            if channels.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    // MARK: - Load Chats

    /// Fetch the user's recent chats.
    /// When sync is enabled, loads cached data first for instant display.
    func loadChats() async {
        // Load from cache first
        if isSyncEnabled {
            let cached = TeamsSyncService.loadCachedChats()
            if !cached.isEmpty { chats = cached }
        }

        guard authManager.isSignedIn else {
            if chats.isEmpty {
                errorMessage = "Sign in to Microsoft 365 to use Teams."
            }
            return
        }

        isLoading = chats.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            chats = try await GraphTeamsService.listChats(accessToken: token)
            Instrumentation.log(
                "Teams: loaded \(chats.count) recent chats",
                area: .aiAnalysis, level: .info
            )
        } catch {
            if chats.isEmpty {
                errorMessage = error.localizedDescription
            } else {
                errorMessage = "Using cached data. \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Load Messages

    /// Fetch messages for a channel.
    func loadChannelMessages(teamId: String, channelId: String) async {
        // Load cached messages first
        if isSyncEnabled {
            let cached = TeamsSyncService.loadCachedMessages(sourceType: "channel", sourceGraphId: channelId)
            if !cached.isEmpty { messages = cached }
        }

        isLoading = messages.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            messages = try await GraphTeamsService.listChannelMessages(
                teamId: teamId,
                channelId: channelId,
                accessToken: token
            )
        } catch {
            if messages.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Fetch messages for a chat.
    func loadChatMessages(chatId: String) async {
        // Load cached messages first
        if isSyncEnabled {
            let cached = TeamsSyncService.loadCachedMessages(sourceType: "chat", sourceGraphId: chatId)
            if !cached.isEmpty { messages = cached }
        }

        isLoading = messages.isEmpty
        errorMessage = nil
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            messages = try await GraphTeamsService.listMessages(
                chatId: chatId,
                accessToken: token
            )
        } catch {
            if messages.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Select a channel and load its messages.
    func selectChannel(_ channel: TeamsChannel) async {
        selectedChannel = channel
        selectedChat = nil
        guard let team = selectedTeam else { return }
        await loadChannelMessages(teamId: team.id, channelId: channel.id)
    }

    /// Select a chat and load its messages.
    func selectChat(_ chat: TeamsChat) async {
        selectedChat = chat
        selectedChannel = nil
        await loadChatMessages(chatId: chat.id)
    }

    // MARK: - Send Messages

    /// Send a message to the currently selected channel or chat.
    func sendMessage() async {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)

            if let channel = selectedChannel, let team = selectedTeam {
                let newMessage = try await GraphTeamsService.sendChannelMessage(
                    teamId: team.id,
                    channelId: channel.id,
                    content: text,
                    accessToken: token
                )
                messages.insert(newMessage, at: 0)
            } else if let chat = selectedChat {
                let newMessage = try await GraphTeamsService.sendChatMessage(
                    chatId: chat.id,
                    content: text,
                    accessToken: token
                )
                messages.insert(newMessage, at: 0)
            } else {
                errorMessage = "Select a channel or chat to send a message."
                return
            }

            composeText = ""
        } catch {
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Share Analysis Results

    /// Format and send spectral analysis results to the currently selected channel or chat.
    func shareAnalysisResult(summary: String, spfValue: String?, criticalWavelength: String?, uvaUvbRatio: String?) async {
        var html = "<b>SPF Spectral Analysis Results</b><br/>"
        html += "<table>"
        if let spf = spfValue {
            html += "<tr><td><b>SPF:</b></td><td>\(spf)</td></tr>"
        }
        if let cw = criticalWavelength {
            html += "<tr><td><b>Critical \u{03BB}:</b></td><td>\(cw) nm</td></tr>"
        }
        if let ratio = uvaUvbRatio {
            html += "<tr><td><b>UVA/UVB:</b></td><td>\(ratio)</td></tr>"
        }
        html += "</table>"
        if !summary.isEmpty {
            html += "<br/><b>Summary:</b><br/>\(summary)"
        }
        html += "<br/><em>Shared from SPF Spectral Analyzer</em>"

        composeText = html

        // Send via the existing send mechanism
        isSending = true
        errorMessage = nil
        defer { isSending = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)

            if let channel = selectedChannel, let team = selectedTeam {
                let newMessage = try await GraphTeamsService.sendChannelMessage(
                    teamId: team.id,
                    channelId: channel.id,
                    content: html,
                    contentType: "html",
                    accessToken: token
                )
                messages.insert(newMessage, at: 0)
            } else if let chat = selectedChat {
                let newMessage = try await GraphTeamsService.sendChatMessage(
                    chatId: chat.id,
                    content: html,
                    contentType: "html",
                    accessToken: token
                )
                messages.insert(newMessage, at: 0)
            } else {
                errorMessage = "Select a channel or chat to share results."
                return
            }

            composeText = ""
        } catch {
            errorMessage = "Share failed: \(error.localizedDescription)"
        }
    }
}
