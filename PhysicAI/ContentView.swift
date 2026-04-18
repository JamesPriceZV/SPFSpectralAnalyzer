import SwiftUI
import Charts
import Combine
import UniformTypeIdentifiers
import Foundation
import SwiftData
import CoreData
import CryptoKit

struct ContentView: View {
    @Environment(DataStoreController.self) var dataStoreController
    @State var analysis = AnalysisViewModel()
    @State var datasets: DatasetViewModel

    @State var appMode: AppMode = .analysis
    @State var showBottomTray = true
    @State var showPipelineDetails = false
    @State var showInspectorDetails = true
    @State var showSettingsSheet = false
    @Namespace var glassNamespace
    @Environment(\.undoManager) var undoManager
    @Environment(\.modelContext) var modelContext
    @Environment(\.openWindow) var openWindow
    #if os(iOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #endif
    // Manual fetching replaces @Query to prevent SwiftData framework crash
    // during CloudKit sync (brk #0x1 in _SwiftData_SwiftUI re-evaluation).
    @State var storedDatasets: [StoredDataset] = []
    @State var archivedDatasets: [StoredDataset] = []
    @State var instruments: [StoredInstrument] = []


    @State var expandChart = false


    // MARK: - Sidebar State
    @State var datasetSidebarCollapsed: Bool = false
    @State var sidebarSortMode: SidebarSortMode = .importOrder
    @State var sidebarFilterText: String = ""
    @State var showSidebarSearchHelp: Bool = false
    @State var analysisSidebarTab: AnalysisSidebarTab = .all

    @State var syncPanelExpanded = false

    @State var showWarningDetails = false
    @State var showInvalidDetails = false
    @State var showInvalidInline = false
    @State private var sessionRestoreAttempted = false
    @State var showSpfMathDetails = false

    @State var dropTargeted = false
    @State var showExportSheet = false
    @State var showBatchComparePopout = false
    @State var scheduleEventType: ScheduleEventSheet.EventType?
    @State var exportFormat: ExportFormat = .csv
    @State var exportTitle = ""
    #if os(macOS)
    @State var exportOperator = ProcessInfo.processInfo.fullUserName
    #else
    @State var exportOperator = ""
    #endif
    @State var exportNotes = ""
    @State var exportIncludeProcessing = true
    @State var exportIncludeMetadata = true


    @AppStorage("aiEnabled") var aiEnabled = false
    @AppStorage("aiTemperature") var aiTemperature = 0.3
    @AppStorage("aiMaxTokens") var aiMaxTokens = 800
    @AppStorage("aiPromptPreset") var aiPromptPresetRawValue = AIPromptPreset.summary.rawValue
    @AppStorage("aiAutoRun") var aiAutoRun = false
    @AppStorage("aiDefaultScope") var aiDefaultScopeRawValue = AISelectionScope.selected.rawValue
    @AppStorage("aiOpenAIEndpoint") var aiOpenAIEndpoint = "https://api.openai.com/v1/responses"
    @AppStorage("aiOpenAIModel") var aiOpenAIModel = "gpt-5.4"
    @AppStorage("aiDiagnosticsEnabled") var aiDiagnosticsEnabled = false
    @AppStorage("aiStructuredOutputEnabled") var aiStructuredOutputEnabled = true
    @AppStorage("aiResponseTextSize") var aiResponseTextSize = 12.0
    @AppStorage("aiCostPerThousandTokens") var aiCostPerThousandTokens = 0.01
    @AppStorage("aiProviderPreference") var aiProviderPreferenceRawValue = AIProviderPreference.auto.rawValue
    @AppStorage("aiClaudeModel") var aiClaudeModel = "claude-sonnet-4-5-20250514"
    @AppStorage("aiGrokModel") var aiGrokModel = "grok-3"
    @AppStorage("aiGeminiModel") var aiGeminiModel = "gemini-2.5-flash"

