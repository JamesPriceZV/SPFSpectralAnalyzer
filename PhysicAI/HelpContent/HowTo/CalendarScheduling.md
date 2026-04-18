@Article(
    title: "Calendar and Scheduling"
)

## Overview
Schedule calibration reminders for instruments and incubation timers for sample preparation. Events are created in the system calendar using EventKit and appear in the Calendar app on all synced devices.

## Calibration Reminders
Set up recurring reminders to calibrate your spectrophotometer instruments:
1. Open the Instrument Registry or select an instrument in Settings.
2. Choose Schedule Calibration Reminder.
3. Set the reminder frequency (weekly, monthly, quarterly, or a custom interval).
4. Optionally add notes about the calibration procedure.
5. The event is created in your default calendar with the specified recurrence.

Calibration reminders help maintain compliance with lab QA/QC protocols and regulatory requirements.

## Incubation Timers
Schedule reminders during sample preparation workflows:
1. From the Schedule Event sheet, select Incubation Timer.
2. Set the duration (e.g., 15 minutes, 1 hour, 24 hours).
3. Add a description of the sample or experiment.
4. A calendar event is created at the calculated end time with an alert.

This is useful for timed UV exposure, temperature incubation, or other waiting steps in the COLIPA or ISO 24443 test methods.

## Permissions
The app requests full calendar access when you first create an event. You can manage this permission in System Settings (macOS) or Settings (iOS) under Privacy and Security, then Calendars.

## Tips
- Calendar events sync across all your Apple devices via iCloud.
- Use calibration reminders to establish a regular maintenance schedule.
- Incubation timers include alerts so you receive a notification when the waiting period ends.
