import Foundation

enum SessionParser {

    // MARK: Claude — one JSONL line per message
    static func parseClaude(line: Substring, fallbackProject: String) -> UsageEvent? {
        parseClaude(line: String(line), fallbackProject: fallbackProject)
    }

    static func parseClaude(line: String, fallbackProject: String) -> UsageEvent? {
        guard let data = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["type"] as? String) == "assistant",
              let msg = obj["message"] as? [String: Any],
              let model = msg["model"] as? String, !model.hasPrefix("<"),
              let usage = msg["usage"] as? [String: Any]
        else { return nil }

        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cw = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cr = usage["cache_read_input_tokens"] as? Int ?? 0
        if input + output + cw + cr == 0 { return nil }

        let ts = parseISODate(obj["timestamp"] as? String) ?? Date()
        let project = (obj["cwd"] as? String) ?? fallbackProject
        let sid = obj["sessionId"] as? String ?? ""
        return UsageEvent(provider: .claude, timestamp: ts, model: model, project: project,
                          sessionId: sid, input: input, output: output, cacheWrite: cw, cacheRead: cr)
    }
}
