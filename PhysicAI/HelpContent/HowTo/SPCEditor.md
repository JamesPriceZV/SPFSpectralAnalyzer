@Article(
    title: "SPC Editor"
)

## Overview
The SPC Editor lets you open, edit, transform, and save SPC spectral files directly within the Library. It is powered by the SPCKit engine, which supports both Thermo Galactic binary and Shimadzu OLE2/CFB formats.

## Opening the SPC Editor
Right-click any dataset in the Library to access the **SPCKit** submenu, which offers three options:

- **Create New Dataset** — Opens a blank SPC document in the editor. Use **Add from Library** or **Import File** to populate it with subfiles.
- **Edit** — Opens the selected dataset's SPC file in the editor. Subfiles are automatically named after the dataset filename. When multiple datasets are selected, this option becomes **Edit Combined**, merging all selected datasets into one document.
- **Duplicate** — Creates a copy of the dataset with a modified memo (timestamped) so the SHA-256 hash differs, bypassing deduplication. The copy opens in the editor for further changes.

The SPCKit submenu is available in both the active Samples tab and the Archived tab. Only datasets with valid SPC file data (Galactic 0x4B/0x4D or Shimadzu OLE2/CFB) can be edited or duplicated.

## Editor Layout

### Sidebar (Subfile Tree)
The left panel lists all subfiles in the SPC document. Subfiles are named after the source dataset filename (e.g., "File_260409_181639_spc_04926_OSB-Mod"). Multi-subfile documents append a suffix ("_1", "_2", etc.). You can rename subfiles, reorder them via drag-and-drop, and filter the list using the search field.

### Detail Area
The center panel displays an interactive spectrum chart of the selected subfile's X-Y data. You can zoom, pan, and inspect individual data points.

### Data Table
Toggle the **Data Table** toolbar button to show or hide the X-Y data table to the right of the spectrum chart. The table displays index, X, and Y values for the selected subfile with filtering by index or X range.

## Toolbar Actions

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

### Edit Metadata
Tap the **Edit Metadata** toolbar button (info circle icon) to open the metadata editor. You can modify:
- Memo text
- Experiment type
- Axis unit codes (X, Y, Z)
- Resolution description
- Source instrument
- Method file
- Z increment and concentration factor
- Custom axis labels

All metadata edits are tracked in the undo history.

### Import File
Tap **Import File** to import subfiles from an SPC file on disk into the current editor session.

### Add from Library
Tap **Add from Library** to import subfiles from datasets already stored in your Library. The picker lists all active (non-archived) datasets and supports search filtering. Select one or more datasets and tap "Add" to append their subfiles to the current document.

## Combining Datasets
To merge multiple SPC datasets into a single multi-subfile document:
1. In the Library, select two or more datasets (use Command-click or Shift-click).
2. Right-click and choose **SPCKit > Edit Combined**.
3. The first dataset becomes the base document; subfiles from the remaining datasets are appended.
4. The combined document opens in the SPC Editor where you can apply further edits before saving.

## Saving (Save As)
1. Tap the **Save As** toolbar button.
2. Choose an output format:
   - **Thermo Galactic SPC** — Standard binary SPC (0x4B header). Compatible with GRAMS, PerkinElmer, and most instruments.
   - **Shimadzu (OLE2/CFB)** — Compound Binary File format required for Shimadzu software compatibility.
3. Choose a file location and name.
4. The saved file is also added to your Library as a new dataset. The original dataset is preserved unchanged.

Datasets saved from the SPC Editor are marked with an **SPC** badge in the Library sidebar to distinguish them from directly imported files.

## Archived Dataset Actions
Archived datasets also support right-click context menus with:
- **Unarchive** — Restore the dataset to the active Samples list. Supports multi-select.
- **SPCKit** — Edit, Duplicate, or Create New Dataset (same options as active datasets).
- **Delete Permanently** — Permanently remove the dataset with a confirmation dialog. Supports multi-select.

## Resizable Editor Window
On macOS, the SPC Editor sheet is resizable. Drag the edges of the sheet to adjust the window size. The minimum size is 800x550 and it can expand to fill the screen.

## Troubleshooting
- **"No file data available"** — The dataset's original file bytes were not stored at import time. Re-import the file from the original source.
- **"Cannot open"** — The file may be corrupted or in an unsupported format variant. Verify the file opens in other SPC viewers.
- **Transform errors** — Some transforms require a minimum number of data points. Ensure the subfile has sufficient data.
- **Save As produces empty file** — Ensure at least one subfile exists in the document before saving.
- **"Add from Library" shows no datasets** — Ensure datasets have been imported into the Library. The picker only shows active (non-archived) datasets.

## Related Topics
- <doc:ImportSPC> — How SPC files are imported and parsed.
- <doc:ExportData> — Other export options for spectral data.
- <doc:AnalyzeAndCombine> — Analysis and combination workflows.
