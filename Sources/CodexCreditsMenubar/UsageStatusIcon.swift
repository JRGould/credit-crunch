import AppKit

@MainActor
enum UsageStatusIcon {
    static func make(usagePercent: Double?) -> NSImage {
        let size = NSSize(width: 22, height: 22)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            let usage = usagePercent.map { min(100, max(0, $0)) }
            let progress = usage.map { $0 / 100 } ?? 0
            let primary = usage.map { _ in color(progress: progress, saturation: 0.86) } ?? .tertiaryLabelColor
            let accent = usage.map { _ in color(progress: min(1, progress + 0.18), saturation: 0.72) } ?? .quaternaryLabelColor

            drawMark(in: context, primary: primary, accent: accent)
            drawDots(in: context, rect: rect, progress: progress, isKnown: usage != nil)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = usagePercent.map { "Codex usage: \(Int($0.rounded())) percent" } ?? "Codex usage loading"
        return image
    }

    private static func drawMark(in context: CGContext, primary: NSColor, accent: NSColor) {
        let symbolRect = NSRect(x: 4.0, y: 4.0, width: 14.0, height: 14.0)
        guard let symbol = baseMark else { return }

        context.saveGState()
        NSGradient(starting: primary, ending: accent)?.draw(in: symbolRect, angle: -45)
        symbol.draw(in: symbolRect, from: .zero, operation: .destinationIn, fraction: 1)
        context.restoreGState()
    }

    private static let baseMark: NSImage? = {
        guard let url = Bundle.module.url(forResource: "ChatGPT-Logo", withExtension: "svg"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        return image
    }()

    private static func drawDots(in context: CGContext, rect: NSRect, progress: Double, isKnown: Bool) {
        let center = CGPoint(x: 11, y: 11)
        let radius = 9.1
        // Sixteen segments make 25% end at 3:00 and 50% end at 6:00.
        let count = 16
        let activeDots = Int((progress * Double(count)).rounded(.up))
        for index in 0..<count {
            // AppKit's positive Y direction makes pi/2 12:00; decreasing is clockwise.
            let angle = .pi / 2 - Double(index) * (2 * .pi / Double(count))
            let point = CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
            let isActive = index < activeDots
            let dotColor: NSColor
            if !isKnown {
                dotColor = .quaternaryLabelColor
            } else if isActive {
                let dotProgress = max(progress, Double(index + 1) / Double(count))
                dotColor = color(progress: dotProgress, saturation: 0.94)
            } else {
                dotColor = color(progress: progress, saturation: 0.40).withAlphaComponent(0.28)
            }
            context.setFillColor(dotColor.cgColor)
            context.fillEllipse(in: NSRect(x: point.x - 0.85, y: point.y - 0.85, width: 1.7, height: 1.7))
        }
    }

    private static func color(progress: Double, saturation: CGFloat) -> NSColor {
        // 0% usage is green; 100% usage is red. Yellow occupies the middle.
        let hue = CGFloat((1 - progress) * 0.34)
        return NSColor(calibratedHue: hue, saturation: saturation, brightness: 0.95, alpha: 1)
    }
}
