import SwiftUI

enum SpectrumPalette: String, CaseIterable, Identifiable {
    case vivid = "Vivid"
    case cool = "Cool"
    case warm = "Warm"
    case mono = "Mono"

    var id: String { rawValue }

    var colors: [Color] {
        switch self {
        case .vivid:
            return [.red, .blue, .green, .orange, .pink, .teal, .purple, .indigo, .mint, .cyan, .brown]
        case .cool:
            return [.blue, .teal, .cyan, .mint, .indigo, .purple]
        case .warm:
            return [.red, .orange, .yellow, .pink, .brown]
        case .mono:
            return [.black, .gray, .gray.opacity(0.7), .gray.opacity(0.5)]
        }
    }
}
