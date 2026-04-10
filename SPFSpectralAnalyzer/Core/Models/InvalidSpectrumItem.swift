import Foundation

struct InvalidSpectrumItem: Identifiable, Sendable {
    let id = UUID()
    let spectrum: ShimadzuSpectrum
    let fileName: String
    let reason: String

    var name: String { spectrum.name }
}
