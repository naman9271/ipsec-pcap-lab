#!/usr/bin/env bash
# Remove generated anomaly samples only.  Historical provenance in
# pcaps/anomaly/archive is deliberately retained.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ANOMALY_DIR="$ROOT/pcaps/anomaly"

find "$ANOMALY_DIR" -maxdepth 1 -type f -name '*.pcap' -print -delete
find "$ANOMALY_DIR" -maxdepth 1 -type f -name '*.partial' -print -delete
python3 "$ROOT/lab/scripts/migrate_metadata.py"
echo 'Generated anomaly captures and their metadata rows were removed. Archive provenance was retained.'
