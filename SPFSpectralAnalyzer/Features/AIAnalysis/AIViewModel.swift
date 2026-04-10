import Foundation
import Observation

/// Observable view model that owns AI analysis runtime state.
/// Persisted preferences remain as @AppStorage properties on ContentView
/// because @AppStorage only works inside SwiftUI View types.
@MainActor @Observable
final class AIViewModel {
    // MARK: - AI Provider

    let providerManager = AIProviderManager()

    // MARK: - Runtime State

    var scopeOverride: AISelectionScope?
    var isRunning = false
    var result: AIAnalysisResult?
    var structuredOutput: AIStructuredOutput?
    var errorMessage: String?
    var cache: [String: AIAnalysisResult] = [:]
    var structuredCache: [String: AIStructuredOutput] = [:]
    var estimatedTokens: Int = 0

    // MARK: - UI State

    var showSavePrompt = false
    var showDetails = true
    var showSection = false
    var showResponsePopup = false

    /// Banner text when a requested provider was unavailable and we fell back.
    var fallbackNotice: String?

    /// Whether to show ensemble comparison sheet after ensemble analysis.
    var showEnsembleComparison = false

    // MARK: - Custom Prompt

    var useCustomPrompt = false
    var customPrompt = ""

    // MARK: - History

    var historyEntries: [AIHistoryEntry] = []
    var historySelectionA: UUID?
    var historySelectionB: UUID?
    let historyMaxEntries = 20

    // MARK: - Ensemble Mode

    /// The selected provider ID from ensemble comparison.
    var selectedEnsembleProviderID: AIProviderID?

    /// Convenience accessor for ensemble results from the provider manager.
    var ensembleResult: EnsembleAnalysisResult? {
        providerManager.ensembleResult
    }

    // MARK: - Microsoft 365 Enterprise

    /// Shared MSAL auth manager for M365 sign-in.
    let m365AuthManager: MSALAuthManager

    init(authManager: MSALAuthManager) {
        self.m365AuthManager = authManager
    }

    /// Enterprise grounding engine for M365 Retrieval API integration.
    let groundingEngine = EnterpriseGroundingEngine()

    /// Whether enterprise grounding was applied to the current analysis.
    var isEnterpriseGrounded = false

    /// Convenience: enterprise grounding citations from last retrieval.
    var groundingCitations: [GroundingCitation] {
        groundingEngine.citations
    }

    // MARK: - Sidebar Structured Sections

    var sidebarInsightsText = ""
    var sidebarRisksText = ""
    var sidebarActionsText = ""
    var sidebarHasStructuredSections = false

    // MARK: - Startup API Key Verification

    /// Per-provider key status discovered on app launch.
    struct ProviderKeyStatus: Identifiable, Sendable {
        let id: AIProviderID
        let name: String
        let hasKey: Bool
        let connectionVerified: Bool?  // nil = not tested, true = reachable, false = failed
        let detail: String
    }

    /// Status of all API keys discovered on launch (observable for UI).
    var providerKeyStatuses: [ProviderKeyStatus] = []

    /// Whether the startup verification has completed.
    var startupVerificationComplete = false

    /// Checks Keychain for all API keys, logs their status, and verifies connectivity.
    func verifyAPIKeysOnStartup() async {
        let keyAccounts: [(AIProviderID, String, String, String)] = [
            (.openAI, "OpenAI", KeychainKeys.openAIAPIKey, "https://api.openai.com"),
            (.claude, "Anthropic Claude", KeychainKeys.anthropicAPIKey, "https://api.anthropic.com"),
            (.grok, "xAI Grok", KeychainKeys.grokAPIKey, "https://api.x.ai"),
            (.gemini, "Google Gemini", KeychainKeys.geminiAPIKey, "https://generativelanguage.googleapis.com"),
        ]

        Instrumentation.log(
            "API key startup verification started",
            area: .aiAnalysis, level: .info,
            details: "checking \(keyAccounts.count) providers"
        )

        var statuses: [ProviderKeyStatus] = []

        // On-device model check
        let onDeviceAvailable = providerManager.isOnDeviceAvailable
        statuses.append(ProviderKeyStatus(
            id: .onDevice,
            name: "Apple Intelligence",
            hasKey: true,
            connectionVerified: onDeviceAvailable,
            detail: onDeviceAvailable ? "On-device model ready" : providerManager.onDeviceStatusText
        ))
        Instrumentation.log(
            "Provider: Apple Intelligence",
            area: .aiAnalysis, level: .info,
            details: "available=\(onDeviceAvailable) status=\(providerManager.onDeviceStatusText)"
        )

        for (providerID, name, account, baseURL) in keyAccounts {
            let key = KeychainStore.readPassword(account: account)
            let hasKey = key != nil && !(key?.isEmpty ?? true)

            var connectionVerified: Bool? = nil
            var detail: String

            if hasKey {
                detail = "Key found in Keychain (\(key!.prefix(8))...)"
                // Verify connectivity with a lightweight HEAD request
                connectionVerified = await verifyEndpointReachable(baseURL)
                if connectionVerified == true {
                    detail += " — endpoint reachable"
                } else {
                    detail += " — endpoint unreachable"
                }
            } else {
                detail = "No API key in Keychain"
            }

            statuses.append(ProviderKeyStatus(
                id: providerID,
                name: name,
                hasKey: hasKey,
                connectionVerified: connectionVerified,
                detail: detail
            ))

            Instrumentation.log(
                "Provider: \(name)",
                area: .aiAnalysis, level: hasKey ? .info : .warning,
                details: "hasKey=\(hasKey) connected=\(connectionVerified.map(String.init) ?? "n/a") detail=\(detail)"
            )
        }

        // PINN on-device
        let pinnAvailable = PINNPredictionService.shared.readyModelCount > 0
        statuses.append(ProviderKeyStatus(
            id: .pinnOnDevice,
            name: "PINN On-Device",
            hasKey: true,
            connectionVerified: pinnAvailable,
            detail: pinnAvailable ? "\(PINNPredictionService.shared.readyModelCount) models loaded" : "No trained models"
        ))
        Instrumentation.log(
            "Provider: PINN On-Device",
            area: .aiAnalysis, level: .info,
            details: "available=\(pinnAvailable) models=\(PINNPredictionService.shared.readyModelCount)"
        )

        providerKeyStatuses = statuses
        startupVerificationComplete = true

        let keysFound = statuses.filter { $0.hasKey && $0.id != .onDevice && $0.id != .pinnOnDevice }.count
        let reachable = statuses.filter { $0.connectionVerified == true }.count
        Instrumentation.log(
            "API key startup verification complete",
            area: .aiAnalysis, level: .info,
            details: "providers=\(statuses.count) keysFound=\(keysFound) reachable=\(reachable)"
        )
    }

    /// Lightweight connectivity check — HEAD request to the provider's base URL.
    private func verifyEndpointReachable(_ baseURL: String) async -> Bool {
        guard let url = URL(string: baseURL) else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                // Any response (even 401/403) means the endpoint is reachable
                return (100...599).contains(http.statusCode)
            }
            return true
        } catch {
            return false
        }
    }
}
