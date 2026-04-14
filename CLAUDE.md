# SPF Spectral Analyzer — SPCKit Integration

## AUTONOMOUS IMPLEMENTATION INSTRUCTIONS

This file drives a complete, autonomous implementation of the SPCKit integration into the
SPF Spectral Analyzer Library. Execute every phase in order. Do not skip steps. After each
phase, verify the project compiles before proceeding to the next phase.

---

## Project Context

**SPF Spectral Analyzer** is a multi-platform SwiftUI app (iOS 26.4 / macOS 26.4) for
importing, analysing, and reporting spectral datasets. Files are persisted in SwiftData
(`StoredDataset`) and synced via CloudKit. The Library section handles all file import
and dataset management.

**SPCKit** is a companion project (sibling folder `../../SPCKit/` relative to this file,
i.e., at `/4_XcodeProjects/SPCKit/`) that is a complete SPC binary file engine: it parses
Galactic/Thermo format, Shimadzu OLE2/CFB format, and writes both. It has non-destructive
delta-store editing, vDSP transforms, expression parsing, and audit-log support. All types
are Swift 6 strict-concurrency compliant (`nonisolated Sendable` value types, actors).

**Goal:** Replace the read-only SPC import stack in the Analyzer with the full SPCKit engine,
enabling Library users to open, edit, transform, combine, and save SPC files without leaving
the app.

---

## Target Settings (do not change)

- Bundle ID: com.zincoverde.SPFSpectralAnalyzer
- Min deployment: iOS 26.4, macOS 26.4
- Swift 6, strict concurrency: ENABLED
- No @unchecked Sendable, no DispatchQueue, no completion handlers
- Zero external dependencies

---

## Source File Paths

All paths below are relative to this CLAUDE.md file's directory
(`SPF Spectral Analyzer/`).

### SPCKit source location (read-only source — copy FROM here)
```
../../SPCKit/CompoundFileReader.swift
../../SPCKit/EditSession.swift
../../SPCKit/EditViews.swift
../../SPCKit/ExpressionParser.swift
../../SPCKit/HelpView.swift
../../SPCKit/PointEditValidator.swift
../../SPCKit/SPCDocumentStore.swift
../../SPCKit/SPCFile.swift
../../SPCKit/SPCFileWriter.swift
../../SPCKit/SPCParser.swift
../../SPCKit/SpectrumChartView.swift
../../SPCKit/TransformEngine.swift
```

### Files to create (new — write these)
```
SPFSpectralAnalyzer/SPCKit/CompoundFileReader.swift   (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/EditSession.swift          (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/EditViews.swift            (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/ExpressionParser.swift     (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SPCKitHelpView.swift       (copied + renamed)
SPFSpectralAnalyzer/SPCKit/PointEditValidator.swift   (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SPCDocumentStore.swift     (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SPCFile.swift              (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SPCFileWriter.swift        (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SPCParser.swift            (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/SpectrumChartView.swift    (copied from SPCKit)
SPFSpectralAnalyzer/SPCKit/TransformEngine.swift      (copied from SPCKit)
SPFSpectralAnalyzer/Library/SPCLibraryBridge.swift    (new — write from scratch)
SPFSpectralAnalyzer/Library/SPCEditorSheet.swift      (new — write from scratch)
SPFSpectralAnalyzer/Library/SPCLibraryExportView.swift (new — write from scratch)
```

### Files to modify (existing — edit precisely)
```
SPFSpectralAnalyzer/SPC/CompoundFile.swift
SPFSpectralAnalyzer/SPC/SPCHeaderParser.swift
SPFSpectralAnalyzer/SPC/ShimadzuSPCParser.swift
SPFSpectralAnalyzer/SPC/GalacticSPCParser.swift
SPFSpectralAnalyzer/Core/Workers/SpectrumParsingWorker.swift
SPFSpectralAnalyzer/Core/Models/ImportModels.swift
SPFSpectralAnalyzer/Core/ViewModels/DatasetViewModel.swift
SPFSpectralAnalyzer/Core/Services/ValidationService.swift
SPFSpectralAnalyzer/ContentView+Utilities.swift
SPFSpectralAnalyzer/Storage/StoredDataset.swift
SPFSpectralAnalyzer/UI/Sidebar/SidebarViews.swift
SPFSpectralAnalyzer/ContentView.swift
```

---

## PHASE 1 — Resolve Name Collisions and Copy SPCKit Files

**Goal:** Copy the 12 SPCKit engine files into a new `SPCKit/` subfolder of the target.
Before copying, rename conflicting types in the existing SDA files so they coexist cleanly.

### Step 1.1 — Rename `CompoundFileError` and `CompoundFile` in SDA's CompoundFile.swift

In `SPFSpectralAnalyzer/SPC/CompoundFile.swift`, perform these renames throughout the
entire file (use replace-all):

| Old name | New name |
|---|---|
| `CompoundFileError` | `SDACompoundFileError` |
| `CompoundFileDirectoryEntry` | `SDACompoundFileDirectoryEntry` |
| `CompoundFile` | `SDACompoundFile` |

After renaming, `SDACompoundFile` must still compile (all internal references updated).
The class is `nonisolated final class SDACompoundFile`.

### Step 1.2 — Fix ShimadzuSPCParser.swift to use SDACompoundFile

In `SPFSpectralAnalyzer/SPC/ShimadzuSPCParser.swift`, find and replace:

```swift
// FIND:
private let compound: CompoundFile

// REPLACE WITH:
private let compound: SDACompoundFile
```

```swift
// FIND:
self.compound = try CompoundFile(fileURL: fileURL)

// REPLACE WITH:
self.compound = try SDACompoundFile(fileURL: fileURL)
```

Also find any `CompoundFileDirectoryEntry` usages in ShimadzuSPCParser.swift and rename
to `SDACompoundFileDirectoryEntry`.

