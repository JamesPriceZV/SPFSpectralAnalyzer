import SwiftUI

struct SpectrumPoint: Identifiable {
    let id: Int
    let x: Double
    let y: Double
}

struct SpectrumSeries: Identifiable {
    let id = UUID()
    let name: String
    let points: [SpectrumPoint]
    let color: Color
}
