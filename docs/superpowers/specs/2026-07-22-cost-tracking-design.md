# Cost Tracking — Design Spec

**Date:** 2026-07-22
**App:** AI Usage Bar (macOS menu-bar app, SwiftPM executable)
**Status:** Approved for planning

## 1. Goal

Add local-first **cost tracking** to AI Usage Bar, inspired by CodeBurn and onWatch, without
bloating the existing minimal UI. Today the app shows only *percentage-of-limit* gauges (from
remote usage APIs). This feature adds a separate **Cost** surface that:

- Computes USD spend from local session files for **Claude Code, Codex, and Gemini**.
- Rolls spend up over **Today / 7 days / 30 days / Month / All**.
- Breaks spend down **by project** (derived from the working directory in the session files).
- Lets the user set a **monthly budget per project** and **alerts** when spend crosses a threshold.
- Opens a **native cost window** from the menu-bar panel, plus an **"Open in browser"** static
  web dashboard.

The existing percentage panel, floating bar, and Touch Bar are **not changed**.

## 2. Key design decisions

1. **No HTTP server for the "web dashboard."** Instead of CodeBurn's loopback React server, we
   render a **self-contained static HTML file** (data embedded as JSON, charts drawn with inline
   SVG, no CDN, no network) and open it in the default browser. Keeps the app local-first with no
   port or CSRF surface. "Open in browser" regenerates the file with fresh data and opens it.
2. **Cost is sourced from local files, priced in-app.** Session files carry token counts but no
   cost. We bundle a curated `pricing.json` (per-model, per-token USD) and multiply — same approach
   as CodeBurn's litellm snapshot, trimmed to the models these three tools emit. No live price fetch
   in the MVP (bundled snapshot, updated via app releases).
3. **Project = working directory.** No project config. Derived from the `cwd`/path encoded in each
   session file, exactly like CodeBurn.
4. **Budgets are monthly, per project, in USD.** Evaluated against **current-calendar-month** spend
   regardless of the view window.
5. **The existing % panel stays untouched.** The only UI addition to the panel is one small "Cost"
   button in the footer.

## 3. Data sources (local files)

All parsers skip missing directories silently and skip malformed lines without failing the scan.

### 3.1 Claude Code
- Paths: `~/.claude/projects/**/*.jsonl` (honor `CLAUDE_CONFIG_DIR` if set).
- Each line is one JSON object. Assistant lines (`type == "assistant"`) carry:
  - `message.model` — e.g. `claude-opus-4-8`
  - `message.usage.{ input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens }`
  - top-level `cwd`, `gitBranch`, `sessionId`, `timestamp` (ISO 8601)
- Mapping → `UsageEvent`: input=`input_tokens`, output=`output_tokens`,
  cacheWrite=`cache_creation_input_tokens`, cacheRead=`cache_read_input_tokens`.
- Project: the `projects/<slug>` directory name (sanitized cwd). Fall back to `cwd` if present.
- The app already opens these files today (`CurrentModel.swift`), so paths/permissions are known-good.

### 3.2 Codex
- Paths: `~/.codex/sessions/<YYYY>/<MM>/<DD>/rollout-*.jsonl` and `~/.codex/archived_sessions/rollout-*.jsonl`
  (honor `CODEX_HOME`).
- Lines are `{ type, timestamp, payload }`:
  - `type == "session_meta"` → `payload.cwd`, `payload.model`, `payload.session_id`,
    `payload.originator` (must start with `"codex"`).
  - `type == "event_msg"` with `payload.type == "token_count"` → tokens at
    `payload.info.last_token_usage.{ input_tokens, cached_input_tokens, output_tokens, reasoning_output_tokens, total_tokens }`.
- OpenAI semantics: `input_tokens` **includes** cached. Map:
  input=`input_tokens - cached_input_tokens`, cacheRead=`cached_input_tokens`,
  output=`output_tokens + reasoning_output_tokens`, cacheWrite=0.
- Project: `sanitize(payload.cwd)` (strip leading `/`, `/`→`-`).

