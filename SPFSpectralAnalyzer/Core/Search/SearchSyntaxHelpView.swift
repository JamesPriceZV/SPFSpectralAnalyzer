import SwiftUI

/// Context for the search syntax help: determines which field prefixes are shown.
enum SearchHelpContext {
    case dataset
    case spectrum
}

/// Compact popover view showing available boolean search syntax and field prefixes.
struct SearchSyntaxHelpView: View {
    let context: SearchHelpContext

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Search Syntax")
                    .font(.headline)

                // Operators
                VStack(alignment: .leading, spacing: 4) {
                    Text("Boolean Operators")
                        .font(.subheadline.bold())
                    syntaxRow("AND", "Implicit between terms, or explicit")
                    syntaxRow("OR", "Match either term")
                    syntaxRow("NOT / -", "Exclude matches")
                    syntaxRow("\"...\"", "Exact phrase match")
                    syntaxRow("( )", "Group expressions")
                }

                Divider()

                // Field prefixes
                VStack(alignment: .leading, spacing: 4) {
                    Text("Field Filters")
                        .font(.subheadline.bold())

                    switch context {
                    case .dataset:
                        syntaxRow("name:", "File name")
                        syntaxRow("role:", "reference, prototype, or none")
                        syntaxRow("spf:", "Known SPF value (e.g., spf:>30)")
                        syntaxRow("date:", "Import date (e.g., date:>2025-01-01)")
                        syntaxRow("spectra:", "Spectrum count (e.g., spectra:>5)")
                        syntaxRow("memo:", "SPC header memo field")
                        syntaxRow("instrument:", "Source instrument")
                        syntaxRow("hash:", "File content hash")
                        syntaxRow("path:", "Source file path")
                    case .spectrum:
                        syntaxRow("name:", "Spectrum name")
                        syntaxRow("tag:", "Auto-tag or HDRS tag")
                        syntaxRow("plate:", "HDRS plate type (moulded/sandblasted)")
                        syntaxRow("irr:", "Irradiation state (pre/post)")
                        syntaxRow("sample:", "HDRS sample name")
                    }
                }

                Divider()

                // Examples
                VStack(alignment: .leading, spacing: 4) {
                    Text("Examples")
                        .font(.subheadline.bold())

                    switch context {
                    case .dataset:
                        exampleRow("cerave", "Search all fields (current behavior)")
                        exampleRow("role:reference spf:>30", "References with SPF above 30")
                        exampleRow("\"commercial formula\"", "Exact phrase match")
                        exampleRow("-role:reference", "Exclude references")
                        exampleRow("date:>2025-01-01 spectra:>5", "Recent, multi-spectrum datasets")
                    case .spectrum:
                        exampleRow("cerva", "Search name and tags")
                        exampleRow("tag:Post-Irr OR tag:Blank", "Either tag")
                        exampleRow("name:cerva NOT tag:Control", "Name match, exclude controls")
                        exampleRow("plate:moulded irr:post", "HDRS filters")
                        exampleRow("sample:\"CeraVe SPF 30\"", "Exact sample name")
                    }
                }

                Text("Unquoted terms search all fields.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(16)
        }
        .frame(width: 340, height: 420)
    }

    private func syntaxRow(_ prefix: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(prefix)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.accentColor)
                .frame(width: 90, alignment: .leading)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func exampleRow(_ query: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(query)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
