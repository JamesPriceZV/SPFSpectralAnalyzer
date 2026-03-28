#if os(iOS)
import UIKit
import Vision
import CoreImage

/// Analyzes photographs of PMMA plates or sunscreen samples using Vision framework
/// to extract color properties that may correlate with UV absorption characteristics.
enum VisionColorAnalyzer {

    /// Analyzes a captured image for color distribution and dominant color properties.
    static func analyze(image: UIImage) async -> ColorAnalysisResult {
        guard let cgImage = image.cgImage else {
            return ColorAnalysisResult.empty
        }

        // Use CIImage for pixel-level analysis
        let ciImage = CIImage(cgImage: cgImage)
        let context = CIContext()

        // Sample center region (40% of image) to focus on the sample area
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let inset = CGFloat(0.3)
        let sampleRect = CGRect(
            x: width * inset,
            y: height * inset,
            width: width * (1.0 - 2.0 * inset),
            height: height * (1.0 - 2.0 * inset)
        )

        let croppedImage = ciImage.cropped(to: sampleRect)

        // Extract average color using CIAreaAverage
        let extentVector = CIVector(
            x: croppedImage.extent.origin.x,
            y: croppedImage.extent.origin.y,
            z: croppedImage.extent.size.width,
            w: croppedImage.extent.size.height
        )

        guard let avgFilter = CIFilter(name: "CIAreaAverage", parameters: [
            kCIInputImageKey: croppedImage,
            kCIInputExtentKey: extentVector
        ]),
              let outputImage = avgFilter.outputImage else {
            return ColorAnalysisResult.empty
        }

        var bitmap = [UInt8](repeating: 0, count: 4)
        context.render(outputImage, toBitmap: &bitmap, rowBytes: 4,
                       bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                       format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB())

        let r = CGFloat(bitmap[0]) / 255.0
        let g = CGFloat(bitmap[1]) / 255.0
        let b = CGFloat(bitmap[2]) / 255.0

        let color = UIColor(red: r, green: g, blue: b, alpha: 1.0)
        var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0
        color.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: nil)

        let colorTemp = estimateColorTemperature(r: r, g: g, b: b)
        let interpretation = interpretForSunscreen(hue: hue * 360, saturation: saturation, brightness: brightness)

        return ColorAnalysisResult(
            dominantHue: hue * 360.0,
            averageSaturation: saturation,
            averageBrightness: brightness,
            averageRed: r,
            averageGreen: g,
            averageBlue: b,
            estimatedColorTemperature: colorTemp,
            interpretationNote: interpretation
        )
    }

    /// Rough color temperature estimate from RGB ratios.
    private static func estimateColorTemperature(r: CGFloat, g: CGFloat, b: CGFloat) -> String {
        let ratio = r / max(b, 0.001)
        if ratio > 1.5 { return "Warm (>5000K)" }
        if ratio > 1.0 { return "Neutral (~5000K)" }
        return "Cool (<5000K)"
    }

    /// Interprets color properties in the context of sunscreen / PMMA plate analysis.
    private static func interpretForSunscreen(hue: CGFloat, saturation: CGFloat, brightness: CGFloat) -> String? {
        if brightness > 0.9 && saturation < 0.1 {
            return "Very light sample — may indicate thin film or low concentration. Ensure adequate sample application (2 mg/cm²) on the PMMA plate."
        }
        if brightness < 0.3 {
            return "Dark sample — may indicate thick application or high-absorption formulation. Check for even distribution across the plate."
        }
        if hue > 30 && hue < 60 && saturation > 0.2 {
            return "Yellowish tint detected — common in mineral sunscreens containing zinc oxide or titanium dioxide."
        }
        return "Color profile within normal range for sunscreen samples."
    }
}

/// Result of color analysis on a captured photograph.
struct ColorAnalysisResult: Equatable {
    let dominantHue: CGFloat
    let averageSaturation: CGFloat
    let averageBrightness: CGFloat
    let averageRed: CGFloat
    let averageGreen: CGFloat
    let averageBlue: CGFloat
    let estimatedColorTemperature: String
    let interpretationNote: String?

    static let empty = ColorAnalysisResult(
        dominantHue: 0, averageSaturation: 0, averageBrightness: 0,
        averageRed: 0, averageGreen: 0, averageBlue: 0,
        estimatedColorTemperature: "Unknown",
        interpretationNote: "Unable to analyze image."
    )
}
#endif
