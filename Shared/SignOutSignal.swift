import Foundation

/// Cross-device sign-in / sign-out coordination via iCloud Key-Value Storage.
///
/// ## Design
///
/// The KVS carries a **session id** — a UUID identifying the currently-active
/// sign-in across the user's devices, or `""` when signed out.
///
/// Only two events mutate the KVS:
///
/// 1. `markSignedIn()` — generates a fresh UUID on explicit sign-in, stores
///    it locally, and broadcasts it via iCloud KVS.
/// 2. `markSignedOut()` — on explicit user sign-out. Clears both local and
///    KVS values.
///
/// Reading (via `observe(isConfigured:)`) is **passive**: the observing
/// device compares the remote value to its local snapshot and decides what
/// to do. It may update its local snapshot, but it never writes to the KVS.
/// This is the key invariant that prevents cascading sign-outs — if a device
/// reacts to another device's sign-out by writing back to the KVS, every
/// other device would see *that* write and cascade again.
///
/// ## Why UUIDs, not timestamps
///
/// The previous timestamp-based design had a subtle bug: a device that never
/// signed in (`local = 0`) would always consider any non-zero remote
/// `signedOutAt` as "newer" and sign out. That reaction re-broadcast a newer
/// timestamp, which then signed out every other device. Using an opaque
/// session id sidesteps the whole ordinal-comparison trap — a device that
/// has never seen the current session id simply adopts it (no false
/// sign-out), and only a deliberate `markSignedOut()` clears the KVS.
enum SignOutSignal {
    private static let kvs = NSUbiquitousKeyValueStore.default
    private static let keyRemoteSessionId = "claudeRingsSessionId"
    private static let keyLocalSessionId = "claudeRingsLocalSessionId"

    // MARK: - Mutating events (the only two that write to KVS)

    /// Record a fresh sign-in on this device. Generates a new session id,
    /// stores it locally, and broadcasts it via iCloud KVS so other devices
    /// can adopt the same session identifier.
    static func markSignedIn() {
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: keyLocalSessionId)
        kvs.set(id, forKey: keyRemoteSessionId)
        kvs.synchronize()
    }

    /// Record an explicit user sign-out. Clears the KVS session id so other
    /// devices see the empty value and sign themselves out.
    static func markSignedOut() {
        UserDefaults.standard.removeObject(forKey: keyLocalSessionId)
        kvs.set("", forKey: keyRemoteSessionId)
        kvs.synchronize()
    }

    // MARK: - Reading (no KVS mutation)

    /// What the caller should do based on comparing KVS to our local state.
    enum Observation: Equatable {
        /// Local and remote agree — nothing to do.
        case inSync
        /// The KVS says signed out but this device still has credentials —
        /// caller should clear local state. Callers MUST NOT re-broadcast
        /// by calling `markSignedOut()` — that would cascade.
        case shouldSignOut
        /// The KVS has a session id we hadn't observed yet (e.g. because
        /// another device signed in and its credentials just synced into our
        /// keychain). We've silently adopted it locally; no UI change needed.
        case adoptedRemote
    }

    /// Compare the KVS value to our local snapshot and classify the result.
    /// May update the local snapshot to match KVS (`adoptedRemote`); never
    /// writes to KVS.
    static func observe(isConfigured: Bool) -> Observation {
        kvs.synchronize()
        let remote = kvs.string(forKey: keyRemoteSessionId) ?? ""
        let local = UserDefaults.standard.string(forKey: keyLocalSessionId) ?? ""

        if remote.isEmpty {
            // Remote says "signed out". Only meaningful if we're still
            // holding credentials; otherwise we're already in sync.
            if isConfigured {
                UserDefaults.standard.removeObject(forKey: keyLocalSessionId)
                return .shouldSignOut
            }
            return .inSync
        }

        if local == remote {
            return .inSync
        }

        // A new session id is live. Adopt it — we don't broadcast, because
        // the device that wrote this id already broadcast the event.
        UserDefaults.standard.set(remote, forKey: keyLocalSessionId)
        return .adoptedRemote
    }
}
