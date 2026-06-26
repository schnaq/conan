#!/usr/bin/env bash
set -euo pipefail

# Cut a release: stamp the version, build the notarized universal Conan.dmg via
# release.sh (auto-detecting your installed Developer ID cert), then publish it
# as a GitHub release with the DMG attached.
#
# Usage:
#   ./scripts/publish.sh 0.2.0          # version (a leading "v" is fine too)
#
# Env overrides:
#   DEV_ID=...        skip cert auto-detection and use this identity
#   DRY_RUN=1         build + preview only — no commit/tag/push/release
#   SKIP_NOTARIZE=1   passed through to release.sh (un-notarized; dry runs only)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PLIST="$ROOT/Resources/Info.plist"
DRY_RUN="${DRY_RUN:-0}"

# --- version argument ---
RAW="${1:-}"
[ -n "$RAW" ] || { echo "usage: $(basename "$0") <version>   e.g. $(basename "$0") 0.2.0" >&2; exit 1; }
VERSION="${RAW#v}"
printf '%s' "$VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
    || { echo "error: version must be MAJOR.MINOR.PATCH (got: $RAW)" >&2; exit 1; }
TAG="v$VERSION"

# --- preflight ---
command -v gh >/dev/null || { echo "error: gh CLI not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated — run: gh auth login" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || {
    echo "error: working tree not clean — commit or stash first:" >&2
    git status --short >&2
    exit 1
}
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1 || gh release view "$TAG" >/dev/null 2>&1; then
    echo "error: $TAG already exists (tag or release) — pick a new version." >&2
    exit 1
fi

# --- Developer ID identity (auto-detect unless DEV_ID is set) ---
if [ -z "${DEV_ID:-}" ]; then
    CERTS="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p')"
    N="$(printf '%s\n' "$CERTS" | grep -c . || true)"
    [ "$N" != "0" ] || { echo "error: no 'Developer ID Application' identity in the keychain." >&2; exit 1; }
    if [ "$N" != "1" ]; then
        echo "error: multiple Developer ID Application identities — set DEV_ID to one of:" >&2
        printf '  %s\n' "$CERTS" >&2
        exit 1
    fi
    DEV_ID="$(printf '%s\n' "$CERTS" | head -1)"
fi
export DEV_ID

echo "==> releasing $TAG"
echo "    identity : $DEV_ID"
echo "    dry run  : $DRY_RUN"

# --- stamp the version into Info.plist ---
CUR_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST" 2>/dev/null || echo 0)"
NEXT_BUILD=$(( ${CUR_BUILD%%.*} + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT_BUILD" "$PLIST"
echo "==> Info.plist → CFBundleShortVersionString=$VERSION, CFBundleVersion=$NEXT_BUILD"

# --- build + sign + notarize + DMG (the slow, failure-prone part first) ---
"$ROOT/scripts/release.sh"
DMG="$ROOT/dist/Conan-$VERSION.dmg"
cp "$ROOT/dist/Conan.dmg" "$DMG"
echo "==> artifact: $DMG"

# --- publish ---
if [ "$DRY_RUN" = "1" ]; then
    echo "==> DRY_RUN: not committing/tagging/pushing/releasing. Would run:"
    echo "    git commit -m 'chore: release $TAG' -- Resources/Info.plist"
    echo "    git tag $TAG && git push --atomic origin HEAD $TAG"
    echo "    gh release create $TAG '$DMG' --title 'Conan $TAG' --generate-notes --latest"
    git checkout -- "$PLIST"
    echo "==> reverted Info.plist (dry run)"
    exit 0
fi

git commit -qm "chore: release $TAG" -- Resources/Info.plist
git tag "$TAG"
git push -q --atomic origin HEAD "$TAG"
gh release create "$TAG" "$DMG" --title "Conan $TAG" --generate-notes --latest
echo "==> published: $(gh release view "$TAG" --json url -q .url)"
