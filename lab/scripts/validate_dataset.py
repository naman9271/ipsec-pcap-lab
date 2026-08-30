#!/usr/bin/env python3
import csv, json, re, sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).parent)); from pcap_info import inspect
ROOT=Path(__file__).resolve().parents[2]; META=ROOT/'metadata.csv'; LABELS={'web','video','voip','email','file_transfer','messaging','icmp'}; ROLES={'train_known','ood_eval','anomaly_eval','protocol_validation'}
errors=[]
def bad(sample, rule, expected, observed): errors.append(f'{sample}: {rule}; expected {expected}; observed {observed}')
if not META.exists(): errors.append('metadata.csv: missing'); rows=[]
else:
 with META.open(newline='') as f: rows=list(csv.DictReader(f))
if not rows: errors.append('metadata.csv: no rows')
seen_ids=set(); seen_hash={}; listed=set()
for r in rows:
 sid=r.get('sample_id','<missing>'); listed.add(r.get('pcap_file',''))
 if not sid: bad('<row>','sample ID','non-empty','empty')
 elif sid in seen_ids: bad(sid,'duplicate sample ID','unique',sid)
 seen_ids.add(sid)
 path=ROOT/r.get('pcap_file','')
 if not path.is_file() or path.stat().st_size==0: bad(sid,'PCAP','existing non-empty file',r.get('pcap_file','missing')); continue
 try: info=inspect(path)
 except Exception as e: bad(sid,'PCAP parse','valid classic pcap',str(e)); continue
 if r.get('sha256') != info['sha256']: bad(sid,'SHA-256',info['sha256'],r.get('sha256',''))
 if info['sha256'] in seen_hash: bad(sid,'duplicate SHA-256','unique',f'{info["sha256"]} (also {seen_hash[info["sha256"]]})')
 seen_hash[info['sha256']]=sid
 for key, actual in [('packet_count',r.get('packet_count')),('captured_bytes',r.get('captured_bytes'))]:
  try:
   if int(actual)<=0: raise ValueError
  except ValueError: bad(sid,key,'positive integer',repr(actual))
 if r.get('packet_count') != str(info['packet_count']): bad(sid,'packet count',str(info['packet_count']),r.get('packet_count',''))
 try: json.loads(r.get('generator_parameters',''))
 except Exception as e: bad(sid,'generator JSON','valid JSON',str(e))
 role=r.get('dataset_role'); label=r.get('canonical_label')
 if role not in ROLES: bad(sid,'dataset role',sorted(ROLES),role)
 if role=='train_known' and label not in LABELS: bad(sid,'canonical label',sorted(LABELS),label)
 if role in ('ood_eval','protocol_validation') and label!='IGNORE': bad(sid,'non-training canonical label','IGNORE',label)
 if role=='anomaly_eval' and label not in LABELS|{'IGNORE'}: bad(sid,'anomaly canonical label','known label or IGNORE',label)
 if not re.fullmatch(r'P0[1-5]',r.get('profile_id','')): bad(sid,'profile ID','P01..P05',r.get('profile_id',''))
 if role=='train_known' and not re.fullmatch(r'R0[12]',r.get('run_id','')): bad(sid,'run ID','R01 or R02',r.get('run_id',''))
 profile=int(r['profile_id'][-1]); expected='UDP/4500 packet' if profile in (2,4) else 'ESP packet'; observed=info['udp4500_packets'] if profile in (2,4) else info['esp_packets']
 if observed==0: bad(sid,'IPsec outer protocol',expected,'none')
 if role in ('ood_eval','protocol_validation') and r.get('dataset_role')=='train_known': bad(sid,'OOD/protocol role','not train_known','train_known')
for p in ROOT.glob('pcaps/**/*.pcap'):
 if p.relative_to(ROOT).as_posix() not in listed: bad(p.name,'metadata','one metadata row','none')
if errors:
 print('Dataset validation failed:'); print('\n'.join('- '+e for e in errors)); sys.exit(1)
print('Dataset validation passed.')
