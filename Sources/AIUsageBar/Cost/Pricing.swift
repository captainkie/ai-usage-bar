import Foundation

/// Per-token USD rates for one model.
struct Rates {
    let input: Double
    let output: Double
    let cacheWrite: Double
    let cacheRead: Double
}

/// Bundled, curated price table (Swift literal — no resource bundling needed).
/// Values are per-1M rates converted to per-token by `m()`. Update via releases.
final class Pricing {
    static let shared = Pricing()

    private static func m(_ inM: Double, _ outM: Double, _ cwM: Double? = nil, _ crM: Double? = nil) -> Rates {
        Rates(input: inM / 1e6, output: outM / 1e6,
              cacheWrite: (cwM ?? inM * 1.25) / 1e6,
              cacheRead: (crM ?? inM * 0.1) / 1e6)
    }

    /// Canonical id -> rates (per 1M). Reconciled against the CodeBurn snapshot
    /// (`litellm-snapshot.json`) on 2026-07-22: claude-opus-4-6/4-7/4-8 and
    /// claude-haiku-4-5 matched as-is; claude-fable-5, gpt-5-codex, and the
    /// gemini-2.5-* cache-read rates were corrected to the real per-1M values.
    private let table: [String: Rates] = [
        // Anthropic
        "claude-opus-4-8":   m(5, 25, 6.25, 0.50),
        "claude-opus-4-7":   m(5, 25, 6.25, 0.50),
        "claude-opus-4-6":   m(5, 25, 6.25, 0.50),
        "claude-sonnet-5":   m(2, 10, 2.5, 0.20),
        "claude-sonnet-4-5": m(3, 15, 3.75, 0.30),
        "claude-sonnet-4":   m(3, 15, 3.75, 0.30),
        "claude-haiku-4-5":  m(1, 5, 1.25, 0.10),
        "claude-fable-5":    m(10, 50, 12.5, 1.0),
        // OpenAI / Codex
        "gpt-5.3-codex":     m(1.75, 14, nil, 0.175),
        "gpt-5.2-codex":     m(1.75, 14, nil, 0.175),
        "gpt-5-codex":       m(1.25, 10, nil, 0.125),
        "gpt-5":             m(1.25, 10, nil, 0.125),
        // Google / Gemini
        "gemini-2.5-pro":    m(1.25, 10, nil, 0.125),
        "gemini-2.5-flash":  m(0.30, 2.5, nil, 0.03),
    ]

    /// Small alias map for variant spellings the tools emit.
    private let aliases: [String: String] = [
        "gemini-2.5-pro-preview": "gemini-2.5-pro",
        "gpt-5-codex-preview": "gpt-5-codex",
    ]

    func rate(for model: String) -> Rates? {
        // 1) strip a [..] suffix (e.g. "[1m]")
        var id = model
        if let open = id.firstIndex(of: "[") { id = String(id[..<open]) }
        // 2) exact
        if let r = table[id] { return r }
        // 3) alias
        if let a = aliases[id], let r = table[a] { return r }
        // 4) longest-prefix match against table keys
        let lower = id.lowercased()
        let match = table.keys
            .filter { lower.hasPrefix($0) || $0.hasPrefix(lower) }
            .sorted { $0.count > $1.count }
            .first
        if let k = match { return table[k] }
        return nil
    }

    func cost(for e: UsageEvent) -> Double {
        var ignore = Set<String>()
        return cost(for: e, unpriced: &ignore)
    }

    func cost(for e: UsageEvent, unpriced: inout Set<String>) -> Double {
        guard let r = rate(for: e.model) else {
            if !e.model.hasPrefix("<") { unpriced.insert(e.model) }
            return 0
        }
        return Double(e.input) * r.input
             + Double(e.output) * r.output
             + Double(e.cacheWrite) * r.cacheWrite
             + Double(e.cacheRead) * r.cacheRead
    }
}
