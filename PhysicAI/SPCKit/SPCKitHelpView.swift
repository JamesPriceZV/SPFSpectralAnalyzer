// SPCKitHelpView.swift
// SPCKit
//
// In-app help documentation with table of contents and navigable sections.
// Covers all features, keyboard shortcuts, file format details, and workflows.

import SwiftUI

// MARK: - Help Section Model

private enum HelpSection: String, CaseIterable, Identifiable {
    case gettingStarted  = "Getting Started"
    case navigating      = "Navigating Your Data"
    case editing         = "Editing Data"
    case transforms      = "Transforms & Expressions"
    case metadata        = "Metadata"
    case subfiles        = "Subfile Management"
    case saving          = "Saving & Exporting"
    case diffPanel       = "Viewing Changes"
    case fileFormats     = "File Formats & Sizes"
    case shortcuts       = "Keyboard Shortcuts"
    case troubleshooting = "Troubleshooting"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .gettingStarted:  return "play.circle"
        case .navigating:      return "sidebar.left"
        case .editing:         return "pencil.and.outline"
        case .transforms:      return "function"
        case .metadata:        return "info.circle"
        case .subfiles:        return "rectangle.stack"
        case .saving:          return "square.and.arrow.down"
        case .diffPanel:       return "arrow.left.arrow.right"
        case .fileFormats:     return "doc.zipper"
        case .shortcuts:       return "keyboard"
        case .troubleshooting: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - HelpView

struct SPCKitHelpView: View {
    @State private var scrollTarget: HelpSection?
    @State private var selectedSection: HelpSection? = .gettingStarted

    var body: some View {
        HStack(spacing: 0) {
            // Sidebar TOC
            List(HelpSection.allCases, selection: $selectedSection) { section in
                Button {
                    scrollTarget = section
                    selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .tag(section)
            }
            .listStyle(.sidebar)
            .frame(width: 200)

            Divider()

            // Content
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 32) {
                        headerBlock

                        ForEach(HelpSection.allCases) { section in
                            VStack(alignment: .leading) {
                                sectionContent(for: section)
                            }
                            .id(section)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(24)
                }
                .onChange(of: scrollTarget) { _, target in
                    guard let target else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(target, anchor: .top)
                    }
                    scrollTarget = nil
                }
            }
        }
        .frame(minWidth: 700, idealWidth: 820, minHeight: 500, idealHeight: 750)
        .navigationTitle("SPCKit Help")
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("SPCKit Help", systemImage: "waveform.path")
                .font(.largeTitle.bold())
            Text("A multi-platform viewer and editor for Thermo Galactic SPC spectral data files.")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Section Router

    @ViewBuilder
    private func sectionContent(for section: HelpSection) -> some View {
        switch section {
        case .gettingStarted:  gettingStartedSection
        case .navigating:      navigatingSection
        case .editing:         editingSection
        case .transforms:      transformsSection
        case .metadata:        metadataSection
        case .subfiles:        subfilesSection
        case .saving:          savingSection
        case .diffPanel:       diffPanelSection
        case .fileFormats:     fileFormatsSection
        case .shortcuts:       shortcutsSection
        case .troubleshooting: troubleshootingSection
        }
    }

    // MARK: - 1. Getting Started

    private var gettingStartedSection: some View {
        sectionBlock("Getting Started", systemImage: "play.circle") {
            helpItem("Welcome Screen",
                     detail: "When you launch SPCKit, the welcome screen offers two options: Create New to start a blank document, or Open File to browse for an existing .spc file. On iPad and iPhone, the system document browser appears automatically with your recent SPC files.")
            helpItem("Open a File",
                     detail: "Use File > Open (or drag an .spc file onto the app window) to open an existing SPC file. SPCKit supports both standard Thermo Galactic and Shimadzu OLE2 compound formats. On iOS, tap any .spc file in the document browser to open it.")
            helpItem("Create a New Document",
                     detail: "Click Create New to start with a blank document. You can then import subfiles from other .spc files to build a combined spectrum file. Name your document using the tab bar before saving.")
            helpItem("Multi-Platform Support",
                     detail: "SPCKit runs natively on iPhone, iPad, and Mac. The interface adapts to each device: Mac and iPad use a three-column layout with sidebar, chart, and data table; iPhone uses a tabbed layout with dedicated Chart, Data, and Subfiles tabs for easy navigation on smaller screens.")
        }
    }

