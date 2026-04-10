import Foundation
import SwiftData

public struct HTMLReportWriter {
    public struct Options {
        public var title: String
        public var operatorName: String?
        public var notes: String?
        public var includeLegend: Bool
        public var width: Int
        public var height: Int

        public init(
            title: String,
            operatorName: String? = nil,
            notes: String? = nil,
            includeLegend: Bool = true,
            width: Int = 1200,
            height: Int = 520
        ) {
            self.title = title
            self.operatorName = operatorName
            self.notes = notes
            self.includeLegend = includeLegend
            self.width = width
            self.height = height
        }
    }

    /// Value-type snapshot of a dataset for report generation.
    /// Captures all needed properties in a single synchronous pass so that
    /// no SwiftData model objects are accessed after snapshot creation.
    public struct DatasetSnapshot {
        public let fileName: String
        public let spectra: [SpectrumSnapshot]
    }

    public struct SpectrumSnapshot {
        public let name: String
        public let orderIndex: Int
        public let xValues: [Double]
        public let yValues: [Double]
    }

    /// Snapshots all datasets and their spectra from live model objects.
    /// Call this once while models are known to be valid, then pass the
    /// snapshots to `writeHTMLReport(snapshots:options:to:)`.
    @MainActor public static func snapshotDatasets(_ datasets: [StoredDataset]) -> [DatasetSnapshot] {
        datasets.compactMap { dataset -> DatasetSnapshot? in
            guard dataset.modelContext != nil else { return nil }
            let fileName = dataset.fileName
            let spectraItems = dataset.spectraItems
            let spectra = spectraItems
                .sorted { $0.orderIndex < $1.orderIndex }
                .compactMap { spectrum -> SpectrumSnapshot? in
                    guard spectrum.modelContext != nil else { return nil }
                    let x = spectrum.xValues
                    let y = spectrum.yValues
                    guard x.count == y.count, !x.isEmpty else { return nil }
                    return SpectrumSnapshot(name: spectrum.name, orderIndex: spectrum.orderIndex, xValues: x, yValues: y)
                }
            return DatasetSnapshot(fileName: fileName, spectra: spectra)
        }
    }

    @MainActor public static func writeHTMLReport(
        datasets: [StoredDataset],
        options: Options,
        to url: URL
    ) throws {
        // Snapshot upfront to avoid touching models during HTML generation
        let snapshots = snapshotDatasets(datasets)
        try writeHTMLReport(snapshots: snapshots, options: options, to: url)
    }

    public static func writeHTMLReport(
        snapshots: [DatasetSnapshot],
        options: Options,
        to url: URL
    ) throws {
        let html = buildHTML(snapshots: snapshots, options: options)
        try html.data(using: .utf8)?.write(to: url, options: .atomic)
    }

    // MARK: - HTML Builder

    private static func buildHTML(snapshots: [DatasetSnapshot], options: Options) -> String {
        let now = ISO8601DateFormatter().string(from: Date())
        let title = htmlEscaped(options.title)
        let operatorLine = options.operatorName.map { "<div class=\"meta\"><strong>Operator:</strong> \(htmlEscaped($0))</div>" } ?? ""
        let notesBlock: String = {
            guard let notes = options.notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "" }
            let escaped = htmlEscaped(notes)
            return """
            <section class=\"notes\">
              <h2>Notes</h2>
              <div class=\"notes-body\">\(escaped.replacingOccurrences(of: "\n", with: "<br>"))</div>
            </section>
            """
        }()

        let jsData = makeJSData(snapshots: snapshots)
        let legendBlock = options.includeLegend ? "<div id=\"legend\"></div>" : ""