### Step 1.3 — Rename `SPCMainHeader` → `SDAMainHeader` in SPCHeaderParser.swift

In `SPFSpectralAnalyzer/SPC/SPCHeaderParser.swift`, replace ALL occurrences of
`SPCMainHeader` with `SDAMainHeader` (there are exactly 3: the struct definition, the
return type annotation, and the return statement).

### Step 1.4 — Propagate `SDAMainHeader` rename to all callers

Perform replace-all for `SPCMainHeader` → `SDAMainHeader` in these files:

- `SPFSpectralAnalyzer/SPC/ShimadzuSPCParser.swift`
- `SPFSpectralAnalyzer/SPC/GalacticSPCParser.swift`
- `SPFSpectralAnalyzer/Core/ViewModels/DatasetViewModel.swift`
- `SPFSpectralAnalyzer/Core/Services/ValidationService.swift`
- `SPFSpectralAnalyzer/ContentView+Utilities.swift`

### Step 1.5 — Copy SPCKit engine files into SPCKit/ subfolder

Create the directory `SPFSpectralAnalyzer/SPCKit/` and copy the following files verbatim
(do not modify content during the copy):

```bash
cp ../../SPCKit/CompoundFileReader.swift  SPFSpectralAnalyzer/SPCKit/CompoundFileReader.swift
cp ../../SPCKit/EditSession.swift         SPFSpectralAnalyzer/SPCKit/EditSession.swift
cp ../../SPCKit/EditViews.swift           SPFSpectralAnalyzer/SPCKit/EditViews.swift
cp ../../SPCKit/ExpressionParser.swift    SPFSpectralAnalyzer/SPCKit/ExpressionParser.swift
cp ../../SPCKit/PointEditValidator.swift  SPFSpectralAnalyzer/SPCKit/PointEditValidator.swift
cp ../../SPCKit/SPCDocumentStore.swift    SPFSpectralAnalyzer/SPCKit/SPCDocumentStore.swift
cp ../../SPCKit/SPCFile.swift             SPFSpectralAnalyzer/SPCKit/SPCFile.swift
cp ../../SPCKit/SPCFileWriter.swift       SPFSpectralAnalyzer/SPCKit/SPCFileWriter.swift
cp ../../SPCKit/SPCParser.swift           SPFSpectralAnalyzer/SPCKit/SPCParser.swift
cp ../../SPCKit/SpectrumChartView.swift   SPFSpectralAnalyzer/SPCKit/SpectrumChartView.swift
cp ../../SPCKit/TransformEngine.swift     SPFSpectralAnalyzer/SPCKit/TransformEngine.swift
```

### Step 1.6 — Copy and rename HelpView to avoid collision with SDA's HelpView

Copy `../../SPCKit/HelpView.swift` to `SPFSpectralAnalyzer/SPCKit/SPCKitHelpView.swift`.

In the copied file, replace the struct name:
```swift
// FIND:
struct HelpView: View {

// REPLACE WITH:
struct SPCKitHelpView: View {
```

Also update the file header comment at the top from `// HelpView.swift` to
`// SPCKitHelpView.swift`.

### Step 1.7 — Add UTType extension for SPC files to SPCDocumentStore.swift

Verify that `SPFSpectralAnalyzer/SPCKit/SPCDocumentStore.swift` already contains:
```swift
nonisolated extension UTType {
    public static let spcFile = UTType(exportedAs: "com.thermogalactic.spc", conformingTo: .data)
}
```
If not, add it at the bottom of that file. This is needed for `.fileExporter` support.

### Step 1.8 — Add UTType to Info.plist

The app target's `Info.plist` (inside the `SPFSpectralAnalyzer` group) must declare the
`com.thermogalactic.spc` UTType. Find the Info.plist and add inside the top-level
`<dict>`:

```xml
<key>CFBundleDocumentTypes</key>
<array>
    <dict>
        <key>CFBundleTypeName</key>
        <string>SPC Spectral File</string>
        <key>CFBundleTypeExtensions</key>
        <array>
            <string>spc</string>
        </array>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>LSHandlerRank</key>
        <string>Owner</string>
    </dict>
</array>
<key>UTExportedTypeDeclarations</key>
<array>
    <dict>
        <key>UTTypeIdentifier</key>
        <string>com.thermogalactic.spc</string>
        <key>UTTypeDescription</key>
        <string>Thermo Galactic SPC Spectral File</string>
        <key>UTTypeConformsTo</key>
        <array>
            <string>public.data</string>
        </array>
        <key>UTTypeTagSpecification</key>
        <dict>
            <key>public.filename-extension</key>
            <array>
                <string>spc</string>
            </array>
        </dict>
    </dict>
</array>
```

### Step 1.9 — Phase 1 Build Verification

After all Phase 1 edits, verify the project builds without errors or Swift 6 strict
concurrency warnings. If there are residual `SPCMainHeader` or `CompoundFileError`
ambiguity errors, apply the appropriate rename to the remaining file and rebuild.

---

## PHASE 2 — Replace the Parser Stack with SPCParser

**Goal:** Route all SPC file imports through `SPCParser` (the SPCKit engine) instead of
the separate `GalacticSPCParser` / `ShimadzuSPCParser` dispatch. Add an adapter that
converts `SPCFile` → `ShimadzuSPCParseResult` so the existing downstream pipeline
(`DatasetPersistenceService`, `StoredDataset`) remains unchanged.

### Step 2.1 — Add SPCFile adapter to ImportModels.swift

At the bottom of `SPFSpectralAnalyzer/Core/Models/ImportModels.swift`, append the
following extension. Do not modify any existing code in that file:

