#!/usr/bin/env python3
"""Phase 3: Extract view extension files from ContentView.swift.

Strategy: Read the file, identify line ranges for each extraction group,
write them to new extension files as `extension ContentView { ... }`,
then remove those lines from ContentView.swift.

All line numbers are 1-indexed to match the editor. We convert to 0-indexed for Python.
"""

import re

FILE = "ContentView.swift"

with open(FILE, 'r') as f:
    lines = f.readlines()

original_count = len(lines)
print(f"Starting with {original_count} lines")

def find_line(pattern, start=0):
    """Find first line matching pattern (0-indexed)."""
    for i in range(start, len(lines)):
        if re.search(pattern, lines[i]):
            return i
    return None

def find_func_end(start_idx):
    """Find the closing brace of a func/var starting at start_idx (0-indexed).
    Tracks brace depth."""
    depth = 0
    found_open = False
    for i in range(start_idx, len(lines)):
        for ch in lines[i]:
            if ch == '{':
                depth += 1
                found_open = True
            elif ch == '}':
                depth -= 1
                if found_open and depth == 0:
                    return i
    return None

# ============================================================
# Define extraction groups with their line ranges
# Each group: (output_file, imports, [(start_pattern, end_is_func_end)])
# We'll collect the actual line ranges first, then write files.
# ============================================================

# Helper to find a block from a pattern to its closing brace
def block_range(pattern, search_start=0):
    """Returns (start_idx, end_idx) 0-indexed inclusive."""
    s = find_line(pattern, search_start)
    if s is None:
        print(f"WARNING: Could not find pattern: {pattern}")
        return None
    e = find_func_end(s)
    if e is None:
        print(f"WARNING: Could not find end for: {pattern} at line {s+1}")
        return None
    return (s, e)

# Find all blocks
ranges = {}

# iCloud computed properties (lines 231-317 area)
ranges['iCloudStatusText'] = block_range(r'var iCloudStatusText:\s*String')
ranges['iCloudCondensedErrorText'] = block_range(r'var iCloudCondensedErrorText:\s*String')
ranges['shouldShowSyncStatusBar'] = block_range(r'var shouldShowSyncStatusBar:\s*Bool')
ranges['syncStatusMessage'] = block_range(r'var syncStatusMessage:\s*String')
ranges['syncEnabledLabel'] = block_range(r'var syncEnabledLabel:\s*String')
ranges['cloudKitAccountSummary'] = block_range(r'var cloudKitAccountSummary:\s*String')
ranges['lastSyncTimestampText'] = block_range(r'var lastSyncTimestampText:\s*String')
ranges['lastSyncStatusLabel'] = block_range(r'var lastSyncStatusLabel:\s*String')
ranges['lastSyncTriggerLabel'] = block_range(r'var lastSyncTriggerLabel:\s*String')

# Sync/cloud views
ranges['syncStatusBar'] = block_range(r'var syncStatusBar:\s*some View')
ranges['progressToggleButton'] = block_range(r'func progressToggleButton')
ranges['copyICloudStatusDetails'] = block_range(r'func copyICloudStatusDetails')
ranges['cloudKitBanner'] = block_range(r'var cloudKitBanner:\s*some View')
ranges['cloudKitProgressBanner'] = block_range(r'func cloudKitProgressBanner')
ranges['localStoreBanner'] = block_range(r'var localStoreBanner:\s*some View')

# Modifier chains
ranges['applyImporters'] = block_range(r'func applyImporters')
ranges['applyAlertsAndSheets'] = block_range(r'func applyAlertsAndSheets')
ranges['applyProcessingChangeHandlers'] = block_range(r'func applyProcessingChangeHandlers')
ranges['applySelectionChangeHandlers'] = block_range(r'func applySelectionChangeHandlers')
ranges['applyHDRSChangeHandlers'] = block_range(r'func applyHDRSChangeHandlers')
ranges['applyAIChangeHandlers'] = block_range(r'func applyAIChangeHandlers')

# Data Management tab
ranges['importPanel'] = block_range(r'var importPanel:\s*some View')
ranges['storedDatasetPickerSheet'] = block_range(r'var storedDatasetPickerSheet:\s*some View')
ranges['archivedDatasetSheet'] = block_range(r'var archivedDatasetSheet:\s*some View')
ranges['permanentDeleteSheet'] = block_range(r'var permanentDeleteSheet:\s*some View')