    // MARK: - 2. Navigating Your Data

    private var navigatingSection: some View {
        sectionBlock("Navigating Your Data", systemImage: "sidebar.left") {
            helpItem("Mac & iPad Layout",
                     detail: "On Mac and iPad, SPCKit uses a three-column NavigationSplitView. The left sidebar shows subfiles, the center displays the spectrum chart, and the right column shows the data table. Toolbar buttons provide quick access to all editing functions.")
            helpItem("iPhone Layout",
                     detail: "On iPhone, SPCKit uses a tabbed interface with three tabs: Chart (spectrum view with an Actions menu in the toolbar), Data (the X/Y point table), and Subfiles (the subfile list). All editing features are accessible through the Actions menu (ellipsis button) in the Chart tab's toolbar.")
            helpItem("Sidebar (Subfile List)",
                     detail: "Shows all subfiles in the document. Each entry displays the subfile index, custom name (if renamed), and point count. Click or tap a subfile to view its spectrum. Select multiple subfiles (Cmd+Click or Shift+Click on Mac) for batch operations like transforms.")
            helpItem("Spectrum Chart",
                     detail: "Displays the selected subfile's spectrum as a line chart using Swift Charts. The X and Y axes are labeled with the appropriate unit names from the file metadata. Pinch to zoom and drag to pan.")
            helpItem("Data Table",
                     detail: "Shows the raw X/Y point data for the focused subfile in a scrollable table. Use the filter field to search by index or X range (e.g. '400-500').")
            helpItem("Inspector Panel",
                     detail: "On Mac and iPad, toggle the inspector sidebar (Option+Cmd+I) to view header metadata, axis information, and the audit log. On iPhone, the inspector opens as a half-sheet from the Actions menu.")
        }
    }

    // MARK: - 3. Editing Data

    private var editingSection: some View {
        sectionBlock("Editing Data", systemImage: "pencil.and.outline") {
            helpItem("Point Editing",
                     detail: "Double-click any X or Y value in the data table to edit it directly. X values must maintain monotonic order (ascending or descending) -- SPCKit validates this and shows an error if the edit would violate monotonicity.")
            helpItem("Non-Destructive Editing",
                     detail: "All edits are stored as deltas on top of the original file. The source file is never modified. This means you can undo any change and the original data is always recoverable.")
            helpItem("Undo / Redo",
                     detail: "Full undo/redo support for all operations. Use Cmd+Z to undo and Shift+Cmd+Z to redo. The undo history includes point edits, transforms, metadata changes, and subfile management actions.")
        }
    }

    // MARK: - 4. Transforms & Expressions

    private var transformsSection: some View {
        sectionBlock("Transforms & Expressions", systemImage: "function") {
            helpItem("Opening the Transform Panel",
                     detail: "Use Edit > Transform (Cmd+T) or the toolbar button. Transforms apply to all currently selected subfiles in the sidebar.")
            helpItem("Scale X / Y",
                     detail: "Multiply all X or Y values by a constant factor. For example, Scale Y by 0.5 halves all intensity values.")
            helpItem("Offset X / Y",
                     detail: "Add a constant to all X or Y values. Useful for baseline correction or wavelength calibration shifts.")
            helpItem("Clamp Y",
                     detail: "Restrict Y values to a minimum and maximum range. Values outside the range are clamped to the nearest bound.")
            helpItem("Custom Expressions",
                     detail: "Enter a mathematical expression using the variables x and y. The expression is evaluated for each point in the selected subfiles.")
            helpItem("Supported Expression Syntax",
                     detail: """
                     Operators: + (add), - (subtract), * (multiply), / (divide), ^ (power)
                     Functions: sin, cos, tan, sqrt, abs, log (base 10), ln (natural log), exp
                     Variables: x (current X value), y (current Y value)
                     Constants: pi, e
                     Examples: "y * 2.5 + 0.1", "sqrt(abs(y))", "x - 400", "log(y + 1)"
                     """)
            helpItem("Performance",
                     detail: "Transforms use Apple's Accelerate framework (vDSP) for vectorized float operations, making bulk transforms fast even on large datasets.")
        }
    }

