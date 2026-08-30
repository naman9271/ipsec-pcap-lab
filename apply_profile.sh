#!/usr/bin/env bash
# Compatibility entry point.  The maintained implementation is in lab/scripts.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/lab/scripts/apply_profile.sh" "$@"