```swift
// MARK: - SPCKit Adapter

/// Converts a fully-parsed SPCFile (SPCKit) into the ShimadzuSPCParseResult
/// format that SpectrumParsingWorker and DatasetPersistenceService expect.
/// This is the bridge between the new SPCKit engine and the existing pipeline.
enum SPCKitAdapter {

    /// Convert an SPCFile to a ShimadzuSPCParseResult.
    /// - Parameters:
    ///   - file: The parsed SPCFile from SPCKit.
    ///   - url: The source URL, used for naming subfiles.
    /// - Returns: A ShimadzuSPCParseResult compatible with the existing pipeline.
    nonisolated static func toParseResult(
        _ file: SPCFile,
        url: URL
    ) -> ShimadzuSPCParseResult {
        let ffp = file.header.firstX
        let flp = file.header.lastX
        let baseName = url.deletingPathExtension().lastPathComponent
        let subfileCount = file.subfiles.count

        let spectra: [ShimadzuSPCRawSpectrum] = file.subfiles.map { sub in
            let xDoubles = sub.resolvedXPoints(ffp: ffp, flp: flp).map { Double($0) }
            let yDoubles = sub.yPoints.map { Double($0) }
            let name: String
            if subfileCount == 1 {
                name = baseName
            } else {
                let label = file.header.memo.trimmingCharacters(in: .whitespaces)
                let sfName = label.isEmpty ? baseName : label
                name = "\(sfName)_\(sub.id + 1)"
            }
            return ShimadzuSPCRawSpectrum(name: name, x: xDoubles, y: yDoubles)
        }

        // Build a minimal SDAMainHeader from the SPCKit SPCMainHeader
        // so metadata display in the Analyzer is populated.
        let sdaHeader = SDAMainHeader(
            fileTypeFlags: file.header.flags.rawValue,
            spcVersion: file.header.version.rawValue,
            experimentTypeCode: file.header.experimentType,
            yExponent: Int8(bitPattern: file.header.yExponent),
            pointCount: Int32(file.header.pointCount),
            firstX: file.header.firstX,
            lastX: file.header.lastX,
            subfileCount: Int32(file.header.subfileCount),
            xUnitsCode: file.header.xUnitsCode,
            yUnitsCode: file.header.yUnitsCode,
            zUnitsCode: file.header.zUnitsCode,
            postingDisposition: 0,
            compressedDate: SDACompressedDate(rawValue: Int32(bitPattern: file.header.compressedDate)),
            resolutionText: file.header.resolutionDescription,
            sourceInstrumentText: file.header.sourceInstrument,
            peakPointNumber: file.header.peakPoint,
            memo: file.header.memo,
            customAxisCombined: file.header.customAxisLabels,
            customAxisX: "",
            customAxisY: "",
            customAxisZ: "",
            logBlockOffset: Int32(bitPattern: file.header.logOffset),
            fileModificationFlag: Int32(bitPattern: file.header.modificationFlag),
            processingCode: 0,
            calibrationLevelPlusOne: 0,
            subMethodInjectionNumber: 0,
            concentrationFactor: file.header.concentrationFactor,
            methodFile: file.header.methodFile,
            zSubfileIncrement: file.header.zIncrement,
            wPlaneCount: Int32(file.header.wPlaneCount),
            wPlaneIncrement: file.header.wIncrement,
            wAxisUnitsCode: file.header.wUnitsCode
        )

        let metadata = ShimadzuSPCMetadata(
            fileName: url.lastPathComponent,
            fileSizeBytes: 0,
            directoryEntryNames: [],
            dataSetNames: spectra.map(\.name),
            headerInfoByteCount: 512,
            mainHeader: sdaHeader
        )

        return ShimadzuSPCParseResult(
            spectra: spectra,
            skippedDataSets: [],
            metadata: metadata,
            headerInfoData: Data()
        )
    }
}
```

> **Note:** The `SDACompressedDate` type was renamed from `SPCCompressedDate` in Phase 1.
> If the project uses `SPCCompressedDate` still (because SPCHeaderParser.swift was the only
> place renamed), update the initializer call above to use whichever name exists in the
> compiled target.

### Step 2.2 — Update SpectrumParsingWorker to use SPCParser

In `SPFSpectralAnalyzer/Core/Workers/SpectrumParsingWorker.swift`, find the existing
`do { ... }` block inside the `for url in urls` loop that dispatches to
`GalacticSPCParser` or `ShimadzuSPCParser`. Replace that block entirely:

```swift
// FIND AND REPLACE the entire do-block beginning with:
//   let result: ShimadzuSPCParseResult
//   if let fileData = try? Data(contentsOf: url, options: .mappedIfSafe),
//      GalacticSPCParser.canParse(fileData) {

// REPLACE WITH:
do {
    let result: ShimadzuSPCParseResult
    // Phase 2: Use SPCKit's unified SPCParser for all SPC file formats.
    // SPCParser handles Galactic 0x4B, legacy LabCalc 0x4D, and Shimadzu OLE2/CFB
    // by detecting the format from magic bytes — no separate dispatch needed.
    let spcFile = try await SPCParser.parse(url: url)
    result = SPCKitAdapter.toParseResult(spcFile, url: url)

    let namedSpectra = result.spectra.enumerated().map { index, spectrum in
        let name = ContentView.sampleDisplayName(
            from: url,
            spectrumName: spectrum.name,
            index: index,
            total: result.spectra.count
        )
        return RawSpectrumInput(name: name, x: spectrum.x, y: spectrum.y, fileName: url.lastPathComponent)
    }

    fileRawSpectra = namedSpectra
    loaded.append(contentsOf: namedSpectra)
    if !result.skippedDataSets.isEmpty {
        filesWithSkipped += 1
        skippedTotal += result.skippedDataSets.count
        let warning = "skipped \(result.skippedDataSets.count)"
        fileWarnings.append(warning)
        warnings.append("\(url.lastPathComponent): \(warning)")
    }

    let fileData = try? Data(contentsOf: url)
    let parsedResult = ParsedFileResult(
        url: url,
        rawSpectra: fileRawSpectra,
        skippedDataSets: result.skippedDataSets,
        warnings: fileWarnings,
        metadata: result.metadata,
        headerInfoData: result.headerInfoData,
        fileData: fileData,
        metadataJSON: nil
    )
    parsedFiles.append(parsedResult)
    await MainActor.run {
        DatasetViewModel.validateSPCHeaderConsistency(for: parsedResult)
    }

    let duration = Date().timeIntervalSince(fileStart)
    let fileName = url.lastPathComponent
    let spectraCount = namedSpectra.count
    let skippedCount = result.skippedDataSets.count
    await MainActor.run {
        Instrumentation.log(
            "File parsed",
            area: .importParsing,
            level: .info,
            details: "file=\(fileName) spectra=\(spectraCount) skipped=\(skippedCount)",
            duration: duration
        )
    }
} catch {
    let duration = Date().timeIntervalSince(fileStart)
    let fileName = url.lastPathComponent
    let errorMessage = error.localizedDescription
    await MainActor.run {
        Instrumentation.log(
            "File parse failed",
            area: .importParsing,
            level: .warning,
            details: "file=\(fileName) error=\(errorMessage)",
            duration: duration
        )
    }
    failures.append("\(url.lastPathComponent): \(error)")
}
```

