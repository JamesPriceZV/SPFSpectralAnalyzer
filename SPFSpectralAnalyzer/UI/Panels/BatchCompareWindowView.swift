import SwiftUI

// MARK: - Shared State for Popout Window

/// Holds snapshot data for the Batch Compare popout window.
/// Populated by ContentView before opening the window.
@Observable @MainActor
final class BatchCompareWindowModel {
    static let shared = BatchCompareWindowModel()

    var rows: [BatchCompareRow] = []
    var sourceLabel: String = ""
    var snapshotDate: Date = Date()

    func update(rows: [BatchCompareRow], sourceLabel: String) {
        self.rows = rows
        self.sourceLabel = sourceLabel
        self.snapshotDate = Date()
    }
}

// MARK: - Batch Compare Window View

/// Resizable popout window for the Batch Compare table with share functionality.
struct BatchCompareWindowView: View {
    @Environment(MSALAuthManager.self) private var authManager

    private let model = BatchCompareWindowModel.shared

    @State private var showShareSheet = false
    @State private var showTeamsPicker = false
    @State private var shareImage: PlatformImage?

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Batch Compare")
                        .font(.title2.bold())
                    HStack(spacing: 8) {
                        Text(model.sourceLabel)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text("\(model.rows.count) samples")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(model.snapshotDate.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                // Share menu
                Menu {
                    Button {
                        shareViaMessages()
                    } label: {
                        Label("Share via Messages", systemImage: "message")
                    }

                    Divider()

                    Button {
                        showTeamsPicker = true
                    } label: {
                        Label("Share to Teams", systemImage: "bubble.left.and.bubble.right")
                    }
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            // Table content
            if model.rows.isEmpty {
                ContentUnavailableView(
                    "No Comparison Data",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text("Select at least 2 spectra in the main window, then pop out again.")
                )
            } else {
                batchTable
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
            }
        }
        #else
        .popover(isPresented: $showShareSheet) {
            if let image = shareImage {
                ShareSheet(items: [image])
                    .frame(width: 1, height: 1)
            }
        }
        #endif
        .sheet(isPresented: $showTeamsPicker) {
            TeamsSharePickerView(htmlContent: generateHTMLTable(), authManager: authManager)
        }
    }

    // MARK: - Table

    private var batchTable: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 0) {
                // Header row
                HStack(spacing: 0) {
                    Text("Sample")
                        .frame(width: 280, alignment: .leading)
                    Text("SPF")
                        .frame(width: 80, alignment: .trailing)
                    Text("ΔSPF")
                        .frame(width: 80, alignment: .trailing)
                    Text("UVA/UVB")
                        .frame(width: 90, alignment: .trailing)
                    Text("ΔUVA")
                        .frame(width: 80, alignment: .trailing)
                    Text("Critical")
                        .frame(width: 90, alignment: .trailing)
                    Text("ΔCrit")
                        .frame(width: 80, alignment: .trailing)
                }
                .font(.subheadline.bold())
                .foregroundColor(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05))

