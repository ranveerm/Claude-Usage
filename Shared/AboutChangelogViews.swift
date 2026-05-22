import SwiftUI

// MARK: - Shared models

/// One row in the about-screen icon legend.
struct IconLegendItem: Identifiable {
    let id = UUID()
    let systemImage: String
    let name: String
    let description: String
}

/// One section of the in-app changelog. Versions are listed newest first
/// in `Changelog.entries`. The plain-data shape is mirrored in
/// `CHANGELOG.md` at the repo root. Keep the two in sync.
struct ChangelogEntry: Identifiable {
    let id = UUID()
    let version: String
    let features: [String]
}

// MARK: - Changelog data
//
// Source of truth for the in-app Changelog view. Newest version goes on
// top. Bullet items describe user-facing changes only. The `/ship` skill
// adds a new section here as part of the version bump.
enum Changelog {
    static let entries: [ChangelogEntry] = [
        ChangelogEntry(version: "1.1.6", features: [
            "Lock-screen Live Activity bars now render as true capsules at all fill levels, matching the fix applied to the Claude Design bar in 1.1.4",
            "Watch app rings page now shows the \"Updated X ago\" timestamp directly below the rings instead of at the bottom of the detail list",
            "Pull down on the watch rings page to fetch fresh usage from the paired iPhone immediately, without waiting for the next scheduled sync",
        ]),
        ChangelogEntry(version: "1.1.5", features: [
            "Live Activity now reliably dismisses after 10 minutes of no usage change even when iOS never wakes the app for a background refresh. The system itself removes the banner at the idle deadline rather than depending on the app process being alive",
        ]),
        ChangelogEntry(version: "1.1.4", features: [
            "Fixed the Claude Design horizontal progress bar so it always renders as a true capsule. Both ends are now rounded at every fill level, the usage fill has a rounded trailing cap when it falls short of the time-progress fill, and very low usage values no longer produce a floating shape or a vertical pill",
        ]),
        ChangelogEntry(version: "1.1.3", features: [
            "Home-screen and lock-screen widgets now refresh on their own schedule, fetching fresh usage directly from Claude when the system reloads them. Previously they only ever displayed whatever the iOS app had last cached, which meant the rings would appear static until you opened the app",
            "Fixed a visual glitch in the horizontal progress bars where low percentages rendered as a floating circle in the middle of the bar instead of as a small sliver hugging the left curve",
        ]),
        ChangelogEntry(version: "1.1.2", features: [
            "Live Activity idle dismissal now survives across cold launches. When iOS terminates the suspended app to reclaim memory, the 10-minute timer keeps running rather than resetting to zero, so the banner actually goes away after you stop using Claude",
        ]),
        ChangelogEntry(version: "1.1.1", features: [
            "Live Activity now actually disappears after 10 minutes of no usage change. Previously it would dismiss but immediately restart on the next background refresh, making it look like nothing had happened",
        ]),
        ChangelogEntry(version: "1.1.0", features: [
            "New About screen with an icon legend explaining every SF Symbol used across the app, widgets, and inline widget",
            "New Changelog screen showing per-version feature additions, accessible from the same menu as Settings and Sign Out",
            "Inline widget default metric changed from Session to All Models Weekly. More representative of long-term usage at a glance",
        ]),
        ChangelogEntry(version: "1.0.9", features: [
            "Configurable inline lock-screen widget. Pick which metric to track (Session, Sonnet Weekly, All Models Weekly, All Rings, All Rings + Design)",
            "Live Activity bars now translucent so the system Liquid Glass banner bleeds through, giving the bars a frosted-tinted-glass look",
        ]),
        ChangelogEntry(version: "1.0.8", features: [
            "Live Activity dismisses automatically after 10 minutes of no observed percentage change. This keeps the lock-screen banner from going stale when the user steps away",
        ]),
        ChangelogEntry(version: "1.0.7", features: [
            "Live Activity for Claude sessions. Four horizontal usage bars on the lock screen, plus a configurable ring in the Dynamic Island",
            "Live Activity opt-in setting (defaults off) with a Dynamic Island metric picker",
        ]),
        ChangelogEntry(version: "1.0.6", features: [
            "Larger row typography on iOS / macOS / watchOS so usage values are easier to read at a glance",
            "Reset hint text capitalised (\"Resets in 2 days\") and spaced more generously from the row above",
        ]),
        ChangelogEntry(version: "1.0.5", features: [
            "New lock-screen accessory circular widget showing the three rings, matching the macOS status-bar design",
        ]),
        ChangelogEntry(version: "1.0.4", features: [
            "Internal release tag (1.0.3 was already on the remote, so the bump skipped to 1.0.4)",
        ]),
        ChangelogEntry(version: "1.0.3", features: [
            "Demo mode for App Store reviewers. Try the app without signing in",
            "Claude Design weekly usage shown as a horizontal bar beneath the rings",
            "Renamed throughout to \"Vibe Your Rings\"",
        ]),
    ]
}

