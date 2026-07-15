import Foundation

/// The AI CLIs the app knows about. Only Claude is wired to a live usage feed
/// today; the others are scanned/listed so the UI is ready for them.
enum Provider: String, CaseIterable, Codable, Identifiable {
    case claude, codex, gemini, opencode

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude:   return "Claude Code"
        case .codex:    return "Codex"
        case .gemini:   return "Gemini"
        case .opencode: return "OpenCode"
        }
    }

    /// Whether the app can actually show live usage for this provider yet.
    var isSupported: Bool { self == .claude }
}

struct ProviderScan: Identifiable {
    let provider: Provider
    let installed: Bool
    var id: String { provider.id }
}

/// Detects which AI CLIs you're actually signed in to — by looking for the
/// credential each one writes locally. Read-only; checks existence only.
enum ProviderScanner {
    static func scan() -> [ProviderScan] {
        Provider.allCases.map { ProviderScan(provider: $0, installed: isSignedIn($0)) }
    }

    static func isSignedIn(_ provider: Provider) -> Bool {
        switch provider {
        case .claude:
            // macOS stores the token in the Keychain, but the profile dir is a
            // reliable, prompt-free signal.
            return exists(".claude/projects") || exists(".claude")
        case .codex:
            return exists(".codex/auth.json")
        case .gemini:
            return exists(".gemini/oauth_creds.json")
        case .opencode:
            return exists(".opencode/auth.json") || exists(".local/share/opencode/auth.json")
        }
    }

    private static func exists(_ relativePath: String) -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path)
    }
}
