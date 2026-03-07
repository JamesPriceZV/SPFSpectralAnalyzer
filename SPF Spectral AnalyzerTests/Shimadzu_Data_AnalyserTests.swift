//
//  Shimadzu_Data_AnalyserTests.swift
//  Shimadzu Data AnalyserTests
//
//  Created by Zinco Verde, Inc. on 3/7/26.
//

import Foundation
import Testing
@testable import Shimadzu_Data_Analyser

struct Shimadzu_Data_AnalyserTests {

    private func approxEqual(_ lhs: Double, _ rhs: Double, tolerance: Double = 1.0e-6) -> Bool {
        abs(lhs - rhs) <= tolerance
    }

    @Test func axesMatchChecksTolerance() async throws {
        let a = [1.0, 2.0, 3.0]
        let b = [1.0, 2.0 + 1.0e-7, 3.0]
        let c = [1.0, 2.0 + 1.0e-3, 3.0]

        #expect(SpectraProcessing.axesMatch(a, b))
        #expect(!SpectraProcessing.axesMatch(a, c))
    }

    @Test func resampleLinearInterpolates() async throws {
        let x = [0.0, 1.0, 2.0]
        let y = [0.0, 1.0, 2.0]
        let newX = [0.0, 0.5, 1.5, 2.0]

        let resampled = SpectraProcessing.resampleLinear(x: x, y: y, onto: newX)
        #expect(resampled.count == newX.count)
        #expect(approxEqual(resampled[0], 0.0))
        #expect(approxEqual(resampled[1], 0.5))
        #expect(approxEqual(resampled[2], 1.5))
        #expect(approxEqual(resampled[3], 2.0))
    }

    @Test func movingAveragePreservesConstantSignal() async throws {
        let y = Array(repeating: 2.0, count: 11)
        let smoothed = SpectraProcessing.movingAverage(y: y, window: 5)
        #expect(smoothed.count == y.count)
        #expect(smoothed.allSatisfy { approxEqual($0, 2.0) })
    }

    @Test func savitzkyGolayPreservesConstantSignal() async throws {
        let y = Array(repeating: 1.5, count: 25)
        let smoothed = SpectraProcessing.savitzkyGolay(y: y, window: 7, polynomialOrder: 3)
        #expect(smoothed.count == y.count)
        #expect(smoothed.allSatisfy { approxEqual($0, 1.5, tolerance: 1.0e-5) })
    }

    @Test func baselineMinSubtractWorks() async throws {
        let y = [2.0, 3.0, 4.0]
        let x = [0.0, 1.0, 2.0]
        let adjusted = SpectraProcessing.applyBaseline(y: y, x: x, method: .minSubtract)
        #expect(approxEqual(adjusted[0], 0.0))
        #expect(approxEqual(adjusted[1], 1.0))
        #expect(approxEqual(adjusted[2], 2.0))
    }

    @Test func normalizationMethodsWork() async throws {
        let x = [0.0, 1.0]
        let y = [2.0, 4.0]

        let minMax = SpectraProcessing.applyNormalization(y: y, x: x, method: .minMax)
        #expect(approxEqual(minMax[0], 0.0))
        #expect(approxEqual(minMax[1], 1.0))

        let area = SpectraProcessing.applyNormalization(y: [1.0, 1.0], x: x, method: .area)
        #expect(approxEqual(area[0], 1.0))
        #expect(approxEqual(area[1], 1.0))

        let peak = SpectraProcessing.applyNormalization(y: y, x: x, method: .peak)
        #expect(approxEqual(peak[0], 0.5))
        #expect(approxEqual(peak[1], 1.0))
    }

    @Test func detectPeaksFindsLocalMaxima() async throws {
        let x = [0.0, 1.0, 2.0, 3.0, 4.0]
        let y = [0.0, 1.0, 0.0, 2.0, 0.0]
        let peaks = SpectraProcessing.detectPeaks(x: x, y: y, minHeight: 0.5, minDistance: 1)
        #expect(peaks.count == 2)
        #expect(peaks[0].id == 1)
        #expect(peaks[1].id == 3)
    }

    @Test func spectralMetricsForConstantAbsorbance() async throws {
        let x = stride(from: 290.0, through: 400.0, by: 10.0).map { $0 }
        let y = Array(repeating: 1.0, count: x.count)
        let spectrum = ShimadzuSpectrum(name: "Constant", x: x, y: y)

        let metrics = SpectralMetricsCalculator.metrics(for: spectrum, yAxisMode: .absorbance)
        #expect(metrics != nil)
        guard let metrics else { return }

        #expect(approxEqual(metrics.uvbArea, 30.0, tolerance: 1.0e-6))
        #expect(approxEqual(metrics.uvaArea, 80.0, tolerance: 1.0e-6))
        #expect(approxEqual(metrics.uvaUvbRatio, 80.0 / 30.0, tolerance: 1.0e-6))
        #expect(approxEqual(metrics.criticalWavelength, 389.0, tolerance: 1.0e-6))
        #expect(approxEqual(metrics.meanUVBTransmittance, 0.1, tolerance: 1.0e-6))
    }

    @Test @MainActor func spcFixturesParse() async throws {
        let urls = spcFixtureURLs()
        #expect(!urls.isEmpty)

        let clock = ContinuousClock()
        let timeCap = fixtureTimeCapSeconds(defaultValue: 5.0)
        let deadline = clock.now.advanced(by: .seconds(timeCap))
        var parsedCount = 0

        for url in urls {
            if clock.now >= deadline { break }
            let parser = try ShimadzuSPCParser(fileURL: url)
            let result = try parser.extractSpectraResult()
            #expect(!result.spectra.isEmpty)
            parsedCount += 1
        }

        #expect(parsedCount > 0)
    }

    private func spcFixtureURLs() -> [URL] {
        let bundle = Bundle(for: FixtureBundleToken.self)
        let withSubdir = bundle.urls(forResourcesWithExtension: "spc", subdirectory: "SPC Sample Files") ?? []
        if !withSubdir.isEmpty {
            return withSubdir
        }
        return bundle.urls(forResourcesWithExtension: "spc", subdirectory: nil) ?? []
    }

    private func fixtureTimeCapSeconds(defaultValue: Double) -> Double {
        let value = ProcessInfo.processInfo.environment["SPC_PARSER_TIME_CAP_SECONDS"]
        if let value, let parsed = Double(value), parsed > 0 {
            return parsed
        }
        return defaultValue
    }

    private final class FixtureBundleToken {}
}
