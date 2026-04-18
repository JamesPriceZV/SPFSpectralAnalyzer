@Article(
    title: "Sharing and Data Packages"
)

## Overview
Share analysis results, spectral datasets, and chart images with collaborators using the system share sheet, Microsoft Teams, Messages, AirDrop, or email. Data packages bundle everything needed to reproduce an analysis into a single portable file.

## Data Packages
The `.spfpackage` format is a JSON-based archive that bundles:
- Selected spectral datasets with full wavelength/absorbance data
- Analysis settings (smoothing, normalization, baseline correction, etc.)
- AI analysis summary (when available)
- SPF estimation results and metrics
- Metadata including instrument assignment and operator information

To create a data package:
1. Select the datasets you want to share in Data Management or Analysis.
2. Choose Share from the menu or toolbar.
3. Select Data Package as the format.
4. Choose a sharing destination (Messages, AirDrop, email, save to file, etc.).

Recipients can open `.spfpackage` files directly in PhysicAI to load all bundled data and settings.

## Chart Snapshots
Export the current spectral chart as a high-resolution PNG image:
1. Open the Analysis or Reporting tab with spectra displayed in the chart.
2. Choose Share Chart Snapshot from the sharing options.
3. The chart is rendered as a PNG image and sent to the share sheet.

Chart snapshots include axis labels, legends, and any overlays currently displayed.

## Share Targets
The share sheet provides access to all system sharing destinations:
- Messages (iMessage): Share data packages or chart images directly in conversations.
- AirDrop: Transfer to nearby Apple devices.
- Email: Attach files to a new email message.
- Microsoft Teams: Share to Teams channels or chats (requires M365 integration).
- Files: Save to iCloud Drive, OneDrive, or other file providers.
- Third-party apps: Any app that accepts the shared file type.

## Teams Sharing
When Microsoft 365 Enterprise integration is enabled, you can share directly to Teams:
1. Select datasets or generate a report.
2. Choose Share to Teams.
3. Pick the team, channel, or chat.
4. The data package, chart snapshot, or report is posted as a message attachment.

## Tips
- Use data packages when you need collaborators to reproduce your exact analysis.
- Use chart snapshots for quick visual sharing in presentations or reports.
- iCloud sync also keeps datasets in sync across your own devices (see Settings).
