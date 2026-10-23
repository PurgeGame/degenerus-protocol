#!/usr/bin/env python3
"""Summarize measured receipts/replay and unmodified production sizes for one item."""
import argparse,collections,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True)
a=p.parse_args()
b=json.load(open(a.before/'abis.json'));c=json.load(open(a.after/'abis.json'))
rows=[];abis=[]
for name in json.load(open(a.after/'sizes.json')):
 if name=='CrapsViews':continue
 x=b[name];y=c[name]
 ptr=lambda z:hex(int(re.findall(r'memoryguard\((0x[0-9a-f]+|\d+)\)',z['irOptimized'])[-1],0))
 rows.append(dict(contract=name,beforeBytes=len(x['evm']['deployedBytecode']['object'])//2,afterBytes=len(y['evm']['deployedBytecode']['object'])//2,beforePointer=ptr(x),afterPointer=ptr(y)))
 old={json.dumps(v,sort_keys=True) for v in x['abi']};new={json.dumps(v,sort_keys=True) for v in y['abi']}
 assert old<=new,(name,'removed ABI')
 abis.append(dict(contract=name,allOldEntriesPreserved=True,added=len(new-old)))
(a.after/'sizes-pointers.json').write_text(json.dumps(rows,indent=2)+'\n');(a.after/'abi-preserved.json').write_text(json.dumps(abis,indent=2)+'\n')
if (a.after/'replay-diff.json').exists():
 rows=[]
 for r in json.load(open(a.after/'replay-diff.json'))['runs']:
  for payer in ['player','protocol']:
   row={'scenario':r['test'],'payer':payer}
   for side in ['baseline','candidate']:
    matches=[v for v in r[side+'Gas'].values() if v['payer']==payer]
    row[side+'Calls']=sum(v['count'] for v in matches);row[side+'Gas']=sum(v['gas'] for v in matches)
   rows.append(row)
 (a.after/'foundry-gas.json').write_text(json.dumps({'rows':rows},indent=2)+'\n')
 for r in rows:
  if r['scenario']=='testLongRunCensus':print(json.dumps(r))
if (a.after/'native/paired.json').exists():
 pairs=json.load(open(a.after/'native/paired.json'));out={}
 for profile in pairs['profiles']:
  labels=collections.defaultdict(list);payers=collections.defaultdict(lambda:{'calls':0,'before':0,'after':0})
  for r in pairs['samples']:
   z=r['profiles'][profile];assert z['covered'] and z['effectsEqual']
   labels[r['label']].append(z['saving']);t=payers[r['payer']];t['calls']+=1
   for side in ['before','after']:t[side]+=z[side]['gas']
  out[profile]={'payers':dict(payers),'labels':{k:{'samples':len(v),'minSaving':min(v),'meanSaving':sum(v)/len(v),'maxSaving':max(v)} for k,v in labels.items()}}
 (a.after/'native-summary.json').write_text(json.dumps(out,indent=2)+'\n')
 print(json.dumps({k:v['payers'] for k,v in out.items()}))
