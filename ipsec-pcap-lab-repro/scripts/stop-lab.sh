#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

sudo docker compose down --remove-orphans

echo 'IPsec lab containers and the ipsec_outer network have been stopped/removed.'
echo 'The Docker service itself is still running, so other Docker projects are unaffected.'
