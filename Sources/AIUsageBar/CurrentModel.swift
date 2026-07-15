import Foundation

/// The model you're actually using, read from Claude Code's most recent local
/// transcript (read-only, never transmitted).
///
/// Why not the usage API? Its `limits[].scope.model` is a rate-limit *bucket*
/// name (e.g. "Fable"), not the model you're running — so it would mislabel an
/// Opus session as "Fable". The transcript's `message.model` is the truth.
func currentModelDisplay() -> String? {
    guard let id = readCurrentModelID() else { return nil }
    return prettyModelName(id)
}

private func readCurrentModelID() -> String? {
    let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".claude/projects")
    guard let newest = newestTranscript(under: root),
          let handle = try? FileHandle(forReadingFrom: newest)
    else { return nil }
    defer { try? handle.close() }

    // Only the tail matters — read up to the last 256 KB.
    let size = (try? handle.seekToEnd()) ?? 0
    let window: UInt64 = 262_144
    try? handle.seek(toOffset: size > window ? size - window : 0)
    guard let data = try? handle.readToEnd(),
          let text = String(data: data, encoding: .utf8) else { return nil }

    for line in text.split(separator: "\n").reversed() {
        guard let d = line.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { continue }
        if let msg = obj["message"] as? [String: Any],
           let model = msg["model"] as? String, !model.isEmpty {
            return model
        }
        if let model = obj["model"] as? String, !model.isEmpty {
            return model
        }
    }
    return nil
}

private func newestTranscript(under root: URL) -> URL? {
    let keys: [URLResourceKey] = [.contentModificationDateKey]
    guard let enumerator = FileManager.default.enumerator(
        at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
    ) else { return nil }

    var newest: URL?
    var newestDate = Date.distantPast
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? .distantPast
        if date > newestDate {
            newestDate = date
            newest = url
        }
    }
    return newest
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
    // Version = leading 1–2 digit segments (drops date stamps like 20251001).
    let version = parts.dropFirst()
        .prefix { $0.count <= 2 && $0.allSatisfy(\.isNumber) }
        .joined(separator: ".")

    var name = version.isEmpty ? String(familyName) : "\(familyName) \(version)"
    if !suffix.isEmpty { name += " · \(suffix.uppercased())" }
    return name
}
