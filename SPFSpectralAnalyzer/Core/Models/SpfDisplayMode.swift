import Foundation

enum SpfDisplayMode: String, CaseIterable, Identifiable {
    case colipa
    case calibrated

    var id: String { rawValue }

    var label: String {
        switch self {
        case .colipa:
            return "COLIPA SPF"
        case .calibrated:
            return "Estimated SPF (calibrated)"
        }
    }
}
