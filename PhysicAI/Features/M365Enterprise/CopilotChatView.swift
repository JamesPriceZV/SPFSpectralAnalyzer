import SwiftUI

// MARK: - Copilot Chat View

/// Copilot-style enterprise chat interface with Work|Web scope toggle,
/// conversational message bubbles, citation cards, and suggestion chips.
struct CopilotChatView: View {
    @State private var viewModel: CopilotChatViewModel

    init(authManager: MSALAuthManager) {
        _viewModel = State(initialValue: CopilotChatViewModel(authManager: authManager))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Scope toggle
                scopeToggle
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                // Messages or empty state
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    messageList
                }

                Divider()

                // Compose bar
                composeBar
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            .navigationTitle("Copilot | M365")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if !viewModel.messages.isEmpty {
                        Button {
                            viewModel.clearConversation()
                        } label: {
                            Label("New Chat", systemImage: "plus.message")
                        }
                    }
                }
            }
        }
    }

    // MARK: - Scope Toggle

    private var scopeToggle: some View {
        Picker("Scope", selection: $viewModel.scope) {
            ForEach(CopilotChatViewModel.Scope.allCases) { scope in
                Text(scope.rawValue).tag(scope)
            }
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 200)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 40)

                Image(systemName: "sparkle")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("How can I help?")
                    .font(.title2.bold())

                Text("Search your Microsoft 365 content using natural language.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)

                // Suggestion chips
                suggestionChips

                Spacer(minLength: 40)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var suggestionChips: some View {
        VStack(spacing: 8) {
            ForEach(viewModel.defaultSuggestions, id: \.self) { suggestion in
                Button {
                    Task { await viewModel.sendSuggestion(suggestion) }
                } label: {
                    HStack {
                        Image(systemName: "sparkle")
                            .font(.caption)
                        Text(suggestion)
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "arrow.up.circle")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 380)
                }
                .buttonStyle(.glass)
            }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.messages) { message in
                        messageRow(message)
                            .id(message.id)
                    }

                    if viewModel.isSearching {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Searching...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
            .scrollEdgeEffectStyle(.soft, for: .bottom)
            .onChange(of: viewModel.messages.count) { _, _ in
                if let lastMessage = viewModel.messages.last {
                    withAnimation {
                        proxy.scrollTo(lastMessage.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func messageRow(_ message: CopilotMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message)
        case .copilot:
            copilotBubble(message)
        }
    }

    // MARK: - User Bubble

    private func userBubble(_ message: CopilotMessage) -> some View {
        HStack {
            Spacer(minLength: 60)
            VStack(alignment: .trailing, spacing: 4) {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.trailing, 16)
        }
    }

    // MARK: - Copilot Bubble

    private func copilotBubble(_ message: CopilotMessage) -> some View {
        HStack(alignment: .top, spacing: 8) {
            // Copilot avatar
            Image(systemName: "sparkle")
                .font(.caption)
                .foregroundStyle(.tint)
                .frame(width: 28, height: 28)
                .background(.tint.opacity(0.1))
                .clipShape(Circle())
                .padding(.leading, 12)

            VStack(alignment: .leading, spacing: 8) {
                Text(message.text)
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .rect(cornerRadius: 16))

                // Citation cards
                if !message.citations.isEmpty {
                    citationCards(message.citations)
                }

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 60)
        }
    }

    // MARK: - Citation Cards

    private func citationCards(_ citations: [GroundingCitation]) -> some View {
        VStack(spacing: 6) {
            ForEach(citations) { citation in
                citationCard(citation)
            }
        }
    }

    private func citationCard(_ citation: GroundingCitation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: citationIcon(for: citation.dataSource))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(citation.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Spacer()
                if let score = citation.relevanceScore {
                    Text("\(Int(score * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            HStack(spacing: 8) {
                Text(citation.dataSource.displayName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if let author = citation.author, !author.isEmpty {
                    Text(author)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            if !citation.extractText.isEmpty {
                Text(citation.extractText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if let url = citation.webUrl, let webURL = URL(string: url) {
                Link(destination: webURL) {
                    Label("Open in source", systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
            }
        }
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 12))
    }

    private func citationIcon(for source: RetrievalDataSource) -> String {
        switch source {
        case .sharePoint: return "building.2"
        case .oneDriveBusiness: return "cloud"
        case .externalItem: return "link"
        }
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $viewModel.inputText, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)
                .onSubmit {
                    Task { await viewModel.send() }
                }

            Button {
                Task { await viewModel.send() }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
            }
            .disabled(viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSearching)
            .buttonStyle(.plain)
        }
    }
}
