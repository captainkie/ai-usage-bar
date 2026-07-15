# Privacy Policy

**AI Usage Bar does not collect, store, or transmit any personal data.**

- **No data collection.** No analytics, no telemetry, no crash reporting, no
  accounts, and no servers operated by this project.
- **Local only.** Everything runs on your Mac.
- **What leaves your device:** exactly one request from your Mac directly to
  Anthropic (`https://api.anthropic.com/api/oauth/usage`), carrying your
  existing Claude Code token, to fetch **your own** usage numbers. The
  developers of AI Usage Bar never see this request or its contents.
- **Your token** is read from the macOS Keychain (only after you approve the
  system prompt), held in memory only, and never written to disk or sent
  anywhere except Anthropic over HTTPS.
- **No third parties.** No SDKs, ad networks, or trackers are bundled.

Because there is no data collection, there is nothing to opt out of, export, or
delete beyond uninstalling the app and revoking its Keychain access in
**Keychain Access → Claude Code-credentials → Access Control**.

_Last updated: 2026-07-15._
