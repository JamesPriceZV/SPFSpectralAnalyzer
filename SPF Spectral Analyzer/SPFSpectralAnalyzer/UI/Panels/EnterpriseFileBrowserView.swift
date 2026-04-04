import SwiftUI

// MARK: - Enterprise File Browser View

/// A Finder-like file browser for OneDrive and SharePoint.
/// Displays breadcrumb navigation, file/folder lists, and search.
struct EnterpriseFileBrowserView: View {
    @State private var viewModel: EnterpriseFileBrowserViewModel

    init(authManager: MSALAuthManager) {
        _viewModel = State(initialValue: EnterpriseFileBrowserViewModel(authManager: authManager))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if viewModel.authManager.isSignedIn {
                browserToolbar
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)

                Divider()

                browserContent
            } else {
                signInPrompt
            }
        }
        .task {
            if viewModel.authManager.isSignedIn, viewModel.items.isEmpty {
                await viewModel.loadRoot()
            }
        }
        .onChange(of: viewModel.selectedSource) {
            Task { await viewModel.loadRoot() }
        }
    }

    // MARK: - Toolbar

    private var browserToolbar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Source picker + SharePoint site path
            HStack(spacing: 12) {
                Picker("Source", selection: $viewModel.selectedSource) {
                    ForEach(EnterpriseFileBrowserViewModel.DriveSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 250)

                if viewModel.selectedSource == .sharePoint {
                    TextField("Site path (e.g., contoso.sharepoint.com:/sites/Lab)", text: $viewModel.sharePointSitePath)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await viewModel.loadRoot() } }
                }

                Spacer()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            }

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search files...", text: $viewModel.searchQuery)
                    .textFieldStyle(.plain)
                    .onSubmit { Task { await viewModel.search() } }

                if !viewModel.searchQuery.isEmpty {
                    Button {
                        viewModel.searchQuery = ""
                        Task { await viewModel.loadRoot() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                Button("Search") {
                    Task { await viewModel.search() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            // Breadcrumb navigation
            breadcrumbBar
        }
    }

    // MARK: - Breadcrumb

    private var breadcrumbBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Button {
                    Task { await viewModel.loadRoot() }
                } label: {
                    Label(viewModel.selectedSource == .oneDrive ? "OneDrive" : "SharePoint",
                          systemImage: viewModel.selectedSource == .oneDrive ? "cloud" : "building.2")
                        .font(.caption.bold())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)

                ForEach(viewModel.pathStack) { entry in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button(entry.name) {
                        Task { await viewModel.navigateToPathEntry(entry) }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
            }
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var browserContent: some View {
        if viewModel.isLoading {
            VStack {
                Spacer()
                ProgressView("Loading...")
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if let error = viewModel.errorMessage, viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle")
                    .font(.title)
                    .foregroundStyle(.secondary)
                Text(error)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Retry") {
                    Task { await viewModel.refresh() }
                }
                .buttonStyle(.bordered)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding()
        } else if viewModel.items.isEmpty {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "folder")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text("This folder is empty")
                    .font(.body)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            fileList
        }
    }

    // MARK: - File List

    private var fileList: some View {
        List {
            // Up button when inside a subfolder
            if !viewModel.pathStack.isEmpty {
                Button {
                    Task { await viewModel.navigateUp() }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.doc")
                            .foregroundStyle(.blue)
                            .frame(width: 24)
                        Text("Up to parent folder")
                            .foregroundStyle(.blue)
                    }
                }
                .buttonStyle(.plain)
            }

            ForEach(viewModel.items) { item in
                fileRow(item)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func fileRow(_ item: GraphDriveItem) -> some View {
        Button {
            if item.isFolder {
                Task { await viewModel.navigateInto(folder: item) }
            } else if let webUrl = item.webUrl, let url = URL(string: webUrl) {
                PlatformURLOpener.open(url)
            }
        } label: {
            HStack(spacing: 10) {
                // Icon
                let iconInfo = DocumentTypeIcon.icon(for: item)
                Image(systemName: iconInfo.systemName)
                    .foregroundStyle(iconInfo.color)
                    .frame(width: 24)

                // Name
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(.body)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        if let size = item.size, !item.isFolder {
                            Text(formattedSize(size))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let childCount = item.folder?.childCount {
                            Text("\(childCount) items")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let modified = item.lastModifiedDateTime {
                            Text(formattedDate(modified))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                if item.isFolder {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Sign-In Prompt

    private var signInPrompt: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "folder.badge.person.crop")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Sign in to browse files")
                .font(.title3.bold())
            Text("Sign in to Microsoft 365 to browse your OneDrive and SharePoint files.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Helpers

    private func formattedSize(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }

    private func formattedDate(_ isoString: String) -> String {
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
