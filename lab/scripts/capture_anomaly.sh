#!/usr/bin/env bash
# Capture one isolated anomaly sample.  A failed traffic or capture check never
# becomes a dataset file or metadata row.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TYPE="${1:?Usage: $0 TYPE PROFILE RUN [DURATION_SECONDS]}"
PROFILE="${2:?Usage: $0 TYPE PROFILE RUN [DURATION_SECONDS]}"
RUN="${3:?Usage: $0 TYPE PROFILE RUN [DURATION_SECONDS]}"
DURATION="${4:-30}"

case "$TYPE" in icmp_flood|udp_flood|beacon_burst) ;; *) echo 'TYPE must be icmp_flood, udp_flood, or beacon_burst' >&2; exit 2;; esac
case "$PROFILE" in 1|2|3|4|5) ;; *) echo 'PROFILE must be 1 through 5' >&2; exit 2;; esac
[[ "$RUN" =~ ^R0[1-5]$ ]] || { echo 'RUN must be R01 through R05' >&2; exit 2; }
[[ "$DURATION" =~ ^[1-9][0-9]*$ ]] || { echo 'DURATION_SECONDS must be a positive integer' >&2; exit 2; }

if [[ "$PROFILE" == 5 ]]; then
  src='fd10::1'; dst='fd20::1'; ping_cmd='ping -6'; nc_flags='-6'; outer='esp'
elif [[ "$PROFILE" == 4 ]]; then
  src='172.30.0.2'; dst='172.30.0.3'; ping_cmd='ping'; nc_flags=''; outer='udp4500'
else
  src='10.10.0.1'; dst='10.20.0.1'; ping_cmd='ping'; nc_flags=''; outer='esp'
  [[ "$PROFILE" == 2 ]] && outer='udp4500'
fi

DEST="$ROOT/pcaps/anomaly/${TYPE}_p$(printf '%02d' "$PROFILE")_${RUN}.pcap"
TMP="${DEST}.partial"
mkdir -p "$(dirname "$DEST")"
[[ ! -e "$DEST" ]] || { echo "Refusing to overwrite existing sample: $DEST" >&2; exit 3; }
rm -f "$TMP"

cap_pid=''
cleanup() {
  [[ -z "$cap_pid" ]] || sudo kill "$cap_pid" >/dev/null 2>&1 || true
  rm -f "$TMP"
}
trap cleanup EXIT INT TERM

"$ROOT/lab/scripts/apply_profile.sh" "$PROFILE" >/dev/null
if ! sudo docker exec ipsec-left sh -c "$ping_cmd -c 2 -W 3 -I '$src' '$dst'" >/dev/null; then
  echo "Tunnel preflight failed for P$(printf '%02d' "$PROFILE")." >&2
  sudo docker exec ipsec-left ipsec statusall >&2 || true
  exit 5
fi

ifindex=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink)
veth=$(ip -o link show | awk -F': ' -v i="$ifindex" '$1==i {split($2,a,"@"); print a[1]}')
[[ -n "$veth" ]] || { echo 'Could not determine the host veth for ipsec-left.' >&2; exit 4; }

case "$TYPE" in
  icmp_flood)
    traffic="timeout --signal=INT $DURATION $ping_cmd -i 0.02 -s 512 -I '$src' '$dst' >/dev/null || test \$? -eq 124"
    ;;
  udp_flood)
    traffic="timeout --signal=INT $DURATION sh -c 'while :; do dd if=/dev/urandom bs=1200 count=1 status=none | nc $nc_flags -u -w 1 -s \"$src\" \"$dst\" 9999; sleep 0.05; done' || test \$? -eq 124"
    ;;
  beacon_burst)
    burst=$(( DURATION > 10 ? DURATION - 10 : 1 ))
    traffic="for i in \$(seq 1 20); do printf beacon | nc $nc_flags -u -w 1 -s '$src' '$dst' 9900; sleep 0.5; done; timeout --signal=INT $burst sh -c 'while :; do dd if=/dev/urandom bs=900 count=1 status=none | nc $nc_flags -u -w 1 -s \"$src\" \"$dst\" 9900; sleep 0.05; done' || test \$? -eq 124"
    ;;
esac

sudo tcpdump -U -i "$veth" -s 0 -w "$TMP" "(ip or ip6) and (esp or udp port 4500)" >/tmp/ipsec-anomaly-tcpdump.log 2>&1 &
cap_pid=$!
sleep 1
sudo docker exec ipsec-left sh -c "$traffic"
sleep 1
sudo kill "$cap_pid" >/dev/null 2>&1 || true
wait "$cap_pid" >/dev/null 2>&1 || true
cap_pid=''

python3 "$ROOT/lab/scripts/pcap_info.py" "$TMP" --require-outer "$outer" >/dev/null
mv "$TMP" "$DEST"
trap - EXIT INT TERM
python3 "$ROOT/lab/scripts/record_capture.py" "$DEST" --label unknown --profile "$PROFILE" --run "$RUN" --role anomaly_eval --generator "$TYPE" --params "{\"duration_s\":$DURATION,\"isolated_lab\":true}" --anomaly "$TYPE"
echo "Captured $DEST"
