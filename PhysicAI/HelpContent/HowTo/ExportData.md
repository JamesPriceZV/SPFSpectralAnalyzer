@Article(
    title: "Export Data and Reports"
)

## Overview
Export spectra and reports for sharing, QA review, regulatory submissions, or downstream analysis. In addition to local file export, you can upload directly to SharePoint, share via Teams, or create portable data packages.

## Quick Reports
The Reporting tab provides Quick Report buttons for the two most common export formats:
- Export PDF Report: Generates a comprehensive PDF with title, metadata, SPF estimation callout, key metrics table, labeled spectra chart, AI summary, and recommendations.
- Export HTML Report: Generates an interactive HTML report with embedded charts.

## Steps
1. Open the Reporting tab in ``ContentView``.
2. Fill in the title, operator name, and notes fields.
3. Toggle whether to include processing settings and metadata.
4. Click Export PDF Report or Export HTML Report from the Quick Reports panel.

## Export Formats Available
Use the export sheet (accessible from the menu bar) for additional formats:
- CSV: Data table for spreadsheets and scripts.
- JCAMP: Spectral exchange format for lab tools.
- Excel (.xlsx): Workbook with spectra and metadata.
- Word (.docx): Report for sharing and review.
- PDF Report: Comprehensive report with charts, metrics, and AI recommendations.
- HTML Report: Interactive report with embedded visualizations.

## PDF Report Contents
The PDF report includes:
- Title and generation date
- Operator name, notes, and instrument metadata
- SPF calculation method used
- Processing pipeline settings
- SPF estimation callout with tier badge
- Key metrics table with per-spectrum data (critical wavelength, UVA/UVB ratio, SPF)
- CoreML prediction with confidence interval (when a trained model is available)
- Batch statistics (averages, ranges, compliance rates)
- Vector-drawn spectra chart with axis labels and legend
- AI summary and recommendations (when available)
- Page numbers and footer

## SharePoint Export
Upload reports directly to your organization's SharePoint or OneDrive:
1. Ensure Microsoft 365 Enterprise is configured in Settings (see <doc:M365Enterprise>).
2. Generate a report in any format.
3. Click Export to SharePoint or open the SharePoint Export panel.
4. Select the destination site, library, and folder.
5. Upload progress is displayed. Large files use chunked uploads supporting up to approximately 2 GB.

Configure a default SharePoint export destination in Settings to streamline repeated uploads.

## Data Packages
Bundle datasets and analysis results into a portable `.spfpackage` file:
1. Select datasets in Data Management or Analysis.
2. Choose Share and select Data Package format.
3. The package includes spectral data, analysis settings, AI summary, and metrics.

See <doc:SharingPackages> for full details on data package contents and sharing options.

## Chart Snapshots
Export the current chart as a high-resolution PNG image for use in presentations, publications, or sharing. Chart snapshots are available from the sharing menu and include all visible overlays, axis labels, and legends.

## Teams Sharing
Share reports and data packages directly to Microsoft Teams channels or chats. See <doc:SharingPackages> for details.

## Tips
- Use consistent titles and operator names to keep exports traceable.
- PDF reports include all displayed spectra metrics, not just the selected spectrum.
- Export the peaks CSV when you need peak-focused comparisons.
- Set a default SharePoint destination in Settings to avoid selecting it each time.