### 3.3 Gemini
- Paths: `~/.gemini/tmp/<projectHash>/chats/session-*.json` or `*.jsonl`.
- Message objects: `{ id, timestamp, type: "user"|"gemini"|"info", content, model, tokens, toolCalls[] }`
  with `tokens = { input, output, cached, thoughts, tool, total }`.
- Semantics: `input` **includes** cached. Map: input=`input - cached`, cacheRead=`cached`,
  output=`output + thoughts` (fold reasoning into output), cacheWrite=0. `tool` tokens are minor and
  folded into output.
- Project: the `<projectHash>` directory name. **Limitation:** Gemini stores a hash, not a readable
  path, so its project label is opaque (shown as `gemini:<hash-prefix>`). Documented as a known limit.

## 4. Components

New code lives under `Sources/AIUsageBar/Cost/`. Each unit has one job and is testable in isolation.

### 4.1 `UsageEvent.swift`
```swift
struct UsageEvent {
    let provider: Provider          // reuse existing enum: .claude/.codex/.gemini
    let timestamp: Date
    let model: String
    let project: String
    let sessionId: String
    let input: Int
    let output: Int
    let cacheWrite: Int
    let cacheRead: Int
}
```

### 4.2 `SessionParser.swift`
- `func scan() -> [UsageEvent]` orchestrating three private sub-parsers
  (`parseClaude`, `parseCodex`, `parseGemini`), each reading its provider's files line-by-line
  (streaming, not whole-file-into-memory) and emitting `UsageEvent`s.
- Returns events for all installed providers; missing providers contribute nothing.

### 4.3 `Pricing.swift`
- Loads bundled `Resources/pricing.json`: `{ "<model-id>": [inPerTok, outPerTok, cacheWritePerTok, cacheReadPerTok] }`
  (USD **per single token**; `null` cacheWrite ⇒ `in × 1.25`, `null` cacheRead ⇒ `in × 0.1`).
- `func cost(for event: UsageEvent) -> Double` =
  `input×inRate + output×outRate + cacheWrite×cwRate + cacheRead×crRate`.
- Model-name resolution (small, in this order): exact → strip provider prefix → tiny built-in alias
  map (only the handful of variant spellings these three tools emit) → longest-prefix → case-insensitive.
- Unknown model ⇒ cost contribution `0` but tokens still counted; aggregator tracks an `unpricedModels`
  set so the UI can show a subtle "some models unpriced" hint.

### 4.4 `Resources/pricing.json`
- Curated snapshot covering current Claude (Opus/Sonnet/Haiku families), Codex/GPT models, and Gemini
  models. Small and hand-maintainable. Schema documented in a header comment / README note.

### 4.5 `CostAggregator.swift`
- Pure functions over `[UsageEvent]` + `Pricing`:
  - `dailyRollups(events) -> [DayRollup]` where `DayRollup { date, byProject: [String: Bucket], byModel: [String: Bucket] }`
    and `Bucket { cost, input, output, cacheWrite, cacheRead, calls, sessions:Set<String> }`.
  - `func totals(in window: Window) -> WindowSummary` (total cost, tokens, calls, sessions, per-project,
    per-model), filtering day rollups by local-time boundaries.
- `enum Window { today, days7, days30, month, all }` with local-time start/end computation
  (day-granular). `all` = everything on disk (bounded by the cache, no artificial cap).

### 4.6 `Budget.swift`
- `struct ProjectBudget { project: String; monthlyLimitUSD: Double }` — persisted in `Settings`
  (UserDefaults) as JSON `[project: Double]`.
- `struct BudgetStatus { spentThisMonth: Double; limit: Double?; fraction: Double?; level: .normal/.warn/.over }`.
  Thresholds: warn ≥ 0.8, over ≥ 1.0.
- Alert firing is a pure function: given month spend, limit, and previously-fired thresholds for the
  current month key, return which new notifications to fire. State persisted as
  `[project: { monthKey, firedThresholds:[Double] }]`; reset when `monthKey` changes.

