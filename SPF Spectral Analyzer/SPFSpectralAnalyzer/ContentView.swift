import SwiftUI
import Charts
import Combine
import UniformTypeIdentifiers
import Foundation
import SwiftData
import CoreData
import CryptoKit

struct ContentView: View {
    @EnvironmentObject var dataStoreController: DataStoreController
    @State var analysis = AnalysisViewModel()
    @State var datasets: DatasetViewModel

    @State var appMode: AppMode = .analyze
    @State var showBottomTray = true
    @State var showPipelineDetails = false
    @State var showInspectorDetails = true
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

    @State var syncPanelExpanded = false

    @State var showWarningDetails = false
    @State var showInvalidDetails = false
    @State var showInvalidInline = false
    @State private var sessionRestoreAttempted = false
    @State var showSpfMathDetails = false

    @State var showExportSheet = false
    @State var scheduleEventType: ScheduleEventSheet.EventType?
    @State var exportFormat: ExportFormat = .csv
    @State var exportTitle = ""
    @State var exportOperator = ""
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

    @EnvironmentObject var instrumentManager: InstrumentManager

    init(authManager: MSALAuthManager, previewSpectra: [ShimadzuSpectrum] = [], previewMode: AppMode = .analyze) {
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
        Instrumentation.log(
            "rebuildAnalysisCaches",
            area: .processing, level: .info,
            details: "calibrationSnapshots=\(calibrationData.count) storedDatasets=\(storedDatasets.count) spectra=\(analysis.spectra.count) cacheSize=\(datasets.searchableRecordCache.count)"
        )
        analysis.rebuildCaches(spfConfig: currentSPFConfig, externalCalibrationSnapshots: calibrationData)
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
                #if os(macOS)
                if appMode == .dataManagement {
                    compactSyncStatusBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                #endif
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
            datasets.onImportComplete = { appMode = .analyze }
            datasets.onSpectraLoaded = { [self] in updateAIEstimate() }

            // One-time migration: the old default adjustment factor of 20.0 produced
            // unrealistic SPF values (raw × 20). Reset to 1.0 if still at old default.
            if spfAdjustmentFactor == 20.0 {
                spfAdjustmentFactor = 1.0
            }

            // Manual fetch replaces @Query — synchronous, so data is immediately available.
            refreshAllData()

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

            // Restore last session datasets on launch and auto-load Reference datasets
            if analysis.spectra.isEmpty {
                let restored = datasets.restoreLastSessionOrShowDataManagement(storedDatasets: storedDatasets)
                sessionRestoreAttempted = true
                if restored {
                    analysis.applyAlignmentIfNeeded()
                    rebuildAnalysisCaches()
                    analysis.updatePeaks()
                } else {
                    appMode = .dataManagement
                }
            } else {
                sessionRestoreAttempted = true
                analysis.applyAlignmentIfNeeded()
                rebuildAnalysisCaches()
                analysis.updatePeaks()
            }
            updateAIEstimate()
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
                .debounce(for: .seconds(2), scheduler: RunLoop.main)
        ) { _ in
            // Re-fetch after CloudKit sync delivers remote changes
            refreshAllData()
            datasets.updateSearchableTextCache(from: storedDatasets)
            datasets.updateArchivedSearchableTextCache(from: archivedDatasets)
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
            Text("Data Management")
                .tag(AppMode.dataManagement)
                .accessibilityIdentifier("tabDataManagement")
            Text("Analysis")
                .tag(AppMode.analyze)
                .accessibilityIdentifier("tabAnalysis")
            Text("Reporting")
                .tag(AppMode.reporting)
                .accessibilityIdentifier("tabReporting")
            Text("Settings")
                .tag(AppMode.settings)
                .accessibilityIdentifier("tabSettings")
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .accessibilityLabel("Mode")
        .accessibilityIdentifier("appModePicker")
        .frame(maxWidth: 500)
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


    @ViewBuilder
    var contentArea: some View {
        TabView(selection: $appMode) {
            #if os(iOS)
            // Primary lab workflow tabs
            Tab("Data", systemImage: "folder.badge.gearshape", value: AppMode.dataManagement) {
                iOSDataManagementView(
                    analysis: analysis,
                    datasets: datasets,
                    appMode: $appMode,
                    storedDatasets: storedDatasets,
                    archivedDatasets: archivedDatasets,
                    instruments: instruments
                )
            }

            Tab("Analysis", systemImage: "waveform.path.ecg", value: AppMode.analyze) {
                iOSAnalysisView(
                    analysis: analysis,
                    datasets: datasets,
                    aiVM: aiVM,
                    storedDatasets: storedDatasets,
                    runAI: { self.runAIAnalysis() }
                )
            }

            Tab("Camera", systemImage: "camera.fill", value: AppMode.camera) {
                SpectralCameraView()
            }

            Tab("Reporting", systemImage: "doc.text.magnifyingglass", value: AppMode.reporting) {
                iOSReportingPanel
            }

            Tab("Enterprise", systemImage: "building.2.fill", value: AppMode.enterprise) {
                EnterpriseSearchView(authManager: aiVM.m365AuthManager)
            }

            Tab("Settings", systemImage: "gearshape", value: AppMode.settings) {
                settingsPanel
            }
            #else
            Tab("Data Management", systemImage: "folder.badge.gearshape", value: AppMode.dataManagement) {
                importPanel
            }

            Tab("Analysis", systemImage: "waveform.path.ecg", value: AppMode.analyze) {
                analysisPanel
            }

            Tab("Reporting", systemImage: "doc.text.magnifyingglass", value: AppMode.reporting) {
                exportPanel
            }

            Tab("Enterprise", systemImage: "building.2.fill", value: AppMode.enterprise) {
                EnterpriseSearchView(authManager: aiVM.m365AuthManager)
            }
            #endif
        }
        #if os(iOS)
        .tabViewStyle(.sidebarAdaptable)
        .tabBarMinimizeBehavior(.onScrollDown)
        #endif
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var settingsPanel: some View {
        #if os(iOS)
        NavigationStack {
            SettingsView(m365AuthManager: aiVM.m365AuthManager)
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
        }
        #else
        SettingsView(m365AuthManager: aiVM.m365AuthManager)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }

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


