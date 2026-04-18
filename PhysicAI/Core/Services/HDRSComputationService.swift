import Foundation

/// Stateless HDRS (ISO 23675) computation and tag assignment helpers.
enum HDRSComputationService {

    static func parseSampleName(from name: String) -> String {
        var working = name
        for ext in [".spc", ".SPC", ".csv", ".CSV"] {
            if working.hasSuffix(ext) {
                working = String(working.dropLast(ext.count))
            }
        }
        if let range = working.range(of: #"^File_\d{6}_\d{6}\.?\s*"#, options: .regularExpression) {
            working = String(working[range.upperBound...])
        }
        if let range = working.range(of: #"\s*spc\s*$"#, options: [.regularExpression, .caseInsensitive]) {
            working = String(working[working.startIndex..<range.lowerBound])
        }
        if let range = working.range(of: "after incubation", options: .caseInsensitive) {
            working = String(working[working.startIndex..<range.lowerBound]) +
                      String(working[range.upperBound...])
        }
        if let range = working.range(of: #"\d+\.?\d*\s*mg"#, options: [.regularExpression, .caseInsensitive]) {
            working = String(working[working.startIndex..<range.lowerBound]) +
                      String(working[range.upperBound...])
        }
        for sub in ["tio2", "zno2", "zno", "combo"] {
            working = working.replacingOccurrences(of: sub, with: "", options: .caseInsensitive)
        }
        working = working.components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return working.isEmpty ? name : working
    }

    static func computeResults(
        displayedSpectra: [ShimadzuSpectrum],
        hdrsSpectrumTags: [UUID: HDRSSpectrumTag],
        yAxisMode: SpectralYAxisMode,
        hdrsProductType: HDRSProductType
    ) -> [String: HDRSResult] {
        var bySample: [String: [(index: Int, spectrum: ShimadzuSpectrum, tag: HDRSSpectrumTag)]] = [:]
        for (i, spectrum) in displayedSpectra.enumerated() {
            guard let tag = hdrsSpectrumTags[spectrum.id] else { continue }
            bySample[tag.sampleName, default: []].append((i, spectrum, tag))
        }

        var results: [String: HDRSResult] = [:]

        for (sampleName, group) in bySample {
            let preMoulded = group
                .filter { $0.tag.irradiationState == .preIrradiation && $0.tag.plateType == .moulded }
                .sorted { $0.tag.plateIndex < $1.tag.plateIndex }
            let preSandblasted = group
                .filter { $0.tag.irradiationState == .preIrradiation && $0.tag.plateType == .sandblasted }
                .sorted { $0.tag.plateIndex < $1.tag.plateIndex }
            let postMoulded = group
                .filter { $0.tag.irradiationState == .postIrradiation && $0.tag.plateType == .moulded }
                .sorted { $0.tag.plateIndex < $1.tag.plateIndex }
            let postSandblasted = group
                .filter { $0.tag.irradiationState == .postIrradiation && $0.tag.plateType == .sandblasted }
                .sorted { $0.tag.plateIndex < $1.tag.plateIndex }

            let prePairCount = min(preMoulded.count, preSandblasted.count)
            var prePairs: [HDRSPlatePair] = []
            for i in 0..<prePairCount {
                guard let mAbs = HDRSCalculator.resampleTo1nm(x: preMoulded[i].spectrum.x, y: preMoulded[i].spectrum.y, yAxisMode: yAxisMode),
                      let sAbs = HDRSCalculator.resampleTo1nm(x: preSandblasted[i].spectrum.x, y: preSandblasted[i].spectrum.y, yAxisMode: yAxisMode)
                else { continue }
                prePairs.append(HDRSPlatePair(plateIndex: i + 1, mouldedAbsorbance: mAbs, sandblastAbsorbance: sAbs))
            }

            let postPairCount = min(postMoulded.count, postSandblasted.count)
            var postPairs: [HDRSPlatePair]? = nil
            if postPairCount > 0 {
                var pairs: [HDRSPlatePair] = []
                for i in 0..<postPairCount {
                    guard let mAbs = HDRSCalculator.resampleTo1nm(x: postMoulded[i].spectrum.x, y: postMoulded[i].spectrum.y, yAxisMode: yAxisMode),
                          let sAbs = HDRSCalculator.resampleTo1nm(x: postSandblasted[i].spectrum.x, y: postSandblasted[i].spectrum.y, yAxisMode: yAxisMode)
                    else { continue }
                    pairs.append(HDRSPlatePair(plateIndex: i + 1, mouldedAbsorbance: mAbs, sandblastAbsorbance: sAbs))
                }
                postPairs = pairs.isEmpty ? nil : pairs
            }

            guard !prePairs.isEmpty else { continue }

            if var result = HDRSCalculator.calculate(pairs: prePairs, postIrradiationPairs: postPairs, productType: hdrsProductType) {
                result = HDRSResult(
                    sampleName: sampleName,
                    productType: result.productType,
                    pairResults: result.pairResults,
                    meanSPF: result.meanSPF,
                    standardDeviation: result.standardDeviation,
                    confidenceInterval95Percent: result.confidenceInterval95Percent,
                    isValid: result.isValid,
                    warnings: result.warnings
                )
                results[sampleName] = result
            }
        }

        return results
    }

