@Article(
    title: "Import SPC Files"
)

## Overview
Importing SPC files brings spectra into the project workspace so they can be validated, analyzed, and exported.

## Steps
1. Open the Import tab in ``ContentView``.
2. Select one or more `.spc` files using the file picker.
3. Review the metadata and any warnings from the import stage.
4. Confirm the spectra appear in the list of loaded datasets.

## What Happens Behind the Scenes
- Files are parsed with ``ShimadzuSPCParser``.
- Parse metadata is captured in ``ShimadzuSPCMetadata``.
- Imported files can be cached as ``StoredDataset`` entries for quick reloading.

## Troubleshooting
- If a file fails to import, verify it is a valid SPC file and not zero length.
- If warnings appear, check for missing data sets or unsupported header sections.
