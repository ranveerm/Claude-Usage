import SwiftUI

/// Three concentric fitness-style rings showing Claude usage and the elapsed
/// portion of each usage window.
///
/// Each ring layers three elements:
///   1. A faint background **track** (full circle).
///   2. A **time arc** (`0 → time`) in a lower-opacity "faded" orange — how
///      far we are through the reset window.
///   3. A solid **usage arc** (`0 → usage`) on top — how much of the quota
///      has been consumed.
///
/// When `time >= usage` the solid arc is shorter, so the faded arc extends
/// visibly beyond it (reading as "you have headroom"). When `usage > time`
/// the solid arc is longer and fully covers the faded arc — matching the
/// "standard" behaviour; the overshoot simply reads as the solid arc having
/// outrun where the time arc would have ended.
///
/// Implemented with SwiftUI `Shape`s (`Circle().trim`) rather than `Canvas`
/// because `trim`'s `animatableData` is an `AnimatablePair<Double, Double>`
/// that SwiftUI interpolates natively inside `withAnimation`. Canvas treats
/// its drawing closure as opaque and doesn't redraw on each animation frame,
/// which is why the cold-boot fill animation on iOS wasn't visible.
struct ConcentricCirclesView: View {
    let input: CircleRendererInput

    @Environment(\.colorScheme) private var colorScheme

    /// SF symbol names overlaid at the 12 o'clock position of each ring.
    /// Pass `nil` to hide for that ring.
    var outerIcon:  String? = "calendar.day.timeline.left"
    var middleIcon: String? = "calendar"
    var innerIcon:  String? = "shippingbox"

