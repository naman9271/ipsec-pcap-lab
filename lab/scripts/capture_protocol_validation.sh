#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
mkdir -p "$ROOT/pcaps/protocol_validation"

capture_profile() {
  local p="$1"
  local out="$ROOT/pcaps/protocol_validation/ike_session_p$(printf '%02d' "$p").pcap"
  local tmp="${out}.partial" pid='' completed=false ping_cmd
  [[ ! -e "$out" ]] || return 0
  rm -f "$tmp"
  cleanup() {
    [[ -n "$pid" ]] && sudo kill "$pid" >/dev/null 2>&1 || true
    [[ "$completed" == true ]] || rm -f "$tmp" "$out"
  }
  trap cleanup RETURN

  sudo docker exec ipsec-left ipsec stop >/dev/null 2>&1 || true
  sudo docker exec ipsec-right ipsec stop >/dev/null 2>&1 || true
  local idx veth
  idx=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink)
  veth=$(ip -o link show | awk -F': ' -v i="$idx" '$1==i {split($2,a,"@");print a[1]}')
  [[ -n "$veth" ]] || { echo 'Could not determine host-side veth.' >&2; return 4; }
  sudo tcpdump -U -i "$veth" -s 0 -w "$tmp" 'udp port 500 or udp port 4500 or esp' >/tmp/ipsec-protocol-tcpdump.log 2>&1 &
  pid=$!
  sleep 1
  "$ROOT/lab/scripts/apply_profile.sh" "$p" >/dev/null
  case "$p" in
    5) ping_cmd='ping -6 -c 3 -I fd10::1 fd20::1' ;;
    4) ping_cmd='ping -c 3 -I 172.30.0.2 172.30.0.3' ;;
    *) ping_cmd='ping -c 3 -I 10.10.0.1 10.20.0.1' ;;
  esac
  sudo docker exec ipsec-left sh -c "$ping_cmd" >/dev/null
  sleep 1
  sudo kill "$pid" >/dev/null 2>&1 || true
  wait "$pid" >/dev/null 2>&1 || true
  pid=''
  mv "$tmp" "$out"
  python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label protocol_session --profile "$p" --role protocol_validation --generator ike-negotiation-and-esp --params '{"duration_s":8,"ike_before_traffic":true}'
  completed=true
}

for p in 1 2 3 4 5; do
  capture_profile "$p"
done
