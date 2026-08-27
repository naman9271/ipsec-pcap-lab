# Reproducible single-machine strongSwan IPsec lab

This bundle recreates the two-container strongSwan testbed used for encrypted/outer-side PCAP collection.

## What it creates

- `ipsec-left`: outer IPv4 `172.30.0.2`, outer IPv6 `fd00:30::2`, inner IPv4 `10.10.0.1`, inner IPv6 `fd10::1`
- `ipsec-right`: outer IPv4 `172.30.0.3`, outer IPv6 `fd00:30::3`, inner IPv4 `10.20.0.1`, inner IPv6 `fd20::1`
- Docker bridge network `ipsec_outer`
- strongSwan, curl, Python, ping, ffmpeg and networking tools inside both containers
- Controlled web/file/HLS content on the right endpoint
- Five strongSwan profiles under `configs/`

## First-time migration from your old manually created containers

If your old `ipsec-left` and `ipsec-right` are still running, remove only those lab containers/network first:

```bash
sudo docker rm -f ipsec-left ipsec-right 2>/dev/null || true
sudo docker network rm ipsec_outer 2>/dev/null || true
```

Do **not** delete your `pcaps/` or `metadata.csv`.

## Start/recreate the lab

```bash
cd ~/Desktop/ipsec-pcap-lab
./scripts/start-lab.sh
```

On the first build/start, the right endpoint creates the controlled test data under `./lab-data/`; later starts reuse it.

## Activate a VPN profile

Example:

```bash
./scripts/apply_profile.sh 1
```

Profiles 1 through 5 correspond to the original experiment matrix.

## Check status

```bash
./scripts/status-lab.sh
```

or:

```bash
sudo docker compose ps
```

## Stop the lab cleanly

```bash
./scripts/stop-lab.sh
```

Equivalent command:

```bash
sudo docker compose down --remove-orphans
```

This stops/removes **only this lab's containers and network**. Your PCAPs, metadata, configs and `lab-data/` remain on disk.

## Recreate from scratch later

```bash
./scripts/reset-lab.sh
./scripts/start-lab.sh
./scripts/apply_profile.sh 1
```

`reset-lab.sh` removes old lab containers/network but intentionally keeps `lab-data/`.

## Stop Docker itself (optional)

Usually you should **not** do this. `docker compose down` is enough.

If you truly want Docker completely stopped on the Ubuntu machine:

```bash
sudo systemctl stop docker.service docker.socket containerd.service
```

That affects every Docker project on the computer, not just this lab.

Start Docker again with:

```bash
sudo systemctl start containerd.service docker.service
```

## Preserve your existing dataset

Keep these outside disposable container state:

- `pcaps/`
- `metadata.csv`
- `logs/`
- `configs/`
- any capture scripts you already use

The Compose setup does not delete these.
