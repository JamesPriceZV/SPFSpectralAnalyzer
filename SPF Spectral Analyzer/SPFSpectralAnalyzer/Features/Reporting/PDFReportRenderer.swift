#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif
import CoreText

// MARK: - Core Graphics PDF Renderer

enum PDFReportRenderer {

    // US Letter size in points
    static let pageWidth: CGFloat = 612
    static let pageHeight: CGFloat = 792
    static let margin: CGFloat = 50
    static let contentWidth: CGFloat = 612 - 100  // pageWidth - 2*margin

    // Colors
    static let accentColor = PlatformColor(red: 0.2, green: 0.4, blue: 0.7, alpha: 1.0)
    static let lightGray = PlatformColor.gray.withAlphaComponent(0.3)
    static let textBlack = PlatformColor.black
    static let textGray = PlatformColor.darkGray

    // Fonts
    static let titleFont = PlatformFont.systemFont(ofSize: 22, weight: .bold)
    static let headingFont = PlatformFont.systemFont(ofSize: 14, weight: .semibold)
    static let bodyFont = PlatformFont.systemFont(ofSize: 10, weight: .regular)
    static let bodySemibold = PlatformFont.systemFont(ofSize: 10, weight: .semibold)
    static let captionFont = PlatformFont.systemFont(ofSize: 9, weight: .regular)

    static func render(data: PDFReportData) -> Data {
        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let pdfInfo: [CFString: Any] = [
            kCGPDFContextTitle: data.title,
            kCGPDFContextCreator: "SPF Spectral Analyzer",
        ]

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, pdfInfo as CFDictionary) else {
            return Data()
        }

        var cursor = PDFCursor(ctx: ctx, y: 0)
        cursor.beginPage()

        // Title
        cursor.drawText(data.title, font: titleFont, color: textBlack)
        cursor.y -= 4

        // Date
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        cursor.drawText("Generated: \(dateFormatter.string(from: data.generatedAt))", font: captionFont, color: textGray)
        cursor.y -= 6

        // Metadata
        if !data.metadataLines.isEmpty {
            for line in data.metadataLines {
                cursor.ensureSpace(14)
                cursor.drawText(line, font: captionFont, color: textGray)
            }
        }

        // SPF Estimation callout
        if let estimation = data.spfEstimation {
            cursor.y -= 8
            cursor.ensureSpace(50)
            drawSPFCallout(cursor: &cursor, estimation: estimation)
        }

        // Divider
        cursor.y -= 8
        cursor.drawHorizontalRule()
        cursor.y -= 8

        // Key Metrics table
        cursor.ensureSpace(40)
        cursor.drawText("Key Metrics", font: headingFont, color: textBlack)
        cursor.y -= 4

        if data.metricRows.isEmpty {
            cursor.drawText("No metrics available.", font: bodyFont, color: textGray)
        } else {
            drawMetricsTable(cursor: &cursor, rows: data.metricRows)
        }

        // Divider
        cursor.y -= 8
        cursor.drawHorizontalRule()
        cursor.y -= 8

        // Spectra chart
        cursor.ensureSpace(200)
        cursor.drawText("Spectra Overview", font: headingFont, color: textBlack)
        cursor.y -= 4

        if data.series.isEmpty {
            cursor.drawText("No spectra available.", font: bodyFont, color: textGray)
        } else {
            drawSpectraChart(cursor: &cursor, series: data.series)
        }

        // Divider
        cursor.y -= 8
        cursor.drawHorizontalRule()
        cursor.y -= 8

        // --- AI Analysis Section ---
        let hasStructuredContent = !data.insights.isEmpty || !data.risks.isEmpty || !data.actions.isEmpty
        let hasAIContent = hasStructuredContent || !data.aiSummary.isEmpty || !data.aiFullText.isEmpty

