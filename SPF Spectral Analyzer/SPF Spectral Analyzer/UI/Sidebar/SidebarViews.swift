import SwiftUI

extension ContentView {

    @ViewBuilder
    func spectrumRow(for index: Int) -> some View {
        let spectra = displayedSpectra
        if index < 0 || index >= spectra.count {
            EmptyView()
        } else {
            spectrumRowContent(for: index, spectrum: spectra[index])
        }
    }

    private func spectrumRowContent(for index: Int, spectrum: ShimadzuSpectrum) -> some View {
        let isSelected = analysis.selectedSpectrumIndices.contains(index)
        let hdrsTag = analysis.hdrsSpectrumTags[spectrum.id]
        return HStack(spacing: 6) {
            Button {
                toggleSelection(for: index)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(spectrum.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                    }
                    HStack(spacing: 4) {
                        tagRow(for: spectrum.name)
                        if let tag = hdrsTag {
                            Text(tag.plateType.badge)
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(tag.plateType == .moulded ? Color.purple.opacity(0.2) : Color.teal.opacity(0.2))
                                .foregroundColor(tag.plateType == .moulded ? .purple : .teal)
                                .cornerRadius(2)
                            Text(tag.irradiationState.badge)
                                .font(.system(size: 7, weight: .bold, design: .rounded))
                                .padding(.horizontal, 3)
                                .padding(.vertical, 1)
                                .background(tag.irradiationState == .preIrradiation ? Color.green.opacity(0.2) : Color.red.opacity(0.2))
                                .foregroundColor(tag.irradiationState == .preIrradiation ? .green : .red)
                                .cornerRadius(2)
                            Text("#\(tag.plateIndex)")
                                .font(.system(size: 7, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Menu {
                spectrumRowMenuContent(for: index)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("Actions")
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        .cornerRadius(8)
        .contextMenu {
            spectrumRowMenuContent(for: index)
        }
    }

    func invalidSpectrumRow(_ item: InvalidSpectrumItem) -> some View {
        let isSelected = analysis.selectedInvalidItemIDs.contains(item.id)
        return HStack(spacing: 8) {
            Button {
                analysis.toggleInvalidSelection(item)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.caption)
                        .lineLimit(1)
                    Text(item.fileName)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(item.reason)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(!analysis.includeInvalidInPlots)

            tagChip("Invalid")
        }
        .padding(8)
        .background(isSelected ? Color.orange.opacity(0.2) : Color.orange.opacity(0.1))
        .cornerRadius(8)
    }

    func toggleSelection(for index: Int) {
        if analysis.selectedSpectrumIndices.contains(index) {
            analysis.selectedSpectrumIndices.remove(index)
        } else {
            analysis.selectedSpectrumIndices.insert(index)
            analysis.selectedSpectrumIndex = index
        }
    }

    func removeSpectrum(at index: Int) {
        guard index >= 0, index < analysis.spectra.count else { return }

        analysis.spectra.remove(at: index)
        analysis.alignedSpectra = []
        analysis.processedSpectra = []
        analysis.pointCache = [:]

        // Keep the session-restore file in sync with the remaining spectra
        DatasetViewModel.syncSessionDatasetIDs(from: analysis.spectra)

        var updatedSelection: Set<Int> = []
        for selected in analysis.selectedSpectrumIndices {
            if selected == index { continue }
            updatedSelection.insert(selected > index ? selected - 1 : selected)
        }
        analysis.selectedSpectrumIndices = updatedSelection

        if analysis.spectra.isEmpty {
            analysis.selectedSpectrumIndex = 0
            analysis.selectedSpectrumIndices = []
            analysis.statusMessage = "No spectra loaded."
            analysis.warningMessage = nil
            analysis.warningDetails = []
            analysis.updatePeaks()
            rebuildAnalysisCaches()
            updateAIEstimate()
            return
        }

        analysis.selectedSpectrumIndex = min(max(analysis.selectedSpectrumIndex, 0), analysis.spectra.count - 1)
        analysis.statusMessage = "Loaded \(analysis.spectra.count) spectra."
        analysis.applyAlignmentIfNeeded()
        analysis.updatePeaks()
        updateAIEstimate()
    }

    func tagRow(for name: String) -> some View {
        let tags = analysis.spectrumTags(for: name)
        return HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                tagChip(tag)
            }
        }
    }

    func metricChip(title: String, value: String, status: MetricStatus? = nil) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption)
                    .lineLimit(1)
            }
            if let status {
                Image(systemName: status.iconName)
                    .font(.caption2)
                    .foregroundColor(status.color)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassSurface(cornerRadius: 12)
    }

    enum MetricStatus {
        case pass
        case warn
        case fail

        var iconName: String {
            switch self {
            case .pass: return "checkmark.circle.fill"
            case .warn: return "exclamationmark.triangle.fill"
            case .fail: return "xmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .pass: return .green
            case .warn: return .orange
            case .fail: return .red
            }
        }
    }

    func tagChip(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .glassSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private func spectrumRowMenuContent(for index: Int) -> some View {
        let spectra = displayedSpectra
        if index < 0 || index >= spectra.count {
            EmptyView()
        } else {
            spectrumRowMenuItems(for: index, spectrum: spectra[index])
        }
    }

    private func spectrumRowMenuItems(for index: Int, spectrum: ShimadzuSpectrum) -> some View {
        let hdrsTag = analysis.hdrsSpectrumTags[spectrum.id]
        return Group {
        if analysis.hdrsMode {
            Divider()
            Menu("HDRS Plate Type") {
                Button("Moulded") { analysis.setHDRSPlateType(.moulded, for: index) }
                Button("Sandblasted") { analysis.setHDRSPlateType(.sandblasted, for: index) }
            }
            Menu("HDRS Irradiation") {
                Button("Pre-Irradiation") { analysis.setHDRSIrradiationState(.preIrradiation, for: index) }
                Button("Post-Irradiation") { analysis.setHDRSIrradiationState(.postIrradiation, for: index) }
            }
            if hdrsTag != nil {
                Button("Clear HDRS Tag") {
                    analysis.hdrsSpectrumTags.removeValue(forKey: spectrum.id)
                }
            }
        }

        Divider()

        Button(role: .destructive) {
            removeSpectrum(at: index)
        } label: {
            Label("Remove", systemImage: "trash")
        }
        } // Group
    }

}
