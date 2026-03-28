import SwiftUI
import UniformTypeIdentifiers
#if canImport(AppKit)
import AppKit
#endif
import Foundation

// MARK: - Export and Reporting Functions

extension ContentView {

    func exportCSV(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }
        guard let url = savePanel(defaultName: "Spectra.csv", allowedTypes: [UTType.commaSeparatedText], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export CSV started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var lines: [String] = []
        if options.includeMetadata {
            lines.append("# Title: \(options.title)")
            lines.append("# Operator: \(options.operatorName)")
            lines.append("# Notes: \(options.notes)")
            if let metrics = analysis.selectedMetrics {
                lines.append(String(format: "# CriticalWavelength: %.2f", metrics.criticalWavelength))
                lines.append(String(format: "# UVA/UVB Ratio: %.4f", metrics.uvaUvbRatio))
            }
            if let label = analysis.selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                lines.append(String(format: "# Label SPF: %.1f", label.spf))
            }
            if let colipa = analysis.colipaSpfValue {
                lines.append(String(format: "# COLIPA SPF: %.1f", colipa))
            }
            if let display = analysis.displaySpfMetric {
                lines.append(String(format: "# SPF (display): %@ = %.1f", display.label, display.value))
            }
            if let calibration = analysis.calibrationResult, let metrics = analysis.selectedMetrics {
                let predicted = calibration.predict(metrics: metrics)
                lines.append(String(format: "# Estimated SPF (calibrated): %.1f", predicted))
                lines.append(String(format: "# Calibration R2: %.3f", calibration.r2))
                lines.append(String(format: "# Calibration RMSE: %.2f", calibration.rmse))
            }
        }
        if options.includeProcessing {
            lines.append("# Alignment: \(analysis.useAlignment ? "On" : "Off")")
            lines.append("# Smoothing: \(analysis.smoothingMethod.rawValue)")
            lines.append("# YAxis: \(analysis.yAxisMode.rawValue)")
            if analysis.smoothingMethod == .movingAverage {
                lines.append("# SmoothingWindow: \(analysis.smoothingWindow)")
            }
            if analysis.smoothingMethod == .savitzkyGolay {
                lines.append("# SGWindow: \(analysis.sgWindow)")
                lines.append("# SGOrder: \(analysis.sgOrder)")
            }
            lines.append("# Baseline: \(analysis.baselineMethod.rawValue)")
            lines.append("# Normalization: \(analysis.normalizationMethod.rawValue)")
        }

