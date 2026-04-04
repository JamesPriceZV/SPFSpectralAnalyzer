import Foundation

// MARK: - M365 Configuration

/// Central configuration for Microsoft 365 Copilot integration.
/// Client ID and Tenant ID are stored in @AppStorage and editable in Settings.
/// Update the placeholders once your Entra app registration is resolved.
enum M365Config {
    // MARK: - PLACEHOLDER — Replace with your Entra app registration values
    static let defaultClientId = "PLACEHOLDER_CLIENT_ID"
    static let defaultTenantId = "PLACEHOLDER_TENANT_ID"

    /// Microsoft identity platform authority URL.
    static func authority(tenantId: String) -> String {
        "https://login.microsoftonline.com/\(tenantId)"
    }

    /// Microsoft Graph base URL for v1.0 API calls.
    static let graphBaseURL = URL(string: "https://graph.microsoft.com/v1.0")!

    // MARK: - Delegated Permission Scopes

    /// Minimum scopes for Retrieval API (SharePoint + OneDrive).
    static let retrievalScopes = [
        "Files.Read.All",
        "Sites.Read.All"
    ]

    /// Extended scopes including Copilot Connectors (externalItem).
    static let retrievalScopesWithConnectors = [
        "Files.Read.All",
        "Sites.Read.All",
        "ExternalItem.Read.All"
    ]

    /// Full scopes including SharePoint write access for export.
    static let exportScopes = [
        "Files.Read.All",
        "Files.ReadWrite.All",
        "Sites.Read.All",
        "ExternalItem.Read.All"
    ]

    /// Scopes for Microsoft Teams integration (chat, channels, activity).
    static let teamsScopes = [
        "Chat.ReadWrite",
        "Channel.ReadBasic.All",
        "ChannelMessage.Send",
        "Team.ReadBasic.All",
        "ChatMessage.Send"
    ]

    /// Extended scopes for Teams sync (includes message history + file access).
    static let teamsSyncScopes = [
        "Chat.ReadWrite",
        "Channel.ReadBasic.All",
        "ChannelMessage.Send",
        "ChannelMessage.Read.All",
        "Team.ReadBasic.All",
        "ChatMessage.Send",
        "ChatMessage.Read",
        "Files.Read.All"
    ]

    /// Combined scopes for full M365 integration (files + Teams).
    static let fullScopes = Array(Set(exportScopes + teamsScopes))

    // MARK: - Redirect URI

    /// MSAL redirect URI derived from the app's bundle identifier.
    static var redirectURI: String {
        let bundleId = Bundle.main.bundleIdentifier ?? "com.zincoverde.SPFSpectralAnalyzer"
        return "msauth.\(bundleId)://auth"
    }

    // MARK: - AppStorage Keys

    enum StorageKeys {
        static let clientId = "m365ClientId"
        static let tenantId = "m365TenantId"
        static let enterpriseGroundingEnabled = "m365EnterpriseGroundingEnabled"
        static let groundingConfigJSON = "m365GroundingConfigJSON"
        static let exportConfigJSON = "m365ExportConfigJSON"
        static let sharePointSiteFiltersJSON = "m365SharePointSiteFiltersJSON"
    }

    /// Storage keys for Teams sync configuration.
    enum TeamsSyncKeys {
        static let syncEnabled = "teamsSyncEnabled"
        static let pollingIntervalMinutes = "teamsSyncPollingIntervalMinutes"
        static let lastSyncTimestamp = "teamsLastSyncTimestamp"
        static let notificationsEnabled = "teamsSyncNotificationsEnabled"
    }
}
