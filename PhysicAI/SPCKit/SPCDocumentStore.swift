// SPCDocumentStore.swift
// SPCKit
//
// The @MainActor-isolated Observable that all SwiftUI views bind to.
// Owns one EditSession per open document. Bridges async actor calls
// onto the main actor cleanly using Swift structured concurrency.
//
// All user actions flow through here so the UI always reflects the
// current resolved state without manual refresh triggers.

import SwiftUI
import Observation

// MARK: - SPCDocumentStore

@MainActor
@Observable
public final class SPCDocumentStore {

    // MARK: Published state

    /// The fully parsed source file. Set once on load; never mutated.
    public private(set) var sourceFile: SPCFile?

    /// Selected subfile indices in the SubfileTreeView.
    public var selectedSubfileIndices: Set<Int> = []

    /// The single subfile index shown in the XYDataTableView (detail focus).
    public var focusedSubfileIndex: Int = 0

    /// Resolved subfile snapshots for the chart and table views.
    /// Refreshed after every edit by calling refreshResolvedState().
    public private(set) var resolvedSubfiles: [Subfile] = []

    /// Resolved axis metadata.
    public private(set) var resolvedAxisMetadata: AxisMetadata?

    /// Resolved memo string.
    public private(set) var resolvedMemo: String = ""

    /// Resolved audit log entries.
    public private(set) var resolvedAuditLog: [AuditLogEntry] = []

    /// Resolved header (with all pending metadata edits).
    public private(set) var resolvedHeader: SPCMainHeader?

    /// Custom display names for subfiles (index → name).
    public private(set) var resolvedSubfileNames: [Int: String] = [:]

    /// Whether any unsaved edits exist.
    public private(set) var isDirty: Bool = false

    /// Subfile indices that have pending deltas (shown with a badge in the tree).
    public private(set) var dirtySubfileIndices: Set<Int> = []

    /// Error presented to the user via an alert.
    public var presentedError: IdentifiableError?

    /// Whether undo is available.
    public private(set) var canUndo: Bool = false

    /// Whether redo is available.
    public private(set) var canRedo: Bool = false

    /// True while an async transform is running (disables UI controls).
    public private(set) var isTransforming: Bool = false

    // MARK: Private state

    private var editSession: EditSession?

    // MARK: - Loading

    /// Load an SPC file from disk. Replaces any existing session.
    public func load(from url: URL) async {
        do {
            let parsed = try await SPCParser.parse(url: url)
            loadParsed(parsed)
            await refreshResolvedState()
        } catch {
            presentedError = IdentifiableError(error)
        }
    }

    /// Load from an already-parsed SPCFile (used by DocumentGroup).
    public func loadParsed(_ file: SPCFile) {
        self.sourceFile  = file
        self.editSession = EditSession(source: file)
    }

    // MARK: - Applying edits

    /// Apply any EditAction. Called by transform panels and the data table.
    public func apply(_ action: EditAction) async {
        guard let session = editSession else { return }
        isTransforming = true
        await Task.yield()   // forces a RunLoop tick; SwiftUI renders spinner here
        do {
            try await session.apply(action)
            await refreshResolvedState()
        } catch {
            presentedError = IdentifiableError(error)
        }
        isTransforming = false
    }

    /// Apply multiple EditActions as a single batch (one refreshResolvedState at the end).
    public func applyBatch(_ actions: [EditAction]) async {
        guard !actions.isEmpty, let session = editSession else { return }
        isTransforming = true
        await Task.yield()
        do {
            for action in actions {
                try await session.apply(action)
            }
            await refreshResolvedState()
        } catch {
            presentedError = IdentifiableError(error)
        }
        isTransforming = false
    }

    // MARK: - Undo / Redo

    public func undo() async {
        guard let session = editSession else { return }
        isTransforming = true
        await Task.yield()
        do {
            try await session.undo()
            await refreshResolvedState()
        } catch {
            presentedError = IdentifiableError(error)
        }
        isTransforming = false
    }

    public func redo() async {
        guard let session = editSession else { return }
        isTransforming = true
        await Task.yield()
        do {
            try await session.redo()
            await refreshResolvedState()
        } catch {
            presentedError = IdentifiableError(error)
        }
        isTransforming = false
    }

    // MARK: - Export (Save As)

    /// Triggers the `.fileExporter` presentation in the view layer.
    public var isExporting: Bool = false

    /// Whether the format-picker confirmation dialog is showing.
    public var showExportFormatPicker: Bool = false

    /// The selected output format for Save As.
    public var selectedExportFormat: SPCExportFormat = .thermoGalactic

