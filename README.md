# Claude Your Rings

A multi-platform companion that visualises your Claude.ai usage as three concentric rings — at a glance, without leaving what you're doing.

Runs on:

- **macOS** — menu bar app
- **iOS / iPadOS** — full-screen app
- **WidgetKit** — home screen widget (iOS)
- **watchOS** — paired watch app

## What the rings mean

| Ring | Metric |
|--------|--------|
| Outer | Current 5-hour session usage |
| Middle | Sonnet 7-day usage |
| Inner | All-models 7-day usage |

Each ring fills clockwise. A faded arc shows the *time elapsed* in the current window, so you can see at a glance whether your usage is running ahead of or behind the clock.

## Getting started

On first launch, each platform walks you through an in-app sign-in:

- **macOS** — a welcome window explains what the app does; tapping **Sign In with Claude** opens an embedded Claude.ai login. The window closes automatically once the API accepts your cookies.
- **iOS** — the main screen shows a "Sign in" button that opens the embedded login flow.

Your session cookies are stored:

- On macOS — in a device-scoped keychain (not shared, not synced)
- On iOS / watchOS — in a shared keychain access group, synced via iCloud Keychain so the watch can read what the phone wrote

No credentials ever leave your device except to call the same `claude.ai` endpoints your browser already uses.

## Development

### Project generation

The Xcode project is generated from `project.yml` using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
xcodegen generate
open "Claude Your Rings.xcodeproj"
```

### Resetting onboarding state (macOS)

In DEBUG builds, the popover settings menu has a **Reset & Re-onboard** button that wipes credentials and the welcome-seen flag, then re-runs the full onboarding flow. Useful when iterating on the welcome / login UX.

If you need to do it from the terminal (e.g. the app isn't running):

```bash
security delete-generic-password -s "com.ranveer.ClaudeYourRings" -a "sessionKey" 2>/dev/null
security delete-generic-password -s "com.ranveer.ClaudeYourRings" -a "cfClearance" 2>/dev/null
security delete-generic-password -s "com.ranveer.ClaudeYourRings" -a "organizationId" 2>/dev/null
defaults delete com.ranveer.ClaudeYourRings 2>/dev/null
rm -rf "$HOME/Library/WebKit/com.ranveer.ClaudeYourRings" 2>/dev/null
```

### Previews

Every view has `#Preview` macros with representative mock data — SwiftUI previews do not hit the network. The iOS and macOS previews include interactive sliders for tuning ring values.

## Privacy

Session cookies live in the keychain (per platform rules above). The app only talks to `claude.ai` to fetch your usage quota. Nothing else leaves the device.
