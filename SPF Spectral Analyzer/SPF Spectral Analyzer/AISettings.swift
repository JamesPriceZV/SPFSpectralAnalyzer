import Foundation

enum AIPromptPreset: String, CaseIterable, Identifiable, Codable {
    case summary
    case compareSelected
    case spfReport
    case getPrototypeSpf

    var id: String { rawValue }

    var label: String {
        switch self {
        case .summary:
            return "Summary"
        case .compareSelected:
            return "Compare Selected"
        case .spfReport:
            return "SPF Report"
        case .getPrototypeSpf:
            return "Get Prototype SPF"
        }
    }

    var template: String {
        switch self {
        case .summary:
            return "Provide a concise analysis using the exact headings below. Each section should be 2–5 bullets.\n\nKey Insights:\n- ...\n\nRisks/Warnings:\n- ...\n\nNext Steps:\n- ...\n\nSummarize the selected spectra in plain language. Highlight key trends across 280–420 nm and any notable deviations."
        case .compareSelected:
            return "Provide a comparative analysis using the exact headings below. Each section should be 2–5 bullets.\n\nKey Insights:\n- ...\n\nRisks/Warnings:\n- ...\n\nNext Steps:\n- ...\n\nCompare the selected samples. Call out relative differences in UVA/UVB ratio, critical wavelength, and overall absorbance profile."
        case .spfReport:
            return "Provide an SPF-focused report using the exact headings below. Each section should be 2–5 bullets.\n\nKey Insights:\n- ...\n\nRisks/Warnings:\n- ...\n\nNext Steps:\n- ...\n\nDiscuss critical wavelength, UVA/UVB ratio, and what these imply about broad spectrum performance."
        case .getPrototypeSpf:
            return "Provide a response using the exact headings below. Each section should be 2–5 bullets.\n\nKey Insights:\n- ...\n\nRisks/Warnings:\n- ...\n\nNext Steps:\n- ...\n\nGive me an SPF estimate for the prototype samples as a correlary to the known (named commercial) samples. Include key insights, risks/warnings, and next steps."
        }
    }
}

enum AISelectionScope: String, CaseIterable, Identifiable, Codable {
    case selected
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .selected:
            return "Selected"
        case .all:
            return "All Loaded"
        }
    }
}

enum AIAuthMode: String, CaseIterable, Identifiable, Codable {
    case apiKey

    var id: String { rawValue }

    var label: String { "API Key" }
}

struct AIAnalysisResult: Codable {
    var text: String
    var createdAt: Date
    var preset: AIPromptPreset
    var selectionScope: AISelectionScope
}
