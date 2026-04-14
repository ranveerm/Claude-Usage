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
            // Scale proportionally so inner ring sits near centre at any render size.
            // At size=120: lineWidth≈18, gap≈2
            let lineWidth: CGFloat = size * 0.15
            let gap: CGFloat = size / 60

            let outerRadius = size / 2 - lineWidth / 2
            let middleRadius = outerRadius - lineWidth - gap
            let innerRadius = middleRadius - lineWidth - gap

            let rings: [(Double, Double, CGFloat)] = [
                (input.sessionProgress, input.sessionTimeProgress, outerRadius),
                (input.sonnetProgress, input.sonnetTimeProgress, middleRadius),
                (input.allModelsProgress, input.allModelsTimeProgress, innerRadius),
            ]

            for (progress, timeProgress, radius) in rings {
                drawRing(
                    center: center, radius: radius, lineWidth: lineWidth,
                    usage: progress, time: timeProgress, rect: rect
                )
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static func drawRing(
        center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
        usage: Double, time: Double, rect: NSRect
    ) {
        let usage = min(max(usage, 0), 1)
        let time = min(max(time, 0), 1)

        // Track
        let trackPath = NSBezierPath()
        trackPath.appendArc(withCenter: center, radius: radius,
                            startAngle: 0, endAngle: 360)
        trackPath.lineWidth = lineWidth
        trackOrange.setStroke()
        trackPath.stroke()

        if usage <= 0 && time <= 0 { return }

        if time > usage {
            // Time ahead: faded arc for full time, solid usage on top
            strokeArc(center: center, radius: radius, lineWidth: lineWidth,
                      from: 0, to: time, color: fadedOrange)
            strokeArc(center: center, radius: radius, lineWidth: lineWidth,
                      from: 0, to: usage, color: anthropicOrange)
        } else if usage > time && time > 0 {
            // Usage ahead: solid usage first, then replace the 0→time region with faded
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }

            strokeArc(center: center, radius: radius, lineWidth: lineWidth,
                      from: 0, to: usage, color: anthropicOrange)

            // Build the thick filled shape of the 0→time arc
            let a1 = CGFloat(90) * .pi / 180
            let a2 = CGFloat(90 - time * 360) * .pi / 180
            let cgCenter = CGPoint(x: center.x, y: center.y)
            let cgArc = CGMutablePath()
            cgArc.addArc(center: cgCenter, radius: radius,
                         startAngle: a1, endAngle: a2, clockwise: true)
            let thickShape = cgArc.copy(
                strokingWithWidth: lineWidth,
                lineCap: .round, lineJoin: .round, miterLimit: 1
            )

            // Clip to that shape, clear pixels, redraw track + faded
            ctx.saveGState()
            ctx.addPath(thickShape)
            ctx.clip()
            ctx.clear(rect)
            // Redraw the track within the cleared region
            trackOrange.setFill()
            ctx.fill(rect)
            strokeArc(center: center, radius: radius, lineWidth: lineWidth,
                      from: 0, to: time, color: fadedOrange)
            ctx.restoreGState()
        } else {
            // time == 0 or equal
            strokeArc(center: center, radius: radius, lineWidth: lineWidth,
                      from: 0, to: usage, color: anthropicOrange)
        }
    }

    private static func strokeArc(
        center: CGPoint, radius: CGFloat, lineWidth: CGFloat,
        from startPct: Double, to endPct: Double, color: NSColor
    ) {
        guard endPct > startPct else { return }
        let a1: CGFloat = 90 - CGFloat(startPct) * 360
        let a2: CGFloat = 90 - CGFloat(endPct) * 360
        let path = NSBezierPath()
        path.appendArc(withCenter: center, radius: radius,
                       startAngle: a1, endAngle: a2, clockwise: true)
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        color.setStroke()
        path.stroke()
    }
}
