import Foundation

#if canImport(FoundationModels)
import FoundationModels

// MARK: - Spectral Metrics Tool

/// A FoundationModels `Tool` that lets the on-device model request spectral
/// metric calculations for specific spectra. The model can call this tool
/// to get precise numerical values like critical wavelength, UVA/UVB ratio,
/// and transmittance statistics.
struct SpectralMetricsTool: Tool {
    let name = "calculateSpectralMetrics"
    let description = "Calculate spectral metrics (critical wavelength, UVA/UVB ratio, mean transmittance) for a named spectrum."

    @Generable
    struct Arguments {
        @Guide(description: "The name of the spectrum to calculate metrics for")
        var spectrumName: String
    }

    /// The spectra available for metric calculation, injected at creation time.
    let availableSpectra: [AISpectrumPayload]

    func call(arguments: Arguments) async throws -> String {
        // Find the requested spectrum by name (case-insensitive)
        guard let spectrum = availableSpectra.first(where: {
            $0.name.localizedCaseInsensitiveCompare(arguments.spectrumName) == .orderedSame
        }) else {
            let available = availableSpectra.map { $0.name }.joined(separator: ", ")
            return "Spectrum '\(arguments.spectrumName)' not found. Available spectra: \(available)"
        }

        if let metrics = spectrum.metrics {
            return """
            Metrics for '\(spectrum.name)':
            - Critical wavelength: \(String(format: "%.1f", metrics.criticalWavelength)) nm
            - UVA/UVB ratio: \(String(format: "%.3f", metrics.uvaUvbRatio))
            - Mean UVB transmittance: \(String(format: "%.4f", metrics.meanUVB))
            - Data points: \(spectrum.points.count)
            """
        } else {
            return """
            Spectrum '\(spectrum.name)':
            - Data points: \(spectrum.points.count)
            - Metrics: not calculated (insufficient wavelength range)
            """
        }
    }
}

#endif