    // MARK: - 5. Metadata

    private var metadataSection: some View {
        sectionBlock("Metadata", systemImage: "info.circle") {
            helpItem("Edit Metadata (Option+Cmd+M)",
                     detail: "Opens the metadata editor with sections for: General (memo, experiment type), Axis Units (X/Y/Z unit pickers and custom labels), Instrument (resolution, source instrument, method file), and Multifile (Z increment, concentration factor).")
            helpItem("Memo Field",
                     detail: "A free-text description up to 130 characters. This is often used as the spectrum title and appears in the inspector and file listings.")
            helpItem("Experiment Type",
                     detail: "A numeric code indicating the type of experiment (e.g. UV-Vis, IR, Raman, mass spectrum). Standard codes are defined in the SPC specification.")
            helpItem("Axis Units",
                     detail: "X, Y, and Z axis unit codes with standard options (wavenumber, wavelength, absorbance, transmittance, etc.). Custom text labels can override the standard names.")
            helpItem("Rename Subfiles",
                     detail: "Right-click a subfile in the sidebar and choose Rename to assign a custom display name. This name is stored in the audit log when saving.")
            helpItem("Edit Z Values",
                     detail: "Right-click a subfile and choose Edit Z Values to set the Z start and Z end values. Z values typically represent time, temperature, or another independent variable in multifile datasets.")
        }
    }

    // MARK: - 6. Subfile Management

    private var subfilesSection: some View {
        sectionBlock("Subfile Management", systemImage: "rectangle.stack") {
            helpItem("Subfile Manager (Option+Cmd+U)",
                     detail: "Opens a panel to import, remove, and reorder subfiles within the current document.")
            helpItem("Import Subfiles from Another SPC File",
                     detail: "Click Import SPC in the Subfile Manager to browse for another .spc file. All subfiles from that file are added to the current document. SPCKit automatically materializes X arrays for Y-only subfiles so the data remains self-contained regardless of the source file's header settings.")
            helpItem("Combining Multiple Files",
                     detail: "To combine spectra from multiple instruments or runs: create a new document, then import subfiles from each source file. Each imported file's subfiles are appended to the document. You can then reorder, rename, or remove individual subfiles as needed.")
            helpItem("Remove Subfiles",
                     detail: "In the Subfile Manager, select one or more subfiles and click Remove Selected. Removed subfiles can be restored with Undo.")
            helpItem("Reorder Subfiles",
                     detail: "Drag and drop subfiles in the Subfile Manager list to change their order. The new order is reflected in the sidebar, chart, and the exported file.")
        }
    }

    // MARK: - 7. Saving & Exporting

    private var savingSection: some View {
        sectionBlock("Saving & Exporting", systemImage: "square.and.arrow.down") {
            helpItem("Save (Cmd+S)",
                     detail: "SPCKit never overwrites your original source file. Save always presents a Save As dialog so you can choose a filename and location for the exported file. This protects your original data at all times.")
            helpItem("Save As (Shift+Cmd+S)",
                     detail: "Identical to Save -- both present the export dialog. The suggested filename defaults to the document's tab name (if you've renamed it) or the memo field, with a .spc extension.")
            helpItem("Document Tab Naming",
                     detail: "You can name your document by editing the tab title in the title bar. This name is used as the default filename when saving, ensuring your exported file matches what you see in the app.")
            helpItem("Choosing an Output Format",
                     detail: "When you save, SPCKit presents a format picker with two options: Thermo Galactic SPC (the standard binary format, version 0x4B) and Shimadzu (OLE2/CFB) (Microsoft Compound File Binary format used by Shimadzu instruments). Choose the format that matches your target instrument or analysis software. The Thermo Galactic format is the default and most widely compatible.")
            helpItem("What Gets Saved",
                     detail: "The exported file includes: the 512-byte main header with all metadata edits, subheaders for each subfile, all X and Y point data, and the audit log (original entries plus a record of every edit made in SPCKit).")
        }
    }

