#!/usr/bin/env bash
set -euo pipefail

# Update the Homebrew cask (packaging/homebrew/conan.rb) for a release and, if
# a local clone of schnaq/homebrew-tap is available, sync + push it there.
#
# Usage:
#   ./scripts/update-cask.sh <version> <dmg-path> [--render-only]
#
#   --render-only   rewrite the cask file only (no tap sync) — used by
#                   publish.sh before the release commit
#
# Env:
#   TAP_DIR=...   path to a local clone of schnaq/homebrew-tap
#                 (default: ../homebrew-tap next to this repo, if present)
#
# Missing tap clone is not an error — prints manual publish instructions.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CASK="$ROOT/packaging/homebrew/conan.rb"

VERSION="${1:-}"
DMG="${2:-}"
RENDER_ONLY="${3:-}"
[ -n "$VERSION" ] && [ -n "$DMG" ] || {
    echo "usage: $(basename "$0") <version> <dmg-path> [--render-only]" >&2
    exit 1
}
VERSION="${VERSION#v}"
[ -f "$DMG" ] || { echo "error: DMG not found: $DMG" >&2; exit 1; }
[ -f "$CASK" ] || { echo "error: cask not found: $CASK" >&2; exit 1; }

SHA256="$(shasum -a 256 "$DMG" | awk '{print $1}')"

# Rewrite the version + sha256 stanzas in place (idempotent).
TMP="$(mktemp)"
sed -E \
    -e "s|^(  version \").*(\")$|\1${VERSION}\2|" \
    -e "s|^(  sha256 \").*(\")$|\1${SHA256}\2|" \
    "$CASK" > "$TMP"
mv "$TMP" "$CASK"
echo "==> cask updated: $CASK (version $VERSION)"

[ "$RENDER_ONLY" = "--render-only" ] && exit 0

TAP_DIR="${TAP_DIR:-$ROOT/../homebrew-tap}"
if [ -d "$TAP_DIR/.git" ]; then
    mkdir -p "$TAP_DIR/Casks"
    cp "$CASK" "$TAP_DIR/Casks/conan.rb"
    git -C "$TAP_DIR" add Casks/conan.rb
    if git -C "$TAP_DIR" diff --cached --quiet; then
        echo "==> tap already up to date: $TAP_DIR"
    else
        git -C "$TAP_DIR" commit -qm "conan $VERSION"
        git -C "$TAP_DIR" push -q
        echo "==> tap updated + pushed: $TAP_DIR"
    fi
else
    cat <<EOF
==> no tap clone at $TAP_DIR — publish the cask manually:
      git clone https://github.com/schnaq/homebrew-tap
      mkdir -p homebrew-tap/Casks && cp "$CASK" homebrew-tap/Casks/conan.rb
      cd homebrew-tap && git add Casks/conan.rb && git commit -m "conan $VERSION" && git push
    (or set TAP_DIR=/path/to/homebrew-tap and re-run)
EOF
fi
