import SwiftUI

struct TrainingDataDashboardView: View {
    @Environment(TrainingDataCoordinator.self) private var coordinator

    private let columns = [
        GridItem(.adaptive(minimum: 280, maximum: 380), spacing: 16)
    ]

    private var classicalModalities: [SpectralModality] {
        SpectralModality.allCases.filter { !quantumModalities.contains($0) }
    }

    private var quantumModalities: [SpectralModality] {
        [.dftQuantumChem, .mossbauer, .quantumDotPL, .augerElectron, .neutronDiffraction]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    Section {
                        ForEach(classicalModalities) { modality in
                            ModalityTrainingCardView(
                                modality: modality,
                                status: coordinator.modalityStatus[modality] ?? .idle
                            )
                        }
                    } header: {
                        sectionHeader(title: "Spectral Modalities",
                                      icon: "waveform.path.ecg",
                                      subtitle: "25 PINNs — 8 enhanced with quantum depth",
                                      color: .blue)
                    }

                    Section {
                        ForEach(quantumModalities) { modality in
                            ModalityTrainingCardView(
                                modality: modality,
                                status: coordinator.modalityStatus[modality] ?? .idle
                            )
                        }
                    } header: {
                        sectionHeader(title: "Quantum Mechanics Layer",
                                      icon: "atom",
                                      subtitle: "5 PINNs grounded in wavefunctions, nuclear physics, and quantum optics",
                                      color: .purple)
                    }
                }
                .padding()
            }
            .navigationTitle("Training Data — \(coordinator.totalRecordCount) records")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Prepare All") {
                        Task { await coordinator.prepareAll() }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func sectionHeader(title: String, icon: String,
                               subtitle: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(color)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 8)
    }
}

struct ModalityTrainingCardView: View {
    let modality: SpectralModality
    let status: TrainingDataCoordinator.ModalityStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: modality.systemImage)
                    .font(.title2)
                    .foregroundStyle(statusColor)
                Spacer()
                statusBadge
            }

            Text(modality.displayName)
                .font(.headline)

            Text(modality.pinnPhysicsLaw)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack {
                Text(modality.primaryDataSource)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                Spacer()
                if case .ready(let count) = status {
                    Text("\(count) records")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.green)
                }
            }

            if case .downloading(let p) = status {
                ProgressView(value: p)
            } else if case .synthesizing(let p) = status {
                ProgressView(value: p)
                    .tint(.orange)
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch status {
        case .idle:
            Text("Idle").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.gray.opacity(0.2), in: Capsule())
        case .downloading:
            Text("Downloading").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.blue.opacity(0.2), in: Capsule())
        case .synthesizing:
            Text("Synthesizing").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.orange.opacity(0.2), in: Capsule())
        case .training:
            Text("Training").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.purple.opacity(0.2), in: Capsule())
        case .ready(let count):
            Text("\(count)").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.green.opacity(0.2), in: Capsule())
        case .error:
            Text("Error").font(.caption2).padding(.horizontal, 8).padding(.vertical, 3)
                .background(.red.opacity(0.2), in: Capsule())
        }
    }

    private var statusColor: Color {
        switch status {
        case .idle: .gray
        case .downloading: .blue
        case .synthesizing: .orange
        case .training: .purple
        case .ready: .green
        case .error: .red
        }
    }
}