    var body: some View {
        GeometryReader { geo in
            let dim        = min(geo.size.width, geo.size.height)
            let lineWidth  = dim * 0.13
            let gap        = dim / 60
            // Centre-line radius of each ring (same values as the previous
            // Canvas implementation so layouts stay visually identical).
            let outerR     = dim / 2 - lineWidth / 2
            let midR       = outerR - lineWidth - gap
            let innerR     = midR   - lineWidth - gap
            let iconSize   = dim * 0.07

            ZStack {
                ringLayer(centerLineRadius: outerR, lineWidth: lineWidth,
                          iconSize: iconSize, iconName: outerIcon,
                          usage: input.sessionProgress,
                          time:  input.sessionTimeProgress)

                // Middle ring (Sonnet): rendered in grey rather than orange
                // for Pro-tier users, who don't have this metric. The ring
                // itself still reads as "there's a quota here", but its
                // dimmed colouring matches the "N/A" treatment in the list.
                ringLayer(centerLineRadius: midR, lineWidth: lineWidth,
                          iconSize: iconSize, iconName: middleIcon,
                          usage: input.sonnetApplicable ? input.sonnetProgress : 0,
                          time:  input.sonnetApplicable ? input.sonnetTimeProgress : 0,
                          palette: input.sonnetApplicable ? .orange : .grey)

                ringLayer(centerLineRadius: innerR, lineWidth: lineWidth,
                          iconSize: iconSize, iconName: innerIcon,
                          usage: input.allModelsProgress,
                          time:  input.allModelsTimeProgress)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Ring construction

    /// Colour scheme for a single ring. Per-ring override lets the middle
    /// ring dim to grey for Pro-tier users where the metric isn't applicable.
    enum Palette {
        case orange, grey
    }

    @ViewBuilder
    private func ringLayer(
        centerLineRadius r: CGFloat,
        lineWidth lw: CGFloat,
        iconSize: CGFloat,
        iconName: String?,
        usage: Double,
        time: Double,
        palette: Palette = .orange
    ) -> some View {
        // Frame the Circle so its stroke's centre-line coincides with `r`.
        // A Circle inscribed in a `(diameter, diameter)` frame has path
        // radius diameter/2, and stroke spreads ±lineWidth/2 from that path.
        let diameter = r * 2
        let usageClamped = CGFloat(max(0, min(1, usage)))
        let timeClamped  = CGFloat(max(0, min(1, time)))
        // Only cut when the usage has actually overshot the elapsed-time
        // window. `time > 0` is required too so a time=0 state renders as a
        // plain fully-solid usage capsule.
        let isOvershoot = usageClamped > timeClamped && timeClamped > 0
        let cutExtent: CGFloat = isOvershoot ? timeClamped : 0

        let trackColor = palette == .grey ? greyTrack  : Self.trackOrange
        let timeColor  = palette == .grey ? greyFaded  : Self.fadedOrange
        let usageColor = palette == .grey ? greySolid  : Self.anthropicOrange

        ZStack {
            // 1. Track — faint full circle.
            Circle()
                .stroke(trackColor, lineWidth: lw)
                .frame(width: diameter, height: diameter)

            // 2. Time capsule — drawn first so the (possibly-cut) usage
            //    capsule can layer on top of it, and its round end cap at
            //    `time` is the piece the usage will visually wrap around.
            Circle()
                .trim(from: 0, to: timeClamped)
                .rotation(.degrees(-90))
                .stroke(
                    timeColor,
                    style: StrokeStyle(lineWidth: lw, lineCap: .round)
                )
                .frame(width: diameter, height: diameter)

            // 3. Usage capsule with an optional time-shaped cut-out. In the
            //    overshoot case (usage > time) the cutter punches the time
            //    capsule's exact shape out of the usage capsule using
            //    `destinationOut`, so the time capsule underneath shows
            //    through and it *appears* to sit on top of the usage (even
            //    though it's drawn below). Both strokes use round caps, so
            //    the cut edge at `time` is a concave curve mirroring the
            //    time capsule's round end cap — they fit together with no
            //    straight radial seam.
            //
            //    `.compositingGroup()` routes the inner ZStack into its own
            //    offscreen buffer, so the cutter only affects the usage
            //    stroke, not the time capsule or track behind it.
            ZStack {
                Circle()
                    .trim(from: 0, to: usageClamped)
                    .rotation(.degrees(-90))
                    .stroke(
                        usageColor,
                        style: StrokeStyle(lineWidth: lw, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)

                Circle()
                    .trim(from: 0, to: cutExtent)
                    .rotation(.degrees(-90))
                    .stroke(
                        Color.black,
                        style: StrokeStyle(lineWidth: lw, lineCap: .round)
                    )
                    .frame(width: diameter, height: diameter)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()

            // 4. Ring icon at 12 o'clock on the centre line.
            if let iconName {
                Image(systemName: iconName)
                    .font(.system(size: iconSize))
                    .foregroundStyle(iconColor(for: palette))
                    .offset(y: -r)
            }
        }
    }

    // MARK: - Colours

    static let anthropicOrange = Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0)
    private static let trackOrange = anthropicOrange.opacity(0.2)
    private static let fadedOrange = anthropicOrange.opacity(0.35)

    // Grey palette — adaptive so the disabled ring stays legible on both
    // light and dark backgrounds. In light mode the ring is near-white so it
    // reads as "empty/inactive"; in dark mode it stays a subtle secondary grey.
    private var greySolid: Color {
        colorScheme == .dark ? Color.secondary : Color(white: 0.78)
    }
    private var greyFaded: Color {
        colorScheme == .dark ? Color.secondary.opacity(0.30) : Color(white: 0.86)
    }
    private var greyTrack: Color {
        colorScheme == .dark ? Color.secondary.opacity(0.15) : Color(white: 0.91)
    }

    /// Icon colour for the 12 o'clock glyph. Orange rings always use white;
    /// grey rings flip to near-black in light mode so the glyph is readable
    /// against the near-white ring surface.
    private func iconColor(for palette: Palette) -> Color {
        guard palette == .grey else { return .white }
        return colorScheme == .dark ? .white : Color(white: 0.15)
    }
}
