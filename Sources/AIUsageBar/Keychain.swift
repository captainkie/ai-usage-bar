import Foundation
import Security

/// The credential blob Claude Code stores in the macOS Keychain under the
/// generic-password service "Claude Code-credentials".
struct ClaudeCredentials: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Double?
    let subscriptionType: String?
    let rateLimitTier: String?
}

private struct CredentialsEnvelope: Decodable {
    let claudeAiOauth: ClaudeCredentials
}

enum KeychainError: LocalizedError {
    case notLoggedIn
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .notLoggedIn:
            return "Not logged in to Claude Code"
        case .decodeFailed:
            return "Could not read Claude credentials"
        }
    }
}

/// Reads Claude Code's OAuth credentials straight from the login Keychain.
/// Read-only; the token never leaves this machine.
func readClaudeCredentials() throws -> ClaudeCredentials {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "Claude Code-credentials",
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]

    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)

    guard status == errSecSuccess, let data = result as? Data else {
        throw KeychainError.notLoggedIn
    }

    guard let envelope = try? JSONDecoder().decode(CredentialsEnvelope.self, from: data) else {
        throw KeychainError.decodeFailed
    }

    return envelope.claudeAiOauth
}
