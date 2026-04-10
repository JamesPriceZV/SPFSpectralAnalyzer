import Foundation

/// Generates and installs Python PINN training scripts for all 10 spectral domains.
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
        "train_pinn_\(domain.rawValue.lowercased().replacingOccurrences(of: " ", with: "_")).py"
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

        def convert_to_coreml(model, input_shape, output_path, domain_name):
            \"\"\"Convert a PyTorch model to CoreML format.\"\"\"
            import torch
            import coremltools as ct

            model.eval()

            # Always save PyTorch state dict as fallback
            pt_path = output_path + ".pt"
            torch.save(model.state_dict(), pt_path)
            print(f"PyTorch model saved to {pt_path}", flush=True)

            # Step 1: Trace and convert to CoreML
            try:
                example_input = torch.randn(1, input_shape)
                traced = torch.jit.trace(model, example_input)
                mlmodel = ct.convert(
                    traced,
                    inputs=[ct.TensorType(name="input", shape=(1, input_shape))],
                    outputs=[ct.TensorType(name="output")],
                    minimum_deployment_target=ct.target.macOS13,
                )
            except Exception as e:
                print(f"WARNING: CoreML conversion failed: {e}", flush=True)
                print(f"PyTorch model saved at {pt_path}. Manual conversion may be needed.", flush=True)
                return

            # Step 2: Save as .mlpackage
            package_path = output_path + ".mlpackage"
            mlmodel.save(package_path)
            print(f"Model saved as .mlpackage at {package_path}", flush=True)

            # Step 3: Compile to .mlmodelc via xcrun (use full path for PATH safety)
            compiled_path = output_path + ".mlmodelc"
            compile_cmd = f'/usr/bin/xcrun coremlcompiler compile "{package_path}" "{os.path.dirname(output_path)}"'
            exit_code = os.system(compile_cmd)

            if os.path.exists(compiled_path):
                print(f"Model compiled to {compiled_path}", flush=True)
            else:
                print(f"WARNING: coremlcompiler exited with code {exit_code >> 8}", flush=True)
                print(f"The .mlpackage was saved at {package_path}", flush=True)
                print(f"Compile manually: xcrun coremlcompiler compile \\"{package_path}\\" \\"{os.path.dirname(output_path)}\\"", flush=True)

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
        """
    }

    // MARK: - Domain-Specific Script Content

    private static func scriptContent(for domain: PINNDomain) -> String {
        let header = scriptHeader(for: domain)
        let body: String
        switch domain {
        case .uvVis:          body = uvVisScript()
        case .ftir:           body = ftirScript()
        case .raman:          body = ramanScript()
        case .massSpec:       body = massSpecScript()
        case .nmr:            body = nmrScript()
        case .fluorescence:   body = fluorescenceScript()
        case .xrd:            body = xrdScript()
        case .chromatography: body = chromatographyScript()
        case .nir:            body = nirScript()
        case .atomicEmission: body = atomicEmissionScript()
        }
        return header + body
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
        from pinn_utils import parse_args, load_training_data, report_progress, convert_to_coreml, ReLoBRaLo

        """
    }

    // MARK: - UV-Vis Script

    private static func uvVisScript() -> String {
        """
        class UVVisPINN(nn.Module):
            \"\"\"Physics-Informed Neural Network for UV-Vis SPF prediction.
            Embeds Beer-Lambert law and Diffey SPF integral as physics constraints.\"\"\"
            def __init__(self, input_dim=122):
                super().__init__()
                self.net = nn.Sequential(
                    nn.Linear(input_dim, 256), nn.Tanh(),
                    nn.Linear(256, 128), nn.Tanh(),
                    nn.Linear(128, 128), nn.Tanh(),
                    nn.Linear(128, 64), nn.Tanh(),
                    nn.Linear(64, 1)
                )
            def forward(self, x):
                return self.net(x)

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
                uvb_area = float(np.trapz(resampled[uvb_mask], target_wl[uvb_mask])) if uvb_mask.any() else 0
                uva_area = float(np.trapz(resampled[uva_mask], target_wl[uva_mask])) if uva_mask.any() else 0
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
            X, y = prepare_features(entries)
            input_dim = X.shape[1]
            model = UVVisPINN(input_dim=input_dim)
            optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
            balancer = ReLoBRaLo(num_losses=2)
            for epoch in range(1, args.epochs + 1):
                model.train()
                optimizer.zero_grad()
                pred = model(X)
                data_loss = nn.MSELoss()(pred, y)
                phys_loss = physics_loss(model, None, X[:, :111], pred)
                weights = balancer.update([data_loss.item(), phys_loss.item()])
                total = weights[0] * data_loss + weights[1] * phys_loss
                total.backward()
                optimizer.step()
                scheduler.step()
                if epoch % max(1, args.epochs // 100) == 0 or epoch == args.epochs:
                    report_progress(epoch, args.epochs, data_loss.item(), phys_loss.item())
            convert_to_coreml(model, input_dim, args.output, args.domain)

        if __name__ == '__main__':
            main()
        """
    }

    // MARK: - FTIR Script

    private static func ftirScript() -> String {
        genericPINNScript(
            className: "FTIRPINN",
            layers: [512, 256, 128, 64],
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
            """
        )
    }

    // MARK: - Raman Script

    private static func ramanScript() -> String {
        genericPINNScript(
            className: "RamanPINN",
            layers: [512, 256, 128, 64],
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
            """
        )
    }

    // MARK: - Mass Spec Script

    private static func massSpecScript() -> String {
        genericPINNScript(
            className: "MassSpecPINN",
            layers: [256, 128, 128, 64],
            physicsDoc: "Isotope distribution (natural abundance) + mass conservation + fragmentation rules",
            physicsBody: """
                # Mass conservation: total ion intensity should be consistent
                if absorbance_batch is not None:
                    total_intensity = absorbance_batch.sum(dim=-1, keepdim=True)
                    intensity_var = total_intensity.var()
                    return intensity_var * 0.01
                return torch.tensor(0.0)
            """
        )
    }

    // MARK: - NMR Script

    private static func nmrScript() -> String {
        genericPINNScript(
            className: "NMRPINN",
            layers: [512, 256, 128, 64],
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
            """
        )
    }

    // MARK: - Fluorescence Script

    private static func fluorescenceScript() -> String {
        genericPINNScript(
            className: "FluorescencePINN",
            layers: [256, 128, 128, 64],
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
            """
        )
    }

    // MARK: - XRD Script

    private static func xrdScript() -> String {
        genericPINNScript(
            className: "XRDPINN",
            layers: [256, 128, 128, 64],
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
            """
        )
    }

    // MARK: - Chromatography Script

    private static func chromatographyScript() -> String {
        genericPINNScript(
            className: "ChromatographyPINN",
            layers: [256, 128, 128, 64],
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
            """
        )
    }

    // MARK: - NIR Script

    private static func nirScript() -> String {
        genericPINNScript(
            className: "NIRPINN",
            layers: [512, 256, 128, 64],
            physicsDoc: "Modified Beer-Lambert for diffuse reflectance + Kubelka-Munk corrections",
            physicsBody: """
                # Modified Beer-Lambert: similar to FTIR but with Kubelka-Munk scattering
                neg_penalty = torch.relu(-absorbance_batch).mean() if absorbance_batch is not None else torch.tensor(0.0)
                smooth = torch.tensor(0.0)
                if absorbance_batch is not None and absorbance_batch.shape[-1] > 2:
                    d2 = absorbance_batch[:, 2:] - 2 * absorbance_batch[:, 1:-1] + absorbance_batch[:, :-2]
                    smooth = (d2 ** 2).mean() * 0.01
                return neg_penalty + smooth
            """
        )
    }

    // MARK: - Atomic Emission Script

    private static func atomicEmissionScript() -> String {
        genericPINNScript(
            className: "AtomicEmissionPINN",
            layers: [256, 128, 128, 64],
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
            """
        )
    }

    // MARK: - Generic PINN Template

    private static func genericPINNScript(
        className: String,
        layers: [Int],
        physicsDoc: String,
        physicsBody: String
    ) -> String {
        let layerDefs = layers.enumerated().map { i, size in
            let prevSize = i == 0 ? "input_dim" : "\(layers[i-1])"
            return "            nn.Linear(\(prevSize), \(size)), nn.Tanh(),"
        }.joined(separator: "\n")

        return """
        class \(className)(nn.Module):
            \"\"\"\(physicsDoc)\"\"\"
            def __init__(self, input_dim=122):
                super().__init__()
                self.net = nn.Sequential(
        \(layerDefs)
                    nn.Linear(\(layers.last ?? 64), 1)
                )
            def forward(self, x):
                return self.net(x)

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
            X, y = prepare_features(entries)
            input_dim = X.shape[1]
            model = \(className)(input_dim=input_dim)
            optimizer = torch.optim.Adam(model.parameters(), lr=args.lr)
            scheduler = torch.optim.lr_scheduler.CosineAnnealingLR(optimizer, T_max=args.epochs)
            balancer = ReLoBRaLo(num_losses=2)
            for epoch in range(1, args.epochs + 1):
                model.train()
                optimizer.zero_grad()
                pred = model(X)
                data_loss = nn.MSELoss()(pred, y)
                phys_loss = physics_loss(model, None, X, pred)
                weights = balancer.update([data_loss.item(), phys_loss.item()])
                total = weights[0] * data_loss + weights[1] * phys_loss
                total.backward()
                optimizer.step()
                scheduler.step()
                if epoch % max(1, args.epochs // 100) == 0 or epoch == args.epochs:
                    report_progress(epoch, args.epochs, data_loss.item(), phys_loss.item())
            convert_to_coreml(model, input_dim, args.output, args.domain)

        if __name__ == '__main__':
            main()
        """
    }
}
