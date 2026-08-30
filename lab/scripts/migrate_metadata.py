#!/usr/bin/env python3
"""Upgrade legacy rows in place without touching any protected capture."""
import csv, datetime as dt, json, platform, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent)); from pcap_info import inspect
FIELDS=['sample_id','pcap_file','traffic_class','mode','ike_version','ike_proposal','esp_proposal','cipher','integrity','dh_group','pfs','ip_version','nat_t','nat_t_forced','actual_nat_present','peer_auth','capture_duration_s','outer_left','outer_right','traffic_generator','sha256','original_label','canonical_label','dataset_role','profile_id','run_id','capture_timestamp_utc','configured_capture_duration_s','observed_packet_span_s','packet_count','captured_bytes','capture_interface','link_type','generator_parameters','strongswan_version','kernel_version','tcpdump_version','is_anomaly','anomaly_type']
root=Path(__file__).resolve().parents[2]; meta=root/'metadata.csv'
with meta.open(newline='') as f: old=list(csv.DictReader(f))
out=[]
for r in old:
 name=r.get('pcap_file',''); path=root/'pcaps'/name if not name.startswith('pcaps/') else root/name
 if not path.exists(): raise SystemExit(f'legacy metadata references missing file: {name}')
 i=inspect(path); label={'file':'file_transfer','ping':'icmp'}.get(r.get('traffic_class'),r.get('traffic_class'))
 n={k:r.get(k,'') for k in FIELDS}; n.update(pcap_file=path.relative_to(root).as_posix(), original_label=r.get('traffic_class',''), canonical_label=label, traffic_class=label, dataset_role='train_known', profile_id='P'+r['sample_id'].split('_p')[-1], run_id='R01', capture_timestamp_utc=dt.datetime.fromtimestamp(path.stat().st_mtime,dt.timezone.utc).isoformat(), configured_capture_duration_s=r.get('capture_duration_s',''), observed_packet_span_s=str(i['observed_packet_span_s']), packet_count=str(i['packet_count']), captured_bytes=str(i['captured_bytes']), capture_interface='legacy-host-veth', link_type=str(i['link_type']), generator_parameters=json.dumps({'legacy_capture':True,'documented_generator':r.get('traffic_generator','')},sort_keys=True), sha256=i['sha256'], strongswan_version='not recorded for legacy capture', kernel_version='not recorded for legacy capture', tcpdump_version='not recorded for legacy capture', is_anomaly='false', anomaly_type='none')
 out.append(n)
with meta.open('w',newline='') as f: w=csv.DictWriter(f,FIELDS,lineterminator='\n'); w.writeheader(); w.writerows(out)
print(f'Migrated {len(out)} metadata rows; PCAP bytes were not modified.')