    // Multi-provider routing
    @AppStorage("aiProviderPriorityOrder") var aiProviderPriorityOrderJSON = ""
    @AppStorage("aiAdvancedRoutingEnabled") var aiAdvancedRoutingEnabled = false
    @AppStorage("aiFunctionRoutingJSON") var aiFunctionRoutingJSON = ""
    @AppStorage("aiEnsembleModeEnabled") var aiEnsembleModeEnabled = false
    @AppStorage("aiEnsembleProvidersJSON") var aiEnsembleProvidersJSON = ""
    @AppStorage("aiEnsembleArbitrationEnabled") var aiEnsembleArbitrationEnabled = true
    @AppStorage("aiCostTrackingEnabled") var aiCostTrackingEnabled = false

    @AppStorage("spfDisplayMode") var spfDisplayModeRawValue = SpfDisplayMode.calibrated.rawValue
    @AppStorage("spfEstimationOverride") var spfEstimationOverrideRawValue = SPFEstimationOverride.automatic.rawValue
    @AppStorage("spfCFactor") var spfCFactor = 0.0
    @AppStorage("spfSubstrateCorrection") var spfSubstrateCorrection = 0.0
    @AppStorage("spfAdjustmentFactor") var spfAdjustmentFactor = 1.0
    @AppStorage("spfCalculationMethod") var spfCalculationMethodRawValue = SPFCalculationMethod.colipa.rawValue

    @AppStorage("excludedReferenceDatasetIDs") var excludedReferenceIDsJSON = ""
    @State var showReferenceFilterPopover = false

    @AppStorage("swiftDataStoreResetOccurred") var storeResetOccurred = false
    @AppStorage("swiftDataStoreResetMessage") var storeResetMessage = ""
    @AppStorage("icloudLastSyncStatus") var icloudLastSyncStatus = "Not synced yet"
    @AppStorage("icloudLastSyncTimestamp") var icloudLastSyncTimestamp = 0.0
    @AppStorage("icloudSyncInProgress") var icloudSyncInProgress = false
    @AppStorage("icloudProgressCollapsed") var icloudProgressCollapsed = true
    @AppStorage("icloudLastSyncTrigger") var icloudLastSyncTrigger = ""
    @AppStorage("toolbarShowLabels") var toolbarShowLabels = false

    @State var aiVM: AIViewModel
    @State var pendingShareContent: ShareableContent?
    @State var spcLibraryBridge = SPCLibraryBridge()

    @EnvironmentObject var instrumentManager: InstrumentManager

    init(authManager: MSALAuthManager, previewSpectra: [ShimadzuSpectrum] = [], previewMode: AppMode = .analysis) {
        let analysisVM = AnalysisViewModel(spectra: previewSpectra)
        _analysis = State(initialValue: analysisVM)
        _datasets = State(initialValue: DatasetViewModel(analysis: analysisVM))
        _appMode = State(initialValue: previewMode)
        _aiVM = State(initialValue: AIViewModel(authManager: authManager))
    }

    var currentSPFConfig: SPFConfiguration {
        SPFConfiguration(
            cFactor: spfCFactor,
            substrateCorrection: spfSubstrateCorrection,
            adjustmentFactor: spfAdjustmentFactor,
            estimationOverride: SPFEstimationOverride(rawValue: spfEstimationOverrideRawValue) ?? .automatic,
            calculationMethod: SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
        )
    }

    func runAnalysisPipeline() {
        analysis.runPipeline()
        if aiEnabled && aiAutoRun {
            runAIAnalysis()
        }
    }

    func rebuildAnalysisCaches() {
        let calibrationData = datasets.resolveReferenceCalibrationData(storedDatasets: storedDatasets)
        // Build a map of dataset-level irradiation overrides so the dashboard
        // can correctly classify pre/post samples even without filename keywords.
        var irradiationOverrides: [UUID: Bool] = [:]
        for (id, record) in datasets.searchableRecordCache {
            if let isPost = record.isPostIrradiation {
                irradiationOverrides[id] = isPost
            }
        }
        Instrumentation.log(
            "rebuildAnalysisCaches",
            area: .processing, level: .info,
            details: "calibrationSnapshots=\(calibrationData.count) storedDatasets=\(storedDatasets.count) spectra=\(analysis.spectra.count) cacheSize=\(datasets.searchableRecordCache.count) irradiationOverrides=\(irradiationOverrides.count)"
        )
        analysis.rebuildCaches(spfConfig: currentSPFConfig, externalCalibrationSnapshots: calibrationData, datasetIrradiationOverrides: irradiationOverrides)
    }

