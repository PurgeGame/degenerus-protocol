#!/usr/bin/env python3
import json,pathlib,subprocess,importlib.util,sys
import argparse,io,tarfile,os
parser=argparse.ArgumentParser(description="Prove Lane A namespace layouts, ABI inclusion and unchanged external layouts against a git revision.")
parser.add_argument('--base',default='db2004c99eaaaca8c4be1b8a1a1c0f6439a0b9b6')
parser.add_argument('--out',type=pathlib.Path,default=pathlib.Path('.planning/consolidation/xa'))
parser.add_argument('--artifacts',type=pathlib.Path)
args=parser.parse_args();p=args.out;p.mkdir(parents=True,exist_ok=True)
solc=os.environ.get('SOLC',str(pathlib.Path.home()/'.svm/0.8.38/solc-0.8.38'))
with tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',args.base,'contracts']))) as archive:
 old_sources={m.name:{'content':archive.extractfile(m).read().decode()} for m in archive.getmembers() if m.isfile() and m.name.endswith('.sol')}
base_request={'language':'Solidity','sources':old_sources,'settings':{'remappings':['@openzeppelin/=node_modules/@openzeppelin/'],'outputSelection':{'*':{'*':['storageLayout','abi']}}}}
with (p/'base-layout-ast.json').open('w') as f:
 subprocess.run([solc,'--base-path','.','--include-path','node_modules','--standard-json'],input=json.dumps(base_request),text=True,stdout=f,check=True)
base=json.loads((p/'base-layout-ast.json').read_text())
assert not [e for e in base.get('errors',[]) if e['severity']=='error'],base.get('errors')
sources={str(f):{'content':f.read_text()} for f in pathlib.Path('contracts').rglob('*.sol')}
proof='''// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {DegenerusQuests} from "./DegenerusQuests.sol";
import {DegenerusAffiliate} from "./DegenerusAffiliate.sol";
contract XaQuestsLayout is DegenerusQuests { DegenerusQuestsStorage private probe; }
contract XaAffiliateLayout is DegenerusAffiliate {
 constructor() DegenerusAffiliate(new address[](0),new bytes32[](0),new uint8[](0),new address[](0),new bytes32[](0)) {}
 DegenerusAffiliateStorage private probe;
}
'''
sources['contracts/XaLayout.sol']={'content':proof}
req={'language':'Solidity','sources':sources,'settings':{'remappings':['@openzeppelin/=node_modules/@openzeppelin/'],'outputSelection':{'*':{'':['ast'],'*':['storageLayout','abi','evm.methodIdentifiers']}}}}
with (p/'layout-ast.json').open('w') as f:subprocess.run([solc,'--base-path','.','--include-path','node_modules','--standard-json'],input=json.dumps(req),text=True,stdout=f,check=True)
o=json.loads((p/'layout-ast.json').read_text());errors=[e['formattedMessage'] for e in o.get('errors',[]) if e['severity']=='error'];assert not errors,errors
spec=importlib.util.spec_from_file_location('layouts','scripts/layout/check_recursive_layout.py');m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)
report={'base':args.base,'namespaces':{},'unchangedLayouts':[],'abi':{},'rewardPaths':{}}
ns=json.load(open('scripts/consolidation/xa-namespaces.json'))
for name,key,proofName,extent in [('DegenerusQuests','quests','XaQuestsLayout',4),('DegenerusAffiliate','affiliate','XaAffiliateLayout',7)]:
 old=base['contracts'][f'contracts/{name}.sol'][name]['storageLayout'];new=o['contracts']['contracts/XaLayout.sol'][proofName]['storageLayout'];typ=new['types'][new['storage'][0]['type']];assert int(typ['numberOfBytes'])==extent*32
 shape={'storage':typ['members'],'types':new['types']};assert m.normalize(old)==m.normalize(shape),(name,m.normalize(old),m.normalize(shape))
 assert o['contracts'][f'contracts/{name}.sol'][name]['storageLayout']['storage']==[]
 report['namespaces'][key]={'root':ns[key]['root'],'slots':extent,'recursiveMemberParity':True}
for file,contracts in base['contracts'].items():
 for name,b in contracts.items():
  if name in ['DegenerusQuests','DegenerusAffiliate']:continue
  n=o['contracts'][file][name]
  assert m.normalize(b['storageLayout'])==m.normalize(n['storageLayout']),name
  if b['storageLayout']['storage']:report['unchangedLayouts'].append(name)
