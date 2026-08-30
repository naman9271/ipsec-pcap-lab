#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROFILE="${1:?Usage: $0 PROFILE_NUMBER}"
CONF="$ROOT/lab/configs/p${PROFILE}.conf"
[[ -f "$CONF" ]] || { echo "Profile configuration not found: $CONF" >&2; exit 2; }
PSK='IPsec-ML-Lab-PSK-2026-DoNotReuse'
for c in ipsec-left ipsec-right; do
  sudo docker cp "$CONF" "$c:/etc/ipsec.conf"
  printf '%s\n' "@left @right : PSK \"$PSK\"" | sudo docker exec -i "$c" sh -c 'cat >/etc/ipsec.secrets && chmod 600 /etc/ipsec.secrets'
  sudo docker exec "$c" pkill -f 'aiosmtpd|websocket' >/dev/null 2>&1 || true
done
sudo docker exec ipsec-left ipsec stop >/dev/null 2>&1 || true
sudo docker exec ipsec-right ipsec stop >/dev/null 2>&1 || true
sleep 1; sudo docker exec ipsec-right ipsec start; sleep 1; sudo docker exec ipsec-left ipsec start; sleep 2
sudo docker exec ipsec-left ipsec up lab; sleep 2
sudo docker exec ipsec-left ipsec statusall
