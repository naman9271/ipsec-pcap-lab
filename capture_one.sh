#!/usr/bin/env bash
# Compatibility entry point.  This avoids the retired capture implementation,
# which used a hard-coded home-directory path and an obsolete metadata schema.
set -euo pipefail
CLASS="${1:?Usage: $0 CLASS PROFILE RUN}"
PROFILE="${2:?Usage: $0 CLASS PROFILE RUN}"
RUN="${3:?Usage: $0 CLASS PROFILE RUN}"
case "$CLASS" in
  file) CLASS='file_transfer' ;;
  ping) CLASS='icmp' ;;
esac
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$ROOT/lab/scripts/capture_one.sh" "$CLASS" "$PROFILE" "$RUN"
