import Foundation

// MARK: - ISO 23675:2024 HDRS Domain Types

/// The type of PMMA plate used in ISO 23675 measurements.
enum HDRSPlateType: String, CaseIterable, Codable, Sendable, Identifiable {
    case moulded
    case sandblasted

    var id: String { rawValue }

    var label: String {
        switch self {
        case .moulded:     return "Moulded"
        case .sandblasted: return "Sandblasted"
        }
    }

    /// Short badge label for sidebar display.
    var badge: String {
        switch self {
        case .moulded:     return "M"
        case .sandblasted: return "S"
        }
    }
}

/// Whether a measurement is before or after UV irradiation.
enum HDRSIrradiationState: String, CaseIterable, Codable, Sendable, Identifiable {
    case preIrradiation
    case postIrradiation

    var id: String { rawValue }

    var label: String {
        switch self {
        case .preIrradiation:  return "Pre-Irradiation"
        case .postIrradiation: return "Post-Irradiation"
        }
    }

    /// Short badge label for sidebar display.
    var badge: String {
        switch self {
        case .preIrradiation:  return "PRE"
        case .postIrradiation: return "POST"
        }
    }
}

/// The product formulation type, which determines correction coefficients per ISO 23675 Table 1.
enum HDRSProductType: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Emulsion/cream: C_Moulded = 0.225, C_Sandblasted = 0.800
    case emulsion
    /// Alcoholic/spray: C_Moulded = 0.000, C_Sandblasted = 0.800
    case alcoholic

    var id: String { rawValue }

    var label: String {
        switch self {
        case .emulsion:  return "Emulsion"
        case .alcoholic: return "Alcoholic"
        }
    }

    var cMoulded: Double {
        switch self {
        case .emulsion:  return 0.225
        case .alcoholic: return 0.000
        }
    }

    var cSandblasted: Double { 0.800 }
}

// MARK: - Spectrum Classification

/// Complete classification of a single spectrum for the HDRS workflow.
struct HDRSSpectrumTag: Codable, Sendable, Equatable {
    var plateType: HDRSPlateType
    var irradiationState: HDRSIrradiationState
    var plateIndex: Int       // 1-based plate number (1, 2, 3, ...)
    var sampleName: String    // e.g., "CeraVe SPF 30"
}

// MARK: - Calculation Intermediates

/// A paired plate measurement: one moulded + one sandblasted with matching plate index.
/// Absorbance arrays are 111 elements (290–400 nm at 1 nm), each value capped at 2.2.
struct HDRSPlatePair: Sendable {
    let plateIndex: Int
    let mouldedAbsorbance: [Double]
    let sandblastAbsorbance: [Double]
}

/// Intermediate result for one plate pair.
struct HDRSPairResult: Sendable {
    let plateIndex: Int
    let combinedAbsorbance: [Double]  // A_initial per Formula 3
    let spfPre: Double
    let irradiationDose: Double       // Dx per Formula 5
    let spfPost: Double?
    let spfFinal: Double              // After Formula 7/8 correction
}

/// Full HDRS result for one sample (product under test).
struct HDRSResult: Sendable {
    let sampleName: String
    let productType: HDRSProductType
    let pairResults: [HDRSPairResult]
    let meanSPF: Double
    let standardDeviation: Double
    let confidenceInterval95Percent: Double  // As percentage of mean
    let isValid: Bool                        // CI ≤ 17% and ≥ 3 pairs
    let warnings: [String]
}

// MARK: - Persistence Metadata

/// HDRS classification metadata stored alongside the existing SPC metadata
/// in StoredDataset.metadataJSON.
struct DatasetHDRSMetadata: Codable, Sendable {
    var plateType: HDRSPlateType?
    var irradiationState: HDRSIrradiationState?
    var plateIndex: Int?
    var sampleName: String?
    var productType: HDRSProductType?
}
