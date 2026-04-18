import Foundation

// MARK: - Graph Teams Service

/// Stateless service for Microsoft Teams operations via the Graph API.
/// Follows the same pattern as `CopilotRetrievalService` and `GraphUploadService`.
enum GraphTeamsService {

    // MARK: - Teams & Channels

    /// List all teams the signed-in user has joined.
    static func listJoinedTeams(
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [TeamsTeam] {
        let url = try graphURL("me/joinedTeams")
        let data = try await authorizedGET(url: url, token: accessToken, session: session)
        return try decodeValueArray(from: data)
    }

    /// List channels in a specific team.
    static func listChannels(
        teamId: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [TeamsChannel] {
        let url = try graphURL("teams/\(teamId)/channels")
        let data = try await authorizedGET(url: url, token: accessToken, session: session)
        return try decodeValueArray(from: data)
    }

    // MARK: - Chats

    /// List the user's recent chats.
    static func listChats(
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [TeamsChat] {
        let url = try graphURL("me/chats?$top=50")
        let data = try await authorizedGET(url: url, token: accessToken, session: session)
        let chats: [TeamsChat] = try decodeValueArray(from: data)
        // Graph /me/chats does not support $orderby — sort client-side
        return chats.sorted { ($0.lastUpdatedDateTime ?? "") > ($1.lastUpdatedDateTime ?? "") }
    }

    /// List recent messages in a chat.
    static func listMessages(
        chatId: String,
        accessToken: String,
        top: Int = 25,
        session: URLSession = .shared
    ) async throws -> [TeamsChatMessage] {
        let url = try graphURL("me/chats/\(chatId)/messages?$top=\(top)")
        let data = try await authorizedGET(url: url, token: accessToken, session: session)
        return try decodeValueArray(from: data)
    }

    /// List recent messages in a channel.
    static func listChannelMessages(
        teamId: String,
        channelId: String,
        accessToken: String,
        top: Int = 25,
        session: URLSession = .shared
    ) async throws -> [TeamsChatMessage] {
        let url = try graphURL("teams/\(teamId)/channels/\(channelId)/messages?$top=\(top)")
        let data = try await authorizedGET(url: url, token: accessToken, session: session)
        return try decodeValueArray(from: data)
    }

    // MARK: - Paginated Message Fetching (for Sync)

    /// Fetch all channel messages, following @odata.nextLink pagination.
    /// - Parameters:
    ///   - teamId: The team's Graph ID.
    ///   - channelId: The channel's Graph ID.
    ///   - accessToken: Bearer token.
    ///   - maxPages: Maximum number of pages to fetch (each page ~25 messages).
    static func listAllChannelMessages(
        teamId: String,
        channelId: String,
        accessToken: String,
        maxPages: Int = 5,
        session: URLSession = .shared
    ) async throws -> [TeamsChatMessage] {
        var allMessages: [TeamsChatMessage] = []
        var nextURL: URL? = try graphURL("teams/\(teamId)/channels/\(channelId)/messages?$top=50")
        var page = 0

        while let url = nextURL, page < maxPages {
            let data = try await authorizedGET(url: url, token: accessToken, session: session)
            let messages: [TeamsChatMessage] = try decodeValueArray(from: data)
            allMessages.append(contentsOf: messages)

            // Check for next page link
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let nextLink = json["@odata.nextLink"] as? String,
               let next = URL(string: nextLink) {
                nextURL = next
            } else {
                nextURL = nil
            }
            page += 1
        }
        return allMessages
    }

    /// Fetch all chat messages, following @odata.nextLink pagination.
    static func listAllChatMessages(
        chatId: String,
        accessToken: String,
        maxPages: Int = 5,
        session: URLSession = .shared
    ) async throws -> [TeamsChatMessage] {
        var allMessages: [TeamsChatMessage] = []
        var nextURL: URL? = try graphURL("me/chats/\(chatId)/messages?$top=50")
        var page = 0

        while let url = nextURL, page < maxPages {
            let data = try await authorizedGET(url: url, token: accessToken, session: session)
            let messages: [TeamsChatMessage] = try decodeValueArray(from: data)
            allMessages.append(contentsOf: messages)

            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let nextLink = json["@odata.nextLink"] as? String,
               let next = URL(string: nextLink) {
                nextURL = next
            } else {
                nextURL = nil
            }
            page += 1
        }
        return allMessages
    }

    // MARK: - Channel Files

    /// List files in a Teams channel's shared files folder.
    /// First fetches the channel's filesFolder DriveItem, then lists its children.
    static func listChannelFiles(
        teamId: String,
        channelId: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        // Step 1: Get the channel's filesFolder to find the driveId and itemId
        let folderURL = try graphURL("teams/\(teamId)/channels/\(channelId)/filesFolder")
        let folderData = try await authorizedGET(url: folderURL, token: accessToken, session: session)

        guard let folderJSON = try? JSONSerialization.jsonObject(with: folderData) as? [String: Any],
              let parentRef = folderJSON["parentReference"] as? [String: Any],
              let driveId = parentRef["driveId"] as? String,
              let folderId = folderJSON["id"] as? String else {
            return []
        }

        // Step 2: List files in that folder
        let childrenURLString = "\(M365Config.graphBaseURL)/drives/\(driveId)/items/\(folderId)/children?$top=100"
        guard let childrenURL = URL(string: childrenURLString) else {
            throw GraphTeamsError.invalidURL(childrenURLString)
        }
        let childrenData = try await authorizedGET(url: childrenURL, token: accessToken, session: session)
        let items: [GraphDriveItem] = try decodeValueArray(from: childrenData)
        return items
    }

    // MARK: - Send Messages

    /// Send a message to a Teams channel.
    @discardableResult
    static func sendChannelMessage(
        teamId: String,
        channelId: String,
        content: String,
        contentType: String = "html",
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> TeamsChatMessage {
        let url = try graphURL("teams/\(teamId)/channels/\(channelId)/messages")
        let body: [String: Any] = [
            "body": [
                "contentType": contentType,
                "content": content
            ]
        ]
        let data = try await authorizedPOST(url: url, body: body, token: accessToken, session: session)
        return try JSONDecoder().decode(TeamsChatMessage.self, from: data)
    }

    /// Send a message to a 1:1 or group chat.
    @discardableResult
    static func sendChatMessage(
        chatId: String,
        content: String,
        contentType: String = "html",
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> TeamsChatMessage {
        let url = try graphURL("me/chats/\(chatId)/messages")
        let body: [String: Any] = [
            "body": [
                "contentType": contentType,
                "content": content
            ]
        ]
        let data = try await authorizedPOST(url: url, body: body, token: accessToken, session: session)
        return try JSONDecoder().decode(TeamsChatMessage.self, from: data)
    }

    // MARK: - User Profiles

    /// Fetch a user's profile (displayName, jobTitle, department, mail).
    static func fetchUserProfile(
        userId: String,
        accessToken: String,
        session: URLSession = .shared
    ) async -> GraphUserProfile? {
        let urlString = "\(M365Config.graphBaseURL)/users/\(userId)?$select=id,displayName,jobTitle,department,mail"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(GraphUserProfile.self, from: data)
    }

    // MARK: - User Photos

    /// Fetch a user's profile photo as raw image data (JPEG/PNG).
    /// Returns nil if the user has no photo set.
    static func fetchUserPhoto(
        userId: String,
        accessToken: String,
        session: URLSession = .shared
    ) async -> Data? {
        let urlString = "\(M365Config.graphBaseURL)/users/\(userId)/photo/$value"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        return data
    }

    // MARK: - Presence

    /// Fetch presence status for multiple users in a single batch request.
    static func batchGetPresence(
        userIds: [String],
        accessToken: String,
        session: URLSession = .shared
    ) async -> [GraphPresenceResponse] {
        guard !userIds.isEmpty else { return [] }

        let urlString = "\(M365Config.graphBaseURL)/communications/getPresencesByUserId"
        guard let url = URL(string: urlString) else { return [] }

        let body: [String: Any] = ["ids": userIds]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return []
        }

        // Decode the "value" array
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valueArray = json["value"],
              let valueData = try? JSONSerialization.data(withJSONObject: valueArray),
              let presences = try? JSONDecoder().decode([GraphPresenceResponse].self, from: valueData) else {
            return []
        }
        return presences
    }

    /// Fetch own presence status.
    static func getMyPresence(
        accessToken: String,
        session: URLSession = .shared
    ) async -> GraphPresenceResponse? {
        let urlString = "\(M365Config.graphBaseURL)/me/presence"
        guard let url = URL(string: urlString) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode) else {
            return nil
        }
        return try? JSONDecoder().decode(GraphPresenceResponse.self, from: data)
    }

    // MARK: - Helpers

    private static func graphURL(_ path: String) throws -> URL {
        let urlString = "\(M365Config.graphBaseURL)/\(path)"
        guard let url = URL(string: urlString) else {
            throw GraphTeamsError.invalidURL(urlString)
        }
        return url
    }

    private static func authorizedGET(
        url: URL,
        token: String,
        session: URLSession
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    private static func authorizedPOST(
        url: URL,
        body: [String: Any],
        token: String,
        session: URLSession
    ) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)
        return data
    }

    /// Decode the "value" array from a Graph API list response without using a generic wrapper.
    /// This avoids Swift 6 strict concurrency issues with synthesized Decodable conformance
    /// being inferred as MainActor-isolated when the element type is used in @MainActor code.
    private static func decodeValueArray<T: Decodable>(from data: Data) throws -> [T] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valueArray = json["value"] else {
            throw GraphTeamsError.invalidResponse
        }
        let valueData = try JSONSerialization.data(withJSONObject: valueArray)
        return try JSONDecoder().decode([T].self, from: valueData)
    }

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphTeamsError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GraphTeamsError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}
