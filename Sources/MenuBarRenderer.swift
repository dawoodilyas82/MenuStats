import AppKit

/// Draws the menu bar item: CPU sparkline, RAM bar, stacked network rates.
/// The image draws lazily, so label colours follow the menu bar's light/dark appearance.
enum MenuBarRenderer {
    struct Snapshot {
        var cpuHistory: [Double]   // 0...1, oldest first
        var cpu: Double?
        var memory: Double?
        var rx: Double?
        var tx: Double?
    }

    private static let height: CGFloat = 18
    private static let sparkWidth: CGFloat = 28
    private static let sparkSamples = 30
    private static let barWidth: CGFloat = 5
    private static let gap: CGFloat = 3
    private static let groupGap: CGFloat = 9

    private static let valueFont = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
    private static let labelFont = NSFont.systemFont(ofSize: 8.5, weight: .semibold)
    private static let netFont = NSFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .medium)

    private static func width(_ s: String, _ f: NSFont) -> CGFloat {
        ceil((s as NSString).size(withAttributes: [.font: f]).width)
    }

    // Values are left-aligned in fixed-width slots so nothing shifts as numbers change.
    private static let pctWidth = width("88%", valueFont)  // "100%" spills into the group gap
    private static let arrowWidth = width("↓", netFont) + 2
    private static let netWidth = arrowWidth + width("99.9M", netFont)

    static func image(_ s: Snapshot) -> NSImage {
        let cpuLabel = width("CPU", labelFont), ramLabel = width("RAM", labelFont)
        let total = cpuLabel + gap + sparkWidth + gap + pctWidth + groupGap
                  + ramLabel + gap + barWidth + gap + pctWidth + groupGap + netWidth

        let image = NSImage(size: NSSize(width: total, height: height), flipped: false) { _ in
            var x: CGFloat = 0

            x = drawText("CPU", font: labelFont, color: .secondaryLabelColor, x: x) + gap
            drawSparkline(s.cpuHistory.suffix(sparkSamples), color: Palette.load(s.cpu ?? 0),
                          in: NSRect(x: x, y: 2, width: sparkWidth, height: height - 4))
            x += sparkWidth + gap
            drawText(s.cpu.map(Fmt.pct) ?? "–", font: valueFont, color: .labelColor, x: x)
            x += pctWidth + groupGap

            x = drawText("RAM", font: labelFont, color: .secondaryLabelColor, x: x) + gap
            drawBar(s.memory ?? 0, color: Palette.load(s.memory ?? 0),
                    in: NSRect(x: x, y: 2, width: barWidth, height: height - 4))
            x += barWidth + gap
            drawText(s.memory.map(Fmt.pct) ?? "–", font: valueFont, color: .labelColor, x: x)
            x += pctWidth + groupGap

            drawRate("↑", s.tx, color: Palette.upload, x: x, y: height / 2)
            drawRate("↓", s.rx, color: Palette.download, x: x, y: 0)
            return true
        }
        image.isTemplate = false
        return image
    }

    // MARK: Drawing helpers

    private static func centeredY(_ f: NSFont) -> CGFloat {
        (height - (f.ascender - f.descender)) / 2
    }

    @discardableResult
    private static func drawText(_ s: String, font: NSFont, color: NSColor, x: CGFloat) -> CGFloat {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        (s as NSString).draw(at: NSPoint(x: x, y: centeredY(font)), withAttributes: attrs)
        return x + width(s, font)
    }

    private static func drawRate(_ arrow: String, _ value: Double?, color: NSColor, x: CGFloat, y: CGFloat) {
        let lineY = y + (height / 2 - (netFont.ascender - netFont.descender)) / 2
        let attrs: [NSAttributedString.Key: Any] = [.font: netFont, .foregroundColor: color]
        (arrow as NSString).draw(at: NSPoint(x: x, y: lineY), withAttributes: attrs)
        ((value.map(Fmt.rate) ?? "–") as NSString).draw(
            at: NSPoint(x: x + arrowWidth, y: lineY),
            withAttributes: [.font: netFont, .foregroundColor: NSColor.labelColor])
    }

    private static func drawSparkline(_ values: ArraySlice<Double>, color: NSColor, in rect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.1).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 2, yRadius: 2).fill()
        guard values.count > 1 else { return }

        // Right-align so a short history grows in from the right edge.
        let step = rect.width / CGFloat(sparkSamples - 1)
        let start = rect.maxX - step * CGFloat(values.count - 1)
        let line = NSBezierPath()
        for (i, v) in values.enumerated() {
            let p = NSPoint(x: start + step * CGFloat(i), y: rect.minY + rect.height * CGFloat(min(max(v, 0), 1)))
            i == 0 ? line.move(to: p) : line.line(to: p)
        }
        let area = line.copy() as! NSBezierPath
        area.line(to: NSPoint(x: rect.maxX, y: rect.minY))
        area.line(to: NSPoint(x: start, y: rect.minY))
        area.close()
        color.withAlphaComponent(0.3).setFill()
        area.fill()
        color.setStroke()
        line.lineWidth = 1.2
        line.lineJoinStyle = .round
        line.stroke()
    }

    private static func drawBar(_ fraction: Double, color: NSColor, in rect: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.15).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 1.5, yRadius: 1.5).fill()
        var fill = rect
        fill.size.height = rect.height * CGFloat(min(max(fraction, 0), 1))
        color.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 1.5, yRadius: 1.5).fill()
    }
}