        if hasAIContent {
            cursor.ensureSpace(40)
            cursor.drawText("AI Analysis", font: titleFont, color: accentColor)
            cursor.y -= 6

            // Summary — only show when we have a dedicated summary field AND structured sections
            // to display as an introduction. When structured output is present, the summary
            // field often duplicates the raw text, so prefer the structured sections.
            if !data.aiSummary.isEmpty, !hasStructuredContent {
                // No structured sections — show summary as the main AI content
                cursor.ensureSpace(30)
                cursor.drawText("Summary", font: headingFont, color: textBlack)
                cursor.y -= 4
                cursor.drawWrappedText(data.aiSummary, font: bodyFont, color: textBlack)
                cursor.y -= 8
            }

            // Insights
            if !data.insights.isEmpty {
                cursor.ensureSpace(30)
                drawBulletSection(cursor: &cursor, title: "Key Insights", items: data.insights, bulletColor: accentColor)
                cursor.y -= 8
            }

            // Risks
            if !data.risks.isEmpty {
                cursor.ensureSpace(30)
                let riskColor = PlatformColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0)
                drawBulletSection(cursor: &cursor, title: "Risks & Concerns", items: data.risks, bulletColor: riskColor)
                cursor.y -= 8
            }

            // Recommended Actions
            if !data.actions.isEmpty {
                cursor.ensureSpace(30)
                let actionColor = PlatformColor(red: 0.2, green: 0.6, blue: 0.3, alpha: 1.0)
                drawBulletSection(cursor: &cursor, title: "Recommended Actions", items: data.actions, bulletColor: actionColor)
                cursor.y -= 8
            }

            // Formulation Recommendations (table-style)
            if !data.recommendations.isEmpty {
                cursor.y -= 4
                cursor.ensureSpace(30)
                cursor.drawText("Formulation Recommendations", font: headingFont, color: textBlack)
                cursor.y -= 4

                drawRecommendationsTable(cursor: &cursor, recommendations: data.recommendations)
                cursor.y -= 8
            }

