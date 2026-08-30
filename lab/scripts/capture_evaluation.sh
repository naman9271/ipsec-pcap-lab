#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
capture(){ local name=$1 label=$2 profile=$3 role=$4 anomaly=$5 cmd=$6; local out="$ROOT/pcaps/$role/${name}.pcap"; [[ ! -e "$out" ]] || return 0
  "$ROOT/lab/scripts/apply_profile.sh" "$profile" >/dev/null
  local idx veth pid; idx=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink); veth=$(ip -o link show | awk -F': ' -v i="$idx" '$1==i {split($2,a,"@");print a[1]}'); [[ -n "$veth" ]] || exit 4
  sudo tcpdump -U -i "$veth" -s 0 -w "$out" 'esp or udp port 4500' >/tmp/ipsec-eval-tcpdump.log 2>&1 & pid=$!
  trap 'sudo kill "$pid" >/dev/null 2>&1 || true' RETURN; sleep 1; sudo docker exec ipsec-left sh -c "$cmd"; sleep 1; sudo kill "$pid" >/dev/null 2>&1 || true; trap - RETURN
  if [[ -n "$anomaly" ]]; then
    python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label "$label" --profile "$profile" --role "$([[ $role == ood ]] && echo ood_eval || echo anomaly_eval)" --generator "$label" --params '{"duration_s":10,"isolated_lab":true}' --anomaly "$anomaly"
  else
    python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label "$label" --profile "$profile" --role ood_eval --generator "$label" --params '{"duration_s":10,"isolated_lab":true}'
  fi
}
# OOD is deliberately distinct from the seven training labels.
capture dns_p01 dns 1 ood '' "for i in \$(seq 1 30); do printf 'x' | timeout 1 nc -u -s 10.10.0.1 10.20.0.1 5353 || true; sleep .1; done"
capture dns_p02 dns 2 ood '' "for i in \$(seq 1 30); do printf 'x' | timeout 1 nc -u -s 10.10.0.1 10.20.0.1 5353 || true; sleep .1; done"
capture ssh_p03 interactive_ssh 3 ood '' "for i in \$(seq 1 50); do printf 'terminal-command-%s\\n' \$i | timeout 1 nc -s 10.10.0.1 10.20.0.1 2222 || true; sleep .15; done"
capture gaming_udp_p04 gaming_udp 4 ood '' "for i in \$(seq 1 150); do head -c 180 /dev/urandom | timeout 1 nc -u -s 172.30.0.2 172.30.0.3 27015 || true; sleep .05; done"
# Controlled anomaly traffic is generated only between the isolated lab endpoints.
capture icmp_flood_p01 icmp 1 anomaly icmp_flood "ping -I 10.10.0.1 -f -c 2000 -s 256 10.20.0.1 >/dev/null || true"
capture udp_flood_p02 unknown 2 anomaly udp_flood "head -c 4000000 /dev/urandom | nc -u -s 10.10.0.1 10.20.0.1 9999 || true"
capture beacon_burst_p03 unknown 3 anomaly beacon_then_burst "for i in \$(seq 1 8); do printf ping | nc -u -s 10.10.0.1 10.20.0.1 9900 || true; sleep .5; done; head -c 1000000 /dev/urandom | nc -u -s 10.10.0.1 10.20.0.1 9900 || true"
