import Foundation

// MARK: - SharePoint Site Info

/// Resolved SharePoint site information from Microsoft Graph.
struct SharePointSiteInfo: Sendable {
    let siteId: String        // composite "host,guid,guid"
    let displayName: String   // e.g. "Zincoverde" or "Lab Site"
    let webUrl: String        // for display
}

// MARK: - Graph Upload Service

/// Stateless service for uploading files to SharePoint/OneDrive via Microsoft Graph.
/// Supports small file PUT (< 4 MB) and large file upload sessions with chunked upload.
enum GraphUploadService {
    // MARK: - Constants

    /// Maximum file size for simple PUT upload (4 MB).
    static let smallFileThreshold = 4 * 1024 * 1024

    /// Chunk size for large file upload sessions (3.75 MB, must be multiple of 320 KiB).
    static let uploadChunkSize = 320 * 1024 * 12 // 3,932,160 bytes

    // MARK: - SharePoint Site Resolution

    /// Parse any user-provided SharePoint URL or path and resolve it to a Graph API site ID.
    ///
    /// Accepts various formats:
    /// - Full URL: `https://tenant.sharepoint.com/_layouts/15/sharepoint.aspx?...`
    /// - Site URL: `https://tenant.sharepoint.com/sites/SiteName`
    /// - Hostname only: `tenant.sharepoint.com`
    /// - Path format: `tenant.sharepoint.com:/sites/SiteName`
    ///
    /// - Parameters:
    ///   - userInput: The raw user-entered SharePoint URL or site path.
    ///   - token: Valid Microsoft Graph access token with Sites.Read.All scope.
    ///   - session: URLSession to use for requests.
    /// - Returns: Resolved site information including composite site ID.
    static func resolveSiteId(
        from userInput: String,
        token: String,
        session: URLSession = .shared
    ) async throws -> SharePointSiteInfo {
        let (hostname, sitePath) = parseSharePointInput(userInput)

        guard !hostname.isEmpty else {
            throw GraphUploadError.invalidSharePointURL(userInput)
        }

        // Build Graph API URL for site resolution
        let urlString: String
        if let sitePath, !sitePath.isEmpty {
            let encodedPath = sitePath
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? sitePath
            urlString = "\(M365Config.graphBaseURL)/sites/\(hostname):/\(encodedPath)"
        } else {
            urlString = "\(M365Config.graphBaseURL)/sites/\(hostname)"
        }

        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let siteResponse = try JSONDecoder().decode(GraphSiteResponse.self, from: data)
        return SharePointSiteInfo(
            siteId: siteResponse.id,
            displayName: siteResponse.displayName ?? siteResponse.name ?? hostname,
            webUrl: siteResponse.webUrl ?? ""
        )
    }

