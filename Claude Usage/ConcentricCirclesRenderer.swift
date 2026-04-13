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
    /// Reduced opacity — time progress indicator
    private static let fadedOrange = NSColor(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0, alpha: 0.35)

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

                func arcPath(from startPct: Double, to endPct: Double) -> NSBezierPath {
                    let a1: CGFloat = 90 - CGFloat(startPct) * 360
                    let a2: CGFloat = 90 - CGFloat(endPct) * 360
                    let path = NSBezierPath()
                    path.appendArc(withCenter: center, radius: ring.radius,
                                   startAngle: a1, endAngle: a2, clockwise: true)
                    path.lineWidth = lineWidth
                    path.lineCapStyle = .round
                    return path
                }

                let longer = max(usage, time)
                let shorter = min(usage, time)

                guard let ctx = NSGraphicsContext.current?.cgContext else { continue }

                if longer > 0 {
                    // 1. Draw the full extent (whichever is longer) in faded
                    fadedOrange.setStroke()
                    arcPath(from: 0, to: longer).stroke()

                    // 2. Draw solid usage arc, clipped to exclude the faded-only region
                    //    When time > usage: solid covers 0→usage (fully inside faded, drawn on top)
                    //    When usage > time: solid covers 0→usage, but we clip to time→usage
                    //    so the faded time portion stays clean in front.
                    if usage > 0 {
                        ctx.saveGState()
                        if usage > time && time > 0 {
                            // Clip: exclude the 0→time region by inverting.
                            // Fill the full rect, then subtract the arc band.
                            let clipRect = CGRect(origin: .zero, size: rect.size)
                            let exclude = arcPath(from: 0, to: time)
                            let full = NSBezierPath(rect: clipRect)
                            full.append(exclude)
                            full.windingRule = .evenOdd
                            full.addClip()
                        }
                        anthropicOrange.setStroke()
                        arcPath(from: 0, to: usage).stroke()
                        ctx.restoreGState()
                    }
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
