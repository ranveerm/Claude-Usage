import Foundation
import Security

enum KeychainHelper {
    private static let service = "com.ranveer.ClaudeYourRings"

    // All platforms use the same iCloud-synced shared access group so that
    // credentials written on one device are visible on all others, and a
    // sign-out deletion propagates everywhere automatically.
    // The access group is declared in each target's entitlements under
    // keychain-access-groups, which suppresses the macOS authorisation prompt.
    private static let accessGroup = "29F59849NR.com.ranveer.ClaudeYourRings.shared"

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
    }

    static func save(key: String, value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query = baseQuery(key: key)
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrSynchronizable as String] = true
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