        var header = ["Wavelength (\(analysis.yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { sanitizeCSVField($0.name) })
        lines.append(header.joined(separator: ","))

        let count = first.x.count
        for i in 0..<count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            lines.append(row.joined(separator: ","))
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export CSV completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export CSV: \(error.localizedDescription)"
        }
    }

    func exportJCAMP(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        let jdx = UTType(filenameExtension: "jdx") ?? .data
        let jcamp = UTType(filenameExtension: "jcamp") ?? .data
        guard let url = savePanel(defaultName: "Spectra.jdx", allowedTypes: [jdx, jcamp], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export JCAMP started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var output = "##JCAMP-DX=5.00\n##DATA TYPE=UV/VIS SPECTRUM\n"
        if options.includeMetadata {
            if !options.title.isEmpty { output += "##TITLE=\(options.title)\n" }
            if !options.operatorName.isEmpty { output += "##OWNER=\(options.operatorName)\n" }
            if !options.notes.isEmpty { output += "##COMMENT=\(options.notes)\n" }
            if let metrics = analysis.selectedMetrics {
                output += String(format: "##CRITICALWAVELENGTH=%.2f\n", metrics.criticalWavelength)
                output += String(format: "##UVAUVBRATIO=%.4f\n", metrics.uvaUvbRatio)
            }
            if let label = analysis.selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                output += String(format: "##LABELSPF=%.1f\n", label.spf)
            }
            if let colipa = analysis.colipaSpfValue {
                output += String(format: "##COLIPASPF=%.1f\n", colipa)
            }
            if let display = analysis.displaySpfMetric {
                output += "##SPFDISPLAY=\(display.label) \(String(format: "%.1f", display.value))\n"
            }
            if let calibration = analysis.calibrationResult, let metrics = analysis.selectedMetrics {
                let predicted = calibration.predict(metrics: metrics)
                output += String(format: "##ESTIMATEDSPF=%.1f\n", predicted)
                output += String(format: "##CALIBRATIONR2=%.3f\n", calibration.r2)
                output += String(format: "##CALIBRATIONRMSE=%.2f\n", calibration.rmse)
            }
        }
        if options.includeProcessing {
            output += "##SPECTRASETTINGS=Alignment=\(analysis.useAlignment ? "On" : "Off")\n"
            output += "##SPECTRASETTINGS=Smoothing=\(analysis.smoothingMethod.rawValue)\n"
            output += "##SPECTRASETTINGS=YAxis=\(analysis.yAxisMode.rawValue)\n"
            if analysis.smoothingMethod == .movingAverage {
                output += "##SPECTRASETTINGS=SmoothingWindow=\(analysis.smoothingWindow)\n"
            }
            if analysis.smoothingMethod == .savitzkyGolay {
                output += "##SPECTRASETTINGS=SGWindow=\(analysis.sgWindow)\n"
                output += "##SPECTRASETTINGS=SGOrder=\(analysis.sgOrder)\n"
            }
            output += "##SPECTRASETTINGS=Baseline=\(analysis.baselineMethod.rawValue)\n"
            output += "##SPECTRASETTINGS=Normalization=\(analysis.normalizationMethod.rawValue)\n"
        }

        for spectrum in spectraToExport {
            output += "##TITLE=\(spectrum.name)\n"
            output += "##NPOINTS=\(spectrum.x.count)\n"
            output += "##XYDATA= (X++(Y..Y))\n"
            for i in 0..<spectrum.x.count {
                let xVal = spectrum.x[i]
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                output += String(format: "%.6f, %.6f\n", xVal, yVal)
            }
            output += "##END=\n"
        }

        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export JCAMP completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export JCAMP failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export JCAMP: \(error.localizedDescription)"
        }
    }

    func exportExcelXLSX(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }
        let xlsx = UTType(filenameExtension: "xlsx") ?? .data
        guard let url = savePanel(defaultName: "Spectra.xlsx", allowedTypes: [xlsx], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export XLSX started", area: .export, level: .info, details: "spectra=\(spectraToExport.count)")

        var header = ["Wavelength (\(analysis.yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { $0.name })

        var rows: [[String]] = []
        if options.includeMetadata {
            let headerLines = spcHeaderExportLines()
            if !headerLines.isEmpty {
                rows.append(["SPC Header", ""]) 
                for line in headerLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        rows.append([parts[0], parts[1]])
                    } else {
                        rows.append([line])
                    }
                }
                rows.append([])
            }

            let mathLines = spfMathExportLines()
            if !mathLines.isEmpty {
                rows.append(["SPF Math", ""]) 
                for line in mathLines {
                    let parts = line.split(separator: ":", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
                    if parts.count == 2 {
                        rows.append([parts[0], parts[1]])
                    } else {
                        rows.append([line])
                    }
                }
                rows.append([])
            }
        }

        let count = first.x.count
        for i in 0..<count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            rows.append(row)
        }

        do {
            try OOXMLWriter.writeXlsx(header: header, rows: rows, to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export XLSX completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export XLSX failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export XLSX: \(error.localizedDescription)"
        }
    }

    func exportWordDOCX(options: ExportOptions) {
        let report = buildAnalysisReport(options: options)
        let docx = UTType(filenameExtension: "docx") ?? .data
        guard let url = savePanel(defaultName: "Analysis Report.docx", allowedTypes: [docx], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export DOCX started", area: .export, level: .info)

        do {
            try OOXMLWriter.writeDocx(report: report, to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export DOCX completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export DOCX failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export DOCX: \(error.localizedDescription)"
        }
    }

    func exportPDFReport(options: ExportOptions) {
        let reportData = buildPDFReportData(options: options)
        let started = Date()
        Instrumentation.log("Export PDF started", area: .export, level: .info)
        let data = PDFReportRenderer.render(data: reportData)

        #if os(iOS)
        Task { @MainActor in
            let _ = await PlatformFileSaver.save(
                defaultName: "Analysis Report.pdf",
                allowedTypes: [UTType.pdf],
                data: data
            )
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export PDF completed", area: .export, level: .info, duration: duration)
        }
        #else
        guard let url = savePanel(defaultName: "Analysis Report.pdf", allowedTypes: [UTType.pdf], directoryKey: .analysisExports) else { return }
        do {
            try data.write(to: url)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export PDF completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export PDF failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export PDF: \(error.localizedDescription)"
        }
        #endif
    }

    func exportHTMLReport(options: ExportOptions) {
        let html = buildHTMLReport(options: options)
        let started = Date()
        Instrumentation.log("Export HTML started", area: .export, level: .info)

        #if os(iOS)
        guard let data = html.data(using: .utf8) else { return }
        Task { @MainActor in
            let _ = await PlatformFileSaver.save(
                defaultName: "Analysis Report.html",
                allowedTypes: [UTType.html],
                data: data
            )
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export HTML completed", area: .export, level: .info, duration: duration)
        }
        #else
        guard let url = savePanel(defaultName: "Analysis Report.html", allowedTypes: [UTType.html], directoryKey: .analysisExports) else { return }
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export HTML completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export HTML failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export HTML: \(error.localizedDescription)"
        }
        #endif
    }

    func buildPDFReportData(options: ExportOptions) -> PDFReportData {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "SPF Spectral Analyzer Report"
            : options.title
        let metadataLines = buildPDFReportMetadataLines(options: options)
        let metricRows = buildPDFReportMetricRows()
        let aiSummary = reportAISummary()
        let structured = aiVM.structuredOutput
        let recommendations = (structured?.recommendations ?? []).map {
            ReportRecommendation(ingredient: $0.ingredient, amount: $0.amount, rationale: $0.rationale)
        }
        let series = reportSeries()

        // Full AI response text (untruncated)
        let aiFullText = aiVM.result?.text ?? ""

        return PDFReportData(
            title: title,
            generatedAt: Date(),
            metadataLines: metadataLines,
            metricRows: metricRows,
            aiSummary: aiSummary,
            aiFullText: aiFullText,
            insights: structured?.insights ?? [],
            risks: structured?.risks ?? [],
            actions: structured?.actions ?? [],
            recommendations: recommendations,
            series: series,
            spfEstimation: analysis.cachedSPFEstimation
        )
    }

    func buildPDFReportMetadataLines(options: ExportOptions) -> [String] {
        var lines: [String] = []
        if options.includeMetadata {
            if !options.operatorName.isEmpty {
                lines.append("Operator: \(options.operatorName)")
            }
            if !options.notes.isEmpty {
                lines.append("Notes: \(options.notes)")
            }
            lines.append("Scope: \(effectiveAIScope.label)")
            lines.append("Spectra count: \(aiSpectraForScope().count)")
            lines.append(contentsOf: spcHeaderExportLines())
        }

        let calcMethod = SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
        lines.append("SPF Calculation Method: \(calcMethod.label)")

        if options.includeProcessing {
            lines.append("Alignment: \(analysis.useAlignment ? "On" : "Off")")
            lines.append("Smoothing: \(analysis.smoothingMethod.rawValue)")
            lines.append("Baseline: \(analysis.baselineMethod.rawValue)")
            lines.append("Normalization: \(analysis.normalizationMethod.rawValue)")
            lines.append("Y-Axis: \(analysis.yAxisMode.rawValue)")
        }

        return lines
    }

    func buildPDFReportMetricRows() -> [ReportMetricRow] {
        var rows: [ReportMetricRow] = []

        let calcMethod = SPFCalculationMethod(rawValue: spfCalculationMethodRawValue) ?? .colipa
        rows.append(ReportMetricRow(label: "Calculation method", value: calcMethod.label))
        rows.append(ReportMetricRow(label: "Y-Axis mode", value: analysis.yAxisMode.rawValue))
        rows.append(ReportMetricRow(label: "Total spectra loaded", value: "\(analysis.displayedSpectra.count)"))

        // Per-spectrum metrics for all displayed spectra
        let allSpectra = analysis.displayedSpectra
        for spectrum in allSpectra {
            if let metrics = SpectralMetricsCalculator.metrics(for: spectrum, yAxisMode: analysis.yAxisMode) {
                let spf = SpectralMetricsCalculator.spf(x: spectrum.x, y: spectrum.y, yAxisMode: analysis.yAxisMode, method: calcMethod)
                let spfStr = spf.map { String(format: "%.1f", $0) } ?? "N/A"
                rows.append(ReportMetricRow(
                    label: spectrum.name,
                    value: String(format: "λc=%.1f nm  UVA/UVB=%.3f  SPF=%@", metrics.criticalWavelength, metrics.uvaUvbRatio, spfStr)
                ))
            }
        }

        // Summary stats
        if let stats = analysis.selectedMetricsStats, analysis.selectedSpectra.count > 1 {
            rows.append(ReportMetricRow(label: "Avg UVA/UVB (selected)", value: String(format: "%.3f", stats.avgUvaUvb)))
            rows.append(ReportMetricRow(label: "Avg critical λ (selected)", value: String(format: "%.1f nm", stats.avgCritical)))
            rows.append(ReportMetricRow(label: "UVA/UVB range", value: String(format: "%.3f – %.3f", stats.uvaUvbRange.lowerBound, stats.uvaUvbRange.upperBound)))
            rows.append(ReportMetricRow(label: "Critical λ range", value: String(format: "%.1f – %.1f nm", stats.criticalRange.lowerBound, stats.criticalRange.upperBound)))
        }

        if let estimation = analysis.cachedSPFEstimation {
            rows.append(ReportMetricRow(label: "SPF (\(estimation.tier.label))", value: String(format: "%.1f", estimation.value)))
            if let raw = estimation.rawColipaValue {
                rows.append(ReportMetricRow(label: "Raw COLIPA SPF", value: String(format: "%.2f", raw)))
            }
        }

        if let calibration = analysis.calibrationResult {
            rows.append(ReportMetricRow(label: "Calibration R²", value: String(format: "%.3f", calibration.r2)))
            rows.append(ReportMetricRow(label: "Calibration RMSE", value: String(format: "%.2f", calibration.rmse)))
            rows.append(ReportMetricRow(label: "Calibration samples", value: "\(calibration.sampleCount)"))
        }

        if let dashboard = analysis.dashboardMetrics {
            rows.append(ReportMetricRow(label: "Compliance SPF≥30", value: String(format: "%.0f%% (%d of %d)", dashboard.compliancePercent, dashboard.complianceCount, dashboard.totalCount)))
            rows.append(ReportMetricRow(label: "Low critical λ count (< 370 nm)", value: "\(dashboard.lowCriticalCount)"))
            if let drop = dashboard.postIncubationDropPercent {
                rows.append(ReportMetricRow(label: "Post-incubation SPF drop", value: String(format: "%.1f%%", drop)))
            }
        }

        return rows
    }

    func buildHTMLReport(options: ExportOptions) -> String {
        let title = options.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "SPF Spectral Analyzer Report"
            : options.title
        let metadataLines = buildPDFReportMetadataLines(options: options)
        let metricRows = buildPDFReportMetricRows()
        let aiSummary = reportAISummary()
        let recommendations = (aiVM.structuredOutput?.recommendations ?? [])

        let seriesTable = buildHTMLSeriesTable()
        let metadataHTML = metadataLines.map { "<li>\(htmlEscape($0))</li>" }.joined()
        let metricsHTML = metricRows.map { "<tr><td>\(htmlEscape($0.label))</td><td>\(htmlEscape($0.value))</td></tr>" }.joined()
        let recommendationsHTML = recommendations.map { rec in
            let rationale = rec.rationale?.isEmpty == false ? "<div class=\"muted\">\(htmlEscape(rec.rationale ?? ""))</div>" : ""
            return "<li><strong>\(htmlEscape(rec.ingredient))</strong> — \(htmlEscape(rec.amount))\(rationale)</li>"
        }.joined()

        return """
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<title>\(htmlEscape(title))</title>
<style>
body { font-family: -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif; margin: 24px; color: #222; }
header { margin-bottom: 16px; }
h1 { font-size: 20px; margin: 0; }
section { margin-top: 16px; }
.muted { color: #666; font-size: 12px; }
table { border-collapse: collapse; width: 100%; font-size: 12px; }
th, td { border: 1px solid #ddd; padding: 6px; text-align: left; }
.small { font-size: 11px; }
</style>
</head>
<body>
<header>
  <h1>\(htmlEscape(title))</h1>
  <div class=\"muted\">Generated: \(htmlEscape(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)))</div>
</header>

<section>
  <h2 class=\"small\">Metadata</h2>
  <ul class=\"small\">\(metadataHTML)</ul>
</section>

<section>
  <h2 class=\"small\">Key Metrics</h2>
  <table>\(metricsHTML)</table>
</section>

<section>
  <h2 class=\"small\">AI Summary</h2>
  <p class=\"small\">\(htmlEscape(aiSummary))</p>
</section>

<section>
  <h2 class=\"small\">Recommendations</h2>
  <ul class=\"small\">\(recommendationsHTML.isEmpty ? "<li>None provided</li>" : recommendationsHTML)</ul>
</section>

<section>
  <h2 class=\"small\">Spectra (Downsampled)</h2>
  \(seriesTable)
</section>
</body>
</html>
"""
    }

    func buildHTMLSeriesTable() -> String {
        let series = analysis.seriesToPlot
        guard !series.isEmpty else { return "<div class=\"muted\">No spectra available.</div>" }

        let downsampled = series.map { series in
            let points = downsampleReportPoints(series.points, targetCount: 120)
            return (name: series.name, points: points)
        }

        let header = (["Wavelength"] + downsampled.map { $0.name }).map { "<th>\(htmlEscape($0))</th>" }.joined()

        let count = downsampled.first?.points.count ?? 0
        var rows: [String] = []
        for index in 0..<count {
            var columns: [String] = []
            let xValue = downsampled[0].points[index].x
            columns.append("<td>\(String(format: "%.2f", xValue))</td>")
            for series in downsampled {
                let yValue = series.points.indices.contains(index) ? series.points[index].y : 0
                columns.append("<td>\(String(format: "%.4f", yValue))</td>")
            }
            rows.append("<tr>\(columns.joined())</tr>")
        }

        return "<table><tr>\(header)</tr>\(rows.joined())</table>"
    }

    func htmlEscape(_ value: String) -> String {
        var escaped = value
        escaped = escaped.replacingOccurrences(of: "&", with: "&amp;")
        escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
        escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
        escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
        return escaped
    }

    func reportAISummary() -> String {
        if let summary = aiVM.structuredOutput?.summary, !summary.isEmpty {
            return summary
        }
        guard let text = aiVM.result?.text, !text.isEmpty else { return "No AI output available." }
        let paragraphs = text.components(separatedBy: "\n\n")
        return paragraphs.first ?? text
    }

    func reportSeries() -> [ReportSpectrumSeries] {
        let seriesSource = analysis.seriesToPlot
        // Fall back to all displayed spectra if nothing is currently plotted
        if seriesSource.isEmpty {
            let colors = analysis.palette.colors
            return analysis.displayedSpectra.enumerated().map { index, spectrum in
                let color = colors[index % colors.count]
                let raw = spectrum.x.indices.map { SpectrumPoint(id: $0, x: spectrum.x[$0], y: spectrum.y[$0]) }
                let points = downsampleReportPoints(raw, targetCount: 200)
                return ReportSpectrumSeries(name: spectrum.name, points: points, color: color)
            }
        }
        return seriesSource.map { series in
            let points = downsampleReportPoints(series.points, targetCount: 200)
            return ReportSpectrumSeries(name: series.name, points: points, color: series.color)
        }
    }

    func downsampleReportPoints(_ points: [SpectrumPoint], targetCount: Int) -> [ReportSpectrumPoint] {
        guard !points.isEmpty else { return [] }
        guard points.count > targetCount else {
            return points.map { ReportSpectrumPoint(x: $0.x, y: $0.y) }
        }

        let stride = max(points.count / targetCount, 1)
        var sampled: [ReportSpectrumPoint] = []
        sampled.reserveCapacity(targetCount + 1)
        for (index, point) in points.enumerated() where index % stride == 0 {
            sampled.append(ReportSpectrumPoint(x: point.x, y: point.y))
        }
        return sampled
    }

    func spcHeaderExportLines() -> [String] {
        guard let header = activeHeader else { return [] }
        var lines: [String] = []
        if let fileName = activeHeaderFileName {
            lines.append("File: \(fileName)")
        }
        if !header.sourceInstrumentText.isEmpty {
            lines.append("Instrument: \(header.sourceInstrumentText)")
        }
        lines.append("Experiment: \(header.experimentType.label) (code \(header.experimentType.rawValue))")
        lines.append("Points: \(header.pointCount)")
        lines.append(String(format: "X Range: %.4f – %.4f", header.firstX, header.lastX))
        lines.append("X Units: \(header.xUnit.formatted)")
        lines.append("Y Units: \(header.yUnit.formatted)")
        if !header.fileType.labels.isEmpty {
            lines.append("Flags: \(header.fileType.labels.joined(separator: ", "))")
        }
        if !header.memo.isEmpty {
            lines.append("Memo: \(header.memo)")
        }
        return lines
    }

    func spfMathExportLines() -> [String] {
        guard let spectrum = analysis.selectedSpectrum, let metrics = analysis.selectedMetrics else { return [] }
        return buildSpfMathLines(spectrum: spectrum, metrics: metrics, calibration: analysis.calibrationResult)
    }

    func buildAnalysisReport(options: ExportOptions) -> String {
        var sections: [String] = []
        sections.append("SPC Analyzer Report")
        sections.append("Generated: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
        sections.append("")

        if options.includeMetadata {
            sections.append("Metadata")
            sections.append("Title: \(options.title)")
            sections.append("Operator: \(options.operatorName)")
            if !options.notes.isEmpty {
                sections.append("Notes: \(options.notes)")
            }
            sections.append("")

            let headerLines = spcHeaderExportLines()
            if !headerLines.isEmpty {
                sections.append("SPC Header")
                sections.append(contentsOf: headerLines)
                sections.append("")
            }
        }

        sections.append("Selection")
        sections.append("Scope: \(effectiveAIScope.label)")
        sections.append("Spectra count: \(aiSpectraForScope().count)")
        if let selectedSpectrum = analysis.selectedSpectrum {
            sections.append("Selected spectrum: \(selectedSpectrum.name)")
        }
        sections.append("")

        if options.includeProcessing {
            sections.append("Processing")
            sections.append("Alignment: \(analysis.useAlignment ? "On" : "Off")")
            sections.append("Smoothing: \(analysis.smoothingMethod.rawValue)")
            if analysis.smoothingMethod == .movingAverage {
                sections.append("Smoothing window: \(analysis.smoothingWindow)")
            }
            if analysis.smoothingMethod == .savitzkyGolay {
                sections.append("SG window: \(analysis.sgWindow)")
                sections.append("SG order: \(analysis.sgOrder)")
            }
            sections.append("Baseline: \(analysis.baselineMethod.rawValue)")
            sections.append("Normalization: \(analysis.normalizationMethod.rawValue)")
            sections.append("YAxis: \(analysis.yAxisMode.rawValue)")
            sections.append("")
        }

        if let metrics = analysis.selectedMetrics {
            sections.append("Metrics")
            sections.append(String(format: "Critical wavelength: %.2f nm", metrics.criticalWavelength))
            sections.append(String(format: "UVA/UVB ratio: %.4f", metrics.uvaUvbRatio))
            sections.append(String(format: "Mean UVB transmittance: %.4f", metrics.meanUVBTransmittance))
            if let label = analysis.selectedSpectrum.flatMap({ SPFLabelStore.matchLabel(for: $0.name) }) {
                sections.append(String(format: "Label SPF: %.1f", label.spf))
            }
            if let colipa = analysis.colipaSpfValue {
                sections.append(String(format: "COLIPA SPF: %.1f", colipa))
            }
            if let estimated = analysis.estimatedSpfValue {
                sections.append(String(format: "Estimated SPF (calibrated): %.1f", estimated))
            }
            if let calibration = analysis.calibrationResult {
                sections.append(String(format: "Calibration R2: %.3f", calibration.r2))
                sections.append(String(format: "Calibration RMSE: %.2f", calibration.rmse))
            }
            sections.append("")
        }

        let mathLines = spfMathExportLines()
        if !mathLines.isEmpty {
            sections.append("SPF Math")
            sections.append(contentsOf: mathLines)
            sections.append("")
        }

        sections.append("AI Analysis")
        if let aiResult = aiVM.result {
            sections.append(aiResult.text)
        } else {
            sections.append("No AI output available.")
        }

        return sections.joined(separator: "\n")
    }

    func exportPeaksCSV() {
        guard !analysis.peaks.isEmpty else { return }
        guard let url = savePanel(defaultName: "Peaks.csv", allowedTypes: [UTType.commaSeparatedText], directoryKey: .analysisExports) else { return }

        let started = Date()
        Instrumentation.log("Export Peaks CSV started", area: .export, level: .info, details: "peaks=\(analysis.peaks.count)")

        var lines: [String] = []
        lines.append("Wavelength,Intensity")
        for peak in analysis.peaks {
            lines.append(String(format: "%.6f,%.6f", peak.x, peak.y))
        }

        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export Peaks CSV completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export Peaks CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export peaks CSV: \(error.localizedDescription)"
        }
    }

    func alignedForExport() -> [ShimadzuSpectrum] {
        let base = analysis.displayedSpectra
        guard let reference = base.first else { return base }
        let refX = reference.x

        let mismatchDetected = base.contains { !SpectraProcessing.axesMatch(refX, $0.x) }
        if !mismatchDetected { return base }

        return base.map { spectrum in
            if SpectraProcessing.axesMatch(refX, spectrum.x) {
                return spectrum
            }
            let resampledY = SpectraProcessing.resampleLinear(x: spectrum.x, y: spectrum.y, onto: refX)
            return ShimadzuSpectrum(name: spectrum.name, x: refX, y: resampledY)
        }
    }

}
