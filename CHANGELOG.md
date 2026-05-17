# Changelog

This file is the source of truth for the in-app **Changelog** screen
(`Shared/AboutChangelogViews.swift` mirrors it). Update both together —
the `/ship` skill instructs the agent to append a section here before
the version-bump commit.

Tag sections are listed newest first. Bullet items describe **user-facing
changes only** — internal refactors, test-only edits, and bump-only
commits don't appear here.

## 1.1.0
- New **About** screen with an icon legend explaining every SF Symbol used across the app, widgets, and inline widget
- New **Changelog** screen showing per-version feature additions, accessible from the same menu as Settings and Sign Out
- Inline widget default metric changed from Session to **All Models Weekly** — more representative of long-term usage at a glance

## 1.0.9
- Configurable inline lock-screen widget — pick which metric to track
  (Session, Sonnet Weekly, All Models Weekly, All Rings, All Rings + Design)
- Live Activity bars now translucent so the system Liquid Glass banner
  bleeds through, giving the bars a frosted-tinted-glass look

## 1.0.8
- Live Activity dismisses automatically after 10 minutes of no observed
  percentage change — keeps the lock-screen banner from going stale when
  the user steps away

## 1.0.7
- Live Activity for Claude sessions — four horizontal usage bars on the
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
- **Demo mode** for App Store reviewers — try the app without signing in
- Claude Design weekly usage shown as a horizontal bar beneath the rings
- Renamed throughout to "Vibe Your Rings"

## 1.0.2 and earlier
- Earlier releases pre-date this changelog; consult `git log` for detail
