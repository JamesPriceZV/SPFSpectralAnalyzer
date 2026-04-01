import Foundation

// MARK: - Graph Upload Service

/// Stateless service for uploading files to SharePoint/OneDrive via Microsoft Graph.
/// Supports small file PUT (< 4 MB) and large file upload sessions with chunked upload.
enum GraphUploadService {
    // MARK: - Constants

    /// Maximum file size for simple PUT upload (4 MB).
    static let smallFileThreshold = 4 * 1024 * 1024

    /// Chunk size for large file upload sessions (3.75 MB, must be multiple of 320 KiB).
    static let uploadChunkSize = 320 * 1024 * 12 // 3,932,160 bytes

    // MARK: - Upload Entry Point

    /// Upload a file to a SharePoint site's document library.
    /// Automatically selects small-file PUT or large-file upload session based on size.
    /// - Parameters:
    ///   - fileData: The raw file content to upload.
    ///   - fileName: Destination file name (e.g., "2024-03-31_Analysis.pdf").
    ///   - sitePath: SharePoint site path (e.g., "zincoverde.sharepoint.com:/sites/Lab").
    ///   - folderPath: Folder within the document library (e.g., "/Results/March").
    ///   - token: Valid Microsoft Graph access token with Files.ReadWrite.All scope.
    ///   - session: URLSession to use for requests.
    ///   - onProgress: Optional progress callback (0.0 ... 1.0).
    /// - Returns: The uploaded DriveItem metadata.
    static func upload(
        fileData: Data,
        fileName: String,
        sitePath: String,
        folderPath: String,
        token: String,
        session: URLSession = .shared,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> GraphDriveItem {
        if fileData.count <= smallFileThreshold {
            return try await uploadSmall(
                fileData: fileData,
                fileName: fileName,
                sitePath: sitePath,
                folderPath: folderPath,
                token: token,
                session: session
            )
        } else {
            return try await uploadLarge(
                fileData: fileData,
                fileName: fileName,
                sitePath: sitePath,
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
        sitePath: String,
        folderPath: String,
        token: String,
        session: URLSession
    ) async throws -> GraphDriveItem {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath
        let encodedFileName = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        let urlString = "\(M365Config.graphBaseURL)/sites/\(sitePath)/drive/root:/\(encodedPath)/\(encodedFileName):/content"
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
        sitePath: String,
        folderPath: String,
        token: String,
        session: URLSession,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> GraphDriveItem {
        // Step 1: Create upload session
        let sessionURL = try await createUploadSession(
            fileName: fileName,
            sitePath: sitePath,
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
        sitePath: String,
        folderPath: String,
        token: String,
        session: URLSession
    ) async throws -> URL {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath
        let encodedFileName = fileName
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? fileName

        let urlString = "\(M365Config.graphBaseURL)/sites/\(sitePath)/drive/root:/\(encodedPath)/\(encodedFileName):/createUploadSession"
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

    /// List items in a SharePoint folder (for folder browser UI).
    static func listFolder(
        sitePath: String,
        folderPath: String,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GraphDriveItem] {
        let encodedPath = folderPath
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? folderPath

        let urlString: String
        if encodedPath.isEmpty {
            urlString = "\(M365Config.graphBaseURL)/sites/\(sitePath)/drive/root/children"
        } else {
            urlString = "\(M365Config.graphBaseURL)/sites/\(sitePath)/drive/root:/\(encodedPath):/children"
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
        }
    }
}
