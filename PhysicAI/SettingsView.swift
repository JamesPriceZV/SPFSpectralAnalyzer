import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(SystemConfiguration)
import SystemConfiguration
#endif
import SwiftData
import UniformTypeIdentifiers
#if canImport(WebKit)
import WebKit
#endif

struct SettingsView: View {
    @Environment(DataStoreController.self) private var dataStoreController
    @AppStorage("aiEnabled") private var aiEnabled = false
    @AppStorage("aiTemperature") private var aiTemperature = 0.3
    @AppStorage("aiMaxTokens") private var aiMaxTokens = 8192
    @AppStorage("aiPromptPreset") private var aiPromptPresetRawValue = AIPromptPreset.summary.rawValue
    @AppStorage("aiAutoRun") private var aiAutoRun = false
    @AppStorage("aiDefaultScope") private var aiDefaultScopeRawValue = AISelectionScope.selected.rawValue
    @AppStorage("aiProviderPreference") private var aiProviderPreferenceRawValue = AIProviderPreference.auto.rawValue

    @AppStorage("aiOpenAIEndpoint") private var aiOpenAIEndpoint = "https://api.openai.com/v1/responses"
    @AppStorage("aiOpenAIModel") private var aiOpenAIModel = "gpt-5.4"
    @AppStorage("aiDiagnosticsEnabled") private var aiDiagnosticsEnabled = false
    @AppStorage("aiStructuredOutputEnabled") private var aiStructuredOutputEnabled = true
    @AppStorage("aiShowLogWindow") private var aiShowLogWindow = false
    @AppStorage("aiOpenAITestStatus") private var aiOpenAITestStatus = "Not tested"
    @AppStorage("aiOpenAITestTimestamp") private var aiOpenAITestTimestamp = 0.0
    @AppStorage("aiClearLogsOnQuit") private var aiClearLogsOnQuit = false
    @AppStorage("aiResponseTextSize") private var aiResponseTextSize = 18.0
    @AppStorage("spfDisplayMode") private var spfDisplayModeRawValue = SpfDisplayMode.calibrated.rawValue
    @AppStorage("spfEstimationOverride") private var spfEstimationOverrideRawValue = SPFEstimationOverride.automatic.rawValue
    @AppStorage("spfCFactor") private var spfCFactor = 0.0
    @AppStorage("spfSubstrateCorrection") private var spfSubstrateCorrection = 0.0
    @AppStorage("spfAdjustmentFactor") private var spfAdjustmentFactor = 1.0
    @AppStorage("spfCalculationMethod") private var spfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @AppStorage("instrumentationEnabled") private var instrumentationEnabled = false
    @AppStorage("instrumentationEnhancedDiagnostics") private var instrumentationEnhancedDiagnostics = false
    @AppStorage("instrumentationAreaImportParsing") private var instrumentationAreaImportParsing = false
    @AppStorage("instrumentationAreaProcessing") private var instrumentationAreaProcessing = false
    @AppStorage("instrumentationAreaChartRendering") private var instrumentationAreaChartRendering = false
    @AppStorage("instrumentationAreaAIAnalysis") private var instrumentationAreaAIAnalysis = false
    @AppStorage("instrumentationAreaExport") private var instrumentationAreaExport = false
    @AppStorage("instrumentationAreaUI") private var instrumentationAreaUI = false
    @AppStorage("instrumentationOutputInApp") private var instrumentationOutputInApp = false
    @AppStorage("instrumentationOutputConsole") private var instrumentationOutputConsole = false
    @AppStorage("instrumentationOutputFile") private var instrumentationOutputFile = false
    @AppStorage("instrumentationOutputOSLog") private var instrumentationOutputOSLog = false
    @AppStorage("instrumentationLevelErrors") private var instrumentationLevelErrors = false
    @AppStorage("instrumentationLevelWarnings") private var instrumentationLevelWarnings = false
    @AppStorage("instrumentationLevelVerbose") private var instrumentationLevelVerbose = false

    @AppStorage("icloudSyncEnabled") private var icloudSyncEnabled = false
    @State private var showIcloudSyncResetAlert = false
    @State private var pendingIcloudSyncEnabled: Bool?
    @State private var suppressIcloudSyncConfirmation = false
    @State private var showLocalStoreResetAlert = false
    @State private var showLocalResetQueuedAlert = false
    @State private var pendingLocalReset = false
    @State private var localStoreResetResult = ""
    @AppStorage("icloudSettingsSyncEnabled") private var icloudSettingsSyncEnabled = false
    @AppStorage("icloudSyncInProgress") private var icloudSyncInProgress = false
    @AppStorage("cloudKitUnavailable") private var cloudKitUnavailable = false
    @AppStorage("cloudKitUnavailableMessage") private var cloudKitUnavailableMessage = ""
    @AppStorage("toolbarShowLabels") private var toolbarShowLabels = false
    @AppStorage("icloudAutoBackupEnabled") private var icloudAutoBackupEnabled = false
    @AppStorage("icloudBackupOnClose") private var icloudBackupOnClose = false
    @AppStorage("icloudBackupIntervalHours") private var icloudBackupIntervalHours = 6.0
    @AppStorage("icloudLastBackupTimestamp") private var icloudLastBackupTimestamp = 0.0
    @AppStorage("icloudLastBackupStatus") private var icloudLastBackupStatus = "No backups yet"
    @AppStorage("icloudLastBackupSizeBytes") private var icloudLastBackupSizeBytes = 0.0
    @AppStorage("icloudLastRestoreTimestamp") private var icloudLastRestoreTimestamp = 0.0
    @AppStorage("icloudLastRestoreStatus") private var icloudLastRestoreStatus = "No restore yet"
    @AppStorage("icloudLastSyncTimestamp") private var icloudLastSyncTimestamp = 0.0
    @AppStorage("icloudLastSyncStatus") private var icloudLastSyncStatus = "Not synced yet"
    @AppStorage("icloudPollingIntervalMinutes") private var icloudPollingIntervalMinutes = 15.0
    #if DEBUG
    @AppStorage("icloudLastNotificationPayload") private var icloudLastNotificationPayload = ""
    @AppStorage("icloudLastTokenDescription") private var icloudLastTokenDescription = ""
    @AppStorage("icloudLastPollTimestamp") private var icloudLastPollTimestamp = 0.0
    @AppStorage("icloudLastPushTimestamp") private var icloudLastPushTimestamp = 0.0
    @AppStorage("icloudLastSyncReason") private var icloudLastSyncReason = ""
    @AppStorage("icloudLastChangedZoneIDs") private var icloudLastChangedZoneIDs = ""
    @AppStorage("icloudLastDeletedZoneIDs") private var icloudLastDeletedZoneIDs = ""
    @AppStorage("icloudLastSubscriptionID") private var icloudLastSubscriptionID = ""
    @AppStorage("icloudLastSubscriptionStatus") private var icloudLastSubscriptionStatus = ""
    @AppStorage("icloudContainerIdentifier") private var icloudContainerIdentifier = ""
    @AppStorage("icloudAccountStatus") private var icloudAccountStatus = ""
    @AppStorage("icloudAccountStatusError") private var icloudAccountStatusError = ""
    @AppStorage("icloudAccountStatusTimestamp") private var icloudAccountStatusTimestamp = 0.0
    @AppStorage("icloudDatabaseScope") private var icloudDatabaseScope = ""
    @AppStorage("icloudLastSyncStartTimestamp") private var icloudLastSyncStartTimestamp = 0.0
    @AppStorage("icloudLastSyncEndTimestamp") private var icloudLastSyncEndTimestamp = 0.0
    @AppStorage("icloudLastSyncDuration") private var icloudLastSyncDuration = 0.0
    @AppStorage("icloudLastSyncErrorDomain") private var icloudLastSyncErrorDomain = ""
    @AppStorage("icloudLastSyncErrorCode") private var icloudLastSyncErrorCode = 0
    @AppStorage("icloudLastSyncErrorDescription") private var icloudLastSyncErrorDescription = ""
    @AppStorage("icloudLastSyncMoreComing") private var icloudLastSyncMoreComing = false
    @AppStorage("icloudLastSyncChangesDetected") private var icloudLastSyncChangesDetected = false
    @AppStorage("icloudLastChangedZoneCount") private var icloudLastChangedZoneCount = 0
    @AppStorage("icloudLastDeletedZoneCount") private var icloudLastDeletedZoneCount = 0
    @AppStorage("icloudLastPushSubscriptionID") private var icloudLastPushSubscriptionID = ""
    @AppStorage("icloudLastNotificationType") private var icloudLastNotificationType = ""
    @AppStorage("icloudLastTokenByteSize") private var icloudLastTokenByteSize = 0
    @AppStorage("icloudLastMoreComingTimestamps") private var icloudLastMoreComingTimestamps = Data()
    @AppStorage("icloudLastPartialZoneErrors") private var icloudLastPartialZoneErrors = ""
    @AppStorage("icloudLastZoneFetchErrors") private var icloudLastZoneFetchErrors = ""
    @AppStorage("icloudLastZoneFetchTimestamp") private var icloudLastZoneFetchTimestamp = 0.0
    @AppStorage("icloudLastZoneFetchMoreComing") private var icloudLastZoneFetchMoreComing = false
    @AppStorage("icloudZoneChangeTokens") private var icloudZoneChangeTokens = Data()
    @State private var showICloudDebugPanel = false
    #endif

    @AppStorage("swiftDataStoreResetTimestamp") private var storeResetTimestamp = 0.0
    @AppStorage("swiftDataStoreResetMessage") private var storeResetMessage = ""
    @AppStorage("swiftDataStoreResetHistory") private var storeResetHistoryData = Data()

    @AppStorage("aiClaudeModel") private var aiClaudeModel = "claude-sonnet-4-5-20250514"
    @AppStorage("aiClaudeTestStatus") private var aiClaudeTestStatus = "Not tested"
    @AppStorage("aiClaudeTestTimestamp") private var aiClaudeTestTimestamp = 0.0

    @AppStorage("aiGrokModel") private var aiGrokModel = "grok-3"
    @AppStorage("aiGrokTestStatus") private var aiGrokTestStatus = "Not tested"
    @AppStorage("aiGrokTestTimestamp") private var aiGrokTestTimestamp = 0.0

    @AppStorage("aiGeminiModel") private var aiGeminiModel = "gemini-2.5-flash"
    @AppStorage("aiGeminiTestStatus") private var aiGeminiTestStatus = "Not tested"
    @AppStorage("aiGeminiTestTimestamp") private var aiGeminiTestTimestamp = 0.0

    // Multi-provider routing
    @AppStorage("aiProviderPriorityOrder") private var aiProviderPriorityOrderJSON = ""
    @AppStorage("aiAdvancedRoutingEnabled") private var aiAdvancedRoutingEnabled = false
    @AppStorage("aiFunctionRoutingJSON") private var aiFunctionRoutingJSON = ""
    @AppStorage("aiEnsembleModeEnabled") private var aiEnsembleModeEnabled = false
    @AppStorage("aiEnsembleProvidersJSON") private var aiEnsembleProvidersJSON = ""
    @AppStorage("aiEnsembleArbitrationEnabled") private var aiEnsembleArbitrationEnabled = true
    @AppStorage("aiCostTrackingEnabled") private var aiCostTrackingEnabled = false