    static func autoAssignTags(
        displayedSpectra: [ShimadzuSpectrum],
        datasetIrradiationOverrides: [UUID: Bool] = [:]
    ) -> [UUID: HDRSSpectrumTag] {
        var tags: [UUID: HDRSSpectrumTag] = [:]
        var groups: [String: [(index: Int, spectrum: ShimadzuSpectrum, isPost: Bool)]] = [:]

        for (i, spectrum) in displayedSpectra.enumerated() {
            let sampleName = parseSampleName(from: spectrum.name)
            // Use dataset-level override when available; fall back to filename detection.
            let isPost: Bool
            if let datasetID = spectrum.sourceDatasetID,
               let override = datasetIrradiationOverrides[datasetID] {
                isPost = override
            } else {
                isPost = spectrum.name.lowercased().contains("after incubation")
            }
            groups[sampleName, default: []].append((i, spectrum, isPost))
        }

        for (sampleName, members) in groups {
            let preMembers = members.filter { !$0.isPost }
            let postMembers = members.filter { $0.isPost }

            assignPlateTypes(members: preMembers, sampleName: sampleName, state: .preIrradiation, tags: &tags)
            assignPlateTypes(members: postMembers, sampleName: sampleName, state: .postIrradiation, tags: &tags)
        }

        return tags
    }

    static func assignPlateTypes(
        members: [(index: Int, spectrum: ShimadzuSpectrum, isPost: Bool)],
        sampleName: String,
        state: HDRSIrradiationState,
        tags: inout [UUID: HDRSSpectrumTag]
    ) {
        var moulded: [(index: Int, spectrum: ShimadzuSpectrum)] = []
        var sandblasted: [(index: Int, spectrum: ShimadzuSpectrum)] = []
        var unknown: [(index: Int, spectrum: ShimadzuSpectrum)] = []

        for member in members {
            let lower = member.spectrum.name.lowercased()
            if lower.contains("moulded") || lower.contains("molded") {
                moulded.append((member.index, member.spectrum))
            } else if lower.contains("sandblast") {
                sandblasted.append((member.index, member.spectrum))
            } else {
                unknown.append((member.index, member.spectrum))
            }
        }

        if moulded.isEmpty && sandblasted.isEmpty && !unknown.isEmpty {
            let half = unknown.count / 2
            moulded = Array(unknown.prefix(half))
            sandblasted = Array(unknown.suffix(from: half))
        } else {
            for item in unknown {
                if moulded.count <= sandblasted.count {
                    moulded.append(item)
                } else {
                    sandblasted.append(item)
                }
            }
        }

        for (plateIdx, item) in moulded.enumerated() {
            tags[item.spectrum.id] = HDRSSpectrumTag(
                plateType: .moulded,
                irradiationState: state,
                plateIndex: plateIdx + 1,
                sampleName: sampleName
            )
        }
        for (plateIdx, item) in sandblasted.enumerated() {
            tags[item.spectrum.id] = HDRSSpectrumTag(
                plateType: .sandblasted,
                irradiationState: state,
                plateIndex: plateIdx + 1,
                sampleName: sampleName
            )
        }
    }
}
