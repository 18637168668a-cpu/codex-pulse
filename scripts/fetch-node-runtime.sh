#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE_VERSION='22.23.2'
ARM64_SHA256='61130f394c1630d211dd50aecc4353d379480f36d3ac913cd85dbba1aed585c6'
X64_SHA256='58e99022c2ff89395576cc7fd4d98cea24bb68081475d5f88b801ee8729fb026'
OUTPUT=''; REFRESH=0
while [ "$#" -gt 0 ]; do case "$1" in --output) OUTPUT="${2:-}"; shift 2 ;; --refresh) REFRESH=1; shift ;; *) echo 'Usage: bash scripts/fetch-node-runtime.sh --output DIR [--refresh]' >&2; exit 2 ;; esac; done
[ -n "$OUTPUT" ] || { echo '--output is required.' >&2; exit 2; }
[ "$(uname -s)" = Darwin ] || { echo 'The bundled runtime is only built on macOS.' >&2; exit 1; }
CACHE="$ROOT/build/node-runtime-cache/v$NODE_VERSION"; mkdir -p "$CACHE"
fetch() { local arch sha archive; arch="$1"; sha="$2"; archive="$CACHE/node-v$NODE_VERSION-darwin-$arch.tar.gz"; if [ "$REFRESH" -eq 1 ] || [ ! -f "$archive" ]; then curl --fail --location --proto '=https' --tlsv1.2 --silent --show-error "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-darwin-$arch.tar.gz" -o "$archive"; fi; printf '%s  %s\n' "$sha" "$archive" | shasum -a 256 -c -; }
fetch arm64 "$ARM64_SHA256"; fetch x64 "$X64_SHA256"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/codex-pulse-node.XXXXXX")"; trap 'rm -rf "$WORK"' EXIT
tar -xzf "$CACHE/node-v$NODE_VERSION-darwin-arm64.tar.gz" -C "$WORK"; tar -xzf "$CACHE/node-v$NODE_VERSION-darwin-x64.tar.gz" -C "$WORK"
mkdir -p "$OUTPUT"
lipo -create "$WORK/node-v$NODE_VERSION-darwin-arm64/bin/node" "$WORK/node-v$NODE_VERSION-darwin-x64/bin/node" -output "$OUTPUT/node"
chmod 755 "$OUTPUT/node"; cp "$WORK/node-v$NODE_VERSION-darwin-arm64/LICENSE" "$OUTPUT/NODE-LICENSE.txt"
lipo -verify_arch arm64 x86_64 "$OUTPUT/node"
codesign --force --timestamp=none --options runtime --sign - --entitlements "$ROOT/scripts/node-runtime.entitlements.plist" "$OUTPUT/node"
[ "$("$OUTPUT/node" --version)" = "v$NODE_VERSION" ]
echo "Bundled official Node.js v$NODE_VERSION runtime at $OUTPUT/node"
