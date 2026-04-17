import Foundation

nonisolated struct TrainingRecord: Sendable, Codable, Identifiable {
    var id: UUID = UUID()
    var modality: SpectralModality
    var sourceID: String
    var createdAt: Date = Date()
    var features: [Float]
    var targets: [String: Double]
    var metadata: [String: String]
    var isComputedLabel: Bool = true
    var computationMethod: String?

    func featureDictionary() -> [String: Double] {
        let spec = ModalityAxisSpec.make(for: modality)
        var d: [String: Double] = [:]
        for (i, axVal) in spec.axisValues.enumerated() where i < features.count {
            let key: String
            switch modality {
            case .nmrProton:
                key = "\(spec.featureNamePrefix)\(String(format: "%.2f", axVal).replacingOccurrences(of: ".", with: "p"))"
            default:
                key = "\(spec.featureNamePrefix)\(Int(axVal))"
            }
            d[key] = Double(features[i])
        }
        for (k, v) in targets { d[k] = v }
        return d
    }
}
