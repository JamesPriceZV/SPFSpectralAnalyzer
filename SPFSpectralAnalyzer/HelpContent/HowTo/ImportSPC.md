@Article(
    title: "Import SPC Files"
)

## Overview
Importing SPC files brings spectra into the project workspace so they can be validated, analyzed, and exported.

## Supported Formats
SPF Spectral Analyzer supports two SPC file formats:
- **Shimadzu SPC** — Compound Binary File (OLE2/CFB) format used by Shimadzu instruments.
- **Galactic/Thermo SPC** — Standard SPC format (versions 0x4B, 0x4D, 0xCF) used by Thermo Scientific, PerkinElmer, and other instruments.

The correct parser is selected automatically based on the file's signature bytes.

## Steps
1. Open the Import tab in ``ContentView``.
2. Select one or more `.spc` files using the file picker.
3. Review the metadata and any warnings from the import stage.
4. Confirm the spectra appear in the list of loaded datasets.

## What Happens Behind the Scenes
- The file's magic bytes are inspected to determine the format.
- Galactic/Thermo files are parsed with the Galactic SPC parser, which handles evenly-spaced and per-subfile X data, multi-subfile layouts, and both integer-scaled and IEEE float Y values.
- Shimadzu files are parsed with the Compound File parser, navigating the OLE2 directory tree to extract X and Y data streams.
- Parse metadata is captured in the SPC metadata model.
- Imported files can be cached as ``StoredDataset`` entries for quick reloading.

## Troubleshooting
- If a file fails to import, verify it is a valid SPC file and not zero length.
- If warnings appear, check for missing data sets or unsupported header sections.
- Files with "Invalid Compound File signature" errors may be Galactic/Thermo format files. Ensure you are running the latest version, which supports both formats.
- "Subfile contains no data points" errors in older versions were caused by incorrect subfile header parsing. Update to the latest version, which correctly reads per-subfile point counts and shared X arrays (TXVALS flag).
- If Galactic/Thermo SPC spectra import but display as flat lines near zero, this was caused by incorrect Y-value exponent handling. The latest version reads the per-subfile exponent (subexp) and correctly distinguishes IEEE float from integer-scaled Y data.