> The outer `for url in urls` loop structure, the `accessGranted` / `defer` security scope
> handling, and the `ParseBatchResult` return at the end remain unchanged.

### Step 2.3 — Phase 2 Build Verification

Build the project. The parse path now flows through `SPCParser`. Existing tests in
`BasicTests.swift` should still pass. Fix any remaining type-name issues before continuing.

---

## PHASE 3 — Library Editor (Three New Files + Sidebar Wiring)

**Goal:** Add a full-featured SPC editor accessible from the Library sidebar context menu.
Users can open any SPC dataset in the editor, apply transforms, undo/redo, and save as
either Galactic or Shimadzu format.

### Step 3.1 — Create SPCLibraryBridge.swift

Create `SPFSpectralAnalyzer/Library/SPCLibraryBridge.swift` with the complete content:

```swift
// SPCLibraryBridge.swift
// SPFSpectralAnalyzer
//
// @MainActor bridge between the Library's DatasetViewModel and SPCKit's
// SPCDocumentStore. One SPCDocumentStore per open editor session.
// All editor actions route through this bridge.

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - SPCLibraryBridge

@MainActor
@Observable
final class SPCLibraryBridge {

    // MARK: - Public state

    /// The active SPCDocumentStore for the currently open editor session.
    /// Nil when no editor is open.
    private(set) var activeStore: SPCDocumentStore?

    /// The StoredDataset that is currently being edited.
    private(set) var editingDataset: StoredDataset?

    /// True while the SPC editor sheet is presented.
    var isEditorPresented: Bool = false

    /// True while a combine operation is running.
    var isCombining: Bool = false

    /// Error to present in an alert.
    var presentedError: String?

    // MARK: - Open for editing

    /// Open a StoredDataset's raw SPC bytes in the full SPCKit editor.
    /// The dataset must have non-nil `fileData` containing valid SPC bytes.
    /// If the dataset has no fileData, an error is shown.
    func openForEditing(_ dataset: StoredDataset) async {
        guard let data = dataset.fileData else {
            presentedError = "No file data available for \(dataset.fileName)."
            return
        }
        do {
            let spcFile = try SPCParser.parse(data: data)
            let store = SPCDocumentStore()
            store.loadParsed(spcFile)
            store.documentName = dataset.fileName
                .replacingOccurrences(of: ".spc", with: "", options: .caseInsensitive)
            activeStore = store
            editingDataset = dataset
            isEditorPresented = true
        } catch {
            presentedError = "Cannot open \(dataset.fileName): \(error.localizedDescription)"
        }
    }

    // MARK: - Combine multiple datasets into one SPC file

    /// Create a new SPC file by merging subfiles from multiple StoredDatasets.
    /// Each dataset contributes its subfiles (materialized X arrays for Y-only files).
    /// The resulting SPCDocumentStore is opened in the editor.
    func combineDatasets(_ datasets: [StoredDataset]) async {
        guard datasets.count >= 2 else {
            presentedError = "Select at least 2 datasets to combine."
            return
        }
        isCombining = true
        defer { isCombining = false }

        // Parse the first dataset as the base document
        guard let firstData = datasets.first?.fileData else {
            presentedError = "First dataset has no file data."
            return
        }
        do {
            let baseFile = try SPCParser.parse(data: firstData)
            let store = SPCDocumentStore()
            store.loadParsed(baseFile)
            store.documentName = "Combined"

            // Import subfiles from the remaining datasets
            for dataset in datasets.dropFirst() {
                guard let data = dataset.fileData else { continue }
                guard let url = dataset.sourcePath.map({ URL(fileURLWithPath: $0) }) else {
                    // Write to a temp file so importSubfiles(from:) can load it
                    let tempURL = FileManager.default.temporaryDirectory
                        .appendingPathComponent(dataset.fileName)
                    try data.write(to: tempURL)
                    await store.importSubfiles(from: tempURL)
                    try? FileManager.default.removeItem(at: tempURL)
                    continue
                }
                await store.importSubfiles(from: url)
            }

            activeStore = store
            editingDataset = nil      // No single source dataset for combined files
            isEditorPresented = true
        } catch {
            presentedError = "Combine failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Save As (called by SPCEditorSheet after fileExporter completes)

    /// Persist the saved SPC file as a new StoredDataset in SwiftData.
    /// The original dataset is preserved; the edited version becomes a new entry.
    func handleSaveAs(
        data: Data,
        format: SPCExportFormat,
        suggestedName: String,
        modelContext: ModelContext
    ) {
        let newDataset = StoredDataset()
        newDataset.fileName = suggestedName
        newDataset.fileData = data
        newDataset.spcKitEdited = true
        newDataset.spcFileFormat = format.rawValue
        modelContext.insert(newDataset)
        do {
            try modelContext.save()
        } catch {
            presentedError = "Failed to save dataset: \(error.localizedDescription)"
        }
    }

    // MARK: - Dismiss editor

    func dismissEditor() {
        isEditorPresented = false
        activeStore = nil
        editingDataset = nil
    }

    // MARK: - Helpers

    /// Returns true if the given StoredDataset has SPC file bytes that can be opened.
    static func canOpen(_ dataset: StoredDataset) -> Bool {
        guard let data = dataset.fileData, data.count >= 256 else { return false }
        // Galactic SPC: version byte at offset 1 is 0x4B or 0x4D
        // Shimadzu OLE2: magic bytes at 0-7 are D0 CF 11 E0 A1 B1 1A E1
        let versionByte = data[1]
        if versionByte == 0x4B || versionByte == 0x4D { return true }
        if data.count >= 8 {
            let magic: [UInt8] = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1]
            return zip(magic, data.prefix(8)).allSatisfy { $0 == $1 }
        }
        return false
    }
}
```

