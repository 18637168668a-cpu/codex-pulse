#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
node "$ROOT/scripts/manage.mjs" preflight
if [ "${1:-}" = '--dry-run' ]; then exit 0; fi
if [ "$#" -gt 0 ]; then echo 'Usage: bash scripts/install.sh [--dry-run]' >&2; exit 1; fi
bash "$ROOT/scripts/build.sh"
node "$ROOT/scripts/manage.mjs" install
