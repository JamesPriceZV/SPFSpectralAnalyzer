import SwiftUI

extension ContentView {

    var exportFormFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Title", text: $exportTitle)
                .accessibilityIdentifier("exportTitleField")
            TextField("Operator", text: $exportOperator)
                .accessibilityIdentifier("exportOperatorField")
            TextField("Notes", text: $exportNotes, axis: .vertical)
                .lineLimit(3, reservesSpace: true)
                .accessibilityIdentifier("exportNotesField")
            Toggle("Include Processing Settings", isOn: $exportIncludeProcessing)
            Toggle("Include Metadata", isOn: $exportIncludeMetadata)
        }
        .padding(12)
        .background(panelBackground)
        .cornerRadius(12)
    }

    var quickReportPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Quick Reports")
                .font(.headline)

            #if os(iOS)
            VStack(spacing: 10) {
                Button {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    exportPDFReport(options: options)
                } label: {
                    Label("Export PDF Report", systemImage: "doc.richtext")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("exportPDFButton")
                .disabled(displayedSpectra.isEmpty)

                Button {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    exportHTMLReport(options: options)
                } label: {
                    Label("Export HTML Report", systemImage: "globe")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.indigo)
                .accessibilityIdentifier("exportHTMLButton")
                .disabled(displayedSpectra.isEmpty)

                ShareButton(
                    items: [analysis.displayedSpectra.map { $0.name }.joined(separator: "\n")],
                    label: "Share Summary",
                    systemImage: "square.and.arrow.up"
                )
                .buttonStyle(.bordered)
                .disabled(displayedSpectra.isEmpty)
            }
            #else
            HStack(spacing: 12) {
                Button("Export PDF Report") {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    exportPDFReport(options: options)
                }
                .accessibilityIdentifier("exportPDFButton")
                .disabled(displayedSpectra.isEmpty)

                Button("Export HTML Report") {
                    let options = ExportOptions(
                        title: exportTitle,
                        operatorName: exportOperator,
                        notes: exportNotes,
                        includeProcessing: exportIncludeProcessing,
                        includeMetadata: exportIncludeMetadata
                    )
                    exportHTMLReport(options: options)
                }
                .accessibilityIdentifier("exportHTMLButton")
                .disabled(displayedSpectra.isEmpty)

                ShareButton(
                    items: [analysis.displayedSpectra.map { $0.name }.joined(separator: "\n")],
                    label: "Share Summary",
                    systemImage: "square.and.arrow.up"
                )
                .disabled(displayedSpectra.isEmpty)
            }
            .glassButtonStyle(isProminent: true)
            #endif

            Text("Includes charts, metrics, and AI recommendations when available.")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        #if os(macOS)
        .background(panelBackground)
        #else
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemGroupedBackground)))
        #endif
        .cornerRadius(12)
    }

}
