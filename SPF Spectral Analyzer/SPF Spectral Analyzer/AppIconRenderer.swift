import AppKit

enum AppIconRenderer {
    static func applyRuntimeIcon() {
        if let image = NSImage(named: NSImage.applicationIconName) {
            NSApplication.shared.applicationIconImage = image
        }
    }

    static func generateIcon(size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        defer { image.unlockFocus() }

        // Background gradient
        let rect = NSRect(x: 0, y: 0, width: size, height: size)
        let bg = NSGradient(colors: [
            NSColor(calibratedRed: 0.04, green: 0.52, blue: 1.00, alpha: 1.0), // #0A84FF
            NSColor(calibratedRed: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)  // #30D158
        ])
        bg?.draw(in: rect, angle: 45)

        // Optional: rounded rect mask look (subtle vignette)
        NSColor.black.withAlphaComponent(0.10).setStroke()
        let inset: CGFloat = size * 0.02
        let rounded = NSBezierPath(roundedRect: rect.insetBy(dx: inset, dy: inset), xRadius: size * 0.08, yRadius: size * 0.08)
        rounded.lineWidth = size * 0.01
        rounded.stroke()

        // Draw spectral waveforms
        func wavePath(yBase: CGFloat, amplitude: CGFloat, phase: CGFloat) -> NSBezierPath {
            let path = NSBezierPath()
            let steps = 32
            for i in 0...steps {
                let t = CGFloat(i) / CGFloat(steps)
                let x = t * size
                let y = yBase + sin((t * 4 * .pi) + phase) * amplitude
                let point = NSPoint(x: x, y: y)
                if i == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            return path
        }

        let strokeWhite = NSColor.white
        let line1 = wavePath(yBase: size * 0.60, amplitude: size * 0.08, phase: 0.0)
        strokeWhite.withAlphaComponent(0.90).setStroke()
        line1.lineWidth = size * 0.027
        line1.lineCapStyle = .round
        line1.lineJoinStyle = .round
        line1.stroke()

        let line2 = wavePath(yBase: size * 0.50, amplitude: size * 0.08, phase: .pi / 6)
        strokeWhite.withAlphaComponent(0.85).setStroke()
        line2.lineWidth = size * 0.020
        line2.lineCapStyle = .round
        line2.lineJoinStyle = .round
        line2.stroke()

        let line3 = wavePath(yBase: size * 0.40, amplitude: size * 0.08, phase: .pi / 3)
        strokeWhite.withAlphaComponent(0.80).setStroke()
        line3.lineWidth = size * 0.012
        line3.lineCapStyle = .round
        line3.lineJoinStyle = .round
        line3.stroke()

        // Subtle chart axes
        let axis = NSBezierPath()
        axis.move(to: NSPoint(x: size * 0.11, y: size * 0.22))
        axis.line(to: NSPoint(x: size * 0.11, y: size * 0.84))
        axis.move(to: NSPoint(x: size * 0.11, y: size * 0.84))
        axis.line(to: NSPoint(x: size * 0.89, y: size * 0.84))
        strokeWhite.withAlphaComponent(0.22).setStroke()
        axis.lineWidth = size * 0.014
        axis.lineCapStyle = .round
        axis.stroke()

        return image
    }
}
