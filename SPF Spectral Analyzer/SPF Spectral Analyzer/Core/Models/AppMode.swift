import Foundation

enum AppMode: String, CaseIterable, Identifiable {
    case dataManagement = "Data Management"
    case analyze = "Analyze"
    case reporting = "Reporting"
    case settings = "Settings"

    var id: String { rawValue }
}
