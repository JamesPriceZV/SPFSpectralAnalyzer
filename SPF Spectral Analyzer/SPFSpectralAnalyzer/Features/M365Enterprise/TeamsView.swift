import SwiftUI

// MARK: - Teams View

/// Microsoft Teams interface for browsing teams, channels, chats, and sending messages.
/// Integrated into the Enterprise tab alongside Enterprise Search.
struct TeamsView: View {
    @State private var viewModel: TeamsViewModel

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    init(authManager: MSALAuthManager) {
        _viewModel = State(initialValue: TeamsViewModel(authManager: authManager))
    }

    var body: some View {
        Group {
            if !viewModel.authManager.isSignedIn {
                teamsSignInPrompt
            } else {
                #if os(iOS)
                if sizeClass == .regular {
                    iPadTeamsLayout
                } else {
                    compactTeamsLayout
                }
                #else
                compactTeamsLayout
                #endif
            }
        }
        .task {
            guard viewModel.authManager.isSignedIn else { return }
            // Start sync monitor if enabled
            if viewModel.isSyncEnabled {
                TeamsSyncMonitor.shared.start(authManager: viewModel.authManager)
            }
            await viewModel.loadTeams()
            await viewModel.loadChats()
        }
    }

    // MARK: - Sign-In Prompt

