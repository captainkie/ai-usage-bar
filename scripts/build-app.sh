#!/usr/bin/env bash
# Build AIUsageBar.app - a menu-bar-only (LSUIElement) macOS app bundle.
#
#   ./scripts/build-app.sh            build ./AIUsageBar.app (ad-hoc signed)
#   ./scripts/build-app.sh install    also copy it to /Applications
#
# Ad-hoc signing ("-") is enough for personal use: macOS remembers your
# "Always Allow" Keychain choice as long as the binary does not change. For a
# signature that survives rebuilds, set SIGN_IDENTITY to a self-signed or
# Developer ID certificate name.
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="release"
APP="AIUsageBar.app"
BUNDLE_ID="co.th.aiusagebar.selfhost"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # default: ad-hoc

echo "==> Building ($CONFIG)"
swift build -c "$CONFIG"
BIN=".build/${CONFIG}/AIUsageBar"

echo "==> Assembling ${APP}"
rm -rf "$APP"
mkdir -p "${APP}/Contents/MacOS" "${APP}/Contents/Resources"
cp "$BIN" "${APP}/Contents/MacOS/AIUsageBar"
cp Resources/Info.plist "${APP}/Contents/Info.plist"

echo "==> Signing (${SIGN_IDENTITY})"
codesign --force --options runtime --identifier "$BUNDLE_ID" \
         --sign "$SIGN_IDENTITY" "$APP"

echo "==> Built ${APP}"

if [[ "${1:-}" == "install" ]]; then
    echo "==> Installing to /Applications"
    rm -rf "/Applications/${APP}"
    cp -R "$APP" "/Applications/${APP}"
    echo "==> Installed. Open with: open -a AIUsageBar"
fi
