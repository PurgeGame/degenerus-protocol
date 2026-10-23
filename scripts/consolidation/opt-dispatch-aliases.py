#!/usr/bin/env python3
"""Generate reviewed low-selector aliases and retarget statically bound protocol calls.

Run once against the preceding item's compiler input/output. Original selectors,
function bodies and guards remain. No bytecode or compiler IR is rewritten.
"""
import argparse,collections,json,re
from pathlib import Path
from Crypto.Hash import keccak

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before',type=Path,required=True)
p.add_argument('--out',type=Path,required=True)
p.add_argument('--apply',action='store_true')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
request=json.load(open(a.before/'input.json'));compiled=json.load(open(a.before/'output.json'))
artifacts=json.load(open(a.before/'abis.json'))
choices={
'DegenerusGame':['extsload(bytes32)','registerWallet(address,bool)','consumeCoinflipBoon(uint32)','mintPackedOfId(uint32)','rngConsumerStage()','setCrapsRngPending(uint48,bool)','resolveAccount(uint32,address)','walletIdOf(address)'],
'Coinflip':['handlePurchase(uint32,uint256,uint32,uint256,uint256,uint256)','payAffiliateCombined(bytes32,uint32,uint24,uint256,uint256,uint256,uint256,uint16)','creditFlipPair(uint32,uint256,uint32,uint256)','creditFlip(uint32,uint256)','affiliateBonusPointsBest(uint24,uint32)','effectiveBaseStreakAndAfking(uint32)','recordCrapsAction(uint32,uint8)'],
'DegenerusGameBoxModule':['runHumanBoxWork(uint256)','runSubscriberWork(uint24,uint256)','runDegeneretteWork(uint256)','runSubDraw(uint24)','runAfkingWork(uint256)'],
'DegenerusGameDailyModule':['publishRng()','runDailyPhase(uint256)','requestMinerRng()','requestDailyRng(uint24)','applyDailyWord()'],
'DegenerusGameEndgameModule':['buyDegenesisBox(uint32,uint256)','recordDecBurn(uint32,uint24,uint256,uint256,uint32)','topUpSdgnrsAfking()','prepareDegenesis(uint24)','runDegenesisWork(uint256)'],
'DegenerusGamePassModule':['runTicketWork(uint24,uint256)','purchaseWhalePassForSdgnrs(uint24)','awardWhalePass(uint24,uint8,uint256,uint256,bool)'],
'CrapsBattle':['minerMaintenancePending()','runCrapsMaintenance(uint256)','resolveRngSlot(uint64,uint256)','finalizeBattle((bytes32,uint128,uint128,uint256,uint256,uint256,uint256,uint256,uint256,bool,uint48,uint32,uint64,uint32,uint32,uint256,uint256),uint256,uint256)','registerRngSlot(uint48,uint64,bytes32)','runCrapsReadWork(uint48,uint256)'],
}
all_selectors={v for art in artifacts.values() for v in art.get('evm',{}).get('methodIdentifiers',{}).values()}
ceiling=min(0x00100000,min(int(v,16) for v in all_selectors))
selected={};manifest=[]
for contract,signatures in choices.items():
 for signature in signatures:
  selector=artifacts[contract]['evm']['methodIdentifiers'][signature]
  if selector in selected:continue
  name,args=signature.split('(',1)
  for nonce in range(10_000_000):
   alias=f'{name}_g{nonce}';sig=alias+'('+args;digest=keccak.new(digest_bits=256,data=sig.encode()).hexdigest()[:8]
   if int(digest,16)<ceiling and digest not in all_selectors:break
  else:raise ValueError('No low selector',signature)
  all_selectors.add(digest)
  row=dict(contract=contract,signature=signature,selector=selector,alias=alias,aliasSignature=sig,aliasSelector=digest)
  selected[selector]=row;manifest.append(row)

