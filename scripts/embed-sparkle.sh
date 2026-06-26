#!/usr/bin/env bash
set -euo pipefail

# Embed Sparkle.framework into an assembled Conan.app and inside-out codesign it.
# Run AFTER assembling the bundle and BEFORE the final `codesign` of the app.
#
# Usage: embed-sparkle.sh <APP_PATH> <SIGN_IDENTITY> [extra codesign flags...]
#   embed-sparkle.sh Conan.app "-"                                   # ad-hoc (build-app.sh)
#   embed-sparkle.sh Conan.app "$DEV_ID" --options runtime --timestamp   # release.sh

APP="${1:?usage: embed-sparkle.sh <APP> <IDENTITY> [flags...]}"
IDENTITY="${2:?usage: embed-sparkle.sh <APP> <IDENTITY> [flags...]}"
shift 2
FLAGS=("$@")

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FW_SRC="$(find "$ROOT/.build/artifacts" -type d -name Sparkle.framework -path '*macos-arm64_x86_64*' 2>/dev/null | head -1)"
[ -n "$FW_SRC" ] || { echo "error: Sparkle.framework not found under .build/artifacts — run 'swift build' first" >&2; exit 1; }

echo "    embedding Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
cp -R "$FW_SRC" "$APP/Contents/Frameworks/Sparkle.framework"

FW="$APP/Contents/Frameworks/Sparkle.framework"
V="$FW/Versions/B"

# `${FLAGS[@]+...}` keeps this safe under `set -u` with an empty flag list (bash 3.2).
sign() { codesign --force --sign "$IDENTITY" ${FLAGS[@]+"${FLAGS[@]}"} "$1"; }

# Inside-out: nested XPC services + helpers first, then the framework bundle.
sign "$V/XPCServices/Installer.xpc"
sign "$V/XPCServices/Downloader.xpc"
sign "$V/Updater.app"
sign "$V/Autoupdate"
sign "$FW"
echo "    Sparkle.framework signed ($IDENTITY)"