### Step 3.2 — Create SPCEditorSheet.swift

Create `SPFSpectralAnalyzer/Library/SPCEditorSheet.swift` with the complete content:

```swift
// SPCEditorSheet.swift
// SPFSpectralAnalyzer
//
// Full-featured SPC editor presented as a sheet from the Library.
// Wraps SPCKit's SPCDocumentStore + views inside a NavigationSplitView.
// Supports Undo/Redo, Transform, and Save As (Galactic or Shimadzu CFB).

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

// MARK: - SPCEditorSheet

struct SPCEditorSheet: View {

    @Bindable var bridge: SPCLibraryBridge
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let store = bridge.activeStore {
                editorContent(store: store)
            } else {
                loadingView
            }
        }
        // Format picker sheet (shown before fileExporter)
        .sheet(isPresented: Binding(
            get: { bridge.activeStore?.showExportFormatPicker ?? false },
            set: { bridge.activeStore?.showExportFormatPicker = $0 }
        )) {
            if let store = bridge.activeStore {
                SPCLibraryExportView(store: store)
            }
        }
        // Transform panel sheet
        .sheet(isPresented: Binding(
            get: { bridge.activeStore?.showTransformPanel ?? false },
            set: { bridge.activeStore?.showTransformPanel = $0 }
        )) {
            if let store = bridge.activeStore {
                TransformPanel(store: store)
                    .presentationDetents([.medium, .large])
            }
        }
        // fileExporter for Save As
        .fileExporter(
            isPresented: Binding(
                get: { bridge.activeStore?.isExporting ?? false },
                set: { bridge.activeStore?.isExporting = $0 }
            ),
            document: bridge.activeStore?.exportDocument,
            contentType: .spcFile,
            defaultFilename: bridge.activeStore?.exportFilename ?? "spectrum.spc"
        ) { result in
            handleExportResult(result)
        }
        // Error alert from bridge
        .alert("Error", isPresented: Binding(
            get: { bridge.presentedError != nil },
            set: { if !$0 { bridge.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { bridge.presentedError = nil }
        } message: {
            Text(bridge.presentedError ?? "")
        }
        // Error alert from store
        .alert("Error", isPresented: Binding(
            get: { bridge.activeStore?.presentedError != nil },
            set: { if !$0 { bridge.activeStore?.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { bridge.activeStore?.presentedError = nil }
        } message: {
            Text(bridge.activeStore?.presentedError?.message ?? "")
        }
    }

    // MARK: - Editor content

    @ViewBuilder
    private func editorContent(store: SPCDocumentStore) -> some View {
        NavigationSplitView {
            // Sidebar: subfile tree
            SubfileTreeView(store: store)
                .navigationTitle(bridge.editingDataset?.fileName ?? "SPC Editor")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
        } detail: {
            // Detail: spectrum chart
            SpectrumChartView(store: store)
        }
        .toolbar {
            // Leading: close
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    bridge.dismissEditor()
                    dismiss()
                }
            }

            // Undo
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.undo() }
                } label: {
                    Label("Undo", systemImage: "arrow.uturn.backward")
                }
                .disabled(!store.canUndo)
                .keyboardShortcut("z", modifiers: .command)
            }

            // Redo
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.redo() }
                } label: {
                    Label("Redo", systemImage: "arrow.uturn.forward")
                }
                .disabled(!store.canRedo)
                .keyboardShortcut("z", modifiers: [.command, .shift])
            }

            // Transform
            ToolbarItem(placement: .automatic) {
                Button {
                    store.showTransformPanel = true
                } label: {
                    Label("Transform", systemImage: "function")
                }
                .disabled(store.isTransforming)
            }

            // Save As
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.requestExport() }
                } label: {
                    Label("Save As…", systemImage: "square.and.arrow.down")
                }
                .disabled(store.resolvedSubfiles.isEmpty)
            }
        }
    }

    // MARK: - Loading placeholder

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Opening SPC file…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Export result handler

    private func handleExportResult(_ result: Result<URL, Error>) {
        guard let store = bridge.activeStore else { return }
        switch result {
        case .success(let url):
            // Read the saved file data and add as a new StoredDataset
            if let data = try? Data(contentsOf: url) {
                bridge.handleSaveAs(
                    data: data,
                    format: store.selectedExportFormat,
                    suggestedName: url.lastPathComponent,
                    modelContext: modelContext
                )
            }
            // Optionally reload in the store (to refresh audit log etc.)
            Task { await store.handleExportResult(.success(url)) }

        case .failure(let error):
            bridge.presentedError = "Save failed: \(error.localizedDescription)"
        }
    }
}
```

### Step 3.3 — Create SPCLibraryExportView.swift

Create `SPFSpectralAnalyzer/Library/SPCLibraryExportView.swift` with the complete content:

```swift
// SPCLibraryExportView.swift
// SPFSpectralAnalyzer
//
// Format picker shown before the fileExporter Save As sheet.
// Lets the user choose between Thermo Galactic binary and Shimadzu OLE2/CFB.

import SwiftUI

struct SPCLibraryExportView: View {

    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(SPCExportFormat.allCases) { format in
                        Button {
                            store.selectedExportFormat = format
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(format.rawValue)
                                        .foregroundStyle(.primary)
                                    Text(format == .thermoGalactic
                                         ? "Standard binary SPC (0x4B header). Compatible with GRAMS and most instruments."
                                         : "OLE2 Compound Binary. Required for Shimadzu software compatibility.")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedExportFormat == format {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.accent)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("Output Format")
                } footer: {
                    Text("The edited file will be saved as a new dataset in your Library. The original is preserved.")
                }
            }
            .navigationTitle("Save As SPC")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Save") {
                        store.showExportFormatPicker = false
                        Task { await store.prepareExport() }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
```

### Step 3.4 — Add SPCLibraryBridge to ContentView

In `SPFSpectralAnalyzer/ContentView.swift`, add the bridge as a `@State` property.
Find the `struct ContentView: View {` declaration block and the existing `@State` property
list. Add after the last `@State var` line near the top of the struct (before `var body`):

```swift
// FIND (the last @State property before body, likely around line 80-85 area):
    @AppStorage("aiProviderPreference") var aiProviderPreferenceRawValue = AIProviderPreference.auto.rawValue

// ADD THIS LINE AFTER IT:
    @State var spcLibraryBridge = SPCLibraryBridge()
```

Then find the main `body: some View` return and locate the outermost `Group` or
`NavigationSplitView`. Add the editor sheet modifier at the end of the view chain
(before the final closing brace of `body`):

```swift
// At the bottom of the var body, before the final closing brace, add:
        .sheet(isPresented: $spcLibraryBridge.isEditorPresented) {
            SPCEditorSheet(bridge: spcLibraryBridge)
                .environment(\.modelContext, modelContext)
        }
        .alert("SPC Error", isPresented: Binding(
            get: { spcLibraryBridge.presentedError != nil },
            set: { if !$0 { spcLibraryBridge.presentedError = nil } }
        )) {
            Button("OK", role: .cancel) { spcLibraryBridge.presentedError = nil }
        } message: {
            Text(spcLibraryBridge.presentedError ?? "")
        }
```

> If ContentView already has a long chain of `.sheet` modifiers, add these new ones
> at the end of that chain.

### Step 3.5 — Add Context Menu to Library Sidebar

In `SPFSpectralAnalyzer/UI/Sidebar/SidebarViews.swift`, find `spectrumRowMenuContent`
(the function that populates the `Menu` for each row). If this function does not exist,
find the `spectrumRow` or the `Menu { }` block inside `spectrumRowContent`.

Add the following menu items at the **top** of the menu content (before any existing
Delete / Remove items), inside the `Menu { }` label content function:

```swift
// ADD THESE ITEMS AT THE TOP OF spectrumRowMenuContent (or the nearest Menu label block):
// Note: 'datasets' here refers to the array of StoredDataset objects the sidebar has access to.
// You need to pass 'spcLibraryBridge' down to this view or use environment.
// The simplest approach: make these items conditional on the parent ContentView's bridge.

Button {
    Task {
        await spcLibraryBridge.openForEditing(/* the StoredDataset for this row */)
    }
} label: {
    Label("Open in SPC Editor…", systemImage: "waveform.and.magnifyingglass")
}
```

> **Implementation note:** The SidebarViews.swift is an extension on ContentView.
> The bridge property `spcLibraryBridge` declared in Step 3.4 is available directly
> since these are ContentView extensions. Find the `StoredDataset` for the sidebar row
> by looking at how the row's `dataset` is identified — it may be a `StoredDataset`
> reference in the closure or accessible via `datasets.first(where: { ... })`.
>
> Look at how `spectrumRowMenuContent` receives its index or dataset reference.
> The menu is generated per-dataset; thread the dataset reference through to the
> `openForEditing` call.

Add a second button for multi-dataset combine (shown when 2+ datasets are selected):

```swift
if datasets.filter({ selectedStoredDatasetIDs.contains($0.id) }).count >= 2 {
    Divider()
    Button {
        let selected = datasets.filter { selectedStoredDatasetIDs.contains($0.id) }
        Task { await spcLibraryBridge.combineDatasets(selected) }
    } label: {
        Label("Combine Selected into SPC…", systemImage: "arrow.triangle.merge")
    }
}
```

### Step 3.6 — Phase 3 Build Verification