        return """
<!doctype html>
<html>
<head>
  <meta charset=\"utf-8\">
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">
  <title>\(title)</title>
  <style>
    :root {
      --bg: #0b0d12;
      --panel: #111620;
      --panel2: #0e1320;
      --text: #e9eef7;
      --muted: #9aa7bd;
      --accent: #7aa2ff;
      --accent2: #30d158;
      --grid: #1b2332;
      --legend-bg: #0f1422;
    }
    html, body { margin: 0; padding: 0; background: var(--bg); color: var(--text); font-family: -apple-system, system-ui, Segoe UI, Roboto, Helvetica, Arial, sans-serif; }
    header { padding: 20px 24px; background: linear-gradient(180deg, rgba(122,162,255,0.08), rgba(0,0,0,0)); position: sticky; top: 0; z-index: 1; }
    header h1 { margin: 0; font-size: 22px; font-weight: 600; }
    header .meta { margin-top: 8px; font-size: 13px; color: var(--muted); }
    .kpis { display: grid; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); gap: 12px; padding: 16px 24px; }
    .kpi { background: var(--panel); border-radius: 12px; padding: 12px 14px; box-shadow: 0 1px 0 rgba(255,255,255,0.04) inset, 0 1px 12px rgba(0,0,0,0.3); }
    .kpi .label { font-size: 12px; color: var(--muted); }
    .kpi .value { font-size: 20px; font-weight: 600; margin-top: 4px; }
    .chart-panel { background: var(--panel2); border-radius: 14px; padding: 14px; margin: 8px 24px 24px; box-shadow: 0 1px 0 rgba(255,255,255,0.04) inset, 0 1px 16px rgba(0,0,0,0.35); }
    .chart-title { font-size: 14px; color: var(--muted); margin: 0 0 8px; }
    canvas { display: block; width: 100%; height: auto; background: #0b0f1a; border-radius: 10px; }
    #legend { margin: 0 24px 24px; background: var(--legend-bg); border-radius: 12px; padding: 10px 12px; display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 8px; }
    .legend-item { display: flex; align-items: center; gap: 8px; font-size: 12px; color: var(--muted); }
    .swatch { width: 14px; height: 14px; border-radius: 3px; }
    .notes { margin: 0 24px 24px; background: var(--panel); border-radius: 12px; padding: 12px 14px; }
    .notes h2 { margin: 0 0 6px; font-size: 15px; }
    .notes-body { font-size: 13px; color: var(--text); }
    footer { padding: 16px 24px; font-size: 12px; color: var(--muted); }
    .toc { margin: 0 24px 24px; background: var(--panel); border-radius: 12px; padding: 14px 18px; }
    .toc h2 { margin: 0 0 10px; font-size: 15px; color: var(--accent); }
    .toc-item { display: flex; justify-content: space-between; padding: 4px 0; font-size: 13px; border-bottom: 1px solid var(--grid); }
    .toc-item:last-child { border-bottom: none; }
    .toc-item a { color: var(--accent); text-decoration: none; }
    .toc-item a:hover { text-decoration: underline; }
    .toc-item .desc { color: var(--muted); font-size: 12px; }
    .report-section { scroll-margin-top: 80px; }
    .report-section h2 { font-size: 18px; font-weight: 600; margin: 0 0 12px; padding-bottom: 6px; border-bottom: 2px solid var(--accent); color: var(--accent); }
    @media print {
      @page { size: A4; margin: 20mm; }
      @page { @bottom-center { content: counter(page) " of " counter(pages); font-size: 10px; color: #666; } }
      body { background: white; color: black; font-size: 11pt; }
      header { position: static; background: none; }
      header h1 { color: black; }
      .meta { color: #666; }
      .kpi { box-shadow: none; border: 1px solid #ddd; background: #fafafa; }
      .kpi .value { color: black; }
      .chart-panel { box-shadow: none; border: 1px solid #ddd; background: white; page-break-inside: avoid; }
      canvas { background: white !important; }
      .toc { border: 1px solid #ddd; background: #fafafa; page-break-after: always; }
      .toc h2, .report-section h2 { color: #2255aa; border-color: #2255aa; }
      .toc-item a { color: #2255aa; }
      #legend { border: 1px solid #ddd; background: #fafafa; }
      .legend-item { color: #333; }
      .notes { border: 1px solid #ddd; background: #fafafa; }
      footer { color: #999; }
    }
  </style>
</head>
<body>
  <header>
    <h1>\(title)</h1>
    <div class=\"meta\"><strong>Generated:</strong> \(now)</div>
    \(operatorLine)
  </header>

  <section class=\"toc\">
    <h2>Table of Contents</h2>
    <div class=\"toc-item\"><a href=\"#results\">1. Results</a><span class=\"desc\">Key metrics and compliance</span></div>
    <div class=\"toc-item\"><a href=\"#spectra\">2. Spectra</a><span class=\"desc\">UV spectral overlay chart</span></div>
    \(notesBlock.isEmpty ? "" : "<div class=\"toc-item\"><a href=\"#notes\">3. Notes</a><span class=\"desc\">Operator notes and observations</span></div>")
  </section>

  <section id=\"results\" class=\"report-section\" style=\"padding: 0 24px 16px;\">
    <h2>1. Results</h2>
    <div class=\"kpis\" style=\"padding: 0;\">
      <div class=\"kpi\"><div class=\"label\">Datasets</div><div class=\"value\" id=\"kpi-datasets\">-</div></div>
      <div class=\"kpi\"><div class=\"label\">Spectra</div><div class=\"value\" id=\"kpi-spectra\">-</div></div>
      <div class=\"kpi\"><div class=\"label\">X Range</div><div class=\"value\" id=\"kpi-xrange\">-</div></div>
      <div class=\"kpi\"><div class=\"label\">Y Range</div><div class=\"value\" id=\"kpi-yrange\">-</div></div>
    </div>
  </section>

  <section id=\"spectra\" class=\"report-section\">
    <div class=\"chart-panel\">
      <p class=\"chart-title\">2. Spectra — Overlaid</p>
      <canvas id=\"chart\" width=\(options.width) height=\(options.height)></canvas>
    </div>
  </section>

  \(legendBlock)
  \(notesBlock.isEmpty ? "" : "<section id=\"notes\" class=\"report-section\">\(notesBlock)</section>")

  <footer>SPF Spectral Analyzer — Self-contained HTML report • All graphics rendered client-side</footer>

  <script>
  // Embedded report data (spectra + metadata)
  const REPORT = \(jsData);

  // Small helper to format numbers
  function fmt(v, p=2) { return (typeof v === 'number' && isFinite(v)) ? v.toFixed(p) : '-'; }

  // Compute global extents
  function computeExtents(report) {
    let minX = +Infinity, maxX = -Infinity, minY = +Infinity, maxY = -Infinity;
    let spectraCount = 0;
    for (const ds of report.datasets) {
      for (const sp of ds.spectra) {
        spectraCount++;
        for (let i = 0; i < sp.x.length; i++) {
          const x = sp.x[i];
          const y = sp.y[i];
          if (x < minX) minX = x; if (x > maxX) maxX = x;
          if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
      }
    }
    if (!isFinite(minX)) { minX = 0; maxX = 1; }
    if (!isFinite(minY)) { minY = 0; maxY = 1; }
    if (minX === maxX) maxX = minX + 1;
    if (minY === maxY) maxY = minY + 1;
    return { minX, maxX, minY, maxY, spectraCount };
  }

  function niceTicks(min, max, count) {
    const span = max - min;
    if (span <= 0) return { step: 1, ticks: [min, max] };
    const step0 = Math.pow(10, Math.floor(Math.log10(span / Math.max(1, count))));
    const step = step0 * [1, 2, 5, 10].find(m => span / (step0 * m) <= count) || step0;
    const t0 = Math.ceil(min / step) * step;
    const ticks = [];
    for (let t = t0; t <= max + 1e-9; t += step) ticks.push(t);
    return { step, ticks };
  }

  function colorFor(index) {
    const palette = [
      '#7aa2ff', '#30d158', '#ff9f0a', '#ff375f', '#64d2ff', '#bf5af2', '#ffd60a', '#ff6b6b', '#34c759', '#0a84ff'
    ];
    return palette[index % palette.length];
  }

  function drawChart(canvas, report) {
    const ctx = canvas.getContext('2d');
    const P = { l: 56, r: 18, t: 18, b: 42 };
    const W = canvas.width, H = canvas.height;
    ctx.clearRect(0,0,W,H);

    const { minX, maxX, minY, maxY } = computeExtents(report);
    const sx = x => P.l + (x - minX) * (W - P.l - P.r) / (maxX - minX);
    const sy = y => H - P.b - (y - minY) * (H - P.t - P.b) / (maxY - minY);

    // Grid
    ctx.strokeStyle = getComputedStyle(document.documentElement).getPropertyValue('--grid');
    ctx.lineWidth = 1;
    const xt = niceTicks(minX, maxX, 8).ticks;
    const yt = niceTicks(minY, maxY, 5).ticks;
    ctx.beginPath();
    for (const x of xt) { const X = Math.round(sx(x)) + 0.5; ctx.moveTo(X, P.t); ctx.lineTo(X, H - P.b); }
    for (const y of yt) { const Y = Math.round(sy(y)) + 0.5; ctx.moveTo(P.l, Y); ctx.lineTo(W - P.r, Y); }
    ctx.stroke();

    // Axes
    ctx.strokeStyle = 'rgba(255,255,255,0.65)';
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(P.l, P.t); ctx.lineTo(P.l, H - P.b); // Y
    ctx.moveTo(P.l, H - P.b); ctx.lineTo(W - P.r, H - P.b); // X
    ctx.stroke();

    // Axis labels
    ctx.fillStyle = 'rgba(255,255,255,0.8)';
    ctx.font = '12px -apple-system, system-ui, Segoe UI, Roboto, Helvetica, Arial, sans-serif';
    ctx.textAlign = 'center'; ctx.textBaseline = 'top';
    for (const x of xt) { const X = sx(x); ctx.fillText(fmt(x), X, H - P.b + 6); }
    ctx.textAlign = 'right'; ctx.textBaseline = 'middle';
    for (const y of yt) { const Y = sy(y); ctx.fillText(fmt(y), P.l - 8, Y); }

    // Series
    let seriesIndex = 0;
    for (const ds of report.datasets) {
      for (const sp of ds.spectra) {
        const color = colorFor(seriesIndex++);
        ctx.strokeStyle = color;
        ctx.lineWidth = 1.6;
        ctx.beginPath();
        let moved = false;
        for (let i = 0; i < sp.x.length; i++) {
          const X = sx(sp.x[i]);
          const Y = sy(sp.y[i]);
          if (!moved) { ctx.moveTo(X, Y); moved = true; }
          else { ctx.lineTo(X, Y); }
        }
        ctx.stroke();
      }
    }
  }

  function populateKPIs(report) {
    const counts = { datasets: report.datasets.length, spectra: 0 };
    let minX=+Infinity, maxX=-Infinity, minY=+Infinity, maxY=-Infinity;
    for (const ds of report.datasets) {
      for (const sp of ds.spectra) {
        counts.spectra++;
        for (let i=0; i<sp.x.length; i++) {
          const x=sp.x[i], y=sp.y[i];
          if (x < minX) minX = x; if (x > maxX) maxX = x;
          if (y < minY) minY = y; if (y > maxY) maxY = y;
        }
      }
    }
    if (!isFinite(minX)) { minX = 0; maxX = 1; }
    if (!isFinite(minY)) { minY = 0; maxY = 1; }
    document.getElementById('kpi-datasets').textContent = counts.datasets.toString();
    document.getElementById('kpi-spectra').textContent = counts.spectra.toString();
    document.getElementById('kpi-xrange').textContent = `${fmt(minX)} – ${fmt(maxX)}`;
    document.getElementById('kpi-yrange').textContent = `${fmt(minY)} – ${fmt(maxY)}`;
  }

  function populateLegend(report) {
    const host = document.getElementById('legend');
    if (!host) return;
    host.innerHTML = '';
    let seriesIndex = 0;
    for (const ds of report.datasets) {
      for (const sp of ds.spectra) {
        const color = colorFor(seriesIndex++);
        const item = document.createElement('div');
        item.className = 'legend-item';
        const sw = document.createElement('div'); sw.className = 'swatch'; sw.style.background = color; item.appendChild(sw);
        const label = document.createElement('div');
        label.textContent = `${ds.fileName} – ${sp.name}`;
        item.appendChild(label);
        host.appendChild(item);
      }
    }
  }

  (function main(){
    const canvas = document.getElementById('chart');
    populateKPIs(REPORT);
    populateLegend(REPORT);
    drawChart(canvas, REPORT);
    // Handle HiDPI rendering crisply
    const dpr = Math.max(1, window.devicePixelRatio || 1);
    const rect = canvas.getBoundingClientRect();
    if (Math.abs(canvas.width - rect.width * dpr) > 1 || Math.abs(canvas.height - rect.height * dpr) > 1) {
      canvas.width = Math.round(rect.width * dpr);
      canvas.height = Math.round(rect.height * dpr);
      drawChart(canvas, REPORT);
    }
    window.addEventListener('resize', () => {
      const r = canvas.getBoundingClientRect();
      canvas.width = Math.round(r.width * dpr);
      canvas.height = Math.round(r.height * dpr);
      drawChart(canvas, REPORT);
    });
  })();
  </script>
</body>
</html>
"""
    }

    private static func makeJSData(snapshots: [DatasetSnapshot]) -> String {
        struct SpectrumDTO: Encodable { let name: String; let x: [Double]; let y: [Double] }
        struct DatasetDTO: Encodable { let fileName: String; let spectra: [SpectrumDTO] }
        struct ReportDTO: Encodable { let datasets: [DatasetDTO] }

        var payload: [DatasetDTO] = []
        payload.reserveCapacity(snapshots.count)
        for ds in snapshots {
            let spectraDTO = ds.spectra.map { sp in
                SpectrumDTO(name: sp.name, x: sp.xValues, y: sp.yValues)
            }
            payload.append(DatasetDTO(fileName: ds.fileName, spectra: spectraDTO))
        }

        let report = ReportDTO(datasets: payload)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        let data = (try? encoder.encode(report)) ?? Data("{\"datasets\":[]}".utf8)
        return String(data: data, encoding: .utf8) ?? "{\"datasets\":[]}"
    }

    private static func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

