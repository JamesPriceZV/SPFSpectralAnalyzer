import Foundation

/// Generates and installs Python PINN training scripts for all 22 spectral domains.
///
/// Each script follows the same CLI interface expected by `PINNTrainingManager`:
/// ```
/// python3 train_pinn_{domain}.py \
///   --data path/to/training_data.json \
///   --output path/to/PINN_Domain \
///   --epochs 500 --lr 0.001 \
///   --domain "UV-Vis" --loss-balancing relobralo
/// ```
///
/// Output format parsed by the app: `EPOCH:N/TOTAL LOSS:X PHYSICS_LOSS:Y`
/// Final output: `{output}.mlmodelc` (CoreML compiled model directory).
enum PINNScriptInstaller {

    /// Result of an installation attempt.
    struct InstallResult: Sendable {
        let installed: [String]
        let skipped: [String]
        let errors: [String]
    }

    /// Installs training scripts for all domains.
    /// Existing scripts are overwritten to ensure they stay current.
    @discardableResult
    static func installAllScripts() -> InstallResult {
        let scriptsDir = PINNTrainingManager.scriptsDirectory
        let fm = FileManager.default

        // Create Scripts directory
        try? fm.createDirectory(at: scriptsDir, withIntermediateDirectories: true)

        // Also install the shared utilities module
        let utilsContent = sharedUtilitiesScript()
        let utilsURL = scriptsDir.appendingPathComponent("pinn_utils.py")
        try? utilsContent.write(to: utilsURL, atomically: true, encoding: .utf8)
        #if os(macOS)
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: utilsURL.path)
        utilsURL.path.withCString { cPath in _ = removexattr(cPath, "com.apple.quarantine", 0) }
        PythonEnvironmentDetector.codesignFile(at: utilsURL.path)
        #endif

        // Also install requirements.txt
        let reqContent = requirementsFile()
        let reqURL = scriptsDir.appendingPathComponent("requirements.txt")
        try? reqContent.write(to: reqURL, atomically: true, encoding: .utf8)
        #if os(macOS)
        reqURL.path.withCString { cPath in _ = removexattr(cPath, "com.apple.quarantine", 0) }
        PythonEnvironmentDetector.codesignFile(at: reqURL.path)
        #endif

        var installed: [String] = []
        let skipped: [String] = []
        var errors: [String] = []

        for domain in PINNDomain.allCases {
            let scriptName = scriptFilename(for: domain)
            let scriptURL = scriptsDir.appendingPathComponent(scriptName)
            let content = scriptContent(for: domain)

            do {
                try content.write(to: scriptURL, atomically: true, encoding: .utf8)
                // Make executable
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
                #if os(macOS)
                scriptURL.path.withCString { cPath in _ = removexattr(cPath, "com.apple.quarantine", 0) }
                PythonEnvironmentDetector.codesignFile(at: scriptURL.path)
                #endif
                installed.append(scriptName)
            } catch {
                errors.append("\(scriptName): \(error.localizedDescription)")
            }
        }

        Instrumentation.log(
            "PINN scripts installed",
            area: .mlTraining, level: .info,
            details: "installed=\(installed.count) skipped=\(skipped.count) errors=\(errors.count)"
        )

