#!/bin/bash
# Assemble the runnable BetterScreenshot.app bundle from the SwiftPM executable.
# Replaces the plans' `xcodegen generate && xcodebuild ...` step (full Xcode is
# unavailable in this environment; only Command Line Tools are installed).
#
# Usage: scripts/build-app.sh [debug|release]   (default: debug)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP_NAME="BetterScreenshot"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/$APP_NAME"
if [ ! -x "$BIN" ]; then
    echo "error: built executable not found at $BIN" >&2
    exit 1
fi

DIST="dist"
APP="$DIST/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp App/Info.plist "$APP/Contents/Info.plist"

if [ -f "Resources/AppIcon.icns" ]; then
    cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
fi

# Ad-hoc sign (non-sandboxed). Entitlements file has no sandbox key.
codesign --force --sign - --entitlements App/BetterScreenshot.entitlements "$APP" >/dev/null 2>&1 \
    || codesign --force --sign - "$APP" >/dev/null 2>&1

echo "==> Built $APP"
