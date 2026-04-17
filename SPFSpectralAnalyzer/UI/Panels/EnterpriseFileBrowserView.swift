import SwiftUI

// MARK: - Enterprise File Browser View

/// A Finder-like file browser for OneDrive and SharePoint.
/// Displays breadcrumb navigation, file/folder lists, and search.
struct EnterpriseFileBrowserView: View {
    @State private var viewModel: EnterpriseFileBrowserViewModel

    init(authManager: MSALAuthManager, initialSource: EnterpriseFileBrowserViewModel.DriveSource = .oneDrive) {
        let vm = EnterpriseFileBrowserViewModel(authManager: authManager)
        vm.selectedSource = initialSource
        _viewModel = State(initialValue: vm)
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
            HStack(alignment: .top, spacing: 12) {
                Picker("Source", selection: $viewModel.selectedSource) {
                    ForEach(EnterpriseFileBrowserViewModel.DriveSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .tint(viewModel.selectedSource == .sharePoint
                      ? Color(red: 0.01, green: 0.53, blue: 0.55)  // SharePoint teal
                      : Color(red: 0.01, green: 0.47, blue: 0.84)) // OneDrive blue
                .frame(maxWidth: 250)

                if viewModel.selectedSource == .sharePoint {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            TextField("Paste SharePoint URL or site path...", text: $viewModel.sharePointSitePath)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    viewModel.clearResolvedSite()
                                    Task { await viewModel.loadRoot() }
                                }
                                .onChange(of: viewModel.sharePointSitePath) {
                                    viewModel.clearResolvedSite()
                                }

                            Button {
                                Task { await viewModel.loadAvailableSites() }
                                viewModel.showSiteBrowser = true
                            } label: {
                                Label("Browse Sites", systemImage: "list.bullet")
                                    .font(.subheadline)
                            }
                            .controlSize(.regular)
                            #if compiler(>=6.2)
                            .buttonStyle(.glass)
                            #else
                            .buttonStyle(.bordered)
                            #endif
                            .popover(isPresented: $viewModel.showSiteBrowser) {
                                siteBrowserPopover
                            }
                        }

                        if viewModel.isResolvingSite {
                            HStack(spacing: 4) {
                                ProgressView()
                                    .controlSize(.mini)
                                Text("Resolving site...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        } else if let site = viewModel.resolvedSite {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                    .font(.caption)
                                Text(site.displayName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Spacer()

                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .controlSize(.regular)
                #if compiler(>=6.2)
                .buttonStyle(.glass)
                #else
                .buttonStyle(.bordered)
                #endif
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
            #if compiler(>=6.2)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            #else
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            #endif

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
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        #if compiler(>=6.2)
                        .glassEffect(.regular.interactive(), in: .capsule)
                        #else
                        .background(Color.accentColor.opacity(0.1))
                        .clipShape(Capsule())
                        #endif
                }
                .buttonStyle(.plain)

                ForEach(viewModel.pathStack) { entry in
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)

                    Button {
                        Task { await viewModel.navigateToPathEntry(entry) }
                    } label: {
                        Text(entry.name)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            #if compiler(>=6.2)
                            .glassEffect(.regular.interactive(), in: .capsule)
                            #else
                            .background(Color.accentColor.opacity(0.1))
                            .clipShape(Capsule())
                            #endif
                    }
                    .buttonStyle(.plain)
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
            Button {
                Task { try? await viewModel.authManager.signIn(scopes: M365Config.retrievalScopes) }
            } label: {
                Label("Sign In to Microsoft 365", systemImage: "person.badge.key")
            }
            .controlSize(.large)
            #if compiler(>=6.2)
            .buttonStyle(.glassProminent)
            #else
            .buttonStyle(.borderedProminent)
            #endif
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

    // MARK: - Site Browser Popover

    private var siteBrowserPopover: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Available SharePoint Sites")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    viewModel.showSiteBrowser = false
                }
                .controlSize(.small)
            }
            .padding()

            Divider()

            if viewModel.isLoadingSites {
                VStack {
                    Spacer()
                    ProgressView("Loading sites...")
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else if viewModel.availableSites.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "building.2")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No sites found")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Your tenant may not have Sites.Read.All permission configured.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
                .padding()
            } else {
                // Filter field
                TextField("Filter sites...", text: $viewModel.siteFilterQuery)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                List(viewModel.filteredSites, id: \.id) { site in
                    Button {
                        // Use the composite siteId directly from the Graph response
                        // instead of re-resolving from the webUrl (which fails).
                        viewModel.directlySetResolvedSite(
                            siteId: site.id,
                            displayName: site.displayName ?? site.name ?? "Site",
                            webUrl: site.webUrl ?? ""
                        )
                        viewModel.showSiteBrowser = false
                        Task { await viewModel.loadRoot() }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(site.displayName ?? site.name ?? "Unnamed Site")
                                .font(.subheadline.weight(.medium))
                            if let webUrl = site.webUrl {
                                Text(webUrl)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .frame(minWidth: 360, idealWidth: 420, minHeight: 300, idealHeight: 400)
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
