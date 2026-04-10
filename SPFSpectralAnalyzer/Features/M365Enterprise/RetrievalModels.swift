import Foundation

// MARK: - Data Sources

/// Microsoft 365 Copilot Retrieval API data sources.
/// Maps to the documented `dataSource` field in the Retrieval API request.
enum RetrievalDataSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case sharePoint
    case oneDriveBusiness
    case externalItem

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sharePoint: return "SharePoint"
        case .oneDriveBusiness: return "OneDrive"
        case .externalItem: return "Copilot Connectors"
        }
    }

    var iconName: String {
        switch self {
        case .sharePoint: return "building.columns.fill"
        case .oneDriveBusiness: return "cloud.fill"
        case .externalItem: return "link.circle.fill"
        }
    }
}

// MARK: - Request Models

/// Request body for POST /v1.0/copilot/retrieval.
/// Matches Microsoft's documented API schema.
struct RetrievalRequest: Codable, Sendable {
    let queryString: String
    let dataSource: RetrievalDataSource
    let filterExpression: String?
    let resourceMetadata: [String]?
    let maximumNumberOfResults: Int?

    init(
        queryString: String,
        dataSource: RetrievalDataSource,
        filterExpression: String? = nil,
        resourceMetadata: [String]? = ["title", "author"],
        maximumNumberOfResults: Int? = 10
    ) {
        self.queryString = queryString
        self.dataSource = dataSource
        self.filterExpression = filterExpression
        self.resourceMetadata = resourceMetadata
        self.maximumNumberOfResults = maximumNumberOfResults
    }
}

// MARK: - Response Models

/// Top-level response from the Retrieval API.
struct RetrievalResponse: Codable, Sendable {
    let retrievalHits: [RetrievalHit]?

    /// Safe accessor that returns an empty array if hits are nil.
    var hits: [RetrievalHit] { retrievalHits ?? [] }
}

/// A single retrieval result with document metadata, extracts, and sensitivity info.
struct RetrievalHit: Codable, Identifiable, Sendable {
    var id: String { webUrl ?? UUID().uuidString }

    let webUrl: String?
    let resourceType: String?
    let resourceMetadata: [String: String]?
    let extracts: [RetrievalExtract]?
    let sensitivityLabel: SensitivityLabel?

    /// Document title from metadata, or a fallback.
    var title: String {
        resourceMetadata?["title"] ?? "Untitled Document"
    }

    /// Document author from metadata, if available.
    var author: String? {
        resourceMetadata?["author"]
    }

    /// Combined extract text for use as grounding context.
    var combinedExtractText: String {
        (extracts ?? []).compactMap(\.text).joined(separator: "\n")
    }
}

/// A text extract from a retrieved document with relevance score.
struct RetrievalExtract: Codable, Sendable {
    let text: String?
    let relevanceScore: Double?
}

/// Microsoft Information Protection sensitivity label.
struct SensitivityLabel: Codable, Sendable {
    let sensitivityLabelId: String?
    let displayName: String?
    let toolTip: String?
    let priority: Int?
    let color: String?
}

// MARK: - Graph Batch Models

/// Batch request wrapper for Graph $batch endpoint.
/// Microsoft documents support for up to 20 Retrieval API requests per batch.
struct GraphBatchRequest: Codable, Sendable {
    let requests: [GraphBatchItem]
}

struct GraphBatchItem: Codable, Sendable {
    let id: String
    let method: String
    let url: String
    let body: RetrievalRequest
    let headers: [String: String]
}

struct GraphBatchResponse: Codable, Sendable {
    let responses: [GraphBatchResponseItem]?

    var items: [GraphBatchResponseItem] { responses ?? [] }
}

struct GraphBatchResponseItem: Codable, Sendable {
    let id: String
    let status: Int
    let headers: [String: String]?
    let body: RetrievalResponse?
}

// MARK: - Grounding Citation

/// A citation extracted from a retrieval hit, ready for UI display.
struct GroundingCitation: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let author: String?
    let extractText: String
    let relevanceScore: Double?
    let webUrl: String?
    let dataSource: RetrievalDataSource
    let sensitivityLabel: SensitivityLabel?

    /// Create a citation from a RetrievalHit and its source.
    init(hit: RetrievalHit, dataSource: RetrievalDataSource) {
        self.title = hit.title
        self.author = hit.author
        self.extractText = hit.combinedExtractText
        self.relevanceScore = hit.extracts?.first?.relevanceScore
        self.webUrl = hit.webUrl
        self.dataSource = dataSource
        self.sensitivityLabel = hit.sensitivityLabel
    }
}

// MARK: - Service Errors

enum RetrievalServiceError: LocalizedError, Sendable {
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case emptyToken
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The Graph response was not a valid HTTP response."
        case .httpError(let statusCode, let body):
            return "Graph request failed with HTTP \(statusCode): \(body)"
        case .emptyToken:
            return "No access token is available. Please sign in to Microsoft 365."
        case .notConfigured:
            return "Microsoft 365 is not configured. Set Client ID and Tenant ID in Settings."
        }
    }
}