    // MARK: - 8. Viewing Changes

    private var diffPanelSection: some View {
        sectionBlock("Viewing Changes", systemImage: "arrow.left.arrow.right") {
            helpItem("Diff Panel (Option+Cmd+D)",
                     detail: "Opens a side-by-side comparison of original and edited values. Available when unsaved changes exist.")
            helpItem("Metadata Diff",
                     detail: "The top section shows any changed metadata fields (memo, experiment type, axis units, etc.) with the original value on the left and the new value on the right, color-coded for easy scanning.")
            helpItem("Point-Level Diff",
                     detail: "Below the metadata diff, each subfile with changed data points is listed. Only modified X or Y values are shown, with original values in red and new values in green.")
        }
    }

    // MARK: - 9. File Formats & Sizes

    private var fileFormatsSection: some View {
        sectionBlock("File Formats & Sizes", systemImage: "doc.zipper") {
            helpItem("Thermo Galactic SPC (Standard)",
                     detail: "The standard binary format used by GRAMS, Galactic, and many other spectroscopy applications. Structure: 512-byte header, optional shared X block, 32-byte subheaders, Y (and optionally X) data arrays, optional directory block, and a log block with audit text.")
            helpItem("File Types Within SPC",
                     detail: """
                     Y-Only: X values are evenly spaced and computed from the header's First X and Last X values. Only Y data is stored, making these files very compact.
                     XYY: All subfiles share a single X array stored once after the header. Each subfile stores only its Y values.
                     XYXY: Each subfile has its own independent X and Y arrays. A directory block at the end provides byte offsets for random access.
                     """)
            helpItem("Legacy LabCalc Format",
                     detail: "Older 256-byte header format (version 0x4D). SPCKit reads these files but always exports in the modern 512-byte format.")
            helpItem("Shimadzu OLE2 Compound Files",
                     detail: "Some Shimadzu instruments save .spc files in Microsoft's OLE2 Compound File Binary format instead of the standard SPC layout. SPCKit detects these automatically (by checking for the OLE2 magic bytes D0 CF 11 E0) and reads the spectral data from the embedded storage streams. You can also export in this format by choosing \"Shimadzu (OLE2/CFB)\" in the format picker when saving. The exported file uses the same directory structure (Root Entry → DataStorage1 → DataSetGroup → DataSet → DataSpectrumStorage → Data → X/Y Data) that Shimadzu software expects.")
            helpItem("Why Exported Files May Be Smaller",
                     detail: "When opening Shimadzu OLE2 files, the source files can be significantly larger than the exported SPC files. This is normal. The OLE2 container format adds substantial overhead (sector allocation tables, directory entries, mini-stream sectors, alignment padding) that can account for 80-90% of the file size. SPCKit extracts only the raw spectral data and writes it in the efficient Thermo Galactic format, which stores the data with minimal overhead. For example, four 12 KB Shimadzu files with 111 points each produce a 3 KB combined SPC file -- all point data is preserved, only the container bloat is eliminated.")
            helpItem("File Size Reference",
                     detail: """
                     For a single subfile with N points:
                     - Y-only: 512 (header) + 32 (subheader) + N x 4 bytes (Y) + log
                     - XYY: add N x 4 bytes for the shared X array
                     - XYXY: add N x 4 bytes per subfile for individual X arrays + 12 bytes/subfile directory
                     Example: 111 points, 4 subfiles, XYY = 512 + 444 + 4 x (32 + 444) + log = ~3 KB
                     """)
        }
    }

