# Changelog

This file is the source of truth for the in-app **Changelog** screen
(`Shared/AboutChangelogViews.swift` mirrors it). Update both together.
The `/ship` skill instructs the agent to append a section here before
the version-bump commit.

Tag sections are listed newest first. Bullet items describe **user-facing
changes only**. Internal refactors, test-only edits, and bump-only
commits don't appear here.

## 1.3.0
- The middle usage ring is now labelled "Fable Only" with a book icon (it was "Sonnet Weekly"), reflecting Anthropic's change to this weekly limit, and the app now reads the Fable weekly figure from the usage API

## 1.2.0
- The Claude Design usage bar now disappears when Anthropic stops reporting it in the usage API, instead of showing a misleading 0%. (Anthropic recently removed the separate Claude Design meter, so the bar would otherwise sit empty.)
- Refined the widget's tap-to-refresh prompt with a cleaner, more subtle refresh icon

## 1.1.13
- The Live Activity now refreshes whenever the app gets a background update, and is set to dismiss itself about 15 minutes after the last update once updates stop arriving, so it no longer lingers on the Lock Screen showing old numbers
- The home-screen and Lock Screen rings widgets now show a tap-to-refresh prompt when their data has gone stale (because iOS stopped refreshing them in the background) instead of silently displaying outdated rings. Tapping opens the app to refresh

## 1.1.12
- The Live Activity now shows a "Not updated recently" hint on the Lock Screen and Dynamic Island when its usage figures have gone stale, so you can tell at a glance whether to open the app for fresh numbers instead of trusting outdated ones
- Fixed the Live Activity fading to a stale, greyed-out look after only 10 minutes during an active session; staleness is now based on when the data was last fetched, so a still-running session stays clear as long as it keeps refreshing

## 1.1.11
- Refined the tap-to-expand reset time: the word "Resets" is replaced by a clock symbol when expanded, the "in" prefix is removed, and days are floored rather than rounded so "3 days (and 12 hours)" always adds up correctly

## 1.1.10
- Tap any usage row to reveal a precise time remaining (e.g. "2 days and 12 hours") instead of the rounded relative label. Tap again to return to the summary

## 1.1.9
- Widened the macOS menu-bar popover slightly so the "All Models Weekly" row label no longer truncates to "All Models Wee..."

## 1.1.8
- Replaced pull-to-refresh on the watch rings page with a tap gesture on the rings. Tapping dims the rings and shows a spinner while fresh usage is fetched from the paired iPhone

## 1.1.7
- Increased spacing between the rings and the "Updated X ago" timestamp on the watch rings page

## 1.1.6
- Lock-screen Live Activity bars now render as true capsules at all fill levels, matching the fix applied to the Claude Design bar in 1.1.4
- Watch app rings page now shows the "Updated X ago" timestamp directly below the rings instead of at the bottom of the detail list
- Pull down on the watch rings page to fetch fresh usage from the paired iPhone immediately, without waiting for the next scheduled sync

## 1.1.5
- Live Activity now reliably dismisses after 10 minutes of no usage change even when iOS never wakes the app for a background refresh. The system itself removes the banner at the idle deadline rather than depending on the app process being alive

## 1.1.4
- Fixed the Claude Design horizontal progress bar so it always renders as a true capsule. Both ends are now rounded at every fill level, the usage fill has a rounded trailing cap when it falls short of the time-progress fill, and very low usage values no longer produce a floating shape or a vertical pill

## 1.1.3
- Home-screen and lock-screen widgets now refresh on their own schedule, fetching fresh usage directly from Claude when the system reloads them. Previously they only ever displayed whatever the iOS app had last cached, which meant the rings would appear static until you opened the app
- Fixed a visual glitch in the horizontal progress bars where low percentages rendered as a floating circle in the middle of the bar instead of as a small sliver hugging the left curve

## 1.1.2
- Live Activity idle dismissal now survives across cold launches. When iOS terminates the suspended app to reclaim memory, the 10-minute timer keeps running rather than resetting to zero, so the banner actually goes away after you stop using Claude

## 1.1.1
- Live Activity now actually disappears after 10 minutes of no usage change. Previously it would dismiss but immediately restart on the next background refresh, making it look like nothing had happened

## 1.1.0
- New **About** screen with an icon legend explaining every SF Symbol used across the app, widgets, and inline widget
- New **Changelog** screen showing per-version feature additions, accessible from the same menu as Settings and Sign Out
- Inline widget default metric changed from Session to **All Models Weekly**. More representative of long-term usage at a glance

## 1.0.9
- Configurable inline lock-screen widget. Pick which metric to track
  (Session, Sonnet Weekly, All Models Weekly, All Rings, All Rings + Design)
- Live Activity bars now translucent so the system Liquid Glass banner
  bleeds through, giving the bars a frosted-tinted-glass look

## 1.0.8
- Live Activity dismisses automatically after 10 minutes of no observed
  percentage change. This keeps the lock-screen banner from going stale when
  the user steps away

## 1.0.7
- Live Activity for Claude sessions. Four horizontal usage bars on the
  lock screen, plus a configurable ring in the Dynamic Island
- Live Activity opt-in setting (defaults off) with a Dynamic Island metric
  picker

## 1.0.6
- Larger row typography on iOS / macOS / watchOS so usage values are
  easier to read at a glance
- Reset hint text capitalised ("Resets in 2 days") and spaced more
  generously from the row above

## 1.0.5
- New lock-screen accessory circular widget showing the three rings,
  matching the macOS status-bar design

## 1.0.4
- Internal release tag (1.0.3 was already on the remote, so the bump
  skipped to 1.0.4)

## 1.0.3
- **Demo mode** for App Store reviewers. Try the app without signing in
- Claude Design weekly usage shown as a horizontal bar beneath the rings
- Renamed throughout to "Vibe Your Rings"

## 1.0.2 and earlier
- Earlier releases pre-date this changelog; consult `git log` for detail
