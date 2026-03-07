import Foundation

enum ConsoleCapture {
    static func start() {
        Task {
            await ConsoleCaptureActor.shared.start()
        }
    }
}

actor ConsoleCaptureActor {
    static let shared = ConsoleCaptureActor()

    private let consoleLogStorageKey = "consoleLogEntriesData"
    private let maxEntries = 2000
    private let maxEntriesPerSecond = 120
    private let streamingPauseKey = "diagnosticsStreamingPaused"

    private var isStarted = false
    private var streamWindowStart = Date()
    private var streamCount = 0
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var stdoutBuffer = ""
    private var stderrBuffer = ""
    private var originalStdout: Int32 = -1
    private var originalStderr: Int32 = -1

    private enum Stream {
        case stdout
        case stderr
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true

        originalStdout = dup(STDOUT_FILENO)
        originalStderr = dup(STDERR_FILENO)

        let outPipe = Pipe()
        let errPipe = Pipe()
        stdoutPipe = outPipe
        stderrPipe = errPipe

        dup2(outPipe.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
        dup2(errPipe.fileHandleForWriting.fileDescriptor, STDERR_FILENO)

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await ConsoleCaptureActor.shared.handle(data: data, source: .stdout)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task {
                await ConsoleCaptureActor.shared.handle(data: data, source: .stderr)
            }
        }
    }

    private func handle(data: Data, source: Stream) {
        switch source {
        case .stdout:
            forward(data: data, originalFD: originalStdout)
            process(data: data, buffer: &stdoutBuffer, sourceLabel: "stdout")
        case .stderr:
            forward(data: data, originalFD: originalStderr)
            process(data: data, buffer: &stderrBuffer, sourceLabel: "stderr")
        }
    }

    private func forward(data: Data, originalFD: Int32) {
        guard originalFD >= 0 else { return }
        let handle = FileHandle(fileDescriptor: originalFD, closeOnDealloc: false)
        try? handle.write(contentsOf: data)
    }

    private func process(data: Data, buffer: inout String, sourceLabel: String) {
        guard let chunk = String(data: data, encoding: .utf8) else { return }
        buffer.append(chunk)
        let lines = buffer.components(separatedBy: "\n")
        guard lines.count > 1 else { return }
        buffer = lines.last ?? ""
        for line in lines.dropLast() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            guard shouldAcceptLine() else { continue }
            let payload = DiagnosticsLogEntryPayload(timestamp: Date(), message: "[\(sourceLabel)] \(trimmed)")
            persist(payload)
            Task { @MainActor in
                NotificationCenter.default.post(name: .consoleLog, object: payload.message)
            }
        }
    }

    private func persist(_ payload: DiagnosticsLogEntryPayload) {
        let defaults = UserDefaults.standard
        let existingData = defaults.data(forKey: consoleLogStorageKey) ?? Data()
        var entries = (try? JSONDecoder().decode([DiagnosticsLogEntryPayload].self, from: existingData)) ?? []
        entries.append(payload)
        if entries.count > maxEntries {
            entries.removeFirst(entries.count - maxEntries)
        }
        if let data = try? JSONEncoder().encode(entries) {
            defaults.set(data, forKey: consoleLogStorageKey)
        }
    }

    private func shouldAcceptLine() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: streamingPauseKey) {
            return false
        }

        let now = Date()
        if now.timeIntervalSince(streamWindowStart) >= 1.0 {
            streamWindowStart = now
            streamCount = 0
        }

        if streamCount >= maxEntriesPerSecond {
            return false
        }

        streamCount += 1
        return true
    }
}

extension Notification.Name {
    static let consoleLog = Notification.Name("ConsoleLog")
}
