import Foundation

// MARK: - Sidebar Sort Mode

enum SidebarSortMode: String, CaseIterable, Identifiable {
    case importOrder = "Import Order"
    case nameAZ = "Name A→Z"
    case nameZA = "Name Z→A"
    case tag = "Tag"

    var id: String { rawValue }

    var label: String { rawValue }

    var icon: String {
        switch self {
        case .importOrder: return "arrow.up.arrow.down"
        case .nameAZ:      return "textformat.abc"
        case .nameZA:      return "textformat.abc"
        case .tag:         return "tag"
        }
    }
}
