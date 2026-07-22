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

extension SessionParser {
    // MARK: Codex — stateful over a rollout file's lines
    static func parseCodex(lines: [String]) -> [UsageEvent] {
        var project: String?
        var model: String?
        var out: [UsageEvent] = []

        for line in lines {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String,
                  let payload = obj["payload"] as? [String: Any]
            else { continue }

            if type == "session_meta" {
                if let cwd = payload["cwd"] as? String { project = cwd }
                model = payload["model"] as? String ?? model
            } else if type == "event_msg", (payload["type"] as? String) == "token_count",
                      let info = payload["info"] as? [String: Any],
                      let u = info["last_token_usage"] as? [String: Any],
                      let project, let model {
                let rawIn = u["input_tokens"] as? Int ?? 0
                let cached = u["cached_input_tokens"] as? Int ?? 0
                let output = (u["output_tokens"] as? Int ?? 0) + (u["reasoning_output_tokens"] as? Int ?? 0)
                let input = max(0, rawIn - cached)
                if input + output + cached == 0 { continue }
                let ts = parseISODate(obj["timestamp"] as? String) ?? Date()
                out.append(UsageEvent(provider: .codex, timestamp: ts, model: model,
                    project: project, sessionId: "", input: input, output: output,
                    cacheWrite: 0, cacheRead: cached))
            }
        }
        return out
    }
}

extension SessionParser {
    // MARK: Gemini — a session file is one JSON object (or JSONL of messages)
    static func parseGemini(contents: String, project: String) -> [UsageEvent] {
        var messages: [[String: Any]] = []
        let trimmed = contents.trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = trimmed.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) {
            if let dict = obj as? [String: Any], let msgs = dict["messages"] as? [[String: Any]] {
                messages = msgs
            } else if let arr = obj as? [[String: Any]] {
                messages = arr
            }
        }
        if messages.isEmpty {   // JSONL fallback
            for line in trimmed.split(separator: "\n") {
                if let d = line.data(using: .utf8),
                   let m = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    messages.append(m)
                }
            }
        }

        var out: [UsageEvent] = []
        for m in messages where (m["type"] as? String) == "gemini" {
            guard let t = m["tokens"] as? [String: Any] else { continue }
            let rawIn = t["input"] as? Int ?? 0
            let cached = t["cached"] as? Int ?? 0
            let output = (t["output"] as? Int ?? 0) + (t["thoughts"] as? Int ?? 0) + (t["tool"] as? Int ?? 0)
            let input = max(0, rawIn - cached)
            if input + output + cached == 0 { continue }
            let model = m["model"] as? String ?? "gemini-2.5-pro"
            let ts = parseISODate(m["timestamp"] as? String) ?? Date()
            out.append(UsageEvent(provider: .gemini, timestamp: ts, model: model, project: project,
                sessionId: "", input: input, output: output, cacheWrite: 0, cacheRead: cached))
        }
        return out
    }
}
