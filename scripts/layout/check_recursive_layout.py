#!/usr/bin/env python3
"""Compare complete recursive compiler layouts, independently of shallow goldens."""
import argparse,json,pathlib,re,sys

def normalize(layout):
 types=layout['types'] or {}
 def shape(key,active=()):
  t=types[key];result={k:t[k] for k in ('label','encoding','numberOfBytes') if k in t}
  if key in active:return {'recursive':t['label']}
  for k in ('base','key','value'):
   if k in t:result[k]=shape(t[k],(*active,key))
  if 'members' in t:result['members']=[entry(e,(*active,key)) for e in t['members']]
  return result
 def entry(e,active=()):
  return {'label':e['label'],'slot':int(e['slot']),'offset':int(e['offset']),'type':shape(e['type'],active)}
 return sorted((entry(e) for e in layout['storage']),key=lambda e:(e['slot'],e['offset'],e['label']))

def read(out):
 result={}
 for p in sorted(out.glob('**/*.json')):
  if p.parent.name=='build-info':continue
  try:d=json.loads(p.read_text())
  except (ValueError,OSError):continue
  if 'storageLayout' in d and (d['storageLayout'].get('storage') or p.stem.endswith('Module') or p.stem=='DegenerusGame'):
   if p.stem in result:raise ValueError(f'duplicate contract artifact: {p.stem}')
   result[p.stem]=normalize(d['storageLayout'])
 return result

def expected_modules():
 source=(pathlib.Path(__file__).resolve().parents[1]/'lib/predictAddresses.js').read_text()
 mapping=re.search(r'export const KEY_TO_CONTRACT = \{([\s\S]*?)\};',source)[1]
 return sorted({name for name in re.findall(r': "(\w+)"',mapping) if name.endswith('Module')})

def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=pathlib.Path,default=pathlib.Path('forge-out'));p.add_argument('--baseline',type=pathlib.Path);p.add_argument('--report',type=pathlib.Path,required=True);a=p.parse_args()
 layouts=read(a.out);game=layouts['DegenerusGame'];fail=[];modules=expected_modules()
 if not game:raise ValueError('empty Game layout')
 for name in modules:
  if name not in layouts or layouts[name]!=game:fail.append(name)
 if layouts['CrapsBattle']!=layouts['JackpotBattle']:fail.append('JackpotBattle')
 delta={}
 if a.baseline:
  before=read(a.baseline)
  for name in layouts.keys()&before.keys():
   if layouts[name]!=before[name]:
    old={e['label']:e for e in before[name]};new={e['label']:e for e in layouts[name]}
    delta[name]={'added':sorted(new.keys()-old.keys()),'removed':sorted(old.keys()-new.keys()),'changed':sorted(k for k in old.keys()&new.keys() if old[k]!=new[k])}
 report={'module_count':len(modules),'modules':modules,'delegate_layout_mismatches':fail,'baseline_deltas':delta,'layouts':layouts}
 a.report.parent.mkdir(exist_ok=True,parents=True);a.report.write_text(json.dumps(report,indent=2)+'\n')
 print(json.dumps({'module_count':len(modules),'delegate_layout_mismatches':fail,'baseline_changed_contracts':sorted(delta)},indent=2))
 return bool(fail)
if __name__=='__main__':sys.exit(main())
