import Foundation
import Observation

/// Orchestrates PINN model training via an external Python process (macOS only).
///
/// Training flow:
/// 1. Export spectral reference data from SwiftData to JSON
/// 2. Launch Python script with domain-specific configuration
/// 3. Monitor training progress via stdout parsing
/// 4. Import converted CoreML .mlpackage to App Support
/// 5. Register with PINNModelRegistry
///
/// The Python training environment requires:
/// - Python 3.10+ with PyTorch, coremltools v7+
/// - Domain-specific training scripts in `~/Library/Application Support/.../PINN/Scripts/`
///
/// Loss function for all domains uses ReLoBRaLo (Relative Loss Balancing with Random Lookback)
/// for adaptive loss weighting across data loss and physics constraint terms.
@MainActor @Observable
final class PINNTrainingManager {

    // MARK: - Training Status

    enum TrainingStatus: Equatable {
        case idle
        case exportingData
        case training(progress: Double, epoch: Int, totalEpochs: Int)
        case converting
        case importing
        case completed(domain: PINNDomain)
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Ready to train"
            case .exportingData: return "Exporting reference data…"
            case .training(let progress, let epoch, let total):
                return "Training epoch \(epoch)/\(total) (\(Int(progress * 100))%)"
            case .converting: return "Converting to CoreML…"
            case .importing: return "Importing model…"
            case .completed(let domain): return "\(domain.displayName) model training complete"
            case .failed(let msg): return "Training failed: \(msg)"
            }
        }

        var isActive: Bool {
            switch self {
            case .idle, .completed, .failed: return false
            default: return true
            }
        }
    }

    // MARK: - State

    var status: TrainingStatus = .idle

    /// Last training metrics (loss values per epoch).
    var trainingHistory: [TrainingEpochMetrics] = []

    /// The domain currently being trained.
    private(set) var activeDomain: PINNDomain?

    #if os(macOS)
    /// The running Python training process.
    private var trainingProcess: Process?
    #endif

    // MARK: - Directories

    /// Directory for Python training scripts.
    static var scriptsDirectory: URL {
        PINNModelRegistry.modelDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts", isDirectory: true)
    }

    /// Directory for exported training data.
    static var trainingDataDirectory: URL {
        PINNModelRegistry.modelDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("TrainingData", isDirectory: true)
    }

    // MARK: - Training

    /// Train a PINN model for the specified domain.
    ///
    /// - Parameters:
    ///   - domain: The spectral domain to train
    ///   - referenceData: Exported spectral reference data as JSON
    ///   - epochs: Number of training epochs (default 500)
    ///   - learningRate: Initial learning rate (default 1e-3)
    ///   - constraints: Enabled physics constraint IDs (empty = all defaults)
    func train(
        domain: PINNDomain,
        referenceData: Data,
        epochs: Int = 500,
        learningRate: Double = 1e-3,
        constraints: [String] = []
    ) async {
        #if os(macOS)
        guard !status.isActive else {
            Instrumentation.log("PINN training already in progress", area: .mlTraining, level: .warning)
            return
        }

        activeDomain = domain
        trainingHistory = []
        status = .exportingData

        let fm = FileManager.default

        // 1. Ensure directories exist
        try? fm.createDirectory(at: Self.trainingDataDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: PINNModelRegistry.modelDirectory, withIntermediateDirectories: true)

        // 2. Export reference data
        let dataURL = Self.trainingDataDirectory.appendingPathComponent("\(domain.rawValue)_training_data.json")
        do {
            try referenceData.write(to: dataURL)
        } catch {
            status = .failed("Failed to export training data: \(error.localizedDescription)")
            return
        }

        // 3. Find Python training script
        let scriptName = "train_pinn_\(domain.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")).py"
        let scriptURL = Self.scriptsDirectory.appendingPathComponent(scriptName)

        guard fm.fileExists(atPath: scriptURL.path) else {
            status = .failed("Training script not found: \(scriptName). Place it in \(Self.scriptsDirectory.path)")
            return
        }

        // 4. Resolve Python path — auto-detect if user hasn't configured one
        let configuredPython = UserDefaults.standard.string(forKey: "pinnPythonPath") ?? "python3"
        let resolvedPython: String

        if configuredPython == "python3" || configuredPython.isEmpty {
            // No explicit path configured — auto-detect best Python installation
            let detection = PythonEnvironmentDetector.detectAll()
            if let rec = detection.recommended {
                resolvedPython = rec.path
                // Persist for future runs so detection only runs once
                UserDefaults.standard.set(rec.path, forKey: "pinnPythonPath")
                Instrumentation.log(
                    "Auto-detected Python for training: \(rec.summary)",
                    area: .mlTraining, level: .info,
                    details: "path=\(rec.path) version=\(rec.version)"
                )
                if !rec.hasTorch || !rec.hasCoreMLTools {
                    let missing = [
                        rec.hasTorch ? nil : "torch",
                        rec.hasCoreMLTools ? nil : "coremltools",
                        rec.hasSciKitLearn ? nil : "scikit-learn"
                    ].compactMap { $0 }
                    status = .failed("Python found at \(rec.path) but missing required packages: \(missing.joined(separator: ", ")). Run: \(rec.path) -m pip install \(missing.joined(separator: " "))")
                    return
                }
            } else {
                let warnings = detection.warnings.joined(separator: " ")
                status = .failed("No Python 3.10+ found on this system. \(warnings) Install via: brew install python@3.12")
                Instrumentation.log("No Python found for PINN training", area: .mlTraining, level: .error, details: warnings)
                return
            }
        } else {
            resolvedPython = configuredPython
        }

        // 5. Launch Python training process
        status = .training(progress: 0, epoch: 0, totalEpochs: epochs)

        let outputModelURL = PINNModelRegistry.modelDirectory
            .appendingPathComponent("PINN_\(domain.rawValue.replacingOccurrences(of: " ", with: ""))")

        let success = await runPythonTraining(
            pythonPath: resolvedPython,
            scriptURL: scriptURL,
            dataURL: dataURL,
            outputURL: outputModelURL,
            domain: domain,
            epochs: epochs,
            learningRate: learningRate,
            constraints: constraints
        )

        if success {
            // 5. Import the converted CoreML model
            status = .importing
            let mlmodelURL = outputModelURL.appendingPathExtension("mlmodelc")
            if fm.fileExists(atPath: mlmodelURL.path) {
                status = .completed(domain: domain)
                Instrumentation.log(
                    "PINN \(domain.displayName) model trained successfully",
                    area: .mlTraining, level: .info,
                    details: "epochs=\(epochs) path=\(mlmodelURL.path)"
                )
            } else {
                status = .failed("CoreML model file not found after conversion")
            }
        }

        activeDomain = nil
        #else
        status = .failed("PINN training requires macOS — train on Mac and sync via iCloud")
        #endif
    }

    /// Cancel an in-progress training.
    func cancelTraining() {
        #if os(macOS)
        trainingProcess?.terminate()
        trainingProcess = nil
        #endif
        status = .idle
        activeDomain = nil
    }

    // MARK: - Python Process Management (macOS only)

    #if os(macOS)
    private func runPythonTraining(
        pythonPath: String,
        scriptURL: URL,
        dataURL: URL,
        outputURL: URL,
        domain: PINNDomain,
        epochs: Int,
        learningRate: Double,
        constraints: [String]
    ) async -> Bool {
        await withCheckedContinuation { continuation in
            let process = Process()

            // macOS Tahoe hardened runtime blocks Process() from executing
            // Homebrew binaries directly. Use /bin/zsh -l -c to get the user's
            // login shell environment (includes Homebrew PATH).
            let configuredPython = pythonPath

            var argList = [
                scriptURL.path,
                "--data", dataURL.path,
                "--output", outputURL.path,
                "--epochs", String(epochs),
                "--lr", String(learningRate),
                "--domain", domain.rawValue,
                "--loss-balancing", "relobralo"
            ]
            if !constraints.isEmpty {
                argList += ["--constraints", constraints.joined(separator: ",")]
            }
            let scriptArgs = argList.map { arg in
                // Shell-escape arguments that may contain spaces
                arg.contains(" ") ? "'\(arg)'" : arg
            }.joined(separator: " ")

            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-l", "-c", "\(configuredPython) \(scriptArgs)"]
            process.currentDirectoryURL = scriptURL.deletingLastPathComponent()

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                // Parse progress from Python stdout
                // Expected format: "EPOCH:50/500 LOSS:0.0123 PHYSICS_LOSS:0.0045"
                Task { @MainActor [weak self] in
                    self?.parseTrainingOutput(line, totalEpochs: epochs)
                }
            }

            process.terminationHandler = { process in
                Task { @MainActor [weak self] in
                    if process.terminationStatus == 0 {
                        self?.status = .converting
                        continuation.resume(returning: true)
                    } else {
                        let code = process.terminationStatus
                        let detail: String
                        switch code {
                        case 127:
                            detail = "Python not found (exit code 127). Install Python 3.10+ and ensure it is on your PATH. On macOS, run: brew install python@3.12"
                        case 126:
                            detail = "Python script is not executable (exit code 126). Check file permissions on the training script."
                        case 1:
                            detail = "Python script encountered an error (exit code 1). Check the Diagnostics Console → ML Training tab for details."
                        case 2:
                            detail = "Python script received invalid arguments (exit code 2). This may indicate an incompatible script version."
                        default:
                            detail = "Python process exited with code \(code)."
                        }
                        Instrumentation.log(detail, area: .mlTraining, level: .error, details: "exitCode=\(code)")
                        self?.status = .failed(detail)
                        continuation.resume(returning: false)
                    }
                }
            }

            do {
                trainingProcess = process
                try process.run()
            } catch {
                status = .failed("Failed to launch Python: \(error.localizedDescription)")
                continuation.resume(returning: false)
            }
        }
    }

    private func parseTrainingOutput(_ output: String, totalEpochs: Int) {
        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Parse "EPOCH:50/500 LOSS:0.0123 PHYSICS_LOSS:0.0045"
            if trimmed.hasPrefix("EPOCH:") {
                let components = trimmed.components(separatedBy: " ")
                if let epochPart = components.first?.replacingOccurrences(of: "EPOCH:", with: ""),
                   let slashIdx = epochPart.firstIndex(of: "/"),
                   let currentEpoch = Int(epochPart[..<slashIdx]) {

                    let progress = Double(currentEpoch) / Double(totalEpochs)
                    status = .training(progress: progress, epoch: currentEpoch, totalEpochs: totalEpochs)

                    // Extract loss values
                    var dataLoss: Double?
                    var physicsLoss: Double?
                    for comp in components {
                        if comp.hasPrefix("LOSS:") {
                            dataLoss = Double(comp.replacingOccurrences(of: "LOSS:", with: ""))
                        }
                        if comp.hasPrefix("PHYSICS_LOSS:") {
                            physicsLoss = Double(comp.replacingOccurrences(of: "PHYSICS_LOSS:", with: ""))
                        }
                    }

                    if let dl = dataLoss {
                        trainingHistory.append(TrainingEpochMetrics(
                            epoch: currentEpoch,
                            dataLoss: dl,
                            physicsLoss: physicsLoss ?? 0,
                            totalLoss: dl + (physicsLoss ?? 0)
                        ))
                    }
                }
            }
        }
    }
    #endif
}

// MARK: - Training Metrics

struct TrainingEpochMetrics: Identifiable, Sendable {
    let id = UUID()
    let epoch: Int
    let dataLoss: Double
    let physicsLoss: Double
    let totalLoss: Double
}
