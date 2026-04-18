@Article(
    title: "Instrument Registry"
)

## Overview
Track and manage the spectrophotometer instruments used in your lab. The instrument registry provides a catalog of over 80 known instruments from 8 major manufacturers, lets you assign instruments to datasets for provenance tracking, and supports scheduling calibration reminders.

## Instrument Catalog
The built-in catalog includes instruments from:
- Shimadzu (UV-2600i, UV-3600i Plus, SolidSpec-3700i, and more)
- PerkinElmer (Lambda series)
- Agilent (Cary series)
- JASCO (V-series)
- Hitachi (UH series)
- Thermo Fisher (Evolution series)
- Anton Paar (spectroscopy accessories)
- Other manufacturers

Each entry includes the instrument name, manufacturer, type (UV-Vis, UV-Vis-NIR, or FTIR), and wavelength range specifications.

## Assigning Instruments to Datasets
1. Open a dataset in Data Management.
2. Use the Assign Instrument sheet to link the dataset to a specific instrument.
3. The instrument assignment is stored with the dataset metadata and appears in exported reports.
4. Instrument provenance helps ensure traceability for regulatory compliance and QA review.

## Custom Instruments
If your instrument is not in the catalog:
1. Open the Instrument Registry from the toolbar or Settings.
2. Click Add Custom Instrument.
3. Enter the instrument name, manufacturer, type, and wavelength range.
4. The custom instrument becomes available for assignment to any dataset.

## Calibration Scheduling
Schedule calibration reminders for your instruments:
1. Select an instrument in the registry.
2. Set a calibration reminder interval (weekly, monthly, quarterly, or custom).
3. A calendar event is created using the system calendar (see <doc:CalendarScheduling>).
4. Reminders appear in your Calendar app at the scheduled intervals.

## Tips
- Assign instruments consistently to maintain audit trails across datasets.
- Include instrument information when sharing data packages or exporting reports.
- Use the calibration scheduler to stay compliant with your lab's QA/QC protocols.