    /// Parse user input into hostname and optional site-relative path.
    ///
    /// Handles:
    /// - `https://tenant.sharepoint.com/_layouts/15/...` → ("tenant.sharepoint.com", nil)
    /// - `https://tenant.sharepoint.com/sites/Lab` → ("tenant.sharepoint.com", "sites/Lab")
    /// - `https://tenant.sharepoint.com/teams/Project` → ("tenant.sharepoint.com", "teams/Project")
    /// - `tenant.sharepoint.com:/sites/Lab` → ("tenant.sharepoint.com", "sites/Lab")
    /// - `tenant.sharepoint.com` → ("tenant.sharepoint.com", nil)
    static func parseSharePointInput(_ input: String) -> (hostname: String, sitePath: String?) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)

        // Handle colon-separated format: hostname:/sites/path
        if let colonRange = trimmed.range(of: ":/") {
            let hostname = String(trimmed[trimmed.startIndex..<colonRange.lowerBound])
                .replacingOccurrences(of: "https://", with: "")
                .replacingOccurrences(of: "http://", with: "")
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let path = String(trimmed[colonRange.upperBound...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return (hostname, path.isEmpty ? nil : path)
        }

        // Handle full URL format
        if trimmed.contains("://") {
            guard let components = URLComponents(string: trimmed) else {
                return ("", nil)
            }
            let hostname = components.host ?? ""
            let urlPath = components.path

            // Ignore SharePoint system paths
            let systemPrefixes = ["/_layouts/", "/_api/", "/_vti_bin/", "/personal/"]
            for prefix in systemPrefixes {
                if urlPath.hasPrefix(prefix) {
                    return (hostname, nil)  // root site
                }
            }

            // Extract /sites/X or /teams/X
            let segments = urlPath.split(separator: "/", omittingEmptySubsequences: true)
            if segments.count >= 2 {
                let firstSegment = segments[0].lowercased()
                if firstSegment == "sites" || firstSegment == "teams" {
                    let sitePath = "\(segments[0])/\(segments[1])"
                    return (hostname, sitePath)
                }
            }

            // No recognized site path — treat as root
            return (hostname, nil)
        }

        // Bare hostname
        let hostname = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return (hostname, nil)
    }

    // MARK: - Site Enumeration

    /// Search for available SharePoint sites in the tenant.
    /// Requires `Sites.Read.All` scope.
    /// - Parameters:
    ///   - query: The search query (use "*" to list all sites).
    ///   - token: Valid Microsoft Graph access token.
    ///   - session: URLSession to use for requests.
    /// - Returns: Array of matching site responses.
    static func searchSites(
        query: String,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphSiteResponse] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        let urlString = "\(M365Config.graphBaseURL)/sites?search=\(encodedQuery)&$top=100"
        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        // Decode value array manually to avoid generic Sendable issues
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let valueArray = json["value"] else {
            return []
        }
        let valueData = try JSONSerialization.data(withJSONObject: valueArray)
        return try JSONDecoder().decode([GraphSiteResponse].self, from: valueData)
    }

    // MARK: - Upload Entry Point

    /// Upload a file to a SharePoint site's document library.
    /// Automatically selects small-file PUT or large-file upload session based on size.
    /// - Parameters:
    ///   - fileData: The raw file content to upload.
    ///   - fileName: Destination file name (e.g., "2024-03-31_Analysis.pdf").
    ///   - siteId: Resolved SharePoint site ID (composite format from `resolveSiteId`).
    ///   - folderPath: Folder within the document library (e.g., "/Results/March").
    ///   - token: Valid Microsoft Graph access token with Files.ReadWrite.All scope.
    ///   - session: URLSession to use for requests.
    ///   - onProgress: Optional progress callback (0.0 ... 1.0).
    /// - Returns: The uploaded DriveItem metadata.
    static func upload(
        fileData: Data,
        fileName: String,
        siteId: String,
        folderPath: String,
        token: String,
        session: URLSession = .shared,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> GraphDriveItem {
        if fileData.count <= smallFileThreshold {
            return try await uploadSmall(
                fileData: fileData,
                fileName: fileName,
                siteId: siteId,
                folderPath: folderPath,
                token: token,
                session: session
            )
        } else {
            return try await uploadLarge(
                fileData: fileData,
                fileName: fileName,
                siteId: siteId,
                folderPath: folderPath,
                token: token,
                session: session,
                onProgress: onProgress
            )
        }
    }

    // MARK: - Small File Upload (PUT)

    /// Upload a file under 4 MB using a simple PUT request.
    private static func uploadSmall(
        fileData: Data,
        fileName: String,
        siteId: String,
        folderPath: String,
        token: String,
        session: URLSession
    ) async throws -> GraphDriveItem {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath
        let encodedFileName = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        let urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root:/\(encodedPath)/\(encodedFileName):/content"
        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.httpBody = fileData

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        return try JSONDecoder().decode(GraphDriveItem.self, from: data)
    }

    // MARK: - Large File Upload Session

    /// Upload a file over 4 MB using an upload session with chunked transfer.
    private static func uploadLarge(
        fileData: Data,
        fileName: String,
        siteId: String,
        folderPath: String,
        token: String,
        session: URLSession,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> GraphDriveItem {
        // Step 1: Create upload session
        let sessionURL = try await createUploadSession(
            fileName: fileName,
            siteId: siteId,
            folderPath: folderPath,
            token: token,
            session: session
        )

        // Step 2: Upload chunks
        let totalSize = fileData.count
        var offset = 0

        while offset < totalSize {
            let chunkEnd = min(offset + uploadChunkSize, totalSize)
            let chunkData = fileData[offset..<chunkEnd]

            let contentRange = "bytes \(offset)-\(chunkEnd - 1)/\(totalSize)"

            var request = URLRequest(url: sessionURL)
            request.httpMethod = "PUT"
            request.setValue(contentRange, forHTTPHeaderField: "Content-Range")
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            request.setValue("\(chunkData.count)", forHTTPHeaderField: "Content-Length")
            request.httpBody = chunkData

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw GraphUploadError.invalidResponse
            }

            if httpResponse.statusCode == 200 || httpResponse.statusCode == 201 {
                // Final chunk — response contains the completed DriveItem
                let item = try JSONDecoder().decode(GraphDriveItem.self, from: data)
                onProgress?(1.0)
                return item
            } else if httpResponse.statusCode == 202 {
                // Accepted — more chunks to send
                offset = chunkEnd
                let progress = Double(offset) / Double(totalSize)
                onProgress?(progress)
            } else {
                let body = String(data: data, encoding: .utf8) ?? ""
                throw GraphUploadError.httpError(statusCode: httpResponse.statusCode, body: body)
            }
        }

        throw GraphUploadError.uploadIncomplete
    }

    /// Create an upload session for large file uploads.
    private static func createUploadSession(
        fileName: String,
        siteId: String,
        folderPath: String,
        token: String,
        session: URLSession
    ) async throws -> URL {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath
        let encodedFileName = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        let urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root:/\(encodedPath)/\(encodedFileName):/createUploadSession"
        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        let body: [String: Any] = [
            "item": [
                "@microsoft.graph.conflictBehavior": "rename",
                "name": fileName
            ]
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let sessionResponse = try JSONDecoder().decode(UploadSessionResponse.self, from: data)
        guard let sessionURL = URL(string: sessionResponse.uploadUrl) else {
            throw GraphUploadError.invalidURL(sessionResponse.uploadUrl)
        }
        return sessionURL
    }

    // MARK: - List Folder Contents

    /// List items in a SharePoint folder by path (for folder browser UI).
    static func listFolder(
        siteId: String,
        folderPath: String,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath

        let urlString: String
        if encodedPath.isEmpty {
            urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root/children"
        } else {
            urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root:/\(encodedPath):/children"
        }

        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder().decode(GraphDriveItemList.self, from: data)
        return listResponse.value
    }

    // MARK: - OneDrive Folder Listing

    /// List items in the signed-in user's OneDrive root or a specific folder.
    /// - Parameters:
    ///   - folderItemId: The DriveItem id of the folder to list, or nil for root.
    ///   - token: Valid Microsoft Graph access token with Files.Read.All scope.
    ///   - session: URLSession to use for requests.
    /// - Returns: Array of items (files and folders) in the specified folder.
    static func listOneDriveFolder(
        folderItemId: String? = nil,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        let urlString: String
        if let folderItemId {
            urlString = "\(M365Config.graphBaseURL)/me/drive/items/\(folderItemId)/children?$top=200&$orderby=name"
        } else {
            urlString = "\(M365Config.graphBaseURL)/me/drive/root/children?$top=200&$orderby=name"
        }

        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder().decode(GraphDriveItemList.self, from: data)
        return listResponse.value
    }

    // MARK: - SharePoint Folder Listing (by Item ID)

    /// List items in a SharePoint folder by item ID.
    static func listSharePointFolder(
        siteId: String,
        folderItemId: String? = nil,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        let urlString: String
        if let folderItemId {
            urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/items/\(folderItemId)/children?$top=200&$orderby=name"
        } else {
            urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root/children?$top=200&$orderby=name"
        }

        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder().decode(GraphDriveItemList.self, from: data)
        return listResponse.value
    }

    // MARK: - Drive Search

    /// Search files in OneDrive or a SharePoint site's document library.
    /// - Parameters:
    ///   - query: The search query string.
    ///   - siteId: Optional resolved SharePoint site ID. When nil, searches user's OneDrive.
    ///   - token: Valid Microsoft Graph access token.
    ///   - session: URLSession to use for requests.
    /// - Returns: Array of matching drive items.
    static func searchDriveItems(
        query: String,
        siteId: String? = nil,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query

        let urlString: String
        if let siteId {
            urlString = "\(M365Config.graphBaseURL)/sites/\(siteId)/drive/root/search(q='\(encodedQuery)')?$top=50"
        } else {
            urlString = "\(M365Config.graphBaseURL)/me/drive/root/search(q='\(encodedQuery)')?$top=50"
        }

        guard let url = URL(string: urlString) else {
            throw GraphUploadError.invalidURL(urlString)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        try validateResponse(response, data: data)

        let listResponse = try JSONDecoder().decode(GraphDriveItemList.self, from: data)
        return listResponse.value
    }

    // MARK: - Helpers

    private static func validateResponse(_ response: URLResponse, data: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw GraphUploadError.invalidResponse
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw GraphUploadError.httpError(statusCode: httpResponse.statusCode, body: body)
        }
    }
}

// MARK: - Response Models

/// Upload session creation response.
private struct UploadSessionResponse: Codable, Sendable {
    let uploadUrl: String
    let expirationDateTime: String?
}

/// SharePoint site response from `GET /sites/{id}`.
struct GraphSiteResponse: Codable, Sendable {
    let id: String
    let displayName: String?
    let name: String?
    let webUrl: String?
}

/// DriveItem returned by Microsoft Graph after upload or from folder listing.
struct GraphDriveItem: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let size: Int?
    let webUrl: String?
    let createdDateTime: String?
    let lastModifiedDateTime: String?
    let folder: FolderFacet?
    let file: FileFacet?

    var isFolder: Bool { folder != nil }

    struct FolderFacet: Codable, Sendable {
        let childCount: Int?
    }

    struct FileFacet: Codable, Sendable {
        let mimeType: String?
    }
}

/// Response wrapper for listing folder children.
struct GraphDriveItemList: Codable, Sendable {
    let value: [GraphDriveItem]
}

// MARK: - Errors

enum GraphUploadError: LocalizedError, Sendable {
    case invalidURL(String)
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case uploadIncomplete
    case notAuthenticated
    case exportDisabled
    case invalidSharePointURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url):
            return "Invalid Graph API URL: \(url)"
        case .invalidResponse:
            return "Invalid response from Microsoft Graph"
        case .httpError(let code, let body):
            return "Graph API error \(code): \(body.prefix(200))"
        case .uploadIncomplete:
            return "Upload session ended without completing"
        case .notAuthenticated:
            return "Not authenticated with Microsoft 365"
        case .exportDisabled:
            return "SharePoint export is not enabled in settings"
        case .invalidSharePointURL(let input):
            return "Could not parse SharePoint URL: \(input). Try pasting a SharePoint site URL or entering your-tenant.sharepoint.com"
        }
    }
}
