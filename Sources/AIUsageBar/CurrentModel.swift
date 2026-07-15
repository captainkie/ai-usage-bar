import Foundation

/// The model you're actually using, read from Claude Code's local transcripts
/// (read-only, never transmitted).
///
/// Why not the usage API? Its `limits[].scope.model` is a rate-limit *bucket*
/// name (e.g. "Fable"), not the model you're running. And why not just the
/// newest file? A project can hold several sessions on different models; the
/// file with the newest mtime isn't always the one you're actively using. So we
/// pick the **most recent assistant message by timestamp**, skipping subagent
/// (sidechain) and synthetic messages.
func currentModelDisplay() -> String? {
    guard let id = readCurrentModelID() else { return nil }
    return prettyModelName(id)
}

private func readCurrentModelID() -> String? {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")

    var bestTimestamp = ""
    var bestModel: String?
    for file in newestTranscripts(under: root, limit: 6) {
        guard let (timestamp, model) = latestModel(in: file) else { continue }
        if timestamp > bestTimestamp {   // ISO-8601 Zulu strings sort chronologically
            bestTimestamp = timestamp
            bestModel = model
        }
    }
    return bestModel
}

/// The latest real, main-chain model in one transcript (scanning from the end).
private func latestModel(in file: URL) -> (timestamp: String, model: String)? {
    guard let handle = try? FileHandle(forReadingFrom: file) else { return nil }
    defer { try? handle.close() }

    let size = (try? handle.seekToEnd()) ?? 0
    let window: UInt64 = 262_144
    try? handle.seek(toOffset: size > window ? size - window : 0)
    guard let data = try? handle.readToEnd(),
          let text = String(data: data, encoding: .utf8) else { return nil }

    for line in text.split(separator: "\n").reversed() {
        guard let d = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { continue }

        if obj["isSidechain"] as? Bool == true { continue }   // subagent message
        guard let msg = obj["message"] as? [String: Any],
              let model = msg["model"] as? String,
              !model.isEmpty,
              !model.hasPrefix("<")                            // skip <synthetic>
        else { continue }

        let timestamp = obj["timestamp"] as? String ?? ""
        return (timestamp, model)
    }
    return nil
}

private func newestTranscripts(under root: URL, limit: Int) -> [URL] {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
    ) else { return [] }

    var dated: [(URL, Date)] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        dated.append((url, date))
    }
    return dated.sorted { $0.1 > $1.1 }.prefix(limit).map(\.0)
}

/// The current reasoning-effort level, from Claude Code's settings
/// (`effortLevel`, e.g. "xhigh"). Read-only, local.
func currentEffortDisplay() -> String? {
    let home = FileManager.default.homeDirectoryForCurrentUser
    for name in [".claude/settings.local.json", ".claude/settings.json"] {
        let url = home.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let level = obj["effortLevel"] as? String, !level.isEmpty
        else { continue }
        return prettyEffort(level)
    }
    return nil
}

func prettyEffort(_ raw: String) -> String {
    switch raw.lowercased() {
    case "low":    return "Low"
    case "medium": return "Medium"
    case "high":   return "High"
    case "xhigh":  return "xHigh"
    case "max":    return "Max"
    default:       return raw.prefix(1).uppercased() + raw.dropFirst()
    }
}

/// "claude-opus-4-8" -> "Opus 4.8", "claude-haiku-4-5-20251001" -> "Haiku 4.5",
/// "claude-opus-4-8[1m]" -> "Opus 4.8 · 1M".
func prettyModelName(_ id: String) -> String {
    var base = id
    var suffix = ""
    if let open = base.firstIndex(of: "["), let close = base.firstIndex(of: "]"), open < close {
        suffix = String(base[base.index(after: open)..<close])
        base = String(base[..<open])
    }
    if base.hasPrefix("claude-") { base = String(base.dropFirst("claude-".count)) }

    let parts = base.split(separator: "-")
    guard let family = parts.first else { return id }
    let familyName = family.prefix(1).uppercased() + family.dropFirst()
    let version = parts.dropFirst()
        .prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        .joined(separator: ".")

    var name = version.isEmpty ? String(familyName) : "\(familyName) \(version)"
    if !suffix.isEmpty { name += " · \(suffix.uppercased())" }
    return name
}
