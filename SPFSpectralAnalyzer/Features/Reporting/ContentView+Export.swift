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

        // Render in a Task so the calling function returns immediately
        // and the UI stays responsive during report generation.
        Task { @MainActor in
            let data = PDFReportRenderer.render(data: reportData)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export PDF completed", area: .export, level: .info, duration: duration)

            #if os(iOS)
            let _ = await PlatformFileSaver.save(
                defaultName: "Analysis Report.pdf",
                allowedTypes: [UTType.pdf],
                data: data
            )
            #else
            guard let url = savePanel(defaultName: "Analysis Report.pdf", allowedTypes: [UTType.pdf], directoryKey: .analysisExports) else { return }
            do {
                try data.write(to: url)
            } catch {
                Instrumentation.log("Export PDF failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
                analysis.errorMessage = "Failed to export PDF: \(error.localizedDescription)"
            }
            #endif
        }
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
        let dateString = DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short)
        let metadataLines = buildPDFReportMetadataLines(options: options)
        let metricRows = buildPDFReportMetricRows()
        let aiSummary = reportAISummary()
        let aiFullText = aiVM.result?.text ?? ""
        let structured = aiVM.structuredOutput
        let recommendations = structured?.recommendations ?? []
        let insights = structured?.insights ?? []
        let risks = structured?.risks ?? []
        let actions = structured?.actions ?? []
        let estimation = analysis.cachedSPFEstimation
        let series = reportSeries()
        let hasAIContent = !insights.isEmpty || !risks.isEmpty || !actions.isEmpty || !aiSummary.isEmpty || !aiFullText.isEmpty
        let hasStructuredContent = !insights.isEmpty || !risks.isEmpty || !actions.isEmpty

        // Build sections
        let spfCalloutHTML = buildHTMLSPFCallout(estimation: estimation)
        let metricsTableHTML = buildHTMLMetricsTable(rows: metricRows)
        let chartSVG = buildHTMLSpectraChart(series: series)
        let legendHTML = buildHTMLLegend(series: series)
        let aiSectionHTML = buildHTMLAISection(
            aiSummary: aiSummary, aiFullText: aiFullText,
            insights: insights, risks: risks, actions: actions,
            recommendations: recommendations,
            hasStructuredContent: hasStructuredContent
        )
        let methodologyHTML = metadataLines.map { "<li>\(htmlEscape($0))</li>" }.joined(separator: "\n              ")

        // TOC entries
        var tocEntries = """
        <a href=\"#results\"><span class=\"num\">1.</span> Results <span class=\"desc\">Key metrics, SPF estimation, compliance status</span></a>
        <a href=\"#spectra\"><span class=\"num\">2.</span> Spectra <span class=\"desc\">UV spectral overlay chart with wavelength analysis</span></a>
        """
        if hasAIContent {
            tocEntries += "\n        <a href=\"#ai-analysis\"><span class=\"num\">3.</span> AI Analysis <span class=\"desc\">Insights, risks, recommended actions</span></a>"
        }
        if !metadataLines.isEmpty {
            let num = hasAIContent ? "4" : "3"
            tocEntries += "\n        <a href=\"#methodology\"><span class=\"num\">\(num).</span> Methodology <span class=\"desc\">Instrument metadata, calculation parameters</span></a>"
        }

        let methodSectionNum = hasAIContent ? "4" : "3"

        return """
<!doctype html>
<html lang=\"en\">
<head>
<meta charset=\"utf-8\">
<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
<title>\(htmlEscape(title))</title>
<style>
:root {
  --accent: #3366B2;
  --accent-light: #4A7FD4;
  --text: #222;
  --muted: #666;
  --border: #ddd;
  --bg-alt: #f8f9fa;
  --bg-header: #f2f2f2;
  --green-bg: #d9f2d9;
  --blue-bg: #d9e4ff;
  --amber-bg: #ffe9d1;
  --risk-color: #cc3333;
  --action-color: #339933;
}
* { box-sizing: border-box; }
html, body { margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif; color: var(--text); font-size: 11pt; line-height: 1.5; }
.page { max-width: 800px; margin: 0 auto; padding: 24px 32px; }

/* Title Page */
.title-page { text-align: center; padding: 80px 32px 60px; border-bottom: 1px solid var(--border); margin-bottom: 32px; }
.title-page .app-name { font-size: 12pt; color: var(--accent); font-weight: 500; letter-spacing: 0.5px; margin-bottom: 8px; }
.title-page h1 { font-size: 24pt; font-weight: 700; margin: 0 0 12px; }
.title-page .rule { width: 180px; height: 1px; background: var(--accent); margin: 16px auto; }
.title-page .date { font-size: 10pt; color: var(--muted); margin-bottom: 20px; }
.title-page .meta-line { font-size: 9pt; color: var(--muted); margin: 2px 0; }

/* Table of Contents */
.toc { background: var(--bg-alt); border: 1px solid var(--border); border-radius: 8px; padding: 16px 20px; margin-bottom: 32px; }
.toc h2 { margin: 0 0 12px; font-size: 14pt; color: var(--accent); }
.toc a { display: flex; align-items: baseline; gap: 6px; padding: 6px 0; border-bottom: 1px solid var(--border); color: var(--accent); text-decoration: none; font-size: 11pt; }
.toc a:last-child { border-bottom: none; }
.toc a:hover { text-decoration: underline; }
.toc .num { font-weight: 600; min-width: 24px; }
.toc .desc { margin-left: auto; font-size: 9pt; color: var(--muted); font-weight: 400; }

/* Section Headings */
.report-section { margin-bottom: 28px; scroll-margin-top: 20px; }
.report-section > h2 { font-size: 18pt; font-weight: 600; color: var(--accent); margin: 0 0 12px; padding-bottom: 6px; border-bottom: 2px solid var(--accent); }
.report-section h3 { font-size: 12pt; font-weight: 600; margin: 16px 0 8px; }

/* SPF Callout */
.spf-callout { display: flex; align-items: center; gap: 12px; padding: 10px 16px; border: 1px solid var(--accent); border-radius: 6px; margin-bottom: 16px; }
.spf-callout.tier-fullColipa { background: var(--green-bg); }
.spf-callout.tier-calibrated { background: var(--blue-bg); }
.spf-callout.tier-adjusted { background: var(--amber-bg); }
.spf-value { font-size: 18pt; font-weight: 700; }
.spf-tier { font-size: 9pt; font-weight: 600; color: var(--accent); }
.spf-raw { margin-left: auto; font-size: 9pt; color: var(--muted); }

/* Metrics Table */
.metrics-table { border-collapse: collapse; width: 100%; font-size: 10pt; margin-bottom: 12px; }
.metrics-table th { background: var(--bg-header); color: var(--accent); font-weight: 600; text-align: left; padding: 6px 10px; border: 1px solid var(--border); }
.metrics-table td { padding: 5px 10px; border: 1px solid var(--border); }
.metrics-table tr:nth-child(even) td { background: var(--bg-alt); }
.metrics-table .label { color: var(--muted); }
.metrics-table .value { font-weight: 600; }

/* Chart */
.chart-container { background: white; border: 1px solid var(--border); border-radius: 8px; padding: 12px; margin-bottom: 12px; }
.chart-container svg { width: 100%; height: auto; }
.legend { display: flex; flex-wrap: wrap; gap: 12px; font-size: 9pt; color: var(--muted); margin-bottom: 16px; }
.legend-item { display: flex; align-items: center; gap: 5px; }
.legend-swatch { width: 12px; height: 3px; border-radius: 1px; }

/* AI Analysis */
.ai-subsection { margin-bottom: 12px; }
.ai-subsection h3 { margin: 12px 0 6px; }
.bullet-list { list-style: none; padding: 0; margin: 0; }
.bullet-list li { padding: 3px 0 3px 18px; position: relative; font-size: 10pt; }
.bullet-list li::before { content: ''; position: absolute; left: 4px; top: 10px; width: 6px; height: 6px; border-radius: 50%; }
.bullet-list.insights li::before { background: var(--accent); }
.bullet-list.risks li::before { background: var(--risk-color); }
.bullet-list.actions li::before { background: var(--action-color); }
.rec-card { padding: 6px 0; border-bottom: 1px solid #eee; font-size: 10pt; }
.rec-card:last-child { border-bottom: none; }
.rec-card .ingredient { font-weight: 600; }
.rec-card .dosage { color: var(--accent); font-size: 9pt; padding-left: 8px; }
.rec-card .rationale { color: var(--muted); font-size: 9pt; padding-left: 8px; }
.ai-full-text { font-size: 10pt; line-height: 1.6; white-space: pre-wrap; color: var(--text); }

/* Methodology */
.methodology-list { font-size: 10pt; color: var(--muted); padding-left: 20px; }
.methodology-list li { margin: 2px 0; }

/* Divider */
.divider { border: none; border-top: 1px solid var(--border); margin: 20px 0; }

/* Footer */
.report-footer { text-align: center; font-size: 9pt; color: var(--muted); padding: 16px 0; border-top: 1px solid var(--border); margin-top: 32px; }

/* Print styles */
@media print {
  @page { size: A4; margin: 18mm; }
  body { font-size: 10pt; }
  .page { max-width: none; padding: 0; }
  .title-page { page-break-after: always; padding: 120px 0 60px; border-bottom: none; }
  .toc { page-break-after: always; }
  .report-section { page-break-inside: avoid; }
  .chart-container { page-break-inside: avoid; }
  .spf-callout { page-break-inside: avoid; }
}
</style>
</head>
<body>
<div class=\"page\">

  <!-- Title Page -->
  <div class=\"title-page\">
    <div class=\"app-name\">SPF Spectral Analyzer</div>
    <h1>\(htmlEscape(title))</h1>
    <div class=\"rule\"></div>
    <div class=\"date\">\(htmlEscape(dateString))</div>
\(metadataLines.prefix(5).map { "    <div class=\"meta-line\">\(htmlEscape($0))</div>" }.joined(separator: "\n"))
  </div>

  <!-- Table of Contents -->
  <nav class=\"toc\">
    <h2>Table of Contents</h2>
    \(tocEntries)
  </nav>

  <!-- Section 1: Results -->
  <section id=\"results\" class=\"report-section\">
    <h2>1. Results</h2>
    \(spfCalloutHTML)
    <h3>Key Metrics</h3>
    \(metricsTableHTML)
  </section>

  <hr class=\"divider\">

  <!-- Section 2: Spectra -->
  <section id=\"spectra\" class=\"report-section\">
    <h2>2. Spectra</h2>
    \(chartSVG)
    \(legendHTML)
  </section>

  <hr class=\"divider\">

  <!-- Section 3: AI Analysis -->
\(hasAIContent ? """
  <section id=\"ai-analysis\" class=\"report-section\">
    <h2>3. AI Analysis</h2>
    \(aiSectionHTML)
  </section>

  <hr class=\"divider\">
