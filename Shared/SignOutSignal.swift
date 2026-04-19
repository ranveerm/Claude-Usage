import Foundation

/// Cross-device sign-out coordination via iCloud Key-Value Storage.
///
/// iCloud Keychain sync — which carries the actual credentials — has
/// multi-minute latency in practice. That's too slow for sign-out UX.
/// iCloud KVS typically propagates within seconds and exposes a
/// `didChangeExternallyNotification` we can listen to, so we use it as
/// a faster signal layer on top of the keychain.
///
/// Flow:
/// - On sign-in: record `lastSignedInAt` locally (UserDefaults).
/// - On sign-out: bump `signedOutAt` in iCloud KVS and match the local
///   timestamp so we don't react to our own write.
/// - On app foreground or external-change notification: if remote
///   `signedOutAt` > local `lastSignedInAt`, sign out locally.
enum SignOutSignal {
    private static let kvs = NSUbiquitousKeyValueStore.default
    private static let keySignedOutAt = "claudeRingsSignedOutAt"
    private static let keyLastSignedInAt = "claudeRingsLastSignedInAt"

    /// Record that we just signed in on this device, so subsequent remote
    /// sign-out signals that happened before now are treated as "already
    /// handled" (they shouldn't sign us back out after a fresh sign-in).
    static func markSignedIn() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: keyLastSignedInAt)
    }

    /// Record a sign-out in iCloud KVS. Other devices listening to KVS
    /// changes will pick this up within seconds and sign out locally.
    static func markSignedOut() {
        let now = Date().timeIntervalSince1970
        kvs.set(now, forKey: keySignedOutAt)
        kvs.synchronize()
        // Match local timestamp so we don't react to our own write.
        UserDefaults.standard.set(now, forKey: keyLastSignedInAt)
    }

    /// Returns true if a sign-out on another device happened after we last
    /// signed in on this one. Also advances our local pointer so the same
    /// remote sign-out is only reported once.
    @discardableResult
    static func shouldSignOutFromRemoteSignal() -> Bool {
        kvs.synchronize()
        let remote = kvs.double(forKey: keySignedOutAt)
        let local = UserDefaults.standard.double(forKey: keyLastSignedInAt)
        guard remote > 0, remote > local else { return false }
        UserDefaults.standard.set(remote, forKey: keyLastSignedInAt)
        return true
    }
}