    private var teamsSignInPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "bubble.left.and.text.bubble.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in to use Teams")
                .font(.title3.bold())
            Text("Sign in from the Enterprise Search tab to access Microsoft Teams messaging.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - iPad Layout

    #if os(iOS)
    private var iPadTeamsLayout: some View {
        NavigationSplitView {
            teamsSidebar
                .navigationTitle("Teams")
                .navigationSplitViewColumnWidth(min: 260, ideal: 320, max: .infinity)
        } detail: {
            messagesDetail
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

    // MARK: - Compact Layout

    @State private var showMessages = false

    private var compactTeamsLayout: some View {
        NavigationStack {
            teamsSidebar
                .navigationTitle("Teams")
                .navigationDestination(isPresented: $showMessages) {
                    messagesDetail
                        .navigationTitle(messageDetailTitle)
                        #if os(iOS)
                        .navigationBarTitleDisplayMode(.inline)
                        #endif
                }
        }
    }

    private var messageDetailTitle: String {
        viewModel.selectedChannel?.displayName
            ?? viewModel.selectedChat?.displayName
            ?? "Messages"
    }

    // MARK: - Sidebar

    private var teamsSidebar: some View {
        List {
            // Sync status section
            if viewModel.isSyncEnabled {
                Section {
                    HStack(spacing: 8) {
                        if viewModel.isSyncing {
                            ProgressView()
                                .controlSize(.small)
                            Text("Syncing...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let date = viewModel.lastSyncDate {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .font(.caption)
                            Text("Synced \(date, format: .relative(presentation: .named))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Sync enabled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Sync Now") {
                            Task { await viewModel.syncNow() }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(viewModel.isSyncing)
                    }
                    .listRowBackground(Color.clear)
                }
            }

            // Mode picker
            Section {
                Picker("View", selection: $viewModel.sidebarMode) {
                    ForEach(TeamsViewModel.SidebarMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            }

            if viewModel.isLoading && viewModel.teams.isEmpty && viewModel.chats.isEmpty {
                Section {
                    HStack {
                        Spacer()
                        ProgressView("Loading...")
                        Spacer()
                    }
                }
            }

            if let error = viewModel.errorMessage {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            switch viewModel.sidebarMode {
            case .teams:
                teamsListSection
            case .chats:
                chatsListSection
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.sidebar)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // Sync toggle
                Button {
                    viewModel.toggleSync()
                } label: {
                    Label(
                        viewModel.isSyncEnabled ? "Sync On" : "Sync Off",
                        systemImage: viewModel.isSyncEnabled
                            ? "arrow.triangle.2.circlepath.circle.fill"
                            : "arrow.triangle.2.circlepath.circle"
                    )
                }
                .help(viewModel.isSyncEnabled ? "Disable Teams sync" : "Enable Teams sync")

                // Manual refresh
                Button {
                    Task {
                        await viewModel.loadTeams()
                        await viewModel.loadChats()
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
        }
    }

    // MARK: - Teams List

    private var teamsListSection: some View {
        Group {
            if viewModel.teams.isEmpty && !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Teams",
                        systemImage: "person.3",
                        description: Text("You haven't joined any teams.")
                    )
                }
            } else {
                ForEach(viewModel.teams) { team in
                    teamSection(team)
                }
            }
        }
    }

    private func teamSection(_ team: TeamsTeam) -> some View {
        Section(team.displayName ?? "Team") {
            if viewModel.selectedTeam?.id == team.id {
                ForEach(viewModel.channels) { channel in
                    channelRow(channel)
                }
            } else {
                Button {
                    Task { await viewModel.loadChannels(for: team) }
                } label: {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundStyle(.blue)
                        Text("View Channels")
                            .font(.subheadline)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func channelRow(_ channel: TeamsChannel) -> some View {
        Button {
            Task {
                await viewModel.selectChannel(channel)
                showMessages = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: channel.isGeneral ? "number.square.fill" : "number")
                    .foregroundStyle(channel.isGeneral ? Color.blue : Color.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.displayName ?? "Channel")
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let desc = channel.description, !desc.isEmpty {
                        Text(desc)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if viewModel.selectedChannel?.id == channel.id {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Chats List

    private var chatsListSection: some View {
        Group {
            if viewModel.chats.isEmpty && !viewModel.isLoading {
                Section {
                    ContentUnavailableView(
                        "No Chats",
                        systemImage: "bubble.left.and.bubble.right",
                        description: Text("No recent chats found.")
                    )
                }
            } else {
                Section("Recent Chats") {
                    ForEach(viewModel.chats) { chat in
                        chatRow(chat)
                    }
                }
            }
        }
    }

    private func chatRow(_ chat: TeamsChat) -> some View {
        Button {
            Task {
                await viewModel.selectChat(chat)
                showMessages = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: chatIcon(for: chat))
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.displayName)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                    if let date = chat.lastUpdatedDateTime {
                        Text(date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if viewModel.selectedChat?.id == chat.id {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func chatIcon(for chat: TeamsChat) -> String {
        switch chat.chatType {
        case "oneOnOne": return "person.fill"
        case "group": return "person.3.fill"
        case "meeting": return "video.fill"
        default: return "bubble.left.fill"
        }
    }

    // MARK: - Messages Detail

    private var messagesDetail: some View {
        VStack(spacing: 0) {
            // Messages list
            if viewModel.isLoading && viewModel.messages.isEmpty {
                Spacer()
                ProgressView("Loading messages...")
                Spacer()
            } else if viewModel.messages.isEmpty {
                Spacer()
                ContentUnavailableView(
                    "No Messages",
                    systemImage: "bubble.left",
                    description: Text("Select a channel or chat to view messages.")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(viewModel.messages) { message in
                            messageRow(message)
                        }
                    }
                    .padding()
                }
            }

            Divider()

            // Compose bar
            composeBar
        }
    }

    private func messageRow(_ message: TeamsChatMessage) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(message.senderName)
                    .font(.caption.bold())
                    .foregroundStyle(Color.accentColor)
                Spacer()
                if let date = message.createdDateTime {
                    Text(formatMessageDate(date))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Text(stripHTML(message.textContent))
                .font(.body)
                .foregroundStyle(.primary)

            // File attachments (from sync cache)
            if viewModel.isSyncEnabled {
                let sourceType = viewModel.selectedChannel != nil ? "channel" : "chat"
                let sourceId = viewModel.selectedChannel?.id ?? viewModel.selectedChat?.id ?? ""
                let files = viewModel.cachedFilesForSource(sourceType: sourceType, sourceGraphId: sourceId)
                if !files.isEmpty && message.id == viewModel.messages.first?.id {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Channel Files")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        ForEach(files, id: \.graphId) { file in
                            Button {
                                if let url = URL(string: file.webUrl) {
                                    PlatformURLOpener.open(url)
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    let info = DocumentTypeIcon.icon(forFilename: file.name)
                                    Image(systemName: info.systemName)
                                        .foregroundStyle(info.color)
                                        .font(.caption)
                                    Text(file.name)
                                        .font(.caption)
                                        .foregroundStyle(.blue)
                                        .lineLimit(1)
                                    Spacer()
                                    if file.size > 0 {
                                        Text(ByteCountFormatter.string(
                                            fromByteCount: Int64(file.size), countStyle: .file))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $viewModel.composeText, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button {
                Task { await viewModel.sendMessage() }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
            }
            .disabled(
                viewModel.composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || viewModel.isSending
                || (viewModel.selectedChannel == nil && viewModel.selectedChat == nil)
            )
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Helpers

    /// Strip basic HTML tags for display.
    private func stripHTML(_ html: String) -> String {
        // Simple regex-based HTML stripping for message display
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Format an ISO 8601 date string for display.
    private func formatMessageDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return isoString
            }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}


