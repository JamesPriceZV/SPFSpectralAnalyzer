import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    // Primary tabs (always visible in tab bar)
    case library = "Library"
    case analysis = "Analysis"
    case ai = "AI"
    case export = "Export"

    // Sidebar-only sections
    #if os(iOS)
    case camera = "Camera"
    #endif
    case enterprise = "Enterprise"
    case sharePoint = "SharePoint"
    case oneDrive = "OneDrive"
    case teams = "Teams"
    case enterpriseSearch = "Search"
    case instruments = "Instruments"
    case mlTraining = "ML Training"

    var id: String { rawValue }

    /// Only primary tabs appear in the tab bar on iPhone
    var isPrimaryTab: Bool {
        switch self {
        case .library, .analysis, .ai, .export: return true
        default: return false
        }
    }
}
