import Foundation
import Observation

/// Tests Microsoft 365 connectivity and discovers tenant service endpoints.
///
/// After the user enters a Tenant ID and Client ID, this validator:
/// 1. Acquires a token to verify authentication
/// 2. Calls GET /me to confirm user identity
/// 3. Calls GET /sites/root to discover the SharePoint tenant root URL
/// 4. Calls GET /me/drive to discover OneDrive for Business
/// 5. Calls GET /me/joinedTeams to verify Teams access
///
/// Discovered endpoints are displayed in the Enterprise settings panel.
@MainActor @Observable
final class M365ConfigValidator {

    // MARK: - Types

    enum TestStatus: Equatable, Sendable {
        case untested
        case testing
        case success(String)
        case failed(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        var detail: String {
            switch self {
            case .untested: return ""
            case .testing: return "Testing..."
            case .success(let msg): return msg
            case .failed(let msg): return msg
            }
        }
    }

    // MARK: - State

    var authStatus: TestStatus = .untested
    var sharePointStatus: TestStatus = .untested
    var oneDriveStatus: TestStatus = .untested
    var teamsStatus: TestStatus = .untested
    var isRunning = false

    /// Whether all tests have been run and passed.
    var allPassed: Bool {
        authStatus.isSuccess && sharePointStatus.isSuccess
            && oneDriveStatus.isSuccess && teamsStatus.isSuccess
    }

    /// Whether any tests have been run.
    var hasResults: Bool {
        authStatus != .untested || sharePointStatus != .untested
            || oneDriveStatus != .untested || teamsStatus != .untested
    }

    // MARK: - Run All Tests

    /// Runs all connectivity tests sequentially.
    /// Requires the auth manager to be configured with a valid Client ID and Tenant ID.
    func runAll(authManager: MSALAuthManager) async {
        isRunning = true
        authStatus = .testing
        sharePointStatus = .testing
        oneDriveStatus = .testing
        teamsStatus = .testing

        // Step 1: Authenticate
        let token: String
        do {
            let scopes = Array(Set(
                M365Config.retrievalScopes + ["User.Read", "Team.ReadBasic.All"]
            ))
            token = try await authManager.acquireToken(scopes: scopes)
            let username = authManager.currentUsername() ?? "authenticated user"
            authStatus = .success("Signed in as \(username)")
        } catch {
            authStatus = .failed("Auth failed: \(error.localizedDescription)")
            sharePointStatus = .failed("Skipped (auth failed)")
            oneDriveStatus = .failed("Skipped (auth failed)")
            teamsStatus = .failed("Skipped (auth failed)")
            isRunning = false
            return
        }

        // Step 2: SharePoint root site
        await testSharePoint(token: token)

        // Step 3: OneDrive
        await testOneDrive(token: token)

        // Step 4: Teams
        await testTeams(token: token)

        isRunning = false
    }

    // MARK: - Individual Tests

    private func testSharePoint(token: String) async {
        sharePointStatus = .testing
        let url = M365Config.graphBaseURL.appendingPathComponent("sites/root")
        do {
            let (data, response) = try await graphGet(url: url, token: token)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                sharePointStatus = .failed("HTTP \(code)")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let webUrl = json["webUrl"] as? String,
               let displayName = json["displayName"] as? String {
                sharePointStatus = .success("\(displayName) — \(webUrl)")
            } else {
                sharePointStatus = .success("Connected (root site accessible)")
            }
        } catch {
            sharePointStatus = .failed(error.localizedDescription)
        }
    }

    private func testOneDrive(token: String) async {
        oneDriveStatus = .testing
        let url = M365Config.graphBaseURL.appendingPathComponent("me/drive")
        do {
            let (data, response) = try await graphGet(url: url, token: token)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                oneDriveStatus = .failed("HTTP \(code)")
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let webUrl = json["webUrl"] as? String {
                oneDriveStatus = .success(webUrl)
            } else {
                oneDriveStatus = .success("Connected")
            }
        } catch {
            oneDriveStatus = .failed(error.localizedDescription)
        }
    }

    private func testTeams(token: String) async {
        teamsStatus = .testing
        let url = M365Config.graphBaseURL.appendingPathComponent("me/joinedTeams")
        do {
            let (data, response) = try await graphGet(url: url, token: token)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                if code == 403 {
                    teamsStatus = .failed("Access denied — Teams scope not granted")
                } else {
                    teamsStatus = .failed("HTTP \(code)")
                }
                return
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let teams = json["value"] as? [[String: Any]] {
                let names = teams.prefix(3).compactMap { $0["displayName"] as? String }
                let preview = names.isEmpty ? "No teams found" : names.joined(separator: ", ")
                let suffix = teams.count > 3 ? " +\(teams.count - 3) more" : ""
                teamsStatus = .success("\(teams.count) teams (\(preview)\(suffix))")
            } else {
                teamsStatus = .success("Connected")
            }
        } catch {
            teamsStatus = .failed(error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func graphGet(url: URL, token: String) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await URLSession.shared.data(for: request)
    }
}
