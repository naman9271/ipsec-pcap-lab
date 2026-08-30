# IPsec PCAP dataset

This repository is an isolated Docker/strongSwan capture lab. It collects Ethernet classic-PCAP files on the host-side veth of `ipsec-left`, so the application traffic is protected by native ESP or UDP/4500 encapsulated ESP. It is not a source of external-network traffic.

## Current provenance and completion gate

The checked-in snapshot contains 82 preserved PCAPs. Before its path-only reorganization, SHA-256 was calculated for every file; the move was verified with zero missing or changed hashes. Twenty original captures are additionally protected by `lab/original-20.sha256`; use `python3 lab/scripts/verify_protected_hashes.py` after any maintenance.

The dataset is **not v1.0 until** `python3 lab/scripts/validate_dataset.py` passes. The validator deliberately rejects an incomplete matrix; it never reports a placeholder corpus as valid. Once it passes, `python3 lab/scripts/freeze_manifest.py` creates `dataset-manifest-v1.0.csv`.

## Layout and labels

`pcaps/known/{web,video,voip,email,file_transfer,messaging,icmp}` holds the seven canonical classes. `file` maps to `file_transfer`, and `ping` maps to `icmp`. `pcaps/ood`, `pcaps/anomaly`, and `pcaps/protocol_validation` are kept separate. If an imported historical archive is present at `pcaps/anomaly/archive`, it is retained as `archived_provenance` and excluded from final anomaly counts.

Known runs use R01–R05: R01–R03 are `train`, R04 is `validation`, and R05 is `locked_test`. New captures use independent generator invocations and a generated seed in `generator_parameters`.

P01 is IKEv2 / native IPv4 ESP, P02 IKEv2 / forced UDP/4500, P03 IKEv1 / native IPv4 ESP, P04 IKEv1 transport / forced UDP/4500, and P05 IKEv2 / native IPv6 ESP. P02/P04 set `udp_encapsulation_forced=yes` and `actual_nat_present=no`: forced encapsulation is not real NAT traversal.

## Reproduction

Requirements are Linux, passwordless-or-interactive `sudo` access to Docker, Docker Compose, `tcpdump`, Python 3, and sufficient disk/time for the capture matrix. Start with:

```bash
./lab/scripts/run_all.sh
```

It never overwrites an existing `.pcap`; interrupted `.partial` files are discarded. `capture_one.sh` supports all known classes, profiles 1–5, and R01–R05. It randomizes web object count, video segment count/rate, file size/rate, ICMP payload/count, SMTP message count, WebSocket message count, and RTP duration separately from the IPsec profile. Capture filters are `esp or udp port 4500` (with the required IP family in known capture calls).

The final target is 175 known captures (7 × 5 × 5), 25 OOD captures (DNS, SSH, gaming UDP, database, remote desktop × P01–P05), and 30 final anomalies (10 each of ICMP flood, UDP flood, beacon burst, 30–90 seconds each). Protocol validation records one negotiation-first session per profile and verifies IKEv1/IKEv2, PSK authentication, native ESP, UDP/4500 forced encapsulation, and IPv4/IPv6 coverage. This topology does not claim real NAT traversal, certificate authentication, or rekey/replay testing.

## Metadata

`metadata.csv` is migrated in place by `lab/scripts/migrate_metadata.py`. It keeps legacy `pcap_file` for compatibility and adds authoritative `pcap_path`, packet-derived start/end timestamps, `pcap_file_size_bytes`, and `captured_frame_bytes`. Container bytes are not presented as traffic bytes. `generator_parameters` is JSON; hashes, counts, frame bytes, duration, timestamps, and link type are derived from PCAP contents.

The strict validator checks paths, hashes, duplicates, packet statistics, JSON, labels, roles, profile/run IDs, outer ESP/UDP4500 semantics, matrix completeness, anomaly/OOD counts, protocol facts, and required fields. It exits non-zero on any failure.

## Limitations and use

Classic Ethernet PCAP is the only capture format used; AH and PCAPNG are intentionally not added. Some normal historical captures show slightly out-of-order ESP packets and must not be repurposed as replay-protection proof. The data is synthetic, lab-only, and intended for research/validation; do not use the included PSK or weak profile outside the lab.
