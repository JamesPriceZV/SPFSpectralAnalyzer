import Foundation
import SwiftData

// MARK: - Cached Teams Models

/// SwiftData models for local Teams cache. These live in a separate ModelContainer
/// from the main app data — local-only, never synced to CloudKit.
/// All properties have defaults to maintain CloudKit-compatible patterns.

/// A cached Microsoft Teams team.
@Model
final class CachedTeamsTeam {
    var graphId: String = ""
    var displayName: String = ""
    var teamDescription: String = ""
    var lastSyncedAt: Date = Date()

    init(graphId: String, displayName: String, teamDescription: String = "") {
        self.graphId = graphId
        self.displayName = displayName
        self.teamDescription = teamDescription
        self.lastSyncedAt = Date()
    }
}

/// A cached channel within a Teams team.
@Model
final class CachedTeamsChannel {
    var graphId: String = ""
    var teamGraphId: String = ""
    var displayName: String = ""
    var channelDescription: String = ""
    var membershipType: String = ""
    var lastSyncedAt: Date = Date()

    init(graphId: String, teamGraphId: String, displayName: String,
         channelDescription: String = "", membershipType: String = "") {
        self.graphId = graphId
        self.teamGraphId = teamGraphId
        self.displayName = displayName
        self.channelDescription = channelDescription
        self.membershipType = membershipType
        self.lastSyncedAt = Date()
    }
}

/// A cached 1:1 or group chat.
@Model
final class CachedTeamsChat {
    var graphId: String = ""
    var topic: String = ""
    var chatType: String = ""
    var lastUpdatedDateTime: String = ""
    var lastSyncedAt: Date = Date()

    init(graphId: String, topic: String = "", chatType: String = "",
         lastUpdatedDateTime: String = "") {
        self.graphId = graphId
        self.topic = topic
        self.chatType = chatType
        self.lastUpdatedDateTime = lastUpdatedDateTime
        self.lastSyncedAt = Date()
    }
}

/// A cached message from a Teams channel or chat.
@Model
final class CachedTeamsMessage {
    var graphId: String = ""
    var bodyContentType: String = ""
    var bodyContent: String = ""
    var senderDisplayName: String = ""
    var senderUserId: String = ""
    var createdDateTime: String = ""
    /// "channel" or "chat"
    var sourceType: String = ""
    /// The channel or chat graphId this message belongs to
    var sourceGraphId: String = ""
    /// For channel messages, the parent team's graphId
    var teamGraphId: String = ""
    var lastSyncedAt: Date = Date()

    init(graphId: String, bodyContentType: String = "", bodyContent: String = "",
         senderDisplayName: String = "", senderUserId: String = "",
         createdDateTime: String = "", sourceType: String, sourceGraphId: String,
         teamGraphId: String = "") {
        self.graphId = graphId
        self.bodyContentType = bodyContentType
        self.bodyContent = bodyContent
        self.senderDisplayName = senderDisplayName
        self.senderUserId = senderUserId
        self.createdDateTime = createdDateTime
        self.sourceType = sourceType
        self.sourceGraphId = sourceGraphId
        self.teamGraphId = teamGraphId
        self.lastSyncedAt = Date()
    }
}

/// Cached file metadata from a Teams channel or chat.
/// Stores metadata only — actual file content is accessed via webUrl.
@Model
final class CachedTeamsFile {
    var graphId: String = ""
    var name: String = ""
    var size: Int = 0
    var webUrl: String = ""
    var mimeType: String = ""
    var lastModifiedDateTime: String = ""
    /// "channel" or "chat"
    var sourceType: String = ""
    var sourceGraphId: String = ""
    var teamGraphId: String = ""
    var lastSyncedAt: Date = Date()

    init(graphId: String, name: String, size: Int = 0, webUrl: String = "",
         mimeType: String = "", lastModifiedDateTime: String = "",
         sourceType: String, sourceGraphId: String, teamGraphId: String = "") {
        self.graphId = graphId
        self.name = name
        self.size = size
        self.webUrl = webUrl
        self.mimeType = mimeType
        self.lastModifiedDateTime = lastModifiedDateTime
        self.sourceType = sourceType
        self.sourceGraphId = sourceGraphId
        self.teamGraphId = teamGraphId
        self.lastSyncedAt = Date()
    }
}

/// Result of a Teams sync operation.
struct TeamsSyncResult: Sendable {
    let newMessageCount: Int
    let newFileCount: Int
    let syncedAt: Date
    let teamsCount: Int
    let channelsCount: Int
    let chatsCount: Int
}
