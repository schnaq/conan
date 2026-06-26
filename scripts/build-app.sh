#!/usr/bin/env bash
set -euo pipefail

# Build Conan.app from the SwiftPM executable, then code-sign it.
#
#   ./scripts/build-app.sh                 # ad-hoc signed, release build
#   SIGN_IDENTITY="Apple Development: …" ./scripts/build-app.sh
#   CONFIG=debug ./scripts/build-app.sh

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"   # "-" = ad-hoc (fine for personal local use)
APP="$ROOT/Conan.app"

cd "$ROOT"

echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)/Conan"
[ -x "$BIN" ] || { echo "error: built binary not found at $BIN" >&2; exit 1; }

echo "==> assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Conan"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
if [ -f "$ROOT/Resources/AppIcon.icns" ]; then
    cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
else
    echo "    (no Resources/AppIcon.icns — run ./scripts/make-icon.sh to generate one)"
fi

echo "==> codesign (identity: $SIGN_IDENTITY)"
codesign --force --sign "$SIGN_IDENTITY" "$APP"

echo "==> done: $APP"
echo "    open \"$APP\"        # launch (menu-bar only, no dock icon)"
echo "    or copy Conan.app to /Applications"
