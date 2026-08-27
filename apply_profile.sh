#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?Usage: ./apply_profile.sh PROFILE_NUMBER}"
LAB="$HOME/ipsec-pcap-lab"
CONF="$LAB/configs/p${PROFILE}.conf"

if [[ ! -f "$CONF" ]]; then
    echo "Profile configuration not found: $CONF"
    exit 1
fi

echo "Installing profile P${PROFILE}..."

for C in ipsec-left ipsec-right; do
    sudo docker cp "$CONF" "$C:/etc/ipsec.conf"

    printf '%s\n' '@left @right : PSK "IPsec-ML-Lab-PSK-2026-DoNotReuse"' |
        sudo docker exec -i "$C" sh -c \
        'cat > /etc/ipsec.secrets && chmod 600 /etc/ipsec.secrets'
done

echo "Stopping any previous strongSwan instances..."

sudo docker exec ipsec-left ipsec stop >/dev/null 2>&1 || true
sudo docker exec ipsec-right ipsec stop >/dev/null 2>&1 || true

sleep 1

echo "Starting responder..."
sudo docker exec ipsec-right ipsec start

sleep 1

echo "Starting initiator..."
sudo docker exec ipsec-left ipsec start

sleep 2

echo "Initiating IPsec connection..."
sudo docker exec ipsec-left ipsec up lab

sleep 2

echo
echo "===== IPSEC STATUS ====="
sudo docker exec ipsec-left ipsec statusall

echo
echo "===== XFRM STATE ====="
sudo docker exec ipsec-left ip xfrm state

echo
echo "===== XFRM POLICY ====="
sudo docker exec ipsec-left ip xfrm policy
