#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROFILE="${1:?Usage: ./scripts/apply_profile.sh PROFILE_NUMBER}"
CONF="$ROOT/configs/p${PROFILE}.conf"

if [[ ! -f "$CONF" ]]; then
    echo "Profile configuration not found: $CONF" >&2
    exit 1
fi

LAB_PSK="IPsec-ML-Lab-PSK-2026-DoNotReuse"
if [[ -f "$ROOT/.env" ]]; then
    # shellcheck disable=SC1091
    source "$ROOT/.env"
fi

for C in ipsec-left ipsec-right; do
    sudo docker cp "$CONF" "$C:/etc/ipsec.conf"
    printf '%s\n' "@left @right : PSK \"$LAB_PSK\"" \
      | sudo docker exec -i "$C" sh -c 'cat > /etc/ipsec.secrets && chmod 600 /etc/ipsec.secrets'
done

sudo docker exec ipsec-left ipsec stop >/dev/null 2>&1 || true
sudo docker exec ipsec-right ipsec stop >/dev/null 2>&1 || true
sleep 1

sudo docker exec ipsec-right ipsec start
sleep 1
sudo docker exec ipsec-left ipsec start
sleep 2
sudo docker exec ipsec-left ipsec up lab
sleep 2

echo
echo '===== IPSEC STATUS ====='
sudo docker exec ipsec-left ipsec statusall

echo
echo '===== XFRM STATE ====='
sudo docker exec ipsec-left ip xfrm state

echo
echo '===== XFRM POLICY ====='
sudo docker exec ipsec-left ip xfrm policy
