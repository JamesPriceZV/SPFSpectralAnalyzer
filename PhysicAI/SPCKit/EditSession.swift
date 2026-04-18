// EditSession.swift
// SPCKit
//
// Actor-isolated edit session. Holds the source SPCFile (immutable) and
// a dictionary of SubfileDeltas (the mutations). Views and the writer
// always call resolvedSubfile(at:) to get the merged view.
//
// All types that cross actor boundaries are Sendable structs.

@preconcurrency import Foundation

// MARK: - SubfileDelta

/// The mutated state for one subfile. Only stores what changed.
/// When xPoints is nil the subfile remains Y-only (evenly spaced X).
/// When xPoints is non-nil the subfile is XY (the writer promotes the file type).
nonisolated public struct SubfileDelta: Sendable {

    /// Mutated X values. Nil = retain Y-only format (no X array stored).
    public var xPoints: [Float]?

    /// Mutated Y values. Always present when a delta exists.
    public var yPoints: [Float]

    /// New ffp/flp limits to write into the subheader / main header.
    /// Recalculated whenever X is scaled or individual X points are edited.
    public var firstX: Double
    public var lastX:  Double

    /// Running description of operations applied, appended to the audit log.
    public var operationLog: [String]

    public init(
        xPoints: [Float]? = nil,
        yPoints: [Float],
        firstX:  Double,
        lastX:   Double,
        operationLog: [String] = []
    ) {
        self.xPoints      = xPoints
        self.yPoints      = yPoints
        self.firstX       = firstX
        self.lastX        = lastX
        self.operationLog = operationLog
    }
}

// MARK: - EditAction

