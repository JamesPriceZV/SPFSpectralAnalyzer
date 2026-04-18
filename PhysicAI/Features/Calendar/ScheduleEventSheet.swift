import SwiftUI

/// A sheet for scheduling calendar events (calibration reminders or incubation re-tests).
struct ScheduleEventSheet: View {
    enum EventType: Identifiable {
        case calibration(instrumentName: String)
        case incubation(sampleName: String)

        var id: String {
            switch self {
            case .calibration(let name): return "cal-\(name)"
            case .incubation(let name):  return "inc-\(name)"
            }
        }

        var title: String {
            switch self {
            case .calibration(let name): return "Schedule Calibration: \(name)"
            case .incubation(let name):  return "Schedule Re-test: \(name)"
            }
        }

        var defaultNotes: String {
            switch self {
            case .calibration(let name): return "Calibration reminder for \(name)."
            case .incubation(let name):  return "Post-incubation re-test for \(name)."
            }
        }
    }

    let eventType: EventType
    @Environment(\.dismiss) private var dismiss

    @State private var selectedDate = Date().addingTimeInterval(3600) // 1 hour from now
    @State private var notes = ""
    @State private var isSaving = false
    @State private var resultMessage: String?
    @State private var didSave = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Event Details") {
                    Text(eventType.title)
                        .font(.headline)

                    DatePicker("Date & Time", selection: $selectedDate, in: Date()...)
                }

                Section("Notes") {
                    TextEditor(text: $notes)
                        .frame(minHeight: 60)
                }

                if let message = resultMessage {
                    Section {
                        HStack {
                            Image(systemName: didSave ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                .foregroundColor(didSave ? .green : .orange)
                            Text(message)
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Schedule Event")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveEvent()
                    }
                    .disabled(isSaving)
                }
            }
            .onAppear {
                notes = eventType.defaultNotes
            }
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 300)
        #endif
    }

    private func saveEvent() {
        isSaving = true
        Task {
            let service = CalendarService.shared
            let identifier: String?

            switch eventType {
            case .calibration(let name):
                identifier = await service.scheduleCalibrationReminder(
                    instrumentName: name,
                    date: selectedDate,
                    notes: notes
                )
            case .incubation(let name):
                identifier = await service.scheduleIncubationTimer(
                    sampleName: name,
                    date: selectedDate,
                    notes: notes
                )
            }

            await MainActor.run {
                isSaving = false
                if identifier != nil {
                    didSave = true
                    resultMessage = "Event saved to Calendar."
                    // Auto-dismiss after brief delay
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1))
                        dismiss()
                    }
                } else {
                    resultMessage = "Could not save event. Check Calendar permissions in System Settings."
                }
            }
        }
    }
}
