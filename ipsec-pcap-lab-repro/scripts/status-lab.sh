#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

sudo docker compose ps

echo
echo 'LEFT addresses:'
sudo docker exec ipsec-left ip -br addr 2>/dev/null || true

echo
echo 'RIGHT addresses:'
sudo docker exec ipsec-right ip -br addr 2>/dev/null || true