                // Data rows
                ForEach(Array(model.rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 0) {
                        Text(row.name)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 280, alignment: .leading)
                        Text(row.spf.map { String(format: "%.1f", $0) } ?? "—")
                            .frame(width: 80, alignment: .trailing)
                        Text(row.deltaSpf.map { String(format: "%+.1f", $0) } ?? "—")
                            .foregroundColor(SpectralInterpretation.deltaColor(row.deltaSpf, positive: .green, negative: .red, threshold: 2.0))
                            .frame(width: 80, alignment: .trailing)
                        Text(row.uvaUvb.map { String(format: "%.2f", $0) } ?? "—")
                            .frame(width: 90, alignment: .trailing)
                        Text(row.deltaUvaUvb.map { String(format: "%+.2f", $0) } ?? "—")
                            .foregroundColor(SpectralInterpretation.deltaColor(row.deltaUvaUvb, positive: .green, negative: .red, threshold: 0.03))
                            .frame(width: 80, alignment: .trailing)
                        Text(row.critical.map { String(format: "%.1f", $0) } ?? "—")
                            .frame(width: 90, alignment: .trailing)
                        Text(row.deltaCritical.map { String(format: "%+.1f", $0) } ?? "—")
                            .foregroundColor(SpectralInterpretation.deltaColor(row.deltaCritical, positive: .green, negative: .red, threshold: 2.0))
                            .frame(width: 80, alignment: .trailing)
                    }
                    .font(.body.monospacedDigit())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(index % 2 == 0 ? Color.clear : Color.primary.opacity(0.03))
                }
            }
        }
    }

    // MARK: - iMessage Share

    private func shareViaMessages() {
        let snapshotView = batchTableSnapshot
            .frame(width: 760, height: CGFloat(50 + model.rows.count * 36 + 30))
            .padding()
            .background(Color.white)

        let size = CGSize(width: 820, height: CGFloat(50 + model.rows.count * 36 + 70))
        if let image = ViewSnapshotService.snapshot(snapshotView, size: size) {
            shareImage = image
            showShareSheet = true
        }
    }

    /// Static version of the table for screenshot capture.
    private var batchTableSnapshot: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Batch Compare — \(model.sourceLabel)")
                .font(.headline)
                .foregroundColor(.black)

            HStack(spacing: 8) {
                Text("Sample").frame(width: 160, alignment: .leading)
                Text("SPF").frame(width: 60, alignment: .trailing)
                Text("ΔSPF").frame(width: 60, alignment: .trailing)
                Text("UVA/UVB").frame(width: 70, alignment: .trailing)
                Text("ΔUVA").frame(width: 60, alignment: .trailing)
                Text("Critical").frame(width: 70, alignment: .trailing)
                Text("ΔCrit").frame(width: 60, alignment: .trailing)
            }
            .font(.caption2.bold())
            .foregroundColor(.gray)

            ForEach(Array(model.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: 8) {
                    Text(row.name)
                        .lineLimit(1)
                        .frame(width: 160, alignment: .leading)
                    Text(row.spf.map { String(format: "%.1f", $0) } ?? "—")
                        .frame(width: 60, alignment: .trailing)
                    Text(row.deltaSpf.map { String(format: "%+.1f", $0) } ?? "—")
                        .foregroundColor(row.deltaSpf.map { abs($0) > 2 ? ($0 > 0 ? .green : .red) : .black } ?? .black)
                        .frame(width: 60, alignment: .trailing)
                    Text(row.uvaUvb.map { String(format: "%.2f", $0) } ?? "—")
                        .frame(width: 70, alignment: .trailing)
                    Text(row.deltaUvaUvb.map { String(format: "%+.2f", $0) } ?? "—")
                        .foregroundColor(row.deltaUvaUvb.map { abs($0) > 0.03 ? ($0 > 0 ? .green : .red) : .black } ?? .black)
                        .frame(width: 60, alignment: .trailing)
                    Text(row.critical.map { String(format: "%.1f", $0) } ?? "—")
                        .frame(width: 70, alignment: .trailing)
                    Text(row.deltaCritical.map { String(format: "%+.1f", $0) } ?? "—")
                        .foregroundColor(row.deltaCritical.map { abs($0) > 2 ? ($0 > 0 ? .green : .red) : .black } ?? .black)
                        .frame(width: 60, alignment: .trailing)
                }
                .font(.caption.monospacedDigit())
                .foregroundColor(.black)
            }

            Text("SPF Spectral Analyzer — \(model.snapshotDate.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundColor(.gray)
                .padding(.top, 4)
        }
    }

    // MARK: - HTML Generation for Teams

    func generateHTMLTable() -> String {
        var html = """
        <table style="border-collapse:collapse;font-family:system-ui;font-size:14px;">
        <caption style="text-align:left;font-weight:bold;padding:8px 0;">Batch Compare &mdash; \(escapeHTML(model.sourceLabel))</caption>
        <tr style="background:#f0f0f0;">
            <th style="padding:6px 12px;text-align:left;border:1px solid #ddd;">Sample</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">SPF</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">&Delta;SPF</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">UVA/UVB</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">&Delta;UVA</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">Critical</th>
            <th style="padding:6px 12px;text-align:right;border:1px solid #ddd;">&Delta;Crit</th>
        </tr>
        """

        for (index, row) in model.rows.enumerated() {
            let bg = index % 2 == 0 ? "#ffffff" : "#f8f8f8"
            let spf = row.spf.map { String(format: "%.1f", $0) } ?? "&mdash;"
            let dSpf = row.deltaSpf.map { String(format: "%+.1f", $0) } ?? "&mdash;"
            let uvaUvb = row.uvaUvb.map { String(format: "%.2f", $0) } ?? "&mdash;"
            let dUva = row.deltaUvaUvb.map { String(format: "%+.2f", $0) } ?? "&mdash;"
            let crit = row.critical.map { String(format: "%.1f", $0) } ?? "&mdash;"
            let dCrit = row.deltaCritical.map { String(format: "%+.1f", $0) } ?? "&mdash;"

            html += """
            <tr style="background:\(bg);">
                <td style="padding:6px 12px;border:1px solid #ddd;">\(escapeHTML(row.name))</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;">\(spf)</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;\(deltaStyle(row.deltaSpf, threshold: 2.0))">\(dSpf)</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;">\(uvaUvb)</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;\(deltaStyle(row.deltaUvaUvb, threshold: 0.03))">\(dUva)</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;">\(crit)</td>
                <td style="padding:6px 12px;text-align:right;border:1px solid #ddd;\(deltaStyle(row.deltaCritical, threshold: 2.0))">\(dCrit)</td>
            </tr>
            """
        }

        html += """
        </table>
        <p style="font-size:11px;color:#888;margin-top:8px;">Generated by SPF Spectral Analyzer &mdash; \(model.snapshotDate.formatted(date: .abbreviated, time: .shortened))</p>
        """

        return html
    }

    private func deltaStyle(_ value: Double?, threshold: Double) -> String {
        guard let v = value, abs(v) > threshold else { return "" }
        let color = v > 0 ? "#2ecc71" : "#e74c3c"
        return "color:\(color);font-weight:bold;"
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Teams Share Picker

/// Lightweight destination picker for sharing Batch Compare data to Teams.
struct TeamsSharePickerView: View {
    let htmlContent: String
    let authManager: MSALAuthManager

    @Environment(\.dismiss) private var dismiss

    @State private var teams: [TeamsTeam] = []
    @State private var channels: [TeamsChannel] = []
    @State private var chats: [TeamsChat] = []
    @State private var expandedTeamId: String?
    @State private var isLoading = false
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    enum ShareMode: String, CaseIterable, Identifiable {
        case channels = "Channels"
        case chats = "Chats"
        var id: String { rawValue }
    }
    @State private var shareMode: ShareMode = .channels

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $shareMode) {
                    ForEach(ShareMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if isLoading {
                    ProgressView("Loading Teams...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage, teams.isEmpty && chats.isEmpty {
                    ContentUnavailableView(
                        "Cannot Load Teams",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else {
                    destinationList
                }

                if let success = successMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text(success)
                            .font(.callout)
                    }
                    .padding()
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle("Share to Teams")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .frame(minWidth: 400, minHeight: 450)
        .task { await loadDestinations() }
    }

    @ViewBuilder
    private var destinationList: some View {
        List {
            switch shareMode {
            case .channels:
                if teams.isEmpty {
                    Text("No teams found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(teams) { team in
                        Section(team.displayName ?? "Team") {
                            if expandedTeamId == team.id {
                                ForEach(channels) { channel in
                                    Button {
                                        Task {
                                            await sendToChannel(
                                                teamId: team.id,
                                                channelId: channel.id,
                                                label: "\(team.displayName ?? "Team") > \(channel.displayName ?? "Channel")"
                                            )
                                        }
                                    } label: {
                                        HStack {
                                            Label(channel.displayName ?? "Channel", systemImage: "number")
                                            Spacer()
                                            if isSending {
                                                ProgressView().controlSize(.small)
                                            }
                                        }
                                    }
                                    .disabled(isSending)
                                }
                            } else {
                                Button {
                                    Task { await loadChannels(for: team) }
                                } label: {
                                    Label("Load channels...", systemImage: "arrow.down.circle")
                                        .foregroundColor(.accentColor)
                                }
                            }
                        }
                    }
                }
            case .chats:
                if chats.isEmpty {
                    Text("No chats found.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(chats) { chat in
                        Button {
                            Task { await sendToChat(chatId: chat.id, label: chat.displayName) }
                        } label: {
                            HStack {
                                Label(
                                    chat.displayName,
                                    systemImage: chat.chatType == "oneOnOne" ? "person" : "person.2"
                                )
                                Spacer()
                                if isSending {
                                    ProgressView().controlSize(.small)
                                }
                            }
                        }
                        .disabled(isSending)
                    }
                }
            }
        }
    }

    // MARK: - Network

    private func loadDestinations() async {
        guard authManager.isSignedIn else {
            errorMessage = "Sign in to Microsoft 365 in Settings to share via Teams."
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            async let fetchedTeams = GraphTeamsService.listJoinedTeams(accessToken: token)
            async let fetchedChats = GraphTeamsService.listChats(accessToken: token)
            teams = try await fetchedTeams
            chats = try await fetchedChats
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadChannels(for team: TeamsTeam) async {
        expandedTeamId = team.id
        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            channels = try await GraphTeamsService.listChannels(teamId: team.id, accessToken: token)
        } catch {
            errorMessage = "Failed to load channels: \(error.localizedDescription)"
        }
    }

    private func sendToChannel(teamId: String, channelId: String, label: String) async {
        isSending = true
        defer { isSending = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            try await GraphTeamsService.sendChannelMessage(
                teamId: teamId,
                channelId: channelId,
                content: htmlContent,
                contentType: "html",
                accessToken: token
            )
            withAnimation { successMessage = "Sent to \(label)" }
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
    }

    private func sendToChat(chatId: String, label: String) async {
        isSending = true
        defer { isSending = false }

        do {
            let token = try await authManager.acquireToken(scopes: M365Config.teamsScopes)
            try await GraphTeamsService.sendChatMessage(
                chatId: chatId,
                content: htmlContent,
                contentType: "html",
                accessToken: token
            )
            withAnimation { successMessage = "Sent to \(label)" }
            try? await Task.sleep(for: .seconds(1.5))
            dismiss()
        } catch {
            errorMessage = "Send failed: \(error.localizedDescription)"
        }
    }
}
