import Foundation
import SwiftUI

// MARK: - Auth Errors

enum M365AuthError: LocalizedError, Sendable {
    case invalidAuthority
    case noPresentationAnchor
    case noAccount
    case noAccessToken
    case msalNotAvailable
    case unexpectedResult(String)

    var errorDescription: String? {
        switch self {
        case .invalidAuthority:
            return "Invalid Microsoft Entra authority URL."
        case .noPresentationAnchor:
            return "No presentation anchor available for sign-in."
        case .noAccount:
            return "No signed-in Microsoft account is available."
        case .noAccessToken:
            return "No access token was returned."
        case .msalNotAvailable:
            return "MSAL library is not available. Add the MSAL Swift Package to the project."
        case .unexpectedResult(let message):
            return message
        }
    }
}

// MARK: - Auth Protocol

protocol M365AuthProviding: Sendable {
    @MainActor func acquireToken(scopes: [String]) async throws -> String
    @MainActor func signIn(scopes: [String]) async throws -> String
    @MainActor func signOut() async throws
    @MainActor func currentUsername() -> String?
    @MainActor var isSignedIn: Bool { get }
}

// MARK: - MSAL Auth Manager

#if canImport(MSAL)
@preconcurrency import MSAL

/// Manages Microsoft identity authentication using MSAL for iOS/macOS.
/// Uses delegated sign-in with browser-based interactive flow (triggers Microsoft Authenticator).
/// Token caching is handled by MSAL — we never store access tokens ourselves.
@MainActor @Observable
final class MSALAuthManager: M365AuthProviding {
    private(set) var isSignedIn = false
    private(set) var username: String?
    private(set) var lastError: String?

    private var application: MSALPublicClientApplication?
    private var cachedAccount: MSALAccount?

    nonisolated init() {}

    // MARK: - Configuration

    /// Initialize MSAL with the given Entra app registration credentials.
    /// Call this when credentials change (e.g., from Settings).
    func configure(clientId: String, tenantId: String) {
        guard !clientId.isEmpty, !tenantId.isEmpty,
              clientId != M365Config.defaultClientId else {
            application = nil
            isSignedIn = false
            username = nil
            lastError = "Client ID or Tenant ID not configured."
            return
        }

        let authorityString = M365Config.authority(tenantId: tenantId)
        guard let authorityURL = URL(string: authorityString) else {
            lastError = "Invalid authority URL: \(authorityString)"
            return
        }

        do {
            let authority = try MSALAADAuthority(url: authorityURL)
            let config = MSALPublicClientApplicationConfig(
                clientId: clientId,
                redirectUri: nil,
                authority: authority
            )
            application = try MSALPublicClientApplication(configuration: config)
            lastError = nil

            // Warm cache — check for existing signed-in account
            Task {
                await refreshAccountState()
            }
        } catch {
            application = nil
            lastError = "MSAL configuration failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Public API

    /// Acquire a token, trying silent acquisition first, falling back to interactive sign-in.
    func acquireToken(scopes: [String]) async throws -> String {
        guard application != nil else { throw M365AuthError.msalNotAvailable }

        if let token = try await acquireTokenSilently(scopes: scopes) {
            return token
        }
        return try await signIn(scopes: scopes)
    }

    /// Interactive sign-in via browser-delegated flow (triggers Authenticator app).
    func signIn(scopes: [String]) async throws -> String {
        guard let application else { throw M365AuthError.msalNotAvailable }

        guard let viewController = PresentationAnchorProvider.currentViewController() else {
            throw M365AuthError.noPresentationAnchor
        }

        let webParameters = MSALWebviewParameters(
            authPresentationViewController: viewController
        )
        let interactiveParameters = MSALInteractiveTokenParameters(
            scopes: scopes,
            webviewParameters: webParameters
        )

        let result: MSALResult = try await withCheckedThrowingContinuation { continuation in
            application.acquireToken(with: interactiveParameters) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let result else {
                    continuation.resume(throwing: M365AuthError.unexpectedResult("MSAL returned no result."))
                    return
                }
                continuation.resume(returning: result)
            }
        }

        cachedAccount = result.account
        username = result.account.username
        isSignedIn = true
        lastError = nil

        let accessToken = result.accessToken
        guard !accessToken.isEmpty else {
            throw M365AuthError.noAccessToken
        }

        Instrumentation.log("M365 sign-in succeeded for \(result.account.username ?? "unknown")", area: .aiAnalysis, level: .info)
        return accessToken
    }

    /// Sign out the current account and clear cached state.
    func signOut() async throws {
        guard let application else { throw M365AuthError.msalNotAvailable }

        let account = try await getCurrentAccount() ?? cachedAccount
        guard let account else { return }

        try application.remove(account)

        cachedAccount = nil
        username = nil
        isSignedIn = false
        lastError = nil
        Instrumentation.log("M365 sign-out completed", area: .aiAnalysis, level: .info)
    }

    func currentUsername() -> String? {
        cachedAccount?.username ?? username
    }

    /// Refresh the signed-in account state from MSAL cache.
    func refreshAccountState() async {
        do {
            let account = try await getCurrentAccount()
            cachedAccount = account
            username = account?.username
            isSignedIn = account != nil
        } catch {
            cachedAccount = nil
            username = nil
            isSignedIn = false
        }
    }

    // MARK: - Private Helpers

    private func acquireTokenSilently(scopes: [String]) async throws -> String? {
        guard let application else { return nil }
        let account = try await getCurrentAccount() ?? cachedAccount
        guard let account else { return nil }

        let parameters = MSALSilentTokenParameters(scopes: scopes, account: account)

        return try await withCheckedThrowingContinuation { continuation in
            application.acquireTokenSilent(with: parameters) { [weak self] result, error in
                if let nsError = error as NSError? {
                    if nsError.domain == MSALErrorDomain,
                       nsError.code == MSALError.interactionRequired.rawValue {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: nsError)
                    return
                }

                guard let result else {
                    continuation.resume(returning: nil)
                    return
                }

                Task { @MainActor in
                    self?.cachedAccount = result.account
                }
                continuation.resume(returning: result.accessToken)
            }
        }
    }

    private func getCurrentAccount() async throws -> MSALAccount? {
        guard let application else { return nil }

        return try await withCheckedThrowingContinuation { continuation in
            let parameters = MSALParameters()
            application.getCurrentAccount(with: parameters) { currentAccount, _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                nonisolated(unsafe) let account = currentAccount
                continuation.resume(returning: account)
            }
        }
    }
}

#else

/// Stub implementation when MSAL is not available.
/// Add the MSAL Swift Package (https://github.com/AzureAD/microsoft-authentication-library-for-objc)
/// to enable Microsoft 365 authentication.
@MainActor @Observable
final class MSALAuthManager: M365AuthProviding {
    private(set) var isSignedIn = false
    private(set) var username: String?
    private(set) var lastError: String? = "MSAL library not installed"

    nonisolated init() {}

    func configure(clientId: String, tenantId: String) {
        lastError = "MSAL library not installed. Add the MSAL Swift Package to enable M365 sign-in."
    }

    func acquireToken(scopes: [String]) async throws -> String {
        throw M365AuthError.msalNotAvailable
    }

    func signIn(scopes: [String]) async throws -> String {
        throw M365AuthError.msalNotAvailable
    }

    func signOut() async throws {
        throw M365AuthError.msalNotAvailable
    }

    func currentUsername() -> String? { nil }

    func refreshAccountState() async {}
}

#endif