            // Full AI Response — only when there are NO structured sections (fallback)
            // When structured sections are present, the detailed text is redundant.
            if !hasStructuredContent, !data.aiFullText.isEmpty, data.aiFullText != data.aiSummary {
                cursor.y -= 4
                cursor.drawHorizontalRule()
                cursor.y -= 8
                cursor.ensureSpace(40)
                cursor.drawText("Detailed Analysis", font: headingFont, color: textBlack)
                cursor.y -= 4
                cursor.drawWrappedText(data.aiFullText, font: bodyFont, color: textBlack)
            }
        } else {
            cursor.ensureSpace(40)
            cursor.drawText("AI Analysis", font: headingFont, color: textBlack)
            cursor.y -= 4
            cursor.drawText("No AI output available.", font: bodyFont, color: textGray)
        }

        // Footer on last page
        drawPageFooter(cursor: &cursor)

        cursor.endPage()
        ctx.closePDF()

        return pdfData as Data
    }

    // MARK: - SPF Callout Box

    private static func drawSPFCallout(cursor: inout PDFCursor, estimation: SPFEstimationResult) {
        let boxHeight: CGFloat = 44
        let boxRect = CGRect(x: margin, y: cursor.y - boxHeight, width: contentWidth, height: boxHeight)

        // Background
        let bgColor: PlatformColor
        switch estimation.tier {
        case .fullColipa: bgColor = PlatformColor(red: 0.85, green: 0.95, blue: 0.85, alpha: 1.0)
        case .calibrated: bgColor = PlatformColor(red: 0.85, green: 0.9, blue: 1.0, alpha: 1.0)
        case .adjusted:   bgColor = PlatformColor(red: 1.0, green: 0.93, blue: 0.82, alpha: 1.0)
        }
        cursor.ctx.setFillColor(bgColor.cgColor)
        cursor.ctx.fill(boxRect)

        // Border
        cursor.ctx.setStrokeColor(accentColor.cgColor)
        cursor.ctx.setLineWidth(0.5)
        cursor.ctx.stroke(boxRect)

        // SPF value
        let spfString = String(format: "SPF: %.1f", estimation.value)
        let spfFont = PlatformFont.systemFont(ofSize: 18, weight: .bold)
        let spfAttrs: [NSAttributedString.Key: Any] = [.font: spfFont, .foregroundColor: textBlack]
        let spfSize = cursor.textSize(spfString, font: spfFont)
        let spfTextY = cursor.y - boxHeight + (boxHeight - spfSize.height) / 2
        cursor.drawTextAt(spfString, x: margin + 12, y: spfTextY, attrs: spfAttrs)

        // Tier badge
        let badgeText = estimation.tier.label
        let badgeFont = PlatformFont.systemFont(ofSize: 9, weight: .semibold)
        let badgeAttrs: [NSAttributedString.Key: Any] = [.font: badgeFont, .foregroundColor: accentColor]
        let badgeSize = cursor.textSize(badgeText, font: badgeFont)
        let badgeX = margin + 12 + spfSize.width + 12
        let badgeY = cursor.y - boxHeight + (boxHeight - badgeSize.height) / 2
        cursor.drawTextAt(badgeText, x: badgeX, y: badgeY, attrs: badgeAttrs)

        // Raw COLIPA on right
        if let raw = estimation.rawColipaValue {
            let rawText = String(format: "Raw COLIPA: %.2f", raw)
            let rawAttrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: textGray]
            let rawSize = cursor.textSize(rawText, font: captionFont)
            cursor.drawTextAt(rawText,
                              x: margin + contentWidth - rawSize.width - 12,
                              y: cursor.y - boxHeight + (boxHeight - rawSize.height) / 2,
                              attrs: rawAttrs)
        }

        cursor.y -= (boxHeight + 4)
    }

    // MARK: - Bullet Section (Insights / Risks / Actions)

    private static func drawBulletSection(cursor: inout PDFCursor, title: String, items: [String], bulletColor: PlatformColor) {
        cursor.drawText(title, font: headingFont, color: textBlack)
        cursor.y -= 4

        for item in items {
            cursor.ensureSpace(20)

            // Bullet dot
            let dotSize: CGFloat = 5
            let dotY = cursor.y - 8
            cursor.ctx.setFillColor(bulletColor.cgColor)
            cursor.ctx.fillEllipse(in: CGRect(x: margin + 4, y: dotY, width: dotSize, height: dotSize))

            // Bullet text
            cursor.drawWrappedText(item, font: bodyFont, color: textBlack, indent: 16)
            cursor.y -= 2
        }
    }

    // MARK: - Recommendations Cards

    private static func drawRecommendationsTable(cursor: inout PDFCursor, recommendations: [ReportRecommendation]) {
        for (index, rec) in recommendations.enumerated() {
            cursor.ensureSpace(40)

            // Light background card for alternating items
            if index % 2 == 0 {
                // We draw the background after measuring, so for now just draw content
            }

            // Ingredient name (wrapped, bold)
            cursor.drawWrappedText(rec.ingredient, font: bodySemibold, color: textBlack, indent: 0)
            cursor.y -= 1

            // Amount (on its own line, accented)
            if !rec.amount.isEmpty {
                cursor.drawWrappedText("Dosage: \(rec.amount)", font: bodyFont, color: accentColor, indent: 8)
                cursor.y -= 1
            }

            // Rationale (indented, smaller)
            if let rationale = rec.rationale, !rationale.isEmpty {
                cursor.drawWrappedText(rationale, font: captionFont, color: textGray, indent: 8)
            }

            cursor.y -= 6

            // Separator line between recommendations
            if index < recommendations.count - 1 {
                cursor.ctx.setStrokeColor(PlatformColor.gray.withAlphaComponent(0.15).cgColor)
                cursor.ctx.setLineWidth(0.5)
                cursor.ctx.move(to: CGPoint(x: margin, y: cursor.y))
                cursor.ctx.addLine(to: CGPoint(x: margin + contentWidth, y: cursor.y))
                cursor.ctx.strokePath()
                cursor.y -= 6
            }
        }
    }

    // MARK: - Metrics Table

    private static func drawMetricsTable(cursor: inout PDFCursor, rows: [ReportMetricRow]) {
        let labelWidth: CGFloat = 200
        let rowHeight: CGFloat = 16
        let textOffsetY: CGFloat = 3  // baseline offset from bottom of row
        let maxLabelTextWidth = labelWidth - 12  // padding on both sides

        // Header row
        let headerAttrs: [NSAttributedString.Key: Any] = [.font: bodySemibold, .foregroundColor: accentColor]
        cursor.ctx.setFillColor(PlatformColor(white: 0.95, alpha: 1.0).cgColor)
        cursor.ctx.fill(CGRect(x: margin, y: cursor.y - rowHeight, width: contentWidth, height: rowHeight))
        cursor.drawTextAt("Metric", x: margin + 8, y: cursor.y - rowHeight + textOffsetY, attrs: headerAttrs)
        cursor.drawTextAt("Value", x: margin + labelWidth + 8, y: cursor.y - rowHeight + textOffsetY, attrs: headerAttrs)
        cursor.y -= rowHeight

        let labelAttrs: [NSAttributedString.Key: Any] = [.font: bodyFont, .foregroundColor: textGray]
        let valueAttrs: [NSAttributedString.Key: Any] = [.font: bodySemibold, .foregroundColor: textBlack]

        for (index, row) in rows.enumerated() {
            cursor.ensureSpace(rowHeight)

            // Alternating row background
            if index % 2 == 0 {
                cursor.ctx.setFillColor(PlatformColor(white: 0.98, alpha: 1.0).cgColor)
                cursor.ctx.fill(CGRect(x: margin, y: cursor.y - rowHeight, width: contentWidth, height: rowHeight))
            }

            // Truncate label if it would overflow into the value column
            let truncatedLabel = cursor.truncatedText(row.label, font: bodyFont, maxWidth: maxLabelTextWidth)
            cursor.drawTextAt(truncatedLabel, x: margin + 8, y: cursor.y - rowHeight + textOffsetY, attrs: labelAttrs)
            cursor.drawTextAt(row.value, x: margin + labelWidth + 8, y: cursor.y - rowHeight + textOffsetY, attrs: valueAttrs)
            cursor.y -= rowHeight
        }
    }

    // MARK: - Spectra Chart (vector drawn)

    private static func drawSpectraChart(cursor: inout PDFCursor, series: [ReportSpectrumSeries]) {
        let chartHeight: CGFloat = 200
        let chartRect = CGRect(x: margin + 30, y: cursor.y - chartHeight, width: contentWidth - 40, height: chartHeight - 20)

        // Determine data bounds
        var xMin = Double.greatestFiniteMagnitude, xMax = -Double.greatestFiniteMagnitude
        var yMin = Double.greatestFiniteMagnitude, yMax = -Double.greatestFiniteMagnitude
        for s in series {
            for p in s.points {
                xMin = min(xMin, p.x); xMax = max(xMax, p.x)
                yMin = min(yMin, p.y); yMax = max(yMax, p.y)
            }
        }
        guard xMax > xMin, yMax > yMin else {
            cursor.drawText("Insufficient data for chart.", font: bodyFont, color: textGray)
            return
        }

        // Add 5% padding
        let xPad = (xMax - xMin) * 0.05
        let yPad = (yMax - yMin) * 0.05
        xMin -= xPad; xMax += xPad; yMin -= yPad; yMax += yPad

        // Axes
        cursor.ctx.setStrokeColor(PlatformColor.gray.cgColor)
        cursor.ctx.setLineWidth(0.5)
        cursor.ctx.move(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
        cursor.ctx.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
        cursor.ctx.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
        // Actually: Y-axis goes up in CG, so minY is bottom. Let's draw properly:
        cursor.ctx.move(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
        cursor.ctx.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.minY))
        cursor.ctx.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.minY))
        cursor.ctx.strokePath()

        // Axis labels
        let axisLabelAttrs: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 8), .foregroundColor: PlatformColor.gray]

        // X-axis tick labels (5 ticks)
        for i in 0...4 {
            let frac = Double(i) / 4.0
            let val = xMin + frac * (xMax - xMin)
            let x = chartRect.minX + CGFloat(frac) * chartRect.width
            let label = String(format: "%.0f", val)
            cursor.drawTextAt(label, x: x - 10, y: chartRect.minY - 12, attrs: axisLabelAttrs)
        }

        // Y-axis tick labels (4 ticks)
        for i in 0...3 {
            let frac = Double(i) / 3.0
            let val = yMin + frac * (yMax - yMin)
            let y = chartRect.minY + CGFloat(frac) * chartRect.height
            let label = String(format: "%.2f", val)
            let labelSize = cursor.textSize(label, font: PlatformFont.systemFont(ofSize: 8))
            cursor.drawTextAt(label, x: chartRect.minX - labelSize.width - 4, y: y - 5, attrs: axisLabelAttrs)
        }

        // Axis titles
        let axisTitleAttrs: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 9, weight: .semibold), .foregroundColor: PlatformColor.darkGray]
        let xAxisTitle = "Wavelength (nm)"
        let xTitleSize = cursor.textSize(xAxisTitle, font: PlatformFont.systemFont(ofSize: 9, weight: .semibold))
        cursor.drawTextAt(xAxisTitle, x: chartRect.midX - xTitleSize.width / 2, y: chartRect.minY - 24, attrs: axisTitleAttrs)

        // Y-axis title (drawn rotated)
        let yAxisTitle = series.first != nil ? "Intensity" : "Value"
        let ytAttrs: [NSAttributedString.Key: Any] = [.font: PlatformFont.systemFont(ofSize: 9, weight: .semibold) as CTFont, .foregroundColor: PlatformColor.darkGray.cgColor]
        let ytAttrStr = NSAttributedString(string: yAxisTitle, attributes: ytAttrs)
        let ytLine = CTLineCreateWithAttributedString(ytAttrStr)
        cursor.ctx.saveGState()
        cursor.ctx.translateBy(x: margin - 2, y: chartRect.midY - 20)
        cursor.ctx.rotate(by: .pi / 2)
        cursor.ctx.textPosition = .zero
        CTLineDraw(ytLine, cursor.ctx)
        cursor.ctx.restoreGState()

        // Spectrum colors (cycle through a palette)
        let palette: [PlatformColor] = [
            PlatformColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1.0),
            PlatformColor(red: 0.8, green: 0.2, blue: 0.2, alpha: 1.0),
            PlatformColor(red: 0.2, green: 0.7, blue: 0.3, alpha: 1.0),
            PlatformColor(red: 0.8, green: 0.5, blue: 0.1, alpha: 1.0),
            PlatformColor(red: 0.6, green: 0.2, blue: 0.7, alpha: 1.0),
            PlatformColor(red: 0.1, green: 0.6, blue: 0.7, alpha: 1.0),
        ]

        func mapPoint(_ p: ReportSpectrumPoint) -> CGPoint {
            let px = chartRect.minX + CGFloat((p.x - xMin) / (xMax - xMin)) * chartRect.width
            let py = chartRect.minY + CGFloat((p.y - yMin) / (yMax - yMin)) * chartRect.height
            return CGPoint(x: px, y: py)
        }

        for (si, s) in series.enumerated() {
            guard s.points.count >= 2 else { continue }
            let color = palette[si % palette.count]
            cursor.ctx.setStrokeColor(color.cgColor)
            cursor.ctx.setLineWidth(0.8)

            let first = mapPoint(s.points[0])
            cursor.ctx.move(to: first)
            for i in 1..<s.points.count {
                cursor.ctx.addLine(to: mapPoint(s.points[i]))
            }
            cursor.ctx.strokePath()
        }

        // Legend (compact, below chart — positioned after axis title)
        cursor.y -= chartHeight
        cursor.y -= 30  // Space for x-axis tick labels + axis title

        let legendFont = PlatformFont.systemFont(ofSize: 7, weight: .regular)
        var legendX = margin
        var legendY = cursor.y - 10
        let nameAttrs: [NSAttributedString.Key: Any] = [.font: legendFont, .foregroundColor: textBlack]

        // Truncate long series names in legend
        let maxLegendNameWidth: CGFloat = 160

        for (si, s) in series.enumerated() {
            let color = palette[si % palette.count]
            // Color swatch
            cursor.ctx.setFillColor(color.cgColor)
            cursor.ctx.fill(CGRect(x: legendX, y: legendY + 2, width: 6, height: 6))
            legendX += 9

            let displayName = cursor.truncatedText(s.name, font: legendFont, maxWidth: maxLegendNameWidth)
            let nameSize = cursor.textSize(displayName, font: legendFont)
            cursor.drawTextAt(displayName, x: legendX, y: legendY, attrs: nameAttrs)
            legendX += nameSize.width + 10

            // Wrap to next line if needed
            if legendX > margin + contentWidth - 80 {
                legendX = margin
                cursor.y -= 12
                legendY -= 12
            }
        }
        cursor.y -= 14
    }

    // MARK: - Footer

    static func drawPageFooter(cursor: inout PDFCursor) {
        let footerY: CGFloat = 30.0
        let footerText = "SPF Spectral Analyzer — Page \(cursor.pageNumber)"
        let attrs: [NSAttributedString.Key: Any] = [.font: captionFont, .foregroundColor: textGray]
        let size = cursor.textSize(footerText, font: captionFont)
        cursor.drawTextAt(footerText, x: (pageWidth - size.width) / 2, y: footerY, attrs: attrs)
    }
}

