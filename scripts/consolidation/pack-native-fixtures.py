#!/usr/bin/env python3
"""Pack NativeGasExport fixtures for exact-runtime native paired replay.

Only exported storage is supplied; the native verifier rejects uncovered reads.
"""
import argparse, gzip, hashlib, json
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('fixtures',type=Path);p.add_argument('out',type=Path);p.add_argument('--pattern',default='*.call.json')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
codes={};hashes={};paths=sorted(a.fixtures.glob(a.pattern));assert paths
with gzip.open(a.out/'calls.jsonl.gz','wt') as output:
 for seq,path in enumerate(paths,1):
  call=json.loads(path.read_text());sp=path.with_name(path.name.replace('.call.json','.state.json'));state=json.loads(sp.read_text());converted={}
  for address,account in state.items():
   address=address.lower();code=account['code'].lower();assert address not in codes or codes[address]==code
   codes[address]=code
   converted[address]={'balance':hex(int(account['balance'],16)),'nonce':hex(account['nonce']),
    'state':{k.lower():v.lower() for k,v in account['storage'].items()}}
  row={'seq':seq,'label':path.name.removesuffix('.call.json'),'payer':'player','success':None,
   'number':call['number'],'timestamp':call['timestamp'],'from_':call['from'].lower(),'to':call['to'].lower(),
   'data':call['input'],'value':'0x0','state':converted}
  output.write(json.dumps(row,separators=(',',':'))+'\n')
  for f in (path,sp):hashes[f.name]=hashlib.sha256(f.read_bytes()).hexdigest()
(a.out/'codes.json').write_text(json.dumps(codes)+'\n')
(a.out/'provenance.json').write_text(json.dumps({'method':__doc__,'samples':len(paths),'sha256':hashes},indent=2)+'\n')
print(json.dumps({'samples':len(paths),'accounts':len(codes)}))
