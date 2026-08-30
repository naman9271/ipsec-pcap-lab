# IPsec PCAP lab dataset

This repository is a reproducible, two-container strongSwan lab for collecting **outer-side encrypted IPsec PCAPs**. It preserves the 20 original captures in `pcaps/` exactly as supplied and extends them with independently generated samples. PCAPs are not decoded or modified after capture.

## One-command dataset run

Run this on a Linux host with Docker Compose, `sudo`, `tcpdump`, Python 3, and sufficient disk space. The first run builds the lab image and takes time because it generates actual traffic; it never substitutes placeholders.

```bash
./lab/scripts/run_all.sh
```

The script migrates metadata, starts the lab, captures missing known/evaluation/protocol samples, validates the dataset, then verifies `lab/original-20.sha256`. It refuses to overwrite a PCAP. If interrupted, rerun it; completed captures are skipped. Stop the containers afterward with `./lab/scripts/stop_lab.sh`.

## Topology and profiles

`ipsec-left` and `ipsec-right` are privileged containers on Docker network `ipsec_outer`. Outer endpoints are `172.30.0.2/172.30.0.3` and `fd00:30::2/fd00:30::3`; tunnel selectors are `10.10.0.1 -> 10.20.0.1` and `fd10::1 -> fd20::1`. Captures run on the host-side veth for `ipsec-left`, so they contain outer ESP or UDP/4500 rather than cleartext application payloads.

| Profile | IKE | mode/IP | outer protection |
|---|---|---|---|
| P01 | IKEv2 | tunnel IPv4 | native ESP |
| P02 | IKEv2 | tunnel IPv4 | forced UDP/4500 encapsulation |
| P03 | IKEv1 | tunnel IPv4 | native ESP |
| P04 | IKEv1 | transport IPv4 | forced UDP/4500 encapsulation |
| P05 | IKEv2 | tunnel IPv6 | native ESP |

`forceencaps=yes` is forced encapsulation, not evidence of a real NAT. Metadata records `actual_nat_present=no`; an optional NAT-router topology is deliberately not claimed.

`lab/configs/` is the authoritative configuration directory. The profile can be activated manually with `./lab/scripts/apply_profile.sh 1`; start/status/stop are in `lab/scripts/`.

## Dataset layout and labels

Known training labels are `web`, `video`, `voip`, `email`, `file_transfer`, `messaging`, and `icmp`. Legacy `file` and `ping` map to `file_transfer` and `icmp` in metadata. New samples live below `pcaps/known/<label>/` and use `<class>_p<profile>_r<run>.pcap`; the legacy capture filenames remain intact to protect their provenance.

Each known class/profile has R01 and R02. Repetitions are separate generator invocations with a fresh seed. Web objects, HLS segments/rate, file size/rate, ICMP count/payload, SMTP messages/attachments, WebSocket messages, and RTP duration vary independently from the profile. SMTP uses a local `aiosmtpd` server; messaging is bidirectional WebSockets; VoIP is bidirectional ffmpeg RTP audio.

`pcaps/ood/` holds DNS-like UDP, interactive terminal-like TCP, and gaming-like UDP evaluation flows. These rows use `dataset_role=ood_eval` and `canonical_label=IGNORE`. `pcaps/anomaly/` separately contains isolated ICMP/UDP flood and beacon-then-burst captures, marked `anomaly_eval` with `is_anomaly=true`. `pcaps/protocol_validation/` contains negotiation-first IKE/ESP sessions for each profile, excluded from classifier training.

## Metadata and validation

`metadata.csv` retains all original columns and adds canonical/original labels, role, profile/run, actual capture timestamp, duration/span, packet/byte counts, interface/link type, JSON generator parameters, versions, SHA-256, and anomaly fields. The migration derives factual PCAP statistics and hashes; fields unavailable for historical captures are explicitly noted rather than invented.

Validate at any time:

```bash
python3 lab/scripts/validate_dataset.py
```

It detects empty/missing captures, file/metadata disagreement, duplicate identifiers or hashes, invalid JSON/labels/roles/profile/runs, hash/stat mismatches, and whether native profiles have ESP / encapsulated profiles have UDP/4500.

## Git LFS and safe cleanup

`.gitattributes` marks future `*.pcap` files for Git LFS. Install Git LFS on the host, then run `git lfs install`; do not rewrite existing history. `./lab/scripts/stop_lab.sh` removes only this lab's containers/network. It never removes PCAPs, metadata, logs, or `lab-data/`.
