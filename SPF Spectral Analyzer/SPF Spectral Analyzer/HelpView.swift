import SwiftUI
import AppKit
import Foundation
import OSLog

private let helpLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "HelpView", category: "Help")

private struct DocCHelpPage: Identifiable, Hashable {
    let id: String
    let title: String
    let resourcePath: String
    let docKey: String?
}

struct HelpView: View {
    @State private var selection: DocCHelpPage?
    @State private var renderedContent: AttributedString = AttributedString("Select a topic from the sidebar.")
    @State private var loadError: String?
    @State private var history: [DocCHelpPage] = []
    @State private var historyIndex: Int = -1
    @State private var isNavigatingFromHistory: Bool = false
    @State private var searchText: String = ""

    private let pages: [DocCHelpPage] = [
        DocCHelpPage(id: "overview", title: "Overview", resourcePath: "HelpContent/Documentation.md", docKey: "Overview"),
        DocCHelpPage(id: "tutorial-workflow", title: "Tutorial: Workflow", resourcePath: "HelpContent/Tutorials/Workflow.tutorial", docKey: "Workflow"),
        DocCHelpPage(id: "workflow-design", title: "Workflow Design", resourcePath: "HelpContent/HowTo/WorkflowDesign.md", docKey: "WorkflowDesign"),
        DocCHelpPage(id: "import-spc", title: "Import SPC Files", resourcePath: "HelpContent/HowTo/ImportSPC.md", docKey: "ImportSPC"),
        DocCHelpPage(id: "analyze-combine", title: "Analyze and Combine", resourcePath: "HelpContent/HowTo/AnalyzeAndCombine.md", docKey: "AnalyzeAndCombine"),
        DocCHelpPage(id: "ai-analysis", title: "AI Analysis", resourcePath: "HelpContent/HowTo/AIAnalysis.md", docKey: "AIAnalysis"),
        DocCHelpPage(id: "export-data", title: "Export Data", resourcePath: "HelpContent/HowTo/ExportData.md", docKey: "ExportData"),
        DocCHelpPage(id: "spf-methods", title: "SPF Calculation Methods", resourcePath: "HelpContent/HowTo/SPFCalculationMethods.md", docKey: "SPFCalculationMethods"),
        DocCHelpPage(id: "privacy-support", title: "Privacy and Support", resourcePath: "HelpContent/HowTo/PrivacySupport.md", docKey: "PrivacySupport"),
        DocCHelpPage(id: "keyboard-shortcuts", title: "Keyboard Shortcuts", resourcePath: "HelpContent/HowTo/KeyboardShortcuts.md", docKey: "KeyboardShortcuts"),
        DocCHelpPage(id: "search-syntax", title: "Search Syntax", resourcePath: "HelpContent/HowTo/SearchSyntax.md", docKey: "SearchSyntax")
    ]

    var body: some View {
        VStack(spacing: 0) {
            helpTopBar
            Divider()
            NavigationSplitView {
                List(filteredPages, selection: $selection) { page in
                    Text(page.title)
                        .tag(page)
                }
            } detail: {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let loadError {
                            Text(loadError)
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Text(renderedContent)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(24)
                }
                .safeAreaInset(edge: .top) {
                    detailHeader
                }
                .environment(\.openURL, OpenURLAction { url in
                    handleDocLink(url)
                })
            }
        }
        .frame(minWidth: 820, minHeight: 640)
        .onAppear {
            if selection == nil {
                selection = pages.first
            }
            if let selection, historyIndex == -1 {
                pushHistory(selection)
            }
        }
        .onChange(of: selection) { _, newValue in
            guard let newValue else { return }
            if isNavigatingFromHistory {
                isNavigatingFromHistory = false
            } else {
                pushHistory(newValue)
            }
            loadMarkdown(for: newValue)
        }
    }