/// Every mutation is modelled as a discrete EditAction.
/// The edit session uses these for undo/redo and audit log generation.
nonisolated public enum EditAction: Sendable {

    // MARK: Bulk transforms (apply to one or more subfiles)

    /// Scale X axis values by `factor` for the given subfile indices.
    case scaleX(subfileIndices: [Int], factor: Double)

    /// Scale Y axis values by `factor` for the given subfile indices.
    case scaleY(subfileIndices: [Int], factor: Double)

    /// Scale both X and Y by independent factors simultaneously.
    case scaleXY(subfileIndices: [Int], xFactor: Double, yFactor: Double)

    /// Add a constant offset to all X values.
    case offsetX(subfileIndices: [Int], offset: Double)

    /// Add a constant offset to all Y values.
    case offsetY(subfileIndices: [Int], offset: Double)

    /// Clamp Y values to [min, max]. Points outside the range are clamped.
    case clampY(subfileIndices: [Int], min: Float, max: Float)

    /// Apply a user-supplied expression such as "y * 2.5 + 0.1" to Y,
    /// or "x - 400" to X. Both `x` and `y` are available as variables.
    case applyExpression(subfileIndices: [Int], expression: String, axis: EditAxis)

    // MARK: Point-level edits (always single subfile)

    /// Replace the X value at a specific point index.
    case editXPoint(subfileIndex: Int, pointIndex: Int, newValue: Float)

    /// Replace the Y value at a specific point index.
    case editYPoint(subfileIndex: Int, pointIndex: Int, newValue: Float)

    /// Replace both X and Y at a specific point index atomically.
    case editXYPoint(subfileIndex: Int, pointIndex: Int, newX: Float, newY: Float)

    // MARK: Metadata edits

    /// Replace the memo field in the main header.
    case editMemo(newMemo: String)

    /// Replace a custom axis label.
    case editAxisLabel(axis: EditAxis, newLabel: String)

    /// Change the experiment type code.
    case editExperimentType(newValue: UInt8)

    /// Change axis unit codes (X, Y, or Z).
    case editAxisUnits(axis: EditAxis, newCode: UInt8)

    /// Change the Z axis unit code.
    case editZUnits(newCode: UInt8)

    /// Edit the resolution description string (max 9 chars).
    case editResolution(newValue: String)

    /// Edit the source instrument string (max 9 chars).
    case editSourceInstrument(newValue: String)

    /// Edit the method file path string (max 48 chars).
    case editMethodFile(newValue: String)

    /// Edit Z start/end values for a subfile.
    case editSubfileZ(subfileIndex: Int, zStart: Float, zEnd: Float)

    /// Edit the Z increment for evenly-spaced multifiles.
    case editZIncrement(newValue: Float)

    /// Edit the concentration factor.
    case editConcentrationFactor(newValue: Float)

    /// Rename a subfile's display name (UI-only, stored in audit log).
    case renameSubfile(subfileIndex: Int, newName: String)

    // MARK: Subfile management

    /// Add subfiles imported from another SPC file.
    case addSubfiles(subfiles: [Subfile])

    /// Remove subfiles at given indices.
    case removeSubfiles(indices: [Int])

    /// Reorder subfiles to a new ordering (array of old indices in new order).
    case reorderSubfiles(newOrder: [Int])

    // MARK: Helpers

    /// Human-readable description appended to the audit log on save.
    public var auditDescription: String {
        let timestamp = String(describing: Date().timeIntervalSince1970)
        switch self {
        case let .scaleX(indices, factor):
            return "\(timestamp) Scale X ×\(factor) applied to subfiles \(indices)"
        case let .scaleY(indices, factor):
            return "\(timestamp) Scale Y ×\(factor) applied to subfiles \(indices)"
        case let .scaleXY(indices, xf, yf):
            return "\(timestamp) Scale X ×\(xf), Y ×\(yf) applied to subfiles \(indices)"
        case let .offsetX(indices, offset):
            return "\(timestamp) Offset X +\(offset) applied to subfiles \(indices)"
        case let .offsetY(indices, offset):
            return "\(timestamp) Offset Y +\(offset) applied to subfiles \(indices)"
        case let .clampY(indices, min, max):
            return "\(timestamp) Clamp Y [\(min), \(max)] applied to subfiles \(indices)"
        case let .applyExpression(indices, expr, axis):
            return "\(timestamp) Expression '\(expr)' on \(axis) applied to subfiles \(indices)"
        case let .editXPoint(sub, pt, val):
            return "\(timestamp) Edit X[\(pt)] = \(val) in subfile \(sub)"
        case let .editYPoint(sub, pt, val):
            return "\(timestamp) Edit Y[\(pt)] = \(val) in subfile \(sub)"
        case let .editXYPoint(sub, pt, nx, ny):
            return "\(timestamp) Edit point[\(pt)] = (\(nx), \(ny)) in subfile \(sub)"
        case let .editMemo(memo):
            return "\(timestamp) Memo updated: \(memo.prefix(40))…"
        case let .editAxisLabel(axis, label):
            return "\(timestamp) \(axis) axis label set to '\(label)'"
        case let .editExperimentType(val):
            return "\(timestamp) Experiment type set to \(val)"
        case let .editAxisUnits(axis, code):
            return "\(timestamp) \(axis) axis units set to \(code)"
        case let .editZUnits(code):
            return "\(timestamp) Z axis units set to \(code)"
        case let .editResolution(val):
            return "\(timestamp) Resolution set to '\(val)'"
        case let .editSourceInstrument(val):
            return "\(timestamp) Source instrument set to '\(val)'"
        case let .editMethodFile(val):
            return "\(timestamp) Method file set to '\(val)'"
        case let .editSubfileZ(idx, zs, ze):
            return "\(timestamp) Subfile \(idx) Z set to \(zs)–\(ze)"
        case let .editZIncrement(val):
            return "\(timestamp) Z increment set to \(val)"
        case let .editConcentrationFactor(val):
            return "\(timestamp) Concentration factor set to \(val)"
        case let .renameSubfile(idx, name):
            return "\(timestamp) Subfile \(idx) renamed to '\(name)'"
        case let .addSubfiles(subs):
            return "\(timestamp) Added \(subs.count) subfile(s)"
        case let .removeSubfiles(indices):
            return "\(timestamp) Removed subfiles at \(indices)"
        case let .reorderSubfiles(order):
            return "\(timestamp) Reordered subfiles: \(order)"
        }
    }

    /// The subfile indices affected by this action.
    public var affectedSubfileIndices: [Int] {
        switch self {
        case let .scaleX(i, _),
             let .scaleY(i, _),
             let .scaleXY(i, _, _),
             let .offsetX(i, _),
             let .offsetY(i, _),
             let .clampY(i, _, _),
             let .applyExpression(i, _, _):
            return i
        case let .editXPoint(s, _, _),
             let .editYPoint(s, _, _),
             let .editXYPoint(s, _, _, _):
            return [s]
        case .editMemo, .editAxisLabel,
             .editExperimentType, .editAxisUnits, .editZUnits,
             .editResolution, .editSourceInstrument, .editMethodFile,
             .editZIncrement, .editConcentrationFactor:
            return []
        case let .editSubfileZ(idx, _, _):
            return [idx]
        case let .renameSubfile(idx, _):
            return [idx]
        case let .addSubfiles(subs):
            return subs.map(\.id)
        case let .removeSubfiles(indices):
            return indices
        case .reorderSubfiles:
            return []
        }
    }
}