    var body: some View {
        applyHDRSChangeHandlers(
            applyAIChangeHandlers(
                applySelectionChangeHandlers(
                    applyProcessingChangeHandlers(
                        applyAlertsAndSheets(
                            applyImporters(baseContent)
                        )
                    )
                )
            )
        )
    }

    var baseContent: some View {
        ZStack {
            backgroundView
            VStack(spacing: 0) {
                if isRunningUITests {
                    // UI tests anchor on this segmented control for mode switching.
                    // Placed in the view hierarchy (not toolbar) for reliable
                    // accessibility tree visibility across macOS versions.
                    modePicker
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }
                contentArea
                #if os(macOS)
                if showBottomTray {
                    bottomTray
                }
                #endif
            }
        }
        .onAppear {
            #if os(macOS)
            AppIconRenderer.applyRuntimeIcon()
            #endif
        }
        .task {
            // Wire DatasetViewModel dependencies
            datasets.modelContext = modelContext
            datasets.dataStoreController = dataStoreController
            datasets.onImportComplete = nil
            datasets.onSpectraLoaded = { [self] in updateAIEstimate() }

            // One-time migration: the old default adjustment factor of 20.0 produced
            // unrealistic SPF values (raw × 20). Reset to 1.0 if still at old default.
            if spfAdjustmentFactor == 20.0 {
                spfAdjustmentFactor = 1.0
            }

            // Manual fetch replaces @Query — synchronous, so data is immediately available.
            refreshAllData()

            // Yield to let the UI render its first frame before heavy cache work.
            await Task.yield()

            // Populate the searchable-text caches for safe dataset filtering
            datasets.updateSearchableTextCache(from: storedDatasets)
            datasets.updateArchivedSearchableTextCache(from: archivedDatasets)
            datasets.updateInstrumentCache(from: instruments)

            // Sync persisted reference exclusions to the ViewModel
            syncExcludedReferencesToViewModel()

            // Restore persisted dataset selections (checkmarks in left panel)
            let savedSelections = DatasetViewModel.readSelectedDatasetIDs()
            let validSelections = savedSelections.intersection(Set(storedDatasets.map(\.id)))
            if !validSelections.isEmpty {
                datasets.selectedStoredDatasetIDs = validSelections
            }

            // Yield again before session restore (another batch of SwiftData queries)
            await Task.yield()

            // Restore last session datasets on launch and auto-load Reference datasets
            if analysis.spectra.isEmpty {
                let restored = datasets.restoreLastSessionOrShowDataManagement(storedDatasets: storedDatasets)
                sessionRestoreAttempted = true
                if restored {
                    analysis.applyAlignmentIfNeeded()
                    await Task.yield()
                    rebuildAnalysisCaches()
                    analysis.updatePeaks()
                } else {
                    appMode = .library
                }
            } else {
                sessionRestoreAttempted = true
                analysis.applyAlignmentIfNeeded()
                await Task.yield()
                rebuildAnalysisCaches()
                analysis.updatePeaks()
            }
            updateAIEstimate()

            // Verify API keys from Keychain and test connectivity
            await aiVM.verifyAPIKeysOnStartup()
        }
        .onChange(of: datasets.dataVersion) { _, _ in
            // Re-fetch after local mutations (import, role assignment, archive, delete, etc.)
            refreshAllData()
            datasets.debouncedUpdateSearchableTextCache(from: storedDatasets)
            datasets.debouncedUpdateArchivedSearchableTextCache(from: archivedDatasets)
            datasets.updateInstrumentCache(from: instruments)
        }
        .onReceive(
            NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                .debounce(for: .seconds(3), scheduler: RunLoop.main)
        ) { _ in
            // Re-fetch after CloudKit sync delivers remote changes.
            // Use debounced cache rebuilds to avoid blocking the main thread
            // with heavy SearchableTextCache iterations during rapid sync.
            refreshAllData()
            datasets.debouncedUpdateSearchableTextCache(from: storedDatasets)
            datasets.debouncedUpdateArchivedSearchableTextCache(from: archivedDatasets)
            datasets.updateInstrumentCache(from: instruments)
        }
        .confirmationDialog("Save AI Analysis?", isPresented: $aiVM.showSavePrompt, titleVisibility: .visible) {
            Button("Save to File") { saveAIResultToDisk() }
            Button("Open") { saveAIResultToDefaultAndOpen() }
            Button("Not Now", role: .cancel) { }
        }
    }

