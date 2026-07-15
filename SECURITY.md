# Security Policy

AI Usage Bar is a local, open-source macOS menu-bar app. This document states
exactly what it does with your data, its threat model, and how to report a
vulnerability. Every claim here is verifiable in the source.

## TL;DR

- Reads your **existing** Claude Code login token from the macOS Keychain —
  **read-only**, and only after you approve the standard macOS prompt.
- Sends it **only** as an `Authorization: Bearer` header to **one** endpoint:
  `https://api.anthropic.com/api/oauth/usage` (the same one Claude Code's
  `/status` uses).
- **No** other network connections. **No** telemetry, analytics, accounts, or
  third-party SDKs.
- The token is **never** written to disk, logged, or sent anywhere else.
- 100% open source — verify every claim below yourself.

## What the app accesses

### Keychain (read-only)
- Exactly one item: generic-password service `Claude Code-credentials`.
- Uses `SecItemCopyMatching` with `kSecReturnData` (a read). It never adds,
  updates, or deletes Keychain items, and never reads any other item.
- macOS gates this. The first time, you see the standard
  *"AIUsageBar wants to use … Claude Code-credentials"* dialog. Nothing is read
  unless you click **Allow**.

### Network
- One host only: `api.anthropic.com`. One request: `GET /api/oauth/usage`.
- The Buy-me-a-coffee / GitHub links open in your browser **only when you
  click them** — the app makes no automatic request to them.

### Filesystem (read-only)
- To show the model you're actually using, the app reads the **tail** of your
  most recently modified Claude Code transcript under `~/.claude/projects/`
  (looking only at the `message.model` field). This is a local read; nothing
  from your transcripts is transmitted, stored, or logged.
- No files are written. App settings (when enabled) use macOS `UserDefaults`
  and never contain your token.

## What the app never does

- No keylogging, screen capture, clipboard, camera, or microphone access.
- No reading of other apps' data or any other Keychain item.
- No background data collection or exfiltration.
- No auto-updater that downloads and executes code.
- No privilege escalation, no `sudo`, no shell/process spawning.

## Credential handling

- The access token exists only **in memory** for the duration of a request.
- It is sent **solely** to Anthropic over HTTPS (TLS) as a Bearer header.
- It is never persisted, cached to disk, or logged.
- The app reads the current token from the Keychain on each refresh, relying on
  Claude Code to keep it fresh — it does not manage or refresh tokens itself.

## Access model (legitimacy)

The app accesses **only your own account data**, using **your own credentials
that already exist on your device**, through Anthropic's own endpoint. It does
**not** bypass, crack, or circumvent any authentication or access control. It is
functionally equivalent to running Claude Code's own `/status`.

## Honest caveats

- **Unofficial endpoint.** `/api/oauth/usage` is undocumented and used
  internally by Claude Code. It may change or break at any time. The app polls
  at a modest default interval (60s). See [DISCLAIMER.md](DISCLAIMER.md).
- **Private Apple API (Touch Bar).** The optional Touch Bar item uses the
  private `DFRFoundation` framework — read-only display, not App Store eligible,
  and can be disabled.
- **Code signing.** Personal builds are ad-hoc or self-signed and not notarized.

## Verify it yourself

1. **Read the source** — the app is ~700 lines. Only three files touch secrets,
   the network, or your files:
   - `Sources/AIUsageBar/Keychain.swift` — the Keychain read
   - `Sources/AIUsageBar/UsageService.swift` — the single API call
   - `Sources/AIUsageBar/CurrentModel.swift` — the read-only transcript peek
2. **Watch the network** with Little Snitch / LuLu / `nettop -m route` — you'll
   see only `api.anthropic.com`.
3. **Build from source:** `swift build -c release`.

## Reporting a vulnerability

Please report privately via GitHub **Security → Report a vulnerability**
(private advisory) on the repository, rather than opening a public issue. We aim
to acknowledge within 7 days.
