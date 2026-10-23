#!/usr/bin/env python3
import io,json,pathlib,re,subprocess,tarfile,sys
import argparse,os
parser=argparse.ArgumentParser(description="Build canonical Lane A and pristine base runtimes with solc 0.8.38.")
parser.add_argument('mode',choices=['candidate','baseline','baseline-pristine','no-spill','native'])
parser.add_argument('--base',default='db2004c99eaaaca8c4be1b8a1a1c0f6439a0b9b6')
parser.add_argument('--pins',type=pathlib.Path,help='Common state-owner pins for replay; production pins by default.')
parser.add_argument('--out',type=pathlib.Path,default=pathlib.Path('.planning/consolidation/xa'))
a=parser.parse_args();root=pathlib.Path.cwd();out=root/a.out;out.mkdir(parents=True,exist_ok=True);mode=a.mode
rev=subprocess.check_output(['git','rev-parse',a.base],text=True).strip()
solc=os.environ.get('SOLC',str(pathlib.Path.home()/'.svm/0.8.38/solc-0.8.38'))
assert '0.8.38+' in subprocess.check_output([solc,'--version'],text=True)
if mode=='no-spill':
 req=json.loads((out/'candidate-production-input.json').read_text())
 req['settings']['optimizer']['details']={'yulDetails':{'stackAllocation':False}}
 req['settings']['outputSelection']={'contracts/Coinflip.sol':{'Coinflip':['evm.deployedBytecode.object']}}
 (out/'no-spill-input.json').write_text(json.dumps(req))
 with (out/'no-spill-output.json').open('w') as f:
  subprocess.run([solc,'--base-path','.','--include-path','node_modules','--standard-json'],input=json.dumps(req),text=True,stdout=f,check=True)
 errors=[e['formattedMessage'] for e in json.loads((out/'no-spill-output.json').read_text()).get('errors',[]) if e['severity']=='error']
 print('\n'.join(errors) or 'No-spill variant compiled');sys.exit(0)
if mode=='native':
 native=out/'native/deployment'
 with (native/'output.json').open('w') as f:
  subprocess.run([solc,'--base-path','.','--include-path','node_modules','--standard-json'],input=(native/'input.json').read_text(),text=True,stdout=f,check=True)
 errors=[e['formattedMessage'] for e in json.loads((native/'output.json').read_text()).get('errors',[]) if e['severity']=='error']
 print('\n'.join(errors) or 'Native artifacts compiled');sys.exit(bool(errors))
if mode.startswith('baseline'):
 tar=tarfile.open(fileobj=io.BytesIO(subprocess.check_output(['git','archive',rev,'contracts'])))
 sources={m.name:{'content':tar.extractfile(m).read().decode()} for m in tar.getmembers() if m.isfile() and m.name.endswith('.sol')}
else:sources={str(p):{'content':p.read_text()} for p in pathlib.Path('contracts').rglob('*.sol')}
pins=(a.pins or pathlib.Path('contracts/ContractAddresses.sol')).read_text()
if mode.startswith('baseline'):
 if a.pins:
  # Only QA storage owners differ. Keep Coinflip/WWXRP seed domains identical.
  for key,value in [('AFFILIATE','0x0000000000000000000000000000000000003001'),('QUESTS','0x0000000000000000000000000000000000003002')]:
   pins=re.sub(r'(address internal constant '+key+r'\s*=\s*address\()[^)]*',r'\g<1>'+value,pins)
 else: pins=subprocess.check_output(['git','show',rev+':contracts/ContractAddresses.sol'],text=True)
 # Constructor-only initialization probes are replaced by pristine runtime before replay.
 for name in (['DegenerusQuests','DegenerusAffiliate'] if mode=='baseline' else []):
  s=sources[f'contracts/{name}.sol']['content'];s=s.replace('contract '+name,'contract XaInit'+name)
  m=re.search(r'constructor\(([\s\S]*?)\)\s*\{',s)
  s=s[:m.start()]+'function initializeXa('+m[1]+') external {'+s[m.end():]
  sources[f'contracts/XaInit{name}.sol']={'content':s}
