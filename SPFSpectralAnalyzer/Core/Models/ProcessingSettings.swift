import Foundation

struct ProcessingSettings: Equatable {
    var useAlignment: Bool
    var smoothingMethod: SmoothingMethod
    var smoothingWindow: Int
    var sgWindow: Int
    var sgOrder: Int
    var baselineMethod: BaselineMethod
    var normalizationMethod: NormalizationMethod
    var showAllSpectra: Bool
    var showAverage: Bool
    var yAxisMode: SpectralYAxisMode
    var overlayLimit: Int
    var showLegend: Bool
    var showLabels: Bool
    var palette: SpectrumPalette
    var detectPeaks: Bool
    var peakMinHeight: Double
    var peakMinDistance: Int
    var showPeaks: Bool
}
