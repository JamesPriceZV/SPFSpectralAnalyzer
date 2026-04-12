@Article(
    title: "Import SPC Files"
)

## Overview
Importing SPC files brings spectra into the project workspace so they can be validated, analyzed, and exported.

## Supported Formats
SPF Spectral Analyzer supports two SPC file formats:

### Galactic/Thermo SPC (Standard SPC)
The standard SPC binary format was developed by Galactic Industries Corporation (now Thermo Fisher Scientific) in 1996. It is used by Thermo Scientific, PerkinElmer, Shimadzu (DL82 export), and many other instruments. Recognized version bytes: 0x4B (new format), 0x4D (old format), and 0xCF (old with log).

**Binary layout:**
- **Main header** — 512 bytes containing global metadata: flags (`ftflgs`), version, experiment type, Y exponent (`fexp`), point count (`fnpts`), X range (`ffirst`/`flast`), subfile count, axis unit codes, memo text, and log block offset.
- **Shared X array** (optional) — When TXVALS (0x80) is set without TXYXYS, an array of `fnpts` IEEE 32-bit floats follows the header, providing shared X values for all subfiles.
- **Subfiles** — Each subfile begins with a 32-byte subheader (`subflgs`, `subexp`, `subindx`, `subtime`, `subnext`, `subnois`, `subnpts`, `subscan`, `subwlevel`, reserved), followed by data arrays.

**Key flags in `ftflgs`:**
- `0x01` (TSPREC) — Y values are 16-bit integers instead of 32-bit.
- `0x04` (TMULTI) — Multiple subfiles with potentially different point counts.
- `0x40` (TXYXYS) — Each subfile carries its own X-Y pair. Per the spec, X array precedes Y array within each subfile. `fnpts` is typically 0; point count comes from `subnpts` at subheader offset +16.
- `0x80` (TXVALS) — Explicit X values are stored (not evenly spaced). Without TXYXYS, a shared X array precedes all subfiles.

**Y-value encoding:**
- If `fexp` is 0x80 (-128 signed), Y values are IEEE 32-bit floats.
- If `fexp` is 0, the per-subfile `subexp` byte determines encoding. If `subexp` is 0x80, Y values are IEEE floats; otherwise `subexp` is the integer scaling exponent.
- For integer-scaled Y: `value = raw_int32 × 2^exp / 2^32` (or `2^exp / 2^16` for 16-bit).

**Reference specifications:**
- [Galactic Universal Data Format Specification (1997)](https://ensembles-eu.metoffice.gov.uk/met-res/aries/technical/GSPC_UDF.PDF)
- [A Brief Guide to SPC File Format and Using GSPCIO](https://docs.c6h6.org/docs/assets/files/spc-3bb9ec9e4c158c5418bcfcc970be77f1.pdf)

### Shimadzu SPC (OLE2/CFB)
Shimadzu instruments use a Compound Binary File (also known as OLE2 or CFB) container for their native SPC format. This is the same container format used by older Microsoft Office documents (.doc, .xls).

**Binary layout:**
- **CFB header** — 512 bytes beginning with magic bytes `D0 CF 11 E0 A1 B1 1A E1`. Contains sector size, FAT/DIFAT locations, and directory stream offset.
- **Directory tree** — A hierarchy of storage and stream entries. Spectral data is found under a `DataSetGroup` storage, with each dataset containing named streams for X and Y data (typically arrays of IEEE 64-bit doubles).
- **FAT/MiniFAT** — Sector allocation tables that map stream data across the file.

**Reference specification:**
- [Microsoft Compound Binary File Format (MS-CFB)](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-cfb/)

### Format Detection
The correct parser is selected automatically based on the file's signature bytes. If byte 1 matches a Galactic version (0x4B, 0x4D, or 0xCF), ``GalacticSPCParser`` is used. Otherwise, the file is attempted as a Shimadzu OLE2 container via ``ShimadzuSPCParser``.

## Steps
1. Open the Import tab in ``ContentView``.
2. Select one or more `.spc` files using the file picker.
3. Review the metadata and any warnings from the import stage.
4. Confirm the spectra appear in the list of loaded datasets.

## What Happens Behind the Scenes
- The file's magic bytes are inspected to determine the format.
- Galactic/Thermo files are parsed with ``GalacticSPCParser``, which handles evenly-spaced X, shared X arrays (TXVALS), per-subfile X-Y pairs (TXYXYS), multi-subfile layouts, and both integer-scaled and IEEE float Y values.
- Shimadzu files are parsed with ``ShimadzuSPCParser``, navigating the OLE2 directory tree to extract X and Y data streams.
- The SPC header is parsed separately by ``SPCHeaderParser`` for display, showing flags, unit codes, experiment type, memo text, and axis ranges.
- Parse metadata is captured in ``ShimadzuSPCMetadata``.
- Imported files are persisted as ``StoredDataset`` entries with their original file bytes cached. Parsed spectra are stored as ``StoredSpectrum`` binary blobs for fast reloading without re-parsing.

## Re-parsing Stored Datasets
If a dataset was imported with an older parser version that had bugs, the stored spectra may contain stale or incorrect data. To refresh without deleting and re-importing:

1. Right-click the dataset in the Import panel.
2. Select **Re-parse from Source**.
3. The app re-parses the cached file bytes with the current parser, replaces the stored spectra, and updates metadata.
4. Load the dataset again to see the corrected data.

This requires that the original file data was stored at import time (the ``StoredDataset/fileData`` field). If the source data is not available, re-import from the original file.

## Troubleshooting
- If a file fails to import, verify it is a valid SPC file and not zero length.
- If warnings appear, check for missing data sets or unsupported header sections.
- Files with "Invalid Compound File signature" errors may be Galactic/Thermo format files. Ensure you are running the latest version, which supports both formats.
- "Subfile contains no data points" typically means `fnpts` is 0 in the main header and the subfile headers also lack valid point counts. This can occur with non-standard SPC writers.
- If spectra import but display as flat lines near zero, the Y-value exponent may not be detected correctly. The parser checks both the main header `fexp` and per-subfile `subexp` to determine whether Y data is IEEE float or integer-scaled.
- If previously imported datasets show incorrect data after a parser update, use **Re-parse from Source** (right-click context menu) to refresh the stored spectra.
