#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP="${1:-$ROOT/build/Codex Pulse.app}"
for key in DEVELOPER_ID_APPLICATION APPLE_ID APPLE_APP_SPECIFIC_PASSWORD APPLE_TEAM_ID; do [ -n "${!key:-}" ] || { echo "Missing required environment variable: $key" >&2; exit 1; }; done
[[ "$DEVELOPER_ID_APPLICATION" == 'Developer ID Application:'* ]] || { echo 'DEVELOPER_ID_APPLICATION must name a Developer ID Application identity.' >&2; exit 1; }
[ -d "$APP" ] || { echo "Missing app: $APP" >&2; exit 1; }
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" --entitlements "$ROOT/scripts/node-runtime.entitlements.plist" "$APP/Contents/Resources/runtime/node"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" --entitlements "$ROOT/native/CodexPulseWidget/CodexPulseWidget.entitlements" "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex"
codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APPLICATION" --entitlements "$ROOT/native/CodexPulse/CodexPulse.entitlements" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-notarize.XXXXXX")"; ARCHIVE="$WORK/archive.zip"; trap 'rm -rf "$WORK"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ARCHIVE"
xcrun notarytool submit "$ARCHIVE" --apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait
xcrun stapler staple "$APP"; codesign --verify --deep --strict "$APP"; spctl --assess --type execute --verbose=4 "$APP"
echo 'Developer ID signing and notarization passed. Run bash scripts/package-release.sh --signed to package this stapled app without rebuilding it.'
