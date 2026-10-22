import re,json,subprocess,pathlib,posixpath
root=pathlib.Path.cwd()
groups={'HotCore': ['DegenerusGame', 'DegenerusGameMintModule', 'DegenerusGameFoilPackModule', 'DegenerusGameMinerModule'], 'BoxAll': ['GameAfkingModule', 'DegenerusGameLootboxModule', 'DegenerusGameBoonModule', 'DegenerusGameDegeneretteModule'], 'AdvanceJackpotDrawRng': ['DegenerusGameAdvanceModule', 'DegenerusGameJackpotModule', 'DegenerusGameJackpotDrawModule', 'DegenerusGameRngModule'], 'PassesTickets': ['DegenerusGameWhaleModule', 'DegenerusGameTicketModule'], 'EndgameDecimatorDegenesisBingo': ['DegenerusGameGameOverModule', 'DegenerusGameDecimatorModule', 'DegenerusGameDegenesisModule', 'DegenerusGameBingoModule'], 'CrapsAll': ['CrapsEngine', 'CrapsBattle', 'JackpotBattle']}
sources={str(p.relative_to(root)):{'content':p.read_text()} for p in (root/'contracts').rglob('*.sol')}
def stripped(s):
 return re.sub(r'//[^\n]*|/\*[\s\S]*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'', lambda m:' '*len(m[0]),s)
def body_of(s,name):
 t=stripped(s);m=re.search(r'contract\s+'+name+r'\s+is\s+([^\{]+)\{',t);start=m.end();d=1;i=start
 while d:
  if t[i]=='{':d+=1
  if t[i]=='}':d-=1
  i+=1
 return s[:m.start()],s[start:i-1],m[1]
for bundle,names in groups.items():
 imports=set(); extras=[]; bodies=[]; bases=[]
 for ix,n in enumerate(names):
  source=('contracts/'+n+'.sol') if ('contracts/'+n+'.sol') in sources else ('contracts/modules/'+n+'.sol')
  s=sources[source]['content'];head,body,parents=body_of(s,n)
  head=re.sub(r'"(\.[^"]+)"',lambda m:'"'+posixpath.normpath(posixpath.join(posixpath.dirname(source),m[1]))+'"',head)
  imports.update(re.findall(r'^import[\s\S]*?;',head,re.M))
  clean_head=re.sub(r'import[\s\S]*?;','',head)
  # Any interfaces declared alongside the source contract are imported from the original.
  if re.search(r'\binterface\s+',stripped(s)):
   for interface in re.findall(r'\binterface\s+(\w+)',stripped(s)):
    imports.add(f'import {{{interface}}} from "{source}";')
  bases.extend(x.strip() for x in parents.split(','))
  t=stripped(body)
  ids=set(re.findall(r'\b(?:function|event|error|struct|enum)\s+(\w+)',t))
  ids.update(re.findall(r'\bconstant\s+(\w+)\s*=',t))
  ids -= {m[1] for m in re.finditer(r'function\s+(\w+)[^{;]*\boverride\b[^{;]*',t)}
  # Prefix every locally declared symbol, leaving imported members (after '.') unchanged.
  for ident in sorted(ids,key=len,reverse=True):
   body=re.sub(r'(?<![.\w])'+re.escape(ident)+r'\b',f'B{ix}_{ident}',body)
   body=re.sub(r'\bthis\.'+re.escape(ident)+r'\b',f'this.B{ix}_{ident}',body)
  body=re.sub(r'\bstruct\s+\w+\s*\{[^}]*\}', lambda m:re.sub(r'\bB\d+_(\w+)(?=\s*;)',r'\1',m[0]),body)
  bodies.append(body)
 # Parent utilities share Storage and must appear before their derived parent in inheritance.
 bases=list(dict.fromkeys(bases))
 order={'Craps':-2,'CrapsCustomTerms':-1,'CrapsBattleStorage':2,'DegenerusGameStorage':0,'DegenerusGameMintStreakUtils':1,'DegenerusGamePayoutUtils':2,'DegenerusGameRngUtils':3}
 bases.sort(key=lambda b:order.get(b,1))
 text='// SPDX-License-Identifier: AGPL-3.0-only\npragma solidity 0.8.38;\n'+'\n'.join(sorted(imports))+'\ncontract '+bundle+' is '+', '.join(bases)+' {'+'\n'.join(bodies)+'\n}\n'
 sources['contracts/modules/'+bundle+'.sol']={'content':text}
 (root/(bundle+'.sol')).write_text(text)
def span(src,name):
 m=re.search(r'\bfunction\s+'+re.escape(name)+r'\s*\(',src);assert m,name
 a=m.start();start=src.index('{',m.end());d=1;i=start+1
 while d:
  if src[i]=='{':d+=1
  elif src[i]=='}':d-=1
  i+=1
 return a,i
bundle=sources['contracts/modules/HotCore.sol']['content']
for origin,fn in [('DegenerusGameTicketModule','registerWallet'),('DegenerusGameTicketModule','registerWalletIdentity'),('GameAfkingModule','recordAfkingSecondary'),('GameAfkingModule','floorAfkingStreakBase')]:
 source=sources['contracts/modules/'+origin+'.sol']['content'];a,b=span(source,fn);func=source[a:b].replace('function '+fn+'(', 'function B0_'+fn+'(');a,b=span(bundle,'B0_'+fn);bundle=bundle[:a]+func+bundle[b:]
sources['contracts/modules/HotCore.sol']={'content':bundle}
(root/'HotCore.sol').write_text(bundle)

selection={'contracts/modules/'+n+'.sol':{n:['evm.deployedBytecode.object','evm.bytecode.object']} for n in groups}
for name in sum(groups.values(),[]):
 source='contracts/'+name+'.sol' if 'contracts/'+name+'.sol' in sources else 'contracts/modules/'+name+'.sol'
 selection[source]={name:['evm.deployedBytecode.object','evm.bytecode.object']}
settings={'optimizer':{'enabled':True,'runs':1000},'viaIR':True,'evmVersion':'osaka','remappings':['@openzeppelin/=node_modules/@openzeppelin/'],'outputSelection':selection}
request={'language':'Solidity','sources':sources,'settings':settings}
(root/'sizing-input.json').write_text(json.dumps(request))
with (root/'sizing-output.json').open('w') as f:
 subprocess.run([str(pathlib.Path.home()/'.svm/0.8.38/solc-0.8.38'),'--base-path',str(root),'--allow-paths',str(root)+','+str((root/'node_modules').resolve()),'--standard-json'],input=json.dumps(request),text=True,stdout=f,check=True)
out=json.loads((root/'sizing-output.json').read_text())
for e in out.get('errors',[]):
 if e['severity']=='error':print(e['formattedMessage'])
for file,contracts in out.get('contracts',{}).items():
 for name,a in contracts.items():print(name,len(a['evm']['deployedBytecode']['object'])//2)
