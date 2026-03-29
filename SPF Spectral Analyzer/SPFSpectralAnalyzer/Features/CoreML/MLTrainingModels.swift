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
    case mineral      // ZnO, TiO2 only
    case organic      // Chemical/organic UV filters only
    case combination  // Mineral + Organic
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mineral:     return "Mineral"
        case .organic:     return "Organic"
        case .combination: return "Combination"
        case .unknown:     return "Unknown"
        }
    }

    /// Integer encoding for ML feature columns.
    var featureValue: Int {
        switch self {
        case .mineral:     return 0
        case .organic:     return 1
        case .combination: return 2
        case .unknown:     return 3
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
