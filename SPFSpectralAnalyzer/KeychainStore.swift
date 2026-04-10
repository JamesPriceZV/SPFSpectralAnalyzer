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

/// Result of a keychain save operation, including inline diagnostic info.
struct KeychainSaveResult: Sendable {
    let success: Bool
    /// Human-readable diagnostic (nil on success).
    let diagnostic: String?
}

enum KeychainStore {

    // MARK: - Read

    static func readPassword(account: String) -> String? {
        print("[Keychain] Reading \(account)…")
        // Try Keychain first
        if let value = keychainRead(account: account) {
            print("[Keychain] Read \(account) from Keychain (\(value.count) chars)")
            return value
        }
        // Fallback: UserDefaults (iOS — for when Keychain is unreliable
        // due to provisioning / entitlement issues on certain devices)
        #if os(iOS)
        if let fallback = fallbackRead(account: account) {
            print("[Keychain] Read \(account) from UserDefaults fallback (\(fallback.count) chars)")
            return fallback
        }
        print("[Keychain] No value found for \(account)")
        return nil
        #else
        return nil
        #endif
    }

    // MARK: - Save

    @discardableResult
    static func savePassword(_ value: String, account: String) -> KeychainSaveResult {
        print("[Keychain] Saving \(account) (\(value.count) chars)…")
        let keychainResult = keychainSave(value, account: account)

        #if os(iOS)
        // Always mirror to UserDefaults fallback on iOS so the key is
        // available even if Keychain is broken.
        fallbackSave(value, account: account)
        print("[Keychain] iOS fallback saved \(account)")
        if !keychainResult.success {
            // Keychain failed but fallback succeeded — report partial success
            // so the UI shows "Key stored" and the key is usable.
            return KeychainSaveResult(
                success: true,
                diagnostic: keychainResult.diagnostic.map { "(\($0) — using app storage fallback)" }
            )
        }
        #endif

        return keychainResult
    }

    // MARK: - Delete

    static func deletePassword(account: String) {
        keychainDelete(account: account)
        #if os(iOS)
        fallbackDelete(account: account)
        #endif
    }

    // MARK: - Keychain Primitives

    private static func keychainRead(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return String(data: data, encoding: .utf8)
        }
        if status != errSecItemNotFound {
            print("[Keychain] Read OSStatus \(status) for \(account)")
        }
        return nil
    }

    private static func keychainSave(_ value: String, account: String) -> KeychainSaveResult {
        let data = Data(value.utf8)

        // Delete any existing item first to avoid errSecDuplicateItem
        keychainDelete(account: account)

        // Add with kSecAttrAccessibleAfterFirstUnlock so keys survive
        // app relaunch and device lock cycles on iOS.
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        if addStatus != errSecSuccess {
            let msg = "Keychain save OSStatus \(addStatus)"
            print("[Keychain] \(msg) for \(account)")
            return KeychainSaveResult(success: false, diagnostic: msg)
        }

        // Verify round-trip
        if keychainRead(account: account) == nil {
            let msg = "Keychain verify failed (read-back nil after add)"
            print("[Keychain] \(msg) for \(account)")
            return KeychainSaveResult(success: false, diagnostic: msg)
        }

        print("[Keychain] Saved \(account) to Keychain successfully")
        return KeychainSaveResult(success: true, diagnostic: nil)
    }

    private static func keychainDelete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainKeys.service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Diagnostics

    /// Check which API key accounts have stored values.
    static func verifyAllKeys() -> [String: Bool] {
        let accounts = [
            KeychainKeys.openAIAPIKey,
            KeychainKeys.anthropicAPIKey,
            KeychainKeys.grokAPIKey,
            KeychainKeys.geminiAPIKey
        ]
        var status: [String: Bool] = [:]
        for account in accounts {
            status[account] = readPassword(account: account) != nil
        }
        return status
    }

    // MARK: - UserDefaults Fallback (iOS)

    #if os(iOS)
    private static let fallbackPrefix = "ks_fb_"

    private static func fallbackSave(_ value: String, account: String) {
        let encoded = Data(value.utf8).base64EncodedString()
        UserDefaults.standard.set(encoded, forKey: fallbackPrefix + account)
    }

    private static func fallbackRead(account: String) -> String? {
        guard let encoded = UserDefaults.standard.string(forKey: fallbackPrefix + account),
              let data = Data(base64Encoded: encoded) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func fallbackDelete(account: String) {
        UserDefaults.standard.removeObject(forKey: fallbackPrefix + account)
    }
    #endif
}
