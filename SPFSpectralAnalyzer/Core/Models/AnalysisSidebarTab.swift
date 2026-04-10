import Foundation

/// Category tabs for the analysis panel's left sidebar.
/// Filters loaded spectra by the role of their source dataset.
enum AnalysisSidebarTab: String, CaseIterable, Identifiable {
    case all = "All"
    case samples = "Samples"
    case references = "References"
    case prototypes = "Prototypes"

    var id: String { rawValue }
}
