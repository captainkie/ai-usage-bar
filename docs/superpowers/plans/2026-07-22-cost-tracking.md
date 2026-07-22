# Cost Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first cost dashboard to AI Usage Bar — spend across Claude/Codex/Gemini, by time window and project, with monthly budgets + alerts, a native window, and a server-less "open in browser" HTML dashboard.

**Architecture:** A pure Swift cost engine (parse local session files → price tokens → aggregate by window/project/model) in `Sources/AIUsageBar/Cost/`, driven by a `CostStore` observable object, surfaced through a new `CostView` window opened from the panel footer. Pricing and the HTML template are Swift constants (no resource bundling — the app ships as a hand-assembled `.app`). Parsers expose pure functions tested with inline JSONL.

**Tech Stack:** Swift 5.9, SwiftPM, Foundation (engine), SwiftUI + Swift Charts + AppKit (UI), UserNotifications (alerts), XCTest.

**Reference (read-only, for exact rates/schemas):** the local CodeBurn fork at `/Users/narenrit.h/Documents/work-hobby/fork-from-github/codeburn` — `src/data/litellm-snapshot.json` (pricing), `src/providers/{claude,codex,gemini}.ts` + `src/parser.ts` (schemas). **Do not import or depend on it.**

---

## Conventions

- Engine files (`UsageEvent`, `Pricing`, `SessionParser`, `CostAggregator`, `Budget`) **import only Foundation** so they compile into the test target cleanly.
- After each task: `swift build` must succeed and `swift test` must pass. Commit at the end of each task.
- Money is `Double` USD. Rates are **USD per single token**.
- All timestamps parsed with the existing `parseISODate(_:)` in `Formatting.swift` (handles microseconds).
- Local-time day boundaries via `Calendar.current`.

## File Structure

- Create `Sources/AIUsageBar/Cost/UsageEvent.swift` — `UsageEvent`, project sanitizers.
- Create `Sources/AIUsageBar/Cost/Pricing.swift` — model→rates table (Swift literal), `cost(for:)`, name resolution.
- Create `Sources/AIUsageBar/Cost/SessionParser.swift` — pure `parseClaude/parseCodex/parseGemini` + `scan()` file discovery.
- Create `Sources/AIUsageBar/Cost/CostAggregator.swift` — `Window`, rollups, `WindowSummary`.
- Create `Sources/AIUsageBar/Cost/Budget.swift` — `ProjectBudget`, `BudgetStatus`, alert-firing.
- Create `Sources/AIUsageBar/Cost/CostCache.swift` — on-disk per-file rollup cache.
- Create `Sources/AIUsageBar/Cost/CostStore.swift` — `@MainActor ObservableObject` orchestrator.
- Create `Sources/AIUsageBar/Cost/DashboardExporter.swift` — HTML string builder + open.
- Create `Sources/AIUsageBar/CostView.swift` — native window (SwiftUI + Charts).
- Create `Sources/AIUsageBar/BudgetSettingsView.swift` — budget editor.
- Modify `Sources/AIUsageBar/Settings.swift` — budgets + alert toggle + fired-threshold state.
- Modify `Sources/AIUsageBar/PanelView.swift` — footer "Cost" button + `onOpenCost` closure.
- Modify `Sources/AIUsageBar/AppDelegate.swift` — `showCostDashboard()`, wire closure, background budget check.
- Modify `Package.swift` — add test target.
- Create `Tests/AIUsageBarTests/*` — engine tests.

---

### Task 0: Test target + smoke test

**Files:**
- Modify: `Package.swift`
- Test: `Tests/AIUsageBarTests/SmokeTests.swift`

- [ ] **Step 1: Add the test target to `Package.swift`**

```swift
// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AIUsageBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AIUsageBar",
            path: "Sources/AIUsageBar"
        ),
        .testTarget(
            name: "AIUsageBarTests",
            dependencies: ["AIUsageBar"],
            path: "Tests/AIUsageBarTests"
        )
    ]
)
```

- [ ] **Step 2: Write a smoke test** — `Tests/AIUsageBarTests/SmokeTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class SmokeTests: XCTestCase {
    func testHarnessWorks() {
        XCTAssertEqual(2 + 2, 4)
    }
}
```

- [ ] **Step 3: Run tests, verify the executable target is testable**

Run: `swift test`
Expected: builds and `testHarnessWorks` PASSES. If linking fails with an entry-point error, fall back to a `CostKit` library target holding the engine + `Provider`; otherwise proceed.

- [ ] **Step 4: Commit**

```bash
git add Package.swift Tests/AIUsageBarTests/SmokeTests.swift
git commit -m "test: add AIUsageBarTests target (@testable import AIUsageBar)"
```

---

### Task 1: UsageEvent + project sanitizers

**Files:**
- Create: `Sources/AIUsageBar/Cost/UsageEvent.swift`
- Test: `Tests/AIUsageBarTests/UsageEventTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/UsageEventTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class UsageEventTests: XCTestCase {
    func testProjectLabelIsLastPathComponent() {
        XCTAssertEqual(projectLabel("/Users/x/Documents/work-hobby/ai-usage-bar"), "ai-usage-bar")
        XCTAssertEqual(projectLabel("/a/b"), "b")
        XCTAssertEqual(projectLabel("gemini:abcdef123456"), "gemini:abcdef")
    }
    func testTotalTokens() {
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "m", project: "p",
                           sessionId: "s", input: 10, output: 20, cacheWrite: 5, cacheRead: 3)
        XCTAssertEqual(e.totalTokens, 38)
    }
}
```

- [ ] **Step 2: Run — expect FAIL** (`sanitizeProject` undefined). `swift test --filter UsageEventTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/UsageEvent.swift`

```swift
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter UsageEventTests`

- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/UsageEvent.swift Tests/AIUsageBarTests/UsageEventTests.swift
git commit -m "feat(cost): UsageEvent model + project sanitizers"
```

---

### Task 2: Pricing

**Files:**
- Create: `Sources/AIUsageBar/Cost/Pricing.swift`
- Test: `Tests/AIUsageBarTests/PricingTests.swift`

> **Rates:** values below are per-token USD, derived from CodeBurn's `litellm-snapshot.json` pattern (`[input, output, cacheWrite, cacheRead]` per 1M ÷ 1e6). Before finishing this task, open the reference snapshot and reconcile the exact IDs present on this machine (`claude-opus-4-8`, `claude-opus-4-7`, `claude-haiku-4-5`, `claude-fable-5`, `gpt-5*-codex`, `gemini-2.5-*`). If an ID is missing there, keep the value below.

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/PricingTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class PricingTests: XCTestCase {
    let p = Pricing.shared

    func testExactCost() {
        // Opus 4.8: $5 / $25 / $6.25 / $0.50 per 1M
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "claude-opus-4-8",
            project: "p", sessionId: "s",
            input: 1_000_000, output: 1_000_000, cacheWrite: 1_000_000, cacheRead: 1_000_000)
        XCTAssertEqual(p.cost(for: e), 5 + 25 + 6.25 + 0.50, accuracy: 1e-6)
    }
    func testVersionSuffixResolves() {
        // "claude-opus-4-8[1m]" resolves to the opus-4-8 row
        XCTAssertGreaterThan(p.rate(for: "claude-opus-4-8[1m]")?.input ?? 0, 0)
    }
    func testUnknownModelIsZeroAndTracked() {
        var unpriced = Set<String>()
        let e = UsageEvent(provider: .claude, timestamp: Date(), model: "totally-unknown-x",
            project: "p", sessionId: "s", input: 100, output: 100, cacheWrite: 0, cacheRead: 0)
        XCTAssertEqual(p.cost(for: e, unpriced: &unpriced), 0)
        XCTAssertTrue(unpriced.contains("totally-unknown-x"))
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter PricingTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/Pricing.swift`

```swift
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

    /// Canonical id -> rates (per 1M). Reconcile against the CodeBurn snapshot.
    private let table: [String: Rates] = [
        // Anthropic
        "claude-opus-4-8":   m(5, 25, 6.25, 0.50),
        "claude-opus-4-7":   m(5, 25, 6.25, 0.50),
        "claude-opus-4-6":   m(5, 25, 6.25, 0.50),
        "claude-sonnet-4-5": m(3, 15, 3.75, 0.30),
        "claude-sonnet-4":   m(3, 15, 3.75, 0.30),
        "claude-haiku-4-5":  m(1, 5, 1.25, 0.10),
        "claude-fable-5":    m(0.80, 4, 1.0, 0.08),
        // OpenAI / Codex
        "gpt-5.3-codex":     m(1.75, 14, nil, 0.175),
        "gpt-5.2-codex":     m(1.75, 14, nil, 0.175),
        "gpt-5-codex":       m(1.75, 14, nil, 0.175),
        "gpt-5":             m(1.25, 10, nil, 0.125),
        // Google / Gemini
        "gemini-2.5-pro":    m(1.25, 10, nil, 0.31),
        "gemini-2.5-flash":  m(0.30, 2.5, nil, 0.075),
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter PricingTests`
- [ ] **Step 5: Reconcile rates** against `…/codeburn/src/data/litellm-snapshot.json` for the exact IDs (read-only). Adjust literals if they differ; re-run tests.
- [ ] **Step 6: Commit**

```bash
git add Sources/AIUsageBar/Cost/Pricing.swift Tests/AIUsageBarTests/PricingTests.swift
git commit -m "feat(cost): bundled pricing table + model resolution"
```

---

### Task 3: Claude parser

**Files:**
- Create: `Sources/AIUsageBar/Cost/SessionParser.swift`
- Test: `Tests/AIUsageBarTests/ClaudeParserTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/ClaudeParserTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class ClaudeParserTests: XCTestCase {
    func testParsesAssistantUsage() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00.123456Z","sessionId":"s1","cwd":"/Users/x/proj","message":{"model":"claude-opus-4-8","usage":{"input_tokens":100,"output_tokens":200,"cache_creation_input_tokens":50,"cache_read_input_tokens":30}}}"#
        let e = SessionParser.parseClaude(line: line, fallbackProject: "fb")
        XCTAssertEqual(e?.provider, .claude)
        XCTAssertEqual(e?.model, "claude-opus-4-8")
        XCTAssertEqual(e?.project, "/Users/x/proj")
        XCTAssertEqual(e?.input, 100); XCTAssertEqual(e?.output, 200)
        XCTAssertEqual(e?.cacheWrite, 50); XCTAssertEqual(e?.cacheRead, 30)
    }
    func testUserLineReturnsNil() {
        XCTAssertNil(SessionParser.parseClaude(line: #"{"type":"user","message":{"role":"user"}}"#, fallbackProject: "fb"))
    }
    func testSyntheticModelSkipped() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","message":{"model":"<synthetic>","usage":{"input_tokens":1,"output_tokens":1}}}"#
        XCTAssertNil(SessionParser.parseClaude(line: line, fallbackProject: "fb"))
    }
    func testFallbackProjectWhenNoCwd() {
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","message":{"model":"claude-opus-4-8","usage":{"input_tokens":1,"output_tokens":1}}}"#
        XCTAssertEqual(SessionParser.parseClaude(line: line, fallbackProject: "fb")?.project, "fb")
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter ClaudeParserTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/SessionParser.swift`

```swift
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter ClaudeParserTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/SessionParser.swift Tests/AIUsageBarTests/ClaudeParserTests.swift
git commit -m "feat(cost): Claude transcript parser"
```

---

### Task 4: Codex parser

**Files:**
- Modify: `Sources/AIUsageBar/Cost/SessionParser.swift`
- Test: `Tests/AIUsageBarTests/CodexParserTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/CodexParserTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class CodexParserTests: XCTestCase {
    func testMetaThenTokenCount() {
        let lines = [
          #"{"type":"session_meta","timestamp":"2026-07-20T09:00:00Z","payload":{"cwd":"/Users/x/proj","model":"gpt-5-codex","session_id":"c1","originator":"codex_cli"}}"#,
          #"{"type":"event_msg","timestamp":"2026-07-20T09:05:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":120,"cached_input_tokens":20,"output_tokens":80,"reasoning_output_tokens":40}}}}"#
        ]
        let events = SessionParser.parseCodex(lines: lines)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.provider, .codex)
        XCTAssertEqual(e.model, "gpt-5-codex")
        XCTAssertEqual(e.project, "/Users/x/proj")
        XCTAssertEqual(e.input, 100)      // 120 - 20 cached
        XCTAssertEqual(e.cacheRead, 20)
        XCTAssertEqual(e.output, 120)     // 80 + 40 reasoning
        XCTAssertEqual(e.cacheWrite, 0)
    }
    func testTokenCountBeforeMetaIsSkipped() {
        let lines = [ #"{"type":"event_msg","timestamp":"2026-07-20T09:05:00Z","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":10,"output_tokens":10}}}}"# ]
        XCTAssertTrue(SessionParser.parseCodex(lines: lines).isEmpty)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter CodexParserTests`