sources['contracts/ContractAddresses.sol']={'content':pins}
# Required to preserve census-only Craps getter ABI at the same storage owner.
sources['test/craps/CrapsViews.sol']={'content':pathlib.Path('test/craps/CrapsViews.sol').read_text()}
rows=json.loads(subprocess.check_output(['node','--input-type=module','-e',"import {DEPLOYMENTS} from './scripts/lib/deploymentManifest.js'; console.log(JSON.stringify(DEPLOYMENTS))"],text=True))
names=[r['contract'] for r in rows]+['DegenerusGameLens','CrapsLens','DegenerusVaultShare','DegenerusQuests','DegenerusAffiliate','CrapsViews','JackpotBattle']
if mode=='baseline':names+=['XaInitDegenerusQuests','XaInitDegenerusAffiliate']
selection={}
for filename,v in sources.items():
 for name in names:
  if re.search(r'\bcontract\s+'+name+r'\b',v['content']):selection.setdefault(filename,{})[name]=['abi','storageLayout','evm.bytecode.object','evm.deployedBytecode.object','evm.deployedBytecode.immutableReferences','irOptimized','metadata']
for filename in selection: selection[filename]['']=['ast']
req={'language':'Solidity','sources':sources,'settings':{'optimizer':{'enabled':True,'runs':1000},'viaIR':True,'evmVersion':'osaka','remappings':['@openzeppelin/=node_modules/@openzeppelin/','forge-std/=lib/forge-std/src/'],'outputSelection':selection}}
(out/f'{mode}-production-input.json').write_text(json.dumps(req))
with (out/f'{mode}-production-output.json').open('w') as f:
 subprocess.run([solc,'--base-path','.', '--include-path','node_modules','--standard-json'],input=json.dumps(req),text=True,stdout=f,check=True)
o=json.loads((out/f'{mode}-production-output.json').read_text());errors=[e['formattedMessage'] for e in o.get('errors',[]) if e['severity']=='error']
if errors:print('\n'.join(errors));sys.exit(1)
contracts={name:a for cc in o['contracts'].values() for name,a in cc.items()};(out/f'{mode}-abis.json').write_text(json.dumps(contracts))
artifact=root/f'forge-out-xa-{mode}'
for name,a in contracts.items():
 p=artifact/('DegenerusVault.sol' if name=='DegenerusVaultShare' else f'{name}.sol')/f'{name}.json';p.parent.mkdir(parents=True,exist_ok=True)
 p.write_text(json.dumps({'abi':a['abi'],'metadata':a.get('metadata'),'storageLayout':a['storageLayout'],'irOptimized':a['irOptimized'],'bytecode':{'object':'0x'+a['evm']['bytecode']['object']},'deployedBytecode':{'object':'0x'+a['evm']['deployedBytecode']['object']}}))
if mode=='baseline':
 targets=dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',pins)); variants=[]
 def walk(x):
  if isinstance(x,dict):
   yield x
   for v in x.values():yield from walk(v)
  elif isinstance(x,list):
   for v in x:yield from walk(v)
 immutableNames={str(x['id']):x['name'] for src in o['sources'].values() for x in walk(src.get('ast',{})) if x.get('nodeType')=='VariableDeclaration' and x.get('mutability')=='immutable'}
 shares=json.loads(subprocess.check_output(['node','--input-type=module','-e',f"import {{getCreateAddress}} from 'ethers';console.log(JSON.stringify([1,2].map(nonce=>getCreateAddress({{from:'{targets['VAULT']}',nonce}}))))"],text=True))
 immutableValues={'flipShare':int(shares[0],16),'ethShare':int(shares[1],16),'dgve':int(shares[1],16),'finalizeOnBootstrap':0}
 def runtime(name):
  a=contracts[name]['evm']['deployedBytecode'];code=bytearray.fromhex(a['object'])
  for key,refs in a.get('immutableReferences',{}).items():
   value=immutableValues[immutableNames[key]]
   for ref in refs:code[ref['start']:ref['start']+ref['length']]=value.to_bytes(ref['length'],'big')
  return '0x'+code.hex()
 for row in rows:
  name=row['contract'];name='CrapsViews' if name=='CrapsBattle' else name
  variants.append({'name':name,'target':targets[row['key']],'runtime':runtime(name)})
 for name,key in [('DegenerusQuests','QUESTS'),('DegenerusAffiliate','AFFILIATE')]:
  variants.append({'name':name,'target':targets[key],'runtime':runtime(name),'initRuntime':'0x'+(contracts if mode=='baseline' else json.loads((out/'baseline-abis.json').read_text()))['XaInit'+name]['evm']['deployedBytecode']['object']})
 (out/'baseline-overrides.json').write_text(json.dumps({'revision':rev,'xa':True,'coinflip':targets['COINFLIP'],'count':len(variants),'contracts':variants}))
print(mode,rev,'contracts',len(contracts),'host bytes',len(contracts['Coinflip']['evm']['deployedBytecode']['object'])//2)
