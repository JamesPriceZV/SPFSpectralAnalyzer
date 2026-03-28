import SwiftUI
import Charts
import UniformTypeIdentifiers
import Foundation
import SwiftData
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
    @Query(
        filter: #Predicate<StoredDataset> { !$0.isArchived },
        sort: \StoredDataset.importedAt,
        order: .reverse
    ) var storedDatasets: [StoredDataset]
    @Query(
        filter: #Predicate<StoredDataset> { $0.isArchived },
        sort: \StoredDataset.archivedAt,
        order: .reverse
    ) var archivedDatasets: [StoredDataset]
    @Query(sort: \StoredInstrument.createdAt, order: .reverse)
    var instruments: [StoredInstrument]


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

    @State var aiVM = AIViewModel()

    @EnvironmentObject var instrumentManager: InstrumentManager

    init(previewSpectra: [ShimadzuSpectrum] = [], previewMode: AppMode = .analyze) {
        let analysisVM = AnalysisViewModel(spectra: previewSpectra)
        _analysis = State(initialValue: analysisVM)
        _datasets = State(initialValue: DatasetViewModel(analysis: analysisVM))
        _appMode = State(initialValue: previewMode)
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
                if appMode == .dataManagement {
                    compactSyncStatusBar
                        .padding(.horizontal, 16)
                        .padding(.top, 6)
                }
                contentArea
                if showBottomTray {
                    bottomTray
                }
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

            // Populate the searchable-text caches for safe dataset filtering
            datasets.updateSearchableTextCache(from: storedDatasets)
            datasets.updateArchivedSearchableTextCache(from: archivedDatasets)
            datasets.updateInstrumentCache(from: instruments)

            // Sync persisted reference exclusions to the ViewModel
            syncExcludedReferencesToViewModel()

            // Restore last session datasets on launch and auto-load Reference datasets
            if analysis.spectra.isEmpty {
                if storedDatasets.isEmpty {
                    // @Query hasn't populated yet — defer to .onChange handler.
                    // Do NOT call restoreLastSession here or it will clear
                    // the saved IDs when it finds zero matching datasets.
                    sessionRestoreAttempted = false
                } else {
                    let restored = datasets.restoreLastSessionOrShowDataManagement(storedDatasets: storedDatasets)
                    sessionRestoreAttempted = true
                    if restored {
                        analysis.applyAlignmentIfNeeded()
                        rebuildAnalysisCaches()
                        analysis.updatePeaks()
                    } else {
                        appMode = .dataManagement
                    }
                }
            } else {
                sessionRestoreAttempted = true
                analysis.applyAlignmentIfNeeded()
                rebuildAnalysisCaches()
                analysis.updatePeaks()
            }
            updateAIEstimate()
        }
        .onChange(of: storedDatasets.count) {
            // Deferred session restore: if .task ran before @Query populated
            // storedDatasets, retry once the data arrives.
            guard !sessionRestoreAttempted, analysis.spectra.isEmpty, !storedDatasets.isEmpty else { return }
            sessionRestoreAttempted = true
            datasets.modelContext = modelContext
            let restored = datasets.restoreLastSessionOrShowDataManagement(storedDatasets: storedDatasets)
            if restored {
                analysis.applyAlignmentIfNeeded()
                rebuildAnalysisCaches()
                analysis.updatePeaks()
                updateAIEstimate()
                appMode = .analyze
            } else {
                appMode = .dataManagement
            }
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
            importPanel
                .tabItem {
                    Label("Data Management", systemImage: "folder.badge.gearshape")
                }
                .tag(AppMode.dataManagement)

            analysisPanel
                .tabItem {
                    Label("Analysis", systemImage: "waveform.path.ecg")
                }
                .tag(AppMode.analyze)

            #if os(iOS)
            SpectralCameraView()
                .tabItem {
                    Label("Camera", systemImage: "camera.fill")
                }
                .tag(AppMode.camera)
            #endif

            exportPanel
                .tabItem {
                    Label("Reporting", systemImage: "doc.text.magnifyingglass")
                }
                .tag(AppMode.reporting)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    var settingsPanel: some View {
        SettingsView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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