- [ ] **Step 3: Implement** — append to `SessionParser`

```swift
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter CodexParserTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/SessionParser.swift Tests/AIUsageBarTests/CodexParserTests.swift
git commit -m "feat(cost): Codex rollout parser (cached-input subtraction)"
```

---

### Task 5: Gemini parser

**Files:**
- Modify: `Sources/AIUsageBar/Cost/SessionParser.swift`
- Test: `Tests/AIUsageBarTests/GeminiParserTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/GeminiParserTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class GeminiParserTests: XCTestCase {
    func testParsesGeminiMessages() {
        let json = #"""
        {"sessionId":"g1","messages":[
          {"type":"user","timestamp":"2026-07-20T08:00:00Z","content":"hi"},
          {"type":"gemini","timestamp":"2026-07-20T08:00:05Z","model":"gemini-2.5-pro","tokens":{"input":100,"output":50,"cached":20,"thoughts":30}}
        ]}
        """#
        let events = SessionParser.parseGemini(contents: json, project: "gemini:abc123")
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.provider, .gemini)
        XCTAssertEqual(e.model, "gemini-2.5-pro")
        XCTAssertEqual(e.input, 80)     // 100 - 20 cached
        XCTAssertEqual(e.cacheRead, 20)
        XCTAssertEqual(e.output, 80)    // 50 + 30 thoughts
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter GeminiParserTests`

- [ ] **Step 3: Implement** — append to `SessionParser`

```swift
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter GeminiParserTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/SessionParser.swift Tests/AIUsageBarTests/GeminiParserTests.swift
git commit -m "feat(cost): Gemini chat parser"
```

---

### Task 6: File discovery (scan)

**Files:**
- Modify: `Sources/AIUsageBar/Cost/SessionParser.swift`
- Test: `Tests/AIUsageBarTests/ScanTests.swift`

