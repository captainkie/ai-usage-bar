#!/usr/bin/env bash
# AI Usage Bar — one-line installer.
#   curl -fsSL https://raw.githubusercontent.com/captainkie/ai-usage-bar/main/install.sh | bash
#
# Downloads the latest release, installs to /Applications, clears the download
# quarantine (the build is self-signed, not notarized), and launches it.
set -euo pipefail

REPO="captainkie/ai-usage-bar"
APP="AIUsageBar.app"
DEST="/Applications/$APP"
URL="https://github.com/$REPO/releases/latest/download/AIUsageBar.zip"

if [[ "$(uname)" != "Darwin" ]]; then
    echo "AI Usage Bar is macOS-only." >&2
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading AI Usage Bar…"
curl -fL "$URL" -o "$TMP/AIUsageBar.zip"

echo "==> Installing to /Applications…"
[[ -d "$DEST" ]] && rm -rf "$DEST"
ditto -x -k "$TMP/AIUsageBar.zip" /Applications
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Launching…"
open "$DEST"

cat <<'DONE'

Installed. On first launch, macOS asks to allow Keychain access to
"Claude Code-credentials" — click Always Allow.

Then look for the "5h .. 7d .." item in your menu bar (and the Touch Bar,
if your Mac has one).
DONE
