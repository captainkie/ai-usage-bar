import Foundation

/// Codable mirror of UsageEvent for on-disk caching.
struct CachedEvent: Codable {
    let provider: String, ts: Double, model: String, project: String, sid: String
    let input: Int, output: Int, cacheWrite: Int, cacheRead: Int
    init(_ e: UsageEvent) {
        provider = e.provider.rawValue; ts = e.timestamp.timeIntervalSince1970
        model = e.model; project = e.project; sid = e.sessionId
        input = e.input; output = e.output; cacheWrite = e.cacheWrite; cacheRead = e.cacheRead
    }
    func toEvent() -> UsageEvent {
        UsageEvent(provider: Provider(rawValue: provider) ?? .claude,
                   timestamp: Date(timeIntervalSince1970: ts), model: model, project: project,
                   sessionId: sid, input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
    }
}

/// Application-Support cache of parsed events keyed by "path|size|mtime".
final class CostCache {
    struct FileEntry: Codable { let key: String; let events: [CachedEvent] }
    private let url: URL
    private var byKey: [String: [CachedEvent]] = [:]

    init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        url = dir.appendingPathComponent("cost-cache.json")
        if let data = try? Data(contentsOf: url),
           let entries = try? JSONDecoder().decode([FileEntry].self, from: data) {
            for e in entries { byKey[e.key] = e.events }
        }
    }

    static func fileKey(_ url: URL) -> String? {
        guard let v = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = v.fileSize, let m = v.contentModificationDate else { return nil }
        return "\(url.path)|\(size)|\(Int(m.timeIntervalSince1970))"
    }
    func cached(_ key: String) -> [UsageEvent]? { byKey[key]?.map { $0.toEvent() } }
    func store(_ key: String, _ events: [UsageEvent]) { byKey[key] = events.map(CachedEvent.init) }
    func retain(keys: Set<String>) { byKey = byKey.filter { keys.contains($0.key) } }
    func persist() {
        let entries = byKey.map { FileEntry(key: $0.key, events: $0.value) }
        if let data = try? JSONEncoder().encode(entries) { try? data.write(to: url) }
    }
}
