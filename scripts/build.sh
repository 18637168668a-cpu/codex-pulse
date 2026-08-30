#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ "$(uname -s)" != Darwin ]; then echo 'Native widgets require macOS.' >&2; exit 1; fi
xcrun --find swiftc >/dev/null
xcodebuild -version >/dev/null
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-build.XXXXXX")"
xcodebuild -quiet -project "$ROOT/native/CodexPulse.xcodeproj" -scheme CodexPulse \
  -configuration Release -derivedDataPath "$STAGE" CODE_SIGNING_ALLOWED=NO build
APP="$STAGE/Build/Products/Release/Codex Pulse.app"
xattr -cr "$APP"
codesign --force --timestamp=none --options runtime --sign - \
  --entitlements "$ROOT/native/CodexPulseWidget/CodexPulseWidget.entitlements" \
  "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex"
codesign --force --timestamp=none --options runtime --sign - \
  --entitlements "$ROOT/native/CodexPulse/CodexPulse.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
mkdir -p "$ROOT/build"
ditto --norsrc --noextattr "$APP" "$ROOT/build/Codex Pulse.app"
echo "Built for $(uname -m): $ROOT/build/Codex Pulse.app"
echo 'Local ad-hoc signature only; this is not a notarized download.'
