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

    // MARK: - Shared Per-Domain Managers

    /// Shared per-domain training managers, created on demand.
    /// Ensures training status is visible across all views (Jobs & Downloads, ML Training sidebar).
    static var managers: [PINNDomain: PINNTrainingManager] = [:]

    /// Returns the shared training manager for a domain, creating one if needed.
    static func manager(for domain: PINNDomain) -> PINNTrainingManager {
        if let existing = managers[domain] { return existing }
        let new = PINNTrainingManager()
        managers[domain] = new
        return new
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

        // Build a Python conversion script that includes the full PINN architecture
        // (ModifiedMLP, FourierFeatureEncoding, AdaptiveTanh, etc.) so the state dict
        // can be loaded into the correct model structure before CoreML conversion.
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

        # ---- Architecture classes (must match training scripts exactly) ----

        class AdaptiveTanh(nn.Module):
            def __init__(self):
                super().__init__()
                self.a = nn.Parameter(torch.ones(1))
            def forward(self, x):
                return torch.tanh(self.a * x)

        class AdaptiveGELU(nn.Module):
            def __init__(self):
                super().__init__()
                self.a = nn.Parameter(torch.ones(1))
            def forward(self, x):
                return nn.functional.gelu(self.a * x)

        def make_activation(name='adaptive_tanh'):
            if name == 'adaptive_tanh': return AdaptiveTanh()
            elif name == 'adaptive_gelu': return AdaptiveGELU()
            elif name == 'tanh': return nn.Tanh()
            elif name == 'gelu': return nn.GELU()
            else: return nn.Tanh()

        class FourierFeatureEncoding(nn.Module):
            def __init__(self, input_dim, num_frequencies=64, sigma=10.0):
                super().__init__()
                B = torch.randn(input_dim, num_frequencies) * sigma
                self.register_buffer('B', B)
                self.output_dim = 2 * num_frequencies
            def forward(self, x):
                proj = x @ self.B
                return torch.cat([torch.sin(proj), torch.cos(proj)], dim=-1)

        class ModifiedMLP(nn.Module):
            def __init__(self, input_dim, hidden_dims, fourier=None, activation='adaptive_tanh'):
                super().__init__()
                self.fourier = fourier
                enc_dim = fourier.output_dim if fourier is not None else input_dim
                self.encoder_U = nn.Linear(enc_dim, hidden_dims[0])
                self.encoder_V = nn.Linear(enc_dim, hidden_dims[0])
                self.gate_projs = nn.ModuleList()
                self.layers = nn.ModuleList()
                self.activations = nn.ModuleList()
                for i in range(len(hidden_dims) - 1):
                    out_dim = hidden_dims[i + 1]
                    self.layers.append(nn.Linear(hidden_dims[i], out_dim))
                    self.activations.append(make_activation(activation))
                    if out_dim != hidden_dims[0]:
                        self.gate_projs.append(nn.Linear(hidden_dims[0], out_dim, bias=False))
                    else:
                        self.gate_projs.append(nn.Identity())
                self.output_layer = nn.Linear(hidden_dims[-1], 1)
                self.first_activation = make_activation(activation)
            def forward(self, x):
                if self.fourier is not None:
                    x = self.fourier(x)
                U = self.first_activation(self.encoder_U(x))
                V = self.first_activation(self.encoder_V(x))
                h = U
                for i, (layer, act) in enumerate(zip(self.layers, self.activations)):
                    h_new = act(layer(h))
                    Ug = self.gate_projs[i](U)
                    Vg = self.gate_projs[i](V)
                    h_new = h_new * Ug + (1 - h_new) * Vg
                    if h_new.shape[-1] == h.shape[-1]:
                        h_new = h_new + h
                    h = h_new
                return self.output_layer(h)

        # ---- Load state dict and detect architecture ----

        state = torch.load(pt_path, map_location="cpu", weights_only=False)
        print(f"Loaded state dict with {len(state)} keys", flush=True)
        all_keys = sorted(state.keys())
        print(f"Keys: {all_keys[:20]}{'...' if len(all_keys) > 20 else ''}", flush=True)

        # Strip wrapper class prefix from state dict keys.
        # Training scripts wrap ModifiedMLP in domain-specific classes (e.g. RamanPINN)
        # that nest it under "mlp." or "ensemble.backbone." prefix.
        for _pfx in ["ensemble.backbone.", "mlp.", "ensemble."]:
            if any(k.startswith(_pfx) for k in state):
                state = {(k[len(_pfx):] if k.startswith(_pfx) else k): v
                         for k, v in state.items()}
                print(f"Stripped wrapper prefix '{_pfx}' from state dict keys", flush=True)
                break

        has_encoder_U = any(k.startswith("encoder_U") for k in state)
        has_fourier = "fourier.B" in state
        has_net = any(k.startswith("net.") for k in state)
        has_trunk = any(k.startswith("trunk.") for k in state)

        if has_encoder_U:
            # ModifiedMLP architecture
            print("Detected ModifiedMLP architecture", flush=True)

            # Infer hidden_dims from layer weights
            hidden_dims = []
            enc_out = state["encoder_U.weight"].shape[0]
            hidden_dims.append(enc_out)

            layer_idx = 0
            while f"layers.{layer_idx}.weight" in state:
                w = state[f"layers.{layer_idx}.weight"]
                hidden_dims.append(w.shape[0])
                layer_idx += 1

            # Detect activation type from state dict keys
            has_adaptive = any("activations" in k and ".a" in k for k in state)
            act_name = 'adaptive_tanh' if has_adaptive else 'tanh'

            # Detect Fourier encoding
            if has_fourier:
                B = state["fourier.B"]
                raw_input_dim = B.shape[0]
                num_freq = B.shape[1]
                fourier = FourierFeatureEncoding(raw_input_dim, num_freq)
                fourier.B.copy_(B)
                input_dim = raw_input_dim
                print(f"Fourier: input_dim={raw_input_dim}, num_freq={num_freq}", flush=True)
            else:
                fourier = None
                input_dim = state["encoder_U.weight"].shape[1]
                print(f"No Fourier encoding, input_dim={input_dim}", flush=True)

            print(f"hidden_dims={hidden_dims}, activation={act_name}", flush=True)
            model = ModifiedMLP(input_dim, hidden_dims, fourier=fourier, activation=act_name)

        elif has_net or has_trunk:
            # Sequential-based architecture (domain-specific PINN class)
            prefix = "trunk." if has_trunk else "net."
            print(f"Detected Sequential architecture (prefix='{prefix}')", flush=True)

            # Collect linear layer dimensions in order
            layer_idx = 0
            dims = []
            while f"{prefix}{layer_idx}.weight" in state:
                w = state[f"{prefix}{layer_idx}.weight"]
                if layer_idx == 0:
                    dims.append(w.shape[1])
                dims.append(w.shape[0])
                layer_idx += 2  # skip activation modules between linear layers

            # Detect activation type
            has_adaptive = any(".a" in k for k in state if prefix in k)
            act_name = 'adaptive_tanh' if has_adaptive else 'tanh'

            # Build Sequential model
            if has_fourier:
                B = state["fourier.B"]
                raw_input_dim = B.shape[0]
                num_freq = B.shape[1]
                fourier = FourierFeatureEncoding(raw_input_dim, num_freq)
                fourier.B.copy_(B)
                enc_dim = 2 * num_freq
                input_dim = raw_input_dim
                # Replace first layer input dim
                if dims:
                    dims[0] = enc_dim
                print(f"Fourier: raw_input={raw_input_dim}, enc_dim={enc_dim}", flush=True)
            else:
                fourier = None
                input_dim = dims[0] if dims else 1

            seq_layers = []
            for i in range(len(dims) - 1):
                seq_layers.append(nn.Linear(dims[i], dims[i + 1]))
                if i < len(dims) - 2:
                    seq_layers.append(make_activation(act_name))

            class SeqPINN(nn.Module):
                def __init__(self, fourier_enc, sequential):
                    super().__init__()
                    self.fourier = fourier_enc
                    if has_trunk:
                        self.trunk = sequential
                        self.heads = nn.ModuleList()
                        # Check for multi-head
                        head_idx = 0
                        while f"heads.{head_idx}.weight" in state:
                            w = state[f"heads.{head_idx}.weight"]
                            self.heads.append(nn.Linear(w.shape[1], w.shape[0]))
                            head_idx += 1
                    else:
                        self.net = sequential
                def forward(self, x):
                    if self.fourier is not None:
                        x = self.fourier(x)
                    if hasattr(self, 'trunk'):
                        features = self.trunk(x)
                        if len(self.heads) > 0:
                            return torch.cat([h(features) for h in self.heads], dim=-1)
                        return features
                    return self.net(x)

            model = SeqPINN(fourier, nn.Sequential(*seq_layers))
            print(f"dims={dims}, activation={act_name}", flush=True)

        else:
            # Fallback: reconstruct from any 2D weight tensors
            print("Fallback: generic weight reconstruction", flush=True)
            weight_keys = sorted([k for k in state if "weight" in k and state[k].dim() == 2])
            if not weight_keys:
                print("ERROR: No 2D weight tensors found", flush=True)
                sys.exit(1)
            input_dim = state[weight_keys[0]].shape[1]
            layers = []
            for k in weight_keys:
                w = state[k]
                layers.append(nn.Linear(w.shape[1], w.shape[0]))
            seq = []
            for i, l in enumerate(layers):
                seq.append(l)
                if i < len(layers) - 1:
                    seq.append(nn.Tanh())
            model = nn.Sequential(*seq)

        # ---- Load weights ----
        try:
            model.load_state_dict(state, strict=True)
            print("Loaded weights (strict=True)", flush=True)
        except Exception as e:
            print(f"strict=True failed ({e}), trying strict=False", flush=True)
            try:
                model.load_state_dict(state, strict=False)
                print("Loaded weights (strict=False)", flush=True)
            except Exception as e2:
                print(f"WARNING: Weight load issue: {e2}", flush=True)

        # ---- Convert to CoreML ----
        model.eval()
        example = torch.randn(1, input_dim)

        try:
            with torch.no_grad():
                traced = torch.jit.trace(model, example)

            mlmodel = ct.convert(
                traced,
                inputs=[ct.TensorType(name="input", shape=(1, input_dim))],
                convert_to="mlprogram",
                minimum_deployment_target=ct.target.macOS15,
            )
        except Exception as e:
            print(f"ERROR: CoreML conversion failed: {e}", flush=True)
            print(f"PyTorch model remains at {pt_path}", flush=True)
            sys.exit(2)

        package_path = output_base + ".mlpackage"
        mlmodel.save(package_path)
        print(f"Saved .mlpackage at {package_path}", flush=True)

        # Try to compile
        import subprocess
        compiled_path = output_base + ".mlmodelc"
        compile_cmd = ['/usr/bin/xcrun', 'coremlcompiler', 'compile', package_path, os.path.dirname(output_base)]
        result = subprocess.run(compile_cmd, capture_output=True, text=True, timeout=300)
        if os.path.exists(compiled_path):
            print(f"Compiled to {compiled_path}", flush=True)
        else:
            print(f"Compilation failed (exit {result.returncode}), .mlpackage is still usable", flush=True)
            if result.stdout:
                print(f"coremlcompiler stdout: {result.stdout[:1000]}", flush=True)
            if result.stderr:
                print(f"coremlcompiler stderr: {result.stderr[:1000]}", flush=True)
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
                let errorExcerpt = lastTrainingLog
                    .components(separatedBy: .newlines)
                    .filter { $0.hasPrefix("ERROR:") }
                    .last ?? "exit code \(process.terminationStatus)"
                status = .failed("Conversion failed: \(errorExcerpt). Full log in Diagnostics Console.")
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
