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
            .appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
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
