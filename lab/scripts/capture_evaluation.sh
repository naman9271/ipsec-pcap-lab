#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
capture(){ local name=$1 label=$2 profile=$3 role=$4 anomaly=$5 cmd=$6; mkdir -p "$ROOT/pcaps/$role"; local out="$ROOT/pcaps/$role/${name}.pcap"; [[ ! -e "$out" ]] || return 0
  "$ROOT/lab/scripts/apply_profile.sh" "$profile" >/dev/null
  local idx veth pid; idx=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink); veth=$(ip -o link show | awk -F': ' -v i="$idx" '$1==i {split($2,a,"@");print a[1]}'); [[ -n "$veth" ]] || exit 4
  sudo tcpdump -U -i "$veth" -s 0 -w "$out" 'esp or udp port 4500' >/tmp/ipsec-eval-tcpdump.log 2>&1 & pid=$!
  trap 'sudo kill "$pid" >/dev/null 2>&1 || true' RETURN; sleep 1; sudo docker exec ipsec-left sh -c "$cmd"; sleep 1; sudo kill "$pid" >/dev/null 2>&1 || true; trap - RETURN
  if [[ -n "$anomaly" ]]; then
    python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label "$label" --profile "$profile" --role "$([[ $role == ood ]] && echo ood_eval || echo anomaly_eval)" --generator "$label" --params '{"duration_s":45,"isolated_lab":true}' --anomaly "$anomaly"
  else
    python3 "$ROOT/lab/scripts/record_capture.py" "$out" --label "$label" --profile "$profile" --role ood_eval --generator "$label" --params '{"duration_s":20,"isolated_lab":true}'
  fi
}
# OOD is deliberately distinct from the seven training labels.
capture dns_p01 dns 1 ood '' "for i in \$(seq 1 30); do printf 'x' | timeout 1 nc -u -s 10.10.0.1 10.20.0.1 5353 || true; sleep .1; done"
capture dns_p02 dns 2 ood '' "for i in \$(seq 1 30); do printf 'x' | timeout 1 nc -u -s 10.10.0.1 10.20.0.1 5353 || true; sleep .1; done"
capture ssh_p03 interactive_ssh 3 ood '' "for i in \$(seq 1 50); do printf 'terminal-command-%s\\n' \$i | timeout 1 nc -s 10.10.0.1 10.20.0.1 2222 || true; sleep .15; done"
capture gaming_udp_p04 gaming_udp 4 ood '' "for i in \$(seq 1 150); do head -c 180 /dev/urandom | timeout 1 nc -u -s 172.30.0.2 172.30.0.3 27015 || true; sleep .05; done"
# Complete the independent OOD matrix.  The source/destination are the tunnel
# selectors; P04 uses its transport-mode outer endpoints.
for p in 1 2 3 4 5; do
  [[ "$p" == 5 ]] && continue  # P05 needs IPv6-specific OOD generation below.
  src=10.10.0.1; dst=10.20.0.1; [[ "$p" == 4 ]] && { src=172.30.0.2; dst=172.30.0.3; }
  capture "dns_p$(printf '%02d' "$p")_R01" dns "$p" ood '' "for i in \$(seq 1 120); do printf 'dns-%s' \$i | nc -u -w 1 -s $src $dst 5353 || true; sleep .15; done"
  capture "ssh_p$(printf '%02d' "$p")_R01" ssh "$p" ood '' "for i in \$(seq 1 30); do printf 'ssh-command-%s\\n' \$i | nc -w 1 -s $src $dst 2222 || true; sleep .4; done"
  capture "gaming_udp_p$(printf '%02d' "$p")_R01" gaming_udp "$p" ood '' "for i in \$(seq 1 250); do head -c 160 /dev/urandom | nc -u -w 1 -s $src $dst 27015 || true; sleep .08; done"
  capture "database_p$(printf '%02d' "$p")_R01" database "$p" ood '' "for i in \$(seq 1 40); do printf 'SELECT %s;' \$i | nc -w 1 -s $src $dst 5432 || true; sleep .3; done"
  capture "remote_desktop_p$(printf '%02d' "$p")_R01" remote_desktop "$p" ood '' "for i in \$(seq 1 80); do head -c 900 /dev/urandom | nc -u -w 1 -s $src $dst 3389 || true; sleep .12; done"
done
for kind in dns ssh gaming_udp database remote_desktop; do
  port=5353; [[ "$kind" == ssh ]] && port=2222; [[ "$kind" == gaming_udp ]] && port=27015; [[ "$kind" == database ]] && port=5432; [[ "$kind" == remote_desktop ]] && port=3389
  capture "${kind}_p05_R01" "$kind" 5 ood '' "for i in \$(seq 1 80); do head -c 120 /dev/urandom | nc -6 -u -w 1 -s fd10::1 fd20::1 $port || true; sleep .15; done"
done
# Ten independent, 45-second isolated-lab captures per anomaly type.
for n in $(seq 1 10); do
  p=$(( (n - 1) % 5 + 1 )); src=10.10.0.1; dst=10.20.0.1; [[ "$p" == 4 ]] && { src=172.30.0.2; dst=172.30.0.3; }
  capture "icmp_flood_p$(printf '%02d' "$p")_R$(printf '%02d' "$n")" unknown "$p" anomaly icmp_flood "timeout 45 ping -f -s 256 -I $src $dst >/dev/null || true"
  capture "udp_flood_p$(printf '%02d' "$p")_R$(printf '%02d' "$n")" unknown "$p" anomaly udp_flood "timeout 45 sh -c 'while :; do head -c 1200 /dev/urandom | nc -u -w 1 -s $src $dst 9999 || true; done'"
  capture "beacon_burst_p$(printf '%02d' "$p")_R$(printf '%02d' "$n")" unknown "$p" anomaly beacon_burst "for i in \$(seq 1 30); do printf beacon | nc -u -w 1 -s $src $dst 9900 || true; sleep 1; done; timeout 15 sh -c 'while :; do head -c 900 /dev/urandom | nc -u -w 1 -s $src $dst 9900 || true; done'"
done
