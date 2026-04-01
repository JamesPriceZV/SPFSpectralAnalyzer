#if os(iOS)
import SwiftUI

// MARK: - iOS Reporting Panel

extension ContentView {

    /// A Liquid Glass–styled reporting view for iOS, replacing the plain exportPanel.
    var iOSReportingPanel: some View {
        ScrollView {
            VStack(spacing: 20) {
                // MARK: Quick Actions — Glass Button Grid
                quickActionGrid

                // MARK: Report Options
                reportOptionsSection

                // MARK: Data Export Formats
                dataExportSection
            }
            .padding()
        }
        .navigationTitle("Reporting")
    }

    // MARK: - Quick Action Grid

    private var quickActionGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Reports")
                .font(.headline)

            let options = currentExportOptions

            GlassEffectContainer(spacing: 12) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    Button {
                        exportPDFReport(options: options)
                    } label: {
                        Label("PDF Report", systemImage: "doc.richtext")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(displayedSpectra.isEmpty)

                    Button {
                        exportHTMLReport(options: options)
                    } label: {
                        Label {
                            Text("HTML Report")
                        } icon: {
                            Image(systemName: "globe")
                        }
                        .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glass)
                    .tint(.indigo)
                    .disabled(displayedSpectra.isEmpty)

                    ShareButton(
                        items: [analysis.displayedSpectra.map { $0.name }.joined(separator: "\n")],
                        label: "Share Summary",
                        systemImage: "square.and.arrow.up"
                    )
                    .frame(maxWidth: .infinity, minHeight: 52)
                    .buttonStyle(.glass)
                    .disabled(displayedSpectra.isEmpty)

                    Button {
                        exportPeaksCSV()
                    } label: {
                        Label("Peak Data", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(.glass)
                    .tint(.orange)
                    .disabled(displayedSpectra.isEmpty || analysis.peaks.isEmpty)
                }
            }

            Text("Includes charts, metrics, and AI recommendations when available.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Report Options

    private var reportOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Report Options")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                TextField("Title", text: $exportTitle)
                    .textFieldStyle(.roundedBorder)
                TextField("Operator", text: $exportOperator)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $exportNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(3, reservesSpace: true)
                Toggle("Include Processing Settings", isOn: $exportIncludeProcessing)
                Toggle("Include Metadata", isOn: $exportIncludeMetadata)
            }
            .padding(12)
            .glassClearSurface(cornerRadius: 12)
        }
    }

    // MARK: - Data Export Formats

    private var dataExportSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Data Export")
                .font(.headline)

            let options = currentExportOptions

            VStack(spacing: 1) {
                exportRow(title: "CSV", icon: "tablecells", detail: "Spectral data + metadata") {
                    exportCSV(options: options)
                }
                exportRow(title: "JCAMP-DX", icon: "waveform", detail: "Standard spectral format") {
                    exportJCAMP(options: options)
                }
                exportRow(title: "Excel (.xlsx)", icon: "tablecells.badge.ellipsis", detail: "Spreadsheet with metadata") {
                    exportExcelXLSX(options: options)
                }
                exportRow(title: "Word (.docx)", icon: "doc.text", detail: "Full analysis report") {
                    exportWordDOCX(options: options)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .glassClearSurface(cornerRadius: 12)
        }
    }

    // MARK: - Helpers

    private var currentExportOptions: ExportOptions {
        ExportOptions(
            title: exportTitle,
            operatorName: exportOperator,
            notes: exportNotes,
            includeProcessing: exportIncludeProcessing,
            includeMetadata: exportIncludeMetadata
        )
    }

    private func exportRow(title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                        Text(detail)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                } icon: {
                    Image(systemName: icon)
                        .foregroundColor(.accentColor)
                        .frame(width: 24)
                }
                Spacer()
                Image(systemName: "arrow.down.doc")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(displayedSpectra.isEmpty)
    }
}
#endif