    /// The document snapshot prepared for export. Set before `isExporting`.
    private(set) var exportDocument: SPCExportDocument?

    /// Suggested filename for the export panel.
    public private(set) var exportFilename: String = "spectrum_edited.spc"

    /// The document's current name from the tab/title bar. Set by ContentView.
    public var documentName: String?

    /// Shows the format picker before exporting.
    public func requestExport() {
        showExportFormatPicker = true
    }

    /// Prepares export data using the selected format, then presents `.fileExporter`.
    public func prepareExport() async {
        guard let session = editSession else { return }
        do {
            let data: Data
            switch selectedExportFormat {
            case .thermoGalactic:
                data = try await SPCFileWriter.writeToData(session: session)
            case .shimadzuCFB:
                data = try await SPCFileWriter.writeToShimadzuData(session: session)
            }
            exportDocument = SPCExportDocument(data: data)
            exportFilename = suggestedSaveAsName(for: sourceFile)
            isExporting = true
        } catch {
            presentedError = IdentifiableError(error)
        }
    }

    /// Called from `.fileExporter` onCompletion to reload the saved file.
    public func handleExportResult(_ result: Result<URL, any Error>) async {
        exportDocument = nil
        switch result {
        case .success(let url):
            // Preserve custom subfile names across reload
            let savedNames = resolvedSubfileNames
            await load(from: url)
            // Re-apply names that still map to valid subfile indices
            for (index, name) in savedNames {
                if index < resolvedSubfiles.count {
                    await apply(.renameSubfile(subfileIndex: index, newName: name))
                }
            }
        case .failure(let error):
            presentedError = IdentifiableError(error)
        }
    }

    // MARK: - Metadata editing

    /// Whether the transform panel sheet is shown.
    public var showTransformPanel: Bool = false

    /// Whether the metadata editor sheet is shown.
    public var showMetadataEditor: Bool = false

    /// Whether the subfile manager sheet is shown.
    public var showSubfileManager: Bool = false

    /// Whether the diff panel sheet is shown.
    public var showDiffPanel: Bool = false

    /// Whether the inspector is shown (sidebar column on iPad/Mac).
    public var showInspector: Bool = false

    /// Whether the inspector is shown as a sheet (compact/iPhone layout).
    public var showInspectorSheet: Bool = false