// MARK: - EditAxis

nonisolated public enum EditAxis: String, Sendable, CaseIterable {
    case x = "X"
    case y = "Y"
    case both = "Both"
}

// MARK: - EditSession

/// Holds the immutable source file and all pending deltas.
/// All mutations flow through `apply(_:)` so the undo stack stays consistent.
public actor EditSession {

    // MARK: State

    private let source: SPCFile

    /// Cached file type to avoid accessing computed property across isolation boundaries.
    private let sourceFileType: SPCFileType

    /// Pending deltas keyed by subfile index.
    private var deltas: [Int: SubfileDelta] = [:]

    /// Edits to memo and axis labels (not per-subfile).
    private var pendingMemo: String?
    private var pendingAxisLabels: [EditAxis: String] = [:]

    /// Pending header field edits.
    private var pendingExperimentType: UInt8?
    private var pendingAxisUnits: [EditAxis: UInt8] = [:]
    private var pendingZUnits: UInt8?
    private var pendingResolution: String?
    private var pendingSourceInstrument: String?
    private var pendingMethodFile: String?
    private var pendingZIncrement: Float?
    private var pendingConcentrationFactor: Float?

    /// Pending per-subfile Z value edits (subfile index → (zStart, zEnd)).
    private var pendingSubfileZ: [Int: (zStart: Float, zEnd: Float)] = [:]

    /// Custom display names for subfiles (index → name).
    private var pendingSubfileNames: [Int: String] = [:]

    /// Subfile structural changes: added, removed, reordered.
    /// These are applied on top of the source subfiles.
    private var addedSubfiles: [Subfile] = []
    private var removedIndices: Set<Int> = []
    private var subfileOrder: [Int]? = nil  // nil = original order

    /// Full state snapshot for O(1) undo/redo.
    private struct SessionSnapshot {
        let deltas: [Int: SubfileDelta]
        let pendingMemo: String?
        let pendingAxisLabels: [EditAxis: String]
        let pendingExperimentType: UInt8?
        let pendingAxisUnits: [EditAxis: UInt8]
        let pendingZUnits: UInt8?
        let pendingResolution: String?
        let pendingSourceInstrument: String?
        let pendingMethodFile: String?
        let pendingZIncrement: Float?
        let pendingConcentrationFactor: Float?
        let pendingSubfileZ: [Int: (zStart: Float, zEnd: Float)]
        let pendingSubfileNames: [Int: String]
        let addedSubfiles: [Subfile]
        let removedIndices: Set<Int>
        let subfileOrder: [Int]?
        let action: EditAction
    }

    /// Snapshot stack for O(1) undo.
    private var undoSnapshots: [SessionSnapshot] = []

    /// Snapshot stack for O(1) redo.
    private var redoSnapshots: [SessionSnapshot] = []

    /// Action history for audit log.
    private var actionHistory: [EditAction] = []

    // MARK: Init

    public init(source: SPCFile) {
        self.source = source
        // Compute file type from raw flag bits to avoid isolation issues
        // with SPCFile.fileType computed property.
        let raw = source.header.flags.rawValue
        if raw & 0x40 != 0 {
            self.sourceFileType = .xyxy
        } else if raw & 0x80 != 0 {
            self.sourceFileType = .xyy
        } else {
            self.sourceFileType = .yOnly
        }
    }

    private func captureSnapshot(action: EditAction) -> SessionSnapshot {
        SessionSnapshot(
            deltas: deltas,
            pendingMemo: pendingMemo,
            pendingAxisLabels: pendingAxisLabels,
            pendingExperimentType: pendingExperimentType,
            pendingAxisUnits: pendingAxisUnits,
            pendingZUnits: pendingZUnits,
            pendingResolution: pendingResolution,
            pendingSourceInstrument: pendingSourceInstrument,
            pendingMethodFile: pendingMethodFile,
            pendingZIncrement: pendingZIncrement,
            pendingConcentrationFactor: pendingConcentrationFactor,
            pendingSubfileZ: pendingSubfileZ,
            pendingSubfileNames: pendingSubfileNames,
            addedSubfiles: addedSubfiles,
            removedIndices: removedIndices,
            subfileOrder: subfileOrder,
            action: action
        )
    }

    private func restoreSnapshot(_ snapshot: SessionSnapshot) {
        deltas = snapshot.deltas
        pendingMemo = snapshot.pendingMemo
        pendingAxisLabels = snapshot.pendingAxisLabels
        pendingExperimentType = snapshot.pendingExperimentType
        pendingAxisUnits = snapshot.pendingAxisUnits
        pendingZUnits = snapshot.pendingZUnits
        pendingResolution = snapshot.pendingResolution
        pendingSourceInstrument = snapshot.pendingSourceInstrument
        pendingMethodFile = snapshot.pendingMethodFile
        pendingZIncrement = snapshot.pendingZIncrement
        pendingConcentrationFactor = snapshot.pendingConcentrationFactor
        pendingSubfileZ = snapshot.pendingSubfileZ
        pendingSubfileNames = snapshot.pendingSubfileNames
        addedSubfiles = snapshot.addedSubfiles
        removedIndices = snapshot.removedIndices
        subfileOrder = snapshot.subfileOrder
    }

    // MARK: Dirty state

    public var isDirty: Bool {
        !deltas.isEmpty || pendingMemo != nil || !pendingAxisLabels.isEmpty
        || pendingExperimentType != nil || !pendingAxisUnits.isEmpty
        || pendingZUnits != nil || pendingResolution != nil
        || pendingSourceInstrument != nil || pendingMethodFile != nil
        || pendingZIncrement != nil || pendingConcentrationFactor != nil
        || !pendingSubfileZ.isEmpty || !pendingSubfileNames.isEmpty
        || !addedSubfiles.isEmpty || !removedIndices.isEmpty || subfileOrder != nil
    }

    public var dirtySubfileIndices: Set<Int> {
        Set(deltas.keys)
    }

    // MARK: Apply

    /// Apply an edit action. Snapshots state before applying for O(1) undo.
    public func apply(_ action: EditAction) async throws {
        let snapshot = captureSnapshot(action: action)
        undoSnapshots.append(snapshot)
        redoSnapshots.removeAll()
        let result = try await TransformEngine.shared.execute(action, on: self)
        applyResult(result)
        actionHistory.append(action)
    }

    private func applyResult(_ result: TransformResult) {
        for (index, delta) in result.deltas {
            deltas[index] = delta
        }
        if let memo = result.memo { pendingMemo = memo }
        for (axis, label) in result.axisLabels { pendingAxisLabels[axis] = label }
        if let v = result.experimentType { pendingExperimentType = v }
        for (axis, code) in result.axisUnitCodes { pendingAxisUnits[axis] = code }
        if let v = result.zUnitsCode { pendingZUnits = v }
        if let v = result.resolution { pendingResolution = v }
        if let v = result.sourceInstrument { pendingSourceInstrument = v }
        if let v = result.methodFile { pendingMethodFile = v }
        if let v = result.zIncrement { pendingZIncrement = v }
        if let v = result.concentrationFactor { pendingConcentrationFactor = v }
        for (idx, z) in result.subfileZEdits { pendingSubfileZ[idx] = z }
        for (idx, name) in result.subfileNames { pendingSubfileNames[idx] = name }
        if let subs = result.addedSubfiles {
            addedSubfiles.append(contentsOf: subs)
        }
        if let indices = result.removedIndices {
            removedIndices.formUnion(indices)
        }
        if let order = result.newSubfileOrder {
            if let existing = subfileOrder {
                // Compose: new order indexes into the already-reordered array,
                // so map through the existing order to get source indices.
                subfileOrder = order.compactMap { idx in
                    idx < existing.count ? existing[idx] : nil
                }
            } else {
                subfileOrder = order
            }
        }
    }

    // MARK: Undo / Redo

    public var canUndo: Bool { !undoSnapshots.isEmpty }
    public var canRedo: Bool { !redoSnapshots.isEmpty }

    /// Reverts the most recent action by restoring the pre-action snapshot. O(1).
    public func undo() async throws {
        guard let snapshot = undoSnapshots.popLast() else { return }
        // Save current state for redo
        redoSnapshots.append(captureSnapshot(action: snapshot.action))
        restoreSnapshot(snapshot)
        if !actionHistory.isEmpty { actionHistory.removeLast() }
    }

    public func redo() async throws {
        guard let snapshot = redoSnapshots.popLast() else { return }
        // Save current state for undo
        undoSnapshots.append(captureSnapshot(action: snapshot.action))
        restoreSnapshot(snapshot)
        actionHistory.append(snapshot.action)
    }

    // MARK: Resolving data for views and the writer

    /// Returns the resolved (source + delta) subfile for a given index.
    public func resolvedSubfile(at index: Int) -> Subfile {
        let allSubs = effectiveSubfiles()
        guard index >= 0, index < allSubs.count else {
            return source.subfiles.indices.contains(index) ? source.subfiles[index] : allSubs[0]
        }
        let sub = allSubs[index]
        let key = sub.id  // Use the subfile's stable ID for delta/name lookups
        guard let delta = deltas[key] else {
            return patchSubfileZ(sub, index: key)
        }
        let patched = Subfile(
            id:         sub.id,
            subheader:  patchedSubheader(sub.subheader, with: delta, index: key),
            xPoints:    delta.xPoints ?? sub.xPoints,
            yPoints:    delta.yPoints
        )
        return patchSubfileZ(patched, index: key)
    }

    /// All resolved subfiles — used by the writer to build the output file.
    public func allResolvedSubfiles() -> [Subfile] {
        let allSubs = effectiveSubfiles()
        return allSubs.indices.map { resolvedSubfile(at: $0) }
    }

    /// The effective subfile list after add/remove/reorder operations.
    /// IDs are assigned before reorder so they stay attached to the data.
    /// The array order reflects the user's chosen display order.
    private func effectiveSubfiles() -> [Subfile] {
        var subs = source.subfiles

        // Remove subfiles
        if !removedIndices.isEmpty {
            subs = subs.enumerated().compactMap { removedIndices.contains($0.offset) ? nil : $0.element }
        }

        // Add imported subfiles
        if !addedSubfiles.isEmpty {
            subs.append(contentsOf: addedSubfiles)
        }

        // Re-index FIRST so IDs are sequential and match deltas/names
        subs = subs.enumerated().map { (i, sub) in
            Subfile(id: i, subheader: sub.subheader, xPoints: sub.xPoints, yPoints: sub.yPoints)
        }

        // THEN reorder — IDs travel with the data
        if let order = subfileOrder {
            let indexed = subs
            subs = order.compactMap { idx in
                idx < indexed.count ? indexed[idx] : nil
            }
        }

        return subs
    }

    /// The count of effective subfiles (after add/remove/reorder).
    public func effectiveSubfileCount() -> Int {
        effectiveSubfiles().count
    }

    private func patchSubfileZ(_ sub: Subfile, index: Int) -> Subfile {
        guard let z = pendingSubfileZ[index] else { return sub }
        let newHeader = SPCSubheader(
            flags: sub.subheader.flags,
            yExponent: sub.subheader.yExponent,
            index: sub.subheader.index,
            zStart: z.zStart,
            zEnd: z.zEnd,
            noiseValue: sub.subheader.noiseValue,
            xyxyPointCount: sub.subheader.xyxyPointCount,
            coAddedScans: sub.subheader.coAddedScans,
            wValue: sub.subheader.wValue
        )
        return Subfile(id: sub.id, subheader: newHeader, xPoints: sub.xPoints, yPoints: sub.yPoints)
    }

    /// Resolved axis metadata (incorporates any pending axis label and unit edits).
    public func resolvedAxisMetadata() -> AxisMetadata {
        AxisMetadata(
            xUnitsCode:   pendingAxisUnits[.x] ?? source.axisMetadata.xUnitsCode,
            yUnitsCode:   pendingAxisUnits[.y] ?? source.axisMetadata.yUnitsCode,
            zUnitsCode:   pendingZUnits ?? source.axisMetadata.zUnitsCode,
            wUnitsCode:   source.axisMetadata.wUnitsCode,
            customXLabel: pendingAxisLabels[.x] ?? source.axisMetadata.customXLabel,
            customYLabel: pendingAxisLabels[.y] ?? source.axisMetadata.customYLabel,
            customZLabel: nil,
            firstX: resolvedFirstX(),
            lastX:  resolvedLastX()
        )
    }

    /// Resolved memo.
    public func resolvedMemo() -> String {
        pendingMemo ?? source.header.memo
    }

    /// Resolved header with all pending metadata edits applied.
    public func resolvedHeader() -> SPCMainHeader {
        let h = source.header
        return SPCMainHeader(
            flags: h.flags,
            version: h.version,
            experimentType: pendingExperimentType ?? h.experimentType,
            yExponent: h.yExponent,
            pointCount: h.pointCount,
            firstX: h.firstX,
            lastX: h.lastX,
            subfileCount: UInt32(effectiveSubfileCount()),
            xUnitsCode: pendingAxisUnits[.x] ?? h.xUnitsCode,
            yUnitsCode: pendingAxisUnits[.y] ?? h.yUnitsCode,
            zUnitsCode: pendingZUnits ?? h.zUnitsCode,
            compressedDate: h.compressedDate,
            resolutionDescription: pendingResolution ?? h.resolutionDescription,
            sourceInstrument: pendingSourceInstrument ?? h.sourceInstrument,
            peakPoint: h.peakPoint,
            memo: pendingMemo ?? h.memo,
            customAxisLabels: h.customAxisLabels,
            logOffset: h.logOffset,
            modificationFlag: h.modificationFlag,
            concentrationFactor: pendingConcentrationFactor ?? h.concentrationFactor,
            methodFile: pendingMethodFile ?? h.methodFile,
            zIncrement: pendingZIncrement ?? h.zIncrement,
            wPlaneCount: h.wPlaneCount,
            wIncrement: h.wIncrement,
            wUnitsCode: h.wUnitsCode
        )
    }

    /// Custom display names for subfiles.
    public func resolvedSubfileNames() -> [Int: String] {
        pendingSubfileNames
    }

    /// Audit log entries: original entries plus one per applied action.
    public func resolvedAuditLog() -> [AuditLogEntry] {
        source.auditLog + actionHistory.map { AuditLogEntry(text: $0.auditDescription) }
    }

    // MARK: Private helpers

    private func patchedSubheader(
        _ original: SPCSubheader,
        with delta: SubfileDelta,
        index: Int
    ) -> SPCSubheader {
        // Re-use all original subheader fields; the writer will recalculate
        // per-subfile point counts for XYXY when it walks resolvedSubfiles.
        original
    }

    private func resolvedFirstX() -> Double {
        // If there are added subfiles or it's XYXY, compute from effective subfiles.
        if sourceFileType == .xyxy || !addedSubfiles.isEmpty {
            let subs = allResolvedSubfiles()
            return subs
                .compactMap { $0.xPoints?.first.map(Double.init) }
                .min() ?? deltas[0]?.firstX ?? source.header.firstX
        }
        return deltas[0]?.firstX ?? source.header.firstX
    }

    private func resolvedLastX() -> Double {
        if sourceFileType == .xyxy || !addedSubfiles.isEmpty {
            let subs = allResolvedSubfiles()
            return subs
                .compactMap { $0.xPoints?.last.map(Double.init) }
                .max() ?? deltas[0]?.lastX ?? source.header.lastX
        }
        return deltas[0]?.lastX ?? source.header.lastX
    }

    // MARK: Source access for TransformEngine

    /// Provides the source subfile to TransformEngine without exposing deltas.
    func sourceSubfile(at index: Int) -> Subfile {
        source.subfiles[index]
    }

    func sourcefile() -> SPCFile { source }
}

