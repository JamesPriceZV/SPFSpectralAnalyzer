// SpectrumChartView.swift
// SPCKit
//
// Swift Charts LineMark view for displaying spectral data.
// Supports pinch-to-zoom (MagnifyGesture), drag-to-pan, double-tap reset,
// multi-subfile overlay when multiple subfiles are selected,
// and an optional before/after overlay for transform previews.

import SwiftUI
import Charts

struct SpectrumChartView: View {
    @Bindable var store: SPCDocumentStore

    /// Optional "before" Y values to show as a dimmed overlay during transform preview.
    var previewBeforeYPoints: [Float]?

    // MARK: - Zoom / Pan state

    @State private var zoomLevel: CGFloat = 1.0
    @State private var lastZoomLevel: CGFloat = 1.0

    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    // MARK: - Series colors

    private static let seriesColors: [Color] = [
        .blue, .red, .green, .orange, .purple, .cyan, .pink, .yellow, .mint, .indigo
    ]

    // MARK: - Derived data

    /// All subfiles that should be displayed (selected ones, or focused if none selected).
    private var displayedSubfiles: [Subfile] {
        let selected = store.selectedSubfileIndices
        let subs = store.resolvedSubfiles.filter { selected.contains($0.id) }
        if !subs.isEmpty { return subs }
        // Fallback to focused subfile
        if let focused = store.resolvedSubfiles.first(where: { $0.id == store.focusedSubfileIndex }) {
            return [focused]
        }
        return Array(store.resolvedSubfiles.prefix(1))
    }

    private var xLabel: String { store.resolvedAxisMetadata?.xLabel ?? "X" }
    private var yLabel: String { store.resolvedAxisMetadata?.yLabel ?? "Y" }

    private func xPoints(for subfile: Subfile) -> [Float] {
        subfile.resolvedXPoints(
            ffp: store.resolvedAxisMetadata?.firstX ?? store.sourceFile?.header.firstX ?? 0,
            flp: store.resolvedAxisMetadata?.lastX ?? store.sourceFile?.header.lastX ?? 1
        )
    }

    private func displayName(for subfile: Subfile) -> String {
        store.resolvedSubfileNames[subfile.id] ?? "Subfile \(subfile.id)"
    }

    // MARK: - Visible domain (zoom + pan)

    private var fullXRange: ClosedRange<Double> {
        var allX: [Float] = []
        for sf in displayedSubfiles {
            let xs = xPoints(for: sf)
            if let lo = xs.first { allX.append(lo) }
            if let hi = xs.last { allX.append(hi) }
        }
        guard let lo = allX.min(), let hi = allX.max(), lo < hi else {
            return 0...1
        }
        return Double(lo)...Double(hi)
    }

    private var visibleXRange: ClosedRange<Double> {
        let full = fullXRange
        let span = (full.upperBound - full.lowerBound) / zoomLevel
        let center = (full.lowerBound + full.upperBound) / 2
        let panFraction = panOffset.width / 500
        let offset = span * panFraction
        let lo = center - span / 2 - offset
        let hi = center + span / 2 - offset
        return lo...hi
    }

    private var fullYRange: ClosedRange<Double> {
        var allY: [Float] = []
        for sf in displayedSubfiles {
            allY.append(contentsOf: sf.yPoints)
        }
        guard let lo = allY.min(), let hi = allY.max(), lo < hi else {
            return 0...1
        }
        let margin = Double(hi - lo) * 0.05
        return Double(lo) - margin ... Double(hi) + margin
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            chartHeader
            chart
                .gesture(magnifyGesture)
                .gesture(dragGesture)
                .onTapGesture(count: 2) { resetZoom() }
                .padding()
        }
    }

    // MARK: - Header

    private var chartHeader: some View {
        HStack {
            if displayedSubfiles.count == 1 {
                Text(displayName(for: displayedSubfiles[0]))
                    .font(.headline)
            } else {
                Text("\(displayedSubfiles.count) subfiles")
                    .font(.headline)
            }
            Spacer()
            if zoomLevel > 1.01 {
                Button("Reset Zoom") { resetZoom() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            if displayedSubfiles.count == 1 {
                Text("\(displayedSubfiles[0].pointCount) points")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Before overlay (dimmed, when transform preview is active)
            if let beforeY = previewBeforeYPoints,
               let focused = displayedSubfiles.first,
               beforeY.count == xPoints(for: focused).count {
                let xs = xPoints(for: focused)
                ForEach(Array(zip(xs, beforeY).enumerated()), id: \.offset) { _, pair in
                    LineMark(
                        x: .value(xLabel, Double(pair.0)),
                        y: .value(yLabel, Double(pair.1)),
                        series: .value("Series", "Before")
                    )
                    .foregroundStyle(.gray.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                }
            }

            // All displayed subfiles
            ForEach(Array(displayedSubfiles.enumerated()), id: \.element.id) { idx, subfile in
                let xs = xPoints(for: subfile)
                let name = displayName(for: subfile)
                let color = Self.seriesColors[idx % Self.seriesColors.count]
                ForEach(Array(zip(xs, subfile.yPoints).enumerated()), id: \.offset) { _, pair in
                    LineMark(
                        x: .value(xLabel, Double(pair.0)),
                        y: .value(yLabel, Double(pair.1)),
                        series: .value("Series", name)
                    )
                    .foregroundStyle(color)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
        }
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .chartXScale(domain: visibleXRange)
        .chartYScale(domain: fullYRange)
        .chartLegend(displayedSubfiles.count > 1 || previewBeforeYPoints != nil ? .visible : .hidden)
    }

    // MARK: - Gestures

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = lastZoomLevel * value.magnification
                zoomLevel = min(max(proposed, 1.0), 50.0)
            }
            .onEnded { _ in
                lastZoomLevel = zoomLevel
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    private func resetZoom() {
        withAnimation(.easeOut(duration: 0.3)) {
            zoomLevel = 1.0
            lastZoomLevel = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }
}
