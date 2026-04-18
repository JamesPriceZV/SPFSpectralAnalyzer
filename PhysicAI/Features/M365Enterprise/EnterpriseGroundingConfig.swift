import Foundation

// MARK: - Enterprise Grounding Configuration

/// User-configurable settings for Microsoft 365 enterprise grounding.
/// Stored as JSON in @AppStorage via M365Config.StorageKeys.groundingConfigJSON.
struct EnterpriseGroundingConfig: Codable, Sendable, Equatable {
    /// Master switch for enterprise grounding.
    var isEnabled: Bool = false

    /// Which M365 data sources to query.
    var enabledDataSources: Set<RetrievalDataSource> = [.sharePoint]

    /// Curated SharePoint site paths for scoped retrieval.
    var sharePointSiteFilters: [String] = []

    /// Maximum results to retrieve per data source.
    var maxResultsPerSource: Int = 10

    /// Whether to apply grounding to spectral analysis.
    var enabledForSpectralAnalysis: Bool = true

    /// Whether to apply grounding to formula card parsing.
    var enabledForFormulaCardParsing: Bool = true

    /// Default configuration.
    static let `default` = EnterpriseGroundingConfig()

    /// Whether grounding is active for a given function.
    func isActiveFor(_ function: AIAppFunction) -> Bool {
        guard isEnabled else { return false }
        switch function {
        case .spectralAnalysis:
            return enabledForSpectralAnalysis
        case .formulaCardParsing:
            return enabledForFormulaCardParsing
        }
    }

    /// The primary site filter (first in the list), if any.
    var primarySiteFilter: String? {
        sharePointSiteFilters.first { !$0.isEmpty }
    }

    /// Required M365 scopes based on enabled data sources.
    var requiredScopes: [String] {
        var scopes = M365Config.retrievalScopes
        if enabledDataSources.contains(.externalItem) {
            scopes = M365Config.retrievalScopesWithConnectors
        }
        return scopes
    }
}

// MARK: - SharePoint Export Configuration

/// Settings for exporting files and results to SharePoint.
/// Stored as JSON in @AppStorage via M365Config.StorageKeys.exportConfigJSON.
struct SharePointExportConfig: Codable, Sendable, Equatable {
    /// Whether SharePoint export is enabled.
    var isEnabled: Bool = false

    /// Default destination site URL.
    var destinationSitePath: String = ""

    /// Folder path within the site for uploads.
    var destinationFolderPath: String = ""

    /// Naming template for uploaded files (supports placeholders).
    var namingTemplate: String = "{date}_{product}_{type}"

    /// Whether to auto-export analysis results when analysis completes.
    var autoExportResults: Bool = false

    /// Default configuration.
    static let `default` = SharePointExportConfig()
}
