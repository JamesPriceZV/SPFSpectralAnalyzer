import Foundation

nonisolated struct ReferenceSpectrum: Sendable, Codable, Identifiable {
    var id: UUID = UUID()
    var modality: SpectralModality
    var sourceID: String
    var xValues: [Double]
    var yValues: [Double]
    var metadata: [String: String] = [:]
}
