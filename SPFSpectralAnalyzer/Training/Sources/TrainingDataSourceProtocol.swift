import Foundation

/// Protocol for all remote spectral data sources.
protocol TrainingDataSourceProtocol: Actor {
    func fetchSpectra(species: [String]) async throws -> AsyncThrowingStream<ReferenceSpectrum, Error>
}
