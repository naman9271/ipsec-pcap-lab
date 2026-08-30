#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
for p in 1 2 3 4 5; do
 out="$ROOT/pcaps/protocol_validation/ike_session_p$(printf '%02d' "$p").pcap"; [[ -e "$out" ]] && continue
 sudo docker exec ipsec-left ipsec stop >/dev/null 2>&1 || true; sudo docker exec ipsec-right ipsec stop >/dev/null 2>&1 || true
 idx=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink); veth=$(ip -o link show | awk -F': ' -v i="$idx" '$1==i {split($2,a,"@");print a[1]}'); [[ -n "$veth" ]] || exit 4
 sudo tcpdump -U -i "$veth" -s 0 -w "$out" 'udp port 500 or udp port 4500 or esp' >/tmp/ipsec-protocol-tcpdump.log 2>&1 & pid=$!; trap 'sudo kill "$pid" >/dev/null 2>&1 || true' RETURN
 "$ROOT/lab/scripts/apply_profile.sh" "$p" >/dev/null
 if [[ $p == 5 ]]; then sudo docker exec ipsec-left ping -6 -c 3 -I fd10::1 fd20::1 >/dev/null; else sudo docker exec ipsec-left ping -c 3 -I 10.10.0.1 10.20.0.1 >/dev/null; fi
 sleep 1; sudo kill "$pid" >/dev/null 2>&1 || true; trap - RETURN
 python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label protocol_session --profile "$p" --role protocol_validation --generator ike-negotiation-and-esp --params '{"duration_s":8,"ike_before_traffic":true}'
done
