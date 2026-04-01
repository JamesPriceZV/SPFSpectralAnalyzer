import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case dataManagement = "Data Management"
    case analyze = "Analyze"
    #if os(iOS)
    case camera = "Camera"
    #endif
    case reporting = "Reporting"
    case enterprise = "Enterprise"
    case settings = "Settings"

    var id: String { rawValue }
}
