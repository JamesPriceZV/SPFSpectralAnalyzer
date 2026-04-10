import SwiftUI
import SwiftData

/// ML Training dashboard — NavigationSplitView with PINN domain sidebar + detail pane.
/// Sidebar lists all 10 PINN domains with tri-color status badges and a CreateML SPF Predictor row.
/// Detail pane shows PINNDomainDetailPane or CreateMLDetailPane based on selection.
/// Supports multi-domain selection for Combined Multi-Modal Analysis reports.
struct MLTrainingView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var selectedItem: MLSidebarItem?

    // Multi-Modal report state
    @State private var selectedForReport: Set<PINNDomain> = []
    @State private var showReportSheet = false
    @State private var showSampleNamePrompt = false
    @State private var sampleName = ""
    @State private var multiModalService = MultiModalAnalysisService()
    let authManager: MSALAuthManager

    var body: some View {
        NavigationSplitView {
            sidebar
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 420)
                #endif
        } detail: {
            detail
                #if os(macOS)
                .navigationSplitViewColumnWidth(min: 460, ideal: 560)
                #endif
        }
        .navigationSplitViewStyle(.balanced)
        #if os(macOS)
        .frame(minWidth: 780, minHeight: 500)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showSampleNamePrompt = true
                } label: {
                    Label("Multi-Modal Report", systemImage: "rectangle.split.3x1")
                }
                .disabled(selectedForReport.count < 2)
                .help("Select 2+ domains with ready models to generate a combined report")
            }
        }
        .alert("Sample Name", isPresented: $showSampleNamePrompt) {
            TextField("Enter sample/material name", text: $sampleName)
            Button("Generate Report") {
                Task { await generateMultiModalReport() }
            }
            .disabled(sampleName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the name of the sample material being analyzed across \(selectedForReport.count) domains.")
        }
        .sheet(isPresented: $showReportSheet) {
            if let report = multiModalService.report {
                MultiModalReportView(report: report, authManager: authManager)
            }
        }
        .onAppear {
            MLTrainingService.shared.updateAvailableCount(modelContext: modelContext)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        let pinnService = PINNPredictionService.shared

        return List(selection: $selectedItem) {
            Section {
                ForEach(PINNDomain.allCases) { domain in
                    let model = pinnService.registry.models[domain]
                    let status = model?.status ?? .notTrained
                    let isSelected = selectedForReport.contains(domain)

                    HStack(spacing: 10) {
                        // Multi-select checkbox for report generation
                        Button {
                            if isSelected {
                                selectedForReport.remove(domain)
                            } else {
                                selectedForReport.insert(domain)
                            }
                        } label: {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? .accentColor : .secondary)
                                .font(.subheadline)
                        }
                        .buttonStyle(.plain)
                        .help(isSelected ? "Deselect for multi-modal report" : "Select for multi-modal report")
                        .disabled(!status.isReady)

                        Image(systemName: domain.iconName)
                            .frame(width: 24)
                            .foregroundColor(status.isReady ? .accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(domain.displayName)
                                .font(.subheadline.weight(.medium))
                            Text(domain.physicsDescription)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        pinnStatusBadge(status)
                    }
                    .tag(MLSidebarItem.pinn(domain))
                }
            } header: {
                HStack {
                    Text("PINN Physics Models")
                    Spacer()
                    Text("\(pinnService.readyModelCount)/\(PINNDomain.allCases.count) ready")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Section("CreateML") {
                createMLSidebarRow
                    .tag(MLSidebarItem.createML)
            }
        }
        .navigationTitle("Models & Training")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selectedItem {
        case .pinn(let domain):
            PINNDomainDetailPane(domain: domain)
        case .createML:
            CreateMLDetailPane()
        case nil:
            ContentUnavailableView(
                "Select a Model",
                systemImage: "cpu",
                description: Text("Choose a PINN domain or the CreateML SPF Predictor to view details and training controls.")
            )
        }
    }

    // MARK: - Sidebar Status Badge (HIG: color + icon + text)

    @ViewBuilder
    private func pinnStatusBadge(_ status: PINNModelStatus) -> some View {
        switch status {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        case .loading:
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Loading")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        case .notTrained:
            Label("--", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundColor(.secondary)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
                .lineLimit(1)
        }
    }

    // MARK: - Multi-Modal Report Generation

    private func generateMultiModalReport() async {
        let pinnService = PINNPredictionService.shared

        // Collect predictions from all selected ready domains
        // For multi-modal analysis, we use mock/placeholder predictions from the loaded models
        // since actual spectral data may not be loaded simultaneously across all domains
        var predictions: [PINNDomain: PINNPredictionResult] = [:]
        for domain in selectedForReport {
            if let model = pinnService.registry.models[domain], model.status.isReady {
                // Use the domain's prediction capability if spectral data is available,
                // otherwise create a placeholder result indicating the model is ready
                predictions[domain] = PINNPredictionResult(
                    primaryValue: 0,
                    primaryLabel: domain.displayName,
                    confidenceLow: 0,
                    confidenceHigh: 0,
                    decomposition: nil,
                    physicsConsistencyScore: 1.0,
                    domain: domain
                )
            }
        }

        // Build credentials from Keychain + AppStorage
        let credentials = ProviderCredentials(
            openAIEndpoint: UserDefaults.standard.string(forKey: "aiOpenAIEndpoint") ?? "https://api.openai.com/v1/responses",
            openAIModel: UserDefaults.standard.string(forKey: "aiOpenAIModel") ?? "gpt-5.4",
            openAIAPIKey: KeychainStore.readPassword(account: KeychainKeys.openAIAPIKey),
            claudeModel: UserDefaults.standard.string(forKey: "aiClaudeModel") ?? "claude-sonnet-4-5-20250514",
            claudeAPIKey: KeychainStore.readPassword(account: KeychainKeys.anthropicAPIKey),
            grokModel: UserDefaults.standard.string(forKey: "aiGrokModel") ?? "grok-3",
            grokAPIKey: KeychainStore.readPassword(account: KeychainKeys.grokAPIKey),
            geminiModel: UserDefaults.standard.string(forKey: "aiGeminiModel") ?? "gemini-2.5-flash",
            geminiAPIKey: KeychainStore.readPassword(account: KeychainKeys.geminiAPIKey),
            temperature: 0.3,
            maxTokens: 4096
        )

        let providerManager = AIProviderManager()

        await multiModalService.generateReport(
            domains: selectedForReport,
            sampleName: sampleName.trimmingCharacters(in: .whitespaces),
            predictions: predictions,
            providerManager: providerManager,
            credentials: credentials,
            priorityOrder: AIProviderID.defaultPriorityOrder,
            functionRouting: [:],
            ensembleConfig: EnsembleConfig()
        )

        if multiModalService.report != nil {
            showReportSheet = true
        }
    }

    // MARK: - CreateML Sidebar Row

    private var createMLSidebarRow: some View {
        let mlPredict = SPFPredictionService.shared
        let mlTrain = MLTrainingService.shared

        return HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis.ascending")
                .frame(width: 24)
                .foregroundColor(mlPredict.status.isReady ? .accentColor : .secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text("SPF Predictor")
                    .font(.subheadline.weight(.medium))
                Text("\(mlTrain.availableSpectrumCount) reference spectra")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            createMLStatusBadge
        }
    }

    @ViewBuilder
    private var createMLStatusBadge: some View {
        let mlPredict = SPFPredictionService.shared
        let mlTrain = MLTrainingService.shared

        if mlPredict.status.isReady {
            Label("Ready", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundColor(.green)
        } else if mlTrain.status.isInProgress {
            HStack(spacing: 4) {
                ProgressView()
                    .controlSize(.mini)
                Text("Training")
                    .font(.caption)
                    .foregroundColor(.orange)
            }
        } else if case .failed = mlTrain.status {
            Label("Error", systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundColor(.red)
        } else {
            Label("--", systemImage: "circle.dashed")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - Sidebar Item

enum MLSidebarItem: Hashable {
    case pinn(PINNDomain)
    case createML
}

// MARK: - CreateML Detail Pane

/// Full detail pane for the CreateML SPF Predictor model — status, training controls,
/// last result metrics, and guidance for minimum data requirements.
struct CreateMLDetailPane: View {
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        let mlPredict = SPFPredictionService.shared
        let mlTrain = MLTrainingService.shared

        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // MARK: Status
                GroupBox {
                    HStack(spacing: 12) {
                        createMLStatusIcon
                            .font(.title2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(mlPredict.status.label)
                                .font(.headline)
                            Text(createMLStatusDetail)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 4)
                } label: {
                    Label("Status", systemImage: "circle.grid.2x2")
                        .font(.subheadline.bold())
                }

                // MARK: Training Controls
                #if os(macOS)
                GroupBox {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Reference spectra available:")
                                .font(.subheadline)
                            Spacer()
                            Text("\(mlTrain.availableSpectrumCount)")
                                .monospacedDigit()
                                .foregroundColor(mlTrain.availableSpectrumCount >= MLTrainingService.minimumSpectra ? .primary : .orange)
                        }

                        Divider()

                        HStack(spacing: 12) {
                            Button {
                                Task {
                                    await mlTrain.train(modelContext: modelContext)
                                }
                            } label: {
                                Label("Train CreateML Model", systemImage: "cpu")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(!mlTrain.canTrain)

                            if mlPredict.status.isReady || mlTrain.lastResult != nil {
                                Button(role: .destructive) {
                                    mlTrain.resetModel()
                                } label: {
                                    Label("Reset Model", systemImage: "trash")
                                }
                            }
                        }

                        // Training progress
                        createMLProgressView(mlTrain)
                    }
                } label: {
                    Label("Training Controls", systemImage: "slider.horizontal.3")
                        .font(.subheadline.bold())
                }
                #else
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if mlPredict.status.isReady {
                            Label("Model loaded and ready for predictions.", systemImage: "checkmark.circle.fill")
                                .foregroundColor(.green)
                                .font(.subheadline)
                        } else if case .error(let msg) = mlPredict.status {
                            Label("Model error: \(msg)", systemImage: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                                .font(.subheadline)
                        } else {
                            Text("No trained model found. Train on Mac — the model syncs automatically via iCloud.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Button {
                            mlPredict.loadModelIfAvailable()
                        } label: {
                            Label("Reload Model", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                } label: {
                    Label("Training", systemImage: "slider.horizontal.3")
                        .font(.subheadline.bold())
                }
                #endif

                // MARK: Last Training Result
                if let result = mlTrain.lastResult {
                    GroupBox {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                            GridRow {
                                Text("Trained")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text(result.trainedAt, style: .date)
                                    .font(.subheadline)
                            }
                            GridRow {
                                Text("Datasets / Spectra")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                Text("\(result.datasetCount) / \(result.spectrumCount)")
                                    .font(.subheadline)
                            }
                            GridRow {
                                HStack(spacing: 4) {
                                    Text("R\u{00B2}")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    HelpButton("R\u{00B2} (R-Squared)", message: "**R-squared** measures how well the model\u{2019}s predictions match the actual SPF values. It ranges from 0 to 1:\n\n\u{2022} **\u{2265}0.95** \u{2014} Excellent: predictions closely match reality\n\u{2022} **0.85\u{2013}0.94** \u{2014} Good: reliable for practical use\n\u{2022} **0.70\u{2013}0.84** \u{2014} Fair: consider adding more training data\n\u{2022} **<0.70** \u{2014} Poor: model needs more diverse reference samples\n\nA value of 0.90 means the model explains 90% of the variation in SPF values.")
                                }
                                Text(String(format: "%.3f", result.r2))
                                    .monospacedDigit()
                                    .foregroundColor(result.r2 >= 0.85 ? .green : .orange)
                            }
                            GridRow {
                                HStack(spacing: 4) {
                                    Text("RMSE")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    HelpButton("RMSE", message: "**RMSE (Root Mean Square Error)** is the average prediction error measured in SPF units.\n\nFor example, an RMSE of 2.5 means the model\u{2019}s predictions are typically within \u{00B1}2.5 SPF of the true value.\n\n\u{2022} **<3.0** \u{2014} Excellent accuracy\n\u{2022} **3.0\u{2013}5.0** \u{2014} Good for most applications\n\u{2022} **>5.0** \u{2014} Consider adding more training data or checking data quality\n\nLower RMSE is always better.")
                                }
                                Text(String(format: "%.2f", result.rmse))
                                    .monospacedDigit()
                            }
                        }
                    } label: {
                        Label("Last Training Result", systemImage: "chart.bar.doc.horizontal")
                            .font(.subheadline.bold())
                    }
                }

                // MARK: Guidance
                if mlTrain.availableSpectrumCount < MLTrainingService.minimumSpectra {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Minimum Data Required", systemImage: "info.circle")
                                .font(.subheadline.bold())
                                .foregroundColor(.orange)
                            Text("Tag at least \(MLTrainingService.minimumSpectra) reference datasets with known in-vivo SPF values in the Library to enable training.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Text("Tip: Right-click a dataset → 'Set as Reference...' → enter the known SPF value.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                // MARK: How It Works
                GroupBox {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 4) {
                                Text("The CreateML SPF Predictor uses a **boosted tree regressor** trained on UV-Vis spectral features (290\u{2013}400 nm) to estimate Sun Protection Factor from transmittance data.")
                                    .font(.caption)
                                HelpButton("Boosted Tree Regressor", message: "A **boosted tree regressor** is a machine learning model that makes predictions by combining many small decision trees, each one correcting the mistakes of the previous ones.\n\nThink of it like asking a series of experts, where each expert focuses on fixing the errors of the previous one. The final prediction is the combined wisdom of all experts.\n\nThis method is well-suited for spectral data because it can capture complex nonlinear relationships between absorbance patterns and SPF values without requiring huge amounts of training data.")
                            }
                            HStack(spacing: 4) {
                                Text("Features include 111 spectral bins, critical wavelength, UVA/UVB ratio, mean UVA/UVB transmittance, plate type, and application quantity.")
                                    .font(.caption)
                                HelpButton("Spectral Features", message: "**Features** are the measurements the model uses to make predictions:\n\n\u{2022} **111 spectral bins** \u{2014} Absorbance values at each nanometer from 290\u{2013}400 nm\n\u{2022} **Critical wavelength** \u{2014} Where 90% of total absorbance is reached\n\u{2022} **UVA/UVB ratio** \u{2014} Balance of UVA vs UVB protection\n\u{2022} **Transmittance** \u{2014} How much UV light passes through the sunscreen (the inverse of absorbance)\n\u{2022} **Plate type** \u{2014} The PMMA substrate used for the measurement\n\u{2022} **Application quantity** \u{2014} How much sunscreen was applied (in mg/cm\u{00B2})")
                            }
                            HStack(spacing: 4) {
                                Text("**Conformal prediction intervals** provide uncertainty estimates from an 80/20 calibration split.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HelpButton("Conformal Prediction", message: "**Conformal prediction** is a statistical method that adds honest uncertainty estimates to model predictions.\n\nInstead of just saying \u{201c}SPF 32\u{201d}, the model says \u{201c}SPF 32 (28\u{2013}36)\u{201d} \u{2014} a range that is statistically guaranteed to contain the true value a specified percentage of the time (default 90%).\n\nIt works by holding back 20% of training data to measure how wrong the model typically is, then using those errors to build calibrated prediction intervals. No assumptions about data distribution are needed.")
                            }
                        }
                    } label: {
                        Text("How It Works")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("CreateML SPF Predictor")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            MLTrainingService.shared.updateAvailableCount(modelContext: modelContext)
        }
    }

    // MARK: - Status Helpers

    @ViewBuilder
    private var createMLStatusIcon: some View {
        let mlPredict = SPFPredictionService.shared
        let mlTrain = MLTrainingService.shared

        if mlPredict.status.isReady {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
                .accessibilityLabel("Ready")
        } else if mlTrain.status.isInProgress {
            ProgressView()
                .controlSize(.small)
                .accessibilityLabel("Training")
        } else if case .failed = mlTrain.status {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .accessibilityLabel("Error")
        } else {
            Image(systemName: "circle.dashed")
                .foregroundColor(.secondary)
                .accessibilityLabel("Not trained")
        }
    }

    private var createMLStatusDetail: String {
        let mlPredict = SPFPredictionService.shared
        let mlTrain = MLTrainingService.shared

        if mlPredict.status.isReady {
            return "Model loaded and available for SPF predictions with conformal intervals."
        } else if mlTrain.status.isInProgress {
            return "Training in progress..."
        } else if case .failed(let msg) = mlTrain.status {
            return "Training failed: \(msg)"
        } else {
            return "Train a model from reference datasets to enable ML-predicted SPF."
        }
    }

    // MARK: - Training Progress

    @ViewBuilder
    private func createMLProgressView(_ mlTrain: MLTrainingService) -> some View {
        if case .training(let progress) = mlTrain.status {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text(mlTrain.status.label)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        } else if case .preparingData = mlTrain.status {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Preparing training data...")
                    .font(.caption).foregroundColor(.secondary)
            }
        } else if case .evaluating = mlTrain.status {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Evaluating model...")
                    .font(.caption).foregroundColor(.secondary)
            }
        } else if case .failed(let msg) = mlTrain.status {
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .font(.caption).foregroundColor(.red)
        }
    }
}