""" : """
  <section id=\"ai-analysis\" class=\"report-section\">
    <h2>3. AI Analysis</h2>
    <p style=\"color: var(--muted); font-size: 10pt;\">No AI output available.</p>
  </section>

  <hr class=\"divider\">
""")

  <!-- Section \(methodSectionNum): Methodology -->
\(!metadataLines.isEmpty ? """
  <section id=\"methodology\" class=\"report-section\">
    <h2>\(methodSectionNum). Methodology</h2>
    <ul class=\"methodology-list\">
      \(methodologyHTML)
    </ul>
  </section>
""" : "")

  <div class=\"report-footer\">SPF Spectral Analyzer &mdash; Generated \(htmlEscape(dateString))</div>

</div>
</body>
</html>
"""
    }

    // MARK: - HTML Report Component Builders

    private func buildHTMLSPFCallout(estimation: SPFEstimationResult?) -> String {
        guard let estimation else { return "" }
        let tierClass = "tier-\(estimation.tier.rawValue)"
        let rawHTML: String
        if let raw = estimation.rawColipaValue {
            rawHTML = "<span class=\"spf-raw\">Raw COLIPA: \(String(format: "%.2f", raw))</span>"
        } else {
            rawHTML = ""
        }
        return """
        <div class=\"spf-callout \(tierClass)\">
          <span class=\"spf-value\">SPF: \(String(format: "%.1f", estimation.value))</span>
          <span class=\"spf-tier\">\(htmlEscape(estimation.tier.label))</span>
          \(rawHTML)
        </div>
        """
    }

    private func buildHTMLMetricsTable(rows: [ReportMetricRow]) -> String {
        guard !rows.isEmpty else {
            return "<p style=\"color: var(--muted); font-size: 10pt;\">No metrics available.</p>"
        }
        var html = """
        <table class=\"metrics-table\">
          <thead><tr><th>Metric</th><th>Value</th></tr></thead>
          <tbody>
        """
        for row in rows {
            html += "      <tr><td class=\"label\">\(htmlEscape(row.label))</td><td class=\"value\">\(htmlEscape(row.value))</td></tr>\n"
        }
        html += "    </tbody>\n    </table>"
        return html
    }

    private func buildHTMLSpectraChart(series: [ReportSpectrumSeries]) -> String {
        guard !series.isEmpty else {
            return "<p style=\"color: var(--muted); font-size: 10pt;\">No spectra available.</p>"
        }

        let svgWidth: Double = 720
        let svgHeight: Double = 320
        let pad = (left: 56.0, right: 18.0, top: 18.0, bottom: 42.0)
        let chartW = svgWidth - pad.left - pad.right
        let chartH = svgHeight - pad.top - pad.bottom

        // Compute bounds
        var xMin = Double.greatestFiniteMagnitude, xMax = -Double.greatestFiniteMagnitude
        var yMin = Double.greatestFiniteMagnitude, yMax = -Double.greatestFiniteMagnitude
        for s in series {
            for p in s.points {
                xMin = min(xMin, p.x); xMax = max(xMax, p.x)
                yMin = min(yMin, p.y); yMax = max(yMax, p.y)
            }
        }
        guard xMax > xMin, yMax > yMin else {
            return "<p style=\"color: var(--muted);\">Insufficient data for chart.</p>"
        }
        let xPad = (xMax - xMin) * 0.05
        let yPadding = (yMax - yMin) * 0.05
        xMin -= xPad; xMax += xPad; yMin -= yPadding; yMax += yPadding

        func sx(_ x: Double) -> Double { pad.left + (x - xMin) / (xMax - xMin) * chartW }
        func sy(_ y: Double) -> Double { pad.top + (1.0 - (y - yMin) / (yMax - yMin)) * chartH }

        let palette = ["#3366B2", "#CC3333", "#339933", "#CC8833", "#9933CC", "#1199AA"]

        // Build SVG
        var svg = "<div class=\"chart-container\"><svg viewBox=\"0 0 \(Int(svgWidth)) \(Int(svgHeight))\" xmlns=\"http://www.w3.org/2000/svg\">\n"

        // Grid lines
        let xTicks = niceHTMLTicks(min: xMin, max: xMax, count: 8)
        let yTicks = niceHTMLTicks(min: yMin, max: yMax, count: 5)
        svg += "  <g stroke=\"#e0e0e0\" stroke-width=\"0.5\">\n"
        for t in xTicks { svg += "    <line x1=\"\(sx(t))\" y1=\"\(pad.top)\" x2=\"\(sx(t))\" y2=\"\(pad.top + chartH)\"/>\n" }
        for t in yTicks { svg += "    <line x1=\"\(pad.left)\" y1=\"\(sy(t))\" x2=\"\(pad.left + chartW)\" y2=\"\(sy(t))\"/>\n" }
        svg += "  </g>\n"

        // Axes
        svg += "  <g stroke=\"#333\" stroke-width=\"1\">\n"
        svg += "    <line x1=\"\(pad.left)\" y1=\"\(pad.top)\" x2=\"\(pad.left)\" y2=\"\(pad.top + chartH)\"/>\n"
        svg += "    <line x1=\"\(pad.left)\" y1=\"\(pad.top + chartH)\" x2=\"\(pad.left + chartW)\" y2=\"\(pad.top + chartH)\"/>\n"
        svg += "  </g>\n"

        // Axis labels
        svg += "  <g fill=\"#666\" font-size=\"8\" font-family=\"-apple-system, system-ui, sans-serif\">\n"
        for t in xTicks {
            svg += "    <text x=\"\(sx(t))\" y=\"\(pad.top + chartH + 14)\" text-anchor=\"middle\">\(String(format: "%.0f", t))</text>\n"
        }
        for t in yTicks {
            svg += "    <text x=\"\(pad.left - 6)\" y=\"\(sy(t) + 3)\" text-anchor=\"end\">\(String(format: "%.2f", t))</text>\n"
        }
        svg += "  </g>\n"

        // Axis titles
        svg += "  <text x=\"\(pad.left + chartW / 2)\" y=\"\(svgHeight - 4)\" text-anchor=\"middle\" fill=\"#444\" font-size=\"9\" font-weight=\"600\" font-family=\"-apple-system, system-ui, sans-serif\">Wavelength (nm)</text>\n"
        svg += "  <text x=\"12\" y=\"\(pad.top + chartH / 2)\" text-anchor=\"middle\" fill=\"#444\" font-size=\"9\" font-weight=\"600\" font-family=\"-apple-system, system-ui, sans-serif\" transform=\"rotate(-90, 12, \(pad.top + chartH / 2))\">Intensity</text>\n"

        // Series polylines
        for (si, s) in series.enumerated() {
            guard s.points.count >= 2 else { continue }
            let color = palette[si % palette.count]
            let pointsStr = s.points.map { "\(String(format: "%.1f", sx($0.x))),\(String(format: "%.1f", sy($0.y)))" }.joined(separator: " ")
            svg += "  <polyline points=\"\(pointsStr)\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"1.2\"/>\n"
        }

        svg += "</svg></div>"
        return svg
    }

    private func niceHTMLTicks(min: Double, max: Double, count: Int) -> [Double] {
        let span = max - min
        guard span > 0 else { return [min, max] }
        let step0 = pow(10, floor(log10(span / Double(Swift.max(1, count)))))
        let step = [1, 2, 5, 10].first(where: { span / (step0 * $0) <= Double(count) }).map { step0 * $0 } ?? step0
        let t0 = ceil(min / step) * step
        var ticks: [Double] = []
        var t = t0
        while t <= max + 1e-9 {
            ticks.append(t)
            t += step
        }
        return ticks
    }

    private func buildHTMLLegend(series: [ReportSpectrumSeries]) -> String {
        guard !series.isEmpty else { return "" }
        let palette = ["#3366B2", "#CC3333", "#339933", "#CC8833", "#9933CC", "#1199AA"]
        var html = "<div class=\"legend\">\n"
        for (si, s) in series.enumerated() {
            let color = palette[si % palette.count]
            html += "  <div class=\"legend-item\"><div class=\"legend-swatch\" style=\"background:\(color)\"></div>\(htmlEscape(s.name))</div>\n"
        }
        html += "</div>"
        return html
    }

    private func buildHTMLAISection(
        aiSummary: String, aiFullText: String,
        insights: [String], risks: [String], actions: [String],
        recommendations: [AIRecommendation],
        hasStructuredContent: Bool
    ) -> String {
        var html = ""

        // Summary (only if no structured content)
        if !aiSummary.isEmpty, !hasStructuredContent {
            html += """
            <div class=\"ai-subsection\">
              <h3>Summary</h3>
              <p style=\"font-size: 10pt;\">\(htmlEscape(aiSummary))</p>
            </div>
            """
        }

        // Key Insights
        if !insights.isEmpty {
            html += "    <div class=\"ai-subsection\">\n      <h3>Key Insights</h3>\n      <ul class=\"bullet-list insights\">\n"
            for item in insights { html += "        <li>\(htmlEscape(item))</li>\n" }
            html += "      </ul>\n    </div>\n"
        }

        // Risks & Concerns
        if !risks.isEmpty {
            html += "    <div class=\"ai-subsection\">\n      <h3>Risks &amp; Concerns</h3>\n      <ul class=\"bullet-list risks\">\n"
            for item in risks { html += "        <li>\(htmlEscape(item))</li>\n" }
            html += "      </ul>\n    </div>\n"
        }

        // Recommended Actions
        if !actions.isEmpty {
            html += "    <div class=\"ai-subsection\">\n      <h3>Recommended Actions</h3>\n      <ul class=\"bullet-list actions\">\n"
            for item in actions { html += "        <li>\(htmlEscape(item))</li>\n" }
            html += "      </ul>\n    </div>\n"
        }

        // Formulation Recommendations
        if !recommendations.isEmpty {
            html += "    <div class=\"ai-subsection\">\n      <h3>Formulation Recommendations</h3>\n"
            for rec in recommendations {
                html += "      <div class=\"rec-card\">\n"
                html += "        <div class=\"ingredient\">\(htmlEscape(rec.ingredient))</div>\n"
                if !rec.amount.isEmpty {
                    html += "        <div class=\"dosage\">Dosage: \(htmlEscape(rec.amount))</div>\n"
                }
                if let rationale = rec.rationale, !rationale.isEmpty {
                    html += "        <div class=\"rationale\">\(htmlEscape(rationale))</div>\n"
                }
                html += "      </div>\n"
            }
            html += "    </div>\n"
        }

        // Full AI text (when no structured content and text differs from summary)
        if !hasStructuredContent, !aiFullText.isEmpty, aiFullText != aiSummary {
            html += """
            <hr class=\"divider\">
            <div class=\"ai-subsection\">
              <h3>Detailed Analysis</h3>
              <div class=\"ai-full-text\">\(htmlEscape(aiFullText))</div>
            </div>
            """
        }

        return html
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

        // Use LTTB for visually superior downsampling
        let downsampled = CacheComputationService.lttbDownsample(points, to: targetCount)
        return downsampled.map { ReportSpectrumPoint(x: $0.x, y: $0.y) }
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

    /// Build a formatted shareable text report with ASCII metrics table.
    func buildShareableTextReport() -> String {
        let divider = String(repeating: "─", count: 48)
        var lines: [String] = []

        lines.append("╔══════════════════════════════════════════════╗")
        lines.append("║   SPF Spectral Analysis Report               ║")
        lines.append("╚══════════════════════════════════════════════╝")
        lines.append("")
        lines.append("Date: \(DateFormatter.localizedString(from: Date(), dateStyle: .medium, timeStyle: .short))")
        if !exportTitle.isEmpty { lines.append("Title: \(exportTitle)") }
        if !exportOperator.isEmpty { lines.append("Operator: \(exportOperator)") }
        lines.append("")

        // Metrics table
        lines.append(divider)
        lines.append("  KEY METRICS")
        lines.append(divider)

        if let metrics = analysis.selectedMetrics {
            lines.append(String(format: "  Critical λ:       %7.1f nm", metrics.criticalWavelength))
            lines.append(String(format: "  UVA/UVB Ratio:    %7.3f", metrics.uvaUvbRatio))
            lines.append(String(format: "  Mean UVB T%%:      %7.3f", metrics.meanUVBTransmittance))
        }
        if let colipa = analysis.colipaSpfValue {
            lines.append(String(format: "  COLIPA SPF:       %7.1f", colipa))
        }
        if let estimated = analysis.estimatedSpfValue {
            lines.append(String(format: "  Estimated SPF:    %7.1f", estimated))
        }
        lines.append(divider)
        lines.append("")

        // Spectra list
        lines.append("  LOADED SPECTRA (\(displayedSpectra.count))")
        lines.append(divider)
        for (i, spectrum) in displayedSpectra.enumerated() {
            let prefix = i < 9 ? " \(i + 1)" : "\(i + 1)"
            lines.append("  \(prefix). \(spectrum.name)")
        }
        lines.append("")

        // AI summary excerpt
        if let aiResult = aiVM.result {
            lines.append(divider)
            lines.append("  AI ANALYSIS SUMMARY")
            lines.append(divider)
            let excerpt = String(aiResult.text.prefix(500))
            lines.append(excerpt)
            if aiResult.text.count > 500 { lines.append("  [... truncated]") }
        }

        lines.append("")
        lines.append("Generated by SPF Spectral Analyzer")

        return lines.joined(separator: "\n")
    }

    func exportPeaksCSV() {
        guard !analysis.peaks.isEmpty else {
            analysis.errorMessage = "No peaks detected in the UV range."
            return
        }

        let started = Date()
        Instrumentation.log("Export Peaks CSV started", area: .export, level: .info, details: "peaks=\(analysis.peaks.count)")

        var lines: [String] = []
        lines.append("Wavelength,Intensity")
        for peak in analysis.peaks {
            lines.append(String(format: "%.6f,%.6f", peak.x, peak.y))
        }
        let csvContent = lines.joined(separator: "\n")

        #if os(iOS)
        // On iOS, write to temp file and share via activity sheet
        let tempDir = FileManager.default.temporaryDirectory
        let tempURL = tempDir.appendingPathComponent(timestampedFileName("Peaks.csv"))
        do {
            try csvContent.write(to: tempURL, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export Peaks CSV completed", area: .export, level: .info, duration: duration)
            guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let window = scene.windows.first,
                  let rootVC = window.rootViewController else { return }
            let activityVC = UIActivityViewController(activityItems: [tempURL], applicationActivities: nil)
            activityVC.popoverPresentationController?.sourceView = window
            activityVC.popoverPresentationController?.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
            rootVC.present(activityVC, animated: true)
        } catch {
            Instrumentation.log("Export Peaks CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export peaks CSV: \(error.localizedDescription)"
        }
        #else
        guard let url = savePanel(defaultName: "Peaks.csv", allowedTypes: [UTType.commaSeparatedText], directoryKey: .analysisExports) else { return }
        do {
            try csvContent.write(to: url, atomically: true, encoding: .utf8)
            let duration = Date().timeIntervalSince(started)
            Instrumentation.log("Export Peaks CSV completed", area: .export, level: .info, duration: duration)
        } catch {
            Instrumentation.log("Export Peaks CSV failed", area: .export, level: .error, details: "error=\(error.localizedDescription)")
            analysis.errorMessage = "Failed to export peaks CSV: \(error.localizedDescription)"
        }
        #endif
    }

    // MARK: - Quick Open (Auto-Save + Open)

    /// Auto-save CSV to last-used directory and open it.
    func openCSV(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }

        var lines: [String] = []
        if options.includeMetadata {
            lines.append("# Title: \(options.title)")
            lines.append("# Operator: \(options.operatorName)")
            lines.append("# Notes: \(options.notes)")
        }
        var header = ["Wavelength (\(analysis.yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { sanitizeCSVField($0.name) })
        lines.append(header.joined(separator: ","))
        for i in 0..<first.x.count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            lines.append(row.joined(separator: ","))
        }

        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Spectra.csv"))
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open CSV: \(error.localizedDescription)"
        }
    }

    /// Auto-save JCAMP to last-used directory and open it.
    func openJCAMP(options: ExportOptions) {
        let spectraToExport = alignedForExport()

        var output = "##JCAMP-DX=5.00\n##DATA TYPE=UV/VIS SPECTRUM\n"
        if options.includeMetadata {
            if !options.title.isEmpty { output += "##TITLE=\(options.title)\n" }
            if !options.operatorName.isEmpty { output += "##OWNER=\(options.operatorName)\n" }
        }
        for spectrum in spectraToExport {
            output += "##TITLE=\(spectrum.name)\n"
            output += "##NPOINTS=\(spectrum.x.count)\n"
            output += "##XYDATA= (X++(Y..Y))\n"
            for i in 0..<spectrum.x.count {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                output += String(format: "%.6f, %.6f\n", spectrum.x[i], yVal)
            }
            output += "##END=\n"
        }

        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Spectra.jdx"))
        do {
            try output.write(to: url, atomically: true, encoding: .utf8)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open JCAMP: \(error.localizedDescription)"
        }
    }

    /// Auto-save Excel to last-used directory and open it.
    func openExcelXLSX(options: ExportOptions) {
        let spectraToExport = alignedForExport()
        guard let first = spectraToExport.first else { return }

        var header = ["Wavelength (\(analysis.yAxisMode.rawValue))"]
        header.append(contentsOf: spectraToExport.map { $0.name })
        var rows: [[String]] = []
        for i in 0..<first.x.count {
            var row = [String(format: "%.6f", first.x[i])]
            for spectrum in spectraToExport {
                let yVal = i < spectrum.y.count ? spectrum.y[i] : 0.0
                row.append(String(format: "%.6f", yVal))
            }
            rows.append(row)
        }

        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Spectra.xlsx"))
        do {
            try OOXMLWriter.writeXlsx(header: header, rows: rows, to: url)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open XLSX: \(error.localizedDescription)"
        }
    }

    /// Auto-save Word report to last-used directory and open it.
    func openWordDOCX(options: ExportOptions) {
        let report = buildAnalysisReport(options: options)
        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Analysis Report.docx"))
        do {
            try OOXMLWriter.writeDocx(report: report, to: url)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open DOCX: \(error.localizedDescription)"
        }
    }

    /// Auto-save PDF report to last-used directory and open it.
    func openPDFReport(options: ExportOptions) {
        let reportData = buildPDFReportData(options: options)
        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Analysis Report.pdf"))
        Task { @MainActor in
            let data = PDFReportRenderer.render(data: reportData)
            do {
                try data.write(to: url)
                storeLastSaveDirectory(from: url, key: .analysisExports)
                PlatformURLOpener.open(url)
            } catch {
                analysis.errorMessage = "Failed to open PDF: \(error.localizedDescription)"
            }
        }
    }

    /// Auto-save HTML report to last-used directory and open it.
    func openHTMLReport(options: ExportOptions) {
        let html = buildHTMLReport(options: options)
        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Analysis Report.html"))
        do {
            try html.write(to: url, atomically: true, encoding: .utf8)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open HTML: \(error.localizedDescription)"
        }
    }

    /// Auto-save peaks CSV to last-used directory and open it.
    func openPeaksCSV() {
        guard !analysis.peaks.isEmpty else { return }

        var lines: [String] = ["Wavelength,Intensity"]
        for peak in analysis.peaks {
            lines.append(String(format: "%.6f,%.6f", peak.x, peak.y))
        }

        let dir = autoSaveDirectoryURL(for: .analysisExports)
        let url = dir.appendingPathComponent(timestampedFileName("Peaks.csv"))
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            storeLastSaveDirectory(from: url, key: .analysisExports)
            PlatformURLOpener.open(url)
        } catch {
            analysis.errorMessage = "Failed to open peaks CSV: \(error.localizedDescription)"
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
