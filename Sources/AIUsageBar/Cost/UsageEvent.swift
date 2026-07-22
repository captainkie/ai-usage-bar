import Foundation

/// One priced-able unit of usage, normalized across providers.
struct UsageEvent {
    let provider: Provider
    let timestamp: Date
    let model: String
    let project: String        // canonical key (sanitized cwd, or "gemini:<hash>")
    let sessionId: String
    let input: Int             // uncached input tokens
    let output: Int            // output (+ reasoning/thoughts folded in)
    let cacheWrite: Int
    let cacheRead: Int

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
}

/// "/Users/x/proj" -> "Users-x-proj" (matches Claude's projects/<slug> scheme).
func sanitizeProject(_ cwd: String) -> String {
    var s = cwd
    while s.hasPrefix("/") { s.removeFirst() }
    return s.replacingOccurrences(of: "/", with: "-")
}

/// A short, human label for display: last path component, or a trimmed gemini hash.
func projectLabel(_ project: String) -> String {
    if project.hasPrefix("gemini:") {
        return "gemini:" + project.dropFirst("gemini:".count).prefix(6)
    }
    return project.split(separator: "-").last.map(String.init) ?? project
}
