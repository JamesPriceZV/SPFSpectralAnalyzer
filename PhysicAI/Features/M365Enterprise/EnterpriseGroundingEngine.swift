import Foundation

// MARK: - Enterprise Grounding Engine

/// Orchestrates Microsoft 365 enterprise grounding for AI analysis.
/// Converts spectral findings or formula data into Retrieval API queries,
/// fetches enterprise context, and injects it into AI provider prompts.
@MainActor @Observable
final class EnterpriseGroundingEngine {
    /// Citations from the most recent grounding retrieval.
    private(set) var citations: [GroundingCitation] = []

    /// Whether a grounding retrieval is currently in progress.
    private(set) var isLoading = false

    /// Last error from a grounding attempt.
    private(set) var lastError: String?

    /// The query that was most recently used for grounding.
    private(set) var lastQuery: String?

    // MARK: - Spectral Analysis Query Generation

    /// Generate a single-sentence Retrieval API query from spectral analysis findings.
    /// Microsoft documents that queryString should be a single sentence with context-rich keywords.
    nonisolated func generateSpectralQuery(
        criticalWavelength: Double?,
        uvaUvbRatio: Double?,
        meanUVBTransmittance: Double?,
        spfEstimate: Double?,
        productName: String?,
        analysisPreset: String?
    ) -> String {
        var components: [String] = []

        if let preset = analysisPreset, !preset.isEmpty {
            components.append("for \(preset) analysis")
        }

        if let cw = criticalWavelength {
            components.append("critical wavelength \(String(format: "%.0f", cw))nm")
        }

        if let ratio = uvaUvbRatio {
            components.append("UVA/UVB ratio \(String(format: "%.2f", ratio))")
        }

        if let transmittance = meanUVBTransmittance {
            components.append("mean UVB transmittance \(String(format: "%.1f", transmittance))%")
        }

        if let spf = spfEstimate {
            components.append("estimated SPF \(String(format: "%.0f", spf))")
        }

        if let product = productName, !product.isEmpty {
            components.append("product \(product)")
        }

        if components.isEmpty {
            return "Find SOPs, protocols, and internal reports related to UV spectral sunscreen analysis on PMMA plates"
        }

        return "Find SOPs, protocols, and reports related to UV spectral analysis \(components.joined(separator: ", "))"
    }

    // MARK: - Formula Card Query Generation

    /// Generate a Retrieval API query from formula card ingredients.
    nonisolated func generateFormulaQuery(
        ingredientNames: [String],
        productName: String?
    ) -> String {
        let topIngredients = ingredientNames.prefix(5).joined(separator: ", ")

        if let product = productName, !product.isEmpty {
            return "Find formulation specifications and SOPs for \(product) containing \(topIngredients)"
        }

        return "Find formulation specifications and SOPs for sunscreen formulations containing \(topIngredients)"
    }

    // MARK: - Fetch Grounding Context

    /// Fetch enterprise grounding context from M365 Retrieval API.
    /// Returns formatted context text ready for injection into an AI prompt.
    func fetchGroundingContext(
        query: String,
        config: EnterpriseGroundingConfig,
        authManager: MSALAuthManager
    ) async throws -> String {
        isLoading = true
        lastError = nil
        lastQuery = query
        defer { isLoading = false }

        // Acquire token with the appropriate scopes
        let token = try await authManager.acquireToken(scopes: config.requiredScopes)

        // Retrieve from all enabled sources
        let fetchedCitations = try await CopilotRetrievalService.retrieveFromMultipleSources(
            query: query,
            sources: config.enabledDataSources,
            sitePathFilter: config.primarySiteFilter,
            maxResultsPerSource: config.maxResultsPerSource,
            token: token
        )

        citations = fetchedCitations

        Instrumentation.log(
            "Enterprise grounding: \(fetchedCitations.count) citations from \(config.enabledDataSources.count) source(s)",
            area: .aiAnalysis, level: .info
        )

        return formatGroundingContext(citations: fetchedCitations)
    }

    // MARK: - Prompt Enrichment

    /// Build an enriched prompt by injecting enterprise grounding context.
    nonisolated func buildEnrichedPrompt(
        originalPrompt: String,
        groundingContext: String
    ) -> String {
        guard !groundingContext.isEmpty else { return originalPrompt }

        return """
        \(originalPrompt)

        --- ENTERPRISE CONTEXT (from Microsoft 365) ---
        The following excerpts were retrieved from your organization's SharePoint, OneDrive, \
        and connected enterprise systems. Use them as authoritative reference material to \
        ground your analysis in organizational SOPs, protocols, and prior work.

        \(groundingContext)
        --- END ENTERPRISE CONTEXT ---

        When referencing enterprise content in your response, cite the document title and source.
        """
    }

    // MARK: - Clear State

    func clearGrounding() {
        citations = []
        lastError = nil
        lastQuery = nil
    }

    // MARK: - Private

    private func formatGroundingContext(citations: [GroundingCitation]) -> String {
        guard !citations.isEmpty else { return "" }

        return citations.enumerated().map { index, citation in
            var parts: [String] = []
            parts.append("[\(index + 1)] \(citation.title)")
            if let author = citation.author {
                parts.append("   Author: \(author)")
            }
            parts.append("   Source: \(citation.dataSource.displayName)")
            if let score = citation.relevanceScore {
                parts.append("   Relevance: \(String(format: "%.3f", score))")
            }
            if !citation.extractText.isEmpty {
                let truncated = String(citation.extractText.prefix(500))
                parts.append("   Extract: \(truncated)")
            }
            if let url = citation.webUrl {
                parts.append("   URL: \(url)")
            }
            return parts.joined(separator: "\n")
        }.joined(separator: "\n\n")
    }
}
