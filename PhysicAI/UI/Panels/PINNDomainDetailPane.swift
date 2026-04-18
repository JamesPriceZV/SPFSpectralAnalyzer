import SwiftUI
import SwiftData
import Charts
import UniformTypeIdentifiers

/// Full training control panel for a single PINN domain.
/// Replaces the old information-only PINNDomainDetailSheet with interactive controls.
struct PINNDomainDetailPane: View {
    let domain: PINNDomain

    @Environment(\.modelContext) private var modelContext
    @State private var trainingManager = PINNTrainingManager()

    // Hyperparameters (defaults from @AppStorage, overridable per session)
    @AppStorage("pinnDefaultEpochs") private var defaultEpochs = 500
    @AppStorage("pinnDefaultLearningRate") private var defaultLR = 0.0003
    @State private var epochs: Int = 500
    @State private var learningRate: Double = 0.0003

    // Help popovers
    @State private var showEpochHelp = false
    @State private var showLearningRateHelp = false

    // Data import
    // File import handled via NSOpenPanel with domain-specific default directory
    @State private var importError: String?
    @State private var exportStatus: String?

    // Training data download
    @State private var trainingDataDownloader = TrainingDataDownloader.shared

    // Script installation
    @State private var scriptInstallStatus: String?

    // Physics constraint selections (persisted per domain as JSON)
    @AppStorage("pinnConstraintsJSON") private var constraintsJSON = "{}"
    @State private var constraintToggles: [String: Bool] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                statusSection
                getTrainingDataSection
                #if os(macOS)
                trainModelSection
                #else
                iosTrainingSection
                #endif
                lossChartSection
                #if os(macOS)
                advancedDataSection
                #endif
                modelInfoSection
                #if os(macOS)
                pythonSetupSection
                #endif
            }
            .padding()
        }
        .navigationTitle(domain.displayName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            epochs = defaultEpochs
            learningRate = defaultLR
            loadConstraintToggles()
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        // Read loadVersion to force re-render when model status changes
        // (domain models are reference types, not @Observable).
        let _ = PINNPredictionService.shared.registry.loadVersion
        let model = PINNPredictionService.shared.registry.models[domain]
        let status = model?.status ?? .notTrained
        let hasPtOnly = PINNModelRegistry.hasPyTorchOnlyModel(named: domain.modelBaseName)

        return GroupBox {
            HStack(spacing: 12) {
                if hasPtOnly && status == .notTrained {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                        .accessibilityLabel("Trained (PyTorch only)")
                } else {
                    statusIcon(status)
                        .font(.title2)
                }
                VStack(alignment: .leading, spacing: 4) {
                    if hasPtOnly && status == .notTrained {
                        Text("Trained (.pt)")
                            .font(.headline)
                        Text("CoreML conversion needed — model cannot run on-device until converted.")
                            .font(.caption)
                            .foregroundColor(.orange)
                        #if os(macOS)
                        Button {
                            Task { await trainingManager.retryConversion(for: domain) }
                        } label: {
                            Label("Convert to CoreML", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .controlSize(.small)
                        .disabled(trainingManager.status.isActive)
                        .padding(.top, 2)
                        #endif
                    } else {
                        Text(statusLabel(status))
                            .font(.headline)
                        Text(statusDetail(status))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 4)
        } label: {
            Label("Status", systemImage: "circle.grid.2x2")
                .font(.subheadline.bold())
        }
    }

    @ViewBuilder
    private func sourceStatusIcon(for source: PINNDomain.TrainingDataSource) -> some View {
        if source.isLicensed {
            Image(systemName: "lock.fill")
                .font(.system(size: 9))
                .foregroundColor(.orange)
        } else if source.url == nil {
            Image(systemName: "person.fill")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
        } else if let sourceStatus = trainingDataDownloader.sourceStatus(for: source.name, in: domain) {
            switch sourceStatus {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.green)
            case .downloading:
                ProgressView()
                    .controlSize(.mini)
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            case .failed:
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
            }
        } else if TrainingDataDownloader.isSourceDownloaded(source, for: domain) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundColor(.green)
        } else {
            Image(systemName: "circle.fill")
                .font(.system(size: 4))
                .foregroundColor(.secondary)
        }
    }

    /// Per-source progress row showing download progress bar, size, and percentage.
    @ViewBuilder
    private func sourceProgressRow(_ sourceStatus: TrainingDataDownloader.SourceStatus) -> some View {
        switch sourceStatus {
        case .downloading(let bytesDownloaded, let totalBytes):
            VStack(alignment: .leading, spacing: 2) {
                if let total = totalBytes, total > 0 {
                    ProgressView(value: Double(bytesDownloaded), total: Double(total))
                        .progressViewStyle(.linear)
                    HStack {
                        Text("\(TrainingDataDownloader.formattedSize(bytes: bytesDownloaded)) / \(TrainingDataDownloader.formattedSize(bytes: total))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(Double(bytesDownloaded) / Double(total) * 100))%")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.accentColor)
                    }
                } else {
                    ProgressView()
                        .controlSize(.mini)
                    Text("\(TrainingDataDownloader.formattedSize(bytes: bytesDownloaded)) downloaded")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
            }
        case .completed(let fileSize):
            Text("\(TrainingDataDownloader.formattedSize(bytes: fileSize))")
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.green)
        case .failed(let msg):
            Text(msg)
                .font(.system(size: 9))
                .foregroundColor(.red)
                .lineLimit(1)
        case .pending:
            EmptyView()
        }
    }

    @ViewBuilder
    private func statusIcon(_ status: PINNModelStatus) -> some View {
        switch status {
        case .ready:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityLabel("Ready")
        case .loading:
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Loading")
        case .notTrained:
            Image(systemName: "circle.dashed")
                .foregroundColor(.secondary)
                .accessibilityLabel("Not trained")
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .accessibilityLabel("Error")
        }
    }

    private func statusLabel(_ status: PINNModelStatus) -> String {
        switch status {
        case .ready: return "Ready"
        case .loading: return "Loading..."
        case .notTrained: return "Not Trained"
        case .error(let msg): return "Error: \(msg)"
        }
    }

    private func statusDetail(_ status: PINNModelStatus) -> String {
        switch status {
        case .ready: return "Model loaded and available for predictions."
        case .loading: return "Loading model from storage..."
        case .notTrained: return "Train this model to enable physics-informed predictions for \(domain.displayName) spectra."
        case .error: return "Check the Python environment and training scripts."
        }
    }

    // MARK: - Step 2: Train Model (macOS)

    #if os(macOS)
    private var trainModelSection: some View {
        let hasDownloadedFiles = !TrainingDataDownloader.downloadedFiles(for: domain).isEmpty

        return GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                if !hasDownloadedFiles && !trainingManager.status.isActive {
                    Label("Download training data first (Step 1) before training.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                // Hyperparameters
                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                    GridRow {
                        HStack(spacing: 4) {
                            Text("Epochs:")
                                .font(.subheadline)
                            Button {
                                showEpochHelp.toggle()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("What is an epoch?")
                            .popover(isPresented: $showEpochHelp, arrowEdge: .trailing) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("What is an Epoch?")
                                        .font(.headline)
                                    Text("An **epoch** is one complete pass through the entire training dataset. During each epoch, the model sees every training example once and adjusts its internal weights to reduce prediction error.")
                                        .font(.subheadline)
                                    Divider()
                                    Text("How it affects training:")
                                        .font(.subheadline.bold())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("**Too few epochs (100\u{2013}200)** \u{2014} The model may underfit: it hasn\u{2019}t learned the patterns in your data well enough, leading to poor predictions.")
                                        Text("**Good range (400\u{2013}800)** \u{2014} Usually enough for the model to converge on accurate predictions without wasting time.")
                                        Text("**Too many epochs (1500+)** \u{2014} Risk of overfitting: the model memorizes training data instead of learning general patterns, reducing accuracy on new spectra.")
                                    }
                                    .font(.caption)
                                    Divider()
                                    Text("**Tip:** Start with 500 epochs. If the loss chart shows the curve still decreasing at the end, try more. If loss flattens early, fewer epochs will save time.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(width: 340)
                            }
                        }
                        .frame(width: 110, alignment: .trailing)
                        Stepper(value: $epochs, in: 100...2000, step: 100) {
                            Text("\(epochs)")
                                .monospacedDigit()
                                .frame(width: 50, alignment: .trailing)
                        }
                    }
                    GridRow {
                        HStack(spacing: 4) {
                            Text("Learning Rate:")
                                .font(.subheadline)
                            Button {
                                showLearningRateHelp.toggle()
                            } label: {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .help("What is learning rate?")
                            .popover(isPresented: $showLearningRateHelp, arrowEdge: .trailing) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("What is Learning Rate?")
                                        .font(.headline)
                                    Text("The **learning rate** controls how much the model adjusts its weights after each batch of training data. Think of it as the step size when walking downhill toward the best solution.")
                                        .font(.subheadline)
                                    Divider()
                                    Text("How it affects training:")
                                        .font(.subheadline.bold())
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("**Too high (1e-1 to 1e-2)** \u{2014} The model takes large steps and may overshoot the optimal solution, causing unstable or diverging loss.")
                                        Text("**Good range (1e-3 to 1e-4)** \u{2014} Balanced steps that converge reliably. 1e-3 is the recommended starting point.")
                                        Text("**Too low (1e-5)** \u{2014} Very small steps mean slow training. The model may need many more epochs to converge, or get stuck in a poor solution.")
                                    }
                                    .font(.caption)
                                    Divider()
                                    Text("**Tip:** Start with 1e-3. If the loss chart oscillates wildly, reduce to 1e-4. If training is very slow, try 3e-3.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .frame(width: 340)
                            }
                        }
                        .frame(width: 110, alignment: .trailing)
                        HStack {
                            Slider(
                                value: Binding(
                                    get: { log10(learningRate) },
                                    set: { learningRate = pow(10, $0) }
                                ),
                                in: -5...(-1),
                                step: 0.5
                            )
                            Text(String(format: "%.0e", learningRate))
                                .monospacedDigit()
                                .font(.caption)
                                .frame(width: 50)
                        }
                    }
                }

                Divider()

                // Action buttons
                HStack(spacing: 12) {
                    Button {
                        Task { await startTraining() }
                    } label: {
                        Label("Train Model", systemImage: "cpu")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasDownloadedFiles || trainingManager.status.isActive)

                    if trainingManager.status.isActive {
                        Button("Cancel", role: .destructive) {
                            trainingManager.cancelTraining()
                        }
                    }
                }

                // Training progress
                trainingProgressView
            }
        } label: {
            Label("Step 2 \u{2014} Train Model", systemImage: "cpu")
                .font(.subheadline.bold())
        }
    }
    #endif

    // MARK: - Training Section (iOS)

    private var iosTrainingSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                let _ = PINNPredictionService.shared.registry.loadVersion
                let model = PINNPredictionService.shared.registry.models[domain]
                let status = model?.status ?? .notTrained

                if status.isReady {
                    Label("Model loaded and ready for predictions.", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.subheadline)
                } else {
                    Text("PINN model training is available on macOS. Trained models sync automatically via iCloud.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                Button {
                    Task { await PINNPredictionService.shared.loadModels() }
                } label: {
                    Label("Reload Models", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        } label: {
            Label("Training", systemImage: "slider.horizontal.3")
                .font(.subheadline.bold())
        }
    }

    // MARK: - Training Progress

    @ViewBuilder
    private var trainingProgressView: some View {
        switch trainingManager.status {
        case .training(let progress, let epoch, let total):
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress) {
                    Text("Epoch \(epoch)/\(total)")
                        .font(.caption)
                }
                if let lastMetric = trainingManager.trainingHistory.last {
                    HStack(spacing: 16) {
                        Text("Data Loss: \(String(format: "%.4f", lastMetric.dataLoss))")
                        Text("Physics Loss: \(String(format: "%.4f", lastMetric.physicsLoss))")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        case .exportingData:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Exporting reference data...")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .converting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Converting to CoreML...")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .importing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Importing model...")
                    .font(.caption).foregroundColor(.secondary)
            }
        case .completed(let d):
            Label("\(d.displayName) training complete!", systemImage: "checkmark.circle.fill")
                .font(.caption).foregroundColor(.green)
        case .failed(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundColor(.red)
        case .idle:
            EmptyView()
        }
    }

    // MARK: - Loss Chart

    private var lossChartSection: some View {
        GroupBox {
            if trainingManager.trainingHistory.isEmpty {
                Text("No training history yet. Train a model to see loss curves.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart {
                    ForEach(trainingManager.trainingHistory) { metric in
                        LineMark(
                            x: .value("Epoch", metric.epoch),
                            y: .value("Loss", metric.dataLoss)
                        )
                        .foregroundStyle(by: .value("Type", "Data Loss"))

                        LineMark(
                            x: .value("Epoch", metric.epoch),
                            y: .value("Loss", metric.physicsLoss)
                        )
                        .foregroundStyle(by: .value("Type", "Physics Loss"))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: true))
                .chartLegend(position: .top)
                .frame(height: 180)
            }
        } label: {
            HStack(spacing: 4) {
                Label("Training Loss", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.bold())
                HelpButton("Training Loss", message: "The loss chart shows how well the model is learning over time. Both curves should decrease during training:\n\n**Data Loss** \u{2014} Measures how closely the model\u{2019}s predictions match the actual training data. Lower means better predictions.\n\n**Physics Loss** \u{2014} Measures how well the model respects known physical laws (e.g., Beer-Lambert absorption, energy conservation). This is what makes a PINN special \u{2014} it doesn\u{2019}t just fit data, it learns physics.\n\nIf **data loss decreases but physics loss increases**, the model is fitting the data in ways that violate physics \u{2014} try a lower learning rate. If both plateau early, the model has converged and more epochs won\u{2019}t help.")
            }
        }
    }

    // MARK: - Step 1: Get Training Data

    private var getTrainingDataSection: some View {
        let downloadedCount = TrainingDataDownloader.downloadedFiles(for: domain).count
        let downloadedSize = TrainingDataDownloader.downloadedSize(for: domain)

        return GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                // Data sources list (always visible)
                ForEach(Array(domain.trainingDataSourcesWithURLs.enumerated()), id: \.offset) { _, source in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 6) {
                            sourceStatusIcon(for: source)
                                .frame(width: 14, alignment: .center)
                                .padding(.top, 1)
                            VStack(alignment: .leading, spacing: 2) {
                                if let url = source.url {
                                    Link(destination: url) {
                                        HStack(spacing: 3) {
                                            Text(source.name)
                                                .underline()
                                            Image(systemName: "arrow.up.right.square")
                                                .font(.system(size: 8))
                                        }
                                    }
                                    .font(.caption)
                                } else {
                                    Text(source.name)
                                        .font(.caption)
                                }
                                Text(source.description)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        // Per-source progress bar
                        if let sourceStatus = trainingDataDownloader.sourceStatus(for: source.name, in: domain) {
                            sourceProgressRow(sourceStatus)
                                .padding(.leading, 20)
                        }
                    }
                }

                Divider()

                // Download status
                if downloadedCount > 0 {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                            .font(.caption)
                        Text("\(downloadedCount) files ready (\(TrainingDataDownloader.formattedSize(bytes: downloadedSize)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Primary action: Download
                HStack(spacing: 12) {
                    Button {
                        Task { await trainingDataDownloader.downloadAllSources(for: domain) }
                    } label: {
                        Label(downloadedCount > 0 ? "Re-Download All Free Sources" : "Download All Free Sources", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(trainingDataDownloader.status(for: domain).isActive)

                    #if os(macOS)
                    if downloadedCount > 0 {
                        Button {
                            trainingDataDownloader.openDownloadFolder(for: domain)
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }
                    }
                    #endif
                }

                // Download progress (domain-scoped)
                switch trainingDataDownloader.status(for: domain) {
                case .downloading(let source, _):
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Downloading \(source)...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                case .staging(let source):
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Staging \(source)...")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                case .completed(let count):
                    Label("\(count) files downloaded and ready", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                case .failed(let msg):
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                case .idle:
                    EmptyView()
                }
            }
        } label: {
            Label("Step 1 \u{2014} Get Training Data", systemImage: "arrow.down.circle")
                .font(.subheadline.bold())
        }
    }

    // MARK: - Advanced Data (Export/Import for power users)

    #if os(macOS)
    private var advancedDataSection: some View {
        GroupBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SPC Type Codes for \(domain.displayName):")
                            .font(.caption.bold())
                        ForEach(domain.spcExperimentTypeDescriptions, id: \.code) { item in
                            HStack(spacing: 4) {
                                Text("•")
                                Text("Code \(item.code) — \(item.name)")
                            }
                            .font(.caption)
                            .foregroundColor(.secondary)
                        }
                    }

                    HStack(spacing: 12) {
                        Button {
                            importTrainingDataWithPanel()
                        } label: {
                            Label("Import Training Data...", systemImage: "square.and.arrow.down")
                        }

                        Button {
                            Task { await exportTrainingData() }
                        } label: {
                            Label("Export Training Data", systemImage: "square.and.arrow.up")
                        }
                        .disabled(trainingManager.status.isActive)
                    }

                    if let status = exportStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundColor(.green)
                    }

                    if let error = importError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            } label: {
                Text("Advanced: Import / Export")
                    .font(.subheadline)
            }
        }
    }
    #endif

    // MARK: - Model Info

    private var modelInfoSection: some View {
        GroupBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Architecture")
                            .font(.caption.bold())
                        Text(domain.architectureDescription)
                            .font(.caption)
                            .monospaced()
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Physics Constraints")
                            .font(.caption.bold())
                        Text(domain.physicsDescription)
                            .font(.caption)
                    }

                    if let model = PINNPredictionService.shared.registry.models[domain] {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Embedded Constraints")
                                .font(.caption.bold())
                            ForEach(model.physicsConstraints, id: \.self) { constraint in
                                HStack(alignment: .top, spacing: 4) {
                                    Text("•")
                                    Text(constraint)
                                }
                                .font(.caption)
                            }
                        }
                    }

                    // Optional physics constraints toggles
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Optional Physics Constraints")
                            .font(.caption.bold())
                        Text("Toggle constraints applied during training. Changes take effect on next training run.")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        ForEach(domain.availablePhysicsConstraints) { constraint in
                            Toggle(isOn: constraintBinding(for: constraint.id)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    HStack(spacing: 4) {
                                        Text(constraint.name)
                                            .font(.caption)
                                        Text("(\(constraint.equation))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    Text(constraint.description)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            #if os(macOS)
                            .toggleStyle(.checkbox)
                            #endif
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("References")
                            .font(.caption.bold())
                        ForEach(domain.references) { ref in
                            if let urlString = ref.url, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    HStack(alignment: .top, spacing: 4) {
                                        Image(systemName: "link")
                                            .font(.system(size: 8))
                                            .foregroundColor(.accentColor)
                                            .padding(.top, 2)
                                        Text(ref.citation)
                                            .font(.caption2)
                                            .foregroundColor(.accentColor)
                                            .multilineTextAlignment(.leading)
                                    }
                                }
                                .help(urlString)
                            } else {
                                Text(ref.citation)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            } label: {
                Text("Model Architecture & Physics")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - Python Setup (macOS)

    #if os(macOS)
    private var pythonSetupSection: some View {
        GroupBox {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    let scriptName = PINNScriptInstaller.scriptFilename(for: domain)
                    let scriptURL = PINNTrainingManager.scriptsDirectory.appendingPathComponent(scriptName)
                    let scriptExists = FileManager.default.fileExists(atPath: scriptURL.path)

                    LabeledContent("Script") {
                        HStack(spacing: 4) {
                            Image(systemName: scriptExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(scriptExists ? .green : .red)
                            Text(scriptName)
                                .font(.caption)
                                .monospaced()
                        }
                    }

                    LabeledContent("Scripts Directory") {
                        Text(PINNTrainingManager.scriptsDirectory.path)
                            .font(.caption2)
                            .monospaced()
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    HStack(spacing: 12) {
                        Button {
                            let dir = PINNTrainingManager.scriptsDirectory
                            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                            PlatformURLOpener.open(dir)
                        } label: {
                            Label("Open Scripts Folder", systemImage: "folder")
                        }
                        .font(.caption)

                        if !scriptExists {
                            Button {
                                let result = PINNScriptInstaller.installAllScripts()
                                if result.errors.isEmpty {
                                    scriptInstallStatus = "Installed \(result.installed.count) scripts"
                                } else {
                                    scriptInstallStatus = "Errors: \(result.errors.joined(separator: ", "))"
                                }
                            } label: {
                                Label("Install All Scripts", systemImage: "arrow.down.doc")
                            }
                            .font(.caption)
                        }
                    }

                    if let status = scriptInstallStatus {
                        Text(status)
                            .font(.caption2)
                            .foregroundColor(.green)
                    }

                    let scriptCounts = PINNScriptInstaller.installedScriptCount()
                    Text("\(scriptCounts.installed)/\(scriptCounts.total) domain scripts installed")
                        .font(.caption2)
                        .foregroundColor(scriptCounts.installed == scriptCounts.total ? .green : .orange)

                    Text("Requires Python 3.10+ with PyTorch, coremltools v7+, and scikit-learn.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } label: {
                Text("Python Environment")
                    .font(.subheadline)
            }
        }
    }
    #endif

    // MARK: - Actions

    #if os(macOS)
    private func startTraining() async {
        // Ensure training scripts are installed before starting
        let scriptResult = PINNScriptInstaller.installAllScripts()
        if !scriptResult.errors.isEmpty {
            Instrumentation.log(
                "Script installation had errors",
                area: .mlTraining, level: .warning,
                details: scriptResult.errors.joined(separator: "; ")
            )
        }

        // Gather ALL available training data (reference datasets + downloaded + imported files)
        let gathered = PINNDataExportService.gatherAllTrainingData(for: domain, modelContext: modelContext)

        // Pre-flight check: ensure we have enough data BEFORE launching Python
        guard gathered.entries.count >= 2 else {
            let downloadedFiles = TrainingDataDownloader.downloadedFiles(for: domain)
            let nonMetaFiles = downloadedFiles.filter { !$0.lastPathComponent.hasPrefix("_") }
            var message = "No training examples. "

            if nonMetaFiles.isEmpty {
                message += "No data files found. Download training data first (Step 1), then click 'Train Model'."
            } else {
                // Build per-file diagnostic
                var fileDiags: [String] = []
                for file in nonMetaFiles {
                    let name = file.lastPathComponent
                    let ext = file.pathExtension.lowercased()
                    if name.contains("LANDING_PAGE") || ext == "html" || ext == "htm" {
                        fileDiags.append("  • \(name) — HTML landing page (not data)")
                    } else {
                        // Try to parse and report specific error
                        do {
                            let entries = try PINNDataExportService.importTrainingData(from: file, domain: domain)
                            if entries.isEmpty {
                                fileDiags.append("  • \(name) — parsed OK but 0 usable entries")
                            }
                        } catch {
                            fileDiags.append("  • \(name) — \(error.localizedDescription)")
                        }
                    }
                }
                message += "The \(nonMetaFiles.count) downloaded file(s) could not be used:\n"
                message += fileDiags.joined(separator: "\n")
                message += "\n\nTry: Use 'Import Training Data' in Advanced > Import/Export to add CSV, JSON, or JCAMP-DX files with spectral data."
            }
            trainingManager.status = .failed(message)
            return
        }

        // Build merged training JSON
        do {
            let export = PINNDataExportService.TrainingDataExport(
                domain: domain.rawValue,
                exportDate: Date(),
                entryCount: gathered.entries.count,
                entries: gathered.entries
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(export)
            try PINNDataExportService.saveToTrainingDirectory(data: data, domain: domain)

            Instrumentation.log(
                "Starting PINN training for \(domain.displayName)",
                area: .mlTraining, level: .info,
                details: "epochs=\(epochs) lr=\(learningRate) entries=\(gathered.entries.count) sources=\(gathered.sources.joined(separator: "; "))"
            )

            await trainingManager.train(
                domain: domain,
                referenceData: data,
                epochs: epochs,
                learningRate: learningRate,
                constraints: enabledConstraintIDs
            )

            // Reload the trained domain model so its status updates to .ready.
            // Only reload this single domain — avoids re-creating all 22 model
            // instances and the 30-second iCloud retry loop that loadModels() does.
            if case .completed = trainingManager.status {
                let registry = PINNPredictionService.shared.registry
                if let model = registry.models[domain] {
                    do {
                        try await model.loadModel()
                    } catch {
                        Instrumentation.log(
                            "CoreML model load failed after training",
                            area: .mlTraining, level: .warning,
                            details: "domain=\(domain.displayName) error=\(error.localizedDescription) — .pt file may exist without CoreML conversion"
                        )
                    }
                }
                registry.loadVersion += 1
            }
        } catch {
            trainingManager.status = .failed("Failed to prepare training data: \(error.localizedDescription)")
            Instrumentation.log(
                "Failed to start PINN training",
                area: .mlTraining, level: .error,
                details: "domain=\(domain.displayName) error=\(error.localizedDescription)"
            )
        }
    }

    private func exportTrainingData() async {
        do {
            let data = try PINNDataExportService.exportReferenceData(for: domain, modelContext: modelContext)
            let url = try PINNDataExportService.saveToTrainingDirectory(data: data, domain: domain)
            exportStatus = "Exported to \(url.lastPathComponent)"
        } catch {
            exportStatus = nil
            importError = "Export failed: \(error.localizedDescription)"
        }
    }
    #endif

    #if os(macOS)
    private func importTrainingDataWithPanel() {
        let panel = NSOpenPanel()
        panel.title = "Import Training Data for \(domain.displayName)"
        panel.allowedContentTypes = [.json, .commaSeparatedText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        // Default to the TrainingData root where exported JSON files live
        let trainingDir = PINNTrainingManager.trainingDataDirectory
        try? FileManager.default.createDirectory(at: trainingDir, withIntermediateDirectories: true)
        panel.directoryURL = trainingDir

        guard panel.runModal() == .OK, let url = panel.url else { return }

        importError = nil
        do {
            let entries = try PINNDataExportService.importTrainingData(from: url, domain: domain)
            _ = try PINNDataExportService.copyToTrainingDirectory(from: url, domain: domain)
            exportStatus = "Imported \(entries.count) entries from \(url.lastPathComponent)"
        } catch {
            importError = error.localizedDescription
        }
    }
    #endif

    // MARK: - Physics Constraint Persistence

    /// Load constraint toggles for the current domain from persisted JSON.
    private func loadConstraintToggles() {
        let allDomains = (try? JSONDecoder().decode([String: [String: Bool]].self, from: Data(constraintsJSON.utf8))) ?? [:]
        let domainToggles = allDomains[domain.rawValue] ?? [:]
        var result: [String: Bool] = [:]
        for constraint in domain.availablePhysicsConstraints {
            result[constraint.id] = domainToggles[constraint.id] ?? constraint.isDefault
        }
        constraintToggles = result
    }

    /// Save constraint toggles for the current domain to persisted JSON.
    private func saveConstraintToggles() {
        var allDomains = (try? JSONDecoder().decode([String: [String: Bool]].self, from: Data(constraintsJSON.utf8))) ?? [:]
        allDomains[domain.rawValue] = constraintToggles
        if let data = try? JSONEncoder().encode(allDomains), let json = String(data: data, encoding: .utf8) {
            constraintsJSON = json
        }
    }

    /// Creates a Binding for a specific constraint toggle.
    private func constraintBinding(for constraintID: String) -> Binding<Bool> {
        Binding(
            get: { constraintToggles[constraintID] ?? true },
            set: { newValue in
                constraintToggles[constraintID] = newValue
                saveConstraintToggles()
            }
        )
    }

    /// Returns the list of enabled constraint IDs for the current domain.
    var enabledConstraintIDs: [String] {
        constraintToggles.filter(\.value).map(\.key)
    }
}