// MARK: - TransformResult

/// Returned by TransformEngine so the actor can apply the result in one step.
nonisolated public struct TransformResult: Sendable {
    public var deltas:              [Int: SubfileDelta]
    public var memo:                String?
    public var axisLabels:          [EditAxis: String]
    public var experimentType:      UInt8?
    public var axisUnitCodes:       [EditAxis: UInt8]
    public var zUnitsCode:          UInt8?
    public var resolution:          String?
    public var sourceInstrument:    String?
    public var methodFile:          String?
    public var zIncrement:          Float?
    public var concentrationFactor: Float?
    public var subfileZEdits:       [Int: (zStart: Float, zEnd: Float)]
    public var addedSubfiles:       [Subfile]?
    public var removedIndices:      Set<Int>?
    public var newSubfileOrder:     [Int]?
    public var subfileNames:        [Int: String]

    public init(
        deltas:              [Int: SubfileDelta] = [:],
        memo:                String?             = nil,
        axisLabels:          [EditAxis: String]  = [:],
        experimentType:      UInt8?              = nil,
        axisUnitCodes:       [EditAxis: UInt8]   = [:],
        zUnitsCode:          UInt8?              = nil,
        resolution:          String?             = nil,
        sourceInstrument:    String?             = nil,
        methodFile:          String?             = nil,
        zIncrement:          Float?              = nil,
        concentrationFactor: Float?              = nil,
        subfileZEdits:       [Int: (zStart: Float, zEnd: Float)] = [:],
        addedSubfiles:       [Subfile]?          = nil,
        removedIndices:      Set<Int>?           = nil,
        newSubfileOrder:     [Int]?              = nil,
        subfileNames:        [Int: String]       = [:]
    ) {
        self.deltas              = deltas
        self.memo                = memo
        self.axisLabels          = axisLabels
        self.experimentType      = experimentType
        self.axisUnitCodes       = axisUnitCodes
        self.zUnitsCode          = zUnitsCode
        self.resolution          = resolution
        self.sourceInstrument    = sourceInstrument
        self.methodFile          = methodFile
        self.zIncrement          = zIncrement
        self.concentrationFactor = concentrationFactor
        self.subfileZEdits       = subfileZEdits
        self.addedSubfiles       = addedSubfiles
        self.removedIndices      = removedIndices
        self.newSubfileOrder     = newSubfileOrder
        self.subfileNames        = subfileNames
    }
}
