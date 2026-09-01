#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_RUNTIME=0
if [ "${1:-}" = '--bundle-runtime' ]; then BUNDLE_RUNTIME=1; shift; fi
if [ "$#" -ne 0 ]; then echo 'Usage: bash scripts/build.sh [--bundle-runtime]' >&2; exit 2; fi
if [ "$(uname -s)" != Darwin ]; then echo 'Native widgets require macOS.' >&2; exit 1; fi
xcrun --find swiftc >/dev/null
xcodebuild -version >/dev/null
VERSION="$(cd "$ROOT" && node -p "require('./package.json').version")"
for file in "$ROOT/native/CodexPulse/Info.plist" "$ROOT/native/CodexPulseWidget/Info.plist"; do
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$file")" = '$(MARKETING_VERSION)' ] || { echo "Expected MARKETING_VERSION template in $file." >&2; exit 1; }
done
grep -Fq "MARKETING_VERSION = $VERSION;" "$ROOT/native/CodexPulse.xcodeproj/project.pbxproj" || { echo "Version mismatch in Xcode project (expected $VERSION)." >&2; exit 1; }
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
xcodebuild -quiet -project "$ROOT/native/CodexPulse.xcodeproj" -scheme CodexPulse \
  -configuration Release -derivedDataPath "$STAGE" CODE_SIGNING_ALLOWED=NO ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO build
APP="$STAGE/Build/Products/Release/Codex Pulse.app"
[ -d "$APP" ] || { echo 'Xcode did not produce the app bundle.' >&2; exit 1; }
RESOURCES="$APP/Contents/Resources"
mkdir -p "$RESOURCES/scripts" "$RESOURCES/runtime"
ditto --norsrc --noextattr "$ROOT/bridge" "$RESOURCES/bridge"
ditto --norsrc --noextattr "$ROOT/scripts/manage.mjs" "$RESOURCES/scripts/manage.mjs"
ditto --norsrc --noextattr "$ROOT/scripts/installer.mjs" "$RESOURCES/scripts/installer.mjs"
ditto --norsrc --noextattr "$ROOT/package.json" "$RESOURCES/package.json"
ditto --norsrc --noextattr "$ROOT/LICENSE" "$RESOURCES/LICENSE.txt"
if [ "$BUNDLE_RUNTIME" -eq 1 ]; then "$ROOT/scripts/fetch-node-runtime.sh" --output "$RESOURCES/runtime"; fi
xattr -cr "$APP"
if [ -f "$APP/Contents/Resources/runtime/node" ]; then codesign --force --timestamp=none --options runtime --sign - --entitlements "$ROOT/scripts/node-runtime.entitlements.plist" "$APP/Contents/Resources/runtime/node"; fi
codesign --force --timestamp=none --options runtime --sign - --entitlements "$ROOT/native/CodexPulseWidget/CodexPulseWidget.entitlements" "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex"
codesign --force --timestamp=none --options runtime --sign - --entitlements "$ROOT/native/CodexPulse/CodexPulse.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
lipo "$APP/Contents/MacOS/Codex Pulse" -verify_arch arm64 x86_64
WIDGET_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex/Contents/Info.plist")"
lipo "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex/Contents/MacOS/$WIDGET_EXECUTABLE" -verify_arch arm64 x86_64
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")" = "$VERSION" ]
[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/PlugIns/CodexPulseWidgetExtension.appex/Contents/Info.plist")" = "$VERSION" ]
[ "$BUNDLE_RUNTIME" -eq 0 ] || lipo "$APP/Contents/Resources/runtime/node" -verify_arch arm64 x86_64
mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/Codex Pulse.app"
ditto --norsrc --noextattr "$APP" "$ROOT/build/Codex Pulse.app"
# File-provider folders can add Finder metadata during copy. This is only our
# freshly generated build output, never a downloaded app or a user's installation.
xattr -cr "$ROOT/build/Codex Pulse.app"
codesign --verify --deep --strict "$ROOT/build/Codex Pulse.app"
if [ "$BUNDLE_RUNTIME" -eq 1 ]; then echo "Built universal ad-hoc preview with bundled Node: $ROOT/build/Codex Pulse.app"; else echo "Built universal ad-hoc source preview: $ROOT/build/Codex Pulse.app"; fi
echo 'This build is not Developer ID signed or notarized.'
