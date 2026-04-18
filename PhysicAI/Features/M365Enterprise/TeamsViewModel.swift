import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

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

    // MARK: - Avatar & Presence Caches

    /// Cached user avatar image data keyed by user ID.
    private var avatarCache: [String: Data] = [:]

    /// Cached presence status keyed by user ID.
    var presenceCache: [String: PresenceStatus] = [:]

    /// Cached user profiles keyed by user ID.
    var profileCache: [String: GraphUserProfile] = [:]

    /// Which user's contact card popover is currently shown (nil = none).
    var contactCardUserId: String?

    /// Grouped messages for the current conversation.
    var messageGroups: [MessageGroup] = []

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
        updateMessageGroups()
    }

    /// Select a chat and load its messages.
    func selectChat(_ chat: TeamsChat) async {
        selectedChat = chat
        selectedChannel = nil
        await loadChatMessages(chatId: chat.id)
        updateMessageGroups()
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
            updateMessageGroups()
        } catch {
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Avatar & Presence

    /// Get cached avatar data for a user ID, fetching if not cached.
    func avatarData(for userId: String) -> Data? {
        avatarCache[userId]
    }

    /// Load avatar for a user, caching the result.
    func loadAvatar(for userId: String) async {
        guard !userId.isEmpty, avatarCache[userId] == nil else { return }
        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            if let data = await GraphTeamsService.fetchUserPhoto(userId: userId, accessToken: token) {
                avatarCache[userId] = data
            }
        } catch {
            // Silently fail — will use initials fallback
        }
    }

    /// Load user profile for a given user ID, caching the result.
    func loadProfile(for userId: String) async {
        guard !userId.isEmpty, profileCache[userId] == nil else { return }
        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            if let profile = await GraphTeamsService.fetchUserProfile(userId: userId, accessToken: token) {
                profileCache[userId] = profile
            }
        } catch {
            // Silently fail — profile is supplementary info
        }
    }

    /// Load presence for all visible user IDs.
    func loadPresence(for userIds: [String]) async {
        let uncached = userIds.filter { !$0.isEmpty && presenceCache[$0] == nil }
        guard !uncached.isEmpty else { return }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            let presences = await GraphTeamsService.batchGetPresence(
                userIds: Array(Set(uncached)),
                accessToken: token
            )
            for p in presences {
                presenceCache[p.id] = PresenceStatus(availability: p.availability)
            }
        } catch {
            // Silently fail
        }
    }

    // MARK: - Message Grouping

    /// Group messages by consecutive sender within a 5-minute window.
    func updateMessageGroups() {
        var groups: [MessageGroup] = []
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoFormatterNoFrac = ISO8601DateFormatter()
        isoFormatterNoFrac.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String?) -> Date? {
            guard let s else { return nil }
            return isoFormatter.date(from: s) ?? isoFormatterNoFrac.date(from: s)
        }

        // Messages come in reverse chronological order from Graph — reverse for grouping
        let chronological = messages.reversed()

        var currentGroup: (senderId: String?, senderName: String, timestamp: Date?, messages: [TeamsChatMessage])?

        for message in chronological {
            let senderId = message.from?.user?.id
            let senderName = message.senderName
            let date = parseDate(message.createdDateTime)

            if let group = currentGroup,
               group.senderId == senderId,
               let groupTime = group.timestamp,
               let msgTime = date,
               msgTime.timeIntervalSince(groupTime) < 300 {
                // Same sender within 5 minutes — extend group
                currentGroup?.messages.append(message)
            } else {
                // Flush previous group
                if let group = currentGroup {
                    groups.append(MessageGroup(
                        id: group.messages.first?.id ?? UUID().uuidString,
                        senderId: group.senderId,
                        senderName: group.senderName,
                        timestamp: group.timestamp,
                        messages: group.messages
                    ))
                }
                currentGroup = (senderId, senderName, date, [message])
            }
        }

        // Flush last group
        if let group = currentGroup {
            groups.append(MessageGroup(
                id: group.messages.first?.id ?? UUID().uuidString,
                senderId: group.senderId,
                senderName: group.senderName,
                timestamp: group.timestamp,
                messages: group.messages
            ))
        }

        messageGroups = groups

        // Kick off avatar, presence, and profile loading for visible senders
        let senderIds = Array(Set(groups.compactMap(\.senderId)))
        Task {
            await loadPresence(for: senderIds)
            for id in senderIds {
                await loadAvatar(for: id)
                await loadProfile(for: id)
            }
        }
    }

    // MARK: - Share Analysis Results

    /// Format and send spectral analysis results to the currently selected channel or chat.
    func shareAnalysisResult(summary: String, spfValue: String?, criticalWavelength: String?, uvaUvbRatio: String?) async {
        var html = "<b>PhysicAI Analysis Results</b><br/>"
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
        html += "<br/><em>Shared from PhysicAI</em>"

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
