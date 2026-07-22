import Foundation

/// One priced-able unit of usage, normalized across providers.
struct UsageEvent {
    let provider: Provider
    let timestamp: Date
    let model: String
    let project: String        // canonical key: raw cwd path, or "gemini:<hash>"
    let sessionId: String
    let input: Int             // uncached input tokens
    let output: Int            // output (+ reasoning/thoughts folded in)
    let cacheWrite: Int
    let cacheRead: Int

    var totalTokens: Int { input + output + cacheWrite + cacheRead }
}

/// A short, human label for display: the working directory's last path
/// component, or a trimmed gemini hash. `project` is the raw cwd path, so this
/// is a clean, reversible mapping (no lossy de-sanitizing of a "-"-joined slug).
func projectLabel(_ project: String) -> String {
    if project.hasPrefix("gemini:") {
        return "gemini:" + project.dropFirst("gemini:".count).prefix(6)
    }
    let label = URL(fileURLWithPath: project).lastPathComponent
    return label.isEmpty ? project : label
}