# Analysis tab
ranges['analysisPanel'] = block_range(r'var analysisPanel:\s*some View')
ranges['leftPanel'] = block_range(r'var leftPanel:\s*some View')
ranges['centerPanel'] = block_range(r'var centerPanel:\s*some View')
ranges['rightPanel'] = block_range(r'var rightPanel:\s*some View')
ranges['invalidItemsPanel'] = block_range(r'var invalidItemsPanel:\s*some View')

# AI Analysis section
ranges['aiAnalysisSection'] = block_range(r'var aiAnalysisSection:\s*some View')
ranges['summaryStrip'] = block_range(r'var summaryStrip:\s*some View')
ranges['dashboardPanel'] = block_range(r'func dashboardPanel')
ranges['dashboardEmptyPanel'] = block_range(r'var dashboardEmptyPanel:\s*some View')
ranges['dashboardCard'] = block_range(r'func dashboardCard')
# Dashboard interpretation helpers
ranges['complianceInterpretation'] = block_range(r'func complianceInterpretation')
ranges['uvaUvbInterpretation'] = block_range(r'func uvaUvbInterpretation')
ranges['criticalWavelengthInterpretation'] = block_range(r'func criticalWavelengthInterpretation')
ranges['trendsInterpretation'] = block_range(r'func trendsInterpretation\(')
ranges['trendsInterpretationColor'] = block_range(r'func trendsInterpretationColor')
# Interpretation delegates
ranges['calibrationQualityLabel'] = block_range(r'func calibrationQualityLabel')
ranges['deltaColor'] = block_range(r'func deltaColor')
ranges['inspectorAssessment'] = block_range(r'func inspectorAssessment')
ranges['inspectorBatchAssessment'] = block_range(r'func inspectorBatchAssessment')

# Pipeline/Inspector/BatchCompare
ranges['overlayControls'] = block_range(r'var overlayControls:\s*some View')
ranges['pipelinePanel'] = block_range(r'var pipelinePanel:\s*some View')
ranges['inspectorPanel'] = block_range(r'var inspectorPanel:\s*some View')
ranges['batchComparePanel'] = block_range(r'var batchComparePanel:\s*some View')
ranges['batchCompareSourceLabel'] = block_range(r'var batchCompareSourceLabel:\s*String')
ranges['batchCompareRows'] = block_range(r'var batchCompareRows:\s*\[BatchCompareRow\]')
ranges['batchCompareSpectra'] = block_range(r'var batchCompareSpectra:\s*\[ShimadzuSpectrum\]')
ranges['spfValue'] = block_range(r'func spfValue\(for:')
ranges['spcHeaderSection'] = block_range(r'var spcHeaderSection:\s*some View')
ranges['spcHeaderPreviewPanel'] = block_range(r'var spcHeaderPreviewPanel:\s*some View')

# AI Left/Right panes
ranges['aiLeftPane'] = block_range(r'var aiLeftPane:\s*some View')
ranges['aiRightPane'] = block_range(r'var aiRightPane:\s*some View')

# Bottom Tray & Chrome
ranges['bottomTray'] = block_range(r'var bottomTray:\s*some View')
ranges['statusPanel'] = block_range(r'var statusPanel:\s*some View')
ranges['backgroundView'] = block_range(r'var backgroundView:\s*some View')
ranges['panelBackground'] = block_range(r'var panelBackground:\s*some')

# Export Form
ranges['exportFormFields'] = block_range(r'var exportFormFields:\s*some View')
ranges['quickReportPanel'] = block_range(r'var quickReportPanel:\s*some View')
ranges['storedDatasetRow'] = block_range(r'func storedDatasetRow\(')
ranges['archivedDatasetRow'] = block_range(r'func archivedDatasetRow\(')
ranges['storedDatasetPickerRow'] = block_range(r'func storedDatasetPickerRow\(')

