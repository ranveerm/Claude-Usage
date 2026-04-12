import AppKit

enum CircleColor {
    static func color(for progress: Double) -> NSColor {
        switch progress {
        case ..<0.6: return .systemGreen
        case ..<0.85: return .systemYellow
        default: return .systemRed
        }
    }
}

struct CircleRendererInput {
    let sessionProgress: Double
    let sonnetProgress: Double
    let allModelsProgress: Double
}

enum ConcentricCirclesRenderer {
    static func renderMenuBarIcon(input: CircleRendererInput) -> NSImage {
        let size: CGFloat = 18
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 2.0
            let gap: CGFloat = 1.0

            let radii: [(Double, CGFloat)] = [
                (input.sessionProgress, size / 2 - lineWidth / 2),
                (input.sonnetProgress, size / 2 - lineWidth - gap - lineWidth / 2),
                (input.allModelsProgress, size / 2 - 2 * (lineWidth + gap) - lineWidth / 2),
            ]

            for (progress, radius) in radii {
                let clampedProgress = min(max(progress, 0), 1)
                let trackPath = NSBezierPath()
                trackPath.appendArc(withCenter: center, radius: radius,
                                    startAngle: 0, endAngle: 360)
                trackPath.lineWidth = lineWidth
                NSColor.tertiaryLabelColor.setStroke()
                trackPath.stroke()

                if clampedProgress > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(clampedProgress) * 360
                    let arcPath = NSBezierPath()
                    arcPath.appendArc(withCenter: center, radius: radius,
                                      startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    arcPath.lineWidth = lineWidth
                    arcPath.lineCapStyle = .round
                    CircleColor.color(for: clampedProgress).setStroke()
                    arcPath.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    static func renderLargeView(input: CircleRendererInput, size: CGFloat = 120) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let center = CGPoint(x: rect.midX, y: rect.midY)
            let lineWidth: CGFloat = 10.0
            let gap: CGFloat = 4.0

            let radii: [(Double, CGFloat, String)] = [
                (input.sessionProgress, size / 2 - lineWidth / 2, "Session"),
                (input.sonnetProgress, size / 2 - lineWidth - gap - lineWidth / 2, "Sonnet"),
                (input.allModelsProgress, size / 2 - 2 * (lineWidth + gap) - lineWidth / 2, "All"),
            ]

            for (progress, radius, _) in radii {
                let clampedProgress = min(max(progress, 0), 1)
                let trackPath = NSBezierPath()
                trackPath.appendArc(withCenter: center, radius: radius,
                                    startAngle: 0, endAngle: 360)
                trackPath.lineWidth = lineWidth
                NSColor.tertiaryLabelColor.withAlphaComponent(0.3).setStroke()
                trackPath.stroke()

                if clampedProgress > 0 {
                    let startAngle: CGFloat = 90
                    let endAngle = startAngle - CGFloat(clampedProgress) * 360
                    let arcPath = NSBezierPath()
                    arcPath.appendArc(withCenter: center, radius: radius,
                                      startAngle: startAngle, endAngle: endAngle, clockwise: true)
                    arcPath.lineWidth = lineWidth
                    arcPath.lineCapStyle = .round
                    CircleColor.color(for: clampedProgress).setStroke()
                    arcPath.stroke()
                }
            }
            return true
        }
        image.isTemplate = false
        return image
    }
}
