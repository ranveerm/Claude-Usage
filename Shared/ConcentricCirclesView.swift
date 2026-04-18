import SwiftUI

struct ConcentricCirclesView: View {
    let input: CircleRendererInput

    /// SF symbol names overlaid at the 12 o'clock position of each ring.
    /// Defaults match the macOS popover (source of truth). Pass nil to hide.
    var outerIcon:  String? = "calendar.day.timeline.left"
    var middleIcon: String? = "calendar"
    var innerIcon:  String? = "shippingbox"

    var body: some View {
        Canvas { context, size in
            let dim    = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let lw     = dim * 0.13
            let gap    = dim / 60
            let outerR = dim / 2 - lw / 2
            let midR   = outerR - lw - gap
            let innerR = midR   - lw - gap

            let rings: [(Double, Double, CGFloat)] = [
                (input.sessionProgress,   input.sessionTimeProgress,   outerR),
                (input.sonnetProgress,    input.sonnetTimeProgress,    midR),
                (input.allModelsProgress, input.allModelsTimeProgress, innerR),
            ]
            for (usage, time, radius) in rings {
                Self.drawRing(
                    in: &context, center: center,
                    radius: radius, lineWidth: lw,
                    usage: usage, time: time
                )
            }
        }
        // Icon overlay: reads the Canvas's settled frame so positions
        // are always consistent with what was drawn.
        .overlay(
            GeometryReader { geo in
                let dim    = min(geo.size.width, geo.size.height)
                let cx     = geo.size.width  / 2
                let cy     = geo.size.height / 2
                let lw     = dim * 0.13
                let gap    = dim / 60
                let outerR = dim / 2 - lw / 2
                let midR   = outerR - lw - gap
                let innerR = midR   - lw - gap

                ZStack {
                    ringIcon(outerIcon,  x: cx, y: cy - outerR, dim: dim)
                    ringIcon(middleIcon, x: cx, y: cy - midR,   dim: dim)
                    ringIcon(innerIcon,  x: cx, y: cy - innerR, dim: dim)
                }
            }
        )
        .aspectRatio(1, contentMode: .fit)
    }

    @ViewBuilder
    private func ringIcon(_ name: String?, x: CGFloat, y: CGFloat, dim: CGFloat) -> some View {
        if let name {
            Image(systemName: name)
                .font(.system(size: dim * 0.07))
                .foregroundStyle(.white)
                .position(x: x, y: y)
        }
    }

    // MARK: - Colors

    static let anthropicOrange = Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0)
    private static let trackOrange = anthropicOrange.opacity(0.2)
    private static let fadedOrange = anthropicOrange.opacity(0.35)

    // MARK: - Drawing

    private static func drawRing(
        in context: inout GraphicsContext, center: CGPoint,
        radius: CGFloat, lineWidth: CGFloat,
        usage: Double, time: Double
    ) {
        let usage = min(max(usage, 0), 1)
        let time  = min(max(time,  0), 1)

        let roundStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        // 1. Track (full background circle)
        context.stroke(
            circlePath(center: center, radius: radius),
            with: .color(trackOrange), style: roundStyle
        )

        if usage <= 0 && time <= 0 { return }

        if time >= usage {
            // Time at or ahead of usage:
            //   faded arc 0→time (elapsed window), solid arc 0→usage on top.
            if time > 0 {
                strokeArc(in: &context, center: center, radius: radius,
                          from: 0, to: time, color: fadedOrange, style: roundStyle)
            }
            if usage > 0 {
                strokeArc(in: &context, center: center, radius: radius,
                          from: 0, to: usage, color: anthropicOrange, style: roundStyle)
            }

        } else if time <= 0 {
            // No time elapsed — draw solid usage with normal round caps.
            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: usage, color: anthropicOrange, style: roundStyle)

        } else {
            // Usage ahead of time:
            //   Solid arc 0→usage (round caps at both ends — usage shape starts
            //   at 12 o'clock). White semi-transparent overlay on 0→time dims the
            //   elapsed portion, making time progress read as clipping the usage arc.
            //   The un-dimmed tail (time→usage) remains full solid orange.
            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: usage, color: anthropicOrange, style: roundStyle)

            strokeArc(in: &context, center: center, radius: radius,
                      from: 0, to: time, color: .white.opacity(0.3), style: roundStyle)
        }
    }

    // MARK: - Path Helpers

    private static func circlePath(center: CGPoint, radius: CGFloat) -> Path {
        Path { p in
            p.addArc(center: center, radius: radius,
                     startAngle: .degrees(0), endAngle: .degrees(360), clockwise: false)
        }
    }

    private static func arcPath(center: CGPoint, radius: CGFloat,
                                from startPct: Double, to endPct: Double) -> Path {
        // 0 % = 12 o'clock. SwiftUI 0° = 3 o'clock, so offset by −90°.
        let a1 = Angle.degrees(-90 + startPct * 360)
        let a2 = Angle.degrees(-90 + endPct   * 360)
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
        context.stroke(
            arcPath(center: center, radius: radius, from: startPct, to: endPct),
            with: .color(color), style: style
        )
    }
}

// MARK: - Preview

#if DEBUG
#Preview("Circles — usage ahead") {
    ConcentricCirclesView(
        input: CircleRendererInput(
            sessionProgress:       0.80,
            sonnetProgress:        0.65,
            allModelsProgress:     0.50,
            sessionTimeProgress:   0.30,
            sonnetTimeProgress:    0.20,
            allModelsTimeProgress: 0.15
        )
    )
    .frame(width: 200, height: 200)
    .padding()
    .background(Color.secondary.opacity(0.1))
}

#Preview("Circles — time ahead") {
    ConcentricCirclesView(
        input: CircleRendererInput(
            sessionProgress:       0.30,
            sonnetProgress:        0.20,
            allModelsProgress:     0.15,
            sessionTimeProgress:   0.70,
            sonnetTimeProgress:    0.60,
            allModelsTimeProgress: 0.50
        )
    )
    .frame(width: 200, height: 200)
    .padding()
    .background(Color.secondary.opacity(0.1))
}
#endif