    var modePicker: some View {
        Picker("Mode", selection: $appMode) {
            Text("Library")
                .tag(AppMode.library)
                .accessibilityIdentifier("tabLibrary")
            Text("Analysis")
                .tag(AppMode.analysis)
                .accessibilityIdentifier("tabAnalysis")
            Text("AI")
                .tag(AppMode.ai)
                .accessibilityIdentifier("tabAI")
            Text("Export")
                .tag(AppMode.export)
                .accessibilityIdentifier("tabExport")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Mode")
        .accessibilityIdentifier("appModePicker")
        .frame(maxWidth: 600)
    }

    /// Manually fetches all datasets and instruments using FetchDescriptor.
    /// Replaces @Query to prevent SwiftData framework crash during CloudKit sync.
    private func refreshAllData() {
        do {
            let activeDescriptor = FetchDescriptor<StoredDataset>(
                predicate: #Predicate { !$0.isArchived },
                sortBy: [SortDescriptor(\.importedAt, order: .reverse)]
            )
            storedDatasets = try modelContext.fetch(activeDescriptor)

            let archivedDescriptor = FetchDescriptor<StoredDataset>(
                predicate: #Predicate { $0.isArchived },
                sortBy: [SortDescriptor(\.archivedAt, order: .reverse)]
            )
            archivedDatasets = try modelContext.fetch(archivedDescriptor)

            let instrumentDescriptor = FetchDescriptor<StoredInstrument>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            instruments = try modelContext.fetch(instrumentDescriptor)

            let formulaCardDescriptor = FetchDescriptor<StoredFormulaCard>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
            )
            datasets.formulaCards = try modelContext.fetch(formulaCardDescriptor)
        } catch {
            Instrumentation.log(
                "refreshAllData failed",
                area: .processing, level: .error,
                details: "\(error.localizedDescription)"
            )
        }
    }

