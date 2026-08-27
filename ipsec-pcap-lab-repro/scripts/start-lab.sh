#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! docker compose version >/dev/null 2>&1; then
    echo 'Docker Compose v2 is required. Try: docker compose version' >&2
    exit 1
fi

sudo docker compose up -d --build

echo
echo 'Lab is running.'
echo 'LEFT outer : 172.30.0.2 / fd00:30::2'
echo 'LEFT inner : 10.10.0.1 / fd10::1'
echo 'RIGHT outer: 172.30.0.3 / fd00:30::3'
echo 'RIGHT inner: 10.20.0.1 / fd20::1'
echo
echo 'Check with: sudo docker compose ps'
echo 'Then activate a VPN profile, e.g.: ./scripts/apply_profile.sh 1'
