import Foundation
import CoreML
import Observation

// MARK: - PINN Domain Model Protocol

/// Protocol for domain-specific PINN model implementations.
/// Each domain (UV-Vis, FTIR, Raman, etc.) provides a concrete type
/// that handles model loading, preprocessing, and prediction.
protocol PINNDomainModel: Sendable {
    var domain: PINNDomain { get }
    var status: PINNModelStatus { get }
    var modelDescription: String { get }
    var physicsConstraints: [String] { get }

    /// Load the CoreML model from disk (App Support → iCloud → Bundle).
    func loadModel() async throws

    /// Run prediction on spectral data.
    func predict(
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata
    ) -> PINNPredictionResult?
}

// MARK: - PINN Model Registry

/// Central registry of all domain-specific PINN CoreML models.
/// Manages model loading, status tracking, and experiment-type routing.
///
/// Model loading follows the same pattern as `SPFPredictionService`:
/// 1. App Support directory (user-trained model)
/// 2. iCloud ubiquity container (synced from macOS)
/// 3. Bundle fallback (pre-bundled default model)
@MainActor @Observable
final class PINNModelRegistry {

    // MARK: - State

    /// Registered domain models, keyed by domain.
    private(set) var models: [PINNDomain: any PINNDomainModel] = [:]

    /// Overall loading state.
    private(set) var isLoading = false

    /// Incremented after each `loadAllModels()` to force SwiftUI re-renders.
    /// Domain model status changes are invisible to observation (they're
    /// reference types, not @Observable), so the sidebar must read this
    /// counter to detect when model readiness has changed.
    private(set) var loadVersion = 0

    /// Domains that have ready models.
    var availableDomains: [PINNDomain] {
        models.values.filter { $0.status.isReady }.map(\.domain).sorted { $0.rawValue < $1.rawValue }
    }

    /// Total number of domain models that are ready.
    var readyModelCount: Int {
        models.values.filter { $0.status.isReady }.count
    }

    // MARK: - Model Directory

    /// Base directory for PINN models in Application Support.
    static var modelDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport
            .appendingPathComponent("com.zincoverde.SPFSpectralAnalyzer", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("PINN", isDirectory: true)
    }

    /// iCloud directory for PINN models.
    static var iCloudModelDirectory: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.zincoverde.SPFSpectralAnalyzer")?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
            .appendingPathComponent("PINN", isDirectory: true)
    }

    // MARK: - Registration & Loading

    /// Register a domain model implementation.
    func register(_ model: any PINNDomainModel) {
        models[model.domain] = model
    }

    /// Register all built-in domain model implementations.
    /// Call this before `loadAllModels()` to populate the registry.
    func registerAllDomainModels() {
        register(UVVisPINNModel())
        register(FTIRPINNModel())
        register(RamanPINNModel())
        register(MassSpecPINNModel())
        register(NMRPINNModel())
        register(FluorescencePINNModel())
        register(XRDPINNModel())
        register(ChromatographyPINNModel())
        register(NIRPINNModel())
        register(AtomicEmissionPINNModel())
    }

    /// Load all registered domain models.
    func loadAllModels() async {
        isLoading = true

        await withTaskGroup(of: Void.self) { group in
            for (domain, model) in models {
                let domainName = domain.displayName
                group.addTask {
                    do {
                        try await model.loadModel()
                        await MainActor.run {
                            Instrumentation.log(
                                "PINN model loaded: \(domainName)",
                                area: .mlTraining, level: .info
                            )
                        }
                    } catch {
                        await MainActor.run {
                            Instrumentation.log(
                                "PINN model failed to load: \(domainName)",
                                area: .mlTraining, level: .warning,
                                details: error.localizedDescription
                            )
                        }
                    }
                }
            }
        }

        isLoading = false
        loadVersion += 1
    }

    // MARK: - Lookup

    /// Get the PINN model for a specific SPC experiment type code.
    func model(for experimentTypeCode: UInt8) -> (any PINNDomainModel)? {
        guard let domain = PINNDomainMapping.domain(for: experimentTypeCode) else { return nil }
        return models[domain]
    }

    /// Get the PINN model for a specific domain.
    func model(for domain: PINNDomain) -> (any PINNDomainModel)? {
        models[domain]
    }

    /// Check if a PINN model is available and ready for a specific experiment type.
    func isModelReady(for experimentTypeCode: UInt8) -> Bool {
        guard let model = model(for: experimentTypeCode) else { return false }
        return model.status.isReady
    }

    // MARK: - Prediction

    /// Run PINN prediction for spectral data, auto-routing to the correct domain model.
    func predict(
        experimentTypeCode: UInt8,
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata
    ) -> PINNPredictionResult? {
        guard let domainModel = model(for: experimentTypeCode),
              domainModel.status.isReady else {
            return nil
        }
        return domainModel.predict(
            wavelengths: wavelengths,
            intensities: intensities,
            metadata: metadata
        )
    }
}
