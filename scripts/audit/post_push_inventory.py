#!/usr/bin/env python3
"""Freeze post-push review inputs. Inventories are navigation, never review verdicts."""
import hashlib,json,pathlib,re,subprocess
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'docs/audit/post-push-rng-spine-2026-10-02/evidence'
BASE='32c604531da19166139fc6061812a2e33c693e1a'; TARGET='5214f7498d854e390e32e52107e40c517ce58995'
def git(*args): return subprocess.check_output(['git',*args],cwd=ROOT,text=True)
def sha(p): return hashlib.sha256(p.read_bytes()).hexdigest()
if (OUT/'target-inputs.json').exists():
 raise SystemExit('Original target evidence already exists; use a separately named candidate capture, never overwrite it.')
inputs=['contracts','test','foundry.toml','hardhat.config.js','package.json','package-lock.json','scope.txt']
if git('diff','--name-only',TARGET,'--',*inputs).strip() or git('ls-files','--others','--exclude-standard','--','contracts','test').strip():
 raise SystemExit('Input tree differs from pinned target; original target inventory requires an exact clean source tree.')
def owner(p):
 if any(x in p for x in ['Rng','Coinflip','WWXRP','GNRUS','Quest','Boon','Deity','Degenerette']): return 'rng_commitments'
 if any(x in p for x in ['Advance','Miner','GameOver','Storage','DegenerusGame.sol','IDegenerusGame']): return 'engine_liveness'
 if p.startswith('contracts/') or any(x in p for x in ['fork-run','fork-probe']):return 'records_accounting'
 return 'root'
OUT.mkdir(parents=True,exist_ok=True)
commits=git('rev-list','--reverse',f'{BASE}..{TARGET}').splitlines()
paths=git('diff','--name-only',BASE,TARGET).splitlines()
(OUT/'changed-files.tsv').write_text('path\treviewer\tstatus\n'+''.join(f'{p}\t{owner(p)}\tASSIGNED\n' for p in paths))
for commit in commits:
 (OUT/f'{commit[:9]}.diff').write_text(git('show','--format=fuller','--find-renames',commit))
(OUT/'net-contracts.diff').write_text(git('diff','--find-renames',BASE,TARGET,'--','contracts'))
production=sorted(p for p in (ROOT/'contracts').rglob('*.sol') if not {'mocks','test'}&set(p.relative_to(ROOT).parts))
imports={}; symbols={}
for p in production:
 rel=str(p.relative_to(ROOT));source=p.read_text()
 imports[rel]=[str((p.parent/x).resolve().relative_to(ROOT)) if x.startswith('.') else x for x in re.findall(r'import\s+(?:[^;]*?from\s+)?[\'"]([^\'"]+)[\'"]\s*;',source)]
 for name in re.findall(r'\b(?:contract|library|interface)\s+(\w+)',source): symbols[name]=rel
model=ROOT/'scripts/lib/predictAddresses.js';txt=model.read_text()
order=re.search(r'export const DEPLOY_ORDER = \[([\s\S]*?)\];',txt)[1]
keys=re.findall(r'^\s*"(\w+)"',order,re.M)
names=dict(re.findall(r'^\s*(\w+): "(\w+)"',re.search(r'export const KEY_TO_CONTRACT = \{([\s\S]*?)\};',txt)[1],re.M))
roots={symbols[names[k]] for k in keys}|{symbols['DegenerusVaultShare']}; closure=set(); todo=list(roots)
while todo:
 p=todo.pop()
 if p in closure:continue
 closure.add(p);todo += [x for x in imports.get(p,[]) if x in imports]
identity={str(p.relative_to(ROOT)):sha(p) for p in sorted(set(production)|set((ROOT/'test').rglob('*.sol'))|set((ROOT/'test').rglob('*.js'))|{ROOT/x for x in ['foundry.toml','hardhat.config.js','package.json','package-lock.json','scope.txt']})}
(OUT/'target-inputs.json').write_text(json.dumps(identity,indent=2)+'\n')
(OUT/'scope-graph.json').write_text(json.dumps({'base':BASE,'target':TARGET,'commits':commits,'deployments':[{ 'key':k,'contract':names[k],'source':symbols[names[k]]} for k in keys]+[{'contract':'DegenerusVaultShare','source':symbols['DegenerusVaultShare']}], 'production_files':list(imports),'imports':imports,'deployment_closure':sorted(closure),'outside_deployment_closure':sorted(set(imports)-closure)},indent=2)+'\n')
rows=[]
for commit in commits:
 diff=git('show','--format=','--unified=0',commit)
 p=''
 for line in diff.splitlines():
  if line.startswith('+++ b/'):p=line[6:]
  elif line.startswith('@@'): rows.append((commit[:9],p,owner(p),line))
(OUT/'change-hunks.tsv').write_text('commit\tpath\treviewer\thunk\n'+''.join('\t'.join(row)+'\n' for row in rows))
fn=[]
for p in production:
 for m in re.finditer(r'\b(function\s+(\w+)|constructor|fallback|receive)\s*\(',p.read_text()):
  fn.append({'source':str(p.relative_to(ROOT)),'line':p.read_text()[:m.start()].count('\n')+1,'function':m[2] or m[1]})
(OUT/'function-navigation.json').write_text(json.dumps(fn,indent=2)+'\n')
print(json.dumps({'commits':len(commits),'changed_files':len(paths),'production_files':len(production),'deployments':len(keys)+1,'closure':len(closure),'outside_closure':sorted(set(imports)-closure),'hunks':len(rows)},indent=2))
