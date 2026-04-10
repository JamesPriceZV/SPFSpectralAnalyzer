#if os(iOS)
import SwiftUI
import PhotosUI
import SwiftData

/// Main camera view for photographing sunscreen samples on PMMA plates.
/// Combines live camera preview, photo capture, photo picker, and analysis results.
struct SpectralCameraView: View {
    @Bindable var datasets: DatasetViewModel
    var storedDatasets: [StoredDataset]

    @State private var capturedImage: UIImage?
    @State private var analysisResult: ColorAnalysisResult?
    @State private var isAnalyzing = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showAttachPicker = false
    @State private var attachSuccessMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                captureSection
                if let image = capturedImage {
                    imagePreviewSection(image)
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
                if let result = analysisResult {
                    resultsSection(result)
                }
                if capturedImage != nil, analysisResult != nil {
                    attachToDatasetButton
                }
                if let msg = attachSuccessMessage {
                    Label(msg, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                        .transition(.opacity)
                }
            }
            .padding()
        }
        .navigationTitle("Camera Analysis")
        .fullScreenCover(isPresented: $showCamera) {
            CameraPreviewView { image in
                capturedImage = image
                showCamera = false
                if let image {
                    analyzeImage(image)
                }
            }
        }
        .sheet(isPresented: $showAttachPicker) {
            attachDatasetPickerSheet
        }
    }

    // MARK: - Attach to Dataset

    private var attachToDatasetButton: some View {
        Button {
            showAttachPicker = true
        } label: {
            Label("Attach Photo to Dataset", systemImage: "paperclip")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
    }

    private var attachDatasetPickerSheet: some View {
        NavigationStack {
            List {
                if storedDatasets.isEmpty {
                    Text("No datasets available. Import SPC files first.")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(storedDatasets, id: \.id) { dataset in
                        let record = datasets.searchableRecordCache[dataset.id]
                        let name = record?.fileName ?? dataset.id.uuidString
                        let hasPhoto = dataset.cameraPhotoData != nil
                        Button {
                            attachPhotoToDataset(dataset)
                            showAttachPicker = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(name)
                                        .font(.subheadline)
                                    Text("\(record?.spectrumCount ?? 0) spectra")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                if hasPhoto {
                                    Image(systemName: "camera.fill")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Select Dataset")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAttachPicker = false }
                }
            }
        }
    }

    private func attachPhotoToDataset(_ dataset: StoredDataset) {
        guard let image = capturedImage,
              let result = analysisResult,
              dataset.modelContext != nil else { return }

        // Compress photo to JPEG
        let jpegData = image.jpegData(compressionQuality: 0.7)

        // Serialize analysis as JSON
        let analysisJSON: String = {
            let dict: [String: Any] = [
                "dominantHue": Double(result.dominantHue),
                "averageSaturation": Double(result.averageSaturation),
                "averageBrightness": Double(result.averageBrightness),
                "averageRed": Double(result.averageRed),
                "averageGreen": Double(result.averageGreen),
                "averageBlue": Double(result.averageBlue),
                "colorTemperature": result.estimatedColorTemperature,
                "interpretation": result.interpretationNote ?? ""
            ]
            if let data = try? JSONSerialization.data(withJSONObject: dict),
               let str = String(data: data, encoding: .utf8) {
                return str
            }
            return "{}"
        }()

        do {
            try ObjCExceptionCatcher.try {
                MainActor.assumeIsolated {
                    dataset.cameraPhotoData = jpegData
                    dataset.cameraAnalysisJSON = analysisJSON
                }
            }
            withAnimation {
                attachSuccessMessage = "Photo attached to \(dataset.fileName)"
            }
            datasets.dataVersion += 1
        } catch {
            Instrumentation.log("Camera attach failed", area: .uiInteraction, level: .error,
                              details: "error=\(error.localizedDescription)")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sample Photography")
                .font(.headline)
            Text("Photograph PMMA plates or sunscreen samples for quick visual color analysis. This supplements — but does not replace — instrument-based spectral measurements.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var captureSection: some View {
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 16) {
                Button {
                    showCamera = true
                } label: {
                    Label("Take Photo", systemImage: "camera.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)

                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .onChange(of: selectedPhotoItem) { _, newItem in
                    guard let newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let image = UIImage(data: data) {
                            capturedImage = image
                            analyzeImage(image)
                        }
                    }
                }
            }
        }
    }

    private func imagePreviewSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured Image")
                .font(.subheadline.bold())
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func resultsSection(_ result: ColorAnalysisResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Color Analysis")
                    .font(.subheadline.bold())
                Spacer()
                if isAnalyzing {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            GlassEffectContainer(spacing: 8) {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    colorMetricCard(title: "Dominant Hue", value: String(format: "%.0f°", result.dominantHue))
                    colorMetricCard(title: "Avg Brightness", value: String(format: "%.2f", result.averageBrightness))
                    colorMetricCard(title: "Saturation", value: String(format: "%.2f", result.averageSaturation))
                    colorMetricCard(title: "Color Temp", value: result.estimatedColorTemperature)
                }
            }

            if let note = result.interpretationNote {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .glassEffect(.clear, in: .rect(cornerRadius: 8))
            }
        }
        .transition(.opacity)
    }

    private func colorMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline.bold())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.clear, in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value)")
    }

    private func analyzeImage(_ image: UIImage) {
        isAnalyzing = true
        Task {
            let result = await VisionColorAnalyzer.analyze(image: image)
            await MainActor.run {
                analysisResult = result
                isAnalyzing = false
            }
        }
    }
}
#endif
