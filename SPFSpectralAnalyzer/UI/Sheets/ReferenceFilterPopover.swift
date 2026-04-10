import SwiftUI

extension ContentView {

    var referenceFilterPopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Reference Datasets")
                    .font(.headline)
                Spacer()
                let summary = datasets.referenceDatasetSummary
                Text("\(summary.included)/\(summary.total) included")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            let records = datasets.allReferenceDatasetRecords
            if records.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "star.slash")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("No reference datasets available.")
                        .font(.callout)
                        .foregroundColor(.secondary)
                    Text("Tag datasets as Reference in Data Management.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(records, id: \.id) { entry in
                            referenceFilterRow(id: entry.id, record: entry.record, effectiveSPF: entry.effectiveSPF)
                        }
                    }
                }
                .frame(minHeight: 120, maxHeight: 300)

                HStack(spacing: 12) {
                    Button("Include All") {
                        datasets.excludedReferenceDatasetIDs.removeAll()
                        excludedReferenceIDs = []
                        rebuildAnalysisCaches()
                    }
                    .buttonStyle(.glass)

                    Button("Exclude All") {
                        let allIDs = Set(records.map { $0.id })
                        datasets.excludedReferenceDatasetIDs = allIDs
                        excludedReferenceIDs = allIDs
                        rebuildAnalysisCaches()
                    }
                    .buttonStyle(.glass)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 380, idealWidth: 420)
    }

    func referenceFilterRow(id: UUID, record: DatasetSearchRecord, effectiveSPF: Double?) -> some View {
        let isIncluded = !datasets.excludedReferenceDatasetIDs.contains(id)
        let isInferred = record.knownInVivoSPF == nil && effectiveSPF != nil
        return Button {
            if isIncluded {
                datasets.excludedReferenceDatasetIDs.insert(id)
            } else {
                datasets.excludedReferenceDatasetIDs.remove(id)
            }
            excludedReferenceIDs = datasets.excludedReferenceDatasetIDs
            rebuildAnalysisCaches()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isIncluded ? .accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(record.fileName)
                            .font(.caption)
                            .lineLimit(1)
                        if let spf = effectiveSPF {
                            Text("SPF \(Int(spf))")
                                .font(.caption2.bold())
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(isInferred ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                                .foregroundColor(isInferred ? .orange : .blue)
                                .cornerRadius(3)
                            if isInferred {
                                Text("inferred")
                                    .font(.caption2)
                                    .foregroundColor(.orange.opacity(0.7))
                            }
                        } else {
                            Text("No SPF")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(spacing: 6) {
                        Text("\(record.validSpectrumCount) spectra")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        if let instrument = record.sourceInstrumentText, !instrument.isEmpty {
                            Text(instrument)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer()
            }
            .padding(6)
            .background(isIncluded ? Color.accentColor.opacity(0.08) : Color.clear)
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
    }
}
