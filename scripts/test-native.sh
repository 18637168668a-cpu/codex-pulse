#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-preview.XXXXXX")"
xcrun swiftc -D LAYOUT_PREVIEW -parse-as-library \
  "$ROOT/native/CodexPulseWidget/CodexPulseWidget.swift" "$ROOT/tests/LayoutPreview.swift" \
  -o "$STAGE/preview"
export PULSE_PREVIEW_DIR="${PULSE_PREVIEW_DIR:-$STAGE}"
"$STAGE/preview" -AppleLanguages '(en)'
"$STAGE/preview" -AppleLanguages '(zh-Hans)'
xcrun swiftc -D SETUP_PREVIEW -parse-as-library \
  "$ROOT/native/CodexPulse/CodexPulseApp.swift" "$ROOT/tests/SetupPreview.swift" \
  -o "$STAGE/setup-preview"
PULSE_SETUP_PREVIEW="$PULSE_PREVIEW_DIR/setup-en.png" "$STAGE/setup-preview" -AppleLanguages '(en)'
PULSE_SETUP_PREVIEW="$PULSE_PREVIEW_DIR/setup-zh.png" "$STAGE/setup-preview" -AppleLanguages '(zh-Hans)'
echo "Preview output: $PULSE_PREVIEW_DIR"