    var isRunningUITests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        || ProcessInfo.processInfo.environment["UITEST_MODE"] == "1"
    }

    var isLocalStore: Bool {
        dataStoreController.storeMode == "local"
    }


    // MARK: - Tab Content Wrappers

    @ViewBuilder
    var contentArea: some View {
        TabView(selection: $appMode) {
            // ── Primary Tabs (visible in tab bar) ──
            Tab("Library", systemImage: "books.vertical", value: AppMode.library) {
                libraryContent
            }

            Tab("Analysis", systemImage: "waveform.path.ecg", value: AppMode.analysis) {
                analysisContent
            }

            Tab("AI", systemImage: "brain.head.profile", value: AppMode.ai) {
                aiTabContent
            }

            Tab("Export", systemImage: "square.and.arrow.up", value: AppMode.export) {
                exportContent
            }

            // ── Sidebar Sections ──
            TabSection("Tools") {
                #if os(iOS)
                Tab("Camera", systemImage: "camera", value: AppMode.camera) {
                    SpectralCameraView(datasets: datasets, storedDatasets: storedDatasets)
                }
                #endif

                Tab("Instruments", systemImage: "gauge.with.dots.needle.33percent", value: AppMode.instruments) {
                    InstrumentRegistryView()
                }

                Tab("ML Training", systemImage: "cpu", value: AppMode.mlTraining) {
                    MLTrainingView(authManager: aiVM.m365AuthManager)
                }

                Tab("Jobs & Downloads", systemImage: "square.and.arrow.down.on.square", value: AppMode.jobsDownloads) {
                    JobsDownloadsView()
                }
            }

            #if os(iOS)
            TabSection("Settings") {
                Tab("Settings", systemImage: "gearshape", value: AppMode.settings) {
                    SettingsView(m365AuthManager: aiVM.m365AuthManager)
                }
            }
            #endif

            TabSection("Enterprise") {
                Tab("Copilot", systemImage: "sparkle", value: AppMode.enterprise) {
                    CopilotChatView(authManager: aiVM.m365AuthManager)
                }
                Tab("SharePoint", systemImage: "building.2", value: AppMode.sharePoint) {
                    EnterpriseFileBrowserView(authManager: aiVM.m365AuthManager, initialSource: .sharePoint)
                }
                Tab("OneDrive", systemImage: "cloud", value: AppMode.oneDrive) {
                    EnterpriseFileBrowserView(authManager: aiVM.m365AuthManager, initialSource: .oneDrive)
                }
                Tab("Teams", systemImage: "bubble.left.and.text.bubble.right", value: AppMode.teams) {
                    TeamsView(authManager: aiVM.m365AuthManager)
                }
                Tab("Search", systemImage: "magnifyingglass", value: AppMode.enterpriseSearch) {
                    EnterpriseSearchView(authManager: aiVM.m365AuthManager)
                }
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettingsSheet = true } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .sheet(isPresented: $showSettingsSheet) {
            SettingsView(m365AuthManager: aiVM.m365AuthManager, isSheet: true)
        }
        .onChange(of: appMode) { _, newMode in
            if newMode == .analysis,
               analysis.spectra.isEmpty,
               !datasets.selectedStoredDatasetIDs.isEmpty {
                datasets.loadStoredDatasetSelection(append: false, storedDatasets: storedDatasets)
            }
        }
        #endif
    }

    @ViewBuilder
    var libraryContent: some View {
        #if os(iOS)
        iOSDataManagementView(
            analysis: analysis,
            datasets: datasets,
            appMode: $appMode,
            storedDatasets: storedDatasets,
            archivedDatasets: archivedDatasets,
            instruments: instruments,
            spcLibraryBridge: spcLibraryBridge
        )
        #else
        VStack(spacing: 0) {
            compactSyncStatusBar
                .padding(.horizontal, 16)
                .padding(.top, 6)
            importPanel
        }
        #endif
    }

    @ViewBuilder
    var analysisContent: some View {
        #if os(iOS)
        iOSAnalysisView(
            analysis: analysis,
            datasets: datasets,
            aiVM: aiVM,
            storedDatasets: storedDatasets,
            runAI: { self.runAIAnalysis() }
        )
        #else
        analysisPanel
        #endif
    }

    @ViewBuilder
    var exportContent: some View {
        #if os(iOS)
        iOSReportingPanel
        #else
        exportPanel
        #endif
    }

    // aiTabContent is defined in AIInspectorView.swift (ContentView extension)
    // to keep AI-related view code consolidated.

    // MARK: - SPF Helpers

    func spfValue(for spectrum: ShimadzuSpectrum, metrics: SpectralMetrics) -> Double? {
        let method = SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
        let rawSpf = SpectralMetricsCalculator.spf(x: spectrum.x, y: spectrum.y, yAxisMode: analysis.yAxisMode, method: method)
        let overrideMode = SPFEstimationOverride(rawValue: spfEstimationOverrideRawValue) ?? .automatic
        let result = SPFEstimationResolver.resolve(
            rawColipaSPF: rawSpf, calibrationResult: analysis.calibrationResult,
            nearestMatch: analysis.cachedNearestMatch,
            metrics: metrics,
            cFactor: spfCFactor > 0 ? spfCFactor : nil,
            substrateCorrection: spfSubstrateCorrection > 0 ? spfSubstrateCorrection : nil,
            adjustmentFactor: spfAdjustmentFactor,
            override: overrideMode,
            calculationMethod: method
        )
        if result == nil {
            Instrumentation.log(
                "spfValue nil",
                area: .processing, level: .warning,
                details: "spectrum=\(spectrum.name) rawSpf=\(rawSpf.map { String($0) } ?? "nil") method=\(method.rawValue) override=\(overrideMode.rawValue) xRange=\(spectrum.x.first ?? 0)–\(spectrum.x.last ?? 0)"
            )
        }
        return result?.value
    }

}


extension ContentView {

    var spfDisplayMode: SpfDisplayMode {
        SpfDisplayMode(rawValue: spfDisplayModeRawValue) ?? .calibrated
    }
}


