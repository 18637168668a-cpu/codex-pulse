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
echo "Preview output: $PULSE_PREVIEW_DIR"
