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
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func savePassword(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        if SecItemUpdate(query as CFDictionary, attributes as CFDictionary) != errSecSuccess {
            let addQuery: [String: Any] = query.merging(attributes) { _, new in new }
            SecItemAdd(addQuery as CFDictionary, nil)
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
