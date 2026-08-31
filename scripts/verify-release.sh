#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; APP="$ROOT/build/Codex Pulse.app"; ZIP=''; DMG=''
while [ "$#" -gt 0 ]; do case "$1" in --app) APP="${2:-}"; shift 2 ;; --zip) ZIP="${2:-}"; shift 2 ;; --dmg) DMG="${2:-}"; shift 2 ;; *) echo 'Usage: bash scripts/verify-release.sh [--app APP] [--zip ZIP] [--dmg DMG]' >&2; exit 2 ;; esac; done
VERSION="$(cd "$ROOT" && node -p "require('./package.json').version")"
entitlement_is_true() {
  local binary="$1" key="$2" plist value
  plist="$(mktemp "${TMPDIR:-/tmp}/codex-pulse-entitlements.XXXXXX")"
  codesign -d --entitlements :- "$binary" > "$plist" 2>/dev/null
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$plist")"
  rm -f "$plist"
  [ "$value" = true ]
}
verify_app() {
  local candidate="$1" plist="$1/Contents/Info.plist" runtime="$1/Contents/Resources/runtime/node" widget widget_executable
  [ -d "$candidate" ] || { echo "Missing app: $candidate" >&2; return 1; }
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" = "$VERSION" ]
  widget="$candidate/Contents/PlugIns/CodexPulseWidgetExtension.appex"
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$widget/Contents/Info.plist")" = "$VERSION" ]
  codesign --verify --deep --strict "$candidate"; lipo -verify_arch arm64 x86_64 "$candidate/Contents/MacOS/Codex Pulse"
  widget_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$widget/Contents/Info.plist")"
  lipo -verify_arch arm64 x86_64 "$widget/Contents/MacOS/$widget_executable"
  for path in "$candidate/Contents/Resources/bridge" "$candidate/Contents/Resources/scripts/manage.mjs" "$candidate/Contents/Resources/scripts/installer.mjs" "$candidate/Contents/Resources/package.json" "$candidate/Contents/Resources/LICENSE.txt" "$runtime" "$candidate/Contents/Resources/runtime/NODE-LICENSE.txt"; do [ -e "$path" ] || { echo "Missing bundled resource: $path" >&2; return 1; }; done
  lipo -verify_arch arm64 x86_64 "$runtime"; "$runtime" --version | grep -qx 'v22.23.2'
  entitlement_is_true "$runtime" 'com.apple.security.cs.allow-jit'
  entitlement_is_true "$widget" 'com.apple.security.app-sandbox'
  entitlement_is_true "$widget" 'com.apple.security.network.client'
}
verify_app "$APP"
if [ -n "$ZIP" ]; then
  ZIP_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-zip.XXXXXX")"; trap 'rm -rf "$ZIP_STAGE"' EXIT
  ditto -x -k "$ZIP" "$ZIP_STAGE"; verify_app "$ZIP_STAGE/Codex Pulse.app"; rm -rf "$ZIP_STAGE"; trap - EXIT
fi
if [ -n "$DMG" ]; then
  MOUNT="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-dmg.XXXXXX")"; trap 'hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; rmdir "$MOUNT" 2>/dev/null || true' EXIT
  hdiutil attach -quiet -readonly -nobrowse -mountpoint "$MOUNT" "$DMG"; verify_app "$MOUNT/Codex Pulse.app"; [ "$(readlink "$MOUNT/Applications")" = '/Applications' ]; hdiutil detach "$MOUNT" -quiet; rmdir "$MOUNT"; trap - EXIT
fi
echo 'Release verification passed.'