// MARK: - PDF Cursor (tracks position, handles pagination)

struct PDFCursor {
    let ctx: CGContext
    var y: CGFloat
    var pageNumber: Int = 0

    private let pageWidth = PDFReportRenderer.pageWidth
    private let pageHeight = PDFReportRenderer.pageHeight
    private let margin = PDFReportRenderer.margin
    private let contentWidth = PDFReportRenderer.contentWidth
    private let bottomMargin: CGFloat = 60

    mutating func beginPage() {
        let mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        ctx.beginPDFPage(nil)
        pageNumber += 1
        y = pageHeight - margin

        // Flip coordinate system so text draws top-down
        // (NSString.draw uses flipped coordinates by default on macOS)
        _ = mediaBox // keep for reference
    }

    mutating func endPage() {
        PDFReportRenderer.drawPageFooter(cursor: &self)
        ctx.endPDFPage()
    }

    /// Ensures at least `needed` points of vertical space remain. If not, starts a new page.
    mutating func ensureSpace(_ needed: CGFloat) {
        if y - needed < bottomMargin {
            endPage()
            beginPage()
        }
    }

    mutating func drawText(_ text: String, font: PlatformFont, color: PlatformColor) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font as CTFont, .foregroundColor: color.cgColor]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        let lineHeight = bounds.height
        let descent = bounds.origin.y  // negative descent
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: margin, y: y - lineHeight - descent)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
        y -= (lineHeight + 2)
    }

    /// Draw text at a specific position using CoreText (works correctly in CG coordinate space)
    func drawTextAt(_ text: String, x: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        // Convert NSAttributedString.Key attrs to CT-compatible attrs
        var ctAttrs: [NSAttributedString.Key: Any] = [:]
        for (key, value) in attrs {
            if key == .font, let nsFont = value as? PlatformFont {
                ctAttrs[key] = nsFont as CTFont
            } else if key == .foregroundColor, let nsColor = value as? PlatformColor {
                ctAttrs[key] = nsColor.cgColor
            } else {
                ctAttrs[key] = value
            }
        }
        let attrStr = NSAttributedString(string: text, attributes: ctAttrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        ctx.saveGState()
        ctx.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Measure text size for layout purposes
    func textSize(_ text: String, font: PlatformFont) -> CGSize {
        let attrs: [NSAttributedString.Key: Any] = [.font: font as CTFont]
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, [])
        return CGSize(width: bounds.width, height: bounds.height)
    }

    /// Truncate text with ellipsis if it exceeds maxWidth
    func truncatedText(_ text: String, font: PlatformFont, maxWidth: CGFloat) -> String {
        let size = textSize(text, font: font)
        guard size.width > maxWidth else { return text }
        var truncated = text
        while truncated.count > 1 {
            truncated = String(truncated.dropLast())
            let testSize = textSize(truncated + "…", font: font)
            if testSize.width <= maxWidth {
                return truncated + "…"
            }
        }
        return "…"
    }

    mutating func drawWrappedText(_ text: String, font: PlatformFont, color: PlatformColor, indent: CGFloat = 0) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let maxWidth = contentWidth - indent
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let framesetter = CTFramesetterCreateWithAttributedString(attrStr)
        let pathRect = CGRect(x: margin + indent, y: bottomMargin, width: maxWidth, height: y - bottomMargin)
        let path = CGPath(rect: pathRect, transform: nil)
        let frame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), path, nil)

        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRangeMake(0, 0), &origins)

        for (i, line) in lines.enumerated() {
            let lineOrigin = CGPoint(x: pathRect.origin.x + origins[i].x,
                                      y: pathRect.origin.y + origins[i].y)
            // Check if this line would go below bottom margin
            if lineOrigin.y < bottomMargin {
                endPage()
                beginPage()
                // Recursively draw remaining text
                let range = CTLineGetStringRange(line)
                let remaining = (text as NSString).substring(from: range.location)
                drawWrappedText(remaining, font: font, color: color, indent: indent)
                return
            }

            ctx.textPosition = lineOrigin
            CTLineDraw(line, ctx)
            y = lineOrigin.y - 2
        }
        y -= 2
    }

    mutating func drawHorizontalRule() {
        ctx.setStrokeColor(PDFReportRenderer.lightGray.cgColor)
        ctx.setLineWidth(0.5)
        ctx.move(to: CGPoint(x: margin, y: y))
        ctx.addLine(to: CGPoint(x: margin + contentWidth, y: y))
        ctx.strokePath()
    }
}
