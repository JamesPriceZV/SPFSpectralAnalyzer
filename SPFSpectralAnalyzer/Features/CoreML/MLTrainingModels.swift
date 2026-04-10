import Foundation

// MARK: - ISO 24443 Metadata Types

/// Substrate plate type for ISO 24443 compliance.
enum SubstratePlateType: String, CaseIterable, Codable, Sendable, Identifiable {
    case pmma     // Standard PMMA (HD6 moulded or SB6 sandblasted)
    case quartz
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pmma:   return "PMMA"
        case .quartz: return "Quartz"
        case .other:  return "Other"
        }
    }
}

/// PMMA plate subtype per ISO 24443 (only applicable when plate type is PMMA).
enum PMMAPlateSubtype: String, CaseIterable, Codable, Sendable, Identifiable {
    case moulded      // HD6 moulded plates
    case sandblasted  // SB6 sandblasted plates

    var id: String { rawValue }

    var label: String {
        switch self {
        case .moulded:     return "Moulded (HD6)"
        case .sandblasted: return "Sandblasted (SB6)"
        }
    }

    /// Integer encoding for ML feature columns.
    var featureValue: Int {
        switch self {
        case .moulded:     return 0
        case .sandblasted: return 1
        }
    }
}

/// UV filter formulation category.
enum FormulationType: String, CaseIterable, Codable, Sendable, Identifiable {
    case mineralZnO          // Mineral (ZnO)
    case mineralTiO2         // Mineral (TiO₂)
    case mineralZnOTiO2      // Mineral (ZnO + TiO₂)
    case organic             // Organic UV filters only
    case organicZnO          // Organic + ZnO
    case organicTiO2         // Organic + TiO₂
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mineralZnO:     return "Mineral (ZnO)"
        case .mineralTiO2:    return "Mineral (TiO₂)"
        case .mineralZnOTiO2: return "Mineral (ZnO + TiO₂)"
        case .organic:        return "Organic"
        case .organicZnO:     return "Organic + ZnO"
        case .organicTiO2:    return "Organic + TiO₂"
        case .unknown:        return "Unknown"
        }
    }

    /// Integer encoding for ML feature columns.
    var featureValue: Int {
        switch self {
        case .mineralZnO:     return 0
        case .mineralTiO2:    return 1
        case .mineralZnOTiO2: return 2
        case .organic:        return 3
        case .organicZnO:     return 4
        case .organicTiO2:    return 5
        case .unknown:        return 6
        }
    }

    /// Backward-compatible decoding: accepts legacy raw values from earlier versions.
    nonisolated init?(rawValue: String) {
        switch rawValue {
        case "mineralZnO":                    self = .mineralZnO
        case "mineralTiO2":                   self = .mineralTiO2
        case "mineralZnOTiO2":                self = .mineralZnOTiO2
        case "organic":                       self = .organic
        case "organicZnO":                    self = .organicZnO
        case "organicTiO2":                   self = .organicTiO2
        case "unknown":                       self = .unknown
        // Legacy values from previous schema versions
        case "mineral":                       self = .mineralZnOTiO2
        case "mineralOrganic", "combination": self = .organicZnO
        default: return nil
        }
    }
}

// MARK: - Training Result

/// Metadata persisted alongside the trained model for evaluation display and conformal intervals.
struct MLTrainingResult: Codable, Sendable {
    let trainedAt: Date
    let datasetCount: Int
    let spectrumCount: Int
    let r2: Double
    let rmse: Double
    let maxError: Double
    /// Sorted absolute residuals from the calibration split, used for conformal prediction intervals.
    let conformalResiduals: [Double]
    let featureColumns: [String]

    /// Returns the conformal quantile at the given level (e.g., 0.9 for 90% interval).
    func conformalQuantile(level: Double) -> Double? {
        guard !conformalResiduals.isEmpty else { return nil }
        let index = min(Int(ceil(level * Double(conformalResiduals.count))) - 1, conformalResiduals.count - 1)
        return conformalResiduals[max(index, 0)]
    }
}

// MARK: - Training Status

/// Observable training progress state.
enum MLTrainingStatus: Equatable, Sendable {
    case idle
    case preparingData
    case training(progress: Double)
    case evaluating
    case complete
    case failed(String)

    var label: String {
        switch self {
        case .idle:                    return "Idle"
        case .preparingData:           return "Preparing data…"
        case .training(let progress):  return String(format: "Training… %.0f%%", progress * 100)
        case .evaluating:              return "Evaluating…"
        case .complete:                return "Complete"
        case .failed(let msg):         return "Failed: \(msg)"
        }
    }

    var isInProgress: Bool {
        switch self {
        case .preparingData, .training, .evaluating: return true
        default: return false
        }
    }
}
