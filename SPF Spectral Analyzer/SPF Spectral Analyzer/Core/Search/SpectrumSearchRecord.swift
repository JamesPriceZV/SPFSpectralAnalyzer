import Foundation

/// Lightweight search record for sidebar spectrum filtering.
///
/// Built on-the-fly from in-memory `ShimadzuSpectrum` + auto-generated tags + HDRS tags.
/// No SwiftData model access needed since sidebar operates on in-memory arrays.
struct SpectrumSearchRecord: SearchableRecord {
    let name: String
    let tags: [String]                  // Auto-generated tags from spectrumTags(for:)
    let hdrsPlateType: String?          // "moulded" or "sandblasted"
    let hdrsIrradiationState: String?   // "preIrradiation" or "postIrradiation"
    let hdrsSampleName: String?

    /// Pre-computed lowercased concatenation for unqualified search.
    let allText: String

    init(
        name: String,
        tags: [String],
        hdrsPlateType: String? = nil,
        hdrsIrradiationState: String? = nil,
        hdrsSampleName: String? = nil
    ) {
        self.name = name
        self.tags = tags
        self.hdrsPlateType = hdrsPlateType
        self.hdrsIrradiationState = hdrsIrradiationState
        self.hdrsSampleName = hdrsSampleName

        var parts: [String] = [name.lowercased()]
        parts.append(contentsOf: tags.map { $0.lowercased() })
        if let plate = hdrsPlateType { parts.append(plate.lowercased()) }
        if let irr = hdrsIrradiationState { parts.append(irr.lowercased()) }
        if let sample = hdrsSampleName { parts.append(sample.lowercased()) }
        self.allText = parts.joined(separator: "\n")
    }

    // MARK: - SearchableRecord

    func values(for field: SearchField) -> [String]? {
        switch field {
        case .name, .file:
            return [name]
        case .tag:
            var all = tags
            if let plate = hdrsPlateType { all.append(plate) }
            if let irr = hdrsIrradiationState { all.append(irr) }
            return all.isEmpty ? nil : all
        case .plate:
            if let plate = hdrsPlateType { return [plate] }
            return nil
        case .irr:
            if let irr = hdrsIrradiationState { return [irr] }
            return nil
        case .sample:
            if let sample = hdrsSampleName { return [sample] }
            return nil
        // Dataset-only fields: not applicable to spectra
        case .role, .spf, .date, .spectra, .memo, .instrument, .hash, .path:
            return nil
        }
    }

    func numericValue(for field: SearchField) -> Double? {
        nil // No numeric fields on spectra
    }

    func dateValue(for field: SearchField) -> Date? {
        nil // No date fields on spectra
    }
}
