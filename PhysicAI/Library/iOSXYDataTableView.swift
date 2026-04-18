// iOSXYDataTableView.swift
// PhysicAI
//
// iOS-friendly replacement for XYDataTableView which uses SwiftUI Table
// (Table only shows the first column in compact width on iPhone).
// This view uses a List with HStack rows to show Index, X, and Y values.

#if os(iOS)
import SwiftUI

struct iOSXYDataTableView: View {
    @Bindable var store: SPCDocumentStore
    @State private var searchText: String = ""

    private var sourceFile: SPCFile? { store.sourceFile }

    private var displayedSubfile: Subfile? {
        let selected = store.selectedSubfileIndices
        if let first = store.resolvedSubfiles.first(where: { selected.contains($0.id) }) {
            return first
        }
        if let focused = store.resolvedSubfiles.first(where: { $0.id == store.focusedSubfileIndex }) {
            return focused
        }
        return store.resolvedSubfiles.first
    }

    private struct PointRow: Identifiable {
        let index: Int
        let x: Float
        let y: Float
        var id: Int { index }
    }

    private func displayedPoints() -> [PointRow] {
        guard let sf = displayedSubfile else { return [] }
        let ffp = store.resolvedAxisMetadata?.firstX ?? sourceFile?.header.firstX ?? 0
        let flp = store.resolvedAxisMetadata?.lastX ?? sourceFile?.header.lastX ?? 1
        let xs = sf.resolvedXPoints(ffp: ffp, flp: flp)
        let rows = zip(xs, sf.yPoints).enumerated().map { (idx, pair) in
            PointRow(index: idx, x: pair.0, y: pair.1)
        }
        if searchText.isEmpty { return rows }
        if let idx = Int(searchText) {
            return rows.filter { $0.index == idx }
        }
        return rows
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(store.resolvedSubfileNames[store.focusedSubfileIndex]
                     ?? "Subfile \(store.focusedSubfileIndex)")
                    .font(.headline)
                Spacer()
                Text("\(displayedSubfile?.pointCount ?? 0) pts")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Filter by index…", text: $searchText)
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

            // Column headers
            HStack(spacing: 0) {
                Text("#")
                    .font(.caption.weight(.semibold))
                    .frame(width: 44, alignment: .leading)
                Text("X")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                Text("Y")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(.quinary)

            Divider()

            // Data rows
            let points = displayedPoints()
            if points.isEmpty {
                ContentUnavailableView("No Data", systemImage: "tablecells")
                    .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(points) { row in
                            HStack(spacing: 0) {
                                Text("\(row.index)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .leading)
                                Text(String(format: "%.4g", row.x))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                Text(String(format: "%.4g", row.y))
                                    .font(.system(.caption, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 3)

                            if row.index < points.count - 1 {
                                Divider().padding(.leading, 12)
                            }
                        }
                    }
                }
            }
        }
    }
}
#endif
