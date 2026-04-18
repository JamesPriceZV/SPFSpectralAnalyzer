import Foundation

// MARK: - Copilot Retrieval Service

/// Stateless service for calling the Microsoft 365 Copilot Retrieval API via Graph REST.
/// Calls POST /v1.0/copilot/retrieval with delegated user tokens.
enum CopilotRetrievalService {

    // MARK: - Single Retrieval

    /// Execute a single retrieval request against the Copilot Retrieval API.
    static func retrieve(
        _ request: RetrievalRequest,
        token: String,
        session: URLSession = .shared
    ) async throws -> RetrievalResponse {
        guard !token.isEmpty else { throw RetrievalServiceError.emptyToken }

        let url = M365Config.graphBaseURL.appendingPathComponent("copilot/retrieval")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (data, response) = try await session.data(for: urlRequest)
        return try decodeResponse(data: data, response: response)
    }

    // MARK: - Batch Retrieval

    /// Execute multiple retrieval requests in a single Graph $batch call.
    /// Microsoft documents support for up to 20 requests per batch.
    static func retrieveBatch(
        _ requests: [RetrievalRequest],
        token: String,
        session: URLSession = .shared
    ) async throws -> [RetrievalResponse] {
        guard !token.isEmpty else { throw RetrievalServiceError.emptyToken }
        guard !requests.isEmpty else { return [] }

        let url = M365Config.graphBaseURL.appendingPathComponent("$batch")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let items = requests.enumerated().map { index, item in
            GraphBatchItem(
                id: String(index + 1),
                method: "POST",
                url: "/copilot/retrieval",
                body: item,
                headers: ["Content-Type": "application/json"]
            )
        }

        urlRequest.httpBody = try JSONEncoder().encode(GraphBatchRequest(requests: items))

        let (data, response) = try await session.data(for: urlRequest)

        guard let http = response as? HTTPURLResponse else {
            throw RetrievalServiceError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RetrievalServiceError.httpError(statusCode: http.statusCode, body: body)
        }

        let batchResponse = try JSONDecoder().decode(GraphBatchResponse.self, from: data)
        return batchResponse.items
            .sorted { $0.id < $1.id }
            .compactMap(\.body)
    }

    // MARK: - Convenience: SharePoint

    /// Retrieve enterprise content from SharePoint with optional site-scoped filtering.
    static func retrieveFromSharePoint(
        query: String,
        sitePathFilter: String? = nil,
        maxResults: Int = 10,
        token: String,
        session: URLSession = .shared
    ) async throws -> RetrievalResponse {
        let filterExpression: String? = {
            guard let sitePathFilter, !sitePathFilter.isEmpty else { return nil }
            return "path:\"\(sitePathFilter)\""
        }()

        let request = RetrievalRequest(
            queryString: query,
            dataSource: .sharePoint,
            filterExpression: filterExpression,
            resourceMetadata: ["title", "author"],
            maximumNumberOfResults: maxResults
        )
        return try await retrieve(request, token: token, session: session)
    }

    // MARK: - Convenience: OneDrive

    /// Retrieve enterprise content from OneDrive for Business.
    static func retrieveFromOneDrive(
        query: String,
        maxResults: Int = 10,
        token: String,
        session: URLSession = .shared
    ) async throws -> RetrievalResponse {
        let request = RetrievalRequest(
            queryString: query,
            dataSource: .oneDriveBusiness,
            resourceMetadata: ["title", "author"],
            maximumNumberOfResults: maxResults
        )
        return try await retrieve(request, token: token, session: session)
    }

    // MARK: - Convenience: Copilot Connectors

    /// Retrieve enterprise content from Copilot Connectors (external items).
    static func retrieveFromExternalItems(
        query: String,
        maxResults: Int = 10,
        token: String,
        session: URLSession = .shared
    ) async throws -> RetrievalResponse {
        let request = RetrievalRequest(
            queryString: query,
            dataSource: .externalItem,
            resourceMetadata: ["title", "author"],
            maximumNumberOfResults: maxResults
        )
        return try await retrieve(request, token: token, session: session)
    }

    // MARK: - Multi-Source Retrieval

    /// Retrieve from multiple data sources in parallel using Graph $batch.
    /// Returns a flat array of citations from all sources.
    static func retrieveFromMultipleSources(
        query: String,
        sources: Set<RetrievalDataSource>,
        sitePathFilter: String? = nil,
        maxResultsPerSource: Int = 10,
        token: String,
        session: URLSession = .shared
    ) async throws -> [GroundingCitation] {
        guard !sources.isEmpty else { return [] }

        let requests = sources.map { source -> RetrievalRequest in
            let filter: String? = {
                guard source == .sharePoint, let sitePathFilter, !sitePathFilter.isEmpty else { return nil }
                return "path:\"\(sitePathFilter)\""
            }()

            return RetrievalRequest(
                queryString: query,
                dataSource: source,
                filterExpression: filter,
                resourceMetadata: ["title", "author"],
                maximumNumberOfResults: maxResultsPerSource
            )
        }

        let sortedSources = Array(sources).sorted { $0.rawValue < $1.rawValue }
        let responses = try await retrieveBatch(requests, token: token, session: session)

        var citations: [GroundingCitation] = []
        for (index, response) in responses.enumerated() {
            let source = index < sortedSources.count ? sortedSources[index] : .sharePoint
            for hit in response.hits {
                citations.append(GroundingCitation(hit: hit, dataSource: source))
            }
        }

        return citations.sorted { ($0.relevanceScore ?? 0) > ($1.relevanceScore ?? 0) }
    }

    // MARK: - Internal

    private static func decodeResponse(data: Data, response: URLResponse) throws -> RetrievalResponse {
        guard let http = response as? HTTPURLResponse else {
            throw RetrievalServiceError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw RetrievalServiceError.httpError(statusCode: http.statusCode, body: body)
        }

        return try JSONDecoder().decode(RetrievalResponse.self, from: data)
    }
}
