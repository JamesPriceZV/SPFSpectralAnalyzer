import SwiftUI
import UniformTypeIdentifiers
#if canImport(MSAL)
@preconcurrency import MSAL
#endif

extension ContentView {

    func applyImporters<V: View>(_ view: V) -> some View {
        // On iOS the SPC file importer is attached inside iOSDataManagementView
        // so it presents correctly within the NavigationSplitView / TabView.
        #if os(macOS)
        view
            .fileImporter(
                isPresented: $datasets.showImporter,
                allowedContentTypes: [UTType(filenameExtension: "spc") ?? .data],
                allowsMultipleSelection: true,
                onCompletion: datasets.handleImport(result:)
            )
            .fileImporter(
                isPresented: $datasets.showFormulaCardImporter,
                allowedContentTypes: [
                    .pdf,
                    .png,
                    .jpeg,
                    .heic,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(filenameExtension: "docx") ?? .data
                ],
                allowsMultipleSelection: false,
                onCompletion: datasets.handleFormulaCardImport(result:)
            )
            .onOpenURL { url in
                guard url.pathExtension.lowercased() == "spc" else { return }
                Task { await datasets.loadSpectra(from: [url], append: false) }
            }
        #else
        view
            .fileImporter(
                isPresented: $datasets.showFormulaCardImporter,
                allowedContentTypes: [
                    .pdf,
                    .png,
                    .jpeg,
                    .heic,
                    UTType(filenameExtension: "xlsx") ?? .data,
                    UTType(filenameExtension: "docx") ?? .data
                ],
                allowsMultipleSelection: false,
                onCompletion: datasets.handleFormulaCardImport(result:)
            )
            .onOpenURL { url in
                #if canImport(MSAL)
                if url.scheme?.hasPrefix("msauth.") == true {
                    MSALPublicClientApplication.handleMSALResponse(url, sourceApplication: nil)
                    return
                }
                #endif
                guard url.pathExtension.lowercased() == "spc" else { return }
                Task { await datasets.loadSpectra(from: [url], append: false) }
            }
        #endif
    }

    func applyAlertsAndSheets<V: View>(_ view: V) -> some View {
        view
            .alert("Error", isPresented: Binding(get: {
                analysis.errorMessage != nil
            }, set: { isPresented in
                if !isPresented { analysis.errorMessage = nil }
            })) {
                Button("OK") { analysis.errorMessage = nil }
            } message: {
                Text(analysis.errorMessage ?? "Unknown error")
            }
            .sheet(isPresented: $showExportSheet) {
                exportSheet
            }
            .sheet(isPresented: $showWarningDetails) {
                warningDetailsSheet
            }
            .sheet(isPresented: $showInvalidDetails) {
                invalidDetailsSheet
            }
            .sheet(isPresented: $showSpfMathDetails) {
                spfMathSheet
            }
            .sheet(isPresented: $datasets.showStoredDatasetPicker) {
                storedDatasetPickerSheet
            }
            .sheet(isPresented: $datasets.showArchivedDatasetSheet) {
                archivedDatasetSheet
            }
            .sheet(isPresented: $datasets.showReferenceSpfSheet) {
                referenceSpfSheet
            }
            .sheet(isPresented: $datasets.showSamplePlateTypeSheet) {
                samplePlateTypeSheet
            }
            .sheet(isPresented: $datasets.showAssignInstrumentSheet) {
                assignInstrumentSheet
            }
            .sheet(item: $pendingShareContent) { content in
                ShareSheet(items: content.shareItems)
                    #if os(macOS)
                    .frame(width: 1, height: 1)
                    #endif
            }
            // Formula card detail sheet moved to ImportPanel (attached directly to the button)
            // to avoid macOS sheet-stacking limitation.
            .sheet(item: $scheduleEventType) { eventType in
                ScheduleEventSheet(eventType: eventType)
            }
            .confirmationDialog(datasets.archiveConfirmationTitle(storedDatasets: storedDatasets), isPresented: $datasets.showArchiveConfirmation, titleVisibility: .visible) {
                Button("Archive", role: .destructive) {
                    datasets.archivePendingDatasets(storedDatasets: storedDatasets)
                }
                Button("Cancel", role: .cancel) {
                    datasets.pendingArchiveDatasetIDs.removeAll()
                }
            } message: {
                Text(datasets.archiveConfirmationMessage(storedDatasets: storedDatasets))
            }
            .confirmationDialog("Remove duplicate datasets?", isPresented: $datasets.showDuplicateCleanupConfirm, titleVisibility: .visible) {
                Button("Remove Duplicates", role: .destructive) {
                    datasets.removeDuplicateDatasets(storedDatasets: storedDatasets, archivedDatasets: archivedDatasets)
                }
                Button("Cancel", role: .cancel) {
                    datasets.duplicateCleanupTargetIDs.removeAll()
                    datasets.duplicateCleanupMessage = ""
                }
            } message: {
                Text(datasets.duplicateCleanupMessage)
            }
    }

