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
                let clampedProgress = min(max(ring.progress, 0), 1)
                let clampedTime = min(max(ring.timeProgress, 0), 1)

                // Track
                let trackPath = NSBezierPath()
                trackPath.appendArc(withCenter: center, radius: ring.radius,
                                    startAngle: 0, endAngle: 360)
                trackPath.lineWidth = lineWidth
                trackOrange.setStroke()
                trackPath.stroke()

                // Dotted time-elapsed arc
                if clampedTime > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(clampedTime) * 360
                    let dottedPath = NSBezierPath()
                    dottedPath.appendArc(withCenter: center, radius: ring.radius,
                                         startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    dottedPath.lineWidth = lineWidth
                    dottedPath.lineCapStyle = .round
                    let dashLength: CGFloat = 2
                    let gapLength: CGFloat = 6
                    dottedPath.setLineDash([dashLength, gapLength], count: 2, phase: 0)
                    anthropicOrange.withAlphaComponent(0.45).setStroke()
                    dottedPath.stroke()
                }

                // Fill arc (drawn on top)
                if clampedProgress > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(clampedProgress) * 360
                    let arcPath = NSBezierPath()
                    arcPath.appendArc(withCenter: center, radius: ring.radius,
                                      startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    arcPath.lineWidth = lineWidth
                    arcPath.lineCapStyle = .round
                    anthropicOrange.setStroke()
                    arcPath.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
