import Foundation
import CoreML
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

    /// Full stdout/stderr log from the last Python training run.
    var lastTrainingLog: String = ""

    /// Whether CoreML conversion was skipped (model saved as .pt only).
    var conversionSkipped = false

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
        lastTrainingLog = ""
        conversionSkipped = false
        status = .exportingData

        let fm = FileManager.default

        // 1. Ensure directories exist
        try? fm.createDirectory(at: Self.trainingDataDirectory, withIntermediateDirectories: true)
        try? fm.createDirectory(at: PINNModelRegistry.modelDirectory, withIntermediateDirectories: true)

        // 2. Export reference data
        let dataURL = Self.trainingDataDirectory.appendingPathComponent("\(domain.scriptBaseName)_training_data.json")
        do {
            try referenceData.write(to: dataURL)
        } catch {
            status = .failed("Failed to export training data: \(error.localizedDescription)")
            return
        }

        // 3. Find Python training script
        let scriptName = "train_pinn_\(domain.scriptBaseName).py"
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
            .appendingPathComponent(domain.modelBaseName)

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
            let mlpackageURL = outputModelURL.appendingPathExtension("mlpackage")
            let ptURL = outputModelURL.appendingPathExtension("pt")

            // 5a. If .mlpackage exists but .mlmodelc does not, compile it via CoreML
            if !fm.fileExists(atPath: mlmodelURL.path), fm.fileExists(atPath: mlpackageURL.path) {
                do {
                    let compiledURL = try await Task.detached {
                        try MLModel.compileModel(at: mlpackageURL)
                    }.value
                    // compileModel returns a temp URL — move it to the final location
                    if fm.fileExists(atPath: mlmodelURL.path) {
                        try? fm.removeItem(at: mlmodelURL)
                    }
                    try fm.moveItem(at: compiledURL, to: mlmodelURL)
                    Instrumentation.log(
                        "Compiled .mlpackage → .mlmodelc via CoreML",
                        area: .mlTraining, level: .info,
                        details: "path=\(mlmodelURL.path)"
                    )
                } catch {
                    Instrumentation.log(
                        "Swift-side .mlpackage compilation failed: \(error.localizedDescription)",
                        area: .mlTraining, level: .warning,
                        details: "Will fall back to .mlpackage loading"
                    )
                }
            }

            if fm.fileExists(atPath: mlmodelURL.path) {
                status = .completed(domain: domain)
                Instrumentation.log(
                    "PINN \(domain.displayName) model trained successfully",
                    area: .mlTraining, level: .info,
                    details: "epochs=\(epochs) path=\(mlmodelURL.path)"
                )
            } else if fm.fileExists(atPath: mlpackageURL.path) {
                // .mlpackage saved but compilation to .mlmodelc failed — still usable
                status = .completed(domain: domain)
                Instrumentation.log(
                    "PINN \(domain.displayName) model trained — .mlpackage saved (compilation to .mlmodelc skipped)",
                    area: .mlTraining, level: .warning,
                    details: "epochs=\(epochs) path=\(mlpackageURL.path)"
                )
            } else if fm.fileExists(atPath: ptURL.path) {
                // CoreML conversion skipped entirely — PyTorch model saved
                status = .completed(domain: domain)
                Instrumentation.log(
                    "PINN \(domain.displayName) model trained — PyTorch .pt saved (CoreML conversion skipped, likely coremltools incompatibility)",
                    area: .mlTraining, level: .warning,
                    details: "epochs=\(epochs) path=\(ptURL.path)"
                )
            } else {
                status = .failed("No model file found after training. Check Python output in Diagnostics Console.")
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

    /// Retry CoreML conversion for a domain that has a .pt file but no .mlpackage.
    /// Runs a minimal Python script that loads the .pt state dict, traces, and converts.
    func retryConversion(for domain: PINNDomain) async {
        #if os(macOS)
        let fm = FileManager.default
        let modelBase = PINNModelRegistry.modelDirectory
            .appendingPathComponent(domain.modelBaseName)
        let ptURL = modelBase.appendingPathExtension("pt")
        let mlpackageURL = modelBase.appendingPathExtension("mlpackage")
        let mlmodelURL = modelBase.appendingPathExtension("mlmodelc")

        guard fm.fileExists(atPath: ptURL.path) else {
            status = .failed("No .pt model file found for \(domain.displayName)")
            return
        }

        status = .converting
        activeDomain = domain
        conversionSkipped = false

        // Build a minimal Python script that converts the .pt to .mlpackage.
        // The script auto-detects input_dim from the state dict's first weight tensor,
        // so no featureCount mapping is needed on the Swift side.
        let script = """
        import sys, os
        try:
            import torch
            import torch.nn as nn
        except ImportError as e:
            print(f"ERROR: PyTorch not available: {e}", flush=True)
            sys.exit(1)

        try:
            import coremltools as ct
        except ImportError as e:
            print(f"ERROR: coremltools not available: {e}", flush=True)
            print("Install with: pip install coremltools", flush=True)
            sys.exit(1)

        pt_path = sys.argv[1]
        output_base = sys.argv[2]

        # Load state dict and auto-detect architecture
        state = torch.load(pt_path, map_location="cpu", weights_only=True)
        weight_keys = sorted([k for k in state.keys() if "weight" in k and state[k].dim() == 2])
        print(f"Loaded state dict with {len(state)} keys, {len(weight_keys)} weight layers", flush=True)

        if not weight_keys:
            print("ERROR: No 2D weight tensors found in state dict", flush=True)
            sys.exit(1)

        # Infer input_dim from first weight layer's shape[1]
        input_dim = state[weight_keys[0]].shape[1]
        print(f"Auto-detected input_dim={input_dim}", flush=True)

        # Reconstruct feedforward model matching state dict layer shapes
        layers = []
        prev_dim = input_dim
        for k in weight_keys:
            w = state[k]
            out_dim = w.shape[0]
            layers.append(nn.Linear(prev_dim, out_dim))
            prev_dim = out_dim

        # Build sequential with Tanh activations between linear layers
        seq_layers = []
        for i, layer in enumerate(layers):
            seq_layers.append(layer)
            if i < len(layers) - 1:
                seq_layers.append(nn.Tanh())
        model = nn.Sequential(*seq_layers)

        # Load weights
        try:
            model.load_state_dict(state, strict=False)
            print("Loaded weights (strict=False)", flush=True)
        except Exception as e:
            print(f"WARNING: Partial weight load: {e}", flush=True)

        model.eval()
        example = torch.randn(1, input_dim)
        traced = torch.jit.trace(model, example)

        mlmodel = ct.convert(
            traced,
            inputs=[ct.TensorType(name="input", shape=(1, input_dim))],
            minimum_deployment_target=ct.target.macOS13,
        )

        package_path = output_base + ".mlpackage"
        mlmodel.save(package_path)
        print(f"Saved .mlpackage at {package_path}", flush=True)

        # Try to compile
        compiled_path = output_base + ".mlmodelc"
        exit_code = os.system(f'/usr/bin/xcrun coremlcompiler compile "{package_path}" "{os.path.dirname(output_base)}"')
        if os.path.exists(compiled_path):
            print(f"Compiled to {compiled_path}", flush=True)
        else:
            print(f"Compilation skipped (exit {exit_code}), .mlpackage is still usable", flush=True)
        """

        // Resolve Python path using the same logic as train()
        let configuredPython = UserDefaults.standard.string(forKey: "pinnPythonPath") ?? "python3"
        let resolvedPython: String
        if configuredPython == "python3" || configuredPython.isEmpty {
            let detection = PythonEnvironmentDetector.detectAll()
            guard let rec = detection.recommended else {
                status = .failed("No Python 3.10+ found. Install via: brew install python@3.12")
                activeDomain = nil
                return
            }
            guard rec.hasTorch && rec.hasCoreMLTools else {
                let missing = [
                    rec.hasTorch ? nil : "torch",
                    rec.hasCoreMLTools ? nil : "coremltools"
                ].compactMap { $0 }
                status = .failed("Python found but missing: \(missing.joined(separator: ", ")). Run: \(rec.path) -m pip install \(missing.joined(separator: " "))")
                activeDomain = nil
                return
            }
            resolvedPython = rec.path
        } else {
            resolvedPython = configuredPython
        }

        let tempScript = fm.temporaryDirectory.appendingPathComponent("pinn_convert_\(domain.scriptBaseName).py")
        try? script.write(to: tempScript, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-l", "-c", "\(resolvedPython) '\(tempScript.path)' '\(ptURL.path)' '\(modelBase.path)'"]
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()

            // Capture output for diagnostics
            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            let stdout = String(data: stdoutData, encoding: .utf8) ?? ""
            let stderr = String(data: stderrData, encoding: .utf8) ?? ""
            lastTrainingLog = "=== Conversion Output ===\n\(stdout)\n\(stderr)"

            Instrumentation.log(
                "CoreML conversion retry for \(domain.displayName)",
                area: .mlTraining, level: process.terminationStatus == 0 ? .info : .warning,
                details: "exit=\(process.terminationStatus) stdout=\(stdout.prefix(500))"
            )

            if process.terminationStatus != 0 {
                status = .failed("Conversion failed (exit \(process.terminationStatus)). Check Diagnostics Console.")
                activeDomain = nil
                return
            }
        } catch {
            status = .failed("Failed to run conversion: \(error.localizedDescription)")
            activeDomain = nil
            return
        }

        // Try Swift-side compilation if .mlpackage exists but .mlmodelc doesn't
        status = .importing
        if !fm.fileExists(atPath: mlmodelURL.path), fm.fileExists(atPath: mlpackageURL.path) {
            do {
                let compiledURL = try await Task.detached {
                    try MLModel.compileModel(at: mlpackageURL)
                }.value
                if fm.fileExists(atPath: mlmodelURL.path) {
                    try? fm.removeItem(at: mlmodelURL)
                }
                try fm.moveItem(at: compiledURL, to: mlmodelURL)
            } catch {
                Instrumentation.log(
                    "Swift-side .mlpackage compilation failed during retry",
                    area: .mlTraining, level: .warning,
                    details: error.localizedDescription
                )
            }
        }

        // Check final state
        if fm.fileExists(atPath: mlmodelURL.path) || fm.fileExists(atPath: mlpackageURL.path) {
            status = .completed(domain: domain)
            conversionSkipped = false
            // Reload models so the registry picks up the new CoreML model
            await PINNPredictionService.shared.loadModels()
        } else {
            status = .failed("Conversion produced no CoreML model. Check Python environment.")
        }

        try? fm.removeItem(at: tempScript)
        activeDomain = nil
        #else
        status = .failed("CoreML conversion requires macOS")
        #endif
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

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Thread-safe stderr accumulator
            let stderrBuffer = StderrBuffer()

            stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let line = String(data: data, encoding: .utf8) else { return }

                Task { @MainActor [weak self] in
                    self?.lastTrainingLog += line
                    // Detect CoreML conversion skipped
                    if line.contains("CONVERSION_SKIPPED") {
                        self?.conversionSkipped = true
                    }
                    self?.parseTrainingOutput(line, totalEpochs: epochs)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                stderrBuffer.append(text)
                Task { @MainActor [weak self] in
                    self?.lastTrainingLog += text
                }
            }

            process.terminationHandler = { [weak self] process in
                let stderrText = stderrBuffer.value
                Task { @MainActor [weak self] in
                    let code = process.terminationStatus
                    let convSkipped = self?.conversionSkipped ?? false

                    // Log the full stderr for diagnostics
                    if !stderrText.isEmpty {
                        Instrumentation.log(
                            "Python stderr output",
                            area: .mlTraining, level: code == 0 ? .info : .error,
                            details: String(stderrText.suffix(2000))
                        )
                    }

                    if code == 0 || convSkipped {
                        // Training succeeded — conversion may have been skipped
                        if convSkipped {
                            Instrumentation.log(
                                "CoreML conversion was skipped — PyTorch .pt model saved",
                                area: .mlTraining, level: .warning,
                                details: "The model was trained successfully but coremltools conversion failed. The .pt file can be converted manually."
                            )
                        }
                        self?.status = .converting
                        continuation.resume(returning: true)
                    } else {
                        // Extract the last meaningful error from stderr
                        let lastLines = stderrText
                            .components(separatedBy: .newlines)
                            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                            .suffix(5)
                            .joined(separator: "\n")

                        let detail: String
                        switch code {
                        case 127:
                            detail = "Python not found (exit code 127). Install Python 3.10+ and ensure it is on your PATH. On macOS, run: brew install python@3.12"
                        case 126:
                            detail = "Python script is not executable (exit code 126). Check file permissions on the training script."
                        case 2:
                            detail = "Python script received invalid arguments (exit code 2). This may indicate an incompatible script version."
                        default:
                            if !lastLines.isEmpty {
                                detail = "Python error (exit code \(code)):\n\(lastLines)"
                            } else {
                                detail = "Python script encountered an error (exit code \(code)). Check the Diagnostics Console → ML Training tab for details."
                            }
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

/// Thread-safe string accumulator for stderr capture from Process pipes.
nonisolated private final class StderrBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = ""

    func append(_ text: String) {
        lock.lock()
        buffer += text
        lock.unlock()
    }

    var value: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }
}