# Utility methods (metadata, persistence, etc.)
ranges['formatBytes'] = block_range(r'func formatBytes\(')
ranges['metadataSummaryLines'] = block_range(r'func metadataSummaryLines\(')
ranges['metadataDetailLines'] = block_range(r'func metadataDetailLines\(')
ranges['spcDateString'] = block_range(r'func spcDateString\(')
ranges['spectrumRowMenuContent'] = block_range(r'func spectrumRowMenuContent')

# Sidebar row views
ranges['spectrumRow'] = block_range(r'func spectrumRow\(for')
ranges['invalidSpectrumRow'] = block_range(r'func invalidSpectrumRow\(')
ranges['toggleSelection'] = block_range(r'func toggleSelection\(for')
ranges['removeSpectrum'] = block_range(r'func removeSpectrum\(at')
ranges['tagRow'] = block_range(r'func tagRow\(for')
ranges['metricChip'] = block_range(r'func metricChip\(')
# MetricStatus enum
metric_status_start = find_line(r'enum MetricStatus')
if metric_status_start:
    ranges['MetricStatus'] = (metric_status_start, find_func_end(metric_status_start))
ranges['tagChip'] = block_range(r'func tagChip\(')

# Chart
ranges['chartSection'] = block_range(r'var chartSection:\s*some View')
ranges['correlationSection'] = block_range(r'var correlationSection:\s*some View')
ranges['spfMathSheet'] = block_range(r'var spfMathSheet:\s*some View')
ranges['labelsSection'] = block_range(r'var labelsSection:\s*some View')

# Sheets
ranges['exportSheet'] = block_range(r'var exportSheet:\s*some View')
ranges['warningDetailsSheet'] = block_range(r'var warningDetailsSheet:\s*some View')
ranges['invalidDetailsSheet'] = block_range(r'var invalidDetailsSheet:\s*some View')

# Static and utility methods
ranges['sampleDisplayName'] = block_range(r'static func sampleDisplayName')
ranges['chartSeriesMarks'] = block_range(r'var chartSeriesMarks:\s*some ChartContent')
ranges['selectedPointMarks'] = block_range(r'var selectedPointMarks:\s*some ChartContent')
ranges['peakMarks'] = block_range(r'var peakMarks:\s*some ChartContent')
ranges['pointAnnotation'] = block_range(r'func pointAnnotation')
ranges['chartTooltipView'] = block_range(r'func chartTooltipView')
ranges['pointReadoutPanel'] = block_range(r'var pointReadoutPanel:\s*some View')
ranges['glassGroup'] = block_range(r'func glassGroup')
ranges['aiPromptPreset'] = block_range(r'var aiPromptPreset:\s*AIPromptPreset')
ranges['effectiveAIPrompt'] = block_range(r'var effectiveAIPrompt:\s*String')
ranges['aiDefaultScope'] = block_range(r'var aiDefaultScope:\s*AISelectionScope')
ranges['effectiveAIScope'] = block_range(r'var effectiveAIScope:\s*AISelectionScope')
ranges['hasAPIKey'] = block_range(r'var hasAPIKey:\s*Bool')
ranges['activeMetadataFromSelection'] = block_range(r'var activeMetadataFromSelection')
ranges['activeHeader'] = block_range(r'var activeHeader:\s*SPCMainHeader')
ranges['activeHeaderFileName'] = block_range(r'var activeHeaderFileName:\s*String')
ranges['aiCanRunAnalysis'] = block_range(r'var aiCanRunAnalysis:\s*Bool')
ranges['isStructuredOutputSupported'] = block_range(r'func isStructuredOutputSupported')
ranges['savePanel'] = block_range(r'func savePanel\(defaultName')
ranges['timestampedFileName'] = block_range(r'func timestampedFileName')
SaveDirectoryKey_start = find_line(r'enum SaveDirectoryKey')
if SaveDirectoryKey_start:
    ranges['SaveDirectoryKey'] = (SaveDirectoryKey_start, find_func_end(SaveDirectoryKey_start))
ranges['lastSaveDirectoryURL'] = block_range(r'func lastSaveDirectoryURL')
ranges['storeLastSaveDirectory'] = block_range(r'func storeLastSaveDirectory')
ranges['sanitizeCSVField'] = block_range(r'func sanitizeCSVField')

