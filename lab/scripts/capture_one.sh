#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLASS="${1:?Usage: $0 CLASS PROFILE RUN}"; PROFILE="${2:?}"; RUN="${3:?Run must be R01/R02}"
case "$CLASS" in web|video|file_transfer|icmp|email|messaging|voip) ;; *) echo 'Invalid known class' >&2; exit 2;; esac
[[ "$PROFILE" =~ ^[1-5]$ && "$RUN" =~ ^R0[12]$ ]] || { echo 'profile 1-5 and run R01/R02 required' >&2; exit 2; }
DEST="$ROOT/pcaps/known/$CLASS/${CLASS}_p$(printf '%02d' "$PROFILE")_${RUN}.pcap"; mkdir -p "$(dirname "$DEST")"
[[ ! -e "$DEST" ]] || { echo "Refusing to overwrite $DEST" >&2; exit 3; }
seed=$((10#$PROFILE * 100 + 10#${RUN#R} + $(date +%s) % 100000)); duration=45; generator=''; remote_start=''
case "$PROFILE" in
  5) src=fd10::1; dst=fd20::1; outer_filter='ip6'; base='http://[fd20::1]:8081' ;;
  4) src=172.30.0.2; dst=172.30.0.3; outer_filter='ip'; base='http://172.30.0.3:8080' ;;
  *) src=10.10.0.1; dst=10.20.0.1; outer_filter='ip'; base='http://10.20.0.1:8080' ;;
esac
case "$CLASS" in
 web) generator=multiple-http-object-requests; objects=$((4+seed%8)); duration=$((25+seed%20)); traffic="for i in \$(seq 1 $objects); do curl -fsS --connect-timeout 8 --max-time 60 --interface '$src' '$base/web/index.html' -o /dev/null; sleep 0.$((seed%7+1)); done";;
 video) generator=hls-segment-streaming; segments=$((8+seed%8)); rate="$((600+seed%700))K"; duration=$((35+seed%20)); traffic="curl -fsS --connect-timeout 8 --max-time 30 --interface '$src' '$base/hls/stream.m3u8' -o /dev/null; for i in \$(seq 0 $((segments-1))); do seg=\$(printf '%03d' \"\$i\"); curl -fsS --connect-timeout 8 --max-time 60 --interface '$src' --limit-rate $rate '$base/hls/seg'\$seg.ts -o /dev/null; sleep 1; done";;
 file_transfer) generator=bulk-http-file-download; size=$((8+(seed%4)*8)); duration=$((20+seed%20)); traffic="curl -fsS --connect-timeout 8 --max-time 180 --interface '$src' --limit-rate $((500+seed%1000))K '$base/files/file${size}M.bin' -o /dev/null";;
 icmp) generator=randomized-icmp-echo; count=$((30+seed%100)); duration=$((15+seed%20)); traffic="ping $([[ $PROFILE == 5 ]] && echo -6) -I '$src' -c $count -i 0.15 -s $((32+seed%1200)) '$dst' >/dev/null";;
 email) generator=smtp-message-transfer; count=$((20+seed%31)); duration=45; smtp_listen="$dst:2525"; [[ "$PROFILE" == 5 ]] && smtp_listen="[$dst]:2525"; remote_start="exec python3 -m aiosmtpd -n -l '$smtp_listen'"; traffic="python3 /lab/generators/smtp_send.py '$dst' --count $count --seed $seed";;
 messaging) generator=bidirectional-websocket-chat; count=$((100+seed%201)); duration=50; remote_start="exec python3 /lab/generators/chat.py server --host '$dst'"; traffic="python3 /lab/generators/chat.py client --host '$dst' --count $count --seed $seed";;
 voip) generator=rtp-audio-call; duration=$((30+seed%31)); remote_start="exec ffmpeg -hide_banner -loglevel error -re -f lavfi -i sine=frequency=700:sample_rate=8000 -t $duration -ac 1 -ar 8000 -c:a pcm_mulaw -f rtp rtp://$src:5006"; traffic="ffmpeg -hide_banner -loglevel error -re -f lavfi -i sine=frequency=900:sample_rate=8000 -t $duration -ac 1 -ar 8000 -c:a pcm_mulaw -f rtp rtp://$dst:5004";;
esac
cleanup(){ [[ -n "${cap_pid:-}" ]] && sudo kill "$cap_pid" >/dev/null 2>&1 || true; sudo docker exec ipsec-right pkill -f 'aiosmtpd|chat.py|ffmpeg.*rtp' >/dev/null 2>&1 || true; }
trap cleanup EXIT INT TERM
"$ROOT/lab/scripts/apply_profile.sh" "$PROFILE" >/dev/null
if [[ "$PROFILE" == 5 ]]; then ping_check='ping -6 -c 2 -W 3 -I fd10::1 fd20::1'; elif [[ "$PROFILE" == 4 ]]; then ping_check='ping -c 2 -W 3 -I 172.30.0.2 172.30.0.3'; else ping_check='ping -c 2 -W 3 -I 10.10.0.1 10.20.0.1'; fi
if ! sudo docker exec ipsec-left sh -c "$ping_check" >/dev/null; then
  echo "Tunnel preflight failed for P$(printf '%02d' "$PROFILE")." >&2
  sudo docker exec ipsec-left ipsec statusall >&2 || true
  exit 5
fi
if [[ -n "$remote_start" ]]; then
  sudo docker exec -d ipsec-right sh -c "$remote_start" >/dev/null
  sleep 1
fi
ifindex=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink); veth=$(ip -o link show | awk -F': ' -v i="$ifindex" '$1==i {split($2,a,"@");print a[1]}'); [[ -n "$veth" ]] || { echo 'host veth unavailable' >&2; exit 4; }
sudo tcpdump -U -i "$veth" -s 0 -w "$DEST" "$outer_filter and (esp or udp port 4500)" >/tmp/ipsec-tcpdump.log 2>&1 & cap_pid=$!; sleep 1
sudo docker exec ipsec-left sh -c "$traffic"; sleep 1; cleanup; cap_pid=''
case "$CLASS" in
  web) params=$(printf '{"duration_s":%s,"object_count":%s,"seed":%s}' "$duration" "$objects" "$seed");;
  video) params=$(printf '{"duration_s":%s,"segment_count":%s,"rate":"%s","seed":%s}' "$duration" "$segments" "$rate" "$seed");;
  file_transfer) params=$(printf '{"duration_s":%s,"file_size_mib":%s,"rate_kib_s":%s,"seed":%s}' "$duration" "$size" "$((500+seed%1000))" "$seed");;
  icmp) params=$(printf '{"duration_s":%s,"packet_count":%s,"payload_bytes":%s,"seed":%s}' "$duration" "$count" "$((32+seed%1200))" "$seed");;
  email) params=$(printf '{"duration_s":%s,"message_count":%s,"seed":%s}' "$duration" "$count" "$seed");;
  messaging) params=$(printf '{"duration_s":%s,"message_count":%s,"seed":%s}' "$duration" "$count" "$seed");;
  voip) params=$(printf '{"duration_s":%s,"codec":"pcm_mulaw","sample_rate_hz":8000,"packetization":"rtp","seed":%s}' "$duration" "$seed");;
esac
python3 "$ROOT/lab/scripts/record_capture.py" "$DEST" --label "$CLASS" --profile "$PROFILE" --run "$RUN" --generator "$generator" --params "$params"
echo "Captured $DEST"
