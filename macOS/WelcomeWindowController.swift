import AppKit
import SwiftUI

/// First-launch onboarding. Explains what the app does before pushing the
/// user into the Claude.ai login flow. Dismissed forever once the user
/// taps "Sign In with Claude".
final class WelcomeWindowController: NSWindowController, NSWindowDelegate {
    private static let hasCompletedKey = "hasCompletedWelcome"
    private static var current: WelcomeWindowController?

    static var hasCompleted: Bool {
        UserDefaults.standard.bool(forKey: hasCompletedKey)
    }

    static func dismiss() {
        current?.close()
    }

    static func resetForDebug() {
        UserDefaults.standard.removeObject(forKey: hasCompletedKey)
    }

    static func present(onSignIn: @escaping () -> Void) {
        if let existing = current {
            existing.window?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = WelcomeView(onSignIn: {
            UserDefaults.standard.set(true, forKey: hasCompletedKey)
            current?.close()
            onSignIn()
        })
        let hosting = NSHostingController(rootView: root)

        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 540),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        win.title = "Welcome"
        win.center()
        win.contentViewController = hosting
        win.isReleasedWhenClosed = false

        let controller = WelcomeWindowController(window: win)
        win.delegate = controller
        current = controller

        controller.showWindow(nil)
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        Self.current = nil
    }
}

// MARK: - View

private struct WelcomeView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            ConcentricCirclesView(input: CircleRendererInput(
                sessionProgress: 0.72, sonnetProgress: 0.45, allModelsProgress: 0.58,
                sessionTimeProgress: 0.5, sonnetTimeProgress: 0.55, allModelsTimeProgress: 0.5
            ))
            .frame(width: 140, height: 140)
            .padding(.top, 24)

            VStack(spacing: 6) {
                Text("Welcome to Claude Your Rings")
                    .font(.title2).bold()
                Text("Your Claude usage, always one glance away.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                ringRow(color: 1.0, label: "Outer ring — current 5-hour session")
                ringRow(color: 0.8, label: "Middle ring — Sonnet weekly quota")
                ringRow(color: 0.6, label: "Inner ring — all-models weekly quota")
            }
            .padding(.horizontal, 36)

            Spacer(minLength: 0)

            VStack(spacing: 8) {
                Button(action: onSignIn) {
                    Text("Sign In with Claude")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)

                Text("Your sign-in stays on this Mac. No data leaves this device.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 36)
            .padding(.bottom, 24)
        }
        .frame(width: 480, height: 540)
    }

    private func ringRow(color: Double, label: String) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(red: 0xDA / 255.0, green: 0x77 / 255.0, blue: 0x56 / 255.0).opacity(color))
                .frame(width: 10, height: 10)
            Text(label)
                .font(.callout)
                .foregroundColor(.primary)
            Spacer()
        }
    }
}

#if DEBUG
#Preview {
    WelcomeView(onSignIn: {})
}
#endif
