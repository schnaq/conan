#!/usr/bin/env bash
set -euo pipefail

# Build a universal, Developer-ID-signed, notarized, stapled Conan.dmg for
# distribution to other Macs (opens with no Gatekeeper warnings).
#
# One-time setup (see README "Distribution"):
#   1. Create a "Developer ID Application" certificate in your paid team.
#   2. Store notary credentials in a keychain profile:
#        xcrun notarytool store-credentials "conan-notary" \
#          --apple-id <you@example.com> --team-id <TEAMID> --password <app-specific-pw>
#
# Usage:
#   DEV_ID="Developer ID Application: Your Name (TEAMID)" ./scripts/release.sh
#   NOTARY_PROFILE=conan-notary  (default)
#   SKIP_NOTARIZE=1              (optional: sign + DMG only, for a local dry run)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NOTARY_PROFILE="${NOTARY_PROFILE:-conan-notary}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"
DIST="$ROOT/dist"

: "${DEV_ID:?Set DEV_ID to your 'Developer ID Application: NAME (TEAMID)' identity (see: security find-identity -v -p codesigning)}"

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
APP="$STAGING/Conan.app"
mkdir -p "$DIST"

# 1. Universal build (arm64 + x86_64).
echo "==> swift build -c release --arch arm64 --arch x86_64"
swift build -c release --arch arm64 --arch x86_64
BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/Conan"
[ -x "$BIN" ] || { echo "error: built binary not found at $BIN" >&2; exit 1; }
ARCHS="$(lipo -archs "$BIN")"
case "$ARCHS" in
    *arm64*x86_64* | *x86_64*arm64*) : ;;
    *) echo "error: binary is not universal (got: $ARCHS)" >&2; exit 1 ;;
esac
echo "    universal binary OK: $ARCHS"

# 2. Assemble Conan.app in clean staging (same layout as build-app.sh).
echo "==> assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Conan"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# 3. Embed Sparkle.framework (inside-out signed), then sign the app for
#    distribution: hardened runtime + secure timestamp, no entitlements.
echo "==> embedding Sparkle.framework"
"$ROOT/scripts/embed-sparkle.sh" "$APP" "$DEV_ID" --options runtime --timestamp

echo "==> codesign (Developer ID, hardened runtime)"
codesign --force --sign "$DEV_ID" --options runtime --timestamp "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

# 4. Team-match guard (this machine has multiple teams).
APP_TEAM="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
NOTARY_TEAM_ID="${NOTARY_TEAM_ID:-$(printf '%s' "$DEV_ID" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')}"
if [ -n "$APP_TEAM" ] && [ "$APP_TEAM" != "$NOTARY_TEAM_ID" ]; then
    echo "error: signing team ($APP_TEAM) != notary team ($NOTARY_TEAM_ID)" >&2
    exit 1
fi
echo "    signed by team $APP_TEAM"

# 5. Notarize + staple the app (unless skipping).
if [ "$SKIP_NOTARIZE" != "1" ]; then
    echo "==> notarize app (profile: $NOTARY_PROFILE)"
    ditto -c -k --keepParent "$APP" "$STAGING/Conan.zip"
    xcrun notarytool submit "$STAGING/Conan.zip" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
    xcrun stapler validate "$APP"
    spctl -a -vvv -t exec "$APP" || true
else
    echo "==> SKIP_NOTARIZE=1: skipping app notarization"
fi

# 6. Build the DMG (drag-to-Applications).
echo "==> hdiutil create $DIST/Conan.dmg"
DMG_STAGE="$(mktemp -d)"
cp -R "$APP" "$DMG_STAGE/Conan.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "Conan" -srcfolder "$DMG_STAGE" -fs HFS+ -format UDZO -ov "$DIST/Conan.dmg"
rm -rf "$DMG_STAGE"

# 7. Notarize + staple the DMG (unless skipping).
if [ "$SKIP_NOTARIZE" != "1" ]; then
    echo "==> notarize DMG"
    xcrun notarytool submit "$DIST/Conan.dmg" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DIST/Conan.dmg"
    xcrun stapler validate "$DIST/Conan.dmg"
    echo "==> done: $DIST/Conan.dmg (signed, notarized, stapled — universal)"
else
    echo "==> done: $DIST/Conan.dmg (signed, NOT notarized — local inspection only)"
fi
