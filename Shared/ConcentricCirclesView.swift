import SwiftUI

struct ConcentricCirclesView: View {
    let input: CircleRendererInput

    var body: some View {
        Canvas { context, size in
            let dim = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lineWidth = dim * 0.13
            let gap = dim / 60

            let outerRadius = dim / 2 - lineWidth / 2
            let middleRadius = outerRadius - lineWidth - gap
            let innerRadius = middleRadius - lineWidth - gap

            let rings: [(Double, Double, CGFloat)] = [
                (input.sessionProgress, input.sessionTimeProgress, outerRadius),
                (input.sonnetProgress, input.sonnetTimeProgress, middleRadius),
                (input.allModelsProgress, input.allModelsTimeProgress, innerRadius),
            ]

            for (usage, time, radius) in rings {
                Self.drawRing(
                    in: &context, size: size, center: center,
                    radius: radius, lineWidth: lineWidth,
                    usage: usage, time: time
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Colors

    private static let anthropicOrange = Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0)
    private static let trackOrange = Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0).opacity(0.2)
    private static let fadedOrange = Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0).opacity(0.35)

    // MARK: - Drawing

    private static func drawRing(
        in context: inout GraphicsContext, size: CGSize, center: CGPoint,
        radius: CGFloat, lineWidth: CGFloat,
        usage: Double, time: Double
    ) {
        let usage = min(max(usage, 0), 1)
        let time = min(max(time, 0), 1)

        let trackStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        let arcStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        // Track circle
        let trackPath = circlePath(center: center, radius: radius)
        context.stroke(trackPath, with: .color(trackOrange), style: trackStyle)

        if usage <= 0 && time <= 0 { return }

        if time > usage {
            // Time ahead of usage: faded arc for full time extent, solid usage on top
            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: time, color: fadedOrange, style: arcStyle)
            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: usage, color: anthropicOrange, style: arcStyle)
        } else if usage > time && time > 0 {
            // Usage ahead of time: draw solid usage, then replace 0→time region with faded
            // Use drawLayer to composite cleanly
            context.drawLayer { layerCtx in
                // Draw the solid usage arc in this layer
                strokeArc(in: &layerCtx, center: center, radius: radius,
                          from: 0, to: usage, color: anthropicOrange, style: arcStyle)

                // Build thick stroke shape of the 0→time arc for clipping
                let timeArcPath = arcPath(center: center, radius: radius, from: 0, to: time)
                let thickTimePath = timeArcPath.strokedPath(arcStyle)

                // Use blendMode to cut out the time region, then redraw faded
                layerCtx.drawLayer { innerCtx in
                    innerCtx.clip(to: thickTimePath)
                    // Clear pixels in this region by drawing with .clear blend mode
                    innerCtx.blendMode = .clear
                    innerCtx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                }

                // Redraw track + faded within the time region
                layerCtx.drawLayer { innerCtx in
                    innerCtx.clip(to: thickTimePath)
                    // Track
                    innerCtx.stroke(trackPath, with: .color(trackOrange), style: trackStyle)
                    // Faded time arc
                    strokeArc(in: &innerCtx, center: center, radius: radius,
                              from: 0, to: time, color: fadedOrange, style: arcStyle)
                }
            }
        } else {
            // time == 0 or equal: just draw usage
            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: usage, color: anthropicOrange, style: arcStyle)
        }
    }

    // MARK: - Path Helpers

    private static func circlePath(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            p.addArc(center: center, radius: radius,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
    }

    private static func arcPath(center: CGPoint, radius: CGFloat, from startPct: Double, to endPct: Double) -> Path {
        // 0% = 12 o'clock (top), increasing clockwise.
        // In SwiftUI, 0 degrees = 3 o'clock, so 12 o'clock = -90 degrees.
        // SwiftUI's "clockwise" is visually clockwise (screen coords).
        let a1 = Angle.degrees(-90 + startPct * 360)
        let a2 = Angle.degrees(-90 + endPct * 360)
        return Path { p in
            p.addArc(center: center, radius: radius,
                     startAngle: a1, endAngle: a2, clockwise: false)
        }
    }

    private static func strokeArc(
        in context: inout GraphicsContext,
        center: CGPoint, radius: CGFloat,
        from startPct: Double, to endPct: Double,
        color: Color, style: StrokeStyle
    ) {
        guard endPct > startPct else { return }
        let path = arcPath(center: center, radius: radius, from: startPct, to: endPct)
        context.stroke(path, with: .color(color), style: style)
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Circles") {
    ConcentricCirclesView(input: CircleRendererInput(
        sessionProgress: 0.69,
        sonnetProgress: 0.33,
        allModelsProgress: 0.42,
        sessionTimeProgress: 0.42,
        sonnetTimeProgress: 0.60,
        allModelsTimeProgress: 0.55
    ))
    .frame(width: 200, height: 200)
    .padding()
}
#endif