    /// Import subfiles from an external SPC file URL.
    /// Materializes X arrays for Y-only subfiles so they're self-contained.
    /// Auto-names each imported subfile using the source filename.
    public func importSubfiles(from url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let importedFile = try SPCParser.parse(data: try Data(contentsOf: url))
            guard !importedFile.subfiles.isEmpty else { return }
            let ffp = importedFile.header.firstX
            let flp = importedFile.header.lastX
            let materialized = importedFile.subfiles.map { sub in
                if sub.xPoints != nil { return sub }
                let xArray = sub.resolvedXPoints(ffp: ffp, flp: flp)
                return Subfile(
                    id: sub.id,
                    subheader: sub.subheader,
                    xPoints: xArray,
                    yPoints: sub.yPoints
                )
            }

            // Record the current count so we know the indices of newly added subfiles
            let countBefore = resolvedSubfiles.count
            await apply(.addSubfiles(subfiles: materialized))

            // Auto-name each imported subfile from the source filename
            let baseName = url.deletingPathExtension().lastPathComponent
            for i in 0 ..< materialized.count {
                let targetIndex = countBefore + i
                let name = materialized.count == 1
                    ? baseName
                    : "\(baseName) [\(i)]"
                await apply(.renameSubfile(subfileIndex: targetIndex, newName: name))
            }
        } catch {
            presentedError = IdentifiableError(error)
        }
    }

    /// Remove subfiles at the given indices.
    public func removeSubfiles(at indices: Set<Int>) async {
        guard !indices.isEmpty else { return }
        await apply(.removeSubfiles(indices: indices.sorted()))
    }

    /// Move subfiles in the list (for drag-and-drop reorder).
    public func moveSubfiles(from source: IndexSet, to destination: Int) async {
        let count = resolvedSubfiles.count
        var order = Array(0..<count)
        order.move(fromOffsets: source, toOffset: destination)
        await apply(.reorderSubfiles(newOrder: order))
    }

    // MARK: - Convenience apply helpers (for toolbar and menu)

    public func scaleSelectedY(factor: Double) async {
        guard !selectedSubfileIndices.isEmpty else { return }
        await apply(.scaleY(subfileIndices: sorted(selectedSubfileIndices), factor: factor))
    }

    public func scaleSelectedX(factor: Double) async {
        guard !selectedSubfileIndices.isEmpty else { return }
        await apply(.scaleX(subfileIndices: sorted(selectedSubfileIndices), factor: factor))
    }

    public func scaleSelectedXY(xFactor: Double, yFactor: Double) async {
        guard !selectedSubfileIndices.isEmpty else { return }
        await apply(.scaleXY(
            subfileIndices: sorted(selectedSubfileIndices),
            xFactor: xFactor,
            yFactor: yFactor
        ))
    }

    public func offsetSelectedY(offset: Double) async {
        guard !selectedSubfileIndices.isEmpty else { return }
        await apply(.offsetY(subfileIndices: sorted(selectedSubfileIndices), offset: offset))
    }

    public func applyExpressionToSelected(
        expression: String,
        axis: EditAxis
    ) async {
        guard !selectedSubfileIndices.isEmpty else { return }
        await apply(.applyExpression(
            subfileIndices: sorted(selectedSubfileIndices),
            expression: expression,
            axis: axis
        ))
    }

    // MARK: - Resolved state refresh

    /// Public entry point for initial state refresh after loading.
    public func refreshResolvedStatePublic() async {
        await refreshResolvedState()
    }

    private func refreshResolvedState() async {
        guard let session = editSession else { return }
        // Gather all resolved values from the actor
        async let subfiles   = session.allResolvedSubfiles()
        async let axisMeta   = session.resolvedAxisMetadata()
        async let memo       = session.resolvedMemo()
        async let auditLog   = session.resolvedAuditLog()
        async let header     = session.resolvedHeader()
        async let sfNames    = session.resolvedSubfileNames()
        async let dirty      = session.isDirty
        async let dirtyIdxs  = session.dirtySubfileIndices
        async let undoAvail  = session.canUndo
        async let redoAvail  = session.canRedo

        // Await all concurrently
        let (sf, am, m, al, hd, sn, d, di, cu, cr) = await (
            subfiles, axisMeta, memo, auditLog, header, sfNames, dirty, dirtyIdxs, undoAvail, redoAvail
        )

        self.resolvedSubfiles      = sf
        self.resolvedAxisMetadata  = am
        self.resolvedMemo          = m
        self.resolvedAuditLog      = al
        self.resolvedHeader        = hd
        self.resolvedSubfileNames  = sn
        self.isDirty               = d
        self.dirtySubfileIndices   = di
        self.canUndo               = cu
        self.canRedo               = cr
    }

    // MARK: - Helpers

    private func sorted(_ set: Set<Int>) -> [Int] { set.sorted() }

    private func suggestedSaveAsName(for file: SPCFile?) -> String {
        // Prefer the document name from the tab/title bar if set by the user
        if let docName = documentName,
           !docName.isEmpty,
           docName != "Untitled" {
            let safe = docName.replacingOccurrences(of: "/", with: "_")
            let base = safe.hasSuffix(".spc") ? String(safe.dropLast(4)) : safe
            return "\(base).spc"
        }
        guard let file else { return "spectrum.spc" }
        let memo = file.header.memo.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = memo.isEmpty ? "spectrum" : String(memo.prefix(40))
        let safe = base.replacingOccurrences(of: "/", with: "_")
        return "\(safe).spc"
    }
}

// MARK: - SPCExportFormat

/// Output format for Save As.
public enum SPCExportFormat: String, CaseIterable, Identifiable, Sendable {
    case thermoGalactic = "Thermo Galactic SPC"
    case shimadzuCFB    = "Shimadzu (OLE2/CFB)"

    public var id: String { rawValue }

    var fileExtension: String { "spc" }
}

// MARK: - SPCExportDocument

import UniformTypeIdentifiers

/// Lightweight FileDocument used with `.fileExporter` for cross-platform Save As.
/// Holds pre-built binary data; fileWrapper simply wraps it.
nonisolated struct SPCExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.spcFile] }
    static var writableContentTypes: [UTType] { [.spcFile] }

    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

// MARK: - IdentifiableError

/// Wraps any Error so it can be stored in @Observable state and shown via .alert(item:).
public struct IdentifiableError: Identifiable, Sendable {
    public let id = UUID()
    public let message: String
    public init(_ error: Error) { self.message = error.localizedDescription }
}

// MARK: - UTType extension

nonisolated extension UTType {
    /// UTType for Thermo Galactic SPC files — register com.thermogalactic.spc in Info.plist.
    public static let spcFile = UTType(exportedAs: "com.thermogalactic.spc", conformingTo: .data)
}

