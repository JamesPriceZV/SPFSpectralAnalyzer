#if os(iOS)
import SwiftUI
import PhotosUI

/// Standalone photo picker for selecting existing images for color analysis.
/// This is an alternative entry point when the user prefers to pick from
/// their photo library rather than using the live camera.
struct PhotoPickerView: View {
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var analysisResult: ColorAnalysisResult?
    @State private var isAnalyzing = false

    var body: some View {
        VStack(spacing: 16) {
            PhotosPicker(selection: $selectedItem, matching: .images) {
                if let image = selectedImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 250)
                        .cornerRadius(12)
                } else {
                    ContentUnavailableView("Select a Photo",
                        systemImage: "photo.on.rectangle",
                        description: Text("Tap to choose a photo of a PMMA plate or sunscreen sample"))
                }
            }

            if isAnalyzing {
                ProgressView("Analyzing…")
            }

            if let result = analysisResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Analysis Results")
                        .font(.headline)
                    LabeledContent("Dominant Hue", value: String(format: "%.0f°", result.dominantHue))
                    LabeledContent("Brightness", value: String(format: "%.2f", result.averageBrightness))
                    LabeledContent("Saturation", value: String(format: "%.2f", result.averageSaturation))
                    LabeledContent("Color Temp", value: result.estimatedColorTemperature)
                    if let note = result.interpretationNote {
                        Text(note)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(12)
            }
        }
        .padding()
        .onChange(of: selectedItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                    isAnalyzing = true
                    let result = await VisionColorAnalyzer.analyze(image: image)
                    analysisResult = result
                    isAnalyzing = false
                }
            }
        }
    }
}
#endif