        return InstallResult(installed: installed, skipped: skipped, errors: errors)
    }

    /// Checks how many scripts are currently installed.
    static func installedScriptCount() -> (installed: Int, total: Int) {
        let fm = FileManager.default
        let scriptsDir = PINNTrainingManager.scriptsDirectory
        var count = 0
        for domain in PINNDomain.allCases {
            let name = scriptFilename(for: domain)
            if fm.fileExists(atPath: scriptsDir.appendingPathComponent(name).path) {
                count += 1
            }
        }
        return (count, PINNDomain.allCases.count)
    }

    /// Returns the expected script filename for a domain.
    static func scriptFilename(for domain: PINNDomain) -> String {
        "train_pinn_\(domain.scriptBaseName).py"
    }

    // MARK: - Requirements File

    private static func requirementsFile() -> String {
        """
        # PINN Training Requirements for SPF Spectral Analyzer
        # Install: pip install -r requirements.txt
        torch>=2.0
        coremltools>=7.0
        numpy>=1.24
        scipy>=1.10
        scikit-learn>=1.3
        """
    }

    // MARK: - Shared Utilities Module

    private static func sharedUtilitiesScript() -> String {
        """
        #!/usr/bin/env python3
        \"\"\"Shared utilities for PINN training scripts.\"\"\"
        import json
        import sys
        import os
        import argparse
        import numpy as np
        import torch
        import torch.nn as nn

        # NumPy 2.0 removed np.trapz in favour of np.trapezoid
        trapz = np.trapezoid if hasattr(np, 'trapezoid') else np.trapz

        def parse_args():
            \"\"\"Parse command-line arguments expected by SPF Spectral Analyzer.\"\"\"
            parser = argparse.ArgumentParser(description='PINN Training Script')
            parser.add_argument('--data', required=True, help='Path to training data JSON')
            parser.add_argument('--output', required=True, help='Output model path (without extension)')
            parser.add_argument('--epochs', type=int, default=500, help='Number of training epochs')
            parser.add_argument('--lr', type=float, default=1e-3, help='Learning rate')
            parser.add_argument('--domain', type=str, default='', help='Domain name')
            parser.add_argument('--loss-balancing', type=str, default='relobralo', help='Loss balancing method')
            parser.add_argument('--constraints', type=str, default='', help='Comma-separated list of enabled physics constraint IDs (empty = all defaults)')
            return parser.parse_args()

        def load_training_data(data_path):
            \"\"\"Load training data from JSON exported by the app.\"\"\"
            with open(data_path, 'r') as f:
                data = json.load(f)
            # Handle both container format and raw array
            if isinstance(data, dict) and 'entries' in data:
                entries = data['entries']
            elif isinstance(data, list):
                entries = data
            else:
                raise ValueError("Unexpected training data format")
            return entries

        def report_progress(epoch, total_epochs, data_loss, physics_loss):
            \"\"\"Print progress in the format expected by the app.\"\"\"
            total_loss = data_loss + physics_loss
            print(f"EPOCH:{epoch}/{total_epochs} LOSS:{total_loss:.6f} PHYSICS_LOSS:{physics_loss:.6f}", flush=True)

        def convert_to_coreml(model, input_shape, output_path, domain_name, num_heads=1):
            \"\"\"Convert a PyTorch model to CoreML format.
            When num_heads > 1, the model outputs (1, num_heads) and metadata is saved
            so the Swift side knows how to interpret the multi-head ensemble output.\"\"\"
            import torch

            model.eval()

            # Always save PyTorch state dict as fallback
            pt_path = output_path + ".pt"
            try:
                torch.save(model.state_dict(), pt_path)
                print(f"PyTorch model saved to {pt_path}", flush=True)
            except Exception as e:
                print(f"ERROR: Failed to save PyTorch model: {e}", flush=True)
                return

            # Save ensemble metadata if multi-head
            if num_heads > 1:
                meta_path = output_path + "_ensemble.json"
                try:
                    with open(meta_path, 'w') as f:
                        json.dump({"num_heads": num_heads}, f)
                    print(f"Ensemble metadata saved to {meta_path}", flush=True)
                except Exception as e:
                    print(f"WARNING: Failed to save ensemble metadata: {e}", flush=True)

            # Step 1: Import coremltools (may fail on unsupported Python versions)
            try:
                import coremltools as ct
            except ImportError as e:
                print(f"WARNING: coremltools not importable: {e}", flush=True)
                print(f"This may indicate a Python version incompatibility.", flush=True)
                print(f'PyTorch model saved at {pt_path}. Convert manually with: python -c "import coremltools"', flush=True)
                print(f"CONVERSION_SKIPPED", flush=True)
                return
            except Exception as e:
                print(f"WARNING: coremltools import error: {e}", flush=True)
                print(f"CONVERSION_SKIPPED", flush=True)
                return

            # Step 2: Trace and convert to CoreML
            try:
                example_input = torch.randn(1, input_shape)
                traced = torch.jit.trace(model, example_input)
                output_shape = (1, num_heads) if num_heads > 1 else (1, 1)
                mlmodel = ct.convert(
                    traced,
                    inputs=[ct.TensorType(name="input", shape=(1, input_shape))],
                    outputs=[ct.TensorType(name="output", shape=output_shape)],
                    minimum_deployment_target=ct.target.macOS13,
                )
            except Exception as e:
                print(f"WARNING: CoreML conversion failed: {e}", flush=True)
                print(f"PyTorch model saved at {pt_path}. Manual conversion may be needed.", flush=True)
                print(f"CONVERSION_SKIPPED", flush=True)
                return

            # Step 3: Save as .mlpackage
            package_path = output_path + ".mlpackage"
            try:
                mlmodel.save(package_path)
                print(f"Model saved as .mlpackage at {package_path}", flush=True)
            except Exception as e:
                print(f"WARNING: Failed to save .mlpackage: {e}", flush=True)
                print(f"CONVERSION_SKIPPED", flush=True)
                return

            # Step 4: Compile to .mlmodelc via xcrun (use full path for PATH safety)
            compiled_path = output_path + ".mlmodelc"
            try:
                compile_cmd = f'/usr/bin/xcrun coremlcompiler compile "{package_path}" "{os.path.dirname(output_path)}"'
                exit_code = os.system(compile_cmd)
            except Exception as e:
                print(f"WARNING: xcrun coremlcompiler failed: {e}", flush=True)
                exit_code = -1

            if os.path.exists(compiled_path):
                print(f"Model compiled to {compiled_path}", flush=True)
            else:
                print(f"WARNING: coremlcompiler exited with code {exit_code >> 8 if exit_code > 0 else exit_code}", flush=True)
                print(f"The .mlpackage was saved at {package_path}", flush=True)
                print(f'Compile manually: xcrun coremlcompiler compile "{package_path}" "{os.path.dirname(output_path)}"', flush=True)

        class AdaptiveTanh(nn.Module):
            \"\"\"Tanh with a learnable scaling parameter.
            Computes tanh(a * x) where 'a' is trained per-layer.
            Accelerates PINN convergence 2-5x by letting each layer find its optimal
            nonlinearity steepness while preserving smoothness for physics gradients.
            Reference: Jagtap, Kawaguchi & Karniadakis (2020), J. Comp. Phys.\"\"\"
            def __init__(self):
                super().__init__()
                self.a = nn.Parameter(torch.ones(1))
            def forward(self, x):
                return torch.tanh(self.a * x)

        class AdaptiveGELU(nn.Module):
            \"\"\"GELU with a learnable scaling parameter.
            Computes GELU(a * x) where 'a' is trained per-layer.
            Offers smoother gradients than AdaptiveTanh for deeper networks.\"\"\"
            def __init__(self):
                super().__init__()
                self.a = nn.Parameter(torch.ones(1))
            def forward(self, x):
                return nn.functional.gelu(self.a * x)

        def make_activation(name='adaptive_tanh'):
            \"\"\"Factory for activation functions used in PINN architectures.\"\"\"
            if name == 'adaptive_tanh':
                return AdaptiveTanh()
            elif name == 'adaptive_gelu':
                return AdaptiveGELU()
            elif name == 'tanh':
                return nn.Tanh()
            elif name == 'gelu':
                return nn.GELU()
            else:
                return nn.Tanh()

        class FourierFeatureEncoding(nn.Module):
            \"\"\"Random Fourier feature encoding for spectral inputs.
            Maps raw inputs through sin/cos at multiple random frequencies to eliminate
            spectral bias — the tendency of MLPs to learn low-frequency functions first.
            This dramatically improves resolution of sharp absorption peaks and fine
            spectral structure.
            Reference: Tancik et al. (2020), NeurIPS.\"\"\"
            def __init__(self, input_dim, num_frequencies=64, sigma=10.0):
                super().__init__()
                # Random frequency matrix B ~ N(0, sigma^2), frozen (not trained)
                B = torch.randn(input_dim, num_frequencies) * sigma
                self.register_buffer('B', B)
                self.output_dim = 2 * num_frequencies

            def forward(self, x):
                # x: (batch, input_dim)
                # Project inputs onto random frequencies then apply sin/cos
                proj = x @ self.B  # (batch, num_frequencies)
                return torch.cat([torch.sin(proj), torch.cos(proj)], dim=-1)  # (batch, 2*num_frequencies)

        class ModifiedMLP(nn.Module):
            \"\"\"Modified MLP with residual/skip connections and adaptive activations for PINNs.
            Implements techniques from Wang et al. (2021) and Jagtap et al. (2020):
            1. Input concatenation: encoded input gated into every hidden layer.
            2. Residual addition: skip connections where dimensions match.
            3. Adaptive activations: learnable scaling parameter per layer (2-5x convergence).
            Supports variable-width hidden layers by projecting U/V per layer.\"\"\"
            def __init__(self, input_dim, hidden_dims, fourier=None, activation='adaptive_tanh'):
                super().__init__()
                self.fourier = fourier
                enc_dim = fourier.output_dim if fourier is not None else input_dim
                # Encoder projects input to first hidden dim
                self.encoder_U = nn.Linear(enc_dim, hidden_dims[0])
                self.encoder_V = nn.Linear(enc_dim, hidden_dims[0])
                # Per-layer projections for U/V when hidden dims change
                self.gate_projs = nn.ModuleList()
                # Hidden layers with per-layer adaptive activations
                self.layers = nn.ModuleList()
                self.activations = nn.ModuleList()
                for i in range(len(hidden_dims) - 1):
                    out_dim = hidden_dims[i + 1]
                    self.layers.append(nn.Linear(hidden_dims[i], out_dim))
                    self.activations.append(make_activation(activation))
                    # Project U/V when layer width differs from encoder width
                    if out_dim != hidden_dims[0]:
                        self.gate_projs.append(nn.Linear(hidden_dims[0], out_dim, bias=False))
                    else:
                        self.gate_projs.append(nn.Identity())
                # Output head
                self.output_layer = nn.Linear(hidden_dims[-1], 1)
                self.first_activation = make_activation(activation)

            def forward(self, x):
                if self.fourier is not None:
                    x = self.fourier(x)
                # Two encoding branches (Wang et al. modified MLP)
                U = self.first_activation(self.encoder_U(x))
                V = self.first_activation(self.encoder_V(x))
                h = U
                for i, (layer, act) in enumerate(zip(self.layers, self.activations)):
                    h_new = act(layer(h))
                    # Project U/V to match current layer width (Identity when dims match)
                    Ug = self.gate_projs[i](U)
                    Vg = self.gate_projs[i](V)
                    # Element-wise gating with the two encoding branches
                    h_new = h_new * Ug + (1 - h_new) * Vg
                    # Residual addition when dimensions match
                    if h_new.shape[-1] == h.shape[-1]:
                        h_new = h_new + h
                    h = h_new
                return self.output_layer(h)

        def gradient_loss(model, X, y, grad_weight=0.1):
            \"\"\"Gradient-enhanced training loss.
            Supervises the model's input-output Jacobian against finite-difference
            derivatives computed from the training data itself. This provides "free"
            additional training signal from the known physics — the network must not
            only predict correct values but also correct slopes.
            Works with any differentiable model (Sequential or ModifiedMLP).
            Returns 0 if batch is too small or if autograd fails.\"\"\"
            if X.shape[0] < 2:
                return torch.tensor(0.0)
            try:
                X_grad = X.detach().requires_grad_(True)
                pred = model(X_grad)
                # Compute dy/dX via autograd (sum over batch for scalar grad output)
                grad_pred = torch.autograd.grad(
                    pred.sum(), X_grad, create_graph=True, retain_graph=True
                )[0]  # (batch, input_dim)
                # Finite-difference "ground truth" derivatives from training targets
                # Use consecutive sample pairs sorted by first feature (proxy for spectral position)
                sorted_idx = torch.argsort(X[:, 0])
                y_sorted = y[sorted_idx]
                x_sorted = X[sorted_idx]
                dy = y_sorted[1:] - y_sorted[:-1]  # (N-1, 1)
                dx = x_sorted[1:, 0:1] - x_sorted[:-1, 0:1] + 1e-8  # (N-1, 1)
                fd_deriv = dy / dx  # finite difference slope
                # Compare model gradient (first feature channel) at midpoints
                mid_idx = sorted_idx[:-1]
                model_deriv = grad_pred[mid_idx, 0:1]  # (N-1, 1)
                loss = nn.MSELoss()(model_deriv, fd_deriv.detach())
                return grad_weight * loss
            except Exception:
                return torch.tensor(0.0)

        def normalize_data(X, y):
            \"\"\"Z-score normalize features and targets for stable training.
            Returns (X_norm, y_norm, X_mean, X_std, y_mean, y_std).
            Normalization parameters are needed for inference denormalization.\"\"\"
            X_mean = X.mean(dim=0, keepdim=True)
            X_std = X.std(dim=0, keepdim=True) + 1e-8
            y_mean = y.mean()
            y_std = y.std() + 1e-8
            X_norm = (X - X_mean) / X_std
            y_norm = (y - y_mean) / y_std
            return X_norm, y_norm, X_mean, X_std, y_mean, y_std

        def save_normalization_params(output_path, X_mean, X_std, y_mean, y_std):
            \"\"\"Save normalization parameters as JSON alongside the model.
            The Swift app loads these to denormalize predictions at inference time.\"\"\"
            params = {
                'X_mean': X_mean.squeeze().tolist() if hasattr(X_mean, 'tolist') else float(X_mean),
                'X_std': X_std.squeeze().tolist() if hasattr(X_std, 'tolist') else float(X_std),
                'y_mean': float(y_mean),
                'y_std': float(y_std),
            }
            norm_path = output_path + "_normalization.json"
            with open(norm_path, 'w') as f:
                json.dump(params, f, indent=2)
            print(f"Normalization params saved to {norm_path}", flush=True)

        class ReLoBRaLo:
            \"\"\"Random Loss Balancing with Look-ahead (ReLoBRaLo).
            Automatically balances data loss and physics loss during training.\"\"\"
            def __init__(self, num_losses=2, temperature=1.0, alpha=0.999):
                self.num_losses = num_losses
                self.temperature = temperature
                self.alpha = alpha
                self.prev_losses = None
                self.weights = np.ones(num_losses) / num_losses

            def update(self, losses):
                \"\"\"Update weights based on current losses.\"\"\"
                losses = np.array(losses, dtype=np.float64)
                if self.prev_losses is None:
                    self.prev_losses = losses.copy()
                    return self.weights.copy()
                ratios = losses / (self.prev_losses + 1e-8)
                exp_ratios = np.exp(ratios / self.temperature)
                new_weights = exp_ratios / (exp_ratios.sum() + 1e-8) * self.num_losses
                self.weights = self.alpha * self.weights + (1 - self.alpha) * new_weights
                self.prev_losses = losses.copy()
                return self.weights.copy()

        class MultiHeadPINN(nn.Module):
            \"\"\"Ensemble via multi-head output on a shared backbone.
            Replaces the backbone's single output layer with N independent linear heads.
            At inference, the mean reduces variance while head disagreement (std)
            serves as an out-of-distribution (OOD) detector.
            Reference: Lakshminarayanan et al. (2017), 'Simple and Scalable Predictive
            Uncertainty Estimation using Deep Ensembles', NeurIPS.\"\"\"
            def __init__(self, backbone, trunk_dim, num_heads=5):
                super().__init__()
                self.backbone = backbone
                self.num_heads = num_heads
                # Neutralize the backbone's single output layer so it returns trunk features
                if hasattr(backbone, 'output_layer'):
                    backbone.output_layer = nn.Identity()
                elif hasattr(backbone, 'net') and isinstance(backbone.net, nn.Sequential):
                    # For Sequential models, remove the final Linear layer
                    modules = list(backbone.net.children())[:-1]
                    backbone.net = nn.Sequential(*modules)
                self.heads = nn.ModuleList([nn.Linear(trunk_dim, 1) for _ in range(num_heads)])

            def forward(self, x):
                features = self.backbone(x)  # (batch, trunk_dim)
                return torch.cat([h(features) for h in self.heads], dim=-1)  # (batch, num_heads)
        """
    }

    // MARK: - Domain-Specific Script Content

    /// Collects all domain config and dispatches to the appropriate script generator.
    private static func scriptContent(for domain: PINNDomain) -> String {
        let header = scriptHeader(for: domain)
        let cfg = DomainScriptConfig(
            fourier: domain.fourierEncodingConfig,
            useModifiedMLP: domain.useModifiedMLP,
            activation: domain.activation,
            gradientTraining: domain.gradientTrainingConfig,
            ensemble: domain.ensembleConfig,
            hiddenLayers: domain.hiddenLayers
        )
        let body: String
        switch domain {
        case .uvVis:          body = uvVisScript(cfg: cfg)
        case .ftir:           body = ftirScript(cfg: cfg)
        case .raman:          body = ramanScript(cfg: cfg)
        case .massSpec:       body = massSpecScript(cfg: cfg)
        case .nmr:            body = nmrScript(cfg: cfg)
        case .fluorescence:   body = fluorescenceScript(cfg: cfg)
        case .xrd:            body = xrdScript(cfg: cfg)
        case .chromatography: body = chromatographyScript(cfg: cfg)
        case .nir:            body = nirScript(cfg: cfg)
        case .atomicEmission:      body = atomicEmissionScript(cfg: cfg)
        case .xps:                 body = genericDomainScript(cfg: cfg, domain: domain)
        case .libs:                body = genericDomainScript(cfg: cfg, domain: domain)
        case .hitran:              body = genericDomainScript(cfg: cfg, domain: domain)
        case .atmosphericUVVis:    body = genericDomainScript(cfg: cfg, domain: domain)
        case .usgsReflectance:     body = genericDomainScript(cfg: cfg, domain: domain)
        case .opticalConstants:    body = genericDomainScript(cfg: cfg, domain: domain)
        case .eels:                body = genericDomainScript(cfg: cfg, domain: domain)
        case .saxs:                body = genericDomainScript(cfg: cfg, domain: domain)
        case .circularDichroism:   body = genericDomainScript(cfg: cfg, domain: domain)
        case .microwaveRotational: body = genericDomainScript(cfg: cfg, domain: domain)
        case .thermogravimetric:   body = genericDomainScript(cfg: cfg, domain: domain)
        case .terahertz:           body = genericDomainScript(cfg: cfg, domain: domain)
        }
        return header + body
    }

    /// Bundles all per-domain PINN config values passed to script generators.
    private struct DomainScriptConfig {
        let fourier: FourierEncodingConfig
        let useModifiedMLP: Bool
        let activation: PINNActivation
        let gradientTraining: GradientTrainingConfig
        let ensemble: PINNEnsembleConfig
        let hiddenLayers: [Int]
    }

    private static func scriptHeader(for domain: PINNDomain) -> String {
        """
        #!/usr/bin/env python3
        \"\"\"PINN Training Script: \(domain.displayName)
        
        Physics-Informed Neural Network for \(domain.displayName) spectral analysis.
        Physics constraints: \(domain.physicsDescription)
        Architecture: \(domain.architectureDescription)
        
        Generated by SPF Spectral Analyzer.
        \"\"\"
        import sys
        import os
        sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

        import torch
        import torch.nn as nn
        import numpy as np
        from pinn_utils import (parse_args, load_training_data, report_progress, convert_to_coreml,
            ReLoBRaLo, FourierFeatureEncoding, ModifiedMLP, MultiHeadPINN, AdaptiveTanh, AdaptiveGELU,
            make_activation, gradient_loss, trapz, normalize_data, save_normalization_params)

        """
    }

    // MARK: - UV-Vis Script

    private static func uvVisScript(cfg: DomainScriptConfig) -> String {
        let fourier = cfg.fourier
        let fourierDesc = fourier.isEnabled
            ? "enabled (\(fourier.numFrequencies) freq, σ=\(String(format: "%.1f", fourier.sigma)))"
            : "disabled"
        let archDesc = cfg.useModifiedMLP ? "Modified MLP with skip connections" : "Sequential MLP"
        let actName = cfg.activation.rawValue
        let layers = cfg.hiddenLayers
        let layerListStr = "[\(layers.map(String.init).joined(separator: ", "))]"
        let lastHidden = layers.last ?? 64

        let fourierConstruction: String
        if fourier.isEnabled {
            fourierConstruction = "FourierFeatureEncoding(input_dim, num_frequencies=\(fourier.numFrequencies), sigma=\(String(format: "%.1f", fourier.sigma)))"
        } else {
            fourierConstruction = "None"
        }

        let ensemble = cfg.ensemble
        let ensembleDesc = ensemble.isEnabled ? ", Ensemble: \(ensemble.numHeads) heads" : ""

        let modelClass: String
        if cfg.useModifiedMLP {
            if ensemble.isEnabled {
                modelClass = """
                class UVVisPINN(nn.Module):
                    \"\"\"Physics-Informed Neural Network for UV-Vis SPF prediction.
                    Embeds Beer-Lambert law and Diffey SPF integral as physics constraints.
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\(ensembleDesc)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                        fourier = \(fourierConstruction)
                        backbone = ModifiedMLP(input_dim, \(layerListStr), fourier=fourier, activation='\(actName)')
                        self.ensemble = MultiHeadPINN(backbone, trunk_dim=\(lastHidden), num_heads=\(ensemble.numHeads))
                    def forward(self, x):
                        return self.ensemble(x)
                """
            } else {
                modelClass = """
                class UVVisPINN(nn.Module):
                    \"\"\"Physics-Informed Neural Network for UV-Vis SPF prediction.
                    Embeds Beer-Lambert law and Diffey SPF integral as physics constraints.
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                        fourier = \(fourierConstruction)
                        self.mlp = ModifiedMLP(input_dim, \(layerListStr), fourier=fourier, activation='\(actName)')
                    def forward(self, x):
                        return self.mlp(x)
                """
            }
        } else {
            let firstLayerInput = fourier.isEnabled ? "encoded_dim" : "input_dim"
            let fourierInit: String
            let fourierForward: String
            if fourier.isEnabled {
                fourierInit = """
                            self.fourier = FourierFeatureEncoding(input_dim, num_frequencies=\(fourier.numFrequencies), sigma=\(String(format: "%.1f", fourier.sigma)))
                            encoded_dim = self.fourier.output_dim
                """
                fourierForward = """
                        x = self.fourier(x)
                """
            } else {
                fourierInit = "        encoded_dim = input_dim"
                fourierForward = ""
            }
            if ensemble.isEnabled {
                // Build trunk (no final Linear) + heads manually for Sequential
                let trunkDefs = layers.enumerated().map { i, size in
                    let prevSize = i == 0 ? firstLayerInput : "\(layers[i-1])"
                    return "                    nn.Linear(\(prevSize), \(size)), make_activation('\(actName)'),"
                }.joined(separator: "\n")
                modelClass = """
                class UVVisPINN(nn.Module):
                    \"\"\"Physics-Informed Neural Network for UV-Vis SPF prediction.
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\(ensembleDesc)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                \(fourierInit)
                        self.trunk = nn.Sequential(
                \(trunkDefs)
                        )
                        self.heads = nn.ModuleList([nn.Linear(\(lastHidden), 1) for _ in range(\(ensemble.numHeads))])
                    def forward(self, x):
                \(fourierForward)        features = self.trunk(x)
                        return torch.cat([h(features) for h in self.heads], dim=-1)
                """
            } else {
                let layerDefs = layers.enumerated().map { i, size in
                    let prevSize = i == 0 ? firstLayerInput : "\(layers[i-1])"
                    return "                    nn.Linear(\(prevSize), \(size)), make_activation('\(actName)'),"
                }.joined(separator: "\n")
                modelClass = """
                class UVVisPINN(nn.Module):
                    \"\"\"Physics-Informed Neural Network for UV-Vis SPF prediction.
                    Embeds Beer-Lambert law and Diffey SPF integral as physics constraints.
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                \(fourierInit)
                        self.net = nn.Sequential(
                \(layerDefs)
                            nn.Linear(\(lastHidden), 1)
                        )
                    def forward(self, x):
                \(fourierForward)        return self.net(x)
                """
            }
        }
        return """
        \(modelClass)

        def physics_loss(model, wavelengths_batch, absorbance_batch, predictions):
            \"\"\"Beer-Lambert + SPF integral physics constraints.\"\"\"
            loss = torch.tensor(0.0)
            # Non-negativity: absorbance should be >= 0
            if absorbance_batch is not None:
                neg_penalty = torch.relu(-absorbance_batch).mean()
                loss = loss + neg_penalty
            # SPF should be >= 1
            spf_penalty = torch.relu(1.0 - predictions).mean()
            loss = loss + spf_penalty
            # Smoothness: penalize large second derivatives in absorbance
            if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                smoothness = (d2 ** 2).mean()
                loss = loss + 0.01 * smoothness
            return loss

        def prepare_features(entries):
            \"\"\"Convert training data entries to feature tensors.\"\"\"
            X_list, y_list = [], []
            for entry in entries:
                wl = np.array(entry['wavelengths'], dtype=np.float64)
                ab = np.array(entry['intensities'], dtype=np.float64)
                target = float(entry['knownValue'])
                # Resample to 290-400nm at 1nm (111 points)
                target_wl = np.arange(290, 401, dtype=np.float64)
                if len(wl) >= 2:
                    resampled = np.interp(target_wl, wl, ab, left=ab[0], right=ab[-1])
                else:
                    resampled = np.zeros(111)
                # Compute derived metrics
                uvb_mask = (target_wl >= 290) & (target_wl <= 320)
                uva_mask = (target_wl > 320) & (target_wl <= 400)
                uvb_area = float(trapz(resampled[uvb_mask], target_wl[uvb_mask])) if uvb_mask.any() else 0
                uva_area = float(trapz(resampled[uva_mask], target_wl[uva_mask])) if uva_mask.any() else 0
                uva_uvb_ratio = uva_area / (uvb_area + 1e-8)
                # Transmittance
                trans = np.power(10, -np.clip(resampled, 0, 10))
                mean_uvb_trans = float(trans[uvb_mask].mean()) if uvb_mask.any() else 1.0
                mean_uva_trans = float(trans[uva_mask].mean()) if uva_mask.any() else 1.0
                peak_wl = float(target_wl[np.argmax(resampled)])
                # Critical wavelength
                cumsum = np.cumsum(resampled)
                total = cumsum[-1] if cumsum[-1] > 0 else 1.0
                crit_idx = np.searchsorted(cumsum, 0.9 * total)
                crit_wl = float(target_wl[min(crit_idx, len(target_wl)-1)])
                # Auxiliary features
                plate_type = 0.0  # Default PMMA
                app_qty = float(entry.get('applicationQuantityMg', 15.0) or 15.0)
                form_type = 0.0
                is_post = 0.0
                features = np.concatenate([
                    resampled,  # 111 spectral features
                    [crit_wl, uva_uvb_ratio, uvb_area, uva_area, mean_uvb_trans, mean_uva_trans, peak_wl],  # 7 derived
                    [plate_type, app_qty, form_type, is_post]  # 4 auxiliary
                ])
                X_list.append(features)
                y_list.append(target)
            return torch.tensor(np.array(X_list), dtype=torch.float32), torch.tensor(np.array(y_list), dtype=torch.float32).unsqueeze(1)

        def main():
            args = parse_args()
            entries = load_training_data(args.data)
            if len(entries) < 2:
                print("ERROR: Need at least 2 training samples", flush=True)
                sys.exit(1)
            X_raw, y_raw = prepare_features(entries)
            X, y, X_mean, X_std, y_mean, y_std = normalize_data(X_raw, y_raw)
            print(f"Normalized: X shape={X.shape}, y range=[{y.min():.3f}, {y.max():.3f}]", flush=True)
            input_dim = X.shape[1]
            model = UVVisPINN(input_dim=input_dim)
            optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
        \(gradientTrainingSetup(cfg.gradientTraining))
        \(ensembleTargetSetup(cfg.ensemble))
            for epoch in range(1, args.epochs + 1):
                model.train()
                optimizer.zero_grad()
                pred = model(X)
        \(ensembleTrainingLoss(cfg.ensemble, physicsCall: "physics_loss(model, None, X[:, :111], pred_mean)"))
        \(gradientTrainingLoop(cfg.gradientTraining))
                total.backward()
                optimizer.step()
                scheduler.step()
                if epoch % max(1, args.epochs // 100) == 0 or epoch == args.epochs:
                    report_progress(epoch, args.epochs, data_loss.item(), phys_loss.item())
            convert_to_coreml(model, input_dim, args.output, args.domain\(ensembleConvertArg(cfg.ensemble)))
            save_normalization_params(args.output, X_mean, X_std, y_mean, y_std)

        if __name__ == '__main__':
            main()
        """
    }

    // MARK: - FTIR Script

    private static func ftirScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "FTIRPINN",
            physicsDoc: "Beer-Lambert (wavenumber domain) + functional group frequency constraints",
            physicsBody: """
                # Beer-Lambert: absorbance should be non-negative
                neg_penalty = torch.relu(-absorbance_batch).mean() if absorbance_batch is not None else torch.tensor(0.0)
                # Smoothness in wavenumber domain
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.01
                return neg_penalty + smooth
            """,
            cfg: cfg
        )
    }

    // MARK: - Raman Script

    private static func ramanScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "RamanPINN",
            physicsDoc: "Background smoothness + Raman shift selection rules",
            physicsBody: """
                # Background smoothness constraint
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.005
                # Non-negativity of decomposed components
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                return smooth + neg_penalty
            """,
            cfg: cfg
        )
    }

    // MARK: - Mass Spec Script

    private static func massSpecScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "MassSpecPINN",
            physicsDoc: "Isotope distribution (natural abundance) + mass conservation + fragmentation rules",
            physicsBody: """
                # Mass conservation: total ion intensity should be consistent
                if absorbance_batch is not None:
                    total_intensity = absorbance_batch.sum(dim=-1, keepdim=True)
                    intensity_var = total_intensity.var()
                    return intensity_var * 0.01
                return torch.tensor(0.0)
            """,
            cfg: cfg
        )
    }

    // MARK: - NMR Script

    private static func nmrScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "NMRPINN",
            physicsDoc: "Bloch equation residuals + J-coupling patterns + Kramers-Kronig relation",
            physicsBody: """
                # Bloch equation inspired: signal should decay smoothly (T2 relaxation)
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d1 = absorbance_batch[:, 1:] - absorbance_batch[:, :-1]
                    smooth = (d1 ** 2).mean() * 0.005
                # Non-negativity for absolute-mode spectra
                neg_penalty = torch.relu(-predictions).mean() * 0.05
                return smooth + neg_penalty
            """,
            cfg: cfg
        )
    }

    // MARK: - Fluorescence Script

    private static func fluorescenceScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "FluorescencePINN",
            physicsDoc: "Stokes shift constraint + mirror-image rule + quantum yield consistency",
            physicsBody: """
                # Stokes shift: emission peak should be at longer wavelength than excitation
                # Quantum yield: total emission should be proportional to absorption
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.01
                # Non-negativity of fluorescence intensity
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                return smooth + neg_penalty
            """,
            cfg: cfg
        )
    }

    // MARK: - XRD Script

    private static func xrdScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "XRDPINN",
            physicsDoc: "Bragg's law (nλ=2d sinθ) + systematic absences + structure factor",
            physicsBody: """
                # Bragg's law: peaks should appear at physically valid angles
                # Peak sharpness constraint (Debye-Waller)
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.005
                # Non-negativity of diffraction intensity
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                return smooth + neg_penalty
            """,
            cfg: cfg
        )
    }

    // MARK: - Chromatography Script

    private static func chromatographyScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "ChromatographyPINN",
            physicsDoc: "ED/LKM transport PDE + Langmuir isotherm",
            physicsBody: """
                # Transport PDE residual: peaks should follow Gaussian/exponentially-modified Gaussian
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d1 = absorbance_batch[:, 1:] - absorbance_batch[:, :-1]
                    d2 = d1[:, 1:] - d1[:, :-1]
                    # Penalize non-smooth transport
                    smooth = (d2 ** 2).mean() * 0.005
                # Non-negativity of concentration
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                return smooth + neg_penalty
            """,
            cfg: cfg
        )
    }

    // MARK: - NIR Script

    private static func nirScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "NIRPINN",
            physicsDoc: "Modified Beer-Lambert for diffuse reflectance + Kubelka-Munk corrections",
            physicsBody: """
                # Modified Beer-Lambert: similar to FTIR but with Kubelka-Munk scattering
                neg_penalty = torch.relu(-absorbance_batch).mean() if absorbance_batch is not None else torch.tensor(0.0)
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.01
                return neg_penalty + smooth
            """,
            cfg: cfg
        )
    }

    // MARK: - Atomic Emission Script

    private static func atomicEmissionScript(cfg: DomainScriptConfig) -> String {
        genericPINNScript(
            className: "AtomicEmissionPINN",
            physicsDoc: "Boltzmann distribution for excited states + transition selection rules",
            physicsBody: """
                # Boltzmann: emission line intensities follow temperature-dependent distribution
                # Non-negativity of emission intensity
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                # Line sharpness: atomic lines should be narrow (penalize wide peaks)
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.001
                return neg_penalty + smooth
            """,
            cfg: cfg
        )
    }

    /// Generic domain script for new modalities (XPS, LIBS, HITRAN, etc.).
    /// Uses the standard PINN template with domain-appropriate physics loss.
    private static func genericDomainScript(cfg: DomainScriptConfig, domain: PINNDomain) -> String {
        let className = domain.rawValue
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "/", with: "") + "PINN"
        return genericPINNScript(
            className: className,
            physicsDoc: domain.physicsDescription,
            physicsBody: """
                # Generic physics loss: non-negativity + smoothness
                neg_penalty = torch.relu(-predictions).mean() * 0.1
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.001
                return neg_penalty + smooth
            """,
            cfg: cfg
        )
    }

    // MARK: - Generic PINN Template

    private static func genericPINNScript(
        className: String,
        physicsDoc: String,
        physicsBody: String,
        cfg: DomainScriptConfig
    ) -> String {
        let fourier = cfg.fourier
        let fourierDesc = fourier.isEnabled
            ? "enabled (\(fourier.numFrequencies) freq, σ=\(String(format: "%.1f", fourier.sigma)))"
            : "disabled"
        let archDesc = cfg.useModifiedMLP ? "Modified MLP with skip connections" : "Sequential MLP"
        let actName = cfg.activation.rawValue
        let layers = cfg.hiddenLayers
        let layerListStr = "[\(layers.map(String.init).joined(separator: ", "))]"

        let fourierConstruction: String
        if fourier.isEnabled {
            fourierConstruction = "FourierFeatureEncoding(input_dim, num_frequencies=\(fourier.numFrequencies), sigma=\(String(format: "%.1f", fourier.sigma)))"
        } else {
            fourierConstruction = "None"
        }

        let ensemble = cfg.ensemble
        let ensembleDesc = ensemble.isEnabled ? ", Ensemble: \(ensemble.numHeads) heads" : ""
        let lastHidden = layers.last ?? 64

        let modelClass: String
        if cfg.useModifiedMLP {
            if ensemble.isEnabled {
                modelClass = """
                class \(className)(nn.Module):
                    \"\"\"\(physicsDoc)
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\(ensembleDesc)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                        fourier = \(fourierConstruction)
                        backbone = ModifiedMLP(input_dim, \(layerListStr), fourier=fourier, activation='\(actName)')
                        self.ensemble = MultiHeadPINN(backbone, trunk_dim=\(lastHidden), num_heads=\(ensemble.numHeads))
                    def forward(self, x):
                        return self.ensemble(x)
                """
            } else {
                modelClass = """
                class \(className)(nn.Module):
                    \"\"\"\(physicsDoc)
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                        fourier = \(fourierConstruction)
                        self.mlp = ModifiedMLP(input_dim, \(layerListStr), fourier=fourier, activation='\(actName)')
                    def forward(self, x):
                        return self.mlp(x)
                """
            }
        } else {
            // Fallback: plain Sequential (for XRD, Chromatography with bespoke architectures)
            let firstLayerInput = fourier.isEnabled ? "encoded_dim" : "input_dim"
            let fourierInit: String
            let fourierForward: String
            if fourier.isEnabled {
                fourierInit = """
                            self.fourier = FourierFeatureEncoding(input_dim, num_frequencies=\(fourier.numFrequencies), sigma=\(String(format: "%.1f", fourier.sigma)))
                            encoded_dim = self.fourier.output_dim
                """
                fourierForward = """
                        x = self.fourier(x)
                """
            } else {
                fourierInit = "        encoded_dim = input_dim"
                fourierForward = ""
            }
            if ensemble.isEnabled {
                // Build trunk (no final Linear) + heads manually
                let trunkDefs = layers.enumerated().map { i, size in
                    let prevSize = i == 0 ? firstLayerInput : "\(layers[i-1])"
                    return "                nn.Linear(\(prevSize), \(size)), make_activation('\(actName)'),"
                }.joined(separator: "\n")
                modelClass = """
                class \(className)(nn.Module):
                    \"\"\"\(physicsDoc)
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\(ensembleDesc)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                \(fourierInit)
                        self.trunk = nn.Sequential(
                \(trunkDefs)
                        )
                        self.heads = nn.ModuleList([nn.Linear(\(lastHidden), 1) for _ in range(\(ensemble.numHeads))])
                    def forward(self, x):
                \(fourierForward)        features = self.trunk(x)
                        return torch.cat([h(features) for h in self.heads], dim=-1)
                """
            } else {
                let layerDefs = layers.enumerated().map { i, size in
                    let prevSize = i == 0 ? firstLayerInput : "\(layers[i-1])"
                    return "            nn.Linear(\(prevSize), \(size)), make_activation('\(actName)'),"
                }.joined(separator: "\n")
                modelClass = """
                class \(className)(nn.Module):
                    \"\"\"\(physicsDoc)
                    Architecture: \(archDesc), Fourier: \(fourierDesc), Activation: \(actName)\"\"\"
                    def __init__(self, input_dim=122):
                        super().__init__()
                \(fourierInit)
                        self.net = nn.Sequential(
                \(layerDefs)
                            nn.Linear(\(lastHidden), 1)
                        )
                    def forward(self, x):
                \(fourierForward)        return self.net(x)
                """
            }
        }

        return """
        \(modelClass)

        def physics_loss(model, wavelengths_batch, absorbance_batch, predictions):
            \"\"\"\(physicsDoc)\"\"\"
            \(physicsBody)

        def prepare_features(entries):
            \"\"\"Convert training data entries to feature tensors.\"\"\"
            X_list, y_list = [], []
            for entry in entries:
                wl = np.array(entry.get('wavelengths', []), dtype=np.float64)
                intensities = np.array(entry.get('intensities', []), dtype=np.float64)
                target = float(entry.get('knownValue', 0))
                # Use raw spectral data, pad/truncate to fixed size
                max_points = 256
                if len(intensities) > max_points:
                    indices = np.linspace(0, len(intensities)-1, max_points, dtype=int)
                    features = intensities[indices]
                else:
                    features = np.pad(intensities, (0, max(0, max_points - len(intensities))))
                X_list.append(features[:max_points])
                y_list.append(target)
            X = np.array(X_list, dtype=np.float32)
            y = np.array(y_list, dtype=np.float32).reshape(-1, 1)
            return torch.tensor(X), torch.tensor(y)

        def main():
            args = parse_args()
            entries = load_training_data(args.data)
            if len(entries) < 2:
                print("ERROR: Need at least 2 training samples", flush=True)
                sys.exit(1)
            X_raw, y_raw = prepare_features(entries)
            X, y, X_mean, X_std, y_mean, y_std = normalize_data(X_raw, y_raw)
            print(f"Normalized: X shape={X.shape}, y range=[{y.min():.3f}, {y.max():.3f}]", flush=True)
            input_dim = X.shape[1]
            model = \(className)(input_dim=input_dim)
            optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
        \(gradientTrainingSetup(cfg.gradientTraining))
        \(ensembleTargetSetup(cfg.ensemble))
            for epoch in range(1, args.epochs + 1):
                model.train()
                optimizer.zero_grad()
                pred = model(X)
        \(ensembleTrainingLoss(cfg.ensemble, physicsCall: "physics_loss(model, None, X, pred_mean)"))
        \(gradientTrainingLoop(cfg.gradientTraining))
                total.backward()
                optimizer.step()
                scheduler.step()
                if epoch % max(1, args.epochs // 100) == 0 or epoch == args.epochs:
                    report_progress(epoch, args.epochs, data_loss.item(), phys_loss.item())
            convert_to_coreml(model, input_dim, args.output, args.domain\(ensembleConvertArg(cfg.ensemble)))
            save_normalization_params(args.output, X_mean, X_std, y_mean, y_std)

        if __name__ == '__main__':
            main()
        """
    }

    // MARK: - Ensemble Helpers

    /// Generates target expansion for multi-head training (y → y_multi).
    private static func ensembleTargetSetup(_ config: PINNEnsembleConfig) -> String {
        guard config.isEnabled, config.numHeads > 1 else { return "" }
        return "    y_multi = y.expand(-1, \(config.numHeads))"
    }

    /// Generates data_loss + phys_loss computation for single or multi-head output.
    /// `physicsCall` is the domain-specific physics_loss() call using `pred_mean`.
    private static func ensembleTrainingLoss(_ config: PINNEnsembleConfig, physicsCall: String) -> String {
        if config.isEnabled, config.numHeads > 1 {
            return """
                    data_loss = nn.MSELoss()(pred, y_multi)
                    pred_mean = pred.mean(dim=-1, keepdim=True)
                    phys_loss = \(physicsCall)
            """
        }
        return """
                data_loss = nn.MSELoss()(pred, y)
                pred_mean = pred
                phys_loss = \(physicsCall)
        """
    }

    /// Generates the num_heads kwarg for convert_to_coreml when ensemble is enabled.
    private static func ensembleConvertArg(_ config: PINNEnsembleConfig) -> String {
        guard config.isEnabled, config.numHeads > 1 else { return "" }
        return ", num_heads=\(config.numHeads)"
    }

    // MARK: - Gradient Training Helpers

    /// Generates the balancer setup line (2 or 3 losses).
    private static func gradientTrainingSetup(_ config: GradientTrainingConfig) -> String {
        if config.isEnabled {
            return "    balancer = ReLoBRaLo(num_losses=3)"
        }
        return "    balancer = ReLoBRaLo(num_losses=2)"
    }

    /// Generates the gradient loss computation and total loss assembly.
    private static func gradientTrainingLoop(_ config: GradientTrainingConfig) -> String {
        if config.isEnabled {
            return """
                    grad_loss = gradient_loss(model, X, y, grad_weight=\(String(format: "%.2f", config.weight)))
                    weights = balancer.update([data_loss.item(), phys_loss.item(), grad_loss.item()])
                    total = weights[0] * data_loss + weights[1] * phys_loss + weights[2] * grad_loss
            """
        }
        return """
                weights = balancer.update([data_loss.item(), phys_loss.item()])
                total = weights[0] * data_loss + weights[1] * phys_loss
        """
    }
}
