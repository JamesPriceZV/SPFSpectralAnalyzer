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
    @EnvironmentObject private var dataStoreController: DataStoreController
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

    @State private var showAPIKey = false
    @State private var hasStoredAPIKey = false
    @State private var apiKeyDraft = ""
    @State private var showOpenAIKeyBrowser = false

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

    @State private var selectedSettingsTab = SettingsTab.general
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow

    private enum SettingsTab: String, CaseIterable, Identifiable {
        case general = "General"
        case ai = "AI"
        case sync = "iCloud Sync"
        case advanced = "Advanced"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .ai: return "sparkles"
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
        draftInstrumentationEnabled != instrumentationEnabled ||
        draftInstrumentationEnhancedDiagnostics != instrumentationEnhancedDiagnostics
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $selectedSettingsTab) {
                ForEach(SettingsTab.allCases) { tab in
                    #if os(iOS)
                    Image(systemName: tab.icon).tag(tab)
                    #else
                    Label(tab.rawValue, systemImage: tab.icon).tag(tab)
                    #endif
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)

            Form {
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

                Picker("Estimation Tier", selection: spfEstimationOverrideSelection) {
                    ForEach(SPFEstimationOverride.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                Text("Automatic uses the best available tier: Full correction → Calibrated → Adjusted.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                GroupBox("Correction Factors (Tier 1 — Full COLIPA)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("C_factor")
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
                            Text("Substrate Correction")
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

                Text("AI analysis sends selected spectral data to your analysis server or OpenAI.")
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
                .pickerStyle(.segmented)

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

            Section("Authentication") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        if showAPIKey {
                            TextField("OpenAI API Key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                        } else {
                            SecureField("OpenAI API Key", text: $apiKeyDraft)
                                .textFieldStyle(.roundedBorder)
                        }

                        Button(showAPIKey ? "Hide" : "Show") {
                            showAPIKey.toggle()
                        }
                    }

                    #if os(iOS)
                    // iOS: stack buttons vertically for better fit
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
                Text("Train models on Mac. The trained model loads automatically on all platforms.")
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                    aiShowLogWindow = true
                }
                .disabled(!draftDiagnosticsEnabled)

                Divider()

                HStack {
                    Button("Test DNS") {
                        runDNSCheck()
                    }
                    .disabled(resolvedOpenAIHost == nil)

                    Button("Copy DNS Results") {
                        copyDNSResults()
                    }
                    .disabled(dnsStatusMessage == nil)

                    if let dnsStatusLabel {
                        Text(dnsStatusLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                if !dnsStatusIPs.isEmpty {
                    Text("IPs: \(dnsStatusIPs.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
            }

            Section("Instrumentation Outputs") {
                Toggle("In-App Log Panel", isOn: $draftInstrumentationOutputInApp)
                Toggle("Console Logs", isOn: $draftInstrumentationOutputConsole)
                Toggle("File Logs", isOn: $draftInstrumentationOutputFile)
                Toggle("OSLog", isOn: $draftInstrumentationOutputOSLog)

                #if os(macOS)
                Button("Open Diagnostics Console") {
                    openWindow(id: "diagnostics-console")
                }
                #endif
            }

            Section("Instrumentation Detail Level") {
                Toggle("Errors", isOn: $draftInstrumentationLevelErrors)
                Toggle("Warnings", isOn: $draftInstrumentationLevelWarnings)
                Toggle("Verbose (timings + payload sizes)", isOn: $draftInstrumentationLevelVerbose)
            }
            } // end Advanced tab

            }
            .formStyle(.grouped)
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
            #if os(macOS)
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .scrollIndicators(.visible)
            #endif

            #if os(macOS)
            Divider()

            HStack {
                Spacer()
                Button("Apply") {
                    applyDraft()
                }
                .disabled(!settingsAreDirty)
                Button("Save") {
                    applyDraft()
                    dismiss()
                }
                Button("Close") {
                    dismiss()
                }
            }
            .padding(20)
            .background(.regularMaterial)
            #endif
        }
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Apply") {
                    applyDraft()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!settingsAreDirty)
            }
        }
        #endif
        #if DEBUG
        .sheet(isPresented: $showICloudDebugPanel) {
            CloudKitDebugPanel()
        }
        #endif
        #if os(macOS)
        .frame(minWidth: 560, minHeight: 640)
        #endif
        .onAppear {
            loadDraft()
            MLTrainingService.shared.updateAvailableCount(modelContext: modelContext)
            Task {
                await refreshBackupSize()
                if hasStoredAPIKey, canResolveOpenAIHost {
                    await fetchOpenAIModels()
                }
            }
        }
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

        if !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            saveAPIKey()
        }
    }

    private func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        KeychainStore.savePassword(trimmed, account: KeychainKeys.openAIAPIKey)
        hasStoredAPIKey = true
        apiKeyDraft = ""
    }

    private func clearAPIKey() {
        KeychainStore.deletePassword(account: KeychainKeys.openAIAPIKey)
        hasStoredAPIKey = false
        apiKeyDraft = ""
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

    private func runDNSCheck() {
        let host = resolvedOpenAIHost ?? "api.openai.com"
        let addresses = resolveHostAddresses(host)
        dnsStatusIPs = addresses
        if addresses.isEmpty {
            dnsStatusMessage = "DNS failed for \(host)"
        } else {
            dnsStatusMessage = "Resolved \(host)"
        }
        dnsStatusTimestamp = Date()

        if !addresses.isEmpty {
            logAIDiagnostics("DNS resolved \(host)", details: "ips=\(addresses.joined(separator: ", "))")
        } else {
            logAIDiagnostics("DNS failed \(host)")
        }
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
                        KeychainStore.savePassword(trimmed, account: KeychainKeys.openAIAPIKey)
                        hasStoredAPIKey = true
                        apiKeyDraft = ""
                        pastedKey = ""
                        keySaved = true
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
