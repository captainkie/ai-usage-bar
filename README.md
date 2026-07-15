<div align="center">

# ☕ AI Usage Bar

**Your Claude Code usage limits, live in the macOS menu bar.**

A tiny, private, open-source menu-bar app that shows your rolling **5-hour**
and **weekly** Claude Code limits at a glance — with the current model and a
live reset countdown. Self-hosted: build it yourself, nothing downloaded from
anyone else.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
![Platform](https://img.shields.io/badge/macOS-13%2B-black?logo=apple)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)

<a href="https://buymeacoffee.com/captainkiez">
  <img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-captainkiez-FFDD00?logo=buymeacoffee&logoColor=black" alt="Buy me a coffee">
</a>

</div>

---

## What it does

- **`● 5h 12%  7d 45%`** right in your menu bar — updated automatically.
- Click for a panel with progress bars, the model you're on (e.g. *Opus 4.8*),
  and live **"resets in 1h 14m"** countdowns.
- **Touch Bar** — a persistent item in the Control Strip on Macs that have one.
- **Launch at login** toggle.
- **Private by design** — the only network call is to `api.anthropic.com`.
  Your token never leaves your Mac.

## How it works

1. Reads Claude Code's OAuth token from your login **Keychain**
   (`Claude Code-credentials`, read-only).
2. Calls **`GET https://api.anthropic.com/api/oauth/usage`** — the exact
   endpoint Claude Code's `/status` uses.
3. Renders `five_hour` / `seven_day` utilization + reset times.

No analytics, no accounts, no telemetry.

## Build & run

Requires macOS 13+, Xcode command-line tools, and a Claude Code login.

```bash
# Quick dev run (menu-bar item appears; no Dock icon)
swift run

# Build a proper .app and install it
./scripts/build-app.sh install
open -a AIUsageBar
```

On first launch macOS asks to allow Keychain access to
`Claude Code-credentials` — click **Always Allow**.

## Roadmap

- [x] Claude Code — 5-hour + weekly limits, model, reset countdowns
- [x] Menu-bar app, `.app` bundle, launch at login
- [x] Touch Bar Control Strip item *(uses private `DFRFoundation` — not App Store safe)*
- [ ] Codex, Gemini, OpenCode providers *(needs those CLIs installed to wire up)*
- [ ] Floating bar view
- [ ] Automatic OAuth token refresh
- [ ] Notarized release download

## Project layout

```
Sources/AIUsageBar/
  main.swift          entry point (+ AIUSAGEBAR_PRINT=1 self-test)
  AppDelegate.swift   NSStatusItem, popover, 60s refresh timer
  PanelView.swift     the SwiftUI panel
  Keychain.swift      reads Claude Code-credentials (read-only)
  UsageService.swift  GET /api/oauth/usage
  UsageModels.swift   response model
  UsageViewModel.swift state + derived values
  LoginItem.swift     launch-at-login (SMAppService)
  TouchBarController.swift  Control Strip item (DFRFoundation bridge)
  Formatting.swift    date parsing, countdowns, severity colors
scripts/build-app.sh  assemble + ad-hoc sign AIUsageBar.app
```

## Support

If this saves you a few `/status` checks, you can
[buy me a coffee ☕](https://buymeacoffee.com/captainkiez) — thank you!

## License

[MIT](LICENSE) © captainkie

> Not affiliated with Anthropic. "Claude" is a trademark of Anthropic.