    private var filteredPages: [DocCHelpPage] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return pages }
        return pages.filter { $0.title.localizedCaseInsensitiveContains(query) }
    }

    private var currentTitle: String {
        selection?.title ?? "Help"
    }

    private var helpTopBar: some View {
        HStack(spacing: 12) {
            Button {
                goBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(historyIndex <= 0)
            .help("Back")

            Button {
                goForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(historyIndex >= history.count - 1)
            .help("Forward")

            Text(currentTitle)
                .font(.headline)
                .lineLimit(1)

            Spacer()

            TextField("Search", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)

            Button {
                copyCurrentLink()
            } label: {
                Image(systemName: "link")
            }
            .disabled(selection?.docKey == nil)
            .help("Copy Link")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private var detailHeader: some View {
        HStack {
            Text(currentTitle)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)
            Spacer()
            Button {
                copyCurrentLink()
            } label: {
                Image(systemName: "link")
            }
            .disabled(selection?.docKey == nil)
            .help("Copy Link")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .bottom)
    }

    private func loadMarkdown(for page: DocCHelpPage) {
        loadError = nil
        renderedContent = AttributedString("Loading...")

        guard let url = resolveResourceURL(for: page) else {
            renderedContent = AttributedString("Help content is not available in this build.")
            loadError = "Missing resource: \(page.resourcePath)"
            return
        }

        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            renderedContent = buildAttributedContent(from: text, for: page)
        } catch {
            renderedContent = AttributedString("Unable to render help content.")
            loadError = error.localizedDescription
        }
    }

    private func handleDocLink(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "doc" else {
            return .systemAction
        }

        let rawKey = url.host ?? url.path.replacingOccurrences(of: "/", with: "")
        let key = rawKey.lowercased()

        if let page = pageByDocKey[key] {
            selection = page
            return .handled
        }

        helpLogger.error("Unhandled doc link: \(url.absoluteString, privacy: .public)")
        return .handled
    }

    private func copyCurrentLink() {
        guard let key = selection?.docKey else { return }
        let link = "doc://\(key)"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
    }

    private func pushHistory(_ page: DocCHelpPage) {
        if historyIndex >= 0, historyIndex < history.count, history[historyIndex].id == page.id {
            return
        }

        if historyIndex < history.count - 1 {
            history = Array(history.prefix(historyIndex + 1))
        }

        history.append(page)
        historyIndex = history.count - 1
    }

    private func goBack() {
        guard historyIndex > 0 else { return }
        historyIndex -= 1
        isNavigatingFromHistory = true
        selection = history[historyIndex]
    }

    private func goForward() {
        guard historyIndex + 1 < history.count else { return }
        historyIndex += 1
        isNavigatingFromHistory = true
        selection = history[historyIndex]
    }

    private var pageByDocKey: [String: DocCHelpPage] {
        Dictionary(uniqueKeysWithValues: pages.compactMap { page in
            guard let key = page.docKey?.lowercased() else { return nil }
            return (key, page)
        })
    }

    private func resolveResourceURL(for page: DocCHelpPage) -> URL? {
        if let url = Bundle.main.url(forResource: page.resourcePath, withExtension: nil) {
            return url
        }

        let fileURL = URL(fileURLWithPath: page.resourcePath)
        let fileName = fileURL.lastPathComponent
        let fileExtension = fileURL.pathExtension
        let baseName = fileURL.deletingPathExtension().lastPathComponent

        if let url = Bundle.main.url(forResource: fileName, withExtension: nil) {
            return url
        }

        if let url = Bundle.main.url(forResource: baseName, withExtension: fileExtension) {
            return url
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: nil),
           let match = urls.first(where: { $0.lastPathComponent == fileName }) {
            return match
        }

        if let urls = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: "Documentation.docc"),
           let match = urls.first(where: { $0.lastPathComponent == fileName }) {
            return match
        }

        logAvailableResources(forExtension: fileExtension, missingPath: page.resourcePath)
        return nil
    }

    private func logAvailableResources(forExtension fileExtension: String, missingPath: String) {
        let urls = Bundle.main.urls(forResourcesWithExtension: fileExtension, subdirectory: nil) ?? []
        let fileNames = urls.map { $0.lastPathComponent }.sorted().joined(separator: ", ")
        helpLogger.error("Missing help resource: \(missingPath). Bundled .\(fileExtension) files: \(fileNames, privacy: .public)")
    }

    private func buildAttributedContent(from text: String, for page: DocCHelpPage) -> AttributedString {
        let fileExtension = URL(fileURLWithPath: page.resourcePath).pathExtension.lowercased()
        let lines = extractContentLines(from: text, fileExtension: fileExtension)

        var output = AttributedString()
        var paragraphBuffer: [String] = []
        var listItems: [String] = []

        func appendNewline(_ count: Int) {
            guard count > 0 else { return }
            output.append(AttributedString(String(repeating: "\n", count: count)))
        }

        func flushParagraph() {
            guard !paragraphBuffer.isEmpty else { return }
            let joined = paragraphBuffer.joined(separator: " ")
            output.append(attributedText(joined, font: .system(.body)))
            appendNewline(2)
            paragraphBuffer.removeAll()
        }

        func flushList() {
            guard !listItems.isEmpty else { return }
            for item in listItems {
                output.append(attributedText("• \(item)", font: .system(.body)))
                appendNewline(1)
            }
            appendNewline(1)
            listItems.removeAll()
        }

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushParagraph()
                flushList()
                continue
            }

            if trimmed.hasPrefix("#") {
                flushParagraph()
                flushList()
                let title = trimmed.replacingOccurrences(of: "^#+\\s*", with: "", options: .regularExpression)
                output.append(attributedText(title, font: .system(.title3, weight: .semibold)))
                appendNewline(2)
                continue
            }

            let isListItem = trimmed.hasPrefix("- ") || trimmed.range(of: "^\\d+\\. ", options: .regularExpression) != nil
            if isListItem {
                flushParagraph()
                let item = trimmed.replacingOccurrences(of: "^(- |\\d+\\. )", with: "", options: .regularExpression)
                listItems.append(item)
                continue
            }

            if !listItems.isEmpty {
                flushList()
            }

            paragraphBuffer.append(trimmed)
        }

        flushParagraph()
        flushList()

        return output
    }

    private func extractContentLines(from text: String, fileExtension: String) -> [String] {
        var lines: [String] = []
        var skippingMetadataBlock = false

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(rawLine)
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if skippingMetadataBlock {
                if trimmed == ")" {
                    skippingMetadataBlock = false
                }
                continue
            }

            if fileExtension == "md" && trimmed.hasPrefix("@Article(") {
                skippingMetadataBlock = true
                continue
            }

            if fileExtension == "tutorial" {
                if trimmed.hasPrefix("@") {
                    continue
                }

                if trimmed == "{" || trimmed == "}" || trimmed == ")" {
                    continue
                }
            }

            lines.append(sanitizeInline(line))
        }

        return lines
    }

    private func attributedText(_ text: String, font: Font) -> AttributedString {
        var output = AttributedString()
        let docRegex = try? NSRegularExpression(pattern: "<doc:([^>]+)>", options: [])
        let sanitized = text.replacingOccurrences(of: "``", with: "")

        guard let docRegex else {
            var run = AttributedString(sanitized)
            run.font = font
            output.append(run)
            return output
        }

        let range = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        var cursor = sanitized.startIndex

        for match in docRegex.matches(in: sanitized, options: [], range: range) {
            guard let matchRange = Range(match.range, in: sanitized),
                  let keyRange = Range(match.range(at: 1), in: sanitized) else {
                continue
            }

            let prefix = String(sanitized[cursor..<matchRange.lowerBound])
            if !prefix.isEmpty {
                output.append(linkifyRun(prefix, font: font))
            }

            let key = String(sanitized[keyRange])
            var linkRun = AttributedString(key)
            linkRun.font = font
            linkRun.link = URL(string: "doc://\(key)")
            output.append(linkRun)

            cursor = matchRange.upperBound
        }

        let suffix = String(sanitized[cursor...])
        if !suffix.isEmpty {
            output.append(linkifyRun(suffix, font: font))
        }

        return output
    }

    private func linkifyRun(_ text: String, font: Font) -> AttributedString {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        guard let detector else {
            var run = AttributedString(text)
            run.font = font
            return run
        }

        var output = AttributedString()
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var cursor = text.startIndex

        for match in detector.matches(in: text, options: [], range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }

            let prefix = String(text[cursor..<matchRange.lowerBound])
            if !prefix.isEmpty {
                var run = AttributedString(prefix)
                run.font = font
                output.append(run)
            }

            let matched = String(text[matchRange])
            var linkRun = AttributedString(matched)
            linkRun.font = font
            linkRun.link = match.url
            output.append(linkRun)

            cursor = matchRange.upperBound
        }

        let suffix = String(text[cursor...])
        if !suffix.isEmpty {
            var run = AttributedString(suffix)
            run.font = font
            output.append(run)
        }

        return output
    }

    private func sanitizeInline(_ text: String) -> String {
        text.replacingOccurrences(of: "``", with: "")
    }

}
