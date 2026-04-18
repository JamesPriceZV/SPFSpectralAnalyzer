import Foundation
import SwiftUI

// MARK: - Generic Graph List Response

/// Generic wrapper for Microsoft Graph paginated list responses.
struct GraphListResponse<T: Codable & Sendable>: Codable, Sendable {
    let value: [T]
    let odataNextLink: String?

    enum CodingKeys: String, CodingKey {
        case value
        case odataNextLink = "@odata.nextLink"
    }
}

// MARK: - Teams & Channels

/// A Microsoft Teams team the user has joined.
struct TeamsTeam: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String?
    let description: String?
}

/// A channel within a Teams team.
struct TeamsChannel: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let displayName: String?
    let description: String?
    let membershipType: String?

    /// Whether this is the default "General" channel.
    var isGeneral: Bool { membershipType == "standard" && displayName == "General" }
}

// MARK: - Chats

/// A 1:1 or group chat in Microsoft Teams.
struct TeamsChat: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let topic: String?
    let chatType: String?
    let lastUpdatedDateTime: String?

    /// Display label: topic if available, or chat type description.
    var displayName: String {
        if let topic, !topic.isEmpty { return topic }
        switch chatType {
        case "oneOnOne": return "1:1 Chat"
        case "group": return "Group Chat"
        case "meeting": return "Meeting Chat"
        default: return "Chat"
        }
    }
}

// MARK: - Chat Messages

/// A message in a Teams chat or channel.
struct TeamsChatMessage: Codable, Sendable, Identifiable {
    let id: String
    let body: TeamsMessageBody?
    let from: TeamsMessageSender?
    let createdDateTime: String?

    /// Sender display name, or "Unknown" if unavailable.
    var senderName: String {
        from?.user?.displayName ?? "Unknown"
    }

    /// Plain-text content of the message body.
    var textContent: String {
        body?.content ?? ""
    }
}

/// The body of a Teams message (text or HTML).
struct TeamsMessageBody: Codable, Sendable {
    let contentType: String?
    let content: String?
}

/// Sender identity of a Teams message.
struct TeamsMessageSender: Codable, Sendable {
    let user: TeamsIdentityUser?
}

/// User identity within a Teams message sender.
struct TeamsIdentityUser: Codable, Sendable {
    let id: String?
    let displayName: String?
}

// MARK: - Teams Chat Member

/// A member of a Teams chat or channel.
struct TeamsChatMember: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String?
    let email: String?
}

// MARK: - Presence

/// User presence/availability status from Microsoft Graph.
enum PresenceStatus: String, Sendable, CaseIterable {
    case available = "Available"
    case busy = "Busy"
    case doNotDisturb = "DoNotDisturb"
    case away = "Away"
    case berightback = "BeRightBack"
    case offline = "Offline"
    case presenceUnknown = "PresenceUnknown"

    init(availability: String?) {
        self = PresenceStatus(rawValue: availability ?? "") ?? .presenceUnknown
    }

    var color: Color {
        switch self {
        case .available: return .green
        case .busy, .doNotDisturb: return .red
        case .away, .berightback: return .yellow
        case .offline, .presenceUnknown: return .gray
        }
    }

    var systemImage: String {
        switch self {
        case .available: return "circle.fill"
        case .busy, .doNotDisturb: return "minus.circle.fill"
        case .away, .berightback: return "clock.fill"
        case .offline, .presenceUnknown: return "circle"
        }
    }
}

/// Graph API presence response.
struct GraphPresenceResponse: Codable, Sendable {
    let id: String
    let availability: String?
    let activity: String?
}

/// Message grouping for consecutive messages from the same sender.
struct MessageGroup: Identifiable {
    let id: String
    let senderId: String?
    let senderName: String
    let timestamp: Date?
    let messages: [TeamsChatMessage]
}

// MARK: - User Profile

/// User profile information from Microsoft Graph.
struct GraphUserProfile: Codable, Sendable, Identifiable {
    let id: String
    let displayName: String?
    let jobTitle: String?
    let department: String?
    let mail: String?
}

// MARK: - Service Errors

enum GraphTeamsError: LocalizedError, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case notAuthenticated
    case encodingError

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Graph API URL: \(url)"
        case .invalidResponse:
            return "Invalid response from Microsoft Graph"
        case .httpError(let code, let body):
            return "Graph API error \(code): \(body.prefix(200))"
        case .notAuthenticated:
            return "Not authenticated with Microsoft 365. Please sign in first."
        case .encodingError:
            return "Failed to encode the message content."
        }
    }
}