Build the project. Confirm:
1. No ambiguous type errors
2. The `SPCEditorSheet` and `SPCLibraryBridge` compile without warnings
3. The `TransformPanel` from `EditViews.swift` is accessible (it's in the same target)
4. The `SpectrumChartView` from `SPCKit/SpectrumChartView.swift` compiles without conflict
   with the SDA chart views (they are different types)

---

## PHASE 4 — StoredDataset Fields, Combine, and Export Enhancements

**Goal:** Add audit-trail fields to `StoredDataset`, wire the export handler back into
the Library dataset list, and add the iOS Data Management tab SPC editor entry point.

### Step 4.1 — Add spcKitEdited and spcFileFormat to StoredDataset

In `SPFSpectralAnalyzer/Storage/StoredDataset.swift`, find the existing property block
(after `formulationType` and before any computed properties / methods). Add these two
new stored properties:

```swift
// ADD after the existing 'formulationType: String?' property:

    /// True when this dataset was saved from the SPCKit editor rather than imported directly.
    var spcKitEdited: Bool = false

    /// The output format used when saving via SPCKit ("Thermo Galactic SPC" or "Shimadzu (OLE2/CFB)").
    /// Only set when spcKitEdited is true.
    var spcFileFormat: String?
```

### Step 4.2 — Add sourcePath property if not present

The `SPCLibraryBridge.combineDatasets` uses `dataset.sourcePath`. Verify that
`StoredDataset` already has `var sourcePath: String?`. If it does not, add:

```swift
    var sourcePath: String?
```

(It likely already exists from the existing `DatasetPersistenceService`.)

### Step 4.3 — Update iOSDataManagementView to show SPC editor entry point

In `SPFSpectralAnalyzer/UI/Panels/iOS/iOSDataManagementView.swift`, find the dataset
list row or context menu. Add the "Open in SPC Editor…" menu item wherever the iOS
dataset action menu is shown, following the same pattern as Step 3.5.

If `iOSDataManagementView` is an extension of `ContentView`, the `spcLibraryBridge`
property from Step 3.4 is already accessible.

### Step 4.4 — Instrument Library badge for edited datasets

In `SPFSpectralAnalyzer/UI/Sidebar/SidebarViews.swift` (or wherever the Library
sidebar row is rendered), find where dataset tags/badges are shown. Add a visual
indicator for SPCKit-edited datasets:

```swift
// After (or near) where hdrsTag or other tags are shown for a StoredDataset:
if let dataset = /* the StoredDataset for this row */,
   dataset.spcKitEdited {
    Text("SPC✏")
        .font(.system(size: 7, weight: .bold, design: .rounded))
        .padding(.horizontal, 3)
        .padding(.vertical, 1)
        .background(Color.blue.opacity(0.15))
        .foregroundColor(.blue)
        .cornerRadius(2)
}
```

### Step 4.5 — Phase 4 Build Verification

Build the project for both macOS and iOS targets. Confirm:
1. `StoredDataset` compiles with the two new properties (SwiftData handles new optionals
   automatically — no migration script needed for CloudKit-compatible optionals)
2. `SPCLibraryBridge.handleSaveAs` can set `newDataset.spcKitEdited = true` without error
3. The iOS data management view shows the SPC editor entry point

---

## NEW TESTS TO ADD

### Unit Test: SPCParser integration

In `SPFSpectralAnalyzer/SPFSpectralAnalyzerTests/BasicTests.swift`, add:

```swift
// MARK: - SPCKit Parser Integration Tests

func testSPCParserParsesGalacticFile() throws {
    // Use any .spc fixture file in the test bundle, or create synthetic data.
    // Minimal valid new-format SPC: 512-byte header with version 0x4B.
    var headerBytes = [UInt8](repeating: 0, count: 512)
    headerBytes[0] = 0x00  // flags: Y-only, 32-bit
    headerBytes[1] = 0x4B  // new format
    headerBytes[3] = 0x80  // yExponent: IEEE float
    // pointCount = 4 at bytes 4-7 (little-endian)
    headerBytes[4] = 4; headerBytes[5] = 0; headerBytes[6] = 0; headerBytes[7] = 0
    // firstX = 400.0 as Double at bytes 8-15
    let firstXBits = 400.0.bitPattern.littleEndian
    withUnsafeBytes(of: firstXBits) { bytes in
        for (i, b) in bytes.enumerated() { headerBytes[8 + i] = b }
    }
    // lastX = 700.0 as Double at bytes 16-23
    let lastXBits = 700.0.bitPattern.littleEndian
    withUnsafeBytes(of: lastXBits) { bytes in
        for (i, b) in bytes.enumerated() { headerBytes[16 + i] = b }
    }
    // subfileCount = 1 at bytes 24-27
    headerBytes[24] = 1

    // One subfile header (32 bytes) + 4 IEEE floats for Y data
    var subfileBytes = [UInt8](repeating: 0, count: 32)
    subfileBytes[1] = 0x80  // yExponent: IEEE float

    let yValues: [Float] = [1.0, 2.0, 3.0, 4.0]
    var yBytes = [UInt8](repeating: 0, count: 16)
    for (i, v) in yValues.enumerated() {
        let bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: bits) { bytes in
            for (j, b) in bytes.enumerated() { yBytes[i * 4 + j] = b }
        }
    }

    let data = Data(headerBytes + subfileBytes + yBytes)
    let file = try SPCParser.parse(data: data)

    XCTAssertEqual(file.subfiles.count, 1)
    XCTAssertEqual(file.subfiles[0].yPoints, yValues, accuracy: 1e-6)
    XCTAssertEqual(file.header.firstX, 400.0, accuracy: 1e-6)
    XCTAssertEqual(file.header.lastX, 700.0, accuracy: 1e-6)
}

func testSPCKitAdapterConvertsToParseResult() throws {
    // Build a minimal SPCFile and verify the adapter produces valid ShimadzuSPCParseResult
    var headerBytes = [UInt8](repeating: 0, count: 512)
    headerBytes[1] = 0x4B
    headerBytes[3] = 0x80
    headerBytes[4] = 2   // 2 points
    let firstX = 300.0.bitPattern.littleEndian
    withUnsafeBytes(of: firstX) { bytes in headerBytes[8..<16] = ArraySlice(bytes) }
    let lastX = 400.0.bitPattern.littleEndian
    withUnsafeBytes(of: lastX) { bytes in headerBytes[16..<24] = ArraySlice(bytes) }
    headerBytes[24] = 1

    var subBytes = [UInt8](repeating: 0, count: 32)
    subBytes[1] = 0x80
    let yVals: [Float] = [0.5, 0.9]
    var yBytes = [UInt8](repeating: 0, count: 8)
    for (i, v) in yVals.enumerated() {
        let bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: bits) { bytes in
            for (j, b) in bytes.enumerated() { yBytes[i * 4 + j] = b }
        }
    }

    let data = Data(headerBytes + subBytes + yBytes)
    let file = try SPCParser.parse(data: data)
    let url = URL(fileURLWithPath: "/tmp/test.spc")
    let result = SPCKitAdapter.toParseResult(file, url: url)

    XCTAssertFalse(result.spectra.isEmpty)
    XCTAssertEqual(result.spectra[0].x.count, 2)
    XCTAssertEqual(result.spectra[0].y[0], Double(yVals[0]), accuracy: 1e-5)
}

func testRoundTrip_parseEditWrite() async throws {
    // Build minimal SPC → parse → scale Y by 2 → write → re-parse → verify
    var headerBytes = [UInt8](repeating: 0, count: 512)
    headerBytes[1] = 0x4B; headerBytes[3] = 0x80
    headerBytes[4] = 3   // 3 points
    let fx = 200.0.bitPattern.littleEndian
    let lx = 400.0.bitPattern.littleEndian
    withUnsafeBytes(of: fx) { bytes in headerBytes[8..<16] = ArraySlice(bytes) }
    withUnsafeBytes(of: lx) { bytes in headerBytes[16..<24] = ArraySlice(bytes) }
    headerBytes[24] = 1
    var subBytes = [UInt8](repeating: 0, count: 32); subBytes[1] = 0x80
    let yIn: [Float] = [1.0, 2.0, 3.0]
    var yBytes = [UInt8](repeating: 0, count: 12)
    for (i, v) in yIn.enumerated() {
        let bits = v.bitPattern.littleEndian
        withUnsafeBytes(of: bits) { bytes in
            for (j, b) in bytes.enumerated() { yBytes[i * 4 + j] = b }
        }
    }
    let data = Data(headerBytes + subBytes + yBytes)
    let file = try SPCParser.parse(data: data)

    let store = await SPCDocumentStore()
    await MainActor.run { store.loadParsed(file) }
    await store.apply(.scaleY(subfileIndices: [0], factor: 2.0))

    let outData = try await SPCFileWriter.writeToData(session: store.editSession!)
    let outFile = try SPCParser.parse(data: outData)

    XCTAssertEqual(outFile.subfiles[0].yPoints.count, 3)
    XCTAssertEqual(outFile.subfiles[0].yPoints[0], 2.0, accuracy: 1e-4)
    XCTAssertEqual(outFile.subfiles[0].yPoints[1], 4.0, accuracy: 1e-4)
    XCTAssertEqual(outFile.subfiles[0].yPoints[2], 6.0, accuracy: 1e-4)
}
```

---

## IMPLEMENTATION RULES FOR THE AGENT

These rules apply throughout all phases:

1. **Read before writing.** Before modifying any existing file, read its current content
   to understand the exact structure. Do not assume structure from this CLAUDE.md alone.

2. **Swift 6 strict concurrency.** Every new type must be either:
   - A `nonisolated` value type with `Sendable` conformance, OR
   - `@MainActor`-isolated, OR
   - An `actor`
   No `@unchecked Sendable`. No `DispatchQueue`. No completion handlers.

3. **Zero external dependencies.** Import only: `SwiftUI`, `SwiftData`, `Foundation`,
   `Charts`, `Accelerate`, `UniformTypeIdentifiers`, `Observation`, `os`. No SPM packages.

4. **Build verification after each phase.** After completing each numbered phase, confirm
   the project builds without errors before starting the next phase.

5. **Do not modify SPCKit source files.** The files in `SPFSpectralAnalyzer/SPCKit/`
   are copied verbatim from the sibling SPCKit project and should not be edited. All
   integration code goes in `SPFSpectralAnalyzer/Library/` or in the existing modified files.

6. **Preserve CloudKit compatibility.** All new `StoredDataset` properties must be
   optional (`Bool = false`, `String?`) so CloudKit does not require a schema migration.

7. **Apple UI/UX Design guidelines.** All new SwiftUI views must follow Apple HIG.
   Use system-provided components: `NavigationSplitView`, `.sheet`, `.fileExporter`,
   `Label`, system SF Symbols. Favor Liquid Glass aesthetic where available in iOS 26.4.

8. **No AppKit or UIKit direct calls.** Use SwiftUI cross-platform APIs only.
   Use `.fileExporter` not `NSSavePanel`. Use `.sheet` not `UIAlertController`.

9. **Phase gate: name collision check.** After Phase 1 and before Phase 2, search the
   target for duplicate type names: `SPCMainHeader`, `CompoundFileError`, `HelpView`.
   Zero duplicates must remain before proceeding.

10. **Instrumentation.** In `SpectrumParsingWorker.swift`, preserve the existing
    `Instrumentation.log(...)` call pattern. The new SPCParser-based path must still
    log parse success and failure with the same fields.

---

## COMPLETION CHECKLIST

After all four phases and tests are implemented, verify every item:

- [ ] `SPFSpectralAnalyzer/SPCKit/` directory contains 12 `.swift` files
- [ ] `SPFSpectralAnalyzer/Library/` directory contains 3 `.swift` files
- [ ] Zero `SPCMainHeader` occurrences in SDA's original files (all renamed `SDAMainHeader`)
- [ ] Zero `CompoundFileError` occurrences in SDA's original files (all renamed `SDACompoundFileError`)
- [ ] Zero ambiguous `HelpView` — SDA uses `HelpView`, SPCKit uses `SPCKitHelpView`
- [ ] `SpectrumParsingWorker` calls `await SPCParser.parse(url:)` (not `GalacticSPCParser`)
- [ ] `SPCLibraryBridge` declared as `@State` in `ContentView`
- [ ] `.sheet(isPresented: $spcLibraryBridge.isEditorPresented)` wired in `ContentView.body`
- [ ] Library sidebar row has "Open in SPC Editor…" menu item
- [ ] `StoredDataset` has `spcKitEdited: Bool = false` and `spcFileFormat: String?`
- [ ] Info.plist declares `com.thermogalactic.spc` UTType
- [ ] Project builds for macOS with zero errors, zero Swift 6 warnings
- [ ] Project builds for iOS with zero errors, zero Swift 6 warnings
- [ ] Three new unit tests pass in SPFSpectralAnalyzerTests