# Reporting tab
ranges['exportPanel'] = block_range(r'var exportPanel:\s*some View')

# Computed properties that are delegates
ranges['filteredSortedIndices'] = block_range(r'var filteredSortedIndices:\s*\[Int\]')
ranges['displayedSpectra_cv'] = block_range(r'var displayedSpectra:\s*\[ShimadzuSpectrum\]')

# PreviewData + #Preview
preview_start = find_line(r'private enum PreviewData')
if preview_start:
    preview_end = find_func_end(preview_start)
    ranges['PreviewData'] = (preview_start, preview_end)
preview_macro = find_line(r'#Preview')
if preview_macro:
    ranges['PreviewMacro'] = (preview_macro, find_func_end(preview_macro))

# Print found ranges
for name, r in sorted(ranges.items(), key=lambda x: x[1][0] if x[1] else 9999):
    if r:
        print(f"  {name}: lines {r[0]+1}-{r[1]+1}")
    else:
        print(f"  {name}: NOT FOUND")

# ============================================================
# Define output files and which blocks go into each
# ============================================================

file_groups = {
    "UI/Chrome/CloudSyncViews.swift": {
        "imports": "import SwiftUI\nimport AppKit\n",
        "blocks": [
            'iCloudStatusText', 'iCloudCondensedErrorText', 'shouldShowSyncStatusBar',
            'syncStatusMessage', 'syncEnabledLabel', 'cloudKitAccountSummary',
            'lastSyncTimestampText', 'lastSyncStatusLabel', 'lastSyncTriggerLabel',
            'syncStatusBar', 'progressToggleButton', 'copyICloudStatusDetails',
            'cloudKitBanner', 'cloudKitProgressBanner', 'localStoreBanner',
        ],
    },
    "ContentView+ChangeHandlers.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'applyImporters', 'applyAlertsAndSheets',
            'applyProcessingChangeHandlers', 'applySelectionChangeHandlers',
            'applyHDRSChangeHandlers', 'applyAIChangeHandlers',
        ],
    },
    "UI/Panels/ImportPanel.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'importPanel', 'storedDatasetPickerSheet', 'archivedDatasetSheet',
            'permanentDeleteSheet', 'storedDatasetRow', 'archivedDatasetRow',
            'storedDatasetPickerRow',
        ],
    },
    "UI/Panels/AnalysisPanel.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'analysisPanel', 'leftPanel', 'centerPanel', 'rightPanel',
            'invalidItemsPanel', 'filteredSortedIndices', 'displayedSpectra_cv',
            'exportPanel',
        ],
    },
    "UI/Panels/DashboardViews.swift": {
        "imports": "import SwiftUI\nimport Charts\n",
        "blocks": [
            'summaryStrip', 'dashboardPanel', 'dashboardEmptyPanel', 'dashboardCard',
            'complianceInterpretation', 'uvaUvbInterpretation',
            'criticalWavelengthInterpretation', 'trendsInterpretation',
            'trendsInterpretationColor',
            'calibrationQualityLabel', 'deltaColor',
            'inspectorAssessment', 'inspectorBatchAssessment',
        ],
    },
    "UI/Panels/PipelinePanel.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'overlayControls', 'pipelinePanel', 'inspectorPanel',
            'batchComparePanel', 'batchCompareSourceLabel', 'batchCompareRows',
            'batchCompareSpectra', 'spfValue',
            'spcHeaderSection', 'spcHeaderPreviewPanel',
        ],
    },
    "UI/Panels/AISection.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'aiAnalysisSection', 'aiLeftPane', 'aiRightPane',
        ],
    },
    "UI/Chrome/BottomTray.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'bottomTray', 'statusPanel', 'backgroundView', 'panelBackground',
        ],
    },
    "UI/Panels/ReportingPanel.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'exportFormFields', 'quickReportPanel',
        ],
    },
    "UI/Sheets/ContentViewSheets.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'spfMathSheet', 'exportSheet', 'warningDetailsSheet', 'invalidDetailsSheet',
        ],
    },
    "UI/Sidebar/SidebarViews.swift": {
        "imports": "import SwiftUI\n",
        "blocks": [
            'spectrumRow', 'invalidSpectrumRow', 'toggleSelection', 'removeSpectrum',
            'tagRow', 'metricChip', 'MetricStatus', 'tagChip',
            'spectrumRowMenuContent',
        ],
    },
    "UI/Chart/ChartSection.swift": {
        "imports": "import SwiftUI\nimport Charts\n",
        "blocks": [
            'chartSection', 'correlationSection', 'labelsSection',
            'chartSeriesMarks', 'selectedPointMarks', 'peakMarks',
            'pointAnnotation', 'chartTooltipView', 'pointReadoutPanel',
        ],
    },
    "ContentView+Utilities.swift": {
        "imports": "import SwiftUI\nimport UniformTypeIdentifiers\nimport AppKit\n",
        "blocks": [
            'sampleDisplayName', 'glassGroup',
            'aiPromptPreset', 'effectiveAIPrompt', 'aiDefaultScope',
            'effectiveAIScope', 'hasAPIKey',
            'activeMetadataFromSelection', 'activeHeader', 'activeHeaderFileName',
            'aiCanRunAnalysis', 'isStructuredOutputSupported',
            'savePanel', 'timestampedFileName', 'SaveDirectoryKey',
            'lastSaveDirectoryURL', 'storeLastSaveDirectory', 'sanitizeCSVField',
            'formatBytes', 'metadataSummaryLines', 'metadataDetailLines', 'spcDateString',
        ],
    },
}

