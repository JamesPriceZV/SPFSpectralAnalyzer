// SPCLibraryBridge.swift
// SPFSpectralAnalyzer
//
// @MainActor bridge between the Library's DatasetViewModel and SPCKit's
// SPCDocumentStore. One SPCDocumentStore per open editor session.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import CryptoKit

@MainActor
@Observable
final class SPCLibraryBridge {

    // MARK: - Public state

    private(set) var activeStore: SPCDocumentStore?
    private(set) var editingDataset: StoredDataset?
    var isEditorPresented: Bool = false
    var isCombining: Bool = false
    var presentedError: String?

    // MARK: - Open for editing

    func openForEditing(_ dataset: StoredDataset) async {
        guard let data = dataset.fileData else {
            presentedError = "No file data available for \(dataset.fileName)."
            return
        }
        do {
            let spcFile = try SPCParser.parse(data: data)
            let store = SPCDocumentStore()
            store.loadParsed(spcFile)
            await store.refreshResolvedStatePublic()
            let baseName = dataset.fileName
                .replacingOccurrences(of: ".spc", with: "", options: .caseInsensitive)
            store.documentName = baseName
            // Name subfiles after the dataset filename
            let subfiles = store.resolvedSubfiles
            for sub in subfiles {
                let name = subfiles.count == 1 ? baseName : "\(baseName)_\(sub.id + 1)"
                await store.apply(.renameSubfile(subfileIndex: sub.id, newName: name))
            }
            activeStore = store
            editingDataset = dataset
            isEditorPresented = true
        } catch {
            presentedError = "Cannot open \(dataset.fileName): \(error.localizedDescription)"
        }
    }

    // MARK: - Create new blank SPC dataset

    /// Create a new blank SPC file with a single empty subfile and open it in the editor.
    func createNewDataset() {
        let header = SPCMainHeader(
            flags: SPCFileFlags(rawValue: 0),
            version: .newFormat,
            experimentType: 0,
            yExponent: 0x80,
            pointCount: 0,
            firstX: 0,
            lastX: 0,
            subfileCount: 0,
            xUnitsCode: 0,
            yUnitsCode: 0,
            zUnitsCode: 0,
            compressedDate: 0,
            resolutionDescription: "",
            sourceInstrument: "",
            peakPoint: 0,
            memo: "Created in SPF Spectral Analyzer",
            customAxisLabels: "",
            logOffset: 0,
            modificationFlag: 0,
            concentrationFactor: 0,
            methodFile: "",
            zIncrement: 0,
            wPlaneCount: 0,
            wIncrement: 0,
            wUnitsCode: 0
        )
        let axis = AxisMetadata(
            xUnitsCode: 0, yUnitsCode: 0, zUnitsCode: 0, wUnitsCode: 0,
            customXLabel: nil, customYLabel: nil, customZLabel: nil,
            firstX: 0, lastX: 0
        )
        let spcFile = SPCFile(
            header: header,
            axisMetadata: axis,
            subfiles: [],
            auditLog: [],
            binaryLogData: nil
        )
        let store = SPCDocumentStore()
        store.loadParsed(spcFile)
        store.documentName = "New Dataset"
        activeStore = store
        editingDataset = nil
        isEditorPresented = true
    }

    // MARK: - Duplicate dataset

    /// Duplicate a StoredDataset by mutating its memo metadata so the SHA256 hash differs,
    /// then open the duplicate in the editor for further changes.
    func duplicateDataset(_ dataset: StoredDataset) async {
        guard let data = dataset.fileData else {
            presentedError = "No file data available for \(dataset.fileName)."
            return
        }
        do {
            let spcFile = try SPCParser.parse(data: data)
            let store = SPCDocumentStore()
            store.loadParsed(spcFile)
            await store.refreshResolvedStatePublic()

            // Apply a metadata edit to the memo so the resulting file will have
            // a different SHA256 hash and won't be blocked by dedup.
            let timestamp = ISO8601DateFormatter().string(from: Date())
            let newMemo = "Duplicated \(timestamp)"
            await store.apply(.editMemo(newMemo: newMemo))

            let baseName = dataset.fileName
                .replacingOccurrences(of: ".spc", with: "", options: .caseInsensitive)
            let copyName = "\(baseName) (Copy)"
            store.documentName = copyName
            // Name subfiles after the duplicate filename
            let subfiles = store.resolvedSubfiles
            for sub in subfiles {
                let name = subfiles.count == 1 ? copyName : "\(copyName)_\(sub.id + 1)"
                await store.apply(.renameSubfile(subfileIndex: sub.id, newName: name))
            }
            activeStore = store
            editingDataset = nil   // Not editing the original — this is a new copy
            isEditorPresented = true
        } catch {
            presentedError = "Cannot duplicate \(dataset.fileName): \(error.localizedDescription)"
        }
    }

    // MARK: - Combine multiple datasets into one SPC file

    func combineDatasets(_ datasets: [StoredDataset]) async {
        guard datasets.count >= 2 else {
            presentedError = "Select at least 2 datasets to combine."
            return
        }
        isCombining = true
        defer { isCombining = false }

        guard let firstData = datasets.first?.fileData else {
            presentedError = "First dataset has no file data."
            return
        }
        do {
            let baseFile = try SPCParser.parse(data: firstData)
            let store = SPCDocumentStore()
            store.loadParsed(baseFile)
            await store.refreshResolvedStatePublic()
            store.documentName = "Combined"

            for dataset in datasets.dropFirst() {
                guard let data = dataset.fileData else { continue }
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent(dataset.fileName)
                try data.write(to: tempURL)
                await store.importSubfiles(from: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
            }

            activeStore = store
            editingDataset = nil
            isEditorPresented = true
        } catch {
            presentedError = "Combine failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Save As

    func handleSaveAs(
        data: Data,
        format: SPCExportFormat,
        suggestedName: String,
        modelContext: ModelContext
    ) {
        let newDataset = StoredDataset(
            fileName: suggestedName,
            sourcePath: nil,
            fileHash: nil,
            fileData: data,
            metadataJSON: nil,
            headerInfoData: nil,
            skippedDataJSON: nil,
            warningsJSON: nil
        )
        newDataset.spcKitEdited = true
        newDataset.spcFileFormat = format.rawValue
        modelContext.insert(newDataset)
        do {
            try modelContext.save()
        } catch {
            presentedError = "Failed to save dataset: \(error.localizedDescription)"
        }
    }

    // MARK: - Add datasets to active editor

    /// Import subfiles from stored datasets into the currently open editor session.
    func addDatasetsToEditor(_ datasets: [StoredDataset]) async {
        guard let store = activeStore else { return }
        for dataset in datasets {
            guard let data = dataset.fileData else { continue }
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(dataset.fileName)
            do {
                try data.write(to: tempURL)
                await store.importSubfiles(from: tempURL)
                try? FileManager.default.removeItem(at: tempURL)
            } catch {
                presentedError = "Failed to import \(dataset.fileName): \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Dismiss editor

    func dismissEditor() {
        isEditorPresented = false
        activeStore = nil
        editingDataset = nil
    }

    // MARK: - Helpers

    static func canOpen(_ dataset: StoredDataset) -> Bool {
        guard let data = dataset.fileData, data.count >= 256 else { return false }
        let versionByte = data[1]
        if versionByte == 0x4B || versionByte == 0x4D { return true }
        if data.count >= 8 {
            let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
            return zip(magic, data.prefix(8)).allSatisfy { $0 == $1 }
        }
        return false
    }
}
