import Foundation
import SwiftData

// MARK: - Teams Sync Service

/// Orchestrates Teams data synchronization: fetches from Microsoft Graph,
/// upserts into a local SwiftData cache, and reports new content counts.
/// Uses a dedicated ModelContainer separate from the main app data store.
enum TeamsSyncService {

    // MARK: - Cache Container

    /// Dedicated local-only ModelContainer for Teams cache data.
    /// Completely independent from the main DataStoreController — no CloudKit sync.
    static let cacheContainer: ModelContainer = {
        let schema = Schema([
            CachedTeamsTeam.self,
            CachedTeamsChannel.self,
            CachedTeamsChat.self,
            CachedTeamsMessage.self,
            CachedTeamsFile.self
        ])

        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)

        // Ensure directory exists
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let storeURL = appSupport.appendingPathComponent("TeamsCache.store")
        let config = ModelConfiguration(
            "TeamsCache",
            schema: schema,
            url: storeURL,
            allowsSave: true,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Failed to create Teams cache container: \(error)")
        }
    }()

    // MARK: - Full Sync

    /// Perform a full sync of all Teams data from Microsoft Graph.
    @MainActor
    static func performFullSync(authManager: MSALAuthManager) async throws -> TeamsSyncResult {
        let token = try await authManager.acquireToken(scopes: M365Config.teamsSyncScopes)
        let context = ModelContext(cacheContainer)

        var newMessageCount = 0
        var newFileCount = 0
        var totalChannels = 0

        // 1. Sync teams
        let teams = try await GraphTeamsService.listJoinedTeams(accessToken: token)
        for team in teams {
            upsertTeam(team, in: context)

            // 2. Sync channels for each team
            let channels = try await GraphTeamsService.listChannels(
                teamId: team.id, accessToken: token
            )
            totalChannels += channels.count

            for channel in channels {
                upsertChannel(channel, teamGraphId: team.id, in: context)

                // 3. Sync channel messages (paginated)
                do {
                    let messages = try await GraphTeamsService.listAllChannelMessages(
                        teamId: team.id, channelId: channel.id, accessToken: token
                    )
                    for msg in messages {
                        let isNew = upsertMessage(
                            msg, sourceType: "channel", sourceGraphId: channel.id,
                            teamGraphId: team.id, in: context
                        )
                        if isNew { newMessageCount += 1 }
                    }
                } catch {
                    // Continue syncing other channels if one fails
                    Instrumentation.log(
                        "Teams sync: channel messages failed",
                        area: .aiAnalysis, level: .warning,
                        details: "team=\(team.id) channel=\(channel.id) error=\(error.localizedDescription)"
                    )
                }

                // 4. Sync channel files
                do {
                    let files = try await GraphTeamsService.listChannelFiles(
                        teamId: team.id, channelId: channel.id, accessToken: token
                    )
                    for file in files where !file.isFolder {
                        let isNew = upsertFile(
                            file, sourceType: "channel", sourceGraphId: channel.id,
                            teamGraphId: team.id, in: context
                        )
                        if isNew { newFileCount += 1 }
                    }
                } catch {
                    Instrumentation.log(
                        "Teams sync: channel files failed",
                        area: .aiAnalysis, level: .warning,
                        details: "team=\(team.id) channel=\(channel.id) error=\(error.localizedDescription)"
                    )
                }
            }
        }

        // 5. Sync chats
        let chats = try await GraphTeamsService.listChats(accessToken: token)
        for chat in chats {
            upsertChat(chat, in: context)

            // 6. Sync chat messages (paginated)
            do {
                let messages = try await GraphTeamsService.listAllChatMessages(
                    chatId: chat.id, accessToken: token
                )
                for msg in messages {
                    let isNew = upsertMessage(
                        msg, sourceType: "chat", sourceGraphId: chat.id,
                        teamGraphId: "", in: context
                    )
                    if isNew { newMessageCount += 1 }
                }
            } catch {
                Instrumentation.log(
                    "Teams sync: chat messages failed",
                    area: .aiAnalysis, level: .warning,
                    details: "chat=\(chat.id) error=\(error.localizedDescription)"
                )
            }
        }

        // Save all changes — safe on this fresh context (NOT the main DataStoreController context)
        try context.save()

        // Update last sync timestamp
        UserDefaults.standard.set(Date().timeIntervalSince1970,
                                   forKey: M365Config.TeamsSyncKeys.lastSyncTimestamp)

        let result = TeamsSyncResult(
            newMessageCount: newMessageCount,
            newFileCount: newFileCount,
            syncedAt: Date(),
            teamsCount: teams.count,
            channelsCount: totalChannels,
            chatsCount: chats.count
        )

        Instrumentation.log(
            "Teams sync complete",
            area: .aiAnalysis, level: .info,
            details: "teams=\(result.teamsCount) channels=\(result.channelsCount) chats=\(result.chatsCount) newMessages=\(newMessageCount) newFiles=\(newFileCount)"
        )

        return result
    }

    // MARK: - Load from Cache

    /// Load cached teams as API model objects.
    @MainActor
    static func loadCachedTeams() -> [TeamsTeam] {
        let context = ModelContext(cacheContainer)
        let descriptor = FetchDescriptor<CachedTeamsTeam>(
            sortBy: [SortDescriptor(\.displayName)]
        )
        guard let cached = try? context.fetch(descriptor) else { return [] }
        return cached.map { TeamsTeam(id: $0.graphId, displayName: $0.displayName, description: $0.teamDescription) }
    }

    /// Load cached channels for a specific team.
    @MainActor
    static func loadCachedChannels(teamGraphId: String) -> [TeamsChannel] {
        let context = ModelContext(cacheContainer)
        let descriptor = FetchDescriptor<CachedTeamsChannel>(
            predicate: #Predicate { $0.teamGraphId == teamGraphId },
            sortBy: [SortDescriptor(\.displayName)]
        )
        guard let cached = try? context.fetch(descriptor) else { return [] }
        return cached.map {
            TeamsChannel(id: $0.graphId, displayName: $0.displayName,
                         description: $0.channelDescription, membershipType: $0.membershipType)
        }
    }

    /// Load cached chats.
    @MainActor
    static func loadCachedChats() -> [TeamsChat] {
        let context = ModelContext(cacheContainer)
        let descriptor = FetchDescriptor<CachedTeamsChat>(
            sortBy: [SortDescriptor(\.lastUpdatedDateTime, order: .reverse)]
        )
        guard let cached = try? context.fetch(descriptor) else { return [] }
        return cached.map {
            TeamsChat(id: $0.graphId, topic: $0.topic.isEmpty ? nil : $0.topic,
                      chatType: $0.chatType.isEmpty ? nil : $0.chatType,
                      lastUpdatedDateTime: $0.lastUpdatedDateTime.isEmpty ? nil : $0.lastUpdatedDateTime)
        }
    }

    /// Load cached messages for a given source (channel or chat).
    @MainActor
    static func loadCachedMessages(sourceType: String, sourceGraphId: String) -> [TeamsChatMessage] {
        let context = ModelContext(cacheContainer)
        let descriptor = FetchDescriptor<CachedTeamsMessage>(
            predicate: #Predicate { $0.sourceType == sourceType && $0.sourceGraphId == sourceGraphId },
            sortBy: [SortDescriptor(\.createdDateTime, order: .reverse)]
        )
        guard let cached = try? context.fetch(descriptor) else { return [] }
        return cached.map { msg in
            let body = TeamsMessageBody(contentType: msg.bodyContentType.isEmpty ? nil : msg.bodyContentType,
                                         content: msg.bodyContent.isEmpty ? nil : msg.bodyContent)
            let sender = TeamsMessageSender(user: TeamsIdentityUser(
                id: msg.senderUserId.isEmpty ? nil : msg.senderUserId,
                displayName: msg.senderDisplayName.isEmpty ? nil : msg.senderDisplayName
            ))
            return TeamsChatMessage(id: msg.graphId, body: body, from: sender,
                                     createdDateTime: msg.createdDateTime.isEmpty ? nil : msg.createdDateTime)
        }
    }

    /// Load cached files for a given source.
    @MainActor
    static func loadCachedFiles(sourceType: String, sourceGraphId: String) -> [CachedTeamsFile] {
        let context = ModelContext(cacheContainer)
        let descriptor = FetchDescriptor<CachedTeamsFile>(
            predicate: #Predicate { $0.sourceType == sourceType && $0.sourceGraphId == sourceGraphId },
            sortBy: [SortDescriptor(\.name)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    // MARK: - Clear Cache

    /// Delete all cached Teams data.
    @MainActor
    static func clearCache() throws {
        let context = ModelContext(cacheContainer)
        try context.delete(model: CachedTeamsMessage.self)
        try context.delete(model: CachedTeamsFile.self)
        try context.delete(model: CachedTeamsChannel.self)
        try context.delete(model: CachedTeamsChat.self)
        try context.delete(model: CachedTeamsTeam.self)
        try context.save()
        UserDefaults.standard.removeObject(forKey: M365Config.TeamsSyncKeys.lastSyncTimestamp)
    }

    // MARK: - Upsert Helpers

    private static func upsertTeam(_ team: TeamsTeam, in context: ModelContext) {
        let teamId = team.id
        let descriptor = FetchDescriptor<CachedTeamsTeam>(
            predicate: #Predicate { $0.graphId == teamId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = team.displayName ?? ""
            existing.teamDescription = team.description ?? ""
            existing.lastSyncedAt = Date()
        } else {
            context.insert(CachedTeamsTeam(
                graphId: team.id,
                displayName: team.displayName ?? "",
                teamDescription: team.description ?? ""
            ))
        }
    }

    private static func upsertChannel(_ channel: TeamsChannel, teamGraphId: String, in context: ModelContext) {
        let channelId = channel.id
        let descriptor = FetchDescriptor<CachedTeamsChannel>(
            predicate: #Predicate { $0.graphId == channelId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.displayName = channel.displayName ?? ""
            existing.channelDescription = channel.description ?? ""
            existing.membershipType = channel.membershipType ?? ""
            existing.lastSyncedAt = Date()
        } else {
            context.insert(CachedTeamsChannel(
                graphId: channel.id,
                teamGraphId: teamGraphId,
                displayName: channel.displayName ?? "",
                channelDescription: channel.description ?? "",
                membershipType: channel.membershipType ?? ""
            ))
        }
    }

    private static func upsertChat(_ chat: TeamsChat, in context: ModelContext) {
        let chatId = chat.id
        let descriptor = FetchDescriptor<CachedTeamsChat>(
            predicate: #Predicate { $0.graphId == chatId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.topic = chat.topic ?? ""
            existing.chatType = chat.chatType ?? ""
            existing.lastUpdatedDateTime = chat.lastUpdatedDateTime ?? ""
            existing.lastSyncedAt = Date()
        } else {
            context.insert(CachedTeamsChat(
                graphId: chat.id,
                topic: chat.topic ?? "",
                chatType: chat.chatType ?? "",
                lastUpdatedDateTime: chat.lastUpdatedDateTime ?? ""
            ))
        }
    }

    /// Upsert a message. Returns `true` if this is a new message (not previously cached).
    @discardableResult
    private static func upsertMessage(
        _ msg: TeamsChatMessage,
        sourceType: String,
        sourceGraphId: String,
        teamGraphId: String,
        in context: ModelContext
    ) -> Bool {
        let msgId = msg.id
        let descriptor = FetchDescriptor<CachedTeamsMessage>(
            predicate: #Predicate { $0.graphId == msgId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.bodyContent = msg.body?.content ?? ""
            existing.bodyContentType = msg.body?.contentType ?? ""
            existing.senderDisplayName = msg.from?.user?.displayName ?? ""
            existing.lastSyncedAt = Date()
            return false
        } else {
            context.insert(CachedTeamsMessage(
                graphId: msg.id,
                bodyContentType: msg.body?.contentType ?? "",
                bodyContent: msg.body?.content ?? "",
                senderDisplayName: msg.from?.user?.displayName ?? "",
                senderUserId: msg.from?.user?.id ?? "",
                createdDateTime: msg.createdDateTime ?? "",
                sourceType: sourceType,
                sourceGraphId: sourceGraphId,
                teamGraphId: teamGraphId
            ))
            return true
        }
    }

    /// Upsert a file. Returns `true` if this is a new file (not previously cached).
    @discardableResult
    private static func upsertFile(
        _ item: GraphDriveItem,
        sourceType: String,
        sourceGraphId: String,
        teamGraphId: String,
        in context: ModelContext
    ) -> Bool {
        let fileId = item.id
        let descriptor = FetchDescriptor<CachedTeamsFile>(
            predicate: #Predicate { $0.graphId == fileId }
        )
        if let existing = try? context.fetch(descriptor).first {
            existing.name = item.name
            existing.size = item.size ?? 0
            existing.webUrl = item.webUrl ?? ""
            existing.mimeType = item.file?.mimeType ?? ""
            existing.lastModifiedDateTime = item.lastModifiedDateTime ?? ""
            existing.lastSyncedAt = Date()
            return false
        } else {
            context.insert(CachedTeamsFile(
                graphId: item.id,
                name: item.name,
                size: item.size ?? 0,
                webUrl: item.webUrl ?? "",
                mimeType: item.file?.mimeType ?? "",
                lastModifiedDateTime: item.lastModifiedDateTime ?? "",
                sourceType: sourceType,
                sourceGraphId: sourceGraphId,
                teamGraphId: teamGraphId
            ))
            return true
        }
    }
}
