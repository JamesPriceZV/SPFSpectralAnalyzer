@Article(
    title: "Export Data and Reports"
)

## Overview
Export spectra and reports for sharing, QA review, or downstream analysis.

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
- Batch statistics (averages, ranges, compliance rates)
- Vector-drawn spectra chart with axis labels and legend
- AI summary and recommendations (when available)
- Page numbers and footer

## Tips
- Use consistent titles and operator names to keep exports traceable.
- PDF reports include all displayed spectra metrics, not just the selected spectrum.
- Export the peaks CSV when you need peak-focused comparisons.
