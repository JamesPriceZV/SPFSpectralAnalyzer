import SwiftUI
import SwiftData

struct TrainingRecordAnnotationView: View {
    @Bindable var record: StoredTrainingRecord

    var body: some View {
        Form {
            Section("Record Info") {
                LabeledContent("Modality", value: SpectralModality(rawValue: record.modalityRaw)?.displayName ?? record.modalityRaw)
                LabeledContent("Source", value: record.sourceID)
                LabeledContent("Created", value: record.createdAt.formatted(date: .abbreviated, time: .shortened))
                if let method = record.computationMethod {
                    LabeledContent("Method", value: method)
                }
            }

            Section("Targets") {
                ForEach(record.targetsJSON.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    LabeledContent(key, value: String(format: "%.4f", value))
                }
            }

            Section("Annotation") {
                HStack {
                    Text("Quality Score")
                    Spacer()
                    Text(String(format: "%.2f", record.qualityScore))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(value: $record.qualityScore, in: 0...1, step: 0.05)

                Toggle("Exclude from Training", isOn: $record.isExcluded)

                TextField("Notes", text: Binding(
                    get: { record.annotationNotes ?? "" },
                    set: { record.annotationNotes = $0.isEmpty ? nil : $0 }
                ), axis: .vertical)
                .lineLimit(3...6)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Annotate Record")
    }
}
