#if os(iOS)
import SwiftUI
import PhotosUI

/// Main camera view for photographing sunscreen samples on PMMA plates.
/// Combines live camera preview, photo capture, photo picker, and analysis results.
struct SpectralCameraView: View {
    @State private var capturedImage: UIImage?
    @State private var analysisResult: ColorAnalysisResult?
    @State private var isAnalyzing = false
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var showCamera = false

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                captureSection
                if let image = capturedImage {
                    imagePreviewSection(image)
                }
                if let result = analysisResult {
                    resultsSection(result)
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
        HStack(spacing: 16) {
            Button {
                showCamera = true
            } label: {
                Label("Take Photo", systemImage: "camera.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                Label("Choose Photo", systemImage: "photo.on.rectangle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
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

    private func imagePreviewSection(_ image: UIImage) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Captured Image")
                .font(.subheadline.bold())
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 300)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
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

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                colorMetricCard(title: "Dominant Hue", value: String(format: "%.0f°", result.dominantHue))
                colorMetricCard(title: "Avg Brightness", value: String(format: "%.2f", result.averageBrightness))
                colorMetricCard(title: "Saturation", value: String(format: "%.2f", result.averageSaturation))
                colorMetricCard(title: "Color Temp", value: result.estimatedColorTemperature)
            }

            if let note = result.interpretationNote {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(8)
            }
        }
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
        .background(Color.secondary.opacity(0.06))
        .cornerRadius(8)
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
