#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; SIGNED=0
if [ "${1:-}" = '--signed' ]; then SIGNED=1; shift; fi
[ "$#" -eq 0 ] || { echo 'Usage: bash scripts/package-release.sh [--signed]' >&2; exit 2; }
VERSION="$(cd "$ROOT" && node -p "require('./package.json').version")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid package version: $VERSION" >&2; exit 1; }
SUFFIX='unsigned'; [ "$SIGNED" -eq 0 ] || SUFFIX='signed-notarized'
NAME="Codex-Pulse-$VERSION-universal-$SUFFIX"; DIST="$ROOT/dist"; APP="$ROOT/build/Codex Pulse.app"
ZIP="$DIST/$NAME.zip"; DMG="$DIST/$NAME.dmg"
[ "$SIGNED" -eq 0 ] && bash "$ROOT/scripts/build.sh" --bundle-runtime
bash "$ROOT/scripts/verify-release.sh" --app "$APP"
[ "$SIGNED" -eq 0 ] && "$APP/Contents/Resources/runtime/node" --test "$ROOT"/tests/*.test.mjs
if [ "$SIGNED" -eq 1 ]; then spctl --assess --type execute --verbose=4 "$APP"; xcrun stapler validate "$APP"; fi
mkdir -p "$DIST"; rm -f "$ZIP" "$DMG"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-dmg-stage.XXXXXX")"; trap 'rm -rf "$STAGE"' EXIT
ditto --norsrc --noextattr "$APP" "$STAGE/Codex Pulse.app"; ln -s /Applications "$STAGE/Applications"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
hdiutil create -quiet -volname "Codex Pulse $VERSION" -srcfolder "$STAGE" -format UDZO -ov "$DMG"
bash "$ROOT/scripts/verify-release.sh" --app "$APP" --zip "$ZIP" --dmg "$DMG"
(cd "$DIST" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS.txt)
echo "Packaged $SUFFIX artifacts: $ZIP and $DMG"
