#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

sudo docker compose down --remove-orphans || true
sudo docker rm -f ipsec-left ipsec-right >/dev/null 2>&1 || true
sudo docker network rm ipsec_outer >/dev/null 2>&1 || true

echo 'Old lab containers/network removed.'
echo 'Host lab-data was NOT deleted.'
echo 'Run ./scripts/start-lab.sh to recreate the lab.'