    @State private var showAPIKey = false
    @State private var hasStoredAPIKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) != nil
    @State private var apiKeyDraft = ""
    @State private var showOpenAIKeyBrowser = false

    // Anthropic Claude state
    @State private var showClaudeAPIKey = false
    @State private var hasStoredClaudeAPIKey = KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey) != nil
    @State private var claudeAPIKeyDraft = ""
    @State private var draftClaudeModel = "claude-sonnet-4-5-20250514"

    @State private var showGrokAPIKey = false
    @State private var hasStoredGrokAPIKey = KeychainStore.readPassword(account: KeychainKeys.grokAPIKey) != nil
    @State private var grokAPIKeyDraft = ""
    @State private var draftGrokModel = "grok-3"

    @State private var showGeminiAPIKey = false
    @State private var hasStoredGeminiAPIKey = KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey) != nil
    @State private var geminiAPIKeyDraft = ""
    @State private var draftGeminiModel = "gemini-2.5-flash"

    @State private var draftAIEnabled = false
    @State private var draftTemperature = 0.3
    @State private var draftMaxTokens = 8192
    @State private var draftPromptPresetRawValue = AIPromptPreset.summary.rawValue
    @State private var draftAutoRun = false
    @State private var draftDefaultScopeRawValue = AISelectionScope.selected.rawValue

    @State private var draftProviderPreferenceRawValue = AIProviderPreference.auto.rawValue
    @State private var draftOpenAIEndpoint = "https://api.openai.com/v1/responses"
    @State private var draftOpenAIModel = "gpt-5.4"
    @State private var draftDiagnosticsEnabled = false
    @State private var draftStructuredOutputEnabled = true
    @State private var draftClearLogsOnQuit = false
    @State private var showDiagnosticsConsole = false
    @State private var draftAIResponseTextSize = 18.0
    @State private var draftSpfDisplayModeRawValue = SpfDisplayMode.calibrated.rawValue
    @State private var draftSpfEstimationOverrideRawValue = SPFEstimationOverride.automatic.rawValue
    @State private var draftSpfCFactor = ""
    @State private var draftSpfSubstrateCorrection = ""
    @State private var draftSpfAdjustmentFactor = "1"
    @State private var draftSpfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @State private var availableOpenAIModels: [String] = []
    @State private var isFetchingOpenAIModels = false
    @State private var openAIModelFetchStatus: String?

    // Routing draft state
    @State private var draftPriorityOrder: [AIProviderID] = AIProviderID.defaultPriorityOrder
    @State private var draftAdvancedRoutingEnabled = false
    @State private var draftFunctionRouting: [AIAppFunction: FunctionRoutingMode] = [:]
    @State private var draftEnsembleModeEnabled = false
    @State private var draftEnsembleProviders: Set<AIProviderID> = [.claude, .openAI]
    @State private var draftEnsembleArbitrationEnabled = true
    @State private var draftCostTrackingEnabled = false

    // M365 Enterprise
    @AppStorage(M365Config.StorageKeys.clientId) private var m365ClientId = M365Config.defaultClientId
    @AppStorage(M365Config.StorageKeys.tenantId) private var m365TenantId = M365Config.defaultTenantId
    @AppStorage(M365Config.StorageKeys.enterpriseGroundingEnabled) private var m365GroundingEnabled = false
    @AppStorage(M365Config.StorageKeys.groundingConfigJSON) private var m365GroundingConfigJSON = ""
    @AppStorage(M365Config.StorageKeys.exportConfigJSON) private var m365ExportConfigJSON = ""

    var m365AuthManager: MSALAuthManager
    var isSheet: Bool = false
    @State private var draftM365ClientId = M365Config.defaultClientId
    @State private var draftM365TenantId = M365Config.defaultTenantId
    @State private var draftGroundingConfig = EnterpriseGroundingConfig.default
    @State private var draftExportConfig = SharePointExportConfig.default
    @State private var draftSiteFilterText = ""
    @State private var m365SignInError: String?
    @State private var m365Validator = M365ConfigValidator()

    // ML Training defaults
    @AppStorage("pinnDefaultEpochs") private var pinnDefaultEpochs = 500
    @AppStorage("pinnDefaultLearningRate") private var pinnDefaultLearningRate = 0.001
    @AppStorage("pinnPythonPath") private var pinnPythonPath = "python3"
    @AppStorage("createMLMaxIterations") private var createMLMaxIterations = 200
    @AppStorage("createMLMaxDepth") private var createMLMaxDepth = 6
    @AppStorage("createMLConformalLevel") private var createMLConformalLevel = 0.90
    @AppStorage("instrumentationAreaMLTraining") private var instrumentationAreaMLTraining = false

    @State private var draftPinnDefaultEpochs = 500
    @State private var draftPinnDefaultLearningRate = 0.001
    @State private var draftPinnPythonPath = "/opt/homebrew/bin/python3"
    @State private var draftCreateMLMaxIterations = 200
    @State private var draftCreateMLMaxDepth = 6
    @State private var draftCreateMLConformalLevel = 0.90
    @State private var draftInstrumentationAreaMLTraining = false
    @State private var pythonDetectionResult: PythonEnvironmentDetector.DetectionResult?
    @State private var isDetectingPython = false
    @State private var scriptInstallMessage: String?
    #if os(macOS)
    @State private var packageInstaller = PackageInstaller()
    @State private var trainingDataDownloader = TrainingDataDownloader.shared
    #endif

    @State private var draftInstrumentationEnabled = false
    @State private var draftInstrumentationEnhancedDiagnostics = false
    @State private var draftInstrumentationAreaImportParsing = false
    @State private var draftInstrumentationAreaProcessing = false
    @State private var draftInstrumentationAreaChartRendering = false
    @State private var draftInstrumentationAreaAIAnalysis = false
    @State private var draftInstrumentationAreaExport = false
    @State private var draftInstrumentationAreaUI = false
    @State private var draftInstrumentationOutputInApp = false
    @State private var draftInstrumentationOutputConsole = false
    @State private var draftInstrumentationOutputFile = false
    @State private var draftInstrumentationOutputOSLog = false
    @State private var draftInstrumentationLevelErrors = false
    @State private var draftInstrumentationLevelWarnings = false
    @State private var draftInstrumentationLevelVerbose = false

    @State private var dnsStatusMessage: String?
    @State private var dnsStatusTimestamp: Date?
    @State private var dnsStatusIPs: [String] = []

    @State private var usageTracker = ProviderUsageTracker()
    @State private var draftBudgetCaps: [AIProviderID: ProviderBudgetCap] = [:]

    @State private var selectedSettingsTab = SettingsTab.general
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case ai = "AI"
        case mlTraining = "ML Training"
        case enterprise = "Enterprise"
        case sync = "iCloud Sync"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .ai: return "sparkles"
            case .mlTraining: return "cpu"
            case .enterprise: return "building.2"
            case .sync: return "icloud"
            case .advanced: return "wrench.and.screwdriver"
            }
        }
    }

    private var selectedPreset: Binding<AIPromptPreset> {
        Binding(
            get: { AIPromptPreset(rawValue: draftPromptPresetRawValue) ?? .summary },
            set: { draftPromptPresetRawValue = $0.rawValue }


        )
    }

    private var defaultScope: Binding<AISelectionScope> {
        Binding(
            get: { AISelectionScope(rawValue: draftDefaultScopeRawValue) ?? .selected },
            set: { draftDefaultScopeRawValue = $0.rawValue }
        )
    }

    private var spfDisplayModeSelection: Binding<SpfDisplayMode> {
        Binding(
            get: { SpfDisplayMode(rawValue: draftSpfDisplayModeRawValue) ?? .calibrated },
            set: { draftSpfDisplayModeRawValue = $0.rawValue }
        )
    }

    private var spfEstimationOverrideSelection: Binding<SPFEstimationOverride> {
        Binding(
            get: { SPFEstimationOverride(rawValue: draftSpfEstimationOverrideRawValue) ?? .automatic },
            set: { draftSpfEstimationOverrideRawValue = $0.rawValue }
        )
    }

    private var spfCalculationMethodSelection: Binding<SPFCalculationMethod> {
        Binding(
            get: { SPFCalculationMethod(rawValue: draftSpfCalculationMethodRawValue) ?? .colipa },
            set: { draftSpfCalculationMethodRawValue = $0.rawValue }
        )
    }

    private var settingsAreDirty: Bool {
        draftAIEnabled != aiEnabled ||
        draftTemperature != aiTemperature ||
        draftMaxTokens != aiMaxTokens ||
        draftPromptPresetRawValue != aiPromptPresetRawValue ||
        draftAutoRun != aiAutoRun ||
        draftDefaultScopeRawValue != aiDefaultScopeRawValue ||
        draftProviderPreferenceRawValue != aiProviderPreferenceRawValue ||
        draftOpenAIEndpoint != aiOpenAIEndpoint ||
        draftOpenAIModel != aiOpenAIModel ||
        draftDiagnosticsEnabled != aiDiagnosticsEnabled ||
        draftStructuredOutputEnabled != aiStructuredOutputEnabled ||
        draftClearLogsOnQuit != aiClearLogsOnQuit ||
        draftSpfDisplayModeRawValue != spfDisplayModeRawValue ||
        draftSpfEstimationOverrideRawValue != spfEstimationOverrideRawValue ||
        draftSpfCalculationMethodRawValue != spfCalculationMethodRawValue ||
        draftClaudeModel != aiClaudeModel ||
        draftGrokModel != aiGrokModel ||
        draftGeminiModel != aiGeminiModel ||
        encodedPriorityOrder != aiProviderPriorityOrderJSON ||
        draftAdvancedRoutingEnabled != aiAdvancedRoutingEnabled ||
        encodedFunctionRouting != aiFunctionRoutingJSON ||
        draftEnsembleModeEnabled != aiEnsembleModeEnabled ||
        encodedEnsembleProviders != aiEnsembleProvidersJSON ||
        draftEnsembleArbitrationEnabled != aiEnsembleArbitrationEnabled ||
        draftCostTrackingEnabled != aiCostTrackingEnabled ||
        draftM365ClientId != m365ClientId ||
        draftM365TenantId != m365TenantId ||
        encodedGroundingConfig != m365GroundingConfigJSON ||
        encodedExportConfig != m365ExportConfigJSON ||
        draftInstrumentationEnabled != instrumentationEnabled ||
        draftInstrumentationEnhancedDiagnostics != instrumentationEnhancedDiagnostics ||
        !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
        !geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Encode the draft priority order to JSON for comparison and persistence.
    private var encodedPriorityOrder: String {
        let rawValues = draftPriorityOrder.map(\.rawValue)
        guard let data = try? JSONEncoder().encode(rawValues) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Encode the draft function routing to JSON.
    private var encodedFunctionRouting: String {
        guard !draftFunctionRouting.isEmpty else { return "" }
        let dict = Dictionary(uniqueKeysWithValues: draftFunctionRouting.map { ($0.key.rawValue, $0.value) })
        guard let data = try? JSONEncoder().encode(dict) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Encode the draft ensemble providers to JSON.
    private var encodedEnsembleProviders: String {
        let rawValues = draftEnsembleProviders.map(\.rawValue).sorted()
        guard let data = try? JSONEncoder().encode(rawValues) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Encode the draft grounding config to JSON.
    private var encodedGroundingConfig: String {
        guard let data = try? JSONEncoder().encode(draftGroundingConfig) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Encode the draft export config to JSON.
    private var encodedExportConfig: String {
        guard let data = try? JSONEncoder().encode(draftExportConfig) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private var resolvedOpenAIEndpointURL: URL? {
        let trimmed = draftOpenAIEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }
        return URL(string: "https://\(trimmed)")
    }

    private var openAITestBadgeText: String {
        guard aiOpenAITestTimestamp > 0 else { return aiOpenAITestStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: aiOpenAITestTimestamp))
        return "\(aiOpenAITestStatus) • \(formatted)"
    }

    private var openAITestSession: URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.waitsForConnectivity = true
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 20
        return URLSession(configuration: configuration)
    }

    private var resolvedOpenAIHost: String? {
        resolvedOpenAIEndpointURL?.host
    }

    private var dnsStatusLabel: String? {
        guard let dnsStatusMessage else { return nil }
        guard let timestamp = dnsStatusTimestamp else { return dnsStatusMessage }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return "\(dnsStatusMessage) • \(formatter.string(from: timestamp))"
    }

    private var dnsStatusText: String {
        let status = dnsStatusLabel ?? "No DNS check yet"
        let ips = dnsStatusIPs.isEmpty ? "" : "\nIPs: \(dnsStatusIPs.joined(separator: ", "))"
        return status + ips
    }

    private var canResolveOpenAIHost: Bool {
        guard let host = resolvedOpenAIHost else { return false }
        return !resolveHostAddresses(host).isEmpty
    }

    private var defaultOpenAIModels: [String] {
        [
            "gpt-4o-2024-08-06",
            "gpt-4o-mini-2024-07-18",
            "gpt-4o-mini",
            "gpt-4o",
            "gpt-5.4"
        ]
    }

    private var openAIModelChoices: [String] {
        let trimmed = draftOpenAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = availableOpenAIModels.isEmpty ? defaultOpenAIModels : availableOpenAIModels
        var unique = Array(Set(base)).sorted()
        if !trimmed.isEmpty, !unique.contains(trimmed) {
            unique.insert(trimmed, at: 0)
        }
        return unique
    }

    // MARK: - Claude Model Choices

    private var defaultClaudeModels: [String] {
        [
            "claude-opus-4-5-20250514",
            "claude-sonnet-4-5-20250514",
            "claude-haiku-4-5-20251001",
            "claude-3-5-sonnet-20241022"
        ]
    }

    private var claudeModelChoices: [String] {
        let trimmed = draftClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var unique = defaultClaudeModels
        if !trimmed.isEmpty, !unique.contains(trimmed) {
            unique.insert(trimmed, at: 0)
        }
        return unique
    }

    private var claudeTestBadgeText: String {
        guard aiClaudeTestTimestamp > 0 else { return aiClaudeTestStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: aiClaudeTestTimestamp))
        return "\(aiClaudeTestStatus) • \(formatted)"
    }

    // MARK: - Grok Model Choices

    private var defaultGrokModels: [String] {
        [
            "grok-4.20-0309-reasoning",
            "grok-4.20-0309-non-reasoning",
            "grok-4.20-multi-agent-0309",
            "grok-4-1-fast-reasoning",
            "grok-4-1-fast-non-reasoning",
            "grok-4",
            "grok-3",
            "grok-3-mini"
        ]
    }

    private var grokModelChoices: [String] {
        let trimmed = draftGrokModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var unique = defaultGrokModels
        if !trimmed.isEmpty, !unique.contains(trimmed) {
            unique.insert(trimmed, at: 0)
        }
        return unique
    }

    private var grokTestBadgeText: String {
        guard aiGrokTestTimestamp > 0 else { return aiGrokTestStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: aiGrokTestTimestamp))
        return "\(aiGrokTestStatus) • \(formatted)"
    }

    // MARK: - Gemini Model Choices

    private var defaultGeminiModels: [String] {
        ["gemini-2.5-pro", "gemini-2.5-flash", "gemini-2.0-flash"]
    }

    private var geminiModelChoices: [String] {
        let trimmed = draftGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        var unique = defaultGeminiModels
        if !trimmed.isEmpty, !unique.contains(trimmed) {
            unique.insert(trimmed, at: 0)
        }
        return unique
    }

    private var geminiTestBadgeText: String {
        guard aiGeminiTestTimestamp > 0 else { return aiGeminiTestStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: aiGeminiTestTimestamp))
        return "\(aiGeminiTestStatus) • \(formatted)"
    }

    private var iCloudBackupStatusText: String {
        guard icloudLastBackupTimestamp > 0 else { return icloudLastBackupStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: icloudLastBackupTimestamp))
        return "\(icloudLastBackupStatus) • \(formatted)"
    }

    private var iCloudRestoreStatusText: String {
        guard icloudLastRestoreTimestamp > 0 else { return icloudLastRestoreStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: icloudLastRestoreTimestamp))
        return "\(icloudLastRestoreStatus) • \(formatted)"
    }

    private var iCloudBackupSizeText: String {
        guard icloudLastBackupSizeBytes > 0 else { return "Not calculated" }
        return ByteCountFormatter.string(fromByteCount: Int64(icloudLastBackupSizeBytes), countStyle: .file)
    }

    private var isLocalStore: Bool {
        dataStoreController.storeMode == "local"
    }

    private var storeModeLabel: String {
        switch dataStoreController.storeMode {
        case "cloudKit": return "CloudKit"
        case "local": return "Local"
        default: return "Unknown"
        }
    }

    private var iCloudSyncStatusText: String {
        if icloudSyncInProgress { return "Sync in progress" }
        guard icloudLastSyncTimestamp > 0 else { return icloudLastSyncStatus }
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        let formatted = formatter.string(from: Date(timeIntervalSince1970: icloudLastSyncTimestamp))
        return "\(icloudLastSyncStatus) • \(formatted)"
    }

    private static let storeResetDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private var storeResetHistoryEntries: [StoreResetHistoryEntry] {
        StoreResetHistoryEntry.decode(from: storeResetHistoryData)
    }

    private func appendStoreResetHistory(message: String) {
        let entry = StoreResetHistoryEntry(message: message)
        var entries = storeResetHistoryEntries
        entries.insert(entry, at: 0)
        if entries.count > 20 {
            entries = Array(entries.prefix(20))
        }
        if let data = StoreResetHistoryEntry.encode(entries) {
            storeResetHistoryData = data
        }
    }

    private func relaunchApp() {
        #if canImport(AppKit)
        let appURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        NSApp.terminate(nil)
        #else
        // iOS: exit is not allowed per Apple guidelines; settings changes take effect immediately
        #endif
    }

    private var storeResetTimestampText: String {
        guard storeResetTimestamp > 0 else { return "Never" }
        return Self.storeResetDateFormatter.string(from: Date(timeIntervalSince1970: storeResetTimestamp))
    }

    private var proxyStatusLabel: String {
        guard let settings = CFNetworkCopySystemProxySettings()?.takeRetainedValue() as? [String: Any] else {
            return "No proxy settings detected"
        }
        let httpEnabled = (settings[kCFNetworkProxiesHTTPEnable as String] as? Int ?? 0) != 0
        let httpProxy = settings[kCFNetworkProxiesHTTPProxy as String] as? String
        let httpPort = settings[kCFNetworkProxiesHTTPPort as String] as? Int
        #if os(macOS)
        let httpsEnabled = (settings[kCFNetworkProxiesHTTPSEnable as String] as? Int ?? 0) != 0
        let httpsProxy = settings[kCFNetworkProxiesHTTPSProxy as String] as? String
        let httpsPort = settings[kCFNetworkProxiesHTTPSPort as String] as? Int
        #endif
        var parts: [String] = []
        if httpEnabled {
            if let httpProxy {
                let portText = httpPort.map { ":\($0)" } ?? ""
                parts.append("HTTP \(httpProxy)\(portText)")
            } else {
                parts.append("HTTP enabled")
            }
        }
        #if os(macOS)
        if httpsEnabled {
            if let httpsProxy {
                let portText = httpsPort.map { ":\($0)" } ?? ""
                parts.append("HTTPS \(httpsProxy)\(portText)")
            } else {
                parts.append("HTTPS enabled")
            }
        }
        #endif
        return parts.isEmpty ? "No proxy enabled" : parts.joined(separator: " • ")
    }

    // MARK: - Settings Form Sections (shared between iOS NavigationLink pages and macOS segmented tabs)

    @ViewBuilder
    private var settingsFormContent: some View {
            if selectedSettingsTab == .general {
            Section("SPF Estimation") {
                Picker("Calculation Method", selection: spfCalculationMethodSelection) {
                    ForEach(SPFCalculationMethod.allCases) { method in
                        Text(method.label).tag(method)
                    }
                }
                Text((SPFCalculationMethod(rawValue: draftSpfCalculationMethodRawValue) ?? .colipa).detailDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                HStack(spacing: 4) {
                    Picker("Estimation Tier", selection: spfEstimationOverrideSelection) {
                    ForEach(SPFEstimationOverride.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                    }
                    HelpButton("Estimation Tiers", message: "SPF estimation uses a **tiered system** with increasing accuracy:\n\n**Tier 1 \u{2014} Full COLIPA:** Uses your C-factor and substrate correction to convert raw in-vitro SPF to a calibrated value. Most accurate, but requires experimentally determined correction factors.\n\n**Tier 2 \u{2014} Calibrated:** Uses a regression model built from your reference datasets (spectra with known in-vivo SPF). Accuracy depends on the quality and quantity of reference data.\n\n**Tier 3 \u{2014} Adjusted:** Applies a simple multiplier to the raw COLIPA value. Least accurate but always available.\n\n**Automatic** selects the best available tier for each measurement.")
                }
                Text("Automatic uses the best available tier: Full correction \u{2192} Calibrated \u{2192} Adjusted.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GroupBox("Correction Factors (Tier 1 — Full COLIPA)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 4) {
                                Text("C_factor")
                                HelpButton("C-Factor", message: "The **C-factor** (correction factor) converts an in-vitro SPF measurement into a value that approximates the in-vivo (on-skin) SPF.\n\nIt is the ratio: **C = in-vivo SPF \u{00F7} in-vitro COLIPA SPF**\n\nTypical values range from **15\u{2013}30**, depending on your instrument, PMMA plate type, and application technique. You determine it by testing the same formulations both in-vitro (on plates) and in-vivo (on human subjects), then computing the average ratio.\n\n**In-vitro** = measured on a laboratory substrate (PMMA plate)\n**In-vivo** = measured on human skin under controlled UV exposure")
                            }
                                #if os(macOS)
                                .frame(width: 130, alignment: .leading)
                                #else
                                .frame(minWidth: 80, alignment: .leading)
                                #endif
                            TextField("e.g. 25.0", text: $draftSpfCFactor)
                                .textFieldStyle(.roundedBorder)
                                #if os(macOS)
                                .frame(width: 100)
                                #else
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        HStack {
                            HStack(spacing: 4) {
                                Text("Substrate Correction")
                                HelpButton("Substrate Correction", message: "**Substrate correction** adjusts the SPF calculation for differences between PMMA plate types.\n\n**PMMA (Polymethylmethacrylate)** plates are the standard laboratory substrates used to simulate skin for in-vitro UV measurements. Different plate types (HD6 moulded, SB6 sandblasted) have slightly different surface textures that affect how sunscreen spreads and absorbs UV light.\n\nThis correction factor accounts for those differences so results are comparable across plate types. A value of 1.0 means no correction.")
                            }
                                #if os(macOS)
                                .frame(width: 130, alignment: .leading)
                                #else
                                .frame(minWidth: 80, alignment: .leading)
                                #endif
                            TextField("e.g. 1.0", text: $draftSpfSubstrateCorrection)
                                .textFieldStyle(.roundedBorder)
                                #if os(macOS)
                                .frame(width: 100)
                                #else
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        Text("C_factor is the ratio of in-vivo SPF to in-vitro COLIPA value (typically 15–30). Substrate correction adjusts for the PMMA plate type. Both must be > 0 for Tier 1.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                GroupBox("Adjustment Factor (Tier 3 — Adjusted COLIPA)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Multiplier")
                                #if os(macOS)
                                .frame(width: 130, alignment: .leading)
                                #else
                                .frame(minWidth: 80, alignment: .leading)
                                #endif
                            TextField("1", text: $draftSpfAdjustmentFactor)
                                .textFieldStyle(.roundedBorder)
                                #if os(macOS)
                                .frame(width: 100)
                                #else
                                .keyboardType(.decimalPad)
                                #endif
                        }
                        Text("Multiplier applied to raw in-vitro SPF when correction factors and calibration are unavailable. Default is 1 (no adjustment). Set a value > 1 only if you have experimentally determined the ratio between in-vitro and in-vivo SPF for your instrument and substrate.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Toolbar") {
                Toggle("Show Toolbar Labels", isOn: $toolbarShowLabels)
                    .toggleStyle(.switch)
                Text("Display labels under the toolbar icons and increase spacing.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            }

            if selectedSettingsTab == .ai {
            Section("AI") {
                Toggle("Enable AI Analysis", isOn: $draftAIEnabled)
                    .toggleStyle(.switch)

                Text("AI analysis sends selected spectral data to Apple Intelligence, Anthropic Claude, OpenAI, xAI Grok, or Google Gemini.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("AI Provider") {
                Picker("Provider", selection: Binding(
                    get: { AIProviderPreference(rawValue: draftProviderPreferenceRawValue) ?? .auto },
                    set: { draftProviderPreferenceRawValue = $0.rawValue }
                )) {
                    ForEach(AIProviderPreference.allCases) { pref in
                        Text(pref.label).tag(pref)
                    }
                }
                .pickerStyle(.menu)

                let selectedPref = AIProviderPreference(rawValue: draftProviderPreferenceRawValue) ?? .auto
                Text(selectedPref.description)
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    let providerManager = AIProviderManager()
                    Circle()
                        .fill(providerManager.isOnDeviceAvailable ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text("Apple Intelligence: \(providerManager.onDeviceStatusText)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Provider Priority (Auto Mode)") {
                Text("Providers are tried in this order when Auto is selected.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Array(draftPriorityOrder.enumerated()), id: \.element) { index, providerID in
                    HStack(spacing: 10) {
                        Text("\(index + 1).")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(.secondary)
                            .frame(width: 20)
                        Image(systemName: providerID.iconName)
                            .frame(width: 20)
                            .foregroundColor(.accentColor)
                        Text(providerID.displayName)
                        Spacer()
                        providerAvailabilityDot(for: providerID)
                        #if os(iOS)
                        // Up/down buttons avoid nested-scroll drag conflicts on iOS
                        Button {
                            guard index > 0 else { return }
                            draftPriorityOrder.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)

                        Button {
                            guard index < draftPriorityOrder.count - 1 else { return }
                            draftPriorityOrder.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == draftPriorityOrder.count - 1)
                        #endif
                    }
                    .padding(.vertical, 4)
                    .accessibilityLabel("Provider \(providerID.displayName), priority \(index + 1)")
                    .accessibilityHint("Use arrows to reorder")
                }
                #if os(macOS)
                .onMove { indices, newOffset in
                    draftPriorityOrder.move(fromOffsets: indices, toOffset: newOffset)
                }
                #endif
                .accessibilityIdentifier("providerPriorityList")

                Button("Reset to Default") {
                    draftPriorityOrder = AIProviderID.defaultPriorityOrder
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Section("Advanced Routing") {
                Toggle("Enable Advanced Routing", isOn: $draftAdvancedRoutingEnabled)
                    .toggleStyle(.switch)
                Text("Assign a specific provider or Smart routing per AI function. When disabled, all functions use the provider preference above.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftAdvancedRoutingEnabled {
                    ForEach(AIAppFunction.allCases) { function in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(function.displayName)
                                    .font(.subheadline.bold())
                                Spacer()
                                Picker("", selection: functionRoutingBinding(for: function)) {
                                    Text("Auto (Priority Queue)").tag(FunctionRoutingMode.auto)
                                    Text("Smart (Task-Based)").tag(FunctionRoutingMode.smart)
                                    ForEach(AIProviderID.allCases) { id in
                                        Text(id.displayName).tag(FunctionRoutingMode.specific(id))
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(maxWidth: 200)
                            }
                            Text(function.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("Ensemble Mode") {
                Toggle("Enable Ensemble Mode", isOn: $draftEnsembleModeEnabled)
                    .toggleStyle(.switch)
                Text("Run multiple providers in parallel and compare results side by side. Only available for Spectral Analysis.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftEnsembleModeEnabled {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Select Providers (minimum 2)")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)

                        ForEach(AIProviderID.allCases) { providerID in
                            Toggle(isOn: ensembleProviderBinding(for: providerID)) {
                                HStack(spacing: 8) {
                                    Image(systemName: providerID.iconName)
                                        .frame(width: 16)
                                        .foregroundColor(.accentColor)
                                    Text(providerID.displayName)
                                    Spacer()
                                    providerAvailabilityDot(for: providerID)
                                }
                            }
                            .toggleStyle(.switch)
                        }

                        if draftEnsembleProviders.count < 2 {
                            HStack(spacing: 4) {
                                Image(systemName: "exclamationmark.triangle")
                                    .foregroundColor(.orange)
                                Text("Select at least 2 providers for ensemble mode.")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                    }

                    Divider()

                    Toggle("Enable Arbitration", isOn: $draftEnsembleArbitrationEnabled)
                        .toggleStyle(.switch)
                    Text("An on-device AI arbitrator synthesizes all provider responses into a unified analysis, identifying consensus findings, disputed claims, and outlier observations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Cost Tracking & Budgets") {
                Toggle("Enable Cost Tracking", isOn: $draftCostTrackingEnabled)
                    .toggleStyle(.switch)
                Text("Track token usage and estimated costs per provider. Over-budget providers are skipped in Auto mode.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftCostTrackingEnabled {
                    // Monthly usage dashboard
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This Month's Usage")
                            .font(.subheadline.bold())

                        ForEach(usageTracker.currentMonthSummaries, id: \.providerID) { summary in
                            let cap = draftBudgetCaps[summary.providerID] ?? ProviderBudgetCap.defaults(for: summary.providerID)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Image(systemName: summary.providerID.iconName)
                                        .frame(width: 16)
                                        .foregroundColor(.accentColor)
                                    Text(summary.providerID.displayName)
                                        .font(.caption.bold())
                                    Spacer()
                                    Text("\(summary.callCount) calls")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                if cap.monthlyBudgetUSD > 0 {
                                    ProgressView(
                                        value: min(summary.totalCostUSD, cap.monthlyBudgetUSD),
                                        total: cap.monthlyBudgetUSD
                                    )
                                    .tint(summary.totalCostUSD >= cap.monthlyBudgetUSD ? .red : .accentColor)
                                }

                                HStack {
                                    Text(String(format: "$%.4f spent", summary.totalCostUSD))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    if cap.monthlyBudgetUSD > 0 {
                                        Text("/ $\(String(format: "%.2f", cap.monthlyBudgetUSD)) budget")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(summary.totalPromptTokens + summary.totalCompletionTokens) tokens")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }

                    // Budget caps
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Monthly Budget Caps")
                            .font(.subheadline.bold())

                        ForEach(AIProviderID.allCases) { providerID in
                            if providerID != .onDevice {
                                HStack {
                                    Text(providerID.displayName)
                                        .font(.caption)
                                        .frame(width: 120, alignment: .leading)
                                    Text("$")
                                        .font(.caption)
                                    TextField("", value: budgetCapBinding(for: providerID), format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("/mo")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    Button("Reset Monthly Usage", role: .destructive) {
                        usageTracker.resetCurrentMonth()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Section("Authentication") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if showAPIKey {
                            TextField("OpenAI API Key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .textContentType(.none)
                                .submitLabel(.done)
                                .onSubmit { saveAPIKey() }
                                #endif
                        } else {
                            SecureField("OpenAI API Key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                                #if os(iOS)
                                .textInputAutocapitalization(.never)
                                .textContentType(.none)
                                .submitLabel(.done)
                                .onSubmit { saveAPIKey() }
                                #endif
                        }

                        Button(showAPIKey ? "Hide" : "Show") {
                            showAPIKey.toggle()
                        }
                    }

                    #if os(iOS)
                    // iOS: compact buttons
                    HStack(spacing: 12) {
                        Button("Save Key") {
                            saveAPIKey()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear") {
                            clearAPIKey()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!hasStoredAPIKey)

                        Button("Test") {
                            Task { await testOpenAIConnection() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(resolvedOpenAIEndpointURL == nil || !hasStoredAPIKey)

                        Spacer()
                    }

                    HStack(spacing: 6) {
                        Image(systemName: hasStoredAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                            .foregroundColor(hasStoredAPIKey ? .green : .secondary)
                            .font(.caption)
                        Text(hasStoredAPIKey ? "Key stored" : "No key stored")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if openAITestBadgeText != "Not tested" {
                        Text(openAITestBadgeText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    #else
                    HStack {
                        Button("Save API Key") {
                            saveAPIKey()
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear Key") {
                            clearAPIKey()
                        }
                        .disabled(!hasStoredAPIKey)

                        Button("Test OpenAI") {
                            Task { await testOpenAIConnection() }
                        }
                        .disabled(resolvedOpenAIEndpointURL == nil || !hasStoredAPIKey)

                        Text(hasStoredAPIKey ? "Key stored" : "No key stored")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(openAITestBadgeText)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }
                    #endif

                    Divider()

                    #if os(iOS)
                    Button {
                        showOpenAIKeyBrowser = true
                    } label: {
                        Label("Get API Key from OpenAI", systemImage: "globe")
                    }
                    Text("Opens the OpenAI platform in-app to create or copy your API key.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    #else
                    HStack {
                        Button {
                            showOpenAIKeyBrowser = true
                        } label: {
                            Label("Get API Key from OpenAI", systemImage: "globe")
                        }
                        Text("Opens the OpenAI platform in-app to create or copy your API key.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    #endif
                }
            }
            .sheet(isPresented: $showOpenAIKeyBrowser) {
                OpenAIKeyBrowserSheet(apiKeyDraft: $apiKeyDraft, hasStoredAPIKey: $hasStoredAPIKey)
            }
            #if os(iOS)
            .sheet(isPresented: $showDiagnosticsConsole) {
                NavigationStack {
                    DiagnosticsConsoleView()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { showDiagnosticsConsole = false }
                            }
                        }
                }
            }
            #endif

            Section("Anthropic Claude") {
                HStack {
                    if showClaudeAPIKey {
                        TextField("Anthropic API Key", text: $claudeAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveClaudeAPIKey() }
                            #endif
                    } else {
                        SecureField("Anthropic API Key", text: $claudeAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveClaudeAPIKey() }
                            #endif
                    }

                    Button(showClaudeAPIKey ? "Hide" : "Show") {
                        showClaudeAPIKey.toggle()
                    }
                }

                #if os(iOS)
                HStack(spacing: 12) {
                    Button("Save Key") {
                        saveClaudeAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear") {
                        clearClaudeAPIKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredClaudeAPIKey)

                    Button("Test") {
                        Task { await testClaudeConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredClaudeAPIKey || draftClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: hasStoredClaudeAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(hasStoredClaudeAPIKey ? .green : .secondary)
                        .font(.caption)
                    Text(hasStoredClaudeAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if claudeTestBadgeText != "Not tested" {
                    Text(claudeTestBadgeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #else
                HStack {
                    Button("Save Key") {
                        saveClaudeAPIKey()
                    }
                    .disabled(claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Key") {
                        clearClaudeAPIKey()
                    }
                    .disabled(!hasStoredClaudeAPIKey)

                    Button("Test Claude") {
                        Task { await testClaudeConnection() }
                    }
                    .disabled(!hasStoredClaudeAPIKey || draftClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(hasStoredClaudeAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if claudeTestBadgeText != "Not tested" {
                        Text(claudeTestBadgeText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                #endif

                Picker("Claude Model", selection: $draftClaudeModel) {
                    ForEach(claudeModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                TextField("Custom model", text: $draftClaudeModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Section("xAI Grok") {
                HStack {
                    if showGrokAPIKey {
                        TextField("Grok API Key", text: $grokAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveGrokAPIKey() }
                            #endif
                    } else {
                        SecureField("Grok API Key", text: $grokAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveGrokAPIKey() }
                            #endif
                    }

                    Button(showGrokAPIKey ? "Hide" : "Show") {
                        showGrokAPIKey.toggle()
                    }
                }

                #if os(iOS)
                HStack(spacing: 12) {
                    Button("Save Key") {
                        saveGrokAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear") {
                        clearGrokAPIKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredGrokAPIKey)

                    Button("Test") {
                        Task { await testGrokConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredGrokAPIKey || draftGrokModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: hasStoredGrokAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(hasStoredGrokAPIKey ? .green : .secondary)
                        .font(.caption)
                    Text(hasStoredGrokAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if grokTestBadgeText != "Not tested" {
                    Text(grokTestBadgeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #else
                HStack {
                    Button("Save Key") {
                        saveGrokAPIKey()
                    }
                    .disabled(grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Key") {
                        clearGrokAPIKey()
                    }
                    .disabled(!hasStoredGrokAPIKey)

                    Button("Test Grok") {
                        Task { await testGrokConnection() }
                    }
                    .disabled(!hasStoredGrokAPIKey || draftGrokModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(hasStoredGrokAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if grokTestBadgeText != "Not tested" {
                        Text(grokTestBadgeText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                #endif

                Picker("Grok Model", selection: $draftGrokModel) {
                    ForEach(grokModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                TextField("Custom model", text: $draftGrokModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
            }

            Section("Google Gemini") {
                HStack {
                    if showGeminiAPIKey {
                        TextField("Gemini API Key", text: $geminiAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveGeminiAPIKey() }
                            #endif
                    } else {
                        SecureField("Gemini API Key", text: $geminiAPIKeyDraft)
                            .textFieldStyle(.roundedBorder)
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .textContentType(.none)
                            .submitLabel(.done)
                            .onSubmit { saveGeminiAPIKey() }
                            #endif
                    }

                    Button(showGeminiAPIKey ? "Hide" : "Show") {
                        showGeminiAPIKey.toggle()
                    }
                }

                #if os(iOS)
                HStack(spacing: 12) {
                    Button("Save Key") {
                        saveGeminiAPIKey()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear") {
                        clearGeminiAPIKey()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredGeminiAPIKey)

                    Button("Test") {
                        Task { await testGeminiConnection() }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!hasStoredGeminiAPIKey || draftGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Spacer()
                }

                HStack(spacing: 6) {
                    Image(systemName: hasStoredGeminiAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundColor(hasStoredGeminiAPIKey ? .green : .secondary)
                        .font(.caption)
                    Text(hasStoredGeminiAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if geminiTestBadgeText != "Not tested" {
                    Text(geminiTestBadgeText)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                #else
                HStack {
                    Button("Save Key") {
                        saveGeminiAPIKey()
                    }
                    .disabled(geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Clear Key") {
                        clearGeminiAPIKey()
                    }
                    .disabled(!hasStoredGeminiAPIKey)

                    Button("Test Gemini") {
                        Task { await testGeminiConnection() }
                    }
                    .disabled(!hasStoredGeminiAPIKey || draftGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Text(hasStoredGeminiAPIKey ? "Key stored" : "No key stored")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if geminiTestBadgeText != "Not tested" {
                        Text(geminiTestBadgeText)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                #endif

                Picker("Gemini Model", selection: $draftGeminiModel) {
                    ForEach(geminiModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }
                .pickerStyle(.menu)

                TextField("Custom model", text: $draftGeminiModel)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)

                Text("Note: Gemini uses API key as a query parameter, not a header.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Connection") {
                TextField("OpenAI Endpoint", text: $draftOpenAIEndpoint)
                    .textFieldStyle(.roundedBorder)
            }

            Section("Defaults") {
                Picker("Prompt Preset", selection: selectedPreset) {
                    ForEach(AIPromptPreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }

                Picker("Default Scope", selection: defaultScope) {
                    ForEach(AISelectionScope.allCases) { scope in
                        Text(scope.label).tag(scope)
                    }
                }

                Toggle("Auto-run on Pipeline Apply", isOn: $draftAutoRun)

                Toggle("Structured JSON Output", isOn: $draftStructuredOutputEnabled)
                Text("Forces AI responses into a JSON schema for tables and reports.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("CoreML SPF Model") {
                let mlPredict = SPFPredictionService.shared
                let mlTrain = MLTrainingService.shared

                // Status indicator
                HStack(spacing: 8) {
                    Circle()
                        .fill(mlPredict.status.isReady ? Color.green :
                              mlTrain.status.isInProgress ? Color.orange : Color.secondary)
                        .frame(width: 8, height: 8)
                    Text(mlPredict.status.label)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Reference data count
                HStack {
                    Text("Reference spectra available:")
                        .font(.caption)
                    Spacer()
                    Text("\(mlTrain.availableSpectrumCount)")
                        .font(.caption)
                        .foregroundColor(mlTrain.availableSpectrumCount >= MLTrainingService.minimumSpectra ? .primary : .orange)
                }

                // Last trained info
                if let result = mlTrain.lastResult {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Last trained:")
                                .font(.caption)
                            Spacer()
                            Text(result.trainedAt, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("Datasets / Spectra:")
                                .font(.caption)
                            Spacer()
                            Text("\(result.datasetCount) / \(result.spectrumCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        HStack {
                            Text("R²:")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.3f", result.r2))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(result.r2 >= 0.85 ? .green : .orange)
                        }
                        HStack {
                            Text("RMSE:")
                                .font(.caption)
                            Spacer()
                            Text(String(format: "%.2f", result.rmse))
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // Training progress
                if case .training(let progress) = mlTrain.status {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                    Text(mlTrain.status.label)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if case .preparingData = mlTrain.status {
                    ProgressView()
                        .controlSize(.small)
                    Text("Preparing training data…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if case .evaluating = mlTrain.status {
                    ProgressView()
                        .controlSize(.small)
                    Text("Evaluating model…")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else if case .failed(let msg) = mlTrain.status {
                    Text(msg)
                        .font(.caption)
                        .foregroundColor(.red)
                }

                #if os(macOS)
                // Train button
                Button {
                    Task {
                        await mlTrain.train(modelContext: modelContext)
                    }
                } label: {
                    Label("Train Model", systemImage: "brain")
                }
                .disabled(!mlTrain.canTrain)
                .help(mlTrain.availableSpectrumCount < MLTrainingService.minimumSpectra
                      ? "Need at least \(MLTrainingService.minimumSpectra) reference spectra"
                      : "Train a boosted tree regressor from reference datasets")

                // Reset button
                if mlPredict.status.isReady || mlTrain.lastResult != nil {
                    Button(role: .destructive) {
                        mlTrain.resetModel()
                    } label: {
                        Label("Reset Model", systemImage: "trash")
                    }
                }
                #else
                if mlPredict.status.isReady {
                    Text("Model loaded and ready for predictions.")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if case .error(let msg) = mlPredict.status {
                    Text("Model error: \(msg)")
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("No trained model found. Train on Mac — the model syncs automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Button {
                    mlPredict.loadModelIfAvailable()
                } label: {
                    Label("Reload Model", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                #endif

                if mlTrain.availableSpectrumCount < MLTrainingService.minimumSpectra {
                    Text("Tag at least \(MLTrainingService.minimumSpectra) reference datasets with known in-vivo SPF values in Data Management to enable training.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            } // end AI tab

            if selectedSettingsTab == .sync {
            Section("iCloud Sync") {
                Toggle("Enable iCloud Sync (CloudKit)", isOn: $icloudSyncEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("icloudSyncToggle")
                    .onChange(of: icloudSyncEnabled) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        if suppressIcloudSyncConfirmation {
                            suppressIcloudSyncConfirmation = false
                            return
                        }
                        pendingIcloudSyncEnabled = newValue
                        suppressIcloudSyncConfirmation = true
                        icloudSyncEnabled = oldValue
                        showIcloudSyncResetAlert = true
                    }
                    .alert("Confirm iCloud Sync Change", isPresented: $showIcloudSyncResetAlert) {
                        Button("Cancel", role: .cancel) {
                            pendingIcloudSyncEnabled = nil
                        }
                        Button("Continue", role: .destructive) {
                            guard let requested = pendingIcloudSyncEnabled else { return }
                            suppressIcloudSyncConfirmation = true
                            icloudSyncEnabled = requested
                            dataStoreController.setCloudSyncEnabled(requested)
                            ICloudSyncCoordinator.shared.scheduleBackupTimerIfNeeded()
                            pendingIcloudSyncEnabled = nil
                        }
                    } message: {
                        Text("Switching iCloud Sync will reset the local store. Make sure you have exported any data you want to keep before continuing.")
                    }

                Toggle("Sync Settings via iCloud", isOn: $icloudSettingsSyncEnabled)
                    .accessibilityIdentifier("icloudSettingsSyncToggle")
                    .onChange(of: icloudSettingsSyncEnabled) { _, isEnabled in
                        if isEnabled {
                            ICloudSyncCoordinator.shared.pushDefaultsToICloud()
                        }
                    }

                if dataStoreController.cloudKitUnavailable {
                    Text(dataStoreController.cloudKitUnavailableMessage.isEmpty
                         ? "CloudKit is unavailable. The app is using local storage until it becomes available."
                         : dataStoreController.cloudKitUnavailableMessage
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)

                    Button("Retry CloudKit") {
                        icloudSyncEnabled = true
                        dataStoreController.setCloudSyncEnabled(true)
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    .accessibilityIdentifier("retryCloudKitButton")
                }

                HStack {
                    Text("Store Mode")
                    Spacer()
                    Text(storeModeLabel)
                        .foregroundColor(.secondary)
                        .accessibilityIdentifier("storeModeValue")
                }

                if isLocalStore && icloudSyncEnabled {
                    Text("Local storage is active. Migration will start automatically.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button("Force Full Sync") {
                        Task { await dataStoreController.forceFullSync() }
                    }
                    .disabled(!icloudSyncEnabled)
                    .accessibilityIdentifier("forceFullSyncButton")

                    Button("Force Upload") {
                        Task { await ICloudSyncCoordinator.shared.forceCloudKitUpload() }
                    }
                    .disabled(!icloudSyncEnabled)
                    .accessibilityIdentifier("forceUploadButton")

                    Spacer()

                    Button("Reset Local Store") {
                        if dataStoreController.syncState.isActive {
                            pendingLocalReset = true
                            showLocalResetQueuedAlert = true
                            dataStoreController.setQueuedActionMessage("Queued local store reset")
                        } else {
                            showLocalStoreResetAlert = true
                        }
                    }
                    .accessibilityIdentifier("resetLocalStoreButton")
                    .alert("Reset Local Store", isPresented: $showLocalStoreResetAlert) {
                        Button("Cancel", role: .cancel) { }
                        Button("Reset", role: .destructive) {
                            Task {
                                let result = await ICloudSyncCoordinator.shared.resetLocalStoreForRestore()
                                await MainActor.run {
                                    localStoreResetResult = result
                                    if !result.isEmpty {
                                        storeResetMessage = result
                                        storeResetTimestamp = Date().timeIntervalSince1970
                                        appendStoreResetHistory(message: result)
                                    }
                                    suppressIcloudSyncConfirmation = true
                                    icloudSyncEnabled = false
                                    dataStoreController.setCloudSyncEnabled(false)
                                    if result.lowercased().contains("reset") {
                                        UserDefaults.standard.set(true, forKey: ICloudDefaultsKeys.skipBackupOnCloseOnce)
                                        relaunchApp()
                                    }
                                }
                            }
                        }
                    } message: {
                        Text("This deletes the local SwiftData store files (including WAL/SHM), disables iCloud sync, and relaunches the app. Make sure you have exported any data you want to keep.")
                    }
                    .alert("Sync In Progress", isPresented: $showLocalResetQueuedAlert) {
                        Button("OK", role: .cancel) { }
                    } message: {
                        Text("A sync is currently running. The reset will be available once it completes.")
                    }
                    .onChange(of: dataStoreController.syncState.isActive) { _, isActive in
                        if !isActive && pendingLocalReset {
                            pendingLocalReset = false
                            dataStoreController.setQueuedActionMessage(nil)
                            showLocalStoreResetAlert = true
                        }
                    }
                }

                if dataStoreController.syncState.isActive {
                    CloudSyncProgressView(state: dataStoreController.syncState)
                }

                HStack {
                    Text("Backup size")
                    Spacer()
                    Text(iCloudBackupSizeText)
                        .foregroundColor(.secondary)
                    Button("Recalculate") {
                        Task { await refreshBackupSize() }
                    }
                    .disabled(!icloudSyncEnabled)
                }

                Text(iCloudSyncStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(iCloudBackupStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(iCloudRestoreStatusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Sync status history")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if dataStoreController.syncHistory.isEmpty {
                        Text("No sync history yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(dataStoreController.syncHistory.prefix(8)) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.message)
                                    .font(.caption)
                                if !entry.detail.isEmpty {
                                    Text(entry.detail)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                Text(Self.storeResetDateFormatter.string(from: entry.timestamp))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if dataStoreController.syncHistory.count > 8 {
                            Text("Showing most recent 8 of \(dataStoreController.syncHistory.count)")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                #if DEBUG
                Button("Show CloudKit Debug") {
                    showICloudDebugPanel.toggle()
                }
                #if os(macOS)
                .buttonStyle(.link)
                #else
                .buttonStyle(.borderless)
                #endif
                #endif

                Toggle("Automatic backups", isOn: $icloudAutoBackupEnabled)
                    .onChange(of: icloudAutoBackupEnabled) { _, _ in
                        ICloudSyncCoordinator.shared.scheduleBackupTimerIfNeeded()
                    }

                Divider()

                Text("Storage reset history")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack {
                    Text("Last reset")
                    Spacer()
                    Text(storeResetTimestampText)
                        .foregroundColor(.secondary)
                }

                if !storeResetMessage.isEmpty {
                    Text(storeResetMessage)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if storeResetHistoryEntries.isEmpty {
                    Text("No resets recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(storeResetHistoryEntries.prefix(5)) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.message)
                                .font(.caption)
                            Text(Self.storeResetDateFormatter.string(from: entry.timestamp))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }

                    if storeResetHistoryEntries.count > 5 {
                        Text("Showing most recent 5 of \(storeResetHistoryEntries.count)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Button("Clear History") {
                        storeResetHistoryData = Data()
                        storeResetMessage = ""
                        storeResetTimestamp = 0.0
                    }
                }

                HStack {
                    Text("CloudKit polling (minutes)")
                    Spacer()
                    Stepper(value: $icloudPollingIntervalMinutes, in: 5...120, step: 5) {
                        Text("\(Int(icloudPollingIntervalMinutes))")
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: icloudPollingIntervalMinutes) { _, _ in
                    CloudKitSyncMonitor.shared.startPollingIfNeeded()
                }

                HStack {
                    Text("Backup interval (hours)")
                    Spacer()
                    Stepper(value: $icloudBackupIntervalHours, in: 0.25...48, step: 0.25) {
                        Text(String(format: "%.2f", icloudBackupIntervalHours))
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: icloudBackupIntervalHours) { _, _ in
                    ICloudSyncCoordinator.shared.scheduleBackupTimerIfNeeded()
                }

                Toggle("Backup on Close", isOn: $icloudBackupOnClose)

                Text("All data is encrypted at rest and in transit by CloudKit. Backups include raw spectra data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            } // end Sync tab

            if selectedSettingsTab == .ai {
            Section("Model") {
                Picker("OpenAI Model", selection: $draftOpenAIModel) {
                    ForEach(openAIModelChoices, id: \.self) { model in
                        Text(model).tag(model)
                    }
                }

                TextField("Custom Model", text: $draftOpenAIModel)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Button(isFetchingOpenAIModels ? "Loading…" : "Refresh Models") {
                        Task { await fetchOpenAIModels() }
                    }
                    .disabled(isFetchingOpenAIModels || !hasStoredAPIKey || !canResolveOpenAIHost)

                    if let openAIModelFetchStatus {
                        Text(openAIModelFetchStatus)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                HStack {
                    Text("Temperature")
                    Slider(value: $draftTemperature, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", draftTemperature))
                        .frame(width: 44, alignment: .trailing)
                        .foregroundColor(.secondary)
                }

                Stepper(value: $draftMaxTokens, in: 128...8192, step: 64) {
                    Text("Max Tokens: \(draftMaxTokens)")
                }
            }

            Section("AI Response") {
                HStack {
                    Text("Response Text Size")
                    Spacer()
                    Text(String(format: "%.1f pt", draftAIResponseTextSize))
                        .foregroundColor(.secondary)
                }
                Slider(value: $draftAIResponseTextSize, in: 10...24, step: 0.5)
                HStack {
                    Button("Reset to Default") {
                        draftAIResponseTextSize = 18.0
                    }
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .buttonStyle(.borderless)
                    #endif
                    Spacer()
                }
            }

            Section("Diagnostics") {
                Toggle("Enable Diagnostics", isOn: $draftDiagnosticsEnabled)
                Text("When enabled, the app logs AI requests/responses and network errors to the system log for troubleshooting.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Toggle("Clear Logs on Quit", isOn: $draftClearLogsOnQuit)

                Button("View Log Stream") {
                    #if os(macOS)
                    openWindow(id: "diagnostics-console")
                    #else
                    showDiagnosticsConsole = true
                    #endif
                }
                .disabled(!draftDiagnosticsEnabled)

                Divider()

                HStack {
                    Button("Test DNS") {
                        runDNSCheck()
                    }

                    Button("Copy DNS Results") {
                        copyDNSResults()
                    }
                    .disabled(dnsStatusMessage == nil)

                    Spacer()
                }

                if let msg = dnsStatusMessage {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(msg.components(separatedBy: "\n"), id: \.self) { line in
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(line.contains("Resolved") ? Color.green : Color.red)
                                    .frame(width: 6, height: 6)
                                Text(line)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        if let ts = dnsStatusTimestamp {
                            Text(RelativeDateTimeFormatter().localizedString(for: ts, relativeTo: Date()))
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Text(proxyStatusLabel)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            } // end AI tab (Model, Response, Diagnostics sections)

            if selectedSettingsTab == .advanced {
            Section("Instrumentation") {
                Toggle("Enable Instrumentation", isOn: $draftInstrumentationEnabled)
                    .toggleStyle(.switch)

                Toggle("Enhanced Diagnostic Logging", isOn: $draftInstrumentationEnhancedDiagnostics)
                    .toggleStyle(.switch)

                Text("Instrumentation adds structured tracing across the app. Enhanced logging includes payload sizes and timings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Instrumentation Areas") {
                Toggle("Import/Parsing", isOn: $draftInstrumentationAreaImportParsing)
                Toggle("Processing Pipeline", isOn: $draftInstrumentationAreaProcessing)
                Toggle("Chart Rendering", isOn: $draftInstrumentationAreaChartRendering)
                Toggle("AI Analysis", isOn: $draftInstrumentationAreaAIAnalysis)
                Toggle("Export", isOn: $draftInstrumentationAreaExport)
                Toggle("UI Interactions", isOn: $draftInstrumentationAreaUI)
                Toggle("ML Training", isOn: $draftInstrumentationAreaMLTraining)
            }

            Section("Instrumentation Outputs") {
                Toggle("In-App Log Panel", isOn: $draftInstrumentationOutputInApp)
                Toggle("Console Logs", isOn: $draftInstrumentationOutputConsole)
                Toggle("File Logs", isOn: $draftInstrumentationOutputFile)
                Toggle("OSLog", isOn: $draftInstrumentationOutputOSLog)

                Button("Open Diagnostics Console") {
                    #if os(macOS)
                    openWindow(id: "diagnostics-console")
                    #else
                    showDiagnosticsConsole = true
                    #endif
                }
            }

            Section("Instrumentation Detail Level") {
                Toggle("Errors", isOn: $draftInstrumentationLevelErrors)
                Toggle("Warnings", isOn: $draftInstrumentationLevelWarnings)
                Toggle("Verbose (timings + payload sizes)", isOn: $draftInstrumentationLevelVerbose)
            }
            } // end Advanced tab

            if selectedSettingsTab == .enterprise {
            Section("Microsoft 365 Account") {
                if m365AuthManager.isSignedIn {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .foregroundColor(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Signed in")
                                .font(.subheadline.bold())
                            if let username = m365AuthManager.username {
                                Text(username)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        Button("Sign Out") {
                            Task { try? await m365AuthManager.signOut() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } else {
                    HStack {
                        Image(systemName: "person.crop.circle.badge.xmark")
                            .foregroundColor(.secondary)
                        Text("Not signed in")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Sign In") {
                            Task {
                                m365SignInError = nil
                                do {
                                    let scopes = draftGroundingConfig.requiredScopes
                                    _ = try await m365AuthManager.signIn(scopes: scopes)
                                } catch {
                                    m365SignInError = error.localizedDescription
                                }
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    if let m365SignInError {
                        Text(m365SignInError)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }

                Text("Sign in with your Microsoft 365 work account to enable enterprise features.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Tenant Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Client ID (Entra App Registration)")
                        .font(.caption.bold())
                    TextField("Client ID", text: $draftM365ClientId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("m365ClientId")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Tenant ID")
                        .font(.caption.bold())
                    TextField("Tenant ID", text: $draftM365TenantId)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .accessibilityIdentifier("m365TenantId")
                }
                Text("Enter your Entra app registration credentials. These are required for all M365 features.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftM365ClientId == M365Config.defaultClientId || draftM365TenantId == M365Config.defaultTenantId {
                    Label("Placeholder values detected. Update with your Entra app registration.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section("Connection Test") {
                if m365Validator.hasResults {
                    connectionTestRow("Authentication", status: m365Validator.authStatus, icon: "person.badge.key")
                    connectionTestRow("SharePoint", status: m365Validator.sharePointStatus, icon: "building.columns.fill")
                    connectionTestRow("OneDrive", status: m365Validator.oneDriveStatus, icon: "externaldrive.fill.badge.icloud")
                    connectionTestRow("Teams", status: m365Validator.teamsStatus, icon: "bubble.left.and.bubble.right.fill")
                }

                HStack {
                    Button {
                        Task {
                            await m365Validator.runAll(authManager: m365AuthManager)
                        }
                    } label: {
                        Label("Verify Configuration", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        draftM365ClientId == M365Config.defaultClientId
                        || draftM365TenantId == M365Config.defaultTenantId
                        || m365Validator.isRunning
                    )

                    if m365Validator.isRunning {
                        ProgressView()
                            .controlSize(.small)
                    } else if m365Validator.allPassed {
                        Label("All services connected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }

                Text("Tests authentication, SharePoint, OneDrive, and Teams connectivity using your Tenant ID and Client ID. Discovered service URLs are shown above.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Enterprise Grounding") {
                Toggle("Enable Enterprise Grounding", isOn: $draftGroundingConfig.isEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("m365GroundingToggle")

                Text("Enrich AI analysis with relevant documents from your Microsoft 365 tenant (SharePoint, OneDrive, Copilot Connectors).")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftGroundingConfig.isEnabled {
                    // Per-function toggles
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Grounding Scope")
                            .font(.subheadline.bold())

                        Toggle("Spectral Analysis", isOn: $draftGroundingConfig.enabledForSpectralAnalysis)
                            .toggleStyle(.switch)
                        Text("Inject relevant SOPs, protocols, and product history into spectral analysis prompts.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Formula Card Parsing", isOn: $draftGroundingConfig.enabledForFormulaCardParsing)
                            .toggleStyle(.switch)
                        Text("Cross-reference ingredient lists with enterprise formulation databases.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Data source checkboxes
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Data Sources")
                            .font(.subheadline.bold())

                        ForEach(RetrievalDataSource.allCases) { source in
                            Toggle(isOn: Binding(
                                get: { draftGroundingConfig.enabledDataSources.contains(source) },
                                set: { isOn in
                                    if isOn {
                                        draftGroundingConfig.enabledDataSources.insert(source)
                                    } else {
                                        draftGroundingConfig.enabledDataSources.remove(source)
                                    }
                                }
                            )) {
                                Label(source.displayName, systemImage: source.iconName)
                            }
                            .toggleStyle(.switch)
                        }
                    }

                    // Max results slider
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Max Results per Source: \(draftGroundingConfig.maxResultsPerSource)")
                            .font(.subheadline.bold())
                        Slider(
                            value: Binding(
                                get: { Double(draftGroundingConfig.maxResultsPerSource) },
                                set: { draftGroundingConfig.maxResultsPerSource = Int($0) }
                            ),
                            in: 1...25,
                            step: 1
                        )
                        Text("Higher values provide more context but increase latency and token usage.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Section("SharePoint Site Filters") {
                Text("Scope retrieval to specific SharePoint sites. Leave empty to search all accessible sites.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                ForEach(Array(draftGroundingConfig.sharePointSiteFilters.enumerated()), id: \.offset) { index, filter in
                    HStack {
                        Image(systemName: "building.columns.fill")
                            .foregroundColor(.accentColor)
                            .frame(width: 16)
                        Text(filter)
                            .font(.system(.caption, design: .monospaced))
                            .lineLimit(1)
                        Spacer()
                        Button {
                            draftGroundingConfig.sharePointSiteFilters.remove(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    TextField("https://tenant.sharepoint.com/sites/...", text: $draftSiteFilterText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                    Button("Add") {
                        let trimmed = draftSiteFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            draftGroundingConfig.sharePointSiteFilters.append(trimmed)
                            draftSiteFilterText = ""
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(draftSiteFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Section("SharePoint Export") {
                Toggle("Enable SharePoint Export", isOn: $draftExportConfig.isEnabled)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("m365ExportToggle")

                Text("Export analysis results and files to SharePoint document libraries.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if draftExportConfig.isEnabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination Site")
                            .font(.caption.bold())
                        TextField("https://tenant.sharepoint.com/sites/...", text: $draftExportConfig.destinationSitePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Destination Folder")
                            .font(.caption.bold())
                        TextField("/Shared Documents/Results/", text: $draftExportConfig.destinationFolderPath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("File Naming Template")
                            .font(.caption.bold())
                        TextField("{date}_{product}_{type}", text: $draftExportConfig.namingTemplate)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))
                        Text("Placeholders: {date}, {product}, {type}, {spf}")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Toggle("Auto-Export on Analysis Complete", isOn: $draftExportConfig.autoExportResults)
                        .toggleStyle(.switch)
                    Text("Automatically upload analysis results to SharePoint when AI analysis finishes.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Section("Teams Sync") {
                Toggle("Enable Teams Sync", isOn: Binding(
                    get: { TeamsSyncMonitor.shared.isEnabled },
                    set: { newValue in
                        TeamsSyncMonitor.shared.isEnabled = newValue
                        if newValue {
                            TeamsSyncMonitor.shared.start(authManager: m365AuthManager)
                        } else {
                            TeamsSyncMonitor.shared.stop()
                        }
                    }
                ))
                .toggleStyle(.switch)

                Text("When enabled, Teams data is cached locally for offline access and faster loading.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if TeamsSyncMonitor.shared.isEnabled {
                    HStack {
                        Text("Polling Interval")
                        Spacer()
                        Picker("", selection: Binding(
                            get: { TeamsSyncMonitor.shared.pollingIntervalMinutes },
                            set: { TeamsSyncMonitor.shared.pollingIntervalMinutes = $0 }
                        )) {
                            Text("1 min").tag(1.0)
                            Text("5 min").tag(5.0)
                            Text("15 min").tag(15.0)
                            Text("30 min").tag(30.0)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 300)
                    }

                    Toggle("Notifications for New Messages", isOn: Binding(
                        get: { TeamsSyncMonitor.shared.notificationsEnabled },
                        set: { TeamsSyncMonitor.shared.notificationsEnabled = $0 }
                    ))
                    .toggleStyle(.switch)

                    Text("Show a notification when new Teams messages are detected during sync.")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack {
                        Text("Last Sync")
                        Spacer()
                        if let date = TeamsSyncMonitor.shared.lastSyncDate {
                            Text(date, format: .relative(presentation: .named))
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Never")
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button("Clear Teams Cache", role: .destructive) {
                        try? TeamsSyncService.clearCache()
                    }
                }
            }
            } // end Enterprise tab

            if selectedSettingsTab == .mlTraining {
            Section("PINN Training Defaults") {
                Stepper("Default Epochs: \(draftPinnDefaultEpochs)", value: $draftPinnDefaultEpochs, in: 100...2000, step: 100)
                Text("Number of training epochs for PINN physics models. Higher values may improve accuracy but increase training time.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Default Learning Rate:")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0e", draftPinnDefaultLearningRate))
                            .monospacedDigit()
                            .font(.caption)
                    }
                    Slider(
                        value: Binding(
                            get: { log10(draftPinnDefaultLearningRate) },
                            set: { draftPinnDefaultLearningRate = pow(10, $0) }
                        ),
                        in: -5...(-1),
                        step: 0.5
                    )
                }
                Text("Controls how quickly the model adjusts during training. Smaller values are more stable but slower.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            #if os(macOS)
            Section("Python Environment") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Python Path")
                        .font(.subheadline)
                    TextField("/opt/homebrew/bin/python3", text: $draftPinnPythonPath)
                        .textFieldStyle(.roundedBorder)
                        .monospaced()
                }

                HStack(spacing: 12) {
                    Button {
                        isDetectingPython = true
                        pythonDetectionResult = PythonEnvironmentDetector.detectAll()
                        // Auto-select recommended Python — triggers on any default/generic path
                        if let rec = pythonDetectionResult?.recommended,
                           draftPinnPythonPath == "/usr/bin/env python3"
                            || draftPinnPythonPath == "/opt/homebrew/bin/python3"
                            || draftPinnPythonPath == "/usr/local/bin/python3"
                            || draftPinnPythonPath.isEmpty {
                            draftPinnPythonPath = rec.path
                        }
                        // Auto-install training scripts into Scripts directory
                        let scriptResult = PINNScriptInstaller.installAllScripts()
                        scriptInstallMessage = "Installed \(scriptResult.installed.count)/\(PINNDomain.allCases.count) training scripts"
                        isDetectingPython = false
                    } label: {
                        Label("Detect & Setup", systemImage: "magnifyingglass")
                    }

                    if isDetectingPython {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                // Detection results
                if let result = pythonDetectionResult {
                    // Homebrew status
                    if let brew = result.homebrew {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Homebrew detected (\(brew.isAppleSilicon ? "Apple Silicon" : "Intel"))")
                                .font(.caption)
                        }
                    } else {
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Homebrew not found — recommended for Python package management")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    if result.installations.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text("No Python 3.10+ found on this system.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Found \(result.installations.count) installation\(result.installations.count == 1 ? "" : "s"):")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            ForEach(result.installations) { install in
                                HStack(spacing: 8) {
                                    // Status indicator
                                    Image(systemName: install.hasTorch && install.hasCoreMLTools
                                          ? "checkmark.circle.fill"
                                          : install.hasTorch || install.hasCoreMLTools
                                          ? "exclamationmark.circle.fill"
                                          : "xmark.circle.fill")
                                    .foregroundColor(install.hasTorch && install.hasCoreMLTools
                                                     ? .green
                                                     : install.hasTorch || install.hasCoreMLTools
                                                     ? .orange
                                                     : .red)
                                    .font(.caption)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(install.summary)
                                            .font(.caption)
                                        Text(install.path)
                                            .font(.caption2)
                                            .monospaced()
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }

                                    Spacer()

                                    if install.path == draftPinnPythonPath {
                                        Text("Active")
                                            .font(.caption2)
                                            .foregroundColor(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.green.opacity(0.15))
                                            .cornerRadius(4)
                                    } else {
                                        Button("Use") {
                                            draftPinnPythonPath = install.path
                                        }
                                        .font(.caption)
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }

                    // Warnings
                    ForEach(result.warnings, id: \.self) { warning in
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(warning)
                                .font(.caption)
                        }
                    }

                    // Actionable package installation
                    #if os(macOS)
                    if let rec = result.recommended {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Package Status:")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            // Package status indicators (all 5)
                            let packageChecks: [(name: String, installed: Bool)] = [
                                ("PyTorch", rec.hasTorch),
                                ("coremltools", rec.hasCoreMLTools),
                                ("scikit-learn", rec.hasSciKitLearn),
                                ("NumPy", rec.hasNumpy),
                                ("SciPy", rec.hasScipy)
                            ]
                            ForEach(packageChecks, id: \.name) { pkg in
                                HStack(spacing: 6) {
                                    Image(systemName: pkg.installed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(pkg.installed ? .green : .red)
                                        .font(.caption)
                                    Text(pkg.installed ? "\(pkg.name) installed" : "\(pkg.name) not installed")
                                        .font(.caption)
                                        .foregroundColor(pkg.installed ? .primary : .primary)
                                }
                            }

                            if !rec.hasAllMLPackages {
                                // Build list of only missing packages for targeted install
                                let missingPackages: [String] = {
                                    var missing: [String] = []
                                    if !rec.hasTorch { missing.append("torch") }
                                    if !rec.hasCoreMLTools { missing.append("coremltools") }
                                    if !rec.hasSciKitLearn { missing.append("scikit-learn") }
                                    if !rec.hasNumpy { missing.append("numpy") }
                                    if !rec.hasScipy { missing.append("scipy") }
                                    return missing
                                }()

                                // Install missing button — opens Terminal for Tahoe compatibility
                                let detectedMethod = PackageInstaller.detectInstallMethod()
                                Button {
                                    packageInstaller.installPackages(
                                        missingPackages,
                                        pythonPath: rec.path,
                                        method: detectedMethod
                                    )
                                } label: {
                                    Label(
                                        "Install Missing Packages",
                                        systemImage: "terminal"
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                                .disabled(packageInstaller.isInstalling)

                                // Install method indicator
                                HStack(spacing: 4) {
                                    Image(systemName: "terminal")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                    Text("Opens Terminal — pip install \(missingPackages.joined(separator: ", "))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.05))
                        .cornerRadius(8)

                        // Version upgrade recommendation (Homebrew opens Terminal with quarantine removed)
                        if rec.minor < 12 {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.circle")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text("Python \(rec.version) — consider upgrading to 3.12+")
                                    .font(.caption)
                                Spacer()
                                Button {
                                    PythonEnvironmentDetector.installPythonViaBrew()
                                } label: {
                                    Label("Upgrade via Homebrew", systemImage: "terminal")
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    // No Python at all — offer Homebrew install (Terminal needed for Homebrew)
                    if result.installations.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No Python 3.10+ found. Install via Homebrew:")
                                .font(.caption)
                            Button {
                                PythonEnvironmentDetector.installPythonViaBrew()
                            } label: {
                                Label("Install Python + ML Packages via Homebrew", systemImage: "terminal")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            Text("Opens Terminal to install Homebrew (if needed), Python 3.12, and all required ML packages.")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.05))
                        .cornerRadius(8)
                    }

                    // Terminal installation status
                    if !packageInstaller.status.isIdle {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                switch packageInstaller.status {
                                case .idle:
                                    EmptyView()
                                case .waitingForTerminal:
                                    ProgressView()
                                        .controlSize(.small)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Installing in Terminal...")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("When Terminal finishes, click \"Detect & Setup\" to verify.")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                case .succeeded:
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.caption)
                                    Text("Installation complete")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                case .failed(let msg):
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                        .font(.caption)
                                    Text(msg)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                                Spacer()
                                Button("Dismiss") {
                                    packageInstaller.reset()
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(8)
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }
                    #endif
                }

                // MARK: Step 3 — Training Data Downloads
                #if os(macOS)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Training Data:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    // Per-domain download status
                    let summary = TrainingDataDownloader.allDomainsDownloadSummary()
                    let domainsWithData = summary.filter { $0.fileCount > 0 }

                    if domainsWithData.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.down.doc")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("No training data downloaded yet")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(domainsWithData, id: \.domain) { item in
                                HStack(spacing: 6) {
                                    Image(systemName: item.domain.iconName)
                                        .foregroundColor(.green)
                                        .font(.caption2)
                                        .frame(width: 14)
                                    Text("\(item.domain.displayName)")
                                        .font(.caption)
                                    Spacer()
                                    let suffix: String = item.fileCount == 1 ? "" : "s"
                                    let sizeStr = TrainingDataDownloader.formattedSize(bytes: item.size)
                                    Text("\(item.fileCount) file\(suffix) · \(sizeStr)")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            Task {
                                await trainingDataDownloader.downloadAllDomains()
                            }
                        } label: {
                            Label(
                                "Download Training Data (All Domains)",
                                systemImage: "arrow.down.circle"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(trainingDataDownloader.isAnyDomainActive)

                        if TrainingDataDownloader.hasAnyDownloadedData {
                            Button {
                                let dir = PINNTrainingManager.trainingDataDirectory
                                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                                PlatformURLOpener.open(dir)
                            } label: {
                                Label("Open Folder", systemImage: "folder")
                            }
                            .font(.caption)
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Text("Downloads open-access spectral databases for each PINN domain.")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    // Download progress (aggregated across active domains)
                    let activeDomains = PINNDomain.allCases.filter { trainingDataDownloader.status(for: $0).isActive }
                    if !activeDomains.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(activeDomains) { dom in
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    switch trainingDataDownloader.status(for: dom) {
                                    case .downloading(let source, _):
                                        Text("\(dom.displayName): \(source)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    case .staging(let source):
                                        Text("\(dom.displayName): Staging \(source)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    default:
                                        EmptyView()
                                    }
                                }

                                if case .downloading(_, let progress) = trainingDataDownloader.status(for: dom) {
                                    ProgressView(value: progress)
                                        .progressViewStyle(.linear)
                                }
                            }
                        }
                    } else {
                        // Show completion/failure for domains that just finished
                        let completedDomains = PINNDomain.allCases.filter {
                            if case .completed = trainingDataDownloader.status(for: $0) { return true }
                            return false
                        }
                        let failedDomains = PINNDomain.allCases.filter {
                            if case .failed = trainingDataDownloader.status(for: $0) { return true }
                            return false
                        }
                        if !completedDomains.isEmpty {
                            let totalFiles = completedDomains.reduce(0) { sum, dom in
                                if case .completed(let c) = trainingDataDownloader.status(for: dom) { return sum + c }
                                return sum
                            }
                            HStack(spacing: 6) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                    .font(.caption)
                                let fileSuffix: String = totalFiles == 1 ? "" : "s"
                                Text("Download complete — \(totalFiles) file\(fileSuffix) staged across \(completedDomains.count) domain\(completedDomains.count == 1 ? "" : "s")")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }
                        if let firstFailed = failedDomains.first,
                           case .failed(let msg) = trainingDataDownloader.status(for: firstFailed) {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.red)
                                    .font(.caption)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .lineLimit(2)
                            }
                        }
                    }
                }
                .padding(8)
                .background(Color.accentColor.opacity(0.05))
                .cornerRadius(8)
                #endif

                // Script installation status
                if let msg = scriptInstallMessage {
                    HStack(spacing: 6) {
                        Image(systemName: msg.contains("10/10") ? "checkmark.circle.fill" : "info.circle.fill")
                            .foregroundColor(msg.contains("10/10") ? .green : .orange)
                            .font(.caption)
                        Text(msg)
                            .font(.caption)
                    }
                }

                LabeledContent("Scripts Directory") {
                    Text(PINNTrainingManager.scriptsDirectory.path)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Button {
                    let dir = PINNTrainingManager.scriptsDirectory
                    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    PlatformURLOpener.open(dir)
                } label: {
                    Label("Open Scripts Folder", systemImage: "folder")
                }
                .font(.caption)

                Text("Requires Python 3.10+ with PyTorch and coremltools v7+.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            #endif

            Section("CreateML Defaults") {
                Stepper("Max Iterations: \(draftCreateMLMaxIterations)", value: $draftCreateMLMaxIterations, in: 50...1000, step: 50)
                Stepper("Max Depth: \(draftCreateMLMaxDepth)", value: $draftCreateMLMaxDepth, in: 2...12, step: 1)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        HStack(spacing: 4) {
                            Text("Conformal Interval Level:")
                                .font(.subheadline)
                            HelpButton("Conformal Interval Level", message: "This setting controls how **wide** the prediction intervals are.\n\nA **90% level** means the true SPF value will fall within the predicted range 90% of the time. A **95% level** gives wider intervals but higher confidence.\n\n\u{2022} **80%** \u{2014} Narrow intervals, but 20% of true values may fall outside\n\u{2022} **90%** \u{2014} Good balance of precision and reliability (recommended)\n\u{2022} **99%** \u{2014} Very wide intervals, but almost all true values will be captured\n\nFor regulatory purposes, 90% is the standard choice.")
                        }
                        Spacer()
                        Text(String(format: "%.0f%%", draftCreateMLConformalLevel * 100))
                            .monospacedDigit()
                            .font(.caption)
                    }
                    Slider(value: $draftCreateMLConformalLevel, in: 0.80...0.99, step: 0.01)
                }
                Text("Confidence level for prediction intervals. Higher values produce wider but more reliable intervals.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Model Storage") {
                LabeledContent("Models Path") {
                    let modelsPath = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("com.zincoverde.PhysicAI/Models").path ?? "Unknown"
                    Text(modelsPath)
                        .font(.caption2)
                        .monospaced()
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                #if os(macOS)
                Button {
                    if let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                        .appendingPathComponent("com.zincoverde.PhysicAI/Models") {
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        PlatformURLOpener.open(dir)
                    }
                } label: {
                    Label("Open Models Folder", systemImage: "folder")
                }
                .font(.caption)
                #endif

                Text("Trained CoreML models are stored in Application Support and sync to other devices via iCloud.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("ML Training Logging") {
                Toggle("Enable ML Training Logs", isOn: $draftInstrumentationAreaMLTraining)
                    .toggleStyle(.switch)
                Text("Log PINN and CreateML training events, including progress, errors, and timing data.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            } // end ML Training tab
    }

    // MARK: - iOS Settings Navigation

    #if os(iOS)
    private var iOSSettingsList: some View {
        List {
            Section("General") {
                NavigationLink(value: SettingsTab.general) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("SPF Estimation")
                            Text("Calculation method, correction factors")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "function")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            Section("AI & Providers") {
                NavigationLink(value: SettingsTab.ai) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("AI Providers & Routing")
                            Text("Keys, models, ensemble, cost tracking")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundColor(.purple)
                    }
                }
            }
            Section("Machine Learning") {
                NavigationLink(value: SettingsTab.mlTraining) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ML Training")
                            Text("PINN defaults, Python, CreateML, storage")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "cpu")
                            .foregroundColor(.green)
                    }
                }
            }
            Section("Cloud & Enterprise") {
                NavigationLink(value: SettingsTab.enterprise) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Enterprise / M365")
                            Text("Microsoft 365, SharePoint, grounding")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "building.2")
                            .foregroundColor(.blue)
                    }
                }
                NavigationLink(value: SettingsTab.sync) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("iCloud & Data")
                            Text("Sync, backup, polling interval")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "icloud")
                            .foregroundColor(.cyan)
                    }
                }
            }
            Section("Developer") {
                NavigationLink(value: SettingsTab.advanced) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Instrumentation")
                            Text("Debug areas, outputs, severity levels")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } icon: {
                        Image(systemName: "wrench.and.screwdriver")
                            .foregroundColor(.orange)
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .navigationDestination(for: SettingsTab.self) { tab in
            Form {
                settingsFormContent
            }
            .formStyle(.grouped)
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(tab.rawValue)
            .onAppear { selectedSettingsTab = tab }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") { applyDraft() }
                        .buttonStyle(.borderedProminent)
                        .disabled(!settingsAreDirty)
                }
            }
        }
    }
    #endif

    // MARK: - Body

    var body: some View {
        #if os(iOS)
        NavigationStack {
            iOSSettingsList
        }
        #if DEBUG
        .sheet(isPresented: $showICloudDebugPanel) {
            CloudKitDebugPanel()
        }
        #endif
        .onAppear {
            loadDraft()
            MLTrainingService.shared.updateAvailableCount(modelContext: modelContext)
            runDNSCheck()  // Auto-run DNS check on launch
            Task {
                await refreshBackupSize()
                if hasStoredAPIKey, canResolveOpenAIHost {
                    await fetchOpenAIModels()
                }
            }
        }
        #else
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedSettingsTab) {
                ForEach(SettingsTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
                settingsFormContent
            }
            .formStyle(.grouped)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.visible)

            Divider()

            HStack {
                Spacer()
                Button("Apply") { applyDraft() }
                    .disabled(!settingsAreDirty)
                Button("Save") { applyDraft(); dismiss() }
                Button("Close") { dismiss() }
            }
            .padding(20)
            .background(.regularMaterial)
        }
        #if DEBUG
        .sheet(isPresented: $showICloudDebugPanel) {
            CloudKitDebugPanel()
        }
        #endif
        .frame(minWidth: 560, minHeight: 640)
        .onAppear {
            loadDraft()
            MLTrainingService.shared.updateAvailableCount(modelContext: modelContext)
            runDNSCheck()  // Auto-run DNS check on launch
            Task {
                await refreshBackupSize()
                if hasStoredAPIKey, canResolveOpenAIHost {
                    await fetchOpenAIModels()
                }
            }
        }
        #endif
    }

    private func loadDraft() {
        draftAIEnabled = aiEnabled
        draftTemperature = aiTemperature
        draftMaxTokens = aiMaxTokens
        draftPromptPresetRawValue = aiPromptPresetRawValue
        draftAutoRun = aiAutoRun
        draftDefaultScopeRawValue = aiDefaultScopeRawValue

        draftProviderPreferenceRawValue = aiProviderPreferenceRawValue
        draftOpenAIEndpoint = aiOpenAIEndpoint
        draftOpenAIModel = aiOpenAIModel
        draftDiagnosticsEnabled = aiDiagnosticsEnabled
        draftStructuredOutputEnabled = aiStructuredOutputEnabled
        draftClearLogsOnQuit = aiClearLogsOnQuit
        draftAIResponseTextSize = aiResponseTextSize
        draftSpfDisplayModeRawValue = spfDisplayModeRawValue
        draftSpfEstimationOverrideRawValue = spfEstimationOverrideRawValue
        draftSpfCalculationMethodRawValue = spfCalculationMethodRawValue
        draftSpfCFactor = spfCFactor > 0 ? String(format: "%.2f", spfCFactor) : ""
        draftSpfSubstrateCorrection = spfSubstrateCorrection > 0 ? String(format: "%.2f", spfSubstrateCorrection) : ""
        draftSpfAdjustmentFactor = String(format: "%.1f", spfAdjustmentFactor)

        // ML Training
        draftPinnDefaultEpochs = pinnDefaultEpochs
        draftPinnDefaultLearningRate = pinnDefaultLearningRate
        draftPinnPythonPath = pinnPythonPath
        draftCreateMLMaxIterations = createMLMaxIterations
        draftCreateMLMaxDepth = createMLMaxDepth
        draftCreateMLConformalLevel = createMLConformalLevel
        draftInstrumentationAreaMLTraining = instrumentationAreaMLTraining

        draftInstrumentationEnabled = instrumentationEnabled
        draftInstrumentationEnhancedDiagnostics = instrumentationEnhancedDiagnostics
        draftInstrumentationAreaImportParsing = instrumentationAreaImportParsing
        draftInstrumentationAreaProcessing = instrumentationAreaProcessing
        draftInstrumentationAreaChartRendering = instrumentationAreaChartRendering
        draftInstrumentationAreaAIAnalysis = instrumentationAreaAIAnalysis
        draftInstrumentationAreaExport = instrumentationAreaExport
        draftInstrumentationAreaUI = instrumentationAreaUI
        draftInstrumentationOutputInApp = instrumentationOutputInApp
        draftInstrumentationOutputConsole = instrumentationOutputConsole
        draftInstrumentationOutputFile = instrumentationOutputFile
        draftInstrumentationOutputOSLog = instrumentationOutputOSLog
        draftInstrumentationLevelErrors = instrumentationLevelErrors
        draftInstrumentationLevelWarnings = instrumentationLevelWarnings
        draftInstrumentationLevelVerbose = instrumentationLevelVerbose

        hasStoredAPIKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) != nil
        apiKeyDraft = ""

        draftClaudeModel = aiClaudeModel
        hasStoredClaudeAPIKey = KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey) != nil
        claudeAPIKeyDraft = ""

        draftGrokModel = aiGrokModel
        hasStoredGrokAPIKey = KeychainStore.readPassword(account: KeychainKeys.grokAPIKey) != nil
        grokAPIKeyDraft = ""

        draftGeminiModel = aiGeminiModel
        hasStoredGeminiAPIKey = KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey) != nil
        geminiAPIKeyDraft = ""

        // Routing
        if !aiProviderPriorityOrderJSON.isEmpty,
           let data = aiProviderPriorityOrderJSON.data(using: .utf8),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            let decoded = rawValues.compactMap { AIProviderID(rawValue: $0) }
            draftPriorityOrder = decoded.isEmpty ? AIProviderID.defaultPriorityOrder : decoded
        } else {
            draftPriorityOrder = AIProviderID.defaultPriorityOrder
        }
        draftAdvancedRoutingEnabled = aiAdvancedRoutingEnabled
        if !aiFunctionRoutingJSON.isEmpty,
           let data = aiFunctionRoutingJSON.data(using: .utf8),
           let dict = try? JSONDecoder().decode([String: FunctionRoutingMode].self, from: data) {
            var routing: [AIAppFunction: FunctionRoutingMode] = [:]
            for (key, mode) in dict {
                if let function = AIAppFunction(rawValue: key) {
                    routing[function] = mode
                }
            }
            draftFunctionRouting = routing
        } else {
            draftFunctionRouting = [:]
        }
        draftEnsembleModeEnabled = aiEnsembleModeEnabled
        if !aiEnsembleProvidersJSON.isEmpty,
           let data = aiEnsembleProvidersJSON.data(using: .utf8),
           let rawValues = try? JSONDecoder().decode([String].self, from: data) {
            let decoded = Set(rawValues.compactMap { AIProviderID(rawValue: $0) })
            draftEnsembleProviders = decoded.count >= 2 ? decoded : [.claude, .openAI]
        } else {
            draftEnsembleProviders = [.claude, .openAI]
        }
        draftEnsembleArbitrationEnabled = aiEnsembleArbitrationEnabled
        draftCostTrackingEnabled = aiCostTrackingEnabled
        draftBudgetCaps = usageTracker.budgetCaps

        // M365 Enterprise
        draftM365ClientId = m365ClientId
        draftM365TenantId = m365TenantId
        if !m365GroundingConfigJSON.isEmpty,
           let data = m365GroundingConfigJSON.data(using: .utf8),
           let config = try? JSONDecoder().decode(EnterpriseGroundingConfig.self, from: data) {
            draftGroundingConfig = config
        } else {
            draftGroundingConfig = .default
        }
        if !m365ExportConfigJSON.isEmpty,
           let data = m365ExportConfigJSON.data(using: .utf8),
           let config = try? JSONDecoder().decode(SharePointExportConfig.self, from: data) {
            draftExportConfig = config
        } else {
            draftExportConfig = .default
        }
        // Configure auth manager with current tenant
        if draftM365ClientId != M365Config.defaultClientId,
           draftM365TenantId != M365Config.defaultTenantId {
            m365AuthManager.configure(clientId: draftM365ClientId, tenantId: draftM365TenantId)
        }
    }

    private func applyDraft() {
        aiEnabled = draftAIEnabled
        aiTemperature = draftTemperature
        aiMaxTokens = draftMaxTokens
        aiPromptPresetRawValue = draftPromptPresetRawValue
        aiAutoRun = draftAutoRun
        aiDefaultScopeRawValue = draftDefaultScopeRawValue

        aiProviderPreferenceRawValue = draftProviderPreferenceRawValue
        aiOpenAIEndpoint = draftOpenAIEndpoint
        aiOpenAIModel = draftOpenAIModel
        aiDiagnosticsEnabled = draftDiagnosticsEnabled
        aiStructuredOutputEnabled = draftStructuredOutputEnabled
        aiClearLogsOnQuit = draftClearLogsOnQuit
        aiResponseTextSize = draftAIResponseTextSize
        spfDisplayModeRawValue = draftSpfDisplayModeRawValue
        spfEstimationOverrideRawValue = draftSpfEstimationOverrideRawValue
        spfCalculationMethodRawValue = draftSpfCalculationMethodRawValue
        spfCFactor = Double(draftSpfCFactor.trimmingCharacters(in: .whitespaces)) ?? 0.0
        spfSubstrateCorrection = Double(draftSpfSubstrateCorrection.trimmingCharacters(in: .whitespaces)) ?? 0.0
        spfAdjustmentFactor = max(Double(draftSpfAdjustmentFactor.trimmingCharacters(in: .whitespaces)) ?? 1.0, 1.0)

        // ML Training
        pinnDefaultEpochs = draftPinnDefaultEpochs
        pinnDefaultLearningRate = draftPinnDefaultLearningRate
        pinnPythonPath = draftPinnPythonPath
        createMLMaxIterations = draftCreateMLMaxIterations
        createMLMaxDepth = draftCreateMLMaxDepth
        createMLConformalLevel = draftCreateMLConformalLevel
        instrumentationAreaMLTraining = draftInstrumentationAreaMLTraining

        instrumentationEnabled = draftInstrumentationEnabled
        instrumentationEnhancedDiagnostics = draftInstrumentationEnhancedDiagnostics
        instrumentationAreaImportParsing = draftInstrumentationAreaImportParsing
        instrumentationAreaProcessing = draftInstrumentationAreaProcessing
        instrumentationAreaChartRendering = draftInstrumentationAreaChartRendering
        instrumentationAreaAIAnalysis = draftInstrumentationAreaAIAnalysis
        instrumentationAreaExport = draftInstrumentationAreaExport
        instrumentationAreaUI = draftInstrumentationAreaUI
        instrumentationOutputInApp = draftInstrumentationOutputInApp
        instrumentationOutputConsole = draftInstrumentationOutputConsole
        instrumentationOutputFile = draftInstrumentationOutputFile
        instrumentationOutputOSLog = draftInstrumentationOutputOSLog
        instrumentationLevelErrors = draftInstrumentationLevelErrors
        instrumentationLevelWarnings = draftInstrumentationLevelWarnings
        instrumentationLevelVerbose = draftInstrumentationLevelVerbose

        aiClaudeModel = draftClaudeModel
        aiGrokModel = draftGrokModel
        aiGeminiModel = draftGeminiModel

        if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveAPIKey()
        }
        if !claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveClaudeAPIKey()
        }
        if !grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveGrokAPIKey()
        }
        if !geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveGeminiAPIKey()
        }

        // Routing
        aiProviderPriorityOrderJSON = encodedPriorityOrder
        aiAdvancedRoutingEnabled = draftAdvancedRoutingEnabled
        aiFunctionRoutingJSON = encodedFunctionRouting
        aiEnsembleModeEnabled = draftEnsembleModeEnabled
        aiEnsembleProvidersJSON = encodedEnsembleProviders
        aiEnsembleArbitrationEnabled = draftEnsembleArbitrationEnabled
        aiCostTrackingEnabled = draftCostTrackingEnabled

        // M365 Enterprise
        m365ClientId = draftM365ClientId
        m365TenantId = draftM365TenantId
        m365GroundingConfigJSON = encodedGroundingConfig
        m365ExportConfigJSON = encodedExportConfig
        // Reconfigure auth manager if tenant changed
        if draftM365ClientId != M365Config.defaultClientId,
           draftM365TenantId != M365Config.defaultTenantId {
            m365AuthManager.configure(clientId: draftM365ClientId, tenantId: draftM365TenantId)
        }
    }

    // MARK: - Routing Helpers

    // MARK: - Connection Test Row

    @ViewBuilder
    private func connectionTestRow(_ label: String, status: M365ConfigValidator.TestStatus, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .frame(width: 18)
                .foregroundColor(.secondary)
            Text(label)
                .font(.subheadline)
                .frame(width: 100, alignment: .leading)

            switch status {
            case .untested:
                Text("Not tested")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .testing:
                ProgressView()
                    .controlSize(.mini)
                Text("Testing...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            case .success(let detail):
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            case .failed(let detail):
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                    .font(.caption)
                Text(detail)
                    .font(.caption)
                    .foregroundColor(.red)
                    .lineLimit(2)
            }

            Spacer()
        }
    }

    private func functionRoutingBinding(for function: AIAppFunction) -> Binding<FunctionRoutingMode> {
        Binding(
            get: { draftFunctionRouting[function] ?? .auto },
            set: { draftFunctionRouting[function] = $0 }
        )
    }

    private func budgetCapBinding(for providerID: AIProviderID) -> Binding<Double> {
        Binding(
            get: {
                draftBudgetCaps[providerID]?.monthlyBudgetUSD
                    ?? ProviderBudgetCap.defaults(for: providerID).monthlyBudgetUSD
            },
            set: { newValue in
                var cap = draftBudgetCaps[providerID] ?? ProviderBudgetCap.defaults(for: providerID)
                cap.monthlyBudgetUSD = max(newValue, 0)
                draftBudgetCaps[providerID] = cap
                usageTracker.budgetCaps[providerID] = cap
            }
        )
    }

    private func ensembleProviderBinding(for providerID: AIProviderID) -> Binding<Bool> {
        Binding(
            get: { draftEnsembleProviders.contains(providerID) },
            set: { isOn in
                if isOn {
                    draftEnsembleProviders.insert(providerID)
                } else if draftEnsembleProviders.count > 2 {
                    draftEnsembleProviders.remove(providerID)
                }
            }
        )
    }

    // MARK: - Provider Availability

    @ViewBuilder
    private func providerAvailabilityDot(for providerID: AIProviderID) -> some View {
        let isAvailable: Bool = {
            switch providerID {
            case .onDevice:
                return AIProviderManager().isOnDeviceAvailable
            case .openAI:
                return KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey) != nil
            case .claude:
                return KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey) != nil
            case .grok:
                return KeychainStore.readPassword(account: KeychainKeys.grokAPIKey) != nil
            case .gemini:
                return KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey) != nil
            case .pinnOnDevice:
                return PINNPredictionService.shared.readyModelCount > 0
            case .microsoft:
                return m365AuthManager.isSignedIn
            }
        }()
        Circle()
            .fill(isAvailable ? Color.green : Color.red.opacity(0.5))
            .frame(width: 8, height: 8)
            .help(isAvailable ? "Available" : "Not configured")
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = KeychainStore.savePassword(trimmed, account: KeychainKeys.openAIAPIKey)
        hasStoredAPIKey = result.success
        if result.success {
            apiKeyDraft = ""
            if let diag = result.diagnostic {
                aiOpenAITestStatus = diag
                aiOpenAITestTimestamp = Date().timeIntervalSince1970
            }
        } else {
            aiOpenAITestStatus = result.diagnostic ?? "Keychain save failed"
            aiOpenAITestTimestamp = Date().timeIntervalSince1970
        }
    }

    private func clearAPIKey() {
        KeychainStore.deletePassword(account: KeychainKeys.openAIAPIKey)
        hasStoredAPIKey = false
        apiKeyDraft = ""
    }

    private func saveClaudeAPIKey() {
        let trimmed = claudeAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = KeychainStore.savePassword(trimmed, account: KeychainKeys.anthropicAPIKey)
        hasStoredClaudeAPIKey = result.success
        if result.success {
            claudeAPIKeyDraft = ""
            if let diag = result.diagnostic {
                aiClaudeTestStatus = diag
                aiClaudeTestTimestamp = Date().timeIntervalSince1970
            }
        } else {
            aiClaudeTestStatus = result.diagnostic ?? "Keychain save failed"
            aiClaudeTestTimestamp = Date().timeIntervalSince1970
        }
    }

    private func clearClaudeAPIKey() {
        KeychainStore.deletePassword(account: KeychainKeys.anthropicAPIKey)
        hasStoredClaudeAPIKey = false
        claudeAPIKeyDraft = ""
    }

    private func saveGrokAPIKey() {
        let trimmed = grokAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = KeychainStore.savePassword(trimmed, account: KeychainKeys.grokAPIKey)
        hasStoredGrokAPIKey = result.success
        if result.success {
            grokAPIKeyDraft = ""
            if let diag = result.diagnostic {
                aiGrokTestStatus = diag
                aiGrokTestTimestamp = Date().timeIntervalSince1970
            }
        } else {
            aiGrokTestStatus = result.diagnostic ?? "Keychain save failed"
            aiGrokTestTimestamp = Date().timeIntervalSince1970
        }
    }

    private func clearGrokAPIKey() {
        KeychainStore.deletePassword(account: KeychainKeys.grokAPIKey)
        hasStoredGrokAPIKey = false
        grokAPIKeyDraft = ""
    }

    private func saveGeminiAPIKey() {
        let trimmed = geminiAPIKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let result = KeychainStore.savePassword(trimmed, account: KeychainKeys.geminiAPIKey)
        hasStoredGeminiAPIKey = result.success
        if result.success {
            geminiAPIKeyDraft = ""
            if let diag = result.diagnostic {
                aiGeminiTestStatus = diag
                aiGeminiTestTimestamp = Date().timeIntervalSince1970
            }
        } else {
            aiGeminiTestStatus = result.diagnostic ?? "Keychain save failed"
            aiGeminiTestTimestamp = Date().timeIntervalSince1970
        }
    }

    private func clearGeminiAPIKey() {
        KeychainStore.deletePassword(account: KeychainKeys.geminiAPIKey)
        hasStoredGeminiAPIKey = false
        geminiAPIKeyDraft = ""
    }

    private func testOpenAIConnection() async {
        guard let endpointURL = resolvedOpenAIEndpointURL else {
            aiOpenAITestStatus = "Endpoint missing"
            aiOpenAITestTimestamp = Date().timeIntervalSince1970
            return
        }

        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey), !apiKey.isEmpty else {
            aiOpenAITestStatus = "API key missing"
            aiOpenAITestTimestamp = Date().timeIntervalSince1970
            return
        }

        let scheme = endpointURL.scheme ?? "https"
        let host = endpointURL.host ?? "api.openai.com"
        let testURL = URL(string: "\(scheme)://\(host)/v1/models") ?? endpointURL

        do {
            var request = URLRequest(url: testURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            let (_, response) = try await openAITestSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    aiOpenAITestStatus = "Reachable (\(http.statusCode))"
                } else if http.statusCode == 401 {
                    aiOpenAITestStatus = "Unauthorized"
                } else {
                    aiOpenAITestStatus = "HTTP \(http.statusCode)"
                }
            } else {
                aiOpenAITestStatus = "Unreachable"
            }
            aiOpenAITestTimestamp = Date().timeIntervalSince1970
        } catch {
            if let urlError = error as? URLError, urlError.code == .cannotFindHost {
                aiOpenAITestStatus = "DNS failed"
            } else {
                aiOpenAITestStatus = error.localizedDescription
            }
            aiOpenAITestTimestamp = Date().timeIntervalSince1970
        }
    }

    private func testClaudeConnection() async {
        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey), !apiKey.isEmpty else {
            aiClaudeTestStatus = "API key missing"
            aiClaudeTestTimestamp = Date().timeIntervalSince1970
            return
        }

        let requestBody: [String: Any] = [
            "model": draftClaudeModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": 1,
            "messages": [["role": "user", "content": "Hi"]]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.anthropic.com/v1/messages") else {
            aiClaudeTestStatus = "Invalid request"
            aiClaudeTestTimestamp = Date().timeIntervalSince1970
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = bodyData

        do {
            let (_, response) = try await openAITestSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    aiClaudeTestStatus = "Reachable (\(http.statusCode))"
                } else if http.statusCode == 401 {
                    aiClaudeTestStatus = "Unauthorized"
                } else {
                    aiClaudeTestStatus = "HTTP \(http.statusCode)"
                }
            } else {
                aiClaudeTestStatus = "Unreachable"
            }
        } catch {
            aiClaudeTestStatus = error.localizedDescription
        }
        aiClaudeTestTimestamp = Date().timeIntervalSince1970
    }

    private func testGrokConnection() async {
        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.grokAPIKey), !apiKey.isEmpty else {
            aiGrokTestStatus = "API key missing"
            aiGrokTestTimestamp = Date().timeIntervalSince1970
            return
        }

        let requestBody: [String: Any] = [
            "model": draftGrokModel.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_tokens": 1,
            "messages": [
                ["role": "user", "content": "Hi"]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody),
              let url = URL(string: "https://api.x.ai/v1/chat/completions") else {
            aiGrokTestStatus = "Invalid request"
            aiGrokTestTimestamp = Date().timeIntervalSince1970
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = bodyData

        do {
            let (_, response) = try await openAITestSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    aiGrokTestStatus = "Reachable (\(http.statusCode))"
                } else if http.statusCode == 401 {
                    aiGrokTestStatus = "Unauthorized"
                } else {
                    aiGrokTestStatus = "HTTP \(http.statusCode)"
                }
            } else {
                aiGrokTestStatus = "Unreachable"
            }
        } catch {
            aiGrokTestStatus = error.localizedDescription
        }
        aiGrokTestTimestamp = Date().timeIntervalSince1970
    }

    private func testGeminiConnection() async {
        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey), !apiKey.isEmpty else {
            aiGeminiTestStatus = "API key missing"
            aiGeminiTestTimestamp = Date().timeIntervalSince1970
            return
        }

        let model = draftGeminiModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty,
              let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(apiKey)") else {
            aiGeminiTestStatus = "Invalid request"
            aiGeminiTestTimestamp = Date().timeIntervalSince1970
            return
        }

        let requestBody: [String: Any] = [
            "contents": [["parts": [["text": "Hi"]]]],
            "generationConfig": ["maxOutputTokens": 1]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else {
            aiGeminiTestStatus = "Invalid request"
            aiGeminiTestTimestamp = Date().timeIntervalSince1970
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData

        do {
            let (_, response) = try await openAITestSession.data(for: request)
            if let http = response as? HTTPURLResponse {
                if (200...299).contains(http.statusCode) {
                    aiGeminiTestStatus = "Reachable (\(http.statusCode))"
                } else if http.statusCode == 400 {
                    aiGeminiTestStatus = "Bad request (check model)"
                } else if http.statusCode == 403 {
                    aiGeminiTestStatus = "API key invalid"
                } else {
                    aiGeminiTestStatus = "HTTP \(http.statusCode)"
                }
            } else {
                aiGeminiTestStatus = "Unreachable"
            }
        } catch {
            aiGeminiTestStatus = error.localizedDescription
        }
        aiGeminiTestTimestamp = Date().timeIntervalSince1970
    }

    private func fetchOpenAIModels() async {
        guard let endpointURL = resolvedOpenAIEndpointURL else {
            await MainActor.run {
                openAIModelFetchStatus = "Endpoint missing"
            }
            return
        }

        guard let apiKey = KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey), !apiKey.isEmpty else {
            await MainActor.run {
                openAIModelFetchStatus = "API key missing"
            }
            return
        }

        let scheme = endpointURL.scheme ?? "https"
        let host = endpointURL.host ?? "api.openai.com"
        let modelsURL = URL(string: "\(scheme)://\(host)/v1/models") ?? endpointURL

        await MainActor.run {
            isFetchingOpenAIModels = true
            openAIModelFetchStatus = "Fetching models…"
        }

        defer {
            Task { @MainActor in
                isFetchingOpenAIModels = false
            }
        }

        do {
            var request = URLRequest(url: modelsURL)
            request.httpMethod = "GET"
            request.timeoutInterval = 10
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await openAITestSession.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                await MainActor.run {
                    openAIModelFetchStatus = "Model list failed"
                }
                return
            }

            guard (200...299).contains(http.statusCode) else {
                await MainActor.run {
                    openAIModelFetchStatus = "Model list HTTP \(http.statusCode)"
                }
                return
            }

            let decoded = try JSONDecoder().decode(OpenAIModelListResponse.self, from: data)
            let models = decoded.data.map(\.id).sorted()
            await MainActor.run {
                availableOpenAIModels = models
                openAIModelFetchStatus = "Loaded \(models.count) models"
            }
        } catch {
            await MainActor.run {
                openAIModelFetchStatus = error.localizedDescription
            }
        }
    }

    // Python verification is now handled by PythonEnvironmentDetector (filesystem-based, sandbox-safe).

    private func runDNSCheck() {
        // Check all providers with known hostnames
        var allIPs: [String] = []
        var results: [String] = []

        for provider in AIProviderID.allCases {
            guard let host = provider.apiHostname else { continue }
            let addresses = resolveHostAddresses(host)
            if addresses.isEmpty {
                results.append("\(provider.displayName): DNS failed for \(host)")
                logAIDiagnostics("DNS failed \(host)")
            } else {
                results.append("\(provider.displayName): Resolved \(host)")
                allIPs.append(contentsOf: addresses)
                logAIDiagnostics("DNS resolved \(host)", details: "ips=\(addresses.joined(separator: ", "))")
            }
        }

        // Also check custom OpenAI endpoint if different
        if let customHost = resolvedOpenAIHost, customHost != "api.openai.com" {
            let addresses = resolveHostAddresses(customHost)
            if addresses.isEmpty {
                results.append("Custom Endpoint: DNS failed for \(customHost)")
            } else {
                results.append("Custom Endpoint: Resolved \(customHost)")
                allIPs.append(contentsOf: addresses)
            }
        }

        dnsStatusIPs = Array(Set(allIPs)).sorted()
        dnsStatusMessage = results.joined(separator: "\n")
        dnsStatusTimestamp = Date()
    }

    private func resolveHostAddresses(_ host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: AI_ADDRCONFIG,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var resultPointer: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, nil, &hints, &resultPointer)
        guard status == 0, let resultPointer else { return [] }
        defer { freeaddrinfo(resultPointer) }

        var addresses: [String] = []
        var current: UnsafeMutablePointer<addrinfo>? = resultPointer
        while let info = current?.pointee {
            if info.ai_family == AF_INET, let addr = info.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { pointer in
                    inet_ntop(AF_INET, &pointer.pointee.sin_addr, &buffer, socklen_t(INET_ADDRSTRLEN))
                }
                if let ip {
                    addresses.append(String(cString: ip))
                }
            } else if info.ai_family == AF_INET6, let addr = info.ai_addr {
                var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                let ip = addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { pointer in
                    inet_ntop(AF_INET6, &pointer.pointee.sin6_addr, &buffer, socklen_t(INET6_ADDRSTRLEN))
                }
                if let ip {
                    addresses.append(String(cString: ip))
                }
            }
            current = info.ai_next
        }

        return Array(Set(addresses)).sorted()
    }

    private func copyDNSResults() {
        let text = dnsStatusText
        PlatformPasteboard.copyString(text)
    }

    private func refreshBackupSize() async {
        guard icloudSyncEnabled else { return }
        // Read the cached backup size from UserDefaults instead of iterating
        // all model objects. The backup size is computed by ICloudSyncCoordinator
        // during performBackupNow() and stored in lastBackupSizeBytes.
        // This avoids touching potentially invalidated SwiftData model objects
        // during CloudKit sync, which causes swift_weakLoadStrong crashes.
        let cachedSize = UserDefaults.standard.double(forKey: ICloudDefaultsKeys.lastBackupSizeBytes)
        if cachedSize > 0 {
            icloudLastBackupSizeBytes = cachedSize
        } else {
            // Fall back to a safe estimation with modelContext != nil guards
            // ObjCExceptionCatcher guards property reads that can throw NSExceptions
            // when CloudKit invalidates backing store mid-iteration.
            do {
                let datasets = try modelContext.fetch(FetchDescriptor<StoredDataset>())
                var total: Int64 = 0
                for dataset in datasets {
                    guard dataset.modelContext != nil else { continue }
                    total += Int64(dataset.fileData?.count ?? 0)
                    total += Int64(dataset.metadataJSON?.count ?? 0)
                    total += Int64(dataset.headerInfoData?.count ?? 0)
                    total += Int64(dataset.skippedDataJSON?.count ?? 0)
                    total += Int64(dataset.warningsJSON?.count ?? 0)

                    let dsID = dataset.id
                    let spectrumPredicate = #Predicate<StoredSpectrum> { $0.datasetID == dsID }
                    let spectra = (try? modelContext.fetch(FetchDescriptor<StoredSpectrum>(predicate: spectrumPredicate))) ?? []
                    for spectrum in spectra {
                        guard spectrum.modelContext != nil else { continue }
                        total += Int64(spectrum.xData.count)
                        total += Int64(spectrum.yData.count)
                    }
                }
                icloudLastBackupSizeBytes = Double(total)
            } catch {
                icloudLastBackupStatus = "Backup size failed: \(error.localizedDescription)"
            }
        }
    }

    private func logAIDiagnostics(_ message: String, details: String? = nil) {
        guard draftDiagnosticsEnabled else { return }
        var parts: [String] = ["[AI Diagnostics] \(message)"]
        if let details { parts.append(details) }
        let line = parts.joined(separator: " ")
        print(line)
        NotificationCenter.default.post(name: Notification.Name("AISettingsDiagnosticsLog"), object: line)
    }

}

private struct OpenAIModelListResponse: Decodable {
    let data: [OpenAIModelListEntry]
}

private struct OpenAIModelListEntry: Decodable {
    let id: String
}

// MARK: - In-App OpenAI Key Browser

private struct OpenAIKeyBrowserSheet: View {
    @Binding var apiKeyDraft: String
    @Binding var hasStoredAPIKey: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var pastedKey = ""
    @State private var keySaved = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Get OpenAI API Key")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            // Browser + sidebar layout
            platformHSplit {
                // WebView showing OpenAI API keys page
                OpenAIWebView(url: URL(string: "https://platform.openai.com/api-keys")!)
                    .frame(minWidth: 500, minHeight: 500)

                // Key entry sidebar
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paste your API key here")
                        .font(.subheadline.bold())

                    Text("1. Log in to OpenAI on the left\n2. Create or copy an API key\n3. Paste it below")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    SecureField("sk-...", text: $pastedKey)
                        .textFieldStyle(.roundedBorder)

                    Button("Save to Keychain") {
                        let trimmed = pastedKey.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let result = KeychainStore.savePassword(trimmed, account: KeychainKeys.openAIAPIKey)
                        hasStoredAPIKey = result.success
                        if result.success {
                            apiKeyDraft = ""
                            pastedKey = ""
                            keySaved = true
                        }
                    }
                    .disabled(pastedKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    if keySaved {
                        Label("Key saved to Keychain", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if hasStoredAPIKey {
                        Label("A key is currently stored", systemImage: "key.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }
                .padding()
                .frame(width: 240)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
    }
}

#if canImport(AppKit)
private struct OpenAIWebView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No dynamic updates needed
    }
}
#elseif canImport(UIKit)
private struct OpenAIWebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No dynamic updates needed
    }
}
#endif

#if DEBUG
private struct CloudKitDebugPanel: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("icloudLastNotificationPayload") private var payload = ""
    @AppStorage("icloudLastTokenDescription") private var tokenDescription = ""
    @AppStorage("icloudLastPollTimestamp") private var lastPollTimestamp = 0.0
    @AppStorage("icloudLastPushTimestamp") private var lastPushTimestamp = 0.0
    @AppStorage("icloudLastSyncReason") private var lastSyncReason = ""
    @AppStorage("icloudLastChangedZoneIDs") private var lastChangedZoneIDs = ""
    @AppStorage("icloudLastDeletedZoneIDs") private var lastDeletedZoneIDs = ""
    @AppStorage("icloudLastSubscriptionID") private var lastSubscriptionID = ""
    @AppStorage("icloudLastSubscriptionStatus") private var lastSubscriptionStatus = ""
    @AppStorage("icloudContainerIdentifier") private var containerIdentifier = ""
    @AppStorage("icloudAccountStatus") private var accountStatus = ""
    @AppStorage("icloudAccountStatusError") private var accountStatusError = ""
    @AppStorage("icloudAccountStatusTimestamp") private var accountStatusTimestamp = 0.0
    @AppStorage("icloudDatabaseScope") private var databaseScope = ""
    @AppStorage("icloudLastSyncStartTimestamp") private var lastSyncStartTimestamp = 0.0
    @AppStorage("icloudLastSyncEndTimestamp") private var lastSyncEndTimestamp = 0.0
    @AppStorage("icloudLastSyncDuration") private var lastSyncDuration = 0.0
    @AppStorage("icloudLastSyncErrorDomain") private var lastSyncErrorDomain = ""
    @AppStorage("icloudLastSyncErrorCode") private var lastSyncErrorCode = 0
    @AppStorage("icloudLastSyncErrorDescription") private var lastSyncErrorDescription = ""
    @AppStorage("icloudLastSyncMoreComing") private var lastSyncMoreComing = false
    @AppStorage("icloudLastSyncChangesDetected") private var lastSyncChangesDetected = false
    @AppStorage("icloudLastChangedZoneCount") private var lastChangedZoneCount = 0
    @AppStorage("icloudLastDeletedZoneCount") private var lastDeletedZoneCount = 0
    @AppStorage("icloudLastPushSubscriptionID") private var lastPushSubscriptionID = ""
    @AppStorage("icloudLastNotificationType") private var lastNotificationType = ""
    @AppStorage("icloudLastTokenByteSize") private var lastTokenByteSize = 0
    @AppStorage("icloudLastMoreComingTimestamps") private var lastMoreComingTimestamps = Data()
    @AppStorage("icloudLastPartialZoneErrors") private var lastPartialZoneErrors = ""
    @AppStorage("icloudLastZoneFetchErrors") private var lastZoneFetchErrors = ""
    @AppStorage("icloudLastZoneFetchTimestamp") private var lastZoneFetchTimestamp = 0.0
    @AppStorage("icloudLastZoneFetchMoreComing") private var lastZoneFetchMoreComing = false
    @AppStorage("icloudZoneChangeTokens") private var zoneChangeTokens = Data()
    @AppStorage("swiftDataStoreMode") private var storeMode = "unknown"
    @AppStorage("icloudMigrateOnRelaunch") private var migrateOnRelaunch = false

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text("CloudKit Debug")
                    .font(.title2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                #if os(iOS)
                Button("Copy", systemImage: "doc.on.doc") {
                    copyDebugInfo()
                }
                .labelStyle(.iconOnly)
                Button("Save", systemImage: "square.and.arrow.down") {
                    exportDebugInfo()
                }
                .labelStyle(.iconOnly)
                Button("Close", systemImage: "xmark.circle.fill") {
                    dismiss()
                }
                .labelStyle(.iconOnly)
                #else
                Button("Copy") {
                    copyDebugInfo()
                }
                Button("Save") {
                    exportDebugInfo()
                }
                Button("Close") {
                    dismiss()
                }
                #endif
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Connection") {
                        VStack(alignment: .leading, spacing: 6) {
                            debugLine(label: "Container", value: containerIdentifier.isEmpty ? "default" : containerIdentifier)
                            debugLine(label: "Database Scope", value: databaseScope.isEmpty ? "(unknown)" : databaseScope)
                            debugLine(label: "Store Mode", value: storeMode.isEmpty ? "(unknown)" : storeMode)
                            if migrateOnRelaunch {
                                debugLine(label: "Migration Requested", value: "yes")
                            }
                            debugLine(label: "Account Status", value: accountStatus.isEmpty ? "(unknown)" : accountStatus)
                            if !accountStatusError.isEmpty {
                                debugLine(label: "Account Error", value: accountStatusError)
                            }
                            debugLine(label: "Account Status Time", value: formattedTimestamp(accountStatusTimestamp))
                            debugLine(label: "Subscription ID", value: lastSubscriptionID.isEmpty ? "(unknown)" : lastSubscriptionID)
                            debugLine(label: "Subscription Status", value: lastSubscriptionStatus.isEmpty ? "(unknown)" : lastSubscriptionStatus)
                            debugLine(label: "Last Sync Reason", value: lastSyncReason.isEmpty ? "(unknown)" : lastSyncReason)
                            debugLine(label: "Last Poll Time", value: formattedTimestamp(lastPollTimestamp))
                            debugLine(label: "Last Push Time", value: formattedTimestamp(lastPushTimestamp))
                            if !lastPushSubscriptionID.isEmpty {
                                debugLine(label: "Last Push Sub ID", value: lastPushSubscriptionID)
                            }
                            if !lastNotificationType.isEmpty {
                                debugLine(label: "Last Notification Type", value: lastNotificationType)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    GroupBox("Last Sync Details") {
                        VStack(alignment: .leading, spacing: 6) {
                            debugLine(label: "Sync Start", value: formattedTimestamp(lastSyncStartTimestamp))
                            debugLine(label: "Sync End", value: formattedTimestamp(lastSyncEndTimestamp))
                            debugLine(label: "Sync Duration", value: formattedDuration(lastSyncDuration))
                            debugLine(label: "Changes Detected", value: lastSyncChangesDetected ? "yes" : "no")
                            debugLine(label: "More Coming", value: lastSyncMoreComing ? "yes" : "no")
                            debugLine(label: "Changed Zones", value: "\(lastChangedZoneCount)")
                            debugLine(label: "Deleted Zones", value: "\(lastDeletedZoneCount)")
                            if !lastSyncErrorDescription.isEmpty {
                                debugLine(label: "Last Error", value: lastSyncErrorDescription)
                                if !lastSyncErrorDomain.isEmpty {
                                    debugLine(label: "Error Domain", value: lastSyncErrorDomain)
                                }
                                if lastSyncErrorCode != 0 {
                                    debugLine(label: "Error Code", value: "\(lastSyncErrorCode)")
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    GroupBox("Last Notification Payload") {
                        ScrollView {
                            Text(payload.isEmpty ? "(none)" : payload)
                                .font(.system(.body, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 240)
                    }
                    GroupBox("Last Change Token") {
                        Text(tokenDescription.isEmpty ? "(none)" : tokenDescription)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    GroupBox("Token Size") {
                        debugLine(label: "Archived Bytes", value: lastTokenByteSize == 0 ? "(unknown)" : "\(lastTokenByteSize)")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    GroupBox("Last Zone Changes") {
                        VStack(alignment: .leading, spacing: 8) {
                            debugMultiline(label: "Changed Zones", value: lastChangedZoneIDs)
                            debugMultiline(label: "Deleted Zones", value: lastDeletedZoneIDs)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                    GroupBox("More Coming Timestamps") {
                        Text(formattedMoreComingTimestamps())
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    GroupBox("Partial Zone Errors") {
                        Text(lastPartialZoneErrors.isEmpty ? "(none)" : lastPartialZoneErrors)
                            .font(.system(.body, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    GroupBox("Zone Changes Fetch") {
                        VStack(alignment: .leading, spacing: 6) {
                            debugLine(label: "Last Fetch Time", value: formattedTimestamp(lastZoneFetchTimestamp))
                            debugLine(label: "More Coming", value: lastZoneFetchMoreComing ? "yes" : "no")
                            debugMultiline(label: "Zone Fetch Errors", value: lastZoneFetchErrors)
                            debugMultiline(label: "Zone Token Sizes", value: zoneTokenSizesDetail())
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
        }
        #if os(macOS)
        .padding(20)
        .frame(minWidth: 560, minHeight: 520)
        #else
        .padding(16)
        #endif
    }

    private func formattedTimestamp(_ value: Double) -> String {
        guard value > 0 else { return "(never)" }
        let date = Date(timeIntervalSince1970: value)
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }

    private func exportDebugInfo() {
        let text = buildExportText()
        guard let data = text.data(using: .utf8) else { return }
        Task { @MainActor in
            let _ = await PlatformFileSaver.save(
                defaultName: "CloudKit Debug.txt",
                allowedTypes: [.plainText],
                data: data,
                directoryKey: nil
            )
        }
    }

    private func copyDebugInfo() {
        let text = buildExportText()
        PlatformPasteboard.copyString(text)
    }

    private func buildExportText() -> String {
        var lines: [String] = []
        func addLine(_ label: String, _ value: String) {
            lines.append("\(label): \(value)")
        }
        func addMultiline(_ value: String) {
            lines.append(value)
        }
        func appendSection(_ title: String, build: () -> Void) {
            lines.append("[\(title)]")
            build()
            lines.append("")
        }

        lines.append("CloudKit Debug")
        lines.append("Generated: \(formattedTimestamp(Date().timeIntervalSince1970))")
        lines.append("")

        appendSection("Connection") {
            addLine("Container", containerIdentifier.isEmpty ? "default" : containerIdentifier)
            addLine("Database Scope", databaseScope.isEmpty ? "(unknown)" : databaseScope)
            addLine("Store Mode", storeMode.isEmpty ? "(unknown)" : storeMode)
            if migrateOnRelaunch { addLine("Migration Requested", "yes") }
            addLine("Account Status", accountStatus.isEmpty ? "(unknown)" : accountStatus)
            if !accountStatusError.isEmpty { addLine("Account Error", accountStatusError) }
            addLine("Account Status Time", formattedTimestamp(accountStatusTimestamp))
            addLine("Subscription ID", lastSubscriptionID.isEmpty ? "(unknown)" : lastSubscriptionID)
            addLine("Subscription Status", lastSubscriptionStatus.isEmpty ? "(unknown)" : lastSubscriptionStatus)
            addLine("Last Sync Reason", lastSyncReason.isEmpty ? "(unknown)" : lastSyncReason)
            addLine("Last Poll Time", formattedTimestamp(lastPollTimestamp))
            addLine("Last Push Time", formattedTimestamp(lastPushTimestamp))
            if !lastPushSubscriptionID.isEmpty { addLine("Last Push Sub ID", lastPushSubscriptionID) }
            if !lastNotificationType.isEmpty { addLine("Last Notification Type", lastNotificationType) }
        }

        appendSection("Last Sync Details") {
            addLine("Sync Start", formattedTimestamp(lastSyncStartTimestamp))
            addLine("Sync End", formattedTimestamp(lastSyncEndTimestamp))
            addLine("Sync Duration", formattedDuration(lastSyncDuration))
            addLine("Changes Detected", lastSyncChangesDetected ? "yes" : "no")
            addLine("More Coming", lastSyncMoreComing ? "yes" : "no")
            addLine("Changed Zones", "\(lastChangedZoneCount)")
            addLine("Deleted Zones", "\(lastDeletedZoneCount)")
            if !lastSyncErrorDescription.isEmpty { addLine("Last Error", lastSyncErrorDescription) }
            if !lastSyncErrorDomain.isEmpty { addLine("Error Domain", lastSyncErrorDomain) }
            if lastSyncErrorCode != 0 { addLine("Error Code", "\(lastSyncErrorCode)") }
        }

        appendSection("Last Notification Payload") {
            addMultiline(payload.isEmpty ? "(none)" : payload)
        }

        appendSection("Last Change Token") {
            addMultiline(tokenDescription.isEmpty ? "(none)" : tokenDescription)
        }

        appendSection("Token Size") {
            addLine("Archived Bytes", lastTokenByteSize == 0 ? "(unknown)" : "\(lastTokenByteSize)")
        }

        appendSection("Last Zone Changes") {
            addLine("Changed Zones", lastChangedZoneIDs.isEmpty ? "(none)" : lastChangedZoneIDs)
            addLine("Deleted Zones", lastDeletedZoneIDs.isEmpty ? "(none)" : lastDeletedZoneIDs)
        }

        appendSection("More Coming Timestamps") {
            addMultiline(formattedMoreComingTimestamps())
        }

        appendSection("Partial Zone Errors") {
            addMultiline(lastPartialZoneErrors.isEmpty ? "(none)" : lastPartialZoneErrors)
        }

        appendSection("Zone Changes Fetch") {
            addLine("Last Fetch Time", formattedTimestamp(lastZoneFetchTimestamp))
            addLine("More Coming", lastZoneFetchMoreComing ? "yes" : "no")
            addLine("Zone Fetch Errors", lastZoneFetchErrors.isEmpty ? "(none)" : lastZoneFetchErrors)
            addLine("Zone Token Sizes", zoneTokenSizesDetail())
        }

        return lines.joined(separator: "\n")
    }

    private func formattedDuration(_ value: Double) -> String {
        guard value > 0 else { return "(unknown)" }
        if value < 1 {
            return String(format: "%.2f s", value)
        }
        return String(format: "%.1f s", value)
    }

    private func formattedMoreComingTimestamps() -> String {
        guard !lastMoreComingTimestamps.isEmpty,
              let decoded = try? JSONDecoder().decode([Double].self, from: lastMoreComingTimestamps),
              !decoded.isEmpty else {
            return "(none)"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return decoded.map { formatter.string(from: Date(timeIntervalSince1970: $0)) }
            .joined(separator: "\n")
    }

    private func zoneTokenSizesDetail() -> String {
        guard !zoneChangeTokens.isEmpty,
              let decoded = try? JSONDecoder().decode([String: Data].self, from: zoneChangeTokens),
              !decoded.isEmpty else {
            return "(none)"
        }
        return decoded
            .map { "\($0.key): \(formatByteCount($0.value.count))" }
            .sorted()
            .joined(separator: "\n")
    }

    private func formatByteCount(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    #if os(iOS)
    private let debugFont: Font = .system(.caption, design: .monospaced)
    #else
    private let debugFont: Font = .system(.body, design: .monospaced)
    #endif

    @ViewBuilder
    private func debugLine(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label + ":")
                .font(debugFont)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(value)
                .font(debugFont)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
    }

    @ViewBuilder
    private func debugMultiline(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label + ":")
                .font(debugFont)
                .foregroundColor(.secondary)
            Text(value.isEmpty ? "(none)" : value)
                .font(debugFont)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
#endif
