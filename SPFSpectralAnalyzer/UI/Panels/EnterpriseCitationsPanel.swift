import SwiftUI

// MARK: - Enterprise Citations Panel

/// Collapsible panel displaying enterprise grounding citations from the M365 Retrieval API.
/// Shows document titles, authors, extracts, relevance scores, sensitivity labels, and source links.
struct EnterpriseCitationsPanel: View {
    let citations: [GroundingCitation]
    @State private var isExpanded = true
    @State private var expandedCitationIDs: Set<UUID> = []

    var body: some View {
        if !citations.isEmpty {
            DisclosureGroup(isExpanded: $isExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(citations) { citation in
                        citationCard(citation)
                    }
                }
                .padding(.top, 4)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "building.2.fill")
                        .foregroundStyle(.blue)
                    Text("Enterprise Sources")
                        .font(.headline)
                    Text("\(citations.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                }
            }
        }
    }

    // MARK: - Citation Card

    @ViewBuilder
    private func citationCard(_ citation: GroundingCitation) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // Title + Source Icon
            HStack(spacing: 6) {
                Image(systemName: citation.dataSource.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(citation.title)
                    .font(.subheadline.bold())
                    .lineLimit(2)

                Spacer()

                if let score = citation.relevanceScore {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            // Author
            if let author = citation.author {
                Text("by \(author)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sensitivity Label
            if let label = citation.sensitivityLabel, let displayName = label.displayName {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                    Text(displayName)
                        .font(.caption2)
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }

            // Extract Text (expandable)
            if !citation.extractText.isEmpty {
                let isExpanded = expandedCitationIDs.contains(citation.id)
                Text(citation.extractText)
                    .font(.caption)
                    .foregroundStyle(.primary.opacity(0.8))
                    .lineLimit(isExpanded ? nil : 3)
                    .onTapGesture {
                        withAnimation {
                            if expandedCitationIDs.contains(citation.id) {
                                expandedCitationIDs.remove(citation.id)
                            } else {
                                expandedCitationIDs.insert(citation.id)
                            }
                        }
                    }
            }

            // Source Link
            if let urlString = citation.webUrl, let url = URL(string: urlString) {
                Link(destination: url) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right.square")
                            .font(.caption2)
                        Text("Open in \(citation.dataSource.displayName)")
                            .font(.caption)
                    }
                }
            }
        }
        .padding(8)
        .background(Color.blue.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.blue.opacity(0.15), lineWidth: 1)
        )
    }
}