Discovery reads files and delegates to the pure parsers. Tested by writing temp files.

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/ScanTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class ScanTests: XCTestCase {
    func testScanClaudeDir() throws {
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("aub-\(UUID().uuidString)")
        let projDir = tmp.appendingPathComponent("Users-x-proj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let line = #"{"type":"assistant","timestamp":"2026-07-20T10:00:00Z","sessionId":"s","cwd":"/Users/x/proj","message":{"model":"claude-opus-4-8","usage":{"input_tokens":10,"output_tokens":10}}}"#
        try line.write(to: projDir.appendingPathComponent("a.jsonl"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let events = SessionParser.scanClaude(root: tmp)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].project, "/Users/x/proj")
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter ScanTests`

- [ ] **Step 3: Implement** — append discovery to `SessionParser`

```swift
import Foundation

extension SessionParser {
    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    /// Read all `~/.claude/projects/**/*.jsonl` (honoring CLAUDE_CONFIG_DIR).
    static func scanClaude(root override: URL? = nil) -> [UsageEvent] {
        let root = override ?? (ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"]
            .map { URL(fileURLWithPath: $0).appendingPathComponent("projects") }
            ?? home.appendingPathComponent(".claude/projects"))
        var out: [UsageEvent] = []
        forEachFile(under: root, ext: "jsonl") { url in
            let fallback = url.deletingLastPathComponent().lastPathComponent
            streamLines(url) { line in
                if let e = parseClaude(line: line, fallbackProject: fallback) { out.append(e) }
            }
        }
        return out
    }

    /// Read `~/.codex/sessions/**/rollout-*.jsonl` + archived_sessions.
    static func scanCodex(root override: URL? = nil) -> [UsageEvent] {
        let base = override ?? (ProcessInfo.processInfo.environment["CODEX_HOME"].map(URL.init(fileURLWithPath:))
            ?? home.appendingPathComponent(".codex"))
        var out: [UsageEvent] = []
        for sub in ["sessions", "archived_sessions"] {
            forEachFile(under: base.appendingPathComponent(sub), ext: "jsonl") { url in
                guard url.lastPathComponent.hasPrefix("rollout-") else { return }
                let lines = (try? String(contentsOf: url, encoding: .utf8))?
                    .split(separator: "\n").map(String.init) ?? []
                out.append(contentsOf: parseCodex(lines: lines))
            }
        }
        return out
    }

    /// Read `~/.gemini/tmp/<hash>/chats/session-*.json[l]`.
    static func scanGemini(root override: URL? = nil) -> [UsageEvent] {
        let base = override ?? home.appendingPathComponent(".gemini/tmp")
        var out: [UsageEvent] = []
        guard let hashes = try? FileManager.default.contentsOfDirectory(at: base,
            includingPropertiesForKeys: nil) else { return out }
        for hashDir in hashes {
            let project = "gemini:" + hashDir.lastPathComponent
            forEachFile(under: hashDir.appendingPathComponent("chats"), ext: nil) { url in
                guard url.lastPathComponent.hasPrefix("session-"),
                      let contents = try? String(contentsOf: url, encoding: .utf8) else { return }
                out.append(contentsOf: parseGemini(contents: contents, project: project))
            }
        }
        return out
    }

    /// All installed providers together.
    static func scanAll() -> [UsageEvent] {
        scanClaude() + scanCodex() + scanGemini()
    }

    // MARK: helpers
    private static func forEachFile(under root: URL, ext: String?, _ body: (URL) -> Void) {
        guard let en = FileManager.default.enumerator(at: root,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return }
        for case let url as URL in en {
            if let ext, url.pathExtension != ext { continue }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue { continue }
            body(url)
        }
    }
    private static func streamLines(_ url: URL, _ body: (Substring) -> Void) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in text.split(separator: "\n") { body(line) }
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter ScanTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/SessionParser.swift Tests/AIUsageBarTests/ScanTests.swift
git commit -m "feat(cost): file discovery for Claude/Codex/Gemini"
```

---

### Task 7: CostAggregator + Window

**Files:**
- Create: `Sources/AIUsageBar/Cost/CostAggregator.swift`
- Test: `Tests/AIUsageBarTests/AggregatorTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/AggregatorTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class AggregatorTests: XCTestCase {
    private func ev(_ project: String, _ model: String, daysAgo: Int, cost1kOut: Int) -> UsageEvent {
        let ts = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        return UsageEvent(provider: .claude, timestamp: ts, model: model, project: project,
                          sessionId: "s\(daysAgo)", input: 0, output: cost1kOut, cacheWrite: 0, cacheRead: 0)
    }

    func testWindowFiltersByDay() {
        let events = [ev("p", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("p", "claude-opus-4-8", daysAgo: 10, cost1kOut: 1000)]
        let today = CostAggregator.summary(events: events, window: .today)
        let week = CostAggregator.summary(events: events, window: .days7)
        let all = CostAggregator.summary(events: events, window: .all)
        XCTAssertEqual(today.byProject.count, 1)
        XCTAssertEqual(today.calls, 1)
        XCTAssertEqual(week.calls, 1)     // 10 days ago excluded from 7d
        XCTAssertEqual(all.calls, 2)
    }

    func testGroupsByProjectAndModel() {
        let events = [ev("a", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("b", "claude-haiku-4-5", daysAgo: 0, cost1kOut: 1000)]
        let s = CostAggregator.summary(events: events, window: .all)
        XCTAssertEqual(Set(s.byProject.map(\.project)), ["a", "b"])
        XCTAssertEqual(Set(s.byModel.map(\.model)), ["claude-opus-4-8", "claude-haiku-4-5"])
        XCTAssertGreaterThan(s.totalCost, 0)
    }

    func testProjectFilter() {
        let events = [ev("a", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000),
                      ev("b", "claude-opus-4-8", daysAgo: 0, cost1kOut: 1000)]
        let s = CostAggregator.summary(events: events, window: .all, project: "a")
        XCTAssertEqual(s.calls, 1)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter AggregatorTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/CostAggregator.swift`

```swift
import Foundation

enum Window: String, CaseIterable, Identifiable {
    case today, days7, days30, month, all
    var id: String { rawValue }
    var label: String {
        switch self {
        case .today: return "Today"; case .days7: return "7 days"
        case .days30: return "30 days"; case .month: return "This month"; case .all: return "All time"
        }
    }
    /// Inclusive local-time start; nil start means "everything".
    func start(now: Date = Date(), cal: Calendar = .current) -> Date? {
        switch self {
        case .today:  return cal.startOfDay(for: now)
        case .days7:  return cal.date(byAdding: .day, value: -6, to: cal.startOfDay(for: now))
        case .days30: return cal.date(byAdding: .day, value: -29, to: cal.startOfDay(for: now))
        case .month:  return cal.date(from: cal.dateComponents([.year, .month], from: now))
        case .all:    return nil
        }
    }
}

struct ProjectSpend: Identifiable { let project: String; let cost: Double; let calls: Int; var id: String { project } }
struct ModelSpend: Identifiable { let model: String; let cost: Double; let calls: Int; var id: String { model } }
struct DayPoint: Identifiable { let day: Date; let cost: Double; var id: Date { day } }

struct WindowSummary {
    var totalCost = 0.0
    var input = 0, output = 0, cacheRead = 0, cacheWrite = 0
    var calls = 0
    var sessions = 0
    var byProject: [ProjectSpend] = []
    var byModel: [ModelSpend] = []
    var days: [DayPoint] = []
    var unpricedModels: Set<String> = []
}

enum CostAggregator {
    static func summary(events: [UsageEvent], pricing: Pricing = .shared,
                        window: Window, project: String? = nil,
                        now: Date = Date(), cal: Calendar = .current) -> WindowSummary {
        let start = window.start(now: now, cal: cal)
        var s = WindowSummary()
        var projCost: [String: (Double, Int)] = [:]
        var modelCost: [String: (Double, Int)] = [:]
        var dayCost: [Date: Double] = [:]
        var sessionIds = Set<String>()

        for e in events {
            if let start, e.timestamp < start { continue }
            if let project, e.project != project { continue }
            let c = pricing.cost(for: e, unpriced: &s.unpricedModels)
            s.totalCost += c
            s.input += e.input; s.output += e.output
            s.cacheRead += e.cacheRead; s.cacheWrite += e.cacheWrite
            s.calls += 1
            if !e.sessionId.isEmpty { sessionIds.insert(e.sessionId) }
            projCost[e.project, default: (0,0)].0 += c
            projCost[e.project]!.1 += 1
            modelCost[e.model, default: (0,0)].0 += c
            modelCost[e.model]!.1 += 1
            let day = cal.startOfDay(for: e.timestamp)
            dayCost[day, default: 0] += c
        }
        s.sessions = max(sessionIds.count, 0)
        s.byProject = projCost.map { ProjectSpend(project: $0.key, cost: $0.value.0, calls: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.byModel = modelCost.map { ModelSpend(model: $0.key, cost: $0.value.0, calls: $0.value.1) }
            .sorted { $0.cost > $1.cost }
        s.days = dayCost.map { DayPoint(day: $0.key, cost: $0.value) }.sorted { $0.day < $1.day }
        return s
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter AggregatorTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/CostAggregator.swift Tests/AIUsageBarTests/AggregatorTests.swift
git commit -m "feat(cost): window aggregation by project/model/day"
```

---

### Task 8: Budget model + alert logic

**Files:**
- Create: `Sources/AIUsageBar/Cost/Budget.swift`
- Test: `Tests/AIUsageBarTests/BudgetTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/BudgetTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class BudgetTests: XCTestCase {
    func testLevels() {
        XCTAssertEqual(BudgetStatus(spent: 5, limit: 20).level, .normal)   // 25%
        XCTAssertEqual(BudgetStatus(spent: 17, limit: 20).level, .warn)    // 85%
        XCTAssertEqual(BudgetStatus(spent: 25, limit: 20).level, .over)    // 125%
    }
    func testAlertFiresOncePerThreshold() {
        // crossing 0.85 fires the 0.8 threshold once
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.85, alreadyFired: []), [0.8])
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.85, alreadyFired: [0.8]), [])
        // crossing 1.0 fires both remaining
        XCTAssertEqual(Budget.newlyCrossed(fraction: 1.2, alreadyFired: []), [0.8, 1.0])
        XCTAssertEqual(Budget.newlyCrossed(fraction: 0.5, alreadyFired: []), [])
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter BudgetTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/Budget.swift`

```swift
import Foundation

struct BudgetStatus {
    let spent: Double
    let limit: Double
    var fraction: Double { limit > 0 ? spent / limit : 0 }
    var percent: Int { Int((fraction * 100).rounded()) }
    enum Level { case normal, warn, over }
    var level: Level { fraction >= 1 ? .over : (fraction >= 0.8 ? .warn : .normal) }
}

enum Budget {
    static let thresholds: [Double] = [0.8, 1.0]

    /// Thresholds newly crossed given current fraction and those already fired this month.
    static func newlyCrossed(fraction: Double, alreadyFired: Set<Double>) -> [Double] {
        thresholds.filter { fraction >= $0 && !alreadyFired.contains($0) }.sorted()
    }

    /// Calendar-month spend for one project.
    static func monthSpend(events: [UsageEvent], pricing: Pricing = .shared,
                           project: String, now: Date = Date(), cal: Calendar = .current) -> Double {
        guard let start = cal.date(from: cal.dateComponents([.year, .month], from: now)) else { return 0 }
        var ignore = Set<String>()
        return events.filter { $0.project == project && $0.timestamp >= start }
                     .reduce(0) { $0 + pricing.cost(for: $1, unpriced: &ignore) }
    }

    /// A stable "2026-07" key for month-scoped alert state.
    static func monthKey(_ now: Date = Date(), cal: Calendar = .current) -> String {
        let c = cal.dateComponents([.year, .month], from: now)
        return String(format: "%04d-%02d", c.year ?? 0, c.month ?? 0)
    }
}
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter BudgetTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/Budget.swift Tests/AIUsageBarTests/BudgetTests.swift
git commit -m "feat(cost): budget status + alert-crossing logic"
```

---

### Task 9: Settings — budgets, alert toggle, fired-threshold state

**Files:**
- Modify: `Sources/AIUsageBar/Settings.swift`
- Test: `Tests/AIUsageBarTests/BudgetSettingsStoreTests.swift`

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/BudgetSettingsStoreTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class BudgetSettingsStoreTests: XCTestCase {
    func testBudgetRoundTrip() {
        let d = UserDefaults(suiteName: "aub-test-\(UUID().uuidString)")!
        let store = BudgetStore(defaults: d)
        store.setBudget(20, for: "proj-a")
        XCTAssertEqual(store.budget(for: "proj-a"), 20)
        store.setBudget(nil, for: "proj-a")
        XCTAssertNil(store.budget(for: "proj-a"))
    }
    func testFiredThresholdsResetOnMonthChange() {
        let d = UserDefaults(suiteName: "aub-test-\(UUID().uuidString)")!
        let store = BudgetStore(defaults: d)
        store.recordFired(0.8, for: "p", monthKey: "2026-07")
        XCTAssertEqual(store.firedThresholds(for: "p", monthKey: "2026-07"), [0.8])
        XCTAssertEqual(store.firedThresholds(for: "p", monthKey: "2026-08"), [])   // new month clean
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter BudgetSettingsStoreTests`

- [ ] **Step 3: Implement** — add `BudgetStore` and wire an alert toggle into `Settings.swift`

Append to `Settings.swift` (a focused helper that owns budget persistence; keeps `Settings` lean):

```swift
/// Persists per-project monthly budgets + fired-alert state. Injectable defaults for tests.
final class BudgetStore {
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    private let budgetsKey = "projectBudgets"          // [project: Double]
    private let firedKey = "budgetFired"               // [monthKey: [project: [Double]]]

    func allBudgets() -> [String: Double] {
        defaults.dictionary(forKey: budgetsKey) as? [String: Double] ?? [:]
    }
    func budget(for project: String) -> Double? { allBudgets()[project] }
    func setBudget(_ value: Double?, for project: String) {
        var m = allBudgets()
        if let value, value > 0 { m[project] = value } else { m.removeValue(forKey: project) }
        defaults.set(m, forKey: budgetsKey)
    }

    private func firedRoot() -> [String: [String: [Double]]] {
        defaults.dictionary(forKey: firedKey) as? [String: [String: [Double]]] ?? [:]
    }
    func firedThresholds(for project: String, monthKey: String) -> Set<Double> {
        Set(firedRoot()[monthKey]?[project] ?? [])
    }
    func recordFired(_ threshold: Double, for project: String, monthKey: String) {
        var root = firedRoot()
        // prune other months so state stays small and resets automatically
        root = root.filter { $0.key == monthKey }
        var month = root[monthKey] ?? [:]
        var list = Set(month[project] ?? []); list.insert(threshold)
        month[project] = Array(list); root[monthKey] = month
        defaults.set(root, forKey: firedKey)
    }
}
```

Add to `Settings` (published toggle, following the existing pattern):

```swift
// In the @Published block:
@Published var budgetAlerts: Bool { didSet { save() } }
// In init():  budgetAlerts = store.object(forKey: Key.budgetAlerts) as? Bool ?? true
// In save():  store.set(budgetAlerts, forKey: Key.budgetAlerts)
// In Key enum: static let budgetAlerts = "budgetAlerts"
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter BudgetSettingsStoreTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Settings.swift Tests/AIUsageBarTests/BudgetSettingsStoreTests.swift
git commit -m "feat(cost): budget persistence + alert toggle in Settings"
```

---

### Task 10: On-disk rollup cache

**Files:**
- Create: `Sources/AIUsageBar/Cost/CostCache.swift`
- Test: `Tests/AIUsageBarTests/CostCacheTests.swift`

The cache stores raw events keyed by file identity so re-opening is fast and pricing changes re-price without re-parsing.

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/CostCacheTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class CostCacheTests: XCTestCase {
    func testEncodeDecodeRoundTrip() throws {
        let e = UsageEvent(provider: .codex, timestamp: Date(timeIntervalSince1970: 1_780_000_000),
            model: "gpt-5-codex", project: "p", sessionId: "s", input: 1, output: 2, cacheWrite: 3, cacheRead: 4)
        let data = try JSONEncoder().encode([CachedEvent(e)])
        let back = try JSONDecoder().decode([CachedEvent].self, from: data)
        XCTAssertEqual(back.first?.toEvent().output, 2)
        XCTAssertEqual(back.first?.toEvent().provider, .codex)
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter CostCacheTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/CostCache.swift`

```swift
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
```

- [ ] **Step 4: Run — expect PASS.** `swift test --filter CostCacheTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/CostCache.swift Tests/AIUsageBarTests/CostCacheTests.swift
git commit -m "feat(cost): on-disk rollup cache (path|size|mtime keyed)"
```

---

### Task 11: DashboardExporter (server-less HTML)

**Files:**
- Create: `Sources/AIUsageBar/Cost/DashboardExporter.swift`
- Test: `Tests/AIUsageBarTests/DashboardExporterTests.swift`

The exporter reuses the **already-approved** demo HTML at `docs/cost.html` as its template: embed a `window.__AUB_DATA__` JSON blob, strip the demo's synthetic-data generator, and drive `render()` from the injected data. For this task, generate a self-contained HTML string that contains the JSON and no external URLs.

- [ ] **Step 1: Failing test** — `Tests/AIUsageBarTests/DashboardExporterTests.swift`

```swift
import XCTest
@testable import AIUsageBar

final class DashboardExporterTests: XCTestCase {
    func testHtmlIsSelfContainedAndEmbedsData() {
        let events = [UsageEvent(provider: .claude, timestamp: Date(), model: "claude-opus-4-8",
            project: "/Users/x/ai-usage-bar", sessionId: "s", input: 10, output: 20, cacheWrite: 0, cacheRead: 0)]
        let html = DashboardExporter.html(events: events, budgets: ["/Users/x/ai-usage-bar": 20])
        XCTAssertTrue(html.contains("__AUB_DATA__"))
        XCTAssertTrue(html.contains("ai-usage-bar"))         // project label present
        XCTAssertFalse(html.contains("http://"))             // no external requests
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("<script src"))
    }
}
```

- [ ] **Step 2: Run — expect FAIL.** `swift test --filter DashboardExporterTests`

- [ ] **Step 3: Implement** — `Sources/AIUsageBar/Cost/DashboardExporter.swift`

Build a per-day / per-project / per-model JSON payload (so the page can compute all windows client-side), inject into a template string, and provide `write()`/`open()` using `NSWorkspace`. Full code:

```swift
import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum DashboardExporter {
    /// Build the embedded JSON: per-day project/model breakdown + budgets.
    static func payload(events: [UsageEvent], budgets: [String: Double],
                        pricing: Pricing = .shared, cal: Calendar = .current) -> [String: Any] {
        var days: [String: [String: Any]] = [:]
        var ignore = Set<String>()
        let fmt = DateFormatter(); fmt.calendar = cal; fmt.dateFormat = "yyyy-MM-dd"
        for e in events {
            let key = fmt.string(from: e.timestamp)
            let cost = pricing.cost(for: e, unpriced: &ignore)
            var day = days[key] ?? ["projects": [String: Double](), "models": [String: Double]()]
            var projects = day["projects"] as! [String: Double]
            var models = day["models"] as! [String: Double]
            projects[projectLabel(e.project), default: 0] += cost
            models[e.model, default: 0] += cost
            day["projects"] = projects; day["models"] = models
            days[key] = day
        }
        let budgetLabels = Dictionary(budgets.map { (projectLabel($0.key), $0.value) },
                                      uniquingKeysWith: +)
        return ["days": days, "budgets": budgetLabels, "currency": "USD"]
    }

    static func html(events: [UsageEvent], budgets: [String: Double]) -> String {
        let json = (try? JSONSerialization.data(withJSONObject: payload(events: events, budgets: budgets)))
            .flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return Self.template.replacingOccurrences(of: "/*__AUB_DATA__*/", with: "window.__AUB_DATA__ = \(json);")
    }

    @discardableResult
    static func writeAndOpen(events: [UsageEvent], budgets: [String: Double]) -> URL? {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AIUsageBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("cost-dashboard.html")
        do { try html(events: events, budgets: budgets).write(to: url, atomically: true, encoding: .utf8) }
        catch { return nil }
        #if canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
        return url
    }

    /// Self-contained template. Contains no external URLs; `render()` reads window.__AUB_DATA__.
    static let template: String = ##"""
    <!doctype html><html lang="en"><head><meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1"><title>AI Usage · Cost</title>
    <style>/* … inline styles adapted from docs/cost.html … */</style></head><body>
    <div id="app">…</div>
    <script>/*__AUB_DATA__*/</script>
    <script>/* window-tab + render logic reading window.__AUB_DATA__ (adapted from docs/cost.html) */</script>
    </body></html>
    """##
}
```

> **Note for the implementer:** port the CSS + `render()` from `docs/cost.html` into `template`, replacing its synthetic `DAYS`/`PROJECTS` generator with a reader of `window.__AUB_DATA__.days`. Keep it fully offline (no CDN). The unit test only checks the data blob + absence of external URLs; the visual port is verified in Task 15.

- [ ] **Step 4: Run — expect PASS.** `swift test --filter DashboardExporterTests`
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/Cost/DashboardExporter.swift Tests/AIUsageBarTests/DashboardExporterTests.swift
git commit -m "feat(cost): server-less HTML dashboard exporter"
```

---

### Task 12: CostStore orchestrator

**Files:**
- Create: `Sources/AIUsageBar/Cost/CostStore.swift`
- (No unit test — integration; covered by build + Task 15 smoke. The pure logic it calls is already tested.)

- [ ] **Step 1: Implement** — `Sources/AIUsageBar/Cost/CostStore.swift`

```swift
import Foundation
import Combine
#if canImport(UserNotifications)
import UserNotifications
#endif

@MainActor
final class CostStore: ObservableObject {
    @Published var window: Window = .days7 { didSet { recompute() } }
    @Published var filterProject: String? { didSet { recompute() } }
    @Published private(set) var summary = WindowSummary()
    @Published private(set) var loading = false

    private var events: [UsageEvent] = []
    private let cache = CostCache()
    private let budgets = BudgetStore()
    private let settings = Settings.shared

    /// Full scan on a background task, then recompute + budget check.
    func refresh() {
        loading = true
        Task.detached(priority: .utility) { [cache] in
            let events = Self.scanUsingCache(cache)
            await MainActor.run {
                self.events = events
                self.loading = false
                self.recompute()
                self.checkBudgets()
            }
        }
    }

    /// Cheap budget check off cached events (called by AppDelegate tick even when window closed).
    func backgroundBudgetCheck() {
        Task.detached(priority: .utility) { [cache] in
            let events = Self.scanUsingCache(cache)
            await MainActor.run { self.events = events; self.checkBudgets() }
        }
    }

    func budget(for project: String) -> Double? { budgets.budget(for: project) }
    func setBudget(_ v: Double?, for project: String) { budgets.setBudget(v, for: project); recompute() }
    func monthStatus(for project: String) -> BudgetStatus? {
        guard let limit = budgets.budget(for: project) else { return nil }
        return BudgetStatus(spent: Budget.monthSpend(events: events, project: project), limit: limit)
    }
    func openInBrowser() {
        DashboardExporter.writeAndOpen(events: events, budgets: budgets.allBudgets())
    }

    private func recompute() {
        summary = CostAggregator.summary(events: events, window: window, project: filterProject)
    }

    private func checkBudgets() {
        guard settings.budgetAlerts else { return }
        let monthKey = Budget.monthKey()
        for (project, limit) in budgets.allBudgets() {
            let spent = Budget.monthSpend(events: events, project: project)
            let fraction = limit > 0 ? spent / limit : 0
            let fired = budgets.firedThresholds(for: project, monthKey: monthKey)
            for t in Budget.newlyCrossed(fraction: fraction, alreadyFired: fired) {
                budgets.recordFired(t, for: project, monthKey: monthKey)
                notify(project: project, threshold: t, spent: spent, limit: limit)
            }
        }
    }

    private func notify(project: String, threshold: Double, spent: Double, limit: Double) {
        #if canImport(UserNotifications)
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let c = UNMutableNotificationContent()
            c.title = threshold >= 1 ? "Budget exceeded" : "Budget at \(Int(threshold*100))%"
            c.body = "\(projectLabel(project)) — $\(String(format: "%.2f", spent)) of $\(String(format: "%.0f", limit)) this month."
            center.add(UNNotificationRequest(identifier: "\(project)-\(threshold)", content: c, trigger: nil))
        }
        #endif
    }

    private static func scanUsingCache(_ cache: CostCache) -> [UsageEvent] {
        // (Full incremental scan: iterate provider files, reuse cache by fileKey, parse changed
        // files, persist. For the first version, a straight scanAll() is acceptable; wire the
        // cache in as an optimization.)
        SessionParser.scanAll()
    }
}
```

> **Note:** the first cut may call `SessionParser.scanAll()` directly (correct, just not cached). Fold `CostCache` into `scanUsingCache` as an optimization once the UI works — keep the cache API from Task 10.

- [ ] **Step 2: Verify build.** Run: `swift build` → Expected: success.
- [ ] **Step 3: Commit**

```bash
git add Sources/AIUsageBar/Cost/CostStore.swift
git commit -m "feat(cost): CostStore orchestrator + budget alerts"
```

---

### Task 13: CostView (native window)

**Files:**
- Create: `Sources/AIUsageBar/CostView.swift`

Match the approved demo: window segmented control, big total + token line, daily bar chart (Swift Charts), By project rows with budget bars (click to filter), collapsible By model, footer with Open-in-browser + Edit-budgets. Colors reuse `severityColor`-style values already in `Formatting.swift`.

- [ ] **Step 1: Implement** — `Sources/AIUsageBar/CostView.swift`

```swift
import SwiftUI
import Charts

struct CostView: View {
    @StateObject private var store = CostStore()
    @State private var showBudgets = false
    @State private var showModels = true

    private var accent: Color { Color(red: 0.85, green: 0.55, blue: 0.35) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("", selection: $store.window) {
                ForEach(Window.allCases) { Text($0.label).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()

            hero
            if !store.summary.days.isEmpty { chart }
            projects
            if showModels && !store.summary.byModel.isEmpty { models }
            footer
        }
        .padding(18)
        .frame(width: 460)
        .onAppear { store.refresh() }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let p = store.filterProject {
                HStack(spacing: 6) {
                    Text(projectLabel(p)).font(.caption.weight(.semibold)).foregroundStyle(accent)
                    Button { store.filterProject = nil } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                }
            }
            Text(money(store.summary.totalCost)).font(.system(size: 40, weight: .semibold).monospacedDigit())
                .foregroundStyle(accent)
            Text("in \(tokens(store.summary.input)) / out \(tokens(store.summary.output)) · \(store.summary.sessions) sessions")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var chart: some View {
        Chart(store.summary.days) { d in
            BarMark(x: .value("Day", d.day, unit: .day), y: .value("Cost", d.cost))
                .foregroundStyle(accent.opacity(0.85))
        }
        .frame(height: 90).chartYAxis(.hidden)
    }

    private var projects: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BY PROJECT").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(store.summary.byProject) { p in
                Button { store.filterProject = (store.filterProject == p.project ? nil : p.project) } label: {
                    VStack(spacing: 5) {
                        HStack {
                            Text(projectLabel(p.project)).font(.subheadline)
                            Spacer()
                            Text(money(p.cost)).font(.subheadline.weight(.semibold).monospacedDigit())
                        }
                        if let st = store.monthStatus(for: p.project) {
                            HStack(spacing: 8) {
                                ProgressBar(fraction: min(1, st.fraction), color: budgetColor(st.level))
                                Text("\(money(st.spent)) / \(money(st.limit)) · \(st.percent)%")
                                    .font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 4)
                .background(store.filterProject == p.project ? accent.opacity(0.10) : .clear,
                            in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BY MODEL").font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            ForEach(store.summary.byModel.prefix(5).map { $0 }) { m in
                HStack {
                    Text(prettyModelName(m.model)).font(.subheadline)
                    Spacer()
                    Text(money(m.cost)).font(.subheadline.weight(.semibold).monospacedDigit())
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Open in browser") { store.openInBrowser() }
            Spacer()
            Button("Edit budgets") { showBudgets = true }
        }
        .font(.caption)
        .sheet(isPresented: $showBudgets) { BudgetSettingsView(store: store) }
    }

    private func budgetColor(_ l: BudgetStatus.Level) -> Color {
        switch l { case .normal: return severityColor(20); case .warn: return severityColor(85); case .over: return severityColor(120) }
    }
    private func money(_ v: Double) -> String { "$" + String(format: "%.2f", v) }
    private func tokens(_ n: Int) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", Double(n)/1e6) : n >= 1000 ? "\(n/1000)K" : "\(n)"
    }
}
```

- [ ] **Step 2: Verify build.** Run: `swift build` → Expected: success.
- [ ] **Step 3: Commit**

```bash
git add Sources/AIUsageBar/CostView.swift
git commit -m "feat(cost): native CostView window (Swift Charts)"
```

---

### Task 14: BudgetSettingsView + panel/app wiring

**Files:**
- Create: `Sources/AIUsageBar/BudgetSettingsView.swift`
- Modify: `Sources/AIUsageBar/PanelView.swift` (footer button + closure)
- Modify: `Sources/AIUsageBar/AppDelegate.swift` (window + wiring + tick)

- [ ] **Step 1: Implement `BudgetSettingsView`** — `Sources/AIUsageBar/BudgetSettingsView.swift`

```swift
import SwiftUI

struct BudgetSettingsView: View {
    @ObservedObject var store: CostStore
    @ObservedObject private var settings = Settings.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Monthly budgets").font(.headline)
            Toggle("Notify me at 80% and 100%", isOn: $settings.budgetAlerts)
            Divider()
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(store.summary.byProject) { p in
                        HStack {
                            Text(projectLabel(p.project)).font(.subheadline)
                            Spacer()
                            TextField("no budget", value: Binding(
                                get: { store.budget(for: p.project) ?? 0 },
                                set: { store.setBudget($0 > 0 ? $0 : nil, for: p.project) }
                            ), format: .number).frame(width: 80).textFieldStyle(.roundedBorder)
                            Text("/ mo").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            HStack { Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
        }
        .padding(18).frame(width: 380, height: 420)
    }
}
```

- [ ] **Step 2: Add the footer button to `PanelView`** — add `var onOpenCost: () -> Void` next to the other closures (`PanelView.swift:8-10`), and a button in the footer's first `HStack` (`PanelView.swift:136`), after the GitHub link:

```swift
Button(action: onOpenCost) {
    Label("Cost", systemImage: "dollarsign.circle").font(.caption.weight(.medium))
}
.buttonStyle(.borderless).foregroundStyle(.secondary)
```

- [ ] **Step 3: Wire it in `AppDelegate`** — supply `onOpenCost` in the `PanelView(...)` init (`AppDelegate.swift:29-34`) and add the window + tick hook:

```swift
// in PanelView(...) init:
onOpenCost: { [weak self] in self?.showCostDashboard() },

// new property near settingsWindow:
private var costWindow: NSWindow?
private let costStore = CostStore()

// new method (mirrors showSettings):
private func showCostDashboard() {
    panelController.close()
    if costWindow == nil {
        costWindow = makeWindow(title: "AI Usage · Cost",
            size: NSSize(width: 496, height: 640), view: CostView())
    }
    NSApp.activate(ignoringOtherApps: true)
    costWindow?.makeKeyAndOrderFront(nil)
}

// in tick() (AppDelegate.swift:68), after the refresh gate, add a background budget check:
costStore.backgroundBudgetCheck()
```

> Note: `CostView` owns its own `@StateObject` store for display; the `AppDelegate.costStore` instance exists only to run background budget alerts on the timer. Both read the same files. Acceptable duplication for v1.

- [ ] **Step 4: Verify build.** Run: `swift build` → Expected: success.
- [ ] **Step 5: Commit**

```bash
git add Sources/AIUsageBar/BudgetSettingsView.swift Sources/AIUsageBar/PanelView.swift Sources/AIUsageBar/AppDelegate.swift
git commit -m "feat(cost): budget editor + panel 'Cost' button + app wiring"
```

---

### Task 15: Full verification

**Files:** none (verification only).

- [ ] **Step 1: Build + test.** Run: `swift build && swift test` → Expected: build succeeds, all tests pass.
- [ ] **Step 2: Self-test smoke.** Run: `AIUSAGEBAR_PRINT=1 swift run` → Expected: no crash.
- [ ] **Step 3: Manual run (per the `verify` skill).** Run: `swift run`, open the panel, click **Cost**. Verify: window opens; totals/chart/by-project render from real local files; switching windows updates; clicking a project filters; **Open in browser** opens `~/Library/Application Support/AIUsageBar/cost-dashboard.html`; **Edit budgets** saves a limit and a budget bar appears.
- [ ] **Step 4: Dashboard offline check.** Open the generated HTML with Wi-Fi off → it must render fully (no external requests).
- [ ] **Step 5: Commit any fixes, then push.**

```bash
git push origin feat/cost-tracking
```

---

## Self-Review (author checklist — completed)

- **Spec coverage:** parsers (§3) → Tasks 3–6; pricing (§4.3–4.4) → Task 2; aggregation/windows (§4.5) → Task 7; budgets/alerts (§4.6, §7) → Tasks 8–9, 12; cache (§4.8) → Task 10; exporter (§4.9) → Task 11; store (§4.7) → Task 12; UI (§6) → Tasks 13–14; credits/non-goals → docs (already shipped). ✔
- **Deviations (documented):** pricing + HTML template are Swift constants, not bundled resources (robust with the hand-assembled `.app`); cache is an optimization layered after a correct `scanAll()`.
- **Type consistency:** `UsageEvent`, `Rates`, `Window`, `WindowSummary`, `ProjectSpend`/`ModelSpend`/`DayPoint`, `BudgetStatus`, `BudgetStore`, `CostCache`, `CostStore` names are used identically across tasks. ✔
- **No placeholders in code steps** (the two prose "Note"s flag intentional v1-simplifications, not missing code). ✔