host=o['contracts']['contracts/Coinflip.sol']['Coinflip'];hostFns=host['evm']['methodIdentifiers'];seen={}
for sig,selector in hostFns.items():assert selector not in seen or seen[selector]==sig;seen[selector]=sig
for name in ['DegenerusQuests','DegenerusAffiliate','Coinflip']:
 old=base['contracts'][f'contracts/{name}.sol'][name]['abi'];new=host['abi']
 for x in old:
  if x['type'] in ['constructor','fallback','receive']:continue
  # Internal types only name source-level structs; wire types and mutability remain exact.
  def norm(x):
   if isinstance(x,list):return [norm(v) for v in x]
   if isinstance(x,dict):return {k:norm(v) for k,v in x.items() if k!='internalType'}
   return x
  assert norm(x) in [norm(y) for y in new],(name,x)
 report['abi'][name]='exact function/event/error inclusion'
# Explicit complete namespace intervals (Craps extends beyond a 256-slot page).
intervals=[('Game',0,847),('Coinflip',0,10)]
roots=[]
for key,extent in [('quests',4),('affiliate',7),('coinflip',10),('jackpots',100),('craps',2849),('sdgnrs',100)]:
 root=int(ns[key]['root'],16);assert root%256==0;assert root>2849
 for other,start,end in roots:assert root+extent<=start or end<=root,(key,other)
 roots.append((key,root,root+extent))
report['namespaceIntervals']='disjoint from each other and ordinary Game/Coinflip direct slots; hashed-key separation relies on Keccak'
def walk(x):
 if isinstance(x,dict):
  yield x
  for v in x.values():yield from walk(v)
 elif isinstance(x,list):
  for v in x:yield from walk(v)
funcs={}
for name in ['DegenerusQuests','DegenerusAffiliate','Coinflip']:
 ast=o['sources'][f'contracts/{name}.sol']['ast'];contract=next(x for x in ast['nodes'] if x.get('name')==name)
 for f in contract['nodes']:
  if f.get('nodeType')=='FunctionDefinition':funcs[f['id']]=(name,f)
# Resolve overridden bridge calls to the concrete host body.
overrides={f['name']:i for i,(name,f) in funcs.items() if name=='Coinflip' and f.get('overrides')}
edges={}
for i,(name,f) in funcs.items():
 edges[i]=[]
 for call in walk(f.get('body')):
  if call.get('nodeType')!='FunctionCall':continue
  expr=call['expression'];target=expr.get('referencedDeclaration')
  if target in funcs:
   called=funcs[target][1]['name'];edges[i].append(overrides.get(called,target))
targets={'_questCreditFlip','_affiliateCreditFlip','_affiliateCreditFlipPair','_affiliateQuestReward','_handleFlip','_handleAffiliate'}
for i,(name,f) in funcs.items():
 if f['visibility'] not in ['external','public']:continue
 paths=[]
 def dfs(at,path):
  if at in path:return
  if funcs[at][1]['name'] in targets:paths.append([funcs[j][1]['name'] for j in path+[at]])
  for nxt in edges[at]:dfs(nxt,path+[at])
 dfs(i,[])
 if paths:report['rewardPaths'][name+'.'+f['name']]=paths
(p/'layout-proof.json').write_text(json.dumps(report,indent=2));print(json.dumps({'namespaces':report['namespaces'],'unchangedLayouts':len(report['unchangedLayouts']),'hostSelectors':len(hostFns),'rewardEntryPoints':list(report['rewardPaths'])},indent=2))

if args.artifacts:
 for name,data in o['contracts']['contracts/XaLayout.sol'].items():
  dest=args.artifacts/'XaLayout.sol'/f'{name}.json';dest.parent.mkdir(parents=True,exist_ok=True)
  dest.write_text(json.dumps(data))

if args.artifacts:
 for filename,contracts in o['contracts'].items():
  for name,data in contracts.items():
   dest=args.artifacts/pathlib.Path(filename).name/f'{name}.json'
   if not dest.exists():
    dest.parent.mkdir(parents=True,exist_ok=True);dest.write_text(json.dumps(data))