### 4.7 `CostStore.swift` (`@ObservableObject`, `@MainActor`)
- Owns the current `WindowSummary`, selected `Window`, budgets, and `unpricedModels`.
- `refresh()`: on a background task, load the on-disk cache, scan changed/today files, merge, compute
  aggregates for the selected window; publish to the UI.
- **Cheap budget check runs on the app's existing periodic tick even when the cost window is closed**
  (uses cached rollups) so notifications fire in the background. Full view aggregation only runs while
  the cost window is visible.

### 4.8 On-disk cache
- `~/Library/Application Support/AIUsageBar/cost-cache.json`.
- Map `fileKey (path+size+mtime)` → per-file rollup `[{ date, project, model, input, output, cacheWrite, cacheRead, calls, sessionIds }]`.
- Unchanged files reuse cached rollups; changed/new files (and always today's files) are re-parsed.
- **Cost is computed from cached token counts at aggregation time**, so updating `pricing.json` is
  reflected without re-parsing.
- Trade-off vs CodeBurn: we key on live files, so **deleted session files drop out of history**
  (reflects current disk state). Accepted for simplicity; documented.

### 4.9 `DashboardExporter.swift`
- Fills a bundled `dashboard-template.html` (or in-code template string) placeholder with JSON:
  ```
  { generatedAt, currency:"USD",
    days:[{ date, projects:{name:{cost,input,output,cacheWrite,cacheRead,calls,sessions}}, models:{...} }],
    budgets:{project:limit}, monthSpend:{project:cost}, unpricedModels:[...] }
  ```
- The page is **self-contained** (inline CSS/JS, inline SVG charts, no external requests). JS computes
  all windows client-side from `days[]`. Written to
  `~/Library/Application Support/AIUsageBar/cost-dashboard.html` and opened via `NSWorkspace.shared.open`.

## 5. Data flow

```
local files (~/.claude, ~/.codex, ~/.gemini)
  → SessionParser.scan()  →  [UsageEvent]
  → (cached per-file rollups)  →  merged day rollups
  → CostAggregator + Pricing  →  WindowSummary / per-project / per-model
  → CostView (native, Swift Charts)   and   DashboardExporter (static HTML → browser)
Budgets: Settings(UserDefaults) → Budget.status(monthSpend, limit) → progress bars + notifications
```

## 6. UI

### 6.1 Menu-bar panel hook (only change to existing UI)
- Add one small **"Cost"** button (SF Symbol, e.g. `chart.bar` / `dollarsign.circle`) to
  `PanelView`'s footer, mirroring the existing `onOpenSettings` closure pattern
  (`PanelView` closures ← supplied by `AppDelegate`).
- `AppDelegate.showCostDashboard()` opens a new `NSWindow` hosting `CostView` via the existing
  `makeWindow(title:size:view:)` helper (same as `showSettings()`).

### 6.2 `CostView.swift` (native window)
```
┌─ AI Usage · Cost ─────────────────────────────┐
│ [Today] [7d] [30d] [Month] [All]              │
│   $42.18   ·  in 1.2M / out 340K · 12 sess     │
│   ▁▂▅▇▃▂▁   cost per day (Swift Charts bars)   │
│                                                │
│ By project                    cost   budget    │
│ ai-usage-bar     $18.20  ▇▇▇▇▇▇▇▇▁ 91% ⚠️      │  ← row click filters the whole view
│ siam-kubota      $12.05  ▇▇▁▁▁▁▁▁▁ 24%         │
│ ai-dpr-autoflow   $8.11  (no budget)  ＋set    │
│                                                │
│ ▸ By model (top 3, collapsible)                │
│ [Open in browser]  [Edit budgets]   Inspired ↗ │
└────────────────────────────────────────────────┘
```
- Segmented window control; big total + compact token/session line; daily bar chart (Swift Charts).
- **By project** rows: cost + (if budget set) a thin progress bar + %, colored normal/warn/over.
  Row click filters the entire view to that project; `＋set` opens the budget editor for that project.
- Collapsible **By model** (top 3) to stay minimal.
- Footer: **Open in browser**, **Edit budgets** (no inspiration credit here — README only).
- If `unpricedModels` non-empty, a subtle one-line hint.

### 6.3 `BudgetSettingsView.swift`
- Table of projects discovered from the last scan (sorted by month spend), each with a USD `TextField`
  for the monthly limit (blank = no budget).
- A global toggle **"Notify me at 80% and 100%"** (requests notification authorization on enable).
- Persists to `Settings`/UserDefaults. Reachable from the cost window footer (and optionally the
  existing Settings window).

### 6.4 Static web dashboard (opened in browser)
- Light theme echoing CodeBurn's web look, but trimmed: window tabs, big cost number, a few stat cards
  (cost, tokens, calls, sessions), a daily SVG bar chart, a **By Project** table with budget bars, and a
  **By Model** table. A "Local only" note in the footer (no inspiration credit — README only).
  Fully offline/self-contained.

## 7. Budgets & alerts

- Monthly limit per project (USD), stored in UserDefaults.
- Status vs current-calendar-month spend. Progress bar colors: `<80%` accent, `80–99%` amber, `≥100%` red.
- Optional macOS notifications via `UNUserNotificationCenter` at **80%** and **100%**, fired at most
  once per threshold per project per calendar month; state persisted and reset on month change.
- Background budget check piggybacks on the app's existing periodic refresh timer (cheap, cache-based),
  so alerts work even when the cost window is closed.

## 8. Error handling & performance

- Missing provider dir ⇒ skip. Malformed line/file ⇒ skip, continue.
- Unknown model ⇒ tokens counted, cost 0, tracked in `unpricedModels`.
- Line-by-line streaming reads to bound memory on large transcripts.
- Per-file rollup cache keeps re-opening fast; only today's/changed files re-parse.
- All parsing/aggregation off the main thread; UI updates on `@MainActor`.

## 9. Credits (required)

- **README only**: a "Credits / Inspiration" section — CodeBurn
  (`https://github.com/getagentseal/codeburn`, local-first AI cost tracker) and onWatch
  (`https://github.com/onllm-dev/onwatch`, open-source AI API quota tracker). The app **does not
  connect to, bundle, or call** either project — it independently reads the same local session files
  and prices them with its own bundled table. **No inspiration credit in the app UI or web dashboard**
  (per user request) — keep those surfaces clean.

## 10. Testing

- **Pricing**: known model + token counts → expected USD; alias/prefix resolution; unknown-model path.
- **Parsers**: small fixture files (one per provider) → expected `UsageEvent`s, incl. cached-input
  subtraction for Codex/Gemini.
- **Aggregator**: window boundary filtering (today vs 7d vs month vs all) and per-project/per-model grouping.
- **Budget**: threshold levels and the pure alert-firing function (fire once per threshold per month; reset on month change).
- Add an `AIUsageBarTests` target to `Package.swift` if not already present; ship fixtures under `Tests/`.

## 11. Non-goals (kept out to stay minimal)

By Activity / Skills / Agents / MCP breakdowns, device sync & sharing, context tree, 15-minute bucket
chart, live pricing fetch, and any local HTTP server. These are ~90% of CodeBurn's surface and are
intentionally excluded.

## 12. New / changed files (summary)

- New: `Sources/AIUsageBar/Cost/{UsageEvent,SessionParser,Pricing,CostAggregator,Budget,CostStore,DashboardExporter}.swift`,
  `Sources/AIUsageBar/CostView.swift`, `Sources/AIUsageBar/BudgetSettingsView.swift`,
  `Resources/pricing.json`, `Resources/dashboard-template.html`, `Tests/**` fixtures.
- Changed: `PanelView.swift` (footer "Cost" button + `onOpenCost` closure), `AppDelegate.swift`
  (`showCostDashboard()`, wire closure, background budget check on the existing tick),
  `Settings.swift` (budgets + alert toggle + fired-threshold state), `Package.swift` (resources +
  test target), `README.md` (credits).