    func applyProcessingChangeHandlers<V: View>(_ view: V) -> some View {
        view
            // Cache updates for storedDatasets/archivedDatasets/instruments are now
            // handled by .onChange(of: datasets.dataVersion) and .onReceive in ContentView.
            .onChange(of: appMode) { _, newMode in
                // Rebuild caches when switching to Analysis tab to pick up any
                // new reference datasets tagged during the Data Management session.
                if newMode == .analyze {
                    rebuildAnalysisCaches()
                }
            }
            .onChange(of: analysis.useAlignment) { _, _ in
                analysis.applyAlignmentIfNeeded()
            }
            .onChange(of: analysis.smoothingMethod) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: analysis.smoothingWindow) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: analysis.sgWindow) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: analysis.sgOrder) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: analysis.baselineMethod) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: analysis.normalizationMethod) { _, _ in
                analysis.applyProcessing()
            }
            .onChange(of: spfDisplayModeRawValue) { _, _ in
                rebuildAnalysisCaches()
            }
    }

    func applySelectionChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: analysis.yAxisMode) { _, _ in
                rebuildAnalysisCaches()
                analysis.updatePeaks()
            }
            .onChange(of: analysis.detectPeaks) { _, _ in
                analysis.updatePeaks()
            }
            .onChange(of: analysis.peakMinHeight) { _, _ in
                analysis.updatePeaks()
            }
            .onChange(of: analysis.peakMinDistance) { _, _ in
                analysis.updatePeaks()
            }
            .onChange(of: analysis.selectedSpectrumIndex) { _, _ in
                rebuildAnalysisCaches()
                analysis.updatePeaks()
                updateAIEstimate()
            }
            .onChange(of: analysis.selectedSpectrumIndices) { _, _ in
                if analysis.showSelectedOnly {
                    analysis.logSelectedOnlySelectionChange()
                }
                rebuildAnalysisCaches()
                analysis.updatePeaks()
                updateAIEstimate()
            }
            .onChange(of: analysis.overlayLimit) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: analysis.palette) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: analysis.includeInvalidInPlots) { _, newValue in
                if !newValue {
                    analysis.selectedInvalidItemIDs.removeAll()
                }
                rebuildAnalysisCaches()
            }
            .onChange(of: spfCalculationMethodRawValue) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: spfEstimationOverrideRawValue) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: spfCFactor) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: spfSubstrateCorrection) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: spfAdjustmentFactor) { _, _ in
                rebuildAnalysisCaches()
            }
    }

    func applyHDRSChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: analysis.hdrsSpectrumTags) { _, _ in
                rebuildAnalysisCaches()
            }
            .onChange(of: analysis.hdrsProductType) { _, _ in
                rebuildAnalysisCaches()
            }
    }

    func applyAIChangeHandlers<V: View>(_ view: V) -> some View {
        view
            .onChange(of: aiPromptPresetRawValue) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiDefaultScopeRawValue) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiVM.scopeOverride) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiVM.useCustomPrompt) { _, _ in
                updateAIEstimate()
            }
            .onChange(of: aiVM.customPrompt) { _, _ in
                updateAIEstimate()
            }
    }

}
