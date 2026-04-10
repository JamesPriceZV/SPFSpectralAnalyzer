import SwiftUI

// MARK: - Teams View

/// Microsoft Teams interface with Liquid Glass design and Microsoft design influences.
/// Features: avatars, presence indicators, message grouping, rich text, glass compose bar.
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
                iPadTeamsLayout
                #endif
            }
        }
        .task {
            guard viewModel.authManager.isSignedIn else { return }
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

    // MARK: - Layouts

    #if os(iOS)
    private var iPadTeamsLayout: some View {
        NavigationSplitView {
            teamsSidebar
                .navigationTitle("Teams")
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: .infinity)
        } detail: {
            messagesDetail
        }
        .navigationSplitViewStyle(.balanced)
    }
    #else
    private var iPadTeamsLayout: some View {
        NavigationSplitView {
            teamsSidebar
                .navigationTitle("Teams")
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: .infinity)
        } detail: {
            messagesDetail
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

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
            // Sync status
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
                            .foregroundStyle(.purple)
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
                    .foregroundStyle(channel.isGeneral ? Color.purple : Color.secondary)
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
            HStack(spacing: 10) {
                // Avatar placeholder with chat type icon
                ZStack(alignment: .bottomTrailing) {
                    Circle()
                        .fill(chatGradient(for: chat))
                        .frame(width: 40, height: 40)
                        .overlay {
                            Image(systemName: chatIcon(for: chat))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(chat.displayName)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let date = chat.lastUpdatedDateTime {
                        Text(formatMessageDate(date))
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

    /// Microsoft-style gradient for chat avatars.
    private func chatGradient(for chat: TeamsChat) -> LinearGradient {
        let colors: [Color]
        switch chat.chatType {
        case "oneOnOne": colors = [.blue, .cyan]
        case "group": colors = [.purple, .indigo]
        case "meeting": colors = [.orange, .red]
        default: colors = [.gray, .secondary]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Messages Detail

    private var messagesDetail: some View {
        VStack(spacing: 0) {
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
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.messageGroups) { group in
                            messageGroupView(group)
                        }
                    }
                    .padding()
                }
                #if compiler(>=6.2)
                .scrollEdgeEffectStyle(.soft, for: .top)
                #endif

                // File attachments section
                if viewModel.isSyncEnabled {
                    let sourceType = viewModel.selectedChannel != nil ? "channel" : "chat"
                    let sourceId = viewModel.selectedChannel?.id ?? viewModel.selectedChat?.id ?? ""
                    let files = viewModel.cachedFilesForSource(sourceType: sourceType, sourceGraphId: sourceId)
                    if !files.isEmpty {
                        Divider()
                        channelFilesSection(files)
                    }
                }
            }

            Divider()
            composeBar
        }
        .toolbar {
            #if os(iOS)
            ToolbarItem(placement: .principal) {
                VStack(spacing: 0) {
                    Text(messageDetailTitle)
                        .font(.subheadline.weight(.semibold))
                }
            }
            #endif
        }
    }

    // MARK: - Message Group View

    private func messageGroupView(_ group: MessageGroup) -> some View {
        HStack(alignment: .top, spacing: 10) {
            // Avatar — tappable for contact card
            avatarView(userId: group.senderId, name: group.senderName)
                .frame(width: 32, height: 32)
                .contentShape(Circle())
                .onTapGesture {
                    if let userId = group.senderId {
                        Task { await viewModel.loadProfile(for: userId) }
                        viewModel.contactCardUserId = userId
                    }
                }
                .popover(isPresented: Binding(
                    get: { viewModel.contactCardUserId == group.senderId && group.senderId != nil },
                    set: { if !$0 { viewModel.contactCardUserId = nil } }
                )) {
                    if let userId = group.senderId {
                        contactCardView(userId: userId, name: group.senderName)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                // Sender name + presence + timestamp
                HStack(spacing: 6) {
                    Text(group.senderName)
                        .font(.subheadline.weight(.semibold))

                    if let userId = group.senderId,
                       let presence = viewModel.presenceCache[userId] {
                        Image(systemName: presence.systemImage)
                            .font(.system(size: 8))
                            .foregroundStyle(presence.color)
                    }

                    if let date = group.timestamp {
                        Text(date, format: .dateTime.hour().minute())
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                // Messages in this group
                ForEach(group.messages) { message in
                    messageContentView(message)
                }
            }
        }
    }

    /// Render a single message's content with basic rich text.
    private func messageContentView(_ message: TeamsChatMessage) -> some View {
        Text(renderRichText(message.textContent))
            .font(.body)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    /// Build an avatar view: real photo if cached, or initials fallback.
    private func avatarView(userId: String?, name: String) -> some View {
        ZStack {
            if let userId, let data = viewModel.avatarData(for: userId),
               let image = platformImage(from: data) {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .clipShape(Circle())
            } else {
                // Initials fallback with Microsoft-style gradient
                Circle()
                    .fill(initialsGradient(for: name))
                    .overlay {
                        Text(initials(for: name))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }

            // Presence dot overlay
            if let userId, let presence = viewModel.presenceCache[userId] {
                Circle()
                    .fill(presence.color)
                    .frame(width: 10, height: 10)
                    .overlay {
                        Circle()
                            .stroke(.background, lineWidth: 2)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            }
        }
    }

    // MARK: - Channel Files

    private func channelFilesSection(_ files: [CachedTeamsFile]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Channel Files")
                .font(.caption2.bold())
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 6)

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
                    .padding(.horizontal, 12)
                    .padding(.vertical, 3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 6)
    }

    // MARK: - Compose Bar

    private var composeBar: some View {
        HStack(spacing: 8) {
            TextField("Type a message...", text: $viewModel.composeText, axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.plain)
                .padding(10)

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
        #if compiler(>=6.2)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
        #else
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        #endif
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    // MARK: - Contact Card

    /// Popover showing user profile, presence, and contact info.
    private func contactCardView(userId: String, name: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header with avatar + name
            HStack(spacing: 12) {
                avatarView(userId: userId, name: name)
                    .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    if let profile = viewModel.profileCache[userId] {
                        Text(profile.displayName ?? name)
                            .font(.headline)
                        if let jobTitle = profile.jobTitle, !jobTitle.isEmpty {
                            Text(jobTitle)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text(name)
                            .font(.headline)
                    }

                    // Presence status
                    if let presence = viewModel.presenceCache[userId] {
                        HStack(spacing: 4) {
                            Image(systemName: presence.systemImage)
                                .font(.system(size: 8))
                                .foregroundStyle(presence.color)
                            Text(presence.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            // Profile details
            if let profile = viewModel.profileCache[userId] {
                VStack(alignment: .leading, spacing: 6) {
                    if let department = profile.department, !department.isEmpty {
                        Label(department, systemImage: "building.2")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let mail = profile.mail, !mail.isEmpty {
                        Label(mail, systemImage: "envelope")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 240, idealWidth: 280)
    }

    // MARK: - Rich Text Rendering

    /// Parse basic HTML tags into an AttributedString for rich display.
    private func renderRichText(_ html: String) -> AttributedString {
        // First decode HTML entities
        var text = html
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")

        // Strip HTML tags but try to parse basic formatting
        text = text.replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        return AttributedString(text)
    }

    // MARK: - Helpers

    /// Generate initials from a display name.
    private func initials(for name: String) -> String {
        let components = name.split(separator: " ")
        if components.count >= 2 {
            return "\(components[0].prefix(1))\(components[1].prefix(1))".uppercased()
        }
        return String(name.prefix(2)).uppercased()
    }

    /// Microsoft-style gradient based on name hash.
    private func initialsGradient(for name: String) -> LinearGradient {
        let hash = abs(name.hashValue)
        let gradients: [(Color, Color)] = [
            (.blue, .cyan),
            (.purple, .indigo),
            (.orange, .red),
            (.green, .teal),
            (.pink, .purple),
            (.indigo, .blue),
            (.teal, .green),
            (.red, .orange),
        ]
        let pair = gradients[hash % gradients.count]
        return LinearGradient(colors: [pair.0, pair.1], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Create a platform image from data.
    private func platformImage(from data: Data) -> PlatformImage? {
        PlatformImage(data: data)
    }

    /// Format an ISO 8601 date string for display.
    private func formatMessageDate(_ isoString: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: isoString) else {
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: isoString) else {
                return isoString
            }
            return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
        }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Image Extension

#if canImport(AppKit)
private extension Image {
    init(platformImage: NSImage) {
        self.init(nsImage: platformImage)
    }
}
#elseif canImport(UIKit)
private extension Image {
    init(platformImage: UIImage) {
        self.init(uiImage: platformImage)
    }
}
#endif
