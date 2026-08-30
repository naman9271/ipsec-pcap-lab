#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT/lab"
sudo docker compose up -d --build
echo 'Lab started. Apply a profile with: lab/scripts/apply_profile.sh 1'
