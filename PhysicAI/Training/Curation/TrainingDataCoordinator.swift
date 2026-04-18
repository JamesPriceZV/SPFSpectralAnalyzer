import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class TrainingDataCoordinator {

    // MARK: - Observable state

    var modalityStatus: [SpectralModality: ModalityStatus] = {
        var d: [SpectralModality: ModalityStatus] = [:]
        SpectralModality.allCases.forEach { d[$0] = .idle }
        return d
    }()

    var totalRecordCount: Int = 0
    var activeDownloads: Set<SpectralModality> = []
    var lastError: (SpectralModality, Error)? = nil

    let modelContainer: ModelContainer
    private let session = URLSession(configuration: .ephemeral)

    enum ModalityStatus: Equatable {
        case idle
        case downloading(progress: Double)
        case synthesizing(progress: Double)
        case training
        case ready(recordCount: Int)
        case error(String)
    }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    // MARK: - Start all

    func prepareAll() async {
        await withTaskGroup(of: Void.self) { group in
            for modality in SpectralModality.allCases {
                group.addTask { [weak self] in
                    await self?.prepare(modality: modality)
                }
            }
        }
    }

    // MARK: - Per-modality dispatch

    func prepare(modality: SpectralModality) async {
        guard modalityStatus[modality] == .idle else { return }
        activeDownloads.insert(modality)
        modalityStatus[modality] = .downloading(progress: 0)

        do {
            let records: [TrainingRecord]
            switch modality {
            case .circularDichroism:
                records = await prepareCD()
            case .thermogravimetric:
                records = await prepareTGA()
            case .terahertz:
                records = await prepareTHz()
            case .xrdPowder:
                records = await prepareXRD()
            case .fluorescence:
                records = await prepareFluorescence()
            case .gcRetention:
                records = await prepareGC()
            case .hplcRetention:
                records = await prepareHPLC()
            case .xps:
                records = await prepareXPS()

            // ── Quantum Layer (Phases 26–31) ────────────────────────
            case .dftQuantumChem:
                records = await prepareDFT()
            case .mossbauer:
                records = await prepareMossbauer()
            case .quantumDotPL:
                records = await prepareQuantumDot()
            case .augerElectron:
                records = await prepareAuger()
            case .neutronDiffraction:
                records = await prepareNeutronDiffraction()

            // ── Existing modalities with synthesizeBatch ─────────────
            case .nmrProton:
                records = await prepareNMRProton()
            case .nmrCarbon:
                records = await prepareNMRCarbon()
            case .raman:
                records = await prepareRaman()
            case .atomicEmission:
                records = await prepareAtomicEmission()
            case .libs:
                records = await prepareLIBS()
            case .hitranMolecular:
                records = await prepareHITRAN()

            default:
                records = []
            }

            modalityStatus[modality] = .synthesizing(progress: 0.5)
            try await persistRecords(records, modality: modality)
            totalRecordCount += records.count
            modalityStatus[modality] = .ready(recordCount: records.count)
        } catch {
            lastError = (modality, error)
            modalityStatus[modality] = .error(error.localizedDescription)
        }
        activeDownloads.remove(modality)
    }

    // MARK: - Synthesis dispatchers

    private func prepareCD() async -> [TrainingRecord] {
        let synth = CDSynthesizer()
        return await synth.synthesizeBatch(count: 3000)
    }

    private func prepareTGA() async -> [TrainingRecord] {
        let synth = TGASynthesizer()
        return await synth.synthesizeBatch(count: 3000)
    }

    private func prepareTHz() async -> [TrainingRecord] {
        let synth = THzSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareXRD() async -> [TrainingRecord] {
        let synth = XRDSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareFluorescence() async -> [TrainingRecord] {
        let synth = FluorescenceSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareGC() async -> [TrainingRecord] {
        let synth = ChromatographyRetentionSynthesizer()
        return await synth.synthesizeGCBatch(count: 2000)
    }

    private func prepareHPLC() async -> [TrainingRecord] {
        let synth = ChromatographyRetentionSynthesizer()
        return await synth.synthesizeHPLCBatch(count: 2000)
    }

    private func prepareXPS() async -> [TrainingRecord] {
        let synth = XPSSynthesizer()
        return await synth.synthesizeBatch(count: 1000)
    }

    // MARK: - Quantum Layer Synthesizers

    private func prepareDFT() async -> [TrainingRecord] {
        let synth = DFTQuantumChemSynthesizer()
        return await synth.synthesizeBatch(count: 5000)
    }

    private func prepareMossbauer() async -> [TrainingRecord] {
        let synth = MossbauerSynthesizer()
        return await synth.synthesizeBatch(count: 5000)
    }

    private func prepareQuantumDot() async -> [TrainingRecord] {
        let synth = QuantumDotSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareAuger() async -> [TrainingRecord] {
        let synth = AESSynthesizer()
        return await synth.synthesizeBatch(count: 3000)
    }

    private func prepareNeutronDiffraction() async -> [TrainingRecord] {
        let synth = NeutronDiffractionSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    // MARK: - Newly Dispatched Existing Synthesizers

    private func prepareNMRProton() async -> [TrainingRecord] {
        let synth = NMRSynthesizer()
        return await synth.synthesizeProton(count: 3000)
    }

    private func prepareNMRCarbon() async -> [TrainingRecord] {
        let synth = NMRSynthesizer()
        return await synth.synthesizeCarbon(count: 3000)
    }

    private func prepareRaman() async -> [TrainingRecord] {
        let synth = RamanSynthesizer()
        return await synth.synthesize(count: 2000)
    }

    private func prepareAtomicEmission() async -> [TrainingRecord] {
        let synth = AtomicEmissionSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareLIBS() async -> [TrainingRecord] {
        let synth = LIBSSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    private func prepareHITRAN() async -> [TrainingRecord] {
        let synth = HITRANSynthesizer()
        return await synth.synthesizeBatch(count: 2000)
    }

    // MARK: - Persistence

    private func persistRecords(_ records: [TrainingRecord], modality: SpectralModality) async throws {
        let context = ModelContext(modelContainer)
        for record in records {
            let stored = StoredTrainingRecord(from: record)
            context.insert(stored)
        }
        try context.save()
    }
}

// MARK: - Supporting species lists

enum AtmosphericSpeciesList {
    static let all: [String] = ["O3", "NO2", "SO2", "HCHO", "BrO", "OClO",
                                  "CHOCHO", "H2O2", "NO3", "N2O5", "HOBr", "IO"]
}

enum SAXSAccessionList {
    static let first500: [String] = (1...500).map { String(format: "SASDA%03d", $0) }
}

enum CDMSSpeciesList {
    static let all: [String] = ["28001", "28002", "32001", "44003", "18002",
                                  "17001", "34001", "64001", "48001", "46013"]
}
