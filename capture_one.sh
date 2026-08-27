#!/usr/bin/env bash
set -euo pipefail

CLASS="${1:?Usage: ./capture_one.sh CLASS PROFILE}"
PROFILE="${2:?Usage: ./capture_one.sh CLASS PROFILE}"

LAB="$HOME/ipsec-pcap-lab"
PCAPDIR="$LAB/pcaps"
METADATA="$LAB/metadata.csv"

case "$CLASS" in
    web|video|file|ping) ;;
    *)
        echo "CLASS must be web, video, file or ping"
        exit 1
        ;;
esac

case "$PROFILE" in
1)
    MODE="tunnel"
    IKE="IKEv2"
    IKE_PROP="aes128-sha256-modp2048"
    ESP_PROP="aes128-sha256"
    CIPHER="AES-128-CBC"
    INTEGRITY="HMAC-SHA256"
    DH="14-MODP2048"
    PFS="off"
    IPVER="IPv4"
    NATT="off"
    NATT_FORCED="no"
    OUTER_LEFT="172.30.0.2"
    OUTER_RIGHT="172.30.0.3"
    SRC="10.10.0.1"
    DST="10.20.0.1"
    BASE="http://10.20.0.1:8080"
    CURL_FLAGS=""
    ;;

2)
    MODE="tunnel"
    IKE="IKEv2"
    IKE_PROP="aes256gcm16-prfsha256-ecp256"
    ESP_PROP="aes256gcm16"
    CIPHER="AES-256-GCM-16"
    INTEGRITY="AEAD-GCM-128-bit-ICV"
    DH="19-ECP256"
    PFS="off"
    IPVER="IPv4"
    NATT="on"
    NATT_FORCED="yes"
    OUTER_LEFT="172.30.0.2"
    OUTER_RIGHT="172.30.0.3"
    SRC="10.10.0.1"
    DST="10.20.0.1"
    BASE="http://10.20.0.1:8080"
    CURL_FLAGS=""
    ;;

3)
    MODE="tunnel"
    IKE="IKEv1"
    IKE_PROP="aes256-sha256-modp2048"
    ESP_PROP="aes256-sha256-modp2048"
    CIPHER="AES-256-CBC"
    INTEGRITY="HMAC-SHA256"
    DH="14-MODP2048"
    PFS="on"
    IPVER="IPv4"
    NATT="off"
    NATT_FORCED="no"
    OUTER_LEFT="172.30.0.2"
    OUTER_RIGHT="172.30.0.3"
    SRC="10.10.0.1"
    DST="10.20.0.1"
    BASE="http://10.20.0.1:8080"
    CURL_FLAGS=""
    ;;

4)
    MODE="transport"
    IKE="IKEv1"
    IKE_PROP="aes128-sha256-modp3072"
    ESP_PROP="aes128-sha256-modp3072"
    CIPHER="AES-128-CBC"
    INTEGRITY="HMAC-SHA256"
    DH="15-MODP3072"
    PFS="on"
    IPVER="IPv4"
    NATT="on"
    NATT_FORCED="yes"
    OUTER_LEFT="172.30.0.2"
    OUTER_RIGHT="172.30.0.3"
    SRC="172.30.0.2"
    DST="172.30.0.3"
    BASE="http://172.30.0.3:8080"
    CURL_FLAGS=""
    ;;

5)
    MODE="tunnel"
    IKE="IKEv2"
    IKE_PROP="aes256-sha384-ecp384"
    ESP_PROP="aes256-sha384"
    CIPHER="AES-256-CBC"
    INTEGRITY="HMAC-SHA384"
    DH="20-ECP384"
    PFS="off"
    IPVER="IPv6"
    NATT="off"
    NATT_FORCED="no"
    OUTER_LEFT="fd00:30::2"
    OUTER_RIGHT="fd00:30::3"
    SRC="fd10::1"
    DST="fd20::1"
    BASE="http://[fd20::1]:8081"
    CURL_FLAGS="-6 -g"
    ;;

*)
    echo "PROFILE must be 1-5"
    exit 1
    ;;
esac

echo
echo "=========================================="
echo "CLASS   : $CLASS"
echo "PROFILE : P$PROFILE"
echo "MODE    : $MODE"
echo "IKE     : $IKE"
echo "IP      : $IPVER"
echo "NAT-T   : $NATT"
echo "=========================================="
echo

"$LAB/apply_profile.sh" "$PROFILE"

LEFT_IFINDEX=$(sudo docker exec ipsec-left cat /sys/class/net/eth0/iflink)

VETH=$(ip -o link show |
    awk -F': ' -v i="$LEFT_IFINDEX" \
    '$1==i {split($2,a,"@"); print a[1]}')

if [[ -z "$VETH" ]]; then
    echo "Could not determine host-side veth"
    exit 1
fi

SAMPLE=$(printf "%s_p%02d" "$CLASS" "$PROFILE")
OUT="$PCAPDIR/${SAMPLE}.pcap"

if [[ -e "$OUT" ]]; then
    echo "PCAP already exists: $OUT"
    echo "Delete or rename it before repeating this sample."
    exit 1
fi

case "$CLASS" in

