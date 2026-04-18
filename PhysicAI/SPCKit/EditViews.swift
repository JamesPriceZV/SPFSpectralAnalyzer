// EditViews.swift
// SPCKit
//
// SwiftUI views for the edit layer:
//   - SubfileTreeView        (node selection in the sidebar)
//   - TransformPanel         (scale / offset / expression controls)
//   - XYDataTableView        (inline point editor)
//   - LivePreviewChart       (before/after overlay)
//
// All views are @MainActor implicitly (SwiftUI requirement).
// They read from SPCDocumentStore and dispatch actions back through it.

import SwiftUI
import Charts

// MARK: - SubfileTreeView

/// Sidebar list of all subfiles with multi-select, drag-to-reorder, and search filter.
/// Shows a "dirty" badge on subfiles that have pending edits.
struct SubfileTreeView: View {
    @Bindable var store: SPCDocumentStore
    @State private var renamingIndex: Int? = nil
    @State private var renameText: String = ""
    @State private var filterText: String = ""

    private var filteredSubfiles: [Subfile] {
        guard !filterText.isEmpty else { return store.resolvedSubfiles }
        let query = filterText.lowercased()
        return store.resolvedSubfiles.filter { sub in
            let name = store.resolvedSubfileNames[sub.id] ?? "Subfile \(sub.id)"
            return name.lowercased().contains(query)
                || "\(sub.id)".contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search filter
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
                TextField("Filter subfiles…", text: $filterText)
                    .textFieldStyle(.plain)
                    .font(.caption)
                if !filterText.isEmpty {
                    Button { filterText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.tertiary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quinary)

            Divider()

            List(selection: $store.selectedSubfileIndices) {
                ForEach(filteredSubfiles) { subfile in
                    HStack(spacing: 4) {
                        SubfileRow(
                            subfile:     subfile,
                            isDirty:     store.dirtySubfileIndices.contains(subfile.id),
                            zLabel:      store.resolvedAxisMetadata?.zLabel ?? "Z",
                            customName:  store.resolvedSubfileNames[subfile.id],
                            isRenaming:  renamingIndex == subfile.id,
                            renameText:  renamingIndex == subfile.id ? $renameText : .constant("")
                        )

                        // Reorder buttons (only when not filtering)
                        if filterText.isEmpty {
                            VStack(spacing: 2) {
                                Button {
                                    Task { await moveSubfile(subfile.id, direction: .up) }
                                } label: {
                                    Image(systemName: "chevron.up")
                                        .font(.caption2)
                                        .frame(width: 20, height: 16)
                                }
                                .buttonStyle(.borderless)
                                .disabled(subfile.id == store.resolvedSubfiles.first?.id)

                                Button {
                                    Task { await moveSubfile(subfile.id, direction: .down) }
                                } label: {
                                    Image(systemName: "chevron.down")
                                        .font(.caption2)
                                        .frame(width: 20, height: 16)
                                }
                                .buttonStyle(.borderless)
                                .disabled(subfile.id == store.resolvedSubfiles.last?.id)
                            }
                        }
                    }
                    .tag(subfile.id)
                    .contextMenu {
                        Button("Rename…") {
                            renameText = store.resolvedSubfileNames[subfile.id] ?? "Subfile \(subfile.id)"
                            renamingIndex = subfile.id
                        }
                        Button("Move Up") {
                            Task { await moveSubfile(subfile.id, direction: .up) }
                        }
                        .disabled(subfile.id == store.resolvedSubfiles.first?.id)
                        Button("Move Down") {
                            Task { await moveSubfile(subfile.id, direction: .down) }
                        }
                        .disabled(subfile.id == store.resolvedSubfiles.last?.id)
                        Divider()
                        Button("Edit Z Values…") {
                            store.showSubfileManager = true
                        }
                    }
                }
            }
            .listStyle(.sidebar)
        }
        .navigationTitle("Subfiles")
        .toolbar {
            ToolbarItem {
                Button(store.selectedSubfileIndices.count == store.resolvedSubfiles.count
                       ? "Deselect all" : "Select all") {
                    if store.selectedSubfileIndices.count == store.resolvedSubfiles.count {
                        store.selectedSubfileIndices.removeAll()
                    } else {
                        store.selectedSubfileIndices = Set(store.resolvedSubfiles.map(\.id))
                    }
                }
                .buttonStyle(.borderless)
            }
        }
        .alert("Rename Subfile", isPresented: Binding(
            get: { renamingIndex != nil },
            set: { if !$0 { renamingIndex = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("OK") {
                guard let idx = renamingIndex else { return }
                Task { await store.apply(.renameSubfile(subfileIndex: idx, newName: renameText)) }
                renamingIndex = nil
            }
            Button("Cancel", role: .cancel) { renamingIndex = nil }
        } message: {
            Text("Enter a display name for this subfile.")
        }
    }

    private enum MoveDirection { case up, down }

    private func moveSubfile(_ subfileID: Int, direction: MoveDirection) async {
        let subs = store.resolvedSubfiles
        guard let currentPos = subs.firstIndex(where: { $0.id == subfileID }) else { return }
        let targetPos: Int
        switch direction {
        case .up:   targetPos = currentPos - 1
        case .down: targetPos = currentPos + 2  // move(fromOffsets:toOffset:) uses insert-before semantics
        }
        guard targetPos >= 0 && targetPos <= subs.count else { return }
        await store.moveSubfiles(from: IndexSet(integer: currentPos), to: targetPos)
    }
}

private struct SubfileRow: View {
    let subfile:    Subfile
    let isDirty:    Bool
    let zLabel:     String
    let customName: String?
    let isRenaming: Bool
    @Binding var renameText: String

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(customName ?? "Subfile \(subfile.id)")
                    .font(.system(.body, design: .monospaced))
                Text("\(zLabel): \(subfile.zStart, specifier: "%.4g")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isDirty {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(.orange)
                    .imageScale(.small)
                    .accessibilityLabel("Has pending edits")
            }
            Text("\(subfile.pointCount) pts")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - TransformPanel

/// Sheet / inspector panel for bulk transforms.
/// Validates input live; applies only on explicit user confirmation.
struct TransformPanel: View {
    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var mode: TransformMode = .scaleY
    @State private var yFactorText: String = "2"
    @State private var xFactorText: String = "1"
    @State private var offsetText:  String = "0"
    @State private var clampMinText: String = "0"
    @State private var clampMaxText: String = "1"
    @State private var expressionText: String = "y * 2"
    @State private var expressionAxis: EditAxis = .y
    @State private var validationMessage: String = ""
    @State private var validationIsError: Bool = false
    @State private var previewTrigger: UUID = UUID()
    @State private var hasApplied: Bool = false

    enum TransformMode: String, CaseIterable, Identifiable {
        case scaleY    = "Scale Y"
        case scaleX    = "Scale X"
        case scaleXY   = "Scale X & Y"
        case offsetY   = "Offset Y"
        case offsetX   = "Offset X"
        case clampY    = "Clamp Y"
        case expression = "Expression"
        var id: String { rawValue }
    }

    var selectionSummary: String {
        let n = store.selectedSubfileIndices.count
        if n == 0 { return "No subfiles selected" }
        if n == store.resolvedSubfiles.count { return "All \(n) subfiles" }
        return "\(n) subfile\(n == 1 ? "" : "s") selected"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Selection scope badge
            Label(selectionSummary, systemImage: "checkmark.circle")
                .font(.headline)
                .foregroundStyle(store.selectedSubfileIndices.isEmpty ? .red : .primary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(TransformMode.allCases) { m in
                        Button(m.rawValue) {
                            mode = m
                            validateCurrentInputs()
                        }
                        .buttonStyle(.bordered)
                        .tint(mode == m ? .accentColor : .secondary)
                        .controlSize(.small)
                    }
                }
            }

            Divider()

            // Mode-specific controls
            switch mode {
            case .scaleY:
                ScaleFactorField(label: "Y factor", text: $yFactorText) { validateCurrentInputs() }
                PresetButtons(factors: [0.5, 2, 3, 4, 5, 10]) { f in
                    yFactorText = formatFactor(f)
                    validateCurrentInputs()
                }

            case .scaleX:
                ScaleFactorField(label: "X factor", text: $xFactorText) { validateCurrentInputs() }
                PresetButtons(factors: [0.5, 2, 3, 4, 5, 10]) { f in
                    xFactorText = formatFactor(f)
                    validateCurrentInputs()
                }

            case .scaleXY:
                ScaleFactorField(label: "X factor", text: $xFactorText) { validateCurrentInputs() }
                ScaleFactorField(label: "Y factor", text: $yFactorText) { validateCurrentInputs() }

            case .offsetY:
                HStack {
                    Text("Y offset")
                        .frame(width: 70, alignment: .trailing)
                    TextField("0", text: $offsetText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: offsetText) { _, _ in validateCurrentInputs() }
                }

            case .offsetX:
                HStack {
                    Text("X offset")
                        .frame(width: 70, alignment: .trailing)
                    TextField("0", text: $offsetText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: offsetText) { _, _ in validateCurrentInputs() }
                }

            case .clampY:
                HStack {
                    Text("Min")
                        .frame(width: 70, alignment: .trailing)
                    TextField("0", text: $clampMinText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: clampMinText) { _, _ in validateCurrentInputs() }
                }
                HStack {
                    Text("Max")
                        .frame(width: 70, alignment: .trailing)
                    TextField("1", text: $clampMaxText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: clampMaxText) { _, _ in validateCurrentInputs() }
                }

            case .expression:
                Picker("Axis", selection: $expressionAxis) {
                    ForEach(EditAxis.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Expr")
                        .frame(width: 70, alignment: .trailing)
                    TextField("y * 2.5 + 0.1", text: $expressionText)
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: expressionText) { _, _ in validateCurrentInputs() }
                }
                Text("Variables: x, y, pi, e  |  Functions: sin cos tan sqrt abs log ln exp floor ceil round")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Validation feedback
            if !validationMessage.isEmpty {
                Label(validationMessage, systemImage: validationIsError ? "xmark.circle" : "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(validationIsError ? .red : .orange)
            }

            Divider()

            // Action buttons
            HStack {
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button("Apply") {
                    Task {
                        await applyCurrentTransform()
                        hasApplied = true
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    store.selectedSubfileIndices.isEmpty ||
                    store.isTransforming ||
                    validationIsError ||
                    hasApplied
                )
                .keyboardShortcut(.return)
            }
        }
        .padding()
        .frame(minWidth: 320)
        .onAppear { validateCurrentInputs() }
    }

    // MARK: Validation

    private func validateCurrentInputs() {
        hasApplied = false
        switch mode {
        case .scaleY:
            check(PointEditValidator.validateScaleFactor(Double(yFactorText) ?? 0, axis: .y))
        case .scaleX:
            check(PointEditValidator.validateScaleFactor(Double(xFactorText) ?? 0, axis: .x))
        case .scaleXY:
            let x = PointEditValidator.validateScaleFactor(Double(xFactorText) ?? 0, axis: .x)
            let y = PointEditValidator.validateScaleFactor(Double(yFactorText) ?? 0, axis: .y)
            // Report whichever is worse
            check(x == .valid ? y : x)
        case .offsetY:
            check(PointEditValidator.validateOffset(Double(offsetText) ?? 0, axis: .y))
        case .offsetX:
            check(PointEditValidator.validateOffset(Double(offsetText) ?? 0, axis: .x))
        case .clampY:
            check(PointEditValidator.validateClampRange(
                min: Float(clampMinText) ?? 0,
                max: Float(clampMaxText) ?? 1
            ))
        case .expression:
            let (result, _) = PointEditValidator.validateExpression(expressionText, axis: expressionAxis)
            check(result)
        }
    }

    private func check(_ result: ValidationResult) {
        switch result {
        case .valid:
            validationMessage = ""
            validationIsError = false
        case let .warning(msg):
            validationMessage = msg
            validationIsError = false
        case let .error(msg):
            validationMessage = msg
            validationIsError = true
        }
    }

    // MARK: Apply

    private func applyCurrentTransform() async {
        let indices = store.selectedSubfileIndices.sorted()
        switch mode {
        case .scaleY:
            guard let f = Double(yFactorText) else { return }
            await store.apply(.scaleY(subfileIndices: indices, factor: f))
        case .scaleX:
            guard let f = Double(xFactorText) else { return }
            await store.apply(.scaleX(subfileIndices: indices, factor: f))
        case .scaleXY:
            guard let xf = Double(xFactorText), let yf = Double(yFactorText) else { return }
            await store.apply(.scaleXY(subfileIndices: indices, xFactor: xf, yFactor: yf))
        case .offsetY:
            guard let o = Double(offsetText) else { return }
            await store.apply(.offsetY(subfileIndices: indices, offset: o))
        case .offsetX:
            guard let o = Double(offsetText) else { return }
            await store.apply(.offsetX(subfileIndices: indices, offset: o))
        case .clampY:
            guard let mn = Float(clampMinText), let mx = Float(clampMaxText) else { return }
            await store.apply(.clampY(subfileIndices: indices, min: mn, max: mx))
        case .expression:
            await store.apply(.applyExpression(
                subfileIndices: indices,
                expression: expressionText,
                axis: expressionAxis
            ))
        }
    }

    private func formatFactor(_ f: Double) -> String {
        f == f.rounded() ? String(Int(f)) : String(format: "%.2f", f)
    }
}

// MARK: - Preset buttons

private struct PresetButtons: View {
    let factors: [Double]
    let onSelect: (Double) -> Void
    var body: some View {
        HStack(spacing: 6) {
            ForEach(factors, id: \.self) { f in
                Button("\(formatFactor(f))×") { onSelect(f) }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
            }
        }
    }
    private func formatFactor(_ f: Double) -> String {
        f == f.rounded() ? String(Int(f)) : String(format: "%.1f", f)
    }
}

// MARK: - Scale factor field

private struct ScaleFactorField: View {
    let label: String
    @Binding var text: String
    let onChange: () -> Void
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 70, alignment: .trailing)
            TextField("1", text: $text)
                .textFieldStyle(.roundedBorder)
                .onChange(of: text) { _, _ in onChange() }
        }
    }
}

// MARK: - XYDataTableView

/// Scrollable table of resolved X/Y values.
/// When a single subfile is selected/focused, shows editable X + Y columns.
/// When multiple subfiles are selected, shows a shared X column and read-only
/// Y columns for each selected subfile (with short names as column headers).
struct XYDataTableView: View {
    @Bindable var store: SPCDocumentStore
    @State private var searchText: String = ""

    private var sourceFile: SPCFile? { store.sourceFile }

    /// The subfiles currently displayed in the table.
    private var displayedSubfiles: [Subfile] {
        let selected = store.selectedSubfileIndices
        let subs = store.resolvedSubfiles.filter { selected.contains($0.id) }
        if !subs.isEmpty { return subs }
        if let focused = store.resolvedSubfiles.first(where: { $0.id == store.focusedSubfileIndex }) {
            return [focused]
        }
        return Array(store.resolvedSubfiles.prefix(1))
    }

    private var isMultiMode: Bool { displayedSubfiles.count > 1 }

    // MARK: - Single-subfile types

    private struct PointRow: Identifiable {
        let index: Int
        let x: Float
        let y: Float
        var id: Int { index }
    }

    private var singleSubfile: Subfile? {
        isMultiMode ? nil : displayedSubfiles.first
    }

    private func singleDisplayedPoints() -> [PointRow] {
        guard let sf = singleSubfile else { return [] }
        let ffp = store.resolvedAxisMetadata?.firstX ?? sourceFile?.header.firstX ?? 0
        let flp = store.resolvedAxisMetadata?.lastX ?? sourceFile?.header.lastX ?? 1
        let xs = sf.resolvedXPoints(ffp: ffp, flp: flp)
        let rows = zip(xs, sf.yPoints).enumerated().map { (idx, pair) in
            PointRow(index: idx, x: pair.0, y: pair.1)
        }
        return filterRows(rows)
    }

    // MARK: - Multi-subfile types

    private struct MultiPointRow: Identifiable {
        let index: Int
        let x: Float
        let yValues: [Int: Float]   // subfile id → Y value
        var id: Int { index }
    }

    private func multiDisplayedPoints() -> [MultiPointRow] {
        guard isMultiMode else { return [] }
        let ffp = store.resolvedAxisMetadata?.firstX ?? sourceFile?.header.firstX ?? 0
        let flp = store.resolvedAxisMetadata?.lastX ?? sourceFile?.header.lastX ?? 1

        // Use the first subfile's X as the shared axis
        let primarySF = displayedSubfiles[0]
        let xs = primarySF.resolvedXPoints(ffp: ffp, flp: flp)
        let maxCount = xs.count

        var rows: [MultiPointRow] = []
        for i in 0..<maxCount {
            var yDict: [Int: Float] = [:]
            for sf in displayedSubfiles {
                if i < sf.yPoints.count {
                    yDict[sf.id] = sf.yPoints[i]
                }
            }
            rows.append(MultiPointRow(index: i, x: xs[i], yValues: yDict))
        }

        return filterRows(rows)
    }

    private func filterRows(_ rows: [PointRow]) -> [PointRow] {
        if searchText.isEmpty { return rows }
        if let rangeMatch = parseXRange(searchText) {
            return rows.filter { $0.x >= rangeMatch.0 && $0.x <= rangeMatch.1 }
        }
        if let idx = Int(searchText) {
            return rows.filter { $0.index == idx }
        }
        return rows
    }

    private func filterRows(_ rows: [MultiPointRow]) -> [MultiPointRow] {
        if searchText.isEmpty { return rows }
        if let rangeMatch = parseXRange(searchText) {
            return rows.filter { $0.x >= rangeMatch.0 && $0.x <= rangeMatch.1 }
        }
        if let idx = Int(searchText) {
            return rows.filter { $0.index == idx }
        }
        return rows
    }

    private func shortName(for subfile: Subfile) -> String {
        let full = store.resolvedSubfileNames[subfile.id] ?? "SF \(subfile.id)"
        // Abbreviate long names
        if full.count > 15 {
            return String(full.prefix(12)) + "…"
        }
        return full
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                if isMultiMode {
                    Text("\(displayedSubfiles.count) subfiles selected")
                        .font(.headline)
                } else {
                    Text(store.resolvedSubfileNames[store.focusedSubfileIndex]
                         ?? "Subfile \(store.focusedSubfileIndex)")
                        .font(.headline)
                }
                Spacer()
                if !isMultiMode {
                    Text("\(singleSubfile?.pointCount ?? 0) points")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by index or X range (e.g. 400–500)", text: $searchText)
                    .textFieldStyle(.plain)
                if !searchText.isEmpty {
                    Button { searchText = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                }
            }
            .padding(8)
            .background(.quinary)

            Divider()

            // Table content
            if isMultiMode {
                multiSubfileTable
            } else {
                singleSubfileTable
            }
        }
    }

    // MARK: - Single subfile table (editable)

    private var singleSubfileTable: some View {
        Table(singleDisplayedPoints(), columns: {
            TableColumn("Index") { row in
                Text(row.index, format: .number)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 60, ideal: 60)

            TableColumn("X") { row in
                EditableCell(
                    value: row.x,
                    onCommit: { newVal in
                        Task {
                            await store.apply(.editXPoint(
                                subfileIndex: store.focusedSubfileIndex,
                                pointIndex:   row.index,
                                newValue:     newVal
                            ))
                        }
                    },
                    validate: { val in
                        guard let sf = singleSubfile, let src = sourceFile else { return .valid }
                        let xs = sf.resolvedXPoints(ffp: src.header.firstX, flp: src.header.lastX)
                        return PointEditValidator.validateXEdit(
                            xPoints:  xs,
                            index:    row.index,
                            newValue: val,
                            fileType: src.fileType
                        )
                    }
                )
            }

            TableColumn("Y") { row in
                EditableCell(
                    value: row.y,
                    onCommit: { newVal in
                        Task {
                            await store.apply(.editYPoint(
                                subfileIndex: store.focusedSubfileIndex,
                                pointIndex:   row.index,
                                newValue:     newVal
                            ))
                        }
                    },
                    validate: { val in
                        guard let src = sourceFile else { return .valid }
                        return PointEditValidator.validateYEdit(
                            yPoints:   singleSubfile?.yPoints ?? [],
                            index:     row.index,
                            newValue:  val,
                            yExponent: src.header.yExponent
                        )
                    }
                )
            }
        })
    }

    // MARK: - Multi subfile table (read-only Y columns per subfile)

    private var multiSubfileTable: some View {
        let rows = multiDisplayedPoints()
        let subs = displayedSubfiles
        return ScrollView {
            LazyVStack(spacing: 0) {
                // Column headers
                HStack(spacing: 0) {
                    Text("Index")
                        .frame(width: 60, alignment: .leading)
                    Text("X")
                        .frame(minWidth: 80, alignment: .leading)
                    ForEach(subs) { sf in
                        Text(shortName(for: sf))
                            .frame(minWidth: 80, alignment: .trailing)
                    }
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.quinary)

                Divider()

                ForEach(rows) { row in
                    HStack(spacing: 0) {
                        Text("\(row.index)")
                            .frame(width: 60, alignment: .leading)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.6g", row.x))
                            .frame(minWidth: 80, alignment: .leading)
                        ForEach(subs) { sf in
                            if let y = row.yValues[sf.id] {
                                Text(String(format: "%.6g", y))
                                    .frame(minWidth: 80, alignment: .trailing)
                            } else {
                                Text("—")
                                    .frame(minWidth: 80, alignment: .trailing)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                    .font(.system(.caption, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                    Divider()
                }
            }
        }
    }

    // MARK: - Helpers

    private func parseXRange(_ s: String) -> (Float, Float)? {
        let parts = s.split(separator: "-").map { Float($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let lo = parts[0], let hi = parts[1], lo < hi else { return nil }
        return (lo, hi)
    }
}

// MARK: - EditableCell

/// A table cell that is a label until tapped, then becomes a TextField.
/// Shows a red border while the proposed value fails validation.
private struct EditableCell: View {
    let value: Float
    let onCommit: (Float) -> Void
    let validate: (Float) -> ValidationResult

    @State private var isEditing  = false
    @State private var editText   = ""
    @State private var isInvalid  = false

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $editText)
                    .font(.system(.body, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: 3)
                            .stroke(isInvalid ? Color.red : .clear, lineWidth: 1)
                    )
                    .onChange(of: editText) { _, newText in
                        if let f = Float(newText) {
                            isInvalid = validate(f) == .valid ? false : true
                        } else {
                            isInvalid = true
                        }
                    }
                    .onSubmit {
                        if let f = Float(editText) {
                            let result = validate(f)
                            if case .error = result { return }
                            onCommit(f)
                        }
                        isEditing = false
                    }
                    #if os(macOS)
                    .onExitCommand { isEditing = false }
                    #endif
            } else {
                Text(value, format: .number.precision(.significantDigits(6)))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editText  = String(value)
                        isInvalid = false
                        isEditing = true
                    }
            }
        }
    }
}

extension ValidationResult: Equatable {
    public static func == (lhs: ValidationResult, rhs: ValidationResult) -> Bool {
        switch (lhs, rhs) {
        case (.valid, .valid): return true
        case (.warning, .warning): return true
        case (.error, .error): return true
        default: return false
        }
    }
}

// MARK: - MetadataEditorView

/// Sheet for editing SPC file header metadata fields.
struct MetadataEditorView: View {
    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss

    @State private var memo: String = ""
    @State private var experimentType: Int = 0
    @State private var xUnitsCode: Int = 0
    @State private var yUnitsCode: Int = 0
    @State private var zUnitsCode: Int = 0
    @State private var resolution: String = ""
    @State private var sourceInstrument: String = ""
    @State private var methodFile: String = ""
    @State private var zIncrement: String = "0"
    @State private var concentrationFactor: String = "1"
    @State private var customXLabel: String = ""
    @State private var customYLabel: String = ""

    private var header: SPCMainHeader? { store.resolvedHeader ?? store.sourceFile?.header }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // General
                    GroupBox("General") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Memo", text: $memo, axis: .vertical)
                                .lineLimit(2...4)
                                .textFieldStyle(.roundedBorder)
                            Picker("Experiment Type", selection: $experimentType) {
                                ForEach(Self.experimentTypes, id: \.code) { item in
                                    Text(item.label).tag(Int(item.code))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Axis Units
                    GroupBox("Axis Units") {
                        VStack(alignment: .leading, spacing: 8) {
                            Picker("X Units", selection: $xUnitsCode) {
                                ForEach(Self.axisUnitOptions, id: \.code) { item in
                                    Text(item.label).tag(Int(item.code))
                                }
                            }
                            TextField("Custom X Label", text: $customXLabel)
                                .textFieldStyle(.roundedBorder)
                            Picker("Y Units", selection: $yUnitsCode) {
                                ForEach(Self.axisUnitOptions, id: \.code) { item in
                                    Text(item.label).tag(Int(item.code))
                                }
                            }
                            TextField("Custom Y Label", text: $customYLabel)
                                .textFieldStyle(.roundedBorder)
                            Picker("Z Units", selection: $zUnitsCode) {
                                ForEach(Self.axisUnitOptions, id: \.code) { item in
                                    Text(item.label).tag(Int(item.code))
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Instrument
                    GroupBox("Instrument") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Resolution") {
                                TextField("", text: $resolution)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledContent("Source") {
                                TextField("", text: $sourceInstrument)
                                    .textFieldStyle(.roundedBorder)
                            }
                            LabeledContent("Method") {
                                TextField("", text: $methodFile)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    // Multifile
                    GroupBox("Multifile") {
                        VStack(alignment: .leading, spacing: 8) {
                            LabeledContent("Z Increment") {
                                TextField("0", text: $zIncrement)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .multilineTextAlignment(.trailing)
                            }
                            LabeledContent("Concentration") {
                                TextField("1", text: $concentrationFactor)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 120)
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
                .padding()
            }
            .navigationTitle("Edit Metadata")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task { await applyChanges() }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .onAppear { loadCurrentValues() }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private func loadCurrentValues() {
        guard let h = header else { return }
        memo = store.resolvedMemo
        experimentType = Int(h.experimentType)
        xUnitsCode = Int(store.resolvedAxisMetadata?.xUnitsCode ?? h.xUnitsCode)
        yUnitsCode = Int(store.resolvedAxisMetadata?.yUnitsCode ?? h.yUnitsCode)
        zUnitsCode = Int(store.resolvedAxisMetadata?.zUnitsCode ?? h.zUnitsCode)
        resolution = h.resolutionDescription
        sourceInstrument = h.sourceInstrument
        methodFile = h.methodFile
        zIncrement = String(h.zIncrement)
        concentrationFactor = String(h.concentrationFactor)
        customXLabel = store.resolvedAxisMetadata?.customXLabel ?? ""
        customYLabel = store.resolvedAxisMetadata?.customYLabel ?? ""
    }

    private func applyChanges() async {
        guard let h = header else { return }

        // Only apply actions for fields that changed
        if memo != store.resolvedMemo {
            await store.apply(.editMemo(newMemo: memo))
        }
        if UInt8(experimentType) != h.experimentType {
            await store.apply(.editExperimentType(newValue: UInt8(experimentType)))
        }
        let resolvedXCode = store.resolvedAxisMetadata?.xUnitsCode ?? h.xUnitsCode
        if UInt8(xUnitsCode) != resolvedXCode {
            await store.apply(.editAxisUnits(axis: .x, newCode: UInt8(xUnitsCode)))
        }
        let resolvedYCode = store.resolvedAxisMetadata?.yUnitsCode ?? h.yUnitsCode
        if UInt8(yUnitsCode) != resolvedYCode {
            await store.apply(.editAxisUnits(axis: .y, newCode: UInt8(yUnitsCode)))
        }
        let resolvedZCode = store.resolvedAxisMetadata?.zUnitsCode ?? h.zUnitsCode
        if UInt8(zUnitsCode) != resolvedZCode {
            await store.apply(.editZUnits(newCode: UInt8(zUnitsCode)))
        }
        if resolution != h.resolutionDescription {
            await store.apply(.editResolution(newValue: resolution))
        }
        if sourceInstrument != h.sourceInstrument {
            await store.apply(.editSourceInstrument(newValue: sourceInstrument))
        }
        if methodFile != h.methodFile {
            await store.apply(.editMethodFile(newValue: methodFile))
        }
        if let zi = Float(zIncrement), zi != h.zIncrement {
            await store.apply(.editZIncrement(newValue: zi))
        }
        if let cf = Float(concentrationFactor), cf != h.concentrationFactor {
            await store.apply(.editConcentrationFactor(newValue: cf))
        }
        let currentCustomX = store.resolvedAxisMetadata?.customXLabel ?? ""
        if customXLabel != currentCustomX {
            await store.apply(.editAxisLabel(axis: .x, newLabel: customXLabel))
        }
        let currentCustomY = store.resolvedAxisMetadata?.customYLabel ?? ""
        if customYLabel != currentCustomY {
            await store.apply(.editAxisLabel(axis: .y, newLabel: customYLabel))
        }

        dismiss()
    }

    // MARK: - Static data

    private struct LabeledCode {
        let code: UInt8
        let label: String
    }

    private static let experimentTypes: [LabeledCode] = [
        LabeledCode(code: 0,  label: "General / Unknown"),
        LabeledCode(code: 1,  label: "Gas Chromatogram"),
        LabeledCode(code: 2,  label: "General Chromatogram"),
        LabeledCode(code: 3,  label: "HPLC Chromatogram"),
        LabeledCode(code: 4,  label: "FT-IR"),
        LabeledCode(code: 5,  label: "NIR"),
        LabeledCode(code: 6,  label: "UV-VIS"),
        LabeledCode(code: 7,  label: "X-Ray Diffraction"),
        LabeledCode(code: 8,  label: "Mass Spectrum"),
        LabeledCode(code: 9,  label: "NMR"),
        LabeledCode(code: 10, label: "Raman"),
        LabeledCode(code: 11, label: "Fluorescence"),
        LabeledCode(code: 12, label: "Atomic"),
        LabeledCode(code: 13, label: "Chromatography - DAD"),
    ]

    private static let axisUnitOptions: [LabeledCode] = [
        LabeledCode(code: 0,   label: "Arbitrary"),
        LabeledCode(code: 1,   label: "Wavenumber (cm⁻¹)"),
        LabeledCode(code: 2,   label: "Micrometers (μm)"),
        LabeledCode(code: 3,   label: "Nanometers (nm)"),
        LabeledCode(code: 4,   label: "Seconds"),
        LabeledCode(code: 5,   label: "Minutes"),
        LabeledCode(code: 6,   label: "Hertz (Hz)"),
        LabeledCode(code: 7,   label: "Kilohertz (kHz)"),
        LabeledCode(code: 8,   label: "Megahertz (MHz)"),
        LabeledCode(code: 9,   label: "Mass (M/z)"),
        LabeledCode(code: 10,  label: "Parts per million (PPM)"),
        LabeledCode(code: 11,  label: "Days"),
        LabeledCode(code: 12,  label: "Years"),
        LabeledCode(code: 13,  label: "Raman shift (cm⁻¹)"),
        LabeledCode(code: 14,  label: "Electron volts (eV)"),
        LabeledCode(code: 32,  label: "Transmission"),
        LabeledCode(code: 33,  label: "Reflectance"),
        LabeledCode(code: 34,  label: "Absorbance (log 1/R)"),
        LabeledCode(code: 35,  label: "Kubelka-Munk"),
        LabeledCode(code: 36,  label: "Counts"),
        LabeledCode(code: 37,  label: "Volts"),
        LabeledCode(code: 38,  label: "Degrees"),
        LabeledCode(code: 43,  label: "Percent"),
        LabeledCode(code: 44,  label: "Intensity"),
        LabeledCode(code: 45,  label: "Relative Intensity"),
        LabeledCode(code: 255, label: "User Defined"),
    ]
}

// MARK: - SubfileManagerView

/// Sheet for managing subfiles: add from other SPC files, remove, reorder,
/// and edit per-subfile Z values.
struct SubfileManagerView: View {
    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var showImporter = false
    @State private var selection: Set<Int> = []
    @State private var editingZIndex: Int? = nil
    @State private var zStartText: String = ""
    @State private var zEndText: String = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Action bar
                HStack(spacing: 12) {
                    Button {
                        showImporter = true
                    } label: {
                        Label("Import SPC…", systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)

                    Button(role: .destructive) {
                        Task { await removeSelected() }
                    } label: {
                        Label("Remove (\(selection.count))", systemImage: "minus.circle")
                    }
                    .buttonStyle(.bordered)
                    .disabled(selection.isEmpty)

                    Spacer()

                    Button(selection.count == store.resolvedSubfiles.count
                           ? "Deselect All" : "Select All") {
                        if selection.count == store.resolvedSubfiles.count {
                            selection.removeAll()
                        } else {
                            selection = Set(store.resolvedSubfiles.map(\.id))
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)

                    Text("\(store.resolvedSubfiles.count) subfile\(store.resolvedSubfiles.count == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
                .padding()

                Divider()

                // Subfile list with tap-to-select checkmarks
                List {
                    ForEach(store.resolvedSubfiles) { subfile in
                        HStack {
                            // Checkbox toggle
                            Button {
                                if selection.contains(subfile.id) {
                                    selection.remove(subfile.id)
                                } else {
                                    selection.insert(subfile.id)
                                }
                            } label: {
                                Image(systemName: selection.contains(subfile.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .foregroundStyle(selection.contains(subfile.id)
                                                     ? .blue : .secondary)
                            }
                            .buttonStyle(.borderless)

                            SubfileManagerRow(
                                subfile: subfile,
                                customName: store.resolvedSubfileNames[subfile.id],
                                zLabel: store.resolvedAxisMetadata?.zLabel ?? "Z",
                                isEditingZ: editingZIndex == subfile.id,
                                zStartText: editingZIndex == subfile.id ? $zStartText : .constant(""),
                                zEndText: editingZIndex == subfile.id ? $zEndText : .constant(""),
                                onTapZ: {
                                    editingZIndex = subfile.id
                                    zStartText = String(subfile.zStart)
                                    zEndText = String(subfile.zEnd)
                                },
                                onCommitZ: {
                                    Task { await commitZEdit(for: subfile.id) }
                                },
                                onCancelZ: {
                                    editingZIndex = nil
                                }
                            )
                        }
                    }
                }
                .listStyle(.inset)
            }
            .navigationTitle("Manage Subfiles")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.spcFile],
                allowsMultipleSelection: true
            ) { result in
                Task { await handleImport(result) }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func removeSelected() async {
        await store.removeSubfiles(at: selection)
        selection.removeAll()
    }

    private func commitZEdit(for index: Int) async {
        guard let zs = Float(zStartText), let ze = Float(zEndText) else { return }
        await store.apply(.editSubfileZ(subfileIndex: index, zStart: zs, zEnd: ze))
        editingZIndex = nil
    }

    private func handleImport(_ result: Result<[URL], any Error>) async {
        switch result {
        case .success(let urls):
            for url in urls {
                await store.importSubfiles(from: url)
            }
        case .failure(let error):
            store.presentedError = IdentifiableError(error)
        }
    }
}

private struct SubfileManagerRow: View {
    let subfile: Subfile
    let customName: String?
    let zLabel: String
    let isEditingZ: Bool
    @Binding var zStartText: String
    @Binding var zEndText: String
    let onTapZ: () -> Void
    let onCommitZ: () -> Void
    let onCancelZ: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(customName ?? "Subfile \(subfile.id)")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                Text("\(subfile.pointCount) pts")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if isEditingZ {
                HStack(spacing: 8) {
                    Text("\(zLabel):")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextField("Start", text: $zStartText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 80)
                    Text("–")
                    TextField("End", text: $zEndText)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                        .frame(width: 80)
                    Button("OK", action: onCommitZ)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                    Button("Cancel", action: onCancelZ)
                        .controlSize(.mini)
                }
            } else {
                HStack {
                    Text("\(zLabel): \(subfile.zStart, specifier: "%.4g") – \(subfile.zEnd, specifier: "%.4g")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        onTapZ()
                    } label: {
                        Image(systemName: "pencil.circle")
                            .imageScale(.small)
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - DiffPanelView

/// Shows a line-by-line diff of source vs. edited values, filtered to changed values only.
struct DiffPanelView: View {
    @Bindable var store: SPCDocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSubfileIndex: Int = 0
    @State private var showMetadataDiff: Bool = true
    @State private var pointDisplayMode: PointDiffMode = .changesOnly

    enum PointDiffMode: String, CaseIterable, Identifiable {
        case allData     = "All Data"
        case changesOnly = "Changes Only"
        case diffsOnly   = "Diffs (Δ)"
        var id: String { rawValue }
    }

    struct DiffRow: Identifiable {
        let id: Int
        let label: String
        let oldValue: String
        let newValue: String
        let isChanged: Bool
    }

    var body: some View {
        NavigationStack {
            List {
                if showMetadataDiff {
                    metadataDiffSection
                }

                if !store.resolvedSubfiles.isEmpty {
                    Section("Subfile Data") {
                        Picker("Subfile", selection: $selectedSubfileIndex) {
                            ForEach(store.resolvedSubfiles) { sub in
                                Text(store.resolvedSubfileNames[sub.id] ?? "Subfile \(sub.id)")
                                    .tag(sub.id)
                            }
                        }
                        .pickerStyle(.menu)

                        Picker("Show", selection: $pointDisplayMode) {
                            ForEach(PointDiffMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        let rows = pointDiffRows
                        if rows.isEmpty {
                            Text(pointDisplayMode == .allData
                                 ? "No data available"
                                 : "No changes in this subfile")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                        } else {
                            ForEach(rows) { row in
                                DiffRowView(row: row)
                            }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .navigationTitle("Changes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .automatic) {
                    Toggle("Metadata", isOn: $showMetadataDiff)
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                }
            }
        }
    }

    @ViewBuilder
    private var metadataDiffSection: some View {
        let rows = metadataDiffRows
        if rows.isEmpty {
            Section("Metadata") {
                Text("No metadata changes")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        } else {
            Section("Metadata") {
                ForEach(rows) { row in
                    DiffRowView(row: row)
                }
            }
        }
    }

    private var metadataDiffRows: [DiffRow] {
        guard let source = store.sourceFile?.header,
              let resolved = store.resolvedHeader else { return [] }
        var rows: [DiffRow] = []
        var id = 0

        func add(_ label: String, _ old: String, _ new: String) {
            if old != new {
                rows.append(DiffRow(id: id, label: label, oldValue: old, newValue: new, isChanged: true))
                id += 1
            }
        }

        add("Memo", source.memo, store.resolvedMemo)
        add("Experiment Type", "\(source.experimentType)", "\(resolved.experimentType)")
        add("X Units", "\(source.xUnitsCode)", "\(resolved.xUnitsCode)")
        add("Y Units", "\(source.yUnitsCode)", "\(resolved.yUnitsCode)")
        add("Z Units", "\(source.zUnitsCode)", "\(resolved.zUnitsCode)")
        add("Resolution", source.resolutionDescription, resolved.resolutionDescription)
        add("Source Instrument", source.sourceInstrument, resolved.sourceInstrument)
        add("Method File", source.methodFile, resolved.methodFile)
        add("Z Increment", "\(source.zIncrement)", "\(resolved.zIncrement)")
        add("Concentration", "\(source.concentrationFactor)", "\(resolved.concentrationFactor)")
        add("Subfile Count", "\(source.subfileCount)", "\(store.resolvedSubfiles.count)")

        let srcXLabel = store.sourceFile?.axisMetadata.customXLabel ?? ""
        let resXLabel = store.resolvedAxisMetadata?.customXLabel ?? ""
        add("Custom X Label", srcXLabel, resXLabel)
        let srcYLabel = store.sourceFile?.axisMetadata.customYLabel ?? ""
        let resYLabel = store.resolvedAxisMetadata?.customYLabel ?? ""
        add("Custom Y Label", srcYLabel, resYLabel)

        return rows
    }

    private var pointDiffRows: [DiffRow] {
        guard let source = store.sourceFile,
              selectedSubfileIndex < store.resolvedSubfiles.count else { return [] }

        let resSub = store.resolvedSubfiles[selectedSubfileIndex]
        let resX = resSub.resolvedXPoints(
            ffp: store.resolvedAxisMetadata?.firstX ?? source.header.firstX,
            flp: store.resolvedAxisMetadata?.lastX ?? source.header.lastX
        )

        // Source subfile may not exist for newly added subfiles
        let hasSrc = selectedSubfileIndex < source.subfiles.count
        let srcSub = hasSrc ? source.subfiles[selectedSubfileIndex] : nil
        let srcX = srcSub?.resolvedXPoints(ffp: source.header.firstX, flp: source.header.lastX) ?? []
        let srcY = srcSub?.yPoints ?? []

        var rows: [DiffRow] = []
        let maxCount = max(srcY.count, resSub.yPoints.count)
        guard maxCount > 0 else { return [] }

        for i in 0..<maxCount {
            let srcXVal = i < srcX.count ? srcX[i] : Float.nan
            let resXVal = i < resX.count ? resX[i] : Float.nan
            let srcYVal = i < srcY.count ? srcY[i] : Float.nan
            let resYVal = i < resSub.yPoints.count ? resSub.yPoints[i] : Float.nan

            let xChanged = srcXVal != resXVal || srcXVal.isNaN != resXVal.isNaN
            let yChanged = srcYVal != resYVal || srcYVal.isNaN != resYVal.isNaN
            let changed = xChanged || yChanged

            switch pointDisplayMode {
            case .allData:
                let oldStr = hasSrc ? "X: \(fmt(srcXVal))  Y: \(fmt(srcYVal))" : "—"
                let newStr = "X: \(fmt(resXVal))  Y: \(fmt(resYVal))"
                rows.append(DiffRow(id: i, label: "[\(i)]",
                                    oldValue: oldStr, newValue: newStr,
                                    isChanged: changed))

            case .changesOnly:
                if changed {
                    let oldStr = hasSrc ? "X: \(fmt(srcXVal))  Y: \(fmt(srcYVal))" : "—"
                    let newStr = "X: \(fmt(resXVal))  Y: \(fmt(resYVal))"
                    rows.append(DiffRow(id: i, label: "[\(i)]",
                                        oldValue: oldStr, newValue: newStr,
                                        isChanged: true))
                }

            case .diffsOnly:
                if changed {
                    let dx = resXVal - srcXVal
                    let dy = resYVal - srcYVal
                    let deltaStr = "ΔX: \(fmt(dx))  ΔY: \(fmt(dy))"
                    let newStr = "X: \(fmt(resXVal))  Y: \(fmt(resYVal))"
                    rows.append(DiffRow(id: i, label: "[\(i)]",
                                        oldValue: deltaStr, newValue: newStr,
                                        isChanged: true))
                }
            }
        }
        return rows
    }

    private func fmt(_ v: Float) -> String {
        v.isNaN ? "—" : String(format: "%.6g", v)
    }
}

private struct DiffRowView: View {
    let row: DiffPanelView.DiffRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(row.label)
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            HStack(alignment: .top) {
                VStack(alignment: .leading) {
                    Text("Old")
                        .font(.caption2)
                        .foregroundStyle(row.isChanged ? .red : .secondary)
                    Text(row.oldValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(row.isChanged ? .red.opacity(0.8) : .secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading) {
                    Text("New")
                        .font(.caption2)
                        .foregroundStyle(row.isChanged ? .green : .secondary)
                    Text(row.newValue)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(row.isChanged ? .green.opacity(0.8) : .secondary.opacity(0.6))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 2)
        .opacity(row.isChanged ? 1.0 : 0.6)
    }
}
