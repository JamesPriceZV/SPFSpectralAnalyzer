import SwiftUI

// MARK: - Enterprise Search View

/// Standalone enterprise search interface for the Enterprise tab.
/// Allows direct querying of SharePoint, OneDrive, and Copilot Connectors
/// via the Microsoft 365 Copilot Retrieval API.
struct EnterpriseSearchView: View {
    @State private var viewModel: EnterpriseSearchViewModel
    @State private var showExportSheet = false
    @State private var selectedCitationID: GroundingCitation.ID?
    @State private var browseMode = false

    /// Which Enterprise sub-feature is active.
    enum EnterpriseTab: String, CaseIterable, Identifiable {
        case search = "Search"
        case teams = "Teams"
        var id: String { rawValue }
    }

    @State private var activeTab: EnterpriseTab = .search
    private let authManager: MSALAuthManager

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(authManager: MSALAuthManager) {
        self.authManager = authManager
        _viewModel = State(initialValue: EnterpriseSearchViewModel(authManager: authManager))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Enterprise sub-tab picker
            Picker("Enterprise", selection: $activeTab) {
                ForEach(EnterpriseTab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab == .search ? "magnifyingglass" : "bubble.left.and.text.bubble.right")
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            switch activeTab {
            case .search:
                if browseMode {
                    EnterpriseFileBrowserView(authManager: authManager)
                } else {
                    searchBody
                }
            case .teams:
                TeamsView(authManager: authManager)
            }
        }
    }

    @ViewBuilder
    private var searchBody: some View {
        #if os(iOS)
        if sizeClass == .regular {
            iPadLayout
        } else {
            compactLayout
        }
        #else
        compactLayout
        #endif
    }

    // MARK: - iPad Layout

    #if os(iOS)
    private var iPadLayout: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                headerSection
                    .padding()
                Divider()
                if viewModel.authManager.isSignedIn {
                    querySection
                        .padding()
                    Divider()
                    if viewModel.isLoading {
                        ProgressView("Searching...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.citations.isEmpty {
                        ContentUnavailableView(
                            "No Results",
                            systemImage: "magnifyingglass",
                            description: Text("Enter a query to search.")
                        )
                    } else {
                        List(viewModel.citations, selection: $selectedCitationID) { citation in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: citation.dataSource.iconName)
                                        .foregroundStyle(.blue)
                                        .font(.caption)
                                    Text(citation.title)
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                if let author = citation.author {
                                    Text(author)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .tag(citation.id)
                        }
                    }
                } else {
                    signInPrompt
                }
            }
            .navigationTitle("Enterprise")
        } detail: {
            if let citationID = selectedCitationID,
               let citation = viewModel.citations.first(where: { $0.id == citationID }) {
                ScrollView {
                    enterpriseResultCard(citation)
                        .padding()
                }
                .navigationTitle(citation.title)
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView(
                    "Select a Result",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Choose a search result to view details.")
                )
            }
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

    // MARK: - Compact / macOS Layout

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding()

            Divider()

            if viewModel.authManager.isSignedIn {
                searchContent
            } else {
                signInPrompt
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Microsoft 365 Enterprise Search")
                    .font(.title2.bold())

                if viewModel.authManager.isSignedIn {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.green)
                            .frame(width: 8, height: 8)
                        Text("Signed in as \(viewModel.authManager.currentUsername() ?? "Unknown")")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.secondary)
                            .frame(width: 8, height: 8)
                        Text("Not signed in")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if viewModel.authManager.isSignedIn {
                // Search / Browse toggle
                if activeTab == .search {
                    Picker("Mode", selection: $browseMode) {
                        Label("Search", systemImage: "magnifyingglass").tag(false)
                        Label("Browse", systemImage: "folder").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }

                Button {
                    showExportSheet = true
                } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)

                Button("Sign Out") {
                    Task { await viewModel.signOut() }
                }
                .buttonStyle(.bordered)
            } else {
                Button("Sign In to M365") {
                    Task { await viewModel.signIn() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .sheet(isPresented: $showExportSheet) {
            SharePointExportView(authManager: viewModel.authManager)
        }
    }

    // MARK: - Sign-In Prompt

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "building.2.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in to Microsoft 365")
                .font(.title3.bold())
            Text("Search your organization's SharePoint, OneDrive, and connected enterprise systems for SOPs, protocols, formulation records, and more.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button("Sign In") {
                Task { await viewModel.signIn() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Search Content

    private var searchContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Query section
            querySection
                .padding()

            Divider()

            // Results
            if viewModel.isLoading {
                VStack {
                    Spacer()
                    ProgressView("Searching enterprise content...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if let error = viewModel.errorMessage, viewModel.citations.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else if viewModel.citations.isEmpty {
                VStack {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundStyle(.secondary)
                    Text("Enter a query to search your enterprise content")
                        .font(.body)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                resultsList
            }
        }
    }

    // MARK: - Query Section

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Query text field
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search enterprise documents...", text: $viewModel.query, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await viewModel.search() } }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                // Data source picker
                Picker("Source", selection: $viewModel.selectedDataSource) {
                    ForEach(RetrievalDataSource.allCases) { source in
                        Label(source.displayName, systemImage: source.iconName)
                            .tag(source)
                    }
                }
                .pickerStyle(.segmented)

                // Site filter (SharePoint only)
                if viewModel.selectedDataSource == .sharePoint {
                    TextField("Site path filter (optional)", text: $viewModel.sitePathFilter)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
            }

            HStack {
                Button {
                    Task { await viewModel.search() }
                } label: {
                    Label("Search", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isLoading || viewModel.query.isEmpty)

                Button {
                    Task { await viewModel.searchAllSources() }
                } label: {
                    Label("Search All Sources", systemImage: "rectangle.stack.fill")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading || viewModel.query.isEmpty)

                if !viewModel.citations.isEmpty {
                    Button("Clear") {
                        viewModel.clearResults()
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                Text("\(viewModel.citations.count) results")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Results List

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.citations) { citation in
                    enterpriseResultCard(citation)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func enterpriseResultCard(_ citation: GroundingCitation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title row
            HStack(spacing: 8) {
                Image(systemName: citation.dataSource.iconName)
                    .foregroundStyle(.blue)

                Text(citation.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                if let score = citation.relevanceScore {
                    Text(String(format: "%.0f%%", score * 100))
                        .font(.caption.monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }
            }

            // Author + Source
            HStack(spacing: 12) {
                if let author = citation.author {
                    Label(author, systemImage: "person")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Label(citation.dataSource.displayName, systemImage: citation.dataSource.iconName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // Sensitivity label
            if let label = citation.sensitivityLabel, let name = label.displayName {
                HStack(spacing: 4) {
                    Image(systemName: "lock.shield.fill")
                        .font(.caption2)
                    Text(name)
                        .font(.caption2)
                    if let tooltip = label.toolTip {
                        Text("— \(tooltip)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }

            // Extract text
            if !citation.extractText.isEmpty {
                Text(citation.extractText)
                    .font(.body)
                    .foregroundStyle(.primary.opacity(0.85))
                    .lineLimit(6)
                    .padding(8)
                    .background(Color.primary.opacity(0.03))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            // Actions
            HStack(spacing: 12) {
                if let urlString = citation.webUrl, let url = URL(string: urlString) {
                    Link(destination: url) {
                        Label("Open in \(citation.dataSource.displayName)", systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                }

                #if canImport(AppKit)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(citation.extractText, forType: .string)
                } label: {
                    Label("Copy Extract", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                #endif
            }
        }
        .padding(12)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