web)
    DURATION=35
    GENERATOR="multiple-http-object-requests"

    TRAFFIC_CMD='
    for r in 1 2 3 4 5 6; do
        curl -sS $CURL_FLAGS --interface "$SRC" "$BASE/web/index.html" -o /dev/null
        curl -sS $CURL_FLAGS --interface "$SRC" "$BASE/web/style.css" -o /dev/null
        curl -sS $CURL_FLAGS --interface "$SRC" "$BASE/web/app.js" -o /dev/null
        curl -sS $CURL_FLAGS --interface "$SRC" "$BASE/web/image1.bin" -o /dev/null
        curl -sS $CURL_FLAGS --interface "$SRC" "$BASE/web/image2.bin" -o /dev/null
        sleep $(( (r + PROFILE) % 3 + 1 ))
    done
    '
    ;;

video)
    DURATION=60
    GENERATOR="hls-segment-streaming"

    case "$PROFILE" in
        1) RATE="700K"; PAUSE="3.0" ;;
        2) RATE="900K"; PAUSE="2.8" ;;
        3) RATE="1100K"; PAUSE="3.2" ;;
        4) RATE="800K"; PAUSE="3.4" ;;
        5) RATE="1000K"; PAUSE="3.0" ;;
    esac

    TRAFFIC_CMD='
    curl -sS $CURL_FLAGS --interface "$SRC" \
        "$BASE/hls/stream.m3u8" -o /dev/null

    for i in $(seq 0 14); do
        SEG=$(printf "%03d" "$i")
        curl -sS $CURL_FLAGS \
            --interface "$SRC" \
            --limit-rate "$RATE" \
            "$BASE/hls/seg${SEG}.ts" \
            -o /dev/null
        sleep "$PAUSE"
    done
    '
    ;;

file)
    GENERATOR="bulk-http-file-download"

    case "$PROFILE" in
        1)
            FILE="file8M.bin"
            RATE="800K"
            DURATION=15
            ;;
        2)
            FILE="file16M.bin"
            RATE="1M"
            DURATION=22
            ;;
        3)
            FILE="file24M.bin"
            RATE="1200K"
            DURATION=27
            ;;
        4)
            FILE="file32M.bin"
            RATE="1M"
            DURATION=38
            ;;
        5)
            FILE="file48M.bin"
            RATE="1500K"
            DURATION=40
            ;;
    esac

    TRAFFIC_CMD='
    curl -sS $CURL_FLAGS \
        --interface "$SRC" \
        --limit-rate "$RATE" \
        "$BASE/files/$FILE" \
        -o /dev/null
    '
    ;;

ping)
    GENERATOR="icmp-echo"

    case "$PROFILE" in
        1) COUNT=40;  INTERVAL=0.50; DURATION=25 ;;
        2) COUNT=60;  INTERVAL=0.40; DURATION=30 ;;
        3) COUNT=80;  INTERVAL=0.30; DURATION=30 ;;
        4) COUNT=50;  INTERVAL=0.60; DURATION=35 ;;
        5) COUNT=100; INTERVAL=0.20; DURATION=25 ;;
    esac

    if [[ "$IPVER" == "IPv6" ]]; then
        TRAFFIC_CMD='
        ping -6 -I "$SRC" -c "$COUNT" -i "$INTERVAL" "$DST"
        '
    else
        TRAFFIC_CMD='
        ping -4 -I "$SRC" -c "$COUNT" -i "$INTERVAL" "$DST"
        '
    fi
    ;;
esac

echo "Host capture interface: $VETH"
echo "Output: $OUT"
echo

FILTER="host $OUTER_LEFT and host $OUTER_RIGHT"

sudo timeout -s INT "${DURATION}s" \
    tcpdump \
    -i "$VETH" \
    -nn \
    -s 0 \
    -U \
    -w "$OUT" \
    "$FILTER" \
    >"$LAB/logs/${SAMPLE}_tcpdump.log" 2>&1 &

CAP_PID=$!

sleep 1

sudo docker exec \
    -e SRC="$SRC" \
    -e DST="$DST" \
    -e BASE="$BASE" \
    -e CURL_FLAGS="$CURL_FLAGS" \
    -e PROFILE="$PROFILE" \
    -e RATE="${RATE:-}" \
    -e PAUSE="${PAUSE:-}" \
    -e FILE="${FILE:-}" \
    -e COUNT="${COUNT:-}" \
    -e INTERVAL="${INTERVAL:-}" \
    ipsec-left \
    bash -c "$TRAFFIC_CMD"

wait "$CAP_PID" || true

sudo chown "$USER:$USER" "$OUT"

SHA256=$(sha256sum "$OUT" | awk "{print \$1}")

if [[ ! -f "$METADATA" ]]; then
    echo "sample_id,pcap_file,traffic_class,mode,ike_version,ike_proposal,esp_proposal,cipher,integrity,dh_group,pfs,ip_version,nat_t,nat_t_forced,actual_nat_present,peer_auth,capture_duration_s,outer_left,outer_right,traffic_generator,sha256" \
        > "$METADATA"
fi

echo "$SAMPLE,$(basename "$OUT"),$CLASS,$MODE,$IKE,$IKE_PROP,$ESP_PROP,$CIPHER,$INTEGRITY,$DH,$PFS,$IPVER,$NATT,$NATT_FORCED,no,PSK,$DURATION,$OUTER_LEFT,$OUTER_RIGHT,$GENERATOR,$SHA256" \
    >> "$METADATA"

echo
echo "Created: $OUT"
echo "Metadata appended to: $METADATA"
echo "SHA256: $SHA256"
