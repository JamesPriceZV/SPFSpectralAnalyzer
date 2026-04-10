import Foundation
import Observation

/// Downloads and stages training data from external sources into per-domain folders.
///
/// Each domain gets its own staging directory under:
/// `~/Library/Application Support/com.zincoverde.SPFSpectralAnalyzer/TrainingData/{domain_name}/Downloads/`
///
/// Downloaded files are placed in domain-specific subfolders to prevent intermingling.
@MainActor @Observable
final class TrainingDataDownloader {

    static let shared = TrainingDataDownloader()

    // MARK: - State

    enum DownloadStatus: Equatable {
        case idle
        case downloading(source: String, progress: Double)
        case staging(source: String)
        case completed(fileCount: Int)
        case failed(String)

        var isActive: Bool {
            switch self {
            case .downloading, .staging: return true
            default: return false
            }
        }
    }

    var status: DownloadStatus = .idle

    /// Per-source download status, keyed by source name.
    enum SourceStatus: Equatable {
        case pending
        case downloading(bytesDownloaded: Int64, totalBytes: Int64?)
        case completed(fileSize: Int64)
        case failed(String)

        /// Convenience check for the old `.downloading` pattern match.
        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }

        var isCompleted: Bool {
            if case .completed = self { return true }
            return false
        }