    // MARK: - 10. Keyboard Shortcuts

    private var shortcutsSection: some View {
        sectionBlock("Keyboard Shortcuts", systemImage: "keyboard") {
            Group {
                shortcutGroup("File") {
                    shortcutRow("Save", shortcut: "Cmd + S")
                    shortcutRow("Save As", shortcut: "Shift + Cmd + S")
                }
                shortcutGroup("Edit") {
                    shortcutRow("Undo", shortcut: "Cmd + Z")
                    shortcutRow("Redo", shortcut: "Shift + Cmd + Z")
                    shortcutRow("Transform", shortcut: "Cmd + T")
                    shortcutRow("Edit Metadata", shortcut: "Option + Cmd + M")
                    shortcutRow("Manage Subfiles", shortcut: "Option + Cmd + U")
                    shortcutRow("View Changes", shortcut: "Option + Cmd + D")
                }
                shortcutGroup("View") {
                    shortcutRow("Toggle Inspector", shortcut: "Option + Cmd + I")
                }
                shortcutGroup("Help") {
                    shortcutRow("SPCKit Help", shortcut: "Cmd + ?")
                }
            }
        }
    }

    // MARK: - 11. Troubleshooting

    private var troubleshootingSection: some View {
        sectionBlock("Troubleshooting", systemImage: "wrench.and.screwdriver") {
            helpItem("File Won't Open",
                     detail: "Ensure the file has a .spc extension and is not corrupted. SPCKit supports standard Thermo Galactic SPC and Shimadzu OLE2 formats. Other vendor-specific variants may not be supported. On iOS, make sure the file is accessible in the Files app and that SPCKit has permission to read from that location.")
            helpItem("X Values Show as Zero",
                     detail: "This can happen with Y-only files where the header's First X and Last X are set to zero. Open the metadata editor (Option+Cmd+M) to check and correct the axis range values.")
            helpItem("Exported File is Smaller Than Source",
                     detail: "This is expected when the source is a Shimadzu OLE2 compound file. The OLE2 container adds significant overhead that is stripped during export. All spectral data is preserved -- see the File Formats section for details.")
            helpItem("Save Produces a File Without .spc Extension",
                     detail: "Always use File > Save (Cmd+S) or File > Save As (Shift+Cmd+S) to export. These use SPCKit's export pipeline which correctly applies the .spc extension. Avoid relying on the system's auto-save, which may not append the extension for custom file types.")
            helpItem("Transforms Not Applying",
                     detail: "Transforms apply only to subfiles selected in the sidebar (or the Subfiles tab on iPhone). Make sure at least one subfile is selected before opening the Transform panel.")
            helpItem("Unexpected Data After Import",
                     detail: "When importing Y-only subfiles from another SPC file, SPCKit materializes the X arrays using the source file's header values. This ensures imported data is self-contained. If the source file's header had incorrect First X / Last X values, the imported X data will reflect that.")
            helpItem("iPhone: Can't Find Editing Features",
                     detail: "On iPhone, all editing features (Transform, Metadata, Subfile Manager, Inspector, Save, Undo/Redo) are in the Actions menu -- tap the ellipsis (•••) button in the top-right corner of the Chart tab.")
        }
    }

    // MARK: - Components

    private func sectionBlock<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()
            Label(title, systemImage: systemImage)
                .font(.title2.bold())
            content()
        }
    }

    private func helpItem(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 8)
    }

    private func shortcutGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
                .padding(.top, 4)
            content()
        }
        .padding(.leading, 8)
    }

    private func shortcutRow(_ action: String, shortcut: String) -> some View {
        HStack {
            Text(action)
                .font(.body)
            Spacer()
            Text(shortcut)
                .font(.body.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 16)
    }
}
