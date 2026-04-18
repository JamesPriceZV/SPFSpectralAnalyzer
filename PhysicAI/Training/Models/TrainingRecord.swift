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
            case .mossbauer:
                // Negative velocity values need sign-preserving keys
                let formatted = String(format: "%.1f", axVal)
                    .replacingOccurrences(of: ".", with: "p")
                    .replacingOccurrences(of: "-", with: "n")
                key = "\(spec.featureNamePrefix)\(formatted)"
            case .dftQuantumChem, .gcRetention, .hplcRetention:
                // Indexed features, not axis bins
                key = "\(spec.featureNamePrefix)\(Int(axVal))"
            default:
                key = "\(spec.featureNamePrefix)\(Int(axVal))"
            }
            d[key] = Double(features[i])
        }
        for (k, v) in targets { d[k] = v }
        return d
    }
}