def nodes(node):
 if isinstance(node,dict):
  yield node
  for v in node.values():yield from nodes(v)
 elif isinstance(node,list):
  for v in node:yield from nodes(v)

units={};definitions={}
for filename,unit in compiled['sources'].items():
 if not filename.startswith('contracts/') or filename=='contracts/XaLayout.sol':continue
 source=request['sources'][filename]['content']
 assert Path(filename).read_text()==source,('Source drift',filename)
 # Solc source ranges are UTF-8 byte offsets, not Python character offsets.
 source=source.encode('utf-8').decode('latin1')
 units[filename]=(source,list(nodes(unit['ast'])))
 for n in units[filename][1]:
  if n.get('nodeType')=='FunctionDefinition' and n.get('functionSelector') in selected:
   definitions[n['id']]=(filename,n,selected[n['functionSelector']])

edits=collections.defaultdict(list);locations=[];calls=[]
def span(n):
 start,length,_=map(int,n['src'].split(':'));return start,start+length
for filename,n,row in definitions.values():
 source=units[filename][0];start,end=span(n);ps,pe=span(n['parameters'])
 params=[];args=[]
 for i,param in enumerate(n['parameters']['parameters']):
  s,e=span(param);text=source[s:e];name=param.get('name')
  if not name:name=f'arg{i}';text+=' '+name
  params.append(text);args.append(name)
 ret=n['returnParameters']['parameters'];returns=''
 if ret:
  rs,re_=span(n['returnParameters']);returns=' returns '+source[rs:re_]
 mutability=n['stateMutability'];mut=' '+mutability if mutability in ('view','pure','payable') else ''
 header=f'function {row["alias"]}('+', '.join(params)+') external'+mut+returns
 implemented=n.get('implemented',n.get('body') is not None)
 if implemented:
  body=('return ' if ret else '')+n['name']+'('+', '.join(args)+');'
  alias='// Low-selector protocol entry; the original ABI and guarded implementation remain.\n    '+header+' { '+body+' }\n\n    '
  if n['visibility']=='external':
   bs,_=span(n['body']);head=source[pe:bs];m=re.search(r'\bexternal\b',head);assert m,(filename,n['name'])
   edits[filename].append((pe+m.start(),pe+m.end(),'public'))
  else:assert n['visibility']=='public',(filename,n['name'],n['visibility'])
 else:alias=header+';\n\n    '
 insert=span(n['documentation'])[0] if isinstance(n.get('documentation'),dict) else start
 edits[filename].append((insert,insert,alias))
 locations.append(dict(path=filename,function=n['name'],alias=row['alias'],implemented=implemented))
for filename,(source,ns) in units.items():
 # This file pins owner-authorized public selectors, not outbound calls.
 if filename=='contracts/libraries/VaultPlayerActions.sol':continue
 for n in ns:
  if n.get('nodeType')=='MemberAccess' and n.get('referencedDeclaration') in definitions:
   _,decl,row=definitions[n['referencedDeclaration']]
   assert n['memberName']==decl['name']
   s,e=span(n);begin=e-len(n['memberName']);assert source[begin:e]==n['memberName']
   edits[filename].append((begin,e,row['alias']))
   calls.append(dict(path=filename,original=source[s:e],alias=row['alias']))
for filename,changes in edits.items():
 source=units[filename][0];last=len(source)+1
 for start,end,text in sorted(changes,reverse=True):
  assert end<=last,('Overlapping edit',filename,start,end,last)
  source=source[:start]+text+source[end:];last=start
 if a.apply:Path(filename).write_bytes(source.encode('latin1'))
(a.out/'dispatcher-aliases.json').write_text(json.dumps(dict(method=__doc__,ceiling=hex(ceiling),aliases=manifest,definitions=locations,retargetedCalls=calls),indent=2)+'\n')
print(json.dumps(dict(aliases=len(manifest),definitions=len(locations),calls=len(calls),files=len(edits),applied=a.apply)))
