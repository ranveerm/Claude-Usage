import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.ranveer.ClaudeYourRings"

    // On iOS/watchOS we share the keychain via an access group and iCloud-sync
    // so the Watch can read what the phone wrote. The macOS menu bar app is
    // standalone, so we use a plain device-scoped keychain — this avoids the
    // "allow this app to access your keychain for other apps" prompt.
    #if !os(macOS)
    private static let accessGroup = "29F59849NR.com.ranveer.ClaudeYourRings.shared"
    #endif

    private static func baseQuery(key: String) -> [String: Any] {
        var q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        #if !os(macOS)
        q[kSecAttrAccessGroup as String] = accessGroup
        q[kSecAttrSynchronizable as String] = kSecAttrSynchronizableAny
        #endif
        return q
    }

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        #if !os(macOS)
        addQuery[kSecAttrSynchronizable as String] = true
        #endif
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func load(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func delete(key: String) {
        let query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)
    }
}
