#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
chmod +x lab/scripts/*.sh lab/scripts/*.py lab/docker/entrypoint.sh
python3 lab/scripts/migrate_metadata.py
lab/scripts/start_lab.sh
for c in web video file_transfer icmp; do
  for p in 1 2 3 4 5; do out="pcaps/known/$c/${c}_p$(printf '%02d' "$p")_R02.pcap"; [[ -e "$out" ]] || lab/scripts/capture_one.sh "$c" "$p" R02; done
done
for c in email messaging voip; do
  for p in 1 2 3 4 5; do for r in R01 R02; do out="pcaps/known/$c/${c}_p$(printf '%02d' "$p")_${r}.pcap"; [[ -e "$out" ]] || lab/scripts/capture_one.sh "$c" "$p" "$r"; done; done
done
lab/scripts/capture_evaluation.sh
lab/scripts/capture_protocol_validation.sh
python3 lab/scripts/validate_dataset.py
sha256sum -c lab/original-20.sha256
echo 'Complete: protected hashes verified unchanged.'