        /// Progress fraction 0...1 (nil if total unknown).
        var progress: Double? {
            if case .downloading(let done, let total) = self, let t = total, t > 0 {
                return Double(done) / Double(t)
            }
            return nil
        }
    }

    var sourceStatuses: [String: SourceStatus] = [:]

    /// Maximum number of concurrent downloads.
    static let maxConcurrentDownloads = 10

    private init() {}

    /// Checks whether a source already has downloaded data files in the domain folder.
    static func isSourceDownloaded(_ source: PINNDomain.TrainingDataSource, for domain: PINNDomain) -> Bool {
        let files = downloadedFiles(for: domain)
        let safeName = source.name
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "—", with: "-")
        return files.contains { file in
            let name = file.lastPathComponent
            // Match by safe source name prefix, exclude landing pages
            return name.contains(safeName) && !name.contains("LANDING_PAGE")
        }
    }

    // MARK: - Directory Management

    /// Returns the download staging directory for a specific domain.
    /// Creates the directory if it doesn't exist.
    static func downloadDirectory(for domain: PINNDomain) -> URL {
        let base = PINNTrainingManager.trainingDataDirectory
        let domainFolder = domain.rawValue.replacingOccurrences(of: " ", with: "_")
        let dir = base.appendingPathComponent(domainFolder, isDirectory: true)
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Lists downloaded files for a domain.
    static func downloadedFiles(for domain: PINNDomain) -> [URL] {
        let dir = downloadDirectory(for: domain)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.fileSizeKey, .creationDateKey]
        ) else { return [] }
        return items.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Total size of downloaded data for a domain.
    static func downloadedSize(for domain: PINNDomain) -> Int64 {
        let files = downloadedFiles(for: domain)
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            return total + Int64(size)
        }
    }

    /// Formatted size string.
    static func formattedSize(bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    // MARK: - Figshare API Resolution

    /// Extracts the Figshare article ID from a figshare.com URL.
    /// Supports patterns like /ndownloader/articles/{id}/versions/{v} and /articles/{id}.
    private static func figshareArticleID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), host.contains("figshare.com") else { return nil }
        let components = url.pathComponents
        guard let articlesIndex = components.firstIndex(of: "articles"),
              articlesIndex + 1 < components.count else { return nil }
        return components[articlesIndex + 1]
    }

    /// Resolves a Figshare article URL to direct file download URLs via the Figshare API v2.
    /// Returns an array of (filename, downloadURL) pairs.
    private static func resolveFigshareFiles(articleID: String) async throws -> [(name: String, url: URL)] {
        let apiURL = URL(string: "https://api.figshare.com/v2/articles/\(articleID)/files")!
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "SPFSpectralAnalyzer/1.0 (macOS; spectral-data-download)"
        ]
        let session = URLSession(configuration: config)
        let (data, response) = try await session.data(from: apiURL)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw URLError(.badServerResponse, userInfo: [NSLocalizedDescriptionKey: "Figshare API returned HTTP \(code)"])
        }

        guard let files = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse, userInfo: [NSLocalizedDescriptionKey: "Unexpected Figshare API response format"])
        }

        return files.compactMap { fileDict -> (name: String, url: URL)? in
            guard let name = fileDict["name"] as? String,
                  let downloadURLString = fileDict["download_url"] as? String,
                  let downloadURL = URL(string: downloadURLString) else { return nil }
            return (name: name, url: downloadURL)
        }
    }

    // MARK: - Download

    /// Downloads training data from a source URL into the domain's staging folder.
    /// Figshare URLs are automatically resolved via the Figshare API v2 to get direct file downloads.
    /// Uses URLSessionDownloadTask with progress tracking via delegate.
    func downloadSource(_ source: PINNDomain.TrainingDataSource, for domain: PINNDomain) async {
        guard let url = source.url else {
            sourceStatuses[source.name] = .failed("No URL")
            return
        }

        // Figshare URLs: resolve via API to get direct file download links
        if let articleID = Self.figshareArticleID(from: url) {
            await downloadFigshareArticle(articleID: articleID, source: source, domain: domain)
            return
        }

        sourceStatuses[source.name] = .downloading(bytesDownloaded: 0, totalBytes: nil)
        status = .downloading(source: source.name, progress: 0)

        let destDir = Self.downloadDirectory(for: domain)
        let sourceName = source.name

        do {
            let (fileURL, response) = try await downloadWithProgress(url: url, sourceName: sourceName)
            defer { try? FileManager.default.removeItem(at: fileURL) }

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                sourceStatuses[sourceName] = .failed("HTTP \(code)")
                return
            }

            // Read first 512 bytes for format sniffing (avoids loading entire file into memory)
            let prefixData: Data
            do {
                let handle = try FileHandle(forReadingFrom: fileURL)
                prefixData = handle.readData(ofLength: 512)
                handle.closeFile()
            } catch {
                prefixData = Data()
            }
            let fileSize = Int64((try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)

            let rawPrefix = String(data: prefixData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let detectedFormat = Self.detectDataFormat(prefix: rawPrefix, data: prefixData)

            if let format = detectedFormat {
                let safeName = sourceName
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "—", with: "-")
                let dataURL = destDir.appendingPathComponent("\(safeName).\(format.fileExtension)")
                try? FileManager.default.removeItem(at: dataURL)
                try FileManager.default.moveItem(at: fileURL, to: dataURL)

                Instrumentation.log(
                    "Downloaded \(format.name) data for \(domain.displayName)",
                    area: .mlTraining, level: .info,
                    details: "source=\(sourceName) format=\(format.name) size=\(fileSize)"
                )
                sourceStatuses[sourceName] = .completed(fileSize: fileSize)
                return
            }

            // Check for HTML (landing pages)
            let contentType = (httpResponse.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
            let isHTML = contentType.contains("text/html")
            let lowerPrefix = rawPrefix.lowercased()
            let looksLikeHTML = lowerPrefix.hasPrefix("<!doctype") || lowerPrefix.hasPrefix("<html")
                || lowerPrefix.hasPrefix("<!") || lowerPrefix.contains("<head>")

            if isHTML || looksLikeHTML {
                let safeName = sourceName.replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                let htmlURL = destDir.appendingPathComponent("\(safeName)_LANDING_PAGE.html")
                try? FileManager.default.removeItem(at: htmlURL)
                try? FileManager.default.moveItem(at: fileURL, to: htmlURL)
                sourceStatuses[sourceName] = .failed("HTML page")
                return
            }

            // Unknown format — save with original or derived filename
            let rawLastComponent = url.lastPathComponent
            let usesQueryParams = url.query != nil && (rawLastComponent.hasSuffix(".cgi") || rawLastComponent.hasSuffix(".pl") || rawLastComponent.hasSuffix(".php"))
            let baseName: String
            if rawLastComponent.isEmpty || usesQueryParams {
                baseName = sourceName
                    .replacingOccurrences(of: " ", with: "_")
                    .replacingOccurrences(of: "/", with: "_")
                    .replacingOccurrences(of: "—", with: "-")
            } else {
                baseName = rawLastComponent.replacingOccurrences(of: " ", with: "_")
            }
            let destFileURL = destDir.appendingPathComponent(baseName)
            try? FileManager.default.removeItem(at: destFileURL)
            try FileManager.default.moveItem(at: fileURL, to: destFileURL)
            sourceStatuses[sourceName] = .completed(fileSize: fileSize)

            Instrumentation.log(
                "Training data downloaded for \(domain.displayName)",
                area: .mlTraining, level: .info,
                details: "source=\(sourceName) size=\(fileSize)"
            )
        } catch {
            sourceStatuses[sourceName] = .failed(error.localizedDescription)
            Instrumentation.log(
                "Training data download failed",
                area: .mlTraining, level: .warning,
                details: "source=\(sourceName) error=\(error.localizedDescription)"
            )
        }
    }

    /// Downloads data from a URL with byte-level progress reporting back to `sourceStatuses`.
    /// Downloads data from a URL with byte-level progress reporting.
    /// Returns a stable temp file URL (caller must clean up) and the HTTP response.
    /// Files are NOT loaded into memory — supports multi-GB downloads.
    private func downloadWithProgress(url: URL, sourceName: String) async throws -> (URL, URLResponse) {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 1800
        config.httpAdditionalHeaders = [
            "User-Agent": "SPFSpectralAnalyzer/1.0 (macOS; spectral-data-download)"
        ]
        let delegate = DownloadProgressDelegate()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        // Set up the progress callback (fires on delegate queue, updates MainActor)
        let name = sourceName
        delegate.onProgress = { [weak self] bytesWritten, totalBytes in
            Task { @MainActor [weak self] in
                self?.sourceStatuses[name] = .downloading(
                    bytesDownloaded: bytesWritten,
                    totalBytes: totalBytes > 0 ? totalBytes : nil
                )
            }
        }

        let (localURL, response) = try await session.download(from: url)
        // Move to stable temp path — URLSession temp files may be reclaimed immediately
        let stableURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: localURL, to: stableURL)
        return (stableURL, response)
    }

    /// Downloads all files from a Figshare article using the API v2.
    private func downloadFigshareArticle(articleID: String, source: PINNDomain.TrainingDataSource, domain: PINNDomain) async {
        let sourceName = source.name
        sourceStatuses[sourceName] = .downloading(bytesDownloaded: 0, totalBytes: nil)
        let destDir = Self.downloadDirectory(for: domain)

        do {
            let files = try await Self.resolveFigshareFiles(articleID: articleID)
            guard !files.isEmpty else {
                sourceStatuses[sourceName] = .failed("No files")
                return
            }

            Instrumentation.log(
                "Figshare API resolved \(files.count) file(s) for article \(articleID)",
                area: .mlTraining, level: .info,
                details: "source=\(sourceName) files=\(files.map(\.name).joined(separator: ", "))"
            )

            var totalSize: Int64 = 0
            for file in files {
                let (fileURL, response) = try await downloadWithProgress(url: file.url, sourceName: sourceName)
                defer { try? FileManager.default.removeItem(at: fileURL) }
                guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { continue }
                let destURL = destDir.appendingPathComponent(file.name)
                try? FileManager.default.removeItem(at: destURL)
                try FileManager.default.moveItem(at: fileURL, to: destURL)
                let size = Int64((try? destURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                totalSize += size
            }

            sourceStatuses[sourceName] = .completed(fileSize: totalSize)
        } catch {
            sourceStatuses[sourceName] = .failed(error.localizedDescription)
            Instrumentation.log(
                "Figshare article download failed",
                area: .mlTraining, level: .warning,
                details: "articleID=\(articleID) source=\(sourceName) error=\(error.localizedDescription)"
            )
        }
    }

    /// Downloads all available (non-licensed) training data sources for a domain **concurrently**.
    /// Uses up to `maxConcurrentDownloads` parallel tasks.
    func downloadAllSources(for domain: PINNDomain) async {
        let sources = domain.trainingDataSourcesWithURLs.filter { $0.url != nil && !$0.isLicensed }

        // Initialize per-source statuses
        for source in sources {
            if Self.isSourceDownloaded(source, for: domain) {
                let size = Self.downloadedFiles(for: domain)
                    .filter { $0.lastPathComponent.contains(source.name.replacingOccurrences(of: " ", with: "_")) }
                    .reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                sourceStatuses[source.name] = .completed(fileSize: size)
            } else {
                sourceStatuses[source.name] = .pending
            }
        }

        let pending = sources.filter { !(sourceStatuses[$0.name]?.isCompleted ?? false) }
        guard !pending.isEmpty else {
            let files = Self.downloadedFiles(for: domain)
            status = .completed(fileCount: files.count)
            return
        }

        status = .downloading(source: "0/\(pending.count) sources", progress: 0)

        // Concurrent downloads with throttling
        await withTaskGroup(of: Void.self) { group in
            var launched = 0
            var completed = 0
            let total = pending.count

            for source in pending {
                // Throttle: wait until a slot is free
                if launched >= Self.maxConcurrentDownloads {
                    await group.next()
                    completed += 1
                    await MainActor.run {
                        status = .downloading(
                            source: "\(completed)/\(total) sources",
                            progress: Double(completed) / Double(total)
                        )
                    }
                }

                let downloader = self
                let capturedSource = source
                let capturedDomain = domain
                group.addTask {
                    await downloader.downloadSource(capturedSource, for: capturedDomain)
                }
                launched += 1
            }

            // Wait for remaining
            for await _ in group {
                completed += 1
                status = .downloading(
                    source: "\(completed)/\(total) sources",
                    progress: Double(completed) / Double(total)
                )
            }
        }

        let files = Self.downloadedFiles(for: domain)
        status = .completed(fileCount: files.count)
    }

    /// Downloads all available (non-licensed) sources across all domains concurrently.
    func downloadAllDomains() async {
        let domains = PINNDomain.allCases
        var totalDownloaded = 0
        let totalDomains = domains.count

        for (i, domain) in domains.enumerated() {
            status = .downloading(
                source: "\(domain.displayName) (\(i+1)/\(totalDomains))",
                progress: Double(i) / Double(totalDomains)
            )
            await downloadAllSources(for: domain)
            totalDownloaded += Self.downloadedFiles(for: domain).count
        }

        status = .completed(fileCount: totalDownloaded)
    }

    /// Summary of downloaded training data across all domains.
    static func allDomainsDownloadSummary() -> [(domain: PINNDomain, fileCount: Int, size: Int64)] {
        PINNDomain.allCases.map { domain in
            let files = downloadedFiles(for: domain)
            let size = downloadedSize(for: domain)
            return (domain: domain, fileCount: files.count, size: size)
        }
    }

    /// Whether any training data has been downloaded for any domain.
    static var hasAnyDownloadedData: Bool {
        PINNDomain.allCases.contains { !downloadedFiles(for: $0).isEmpty }
    }

    /// Opens the download folder for a domain in Finder.
    func openDownloadFolder(for domain: PINNDomain) {
        let dir = Self.downloadDirectory(for: domain)
        PlatformURLOpener.open(dir)
    }

    /// Clears all downloaded data for a domain.
    func clearDownloads(for domain: PINNDomain) {
        let dir = Self.downloadDirectory(for: domain)
        try? FileManager.default.removeItem(at: dir)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        sourceStatuses.removeAll()
        status = .idle
    }

    // MARK: - Download Progress Delegate

    /// URLSession delegate that reports download progress via a closure.
    private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
        /// Called with (bytesWritten, totalBytesExpectedToWrite). totalBytes is -1 if unknown.
        var onProgress: ((_ bytesWritten: Int64, _ totalBytes: Int64) -> Void)?

        /// Stores the downloaded file URL so the async `download(from:)` call can access it.
        private var downloadedFileURL: URL?

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                        totalBytesExpectedToWrite: Int64) {
            onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
        }

        func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                        didFinishDownloadingTo location: URL) {
            downloadedFileURL = location
        }
    }

    // MARK: - Content Format Detection

    /// Known spectral data format detected from file content.
    enum DetectedFormat {
        case jcampDX
        case csv
        case json
        case sdf
        case msp
        case xyText
        case gzip

        var fileExtension: String {
            switch self {
            case .jcampDX: return "jdx"
            case .csv:     return "csv"
            case .json:    return "json"
            case .sdf:     return "sdf"
            case .msp:     return "msp"
            case .xyText:  return "txt"
            case .gzip:    return "csv.gz"
            }
        }

        var name: String {
            switch self {
            case .jcampDX: return "JCAMP-DX"
            case .csv:     return "CSV"
            case .json:    return "JSON"
            case .sdf:     return "SDF"
            case .msp:     return "MSP"
            case .xyText:  return "XY Text"
            case .gzip:    return "Gzip"
            }
        }
    }

    /// Detects the data format from the first bytes of downloaded content.
    /// Returns nil if no known spectral data format is detected.
    static func detectDataFormat(prefix: String, data: Data) -> DetectedFormat? {
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)

        // JCAMP-DX: starts with ## labels
        if trimmed.hasPrefix("##TITLE") || trimmed.hasPrefix("##JCAMP")
            || trimmed.hasPrefix("##ORIGIN") || trimmed.hasPrefix("##DATA TYPE")
            || (trimmed.hasPrefix("##") && trimmed.contains("=")) {
            return .jcampDX
        }

        // JSON: starts with { or [
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            return .json
        }

        // SDF/MOL: starts with molecule name line then counts line then "M  END" eventually
        // SDF records end with $$$$
        if trimmed.contains("M  END") || trimmed.contains("$$$$") || trimmed.contains("V2000") || trimmed.contains("V3000") {
            return .sdf
        }

        // MSP: starts with NAME: or starts with field headers
        let upper = trimmed.uppercased()
        if upper.hasPrefix("NAME:") || (upper.contains("NUM PEAKS:") && upper.contains("MW:")) {
            return .msp
        }

        // Gzip: magic bytes 0x1F 0x8B
        if data.count >= 2, data[data.startIndex] == 0x1F, data[data.startIndex + 1] == 0x8B {
            return .gzip
        }

        // CSV: contains comma-separated values with a header row
        let firstLine = trimmed.components(separatedBy: .newlines).first ?? ""
        if firstLine.contains(",") && !firstLine.hasPrefix("<") {
            let commaCount = firstLine.filter { $0 == "," }.count
            if commaCount >= 2 {
                return .csv
            }
        }

        // XY text: lines of "number number" (whitespace-separated numeric pairs)
        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") && !$0.hasPrefix("//") }
        if lines.count >= 3 {
            var numericPairCount = 0
            for line in lines.prefix(10) {
                let tokens = line.components(separatedBy: CharacterSet.whitespaces)
                    .filter { !$0.isEmpty }
                if tokens.count >= 2, Double(tokens[0]) != nil, Double(tokens[1]) != nil {
                    numericPairCount += 1
                }
            }
            if numericPairCount >= 3 {
                return .xyText
            }
        }

        return nil
    }
}
