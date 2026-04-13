import AppKit

struct CircleRendererInput {
    let sessionProgress: Double
    let sonnetProgress: Double
    let allModelsProgress: Double
    var sessionTimeProgress: Double = 0
    var sonnetTimeProgress: Double = 0
    var allModelsTimeProgress: Double = 0
}

enum ConcentricCirclesRenderer {
    static func renderMenuBarIcon(input: CircleRendererInput) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 2.0
            let gap: CGFloat = 1.0

            let progresses: [Double] = [input.sessionProgress, input.sonnetProgress, input.allModelsProgress]
            let outerRadius = size / 2 - lineWidth / 2

            for (i, progress) in progresses.enumerated() {
                let radius = outerRadius - CGFloat(i) * (lineWidth + gap)
                let clampedProgress = min(max(progress, 0), 1)

                // Track — same color as fill but faint
                let trackPath = NSBezierPath()
                trackPath.appendArc(withCenter: center, radius: radius,
                                    startAngle: 0, endAngle: 360)
                trackPath.lineWidth = lineWidth
                NSColor.labelColor.withAlphaComponent(0.15).setStroke()
                trackPath.stroke()

                // Fill arc
                if clampedProgress > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(clampedProgress) * 360
                    let arcPath = NSBezierPath()
                    arcPath.appendArc(withCenter: center, radius: radius,
                                      startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    arcPath.lineWidth = lineWidth
                    arcPath.lineCapStyle = .round
                    NSColor.labelColor.setStroke()
                    arcPath.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// Anthropic brand orange: #DA7756
    private static let anthropicOrange = NSColor(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0, alpha: 1.0)
    private static let trackOrange = NSColor(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0, alpha: 0.2)
    /// Reduced opacity — time is ahead of usage (under budget)
    private static let aheadOrange = NSColor(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0, alpha: 0.35)
    /// Darker — usage is ahead of time (over budget)
    private static let behindOrange = NSColor(red: 0x9A / 255.0, green: 0x42 / 255.0, blue: 0x26 / 255.0, alpha: 1.0)

    static func renderLargeView(input: CircleRendererInput, size: CGFloat = 120) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 16.0
            let gap: CGFloat = 3.0

            // Apple Fitness-style: outer ring large, tighter inner rings
            let outerRadius = size / 2 - lineWidth / 2
            let middleRadius = outerRadius - lineWidth - gap
            let innerRadius = middleRadius - lineWidth - gap

            let rings: [(progress: Double, timeProgress: Double, radius: CGFloat)] = [
                (input.sessionProgress, input.sessionTimeProgress, outerRadius),
                (input.sonnetProgress, input.sonnetTimeProgress, middleRadius),
                (input.allModelsProgress, input.allModelsTimeProgress, innerRadius),
            ]

            for ring in rings {
                let usage = min(max(ring.progress, 0), 1)
                let time = min(max(ring.timeProgress, 0), 1)
                let shared = min(usage, time)

                // Track
                let trackPath = NSBezierPath()
                trackPath.appendArc(withCenter: center, radius: ring.radius,
                                    startAngle: 0, endAngle: 360)
                trackPath.lineWidth = lineWidth
                trackOrange.setStroke()
                trackPath.stroke()

                func strokeArc(from startPct: Double, to endPct: Double, color: NSColor) {
                    guard endPct > startPct else { return }
                    let a1: CGFloat = 90 - CGFloat(startPct) * 360
                    let a2: CGFloat = 90 - CGFloat(endPct) * 360
                    let path = NSBezierPath()
                    path.appendArc(withCenter: center, radius: ring.radius,
                                   startAngle: a1, endAngle: a2, clockwise: true)
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .round
                    color.setStroke()
                    path.stroke()
                }

                // Shared segment: 0 → min(usage, time) — normal orange
                strokeArc(from: 0, to: shared, color: anthropicOrange)

                if time > usage {
                    // Time ahead of usage: reduced opacity (under budget)
                    strokeArc(from: usage, to: time, color: aheadOrange)
                } else if usage > time {
                    // Usage ahead of time: darker colour (over budget)
                    strokeArc(from: time, to: usage, color: behindOrange)
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
