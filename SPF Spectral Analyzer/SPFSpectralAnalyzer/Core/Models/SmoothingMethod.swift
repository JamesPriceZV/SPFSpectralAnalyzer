import Foundation

enum SmoothingMethod: String, CaseIterable, Identifiable {
    case none = "None"
    case movingAverage = "Moving Avg"
    case savitzkyGolay = "Savitzky-Golay"

    var id: String { rawValue }
}
