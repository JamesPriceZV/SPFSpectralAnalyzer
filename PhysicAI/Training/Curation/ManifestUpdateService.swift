import Foundation
import CryptoKit

actor ManifestUpdateService {

    private let manifestURL = URL(string: "https://raw.githubusercontent.com/zincoverde/spectral-pinn-manifest/main/manifest.json")!
    private let session = URLSession.shared

    func fetchManifest() async throws -> TrainingDataManifest {
        let (data, _) = try await session.data(from: manifestURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(TrainingDataManifest.self, from: data)
    }

    func downloadPackage(_ pkg: TrainingDataManifest.ModalityPackage) async throws -> URL {
        guard let url = URL(string: pkg.downloadURL) else {
            throw ManifestError.invalidURL(pkg.downloadURL)
        }
        let (tempURL, _) = try await session.download(from: url)

        // Verify SHA-256
        let data = try Data(contentsOf: tempURL)
        let digest = SHA256.hash(data: data)
        let hexHash = digest.map { String(format: "%02x", $0) }.joined()
        guard hexHash == pkg.sha256 else {
            throw ManifestError.sha256Mismatch(expected: pkg.sha256, actual: hexHash)
        }

        // Move to Application Support
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dest = appSupport
            .appendingPathComponent("com.zincoverde.PhysicAI", isDirectory: true)
            .appendingPathComponent("TrainingData", isDirectory: true)
            .appendingPathComponent(pkg.id, isDirectory: true)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        let finalURL = dest.appendingPathComponent(URL(string: pkg.downloadURL)!.lastPathComponent)
        if FileManager.default.fileExists(atPath: finalURL.path) {
            try FileManager.default.removeItem(at: finalURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: finalURL)
        return finalURL
    }

    // MARK: - Quantum Layer Manifest Metadata (Phases 26–39)

    /// Version string for the quantum-enhanced manifest.
    static let quantumManifestVersion = "3.0.0-quantum"

    /// New modalities added in Phases 26–31.
    static let quantumAdditions: [(rawValue: String, physicsLaw: String, dataSource: String, estimatedRecords: Int)] = [
        ("dft_qm",              "Kohn-Sham DFT HOMO-LUMO",    "QM9/PubChemQC",     134_000),
        ("mossbauer",           "Lamb-Mössbauer; Hyperfine",   "Zenodo/ISEDB",        5_000),
        ("qd_pl",               "Brus QD Confinement",         "Zenodo QD libs",      2_000),
        ("aes",                 "Auger KE; Wagner α′",         "NIST SRD 29",        15_000),
        ("neutron_diffraction", "Neutron b_coh scattering",    "ILL/Zenodo",         10_000),
    ]

    /// Existing modalities enhanced with quantum features in Phases 32–39.
    static let quantumEnhancements: [(rawValue: String, enhancement: String)] = [
        ("nmr_1h",           "Phase 32: Zeeman H, CSA, T1/T2, NOE"),
        ("nmr_13c",          "Phase 33: CSA tensor, T1 13C, NOE, DEPT, J_CC"),
        ("raman",            "Phase 34: Resonance enhancement, Anharmonic Morse, CARS, Depolarisation"),
        ("xps",              "Phase 35: SOC doublets, Shake-up satellites, Wagner α′"),
        ("fluorescence",     "Phase 36: Marcus ET, El-Sayed ISC, Franck-Condon, FRET"),
        ("xrd_powder",       "Phase 37: Cromer-Mann f(q), Debye-Waller, Wilson plot, LP correction"),
        ("hitran",           "Phase 38: Dicke narrowing, SD-Voigt, Line mixing"),
        ("atomic_emission",  "Phase 39: Fine structure doublets, Stark broadening, Saha"),
    ]

    enum ManifestError: Error, LocalizedError {
        case invalidURL(String)
        case sha256Mismatch(expected: String, actual: String)

        var errorDescription: String? {
            switch self {
            case .invalidURL(let url): return "Invalid package URL: \(url)"
            case .sha256Mismatch(let e, let a): return "SHA-256 mismatch: expected \(e), got \(a)"
            }
        }
    }
}
