@Article(
    title: "SPC Editor"
)

## Overview
The SPC Editor lets you open, edit, transform, and save SPC spectral files directly within the Library. It is powered by the SPCKit engine, which supports both Thermo Galactic binary and Shimadzu OLE2/CFB formats.

## Opening the SPC Editor
1. In the Library sidebar (macOS) or Data Management tab (iOS), right-click a dataset that was imported from an SPC file.
2. Select **Open in SPC Editor...** from the context menu.
3. The editor opens as a sheet with a navigation split view: the sidebar lists subfiles, and the detail area shows the spectrum chart.

Only datasets with valid SPC file data can be opened. The editor detects Galactic (0x4B/0x4D) and Shimadzu (OLE2/CFB) formats automatically.

## Editor Layout

### Sidebar (Subfile Tree)
The left panel lists all subfiles in the SPC document. Select a subfile to view its spectrum in the chart. Multi-subfile documents show each subfile with its index and any metadata label.

### Detail (Spectrum Chart)
The right panel displays an interactive chart of the selected subfile's X-Y data. You can zoom, pan, and inspect individual data points.

## Editing Features

### Undo and Redo
All edits are tracked in a non-destructive delta store. Use the **Undo** and **Redo** toolbar buttons (or Command-Z / Command-Shift-Z) to step through the edit history.

### Transforms
Tap the **Transform** toolbar button (function icon) to open the Transform panel. Available transforms include:
- **Scale Y** — Multiply Y values by a constant factor.
- **Offset Y** — Add a constant to all Y values.
- **Derivative** — Compute the first or second derivative of the spectrum.
- **Smoothing** — Apply Savitzky-Golay or moving average smoothing.
- **Baseline Correction** — Remove baseline drift.
- **Expression** — Apply a custom mathematical expression to X or Y values using the built-in expression parser.

Transforms are applied to the currently selected subfile(s). Each transform is recorded in the audit log and can be undone.

## Combining Datasets
To merge multiple SPC datasets into a single multi-subfile document:
1. In the Library sidebar, select two or more datasets (use Command-click or Shift-click).
2. Right-click and choose **Combine Selected into SPC...**.
3. The first dataset becomes the base document; subfiles from the remaining datasets are appended.
4. The combined document opens in the SPC Editor where you can apply further edits before saving.

## Saving (Save As)
1. Tap the **Save As...** toolbar button.
2. Choose an output format:
   - **Thermo Galactic SPC** — Standard binary SPC (0x4B header). Compatible with GRAMS, PerkinElmer, and most instruments.
   - **Shimadzu (OLE2/CFB)** — Compound Binary File format required for Shimadzu software compatibility.
3. Choose a file location and name.
4. The saved file is also added to your Library as a new dataset. The original dataset is preserved unchanged.

Datasets saved from the SPC Editor are marked with an **SPC** badge in the Library sidebar to distinguish them from directly imported files.

## Troubleshooting
- **"No file data available"** — The dataset's original file bytes were not stored at import time. Re-import the file from the original source.
- **"Cannot open"** — The file may be corrupted or in an unsupported format variant. Verify the file opens in other SPC viewers.
- **Transform errors** — Some transforms require a minimum number of data points. Ensure the subfile has sufficient data.
- **Save As produces empty file** — Ensure at least one subfile exists in the document before saving.

## Related Topics
- <doc:ImportSPC> — How SPC files are imported and parsed.
- <doc:ExportData> — Other export options for spectral data.
- <doc:AnalyzeAndCombine> — Analysis and combination workflows.
