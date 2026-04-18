import EventKit
import Foundation

/// Manages calendar event creation for calibration reminders and incubation timers.
/// Uses EventKit which works on both macOS and iOS.
@MainActor
final class CalendarService {

    static let shared = CalendarService()

    private let eventStore = EKEventStore()

    private init() {}

    // MARK: - Authorization

    /// Requests full calendar access. Returns true if granted.
    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            print("[CalendarService] Access request failed: \(error.localizedDescription)")
            return false
        }
    }

    var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - Event Creation

    /// Schedules a calibration reminder for an instrument.
    /// - Parameters:
    ///   - instrumentName: Display name of the instrument.
    ///   - date: When the calibration should occur.
    ///   - notes: Optional notes for the event.
    /// - Returns: The saved event identifier, or nil on failure.
    @discardableResult
    func scheduleCalibrationReminder(
        instrumentName: String,
        date: Date,
        notes: String? = nil
    ) async -> String? {
        guard await requestAccess() else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.title = "Calibrate: \(instrumentName)"
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .hour, value: 1, to: date)
        event.notes = notes ?? "Scheduled calibration reminder for \(instrumentName) from PhysicAI."
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Add a 30-minute reminder alarm
        let alarm = EKAlarm(relativeOffset: -1800) // 30 minutes before
        event.addAlarm(alarm)

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            print("[CalendarService] Failed to save calibration event: \(error.localizedDescription)")
            return nil
        }
    }

    /// Schedules an incubation re-test deadline.
    /// - Parameters:
    ///   - sampleName: Name of the sample being tested.
    ///   - date: When the re-test should occur.
    ///   - notes: Optional notes.
    /// - Returns: The saved event identifier, or nil on failure.
    @discardableResult
    func scheduleIncubationTimer(
        sampleName: String,
        date: Date,
        notes: String? = nil
    ) async -> String? {
        guard await requestAccess() else { return nil }

        let event = EKEvent(eventStore: eventStore)
        event.title = "Re-test: \(sampleName)"
        event.startDate = date
        event.endDate = Calendar.current.date(byAdding: .minute, value: 30, to: date)
        event.notes = notes ?? "Incubation period complete. Re-test sample \"\(sampleName)\" from PhysicAI."
        event.calendar = eventStore.defaultCalendarForNewEvents

        // Add a 15-minute reminder alarm
        let alarm = EKAlarm(relativeOffset: -900)
        event.addAlarm(alarm)

        do {
            try eventStore.save(event, span: .thisEvent)
            return event.eventIdentifier
        } catch {
            print("[CalendarService] Failed to save incubation event: \(error.localizedDescription)")
            return nil
        }
    }
}
