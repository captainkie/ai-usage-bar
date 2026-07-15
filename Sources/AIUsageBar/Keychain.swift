import Foundation

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
        case .notLoggedIn:  return "Not logged in to Claude Code"
        case .decodeFailed: return "Could not read Claude credentials"
        }
    }
}

/// Reads Claude Code's OAuth credentials from the login Keychain via Apple's
/// own `/usr/bin/security` tool (read-only).
///
/// Why `security` instead of `SecItemCopyMatching`? The credential item's ACL
/// partition trusts Apple-signed binaries, so `security` reads it **without a
/// GUI Keychain prompt** — whereas a call from our own (self-signed) app would
/// pop the "allow access" dialog every install. Same item, same read, no prompt.
/// The token is used only to query your own usage; it never leaves your Mac.
func readClaudeCredentials() throws -> ClaudeCredentials {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
    process.arguments = ["find-generic-password", "-w", "-s", "Claude Code-credentials"]

    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
        try process.run()
    } catch {
        throw KeychainError.notLoggedIn
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else { throw KeychainError.notLoggedIn }
    guard let envelope = try? JSONDecoder().decode(CredentialsEnvelope.self, from: data) else {
        throw KeychainError.decodeFailed
    }
    return envelope.claudeAiOauth
}
