#!/usr/bin/env python3
"""Check generated dispatcher entries and preservation of the preceding public ABIs."""
import argparse,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before',type=Path,required=True);p.add_argument('--after',type=Path,required=True)
p.add_argument('--manifest',type=Path,required=True);p.add_argument('--report',type=Path,required=True)
p.add_argument('--additional-abi',type=Path,help='Exact separately reviewed ABI entries, keyed by production contract')
a=p.parse_args();extra=json.load(open(a.additional_abi)) if a.additional_abi else {};before=json.load(open(a.before/'abis.json'));after=json.load(open(a.after/'abis.json'))
source=json.load(open(a.after/'input.json'))['sources'];output=json.load(open(a.after/'output.json'));manifest=json.load(open(a.manifest));byalias={r['alias']:r for r in manifest['aliases']}
def nodes(n):
 if isinstance(n,dict):
  yield n
  for v in n.values():yield from nodes(v)
 elif isinstance(n,list):
  for v in n:yield from nodes(v)
def content(path,n):
 s,l,_=map(int,n['src'].split(':'));return source[path]['content'].encode()[s:s+l].decode()
def compact(s):return re.sub(r'\s+','',s)
checked=[]
for filename,unit in output['sources'].items():
 if filename not in source:continue
 for contract in [n for n in nodes(unit['ast']) if n.get('nodeType')=='ContractDefinition']:
  funcs={n['name']:n for n in contract['nodes'] if n.get('nodeType')=='FunctionDefinition' and n.get('name')}
  for alias,node in funcs.items():
   if alias not in byalias:continue
   row=byalias[alias];original=next(n for n in contract['nodes'] if n.get('nodeType')=='FunctionDefinition' and n.get('functionSelector')==row['selector'])
   assert node['functionSelector']==row['aliasSelector'],alias
   assert node['stateMutability']==original['stateMutability'],alias
   for field in ['parameters','returnParameters']:
    assert [n['typeDescriptions']['typeIdentifier'] for n in node[field]['parameters']]==[n['typeDescriptions']['typeIdentifier'] for n in original[field]['parameters']],(alias,field)
   if node.get('body'):
    body=content(filename,node['body'])
    if original['name']=='runJackpotTicketAwards':
     assert body==content(filename,original['body']),'Duplicated checkpoint bodies drifted'
     assert 'msg.data' not in body and 'msg.sig' not in body
     method='identical external checkpoint body'
    else:
     args=','.join(n['name'] for n in node['parameters']['parameters'])
     expected='{'+('return ' if node['returnParameters']['parameters'] else '')+original['name']+'('+args+');}'
     assert compact(body)==compact(expected),(alias,body)
     assert not node['modifiers'],alias
     method='direct call to original guarded public implementation'
   else:method='interface declaration'
   checked.append(dict(path=filename,contract=contract['name'],alias=alias,proof=method))
changes=[]
for name in json.load(open(a.after/'sizes.json')):
 if name=='CrapsViews':continue
 old={json.dumps(x,sort_keys=True) for x in before[name]['abi']};new={json.dumps(x,sort_keys=True) for x in after[name]['abi']}
 assert old<=new,('Existing ABI removed or changed',name,old-new)
 methods=after[name]['evm']['methodIdentifiers'];assert len(methods)==len(set(methods.values())),('Selector collision',name)
 additions=sorted(new-old)
 for entry in map(json.loads,additions):
  assert entry['type']=='function' and (entry['name'] in byalias or entry in extra.get(name,[])),('Unreviewed ABI addition',name,entry)
 changes.append(dict(contract=name,addedFunctions=[json.loads(x)['name'] for x in additions]))
for name,entries in extra.items():
 for entry in entries:
  assert entry in after[name]['abi'] and entry not in before[name]['abi'],('Additional ABI is not a new exact entry',name,entry)
assert checked and len(checked)==len(manifest['definitions']),(len(checked),len(manifest['definitions']))
orders=[]
for name in ['DegenerusGame','Coinflip','DegenerusGameBoxModule','DegenerusGameDailyModule','DegenerusGameEndgameModule','DegenerusGamePassModule','CrapsBattle']:
 code=bytes.fromhex(after[name]['evm']['deployedBytecode']['object']);ops=[];pc=0
 while pc<min(len(code),6000):
  at=pc;op=code[pc];pc+=1;size=op-0x5f if 0x60<=op<=0x7f else 0;value=code[pc:pc+size];pc+=size;ops.append((at,op,value))
 selected=[];started=False
 for i in range(len(ops)-4):
  aa,b,c,d,e=ops[i:i+5]
  iscase=0x80<=aa[1]<=0x8f and 0x60<=b[1]<=0x63 and c[1]==0x14 and 0x60<=d[1]<=0x63 and e[1]==0x57
  if iscase:selected.append(b[2].hex().zfill(8));started=True
  elif started and aa[1]==0x5b:break
 expected=set(after[name]['evm']['methodIdentifiers'].values()) & {r['aliasSelector'] for r in manifest['aliases']}
 assert set(selected[:len(expected)])==expected,('Aliases are not the first runtime comparisons',name,selected[:len(expected)],expected)
 orders.append(dict(contract=name,firstSelectors=selected[:len(expected)],aliasCount=len(expected)))

a.report.write_text(json.dumps(dict(definitions=checked,abis=changes,dispatcherOrder=orders),indent=2)+'\n')
print(f'{len(checked)} alias definitions verified; all {len(changes)} production ABIs preserve their original entries')
