import Foundation
import Observation

// MARK: - PINN Prediction Service

/// Unified prediction service that wraps both the existing `SPFPredictionService`
/// (MLBoostedTreeRegressor for UV-Vis SPF) and new PINN domain models.
///
/// For UV-Vis with SPF target, delegates to the existing `SPFPredictionService`
/// or the new UV-Vis PINN model based on user preference.
/// For all other domains, uses the domain-specific PINN model from the registry.
@MainActor @Observable
final class PINNPredictionService {

    /// Shared singleton instance.
    static let shared = PINNPredictionService()

    /// The central registry of all PINN domain models.
    let registry = PINNModelRegistry()

    /// Whether PINN models are currently being loaded.
    var isLoading: Bool { registry.isLoading }

    /// Number of ready PINN models.
    var readyModelCount: Int { registry.readyModelCount }

    /// All domains that have ready models.
    var availableDomains: [PINNDomain] { registry.availableDomains }

    // MARK: - Initialization

    private init() {}

    /// Register and load all PINN domain models. Call at app startup.
    func loadModels() async {
        registry.registerAllDomainModels()
        await registry.loadAllModels()
    }

    // MARK: - Prediction

    /// Run PINN prediction for spectral data.
    /// Automatically routes to the correct domain model based on experiment type.
    func predict(
        experimentTypeCode: UInt8,
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata = PINNInputMetadata(
            experimentTypeCode: nil,
            instrumentID: nil,
            plateType: nil,
            applicationQuantityMg: nil,
            formulationType: nil,
            isPostIrradiation: false
        )
    ) -> PINNPredictionResult? {
        registry.predict(
            experimentTypeCode: experimentTypeCode,
            wavelengths: wavelengths,
            intensities: intensities,
            metadata: metadata
        )
    }

    /// Check if a PINN model is available for a specific experiment type.
    func isAvailable(for experimentTypeCode: UInt8) -> Bool {
        registry.isModelReady(for: experimentTypeCode)
    }

    /// Get the domain for a specific experiment type code.
    func domain(for experimentTypeCode: UInt8) -> PINNDomain? {
        PINNDomainMapping.domain(for: experimentTypeCode)
    }

    // MARK: - Batch Prediction

    /// Run predictions for multiple PINN domains on the same spectral data.
    /// Returns a dictionary of results keyed by domain. Domains without ready
    /// models or that fail prediction are omitted from the result.
    func predictionsForDomains(
        _ domains: Set<PINNDomain>,
        wavelengths: [Double],
        intensities: [Double],
        metadata: PINNInputMetadata = PINNInputMetadata(
            experimentTypeCode: nil,
            instrumentID: nil,
            plateType: nil,
            applicationQuantityMg: nil,
            formulationType: nil,
            isPostIrradiation: false
        )
    ) -> [PINNDomain: PINNPredictionResult] {
        var results: [PINNDomain: PINNPredictionResult] = [:]
        for domain in domains {
            // Use the first SPC experiment type code for this domain
            guard let typeCode = domain.spcExperimentTypeCodes.first else { continue }
            if let result = predict(
                experimentTypeCode: typeCode,
                wavelengths: wavelengths,
                intensities: intensities,
                metadata: metadata
            ) {
                results[domain] = result
            }
        }
        return results
    }

    // MARK: - Status Summary

    /// Summary text for display in settings/diagnostics.
    var statusSummary: String {
        let total = PINNDomain.allCases.count
        let ready = readyModelCount
        if ready == 0 {
            return "No PINN models loaded"
        }
        return "\(ready)/\(total) PINN models ready"
    }

    /// Detailed status for each domain.
    var domainStatuses: [(domain: PINNDomain, status: PINNModelStatus)] {
        PINNDomain.allCases.map { domain in
            let status = registry.model(for: domain)?.status ?? .notTrained
            return (domain: domain, status: status)
        }
    }
}
