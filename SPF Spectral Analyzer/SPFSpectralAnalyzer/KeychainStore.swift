import Foundation
import Security

enum KeychainKeys {
    static let service = "ShimadzuDataAnalyser"
    static let openAIAPIKey = "openai_api_key"
    static let anthropicAPIKey = "anthropic_api_key"
    static let grokAPIKey = "grok_api_key"
    static let geminiAPIKey = "gemini_api_key"
    static let oauthAccessToken = "oauth_access_token"
    static let oauthRefreshToken = "oauth_refresh_token"
}

enum KeychainStore {
    static func readPassword(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                print("[Keychain] Read failed for \(account): OSStatus \(status)")
            }
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func savePassword(_ value: String, account: String) {
        let data = Data(value.utf8)
        // Query to find existing item
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if updateStatus == errSecSuccess { return }

        // Item doesn't exist yet — add it
        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            print("[Keychain] Save failed for \(account): OSStatus \(addStatus)")
        }
    }

    static func deletePassword(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