# ============================================================
# Write extension files
# ============================================================

all_extracted_ranges = []  # list of (start, end) 0-indexed inclusive

for filename, group in file_groups.items():
    content_blocks = []
    for block_name in group['blocks']:
        r = ranges.get(block_name)
        if r is None:
            print(f"  SKIP {block_name} (not found)")
            continue
        start, end = r
        block_lines = lines[start:end+1]
        content_blocks.append(''.join(block_lines))
        all_extracted_ranges.append((start, end))

    if not content_blocks:
        print(f"  SKIP file {filename} (no blocks)")
        continue

    file_content = group['imports'] + "\nextension ContentView {\n\n"
    file_content += "\n".join(content_blocks)
    file_content += "\n}\n"

    # Write file
    outpath = filename
    with open(outpath, 'w') as f:
        f.write(file_content)
    print(f"  Wrote {outpath} ({len(content_blocks)} blocks)")

# Also write PreviewData separately (not an extension of ContentView)
if 'PreviewData' in ranges and ranges['PreviewData']:
    preview_lines = []
    s, e = ranges['PreviewData']
    preview_lines.extend(lines[s:e+1])
    all_extracted_ranges.append((s, e))
    if 'PreviewMacro' in ranges and ranges['PreviewMacro']:
        ms, me = ranges['PreviewMacro']
        preview_lines.append('\n')
        preview_lines.extend(lines[ms:me+1])
        preview_lines.append('\n')
        all_extracted_ranges.append((ms, me))

    preview_content = "import SwiftUI\n\n" + ''.join(preview_lines)
    with open("ContentView+Preview.swift", 'w') as f:
        f.write(preview_content)
    print(f"  Wrote ContentView+Preview.swift")

# ============================================================
# Remove extracted lines from ContentView.swift
# ============================================================

# Sort ranges and merge overlapping ones
all_extracted_ranges.sort()
merged = []
for start, end in all_extracted_ranges:
    if merged and start <= merged[-1][1] + 1:
        merged[-1] = (merged[-1][0], max(merged[-1][1], end))
    else:
        merged.append((start, end))

# Mark lines for removal
remove_set = set()
for start, end in merged:
    for i in range(start, end + 1):
        remove_set.add(i)

# Also remove any blank lines immediately after removed blocks (up to 2)
for start, end in merged:
    for i in range(end + 1, min(end + 3, len(lines))):
        if i not in remove_set and lines[i].strip() == '':
            remove_set.add(i)
        else:
            break

new_lines = [line for i, line in enumerate(lines) if i not in remove_set]

with open(FILE, 'w') as f:
    f.writelines(new_lines)

print(f"\nContentView.swift: {original_count} -> {len(new_lines)} lines (removed {original_count - len(new_lines)})")
print(f"Extracted {len(merged)} contiguous blocks covering {len(remove_set)} lines")