// MARK: - Icon legend data

private let usageMetricIcons: [IconLegendItem] = [
    IconLegendItem(
        systemImage: "calendar.day.timeline.left",
        name: "Session (5h)",
        description: "Your rolling 5-hour usage window."
    ),
    IconLegendItem(
        systemImage: "calendar",
        name: "Sonnet Weekly",
        description: "Sonnet-specific weekly cap (Max tier only). Shown as N/A on Pro accounts."
    ),
    IconLegendItem(
        systemImage: "shippingbox",
        name: "All Models Weekly",
        description: "Combined weekly usage across every model."
    ),
    IconLegendItem(
        systemImage: "paintbrush.pointed.fill",
        name: "Claude Design",
        description: "Anthropic Labs design feature, metered as a separate weekly quota."
    ),
]

private let inlineWidgetIcons: [IconLegendItem] = [
    IconLegendItem(
        systemImage: "timelapse",
        name: "Progress indicator",
        description: "Pie-slice fill that scales with the metric's current utilisation."
    ),
]

// MARK: - About view

/// Legend for every SF Symbol the app, widget, and inline widget use to
/// represent a particular concept. Presented as a `Form` so it slots into
/// both the iOS Settings sheet (push) and a macOS sheet without extra work.
struct AboutView: View {
    var body: some View {
        Form {
            Section {
                ForEach(usageMetricIcons) { item in
                    legendRow(item)
                }
            } header: {
                Text("Usage metrics")
            } footer: {
                Text("These icons appear next to every usage row across the iOS app, the macOS menu-bar popover, the watch detail page, and the lock-screen Live Activity.")
            }

            Section {
                ForEach(inlineWidgetIcons) { item in
                    legendRow(item)
                }
            } header: {
                Text("Inline lock-screen widget")
            } footer: {
                Text("Each variant of the inline widget shows the metric icon followed by a progress indicator whose fill matches that ring's current utilisation.")
            }
        }
        #if os(iOS)
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .formStyle(.grouped)
        .frame(width: 440, height: 480)
        #endif
    }

    private func legendRow(_ item: IconLegendItem) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: item.systemImage)
                .font(.title3)
                .foregroundStyle(ConcentricCirclesView.anthropicOrange)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                Text(item.description)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Changelog view

/// Versioned feature list. One `Section` per release, bullet rows beneath.
struct ChangelogView: View {
    var body: some View {
        Form {
            ForEach(Changelog.entries) { entry in
                Section(entry.version) {
                    ForEach(entry.features, id: \.self) { feature in
                        Text(feature)
                            .font(.body)
                            .padding(.vertical, 2)
                    }
                }
            }
        }
        #if os(iOS)
        .navigationTitle("Changelog")
        .navigationBarTitleDisplayMode(.inline)
        #else
        .formStyle(.grouped)
        .frame(width: 480, height: 540)
        #endif
    }
}

// MARK: - Previews

#if DEBUG
#if os(iOS)
#Preview("About - iOS") {
    NavigationStack { AboutView() }
}

#Preview("Changelog - iOS") {
    NavigationStack { ChangelogView() }
}
#endif

#if os(macOS)
#Preview("About - macOS") {
    AboutView()
}

#Preview("Changelog - macOS") {
    ChangelogView()
}
#endif
#endif
