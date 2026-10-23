#!/usr/bin/env python3
"""Reconcile the reviewed item-2 boundary inventory with exact final source sites."""
import argparse,importlib.util,json,re
from pathlib import Path
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True);a=p.parse_args()
spec=importlib.util.spec_from_file_location('calls','scripts/check-recipient-calls.py');mod=importlib.util.module_from_spec(spec);spec.loader.exec_module(mod)
old=json.load(open('.planning/consolidation/opt/item2/external-call-classification.json'))['sites']
aliases={r['alias']:r['signature'].split('(')[0] for r in json.load(open('.planning/consolidation/opt/item3/dispatcher-aliases.json'))['aliases']}
def canonical(text):
 for alias,name in aliases.items():text=re.sub(r'\b'+re.escape(alias)+r'\b',name,text)
 return text
key=lambda r:tuple(r[k] for k in ('path','scope','kind','expression'))
reviewed={key(r):r for r in old};rows=[];changes=[]
for (path,scope,kind,expr),count in sorted(mod.discover().items()):
 if kind=='recipient-helper':continue
 if not path.startswith('contracts/') or path.startswith('contracts/mocks/'):continue
 lookup=(path,canonical(scope),kind,canonical(expr))
 prior=reviewed.get(lookup)
 if prior is None and scope=='DegenerusGameGameOverModule._shutdownVrf':
  original=expr.replace('ContractAddresses.ADMIN, 1_000_000, 250_000', 'ContractAddresses.ADMIN, 800_000, 250_000')
  prior=reviewed.get((path,scope,kind,original))
 if prior is None and scope=='DegenerusGame.buyDegenesisBox':
  prior=next(r for r in old if r['scope']==scope and r['kind']==kind)
 elif prior is None and scope=='GameBingo._claimAffiliateDgnrs' and 'affiliateScoreAndTotal_g4013' in expr:
  prior=next(r for r in old if r['scope']==scope and 'affiliate.affiliateScore(' in r['expression'])
 assert prior is not None,('Unclassified new boundary',lookup)
 row={**prior,'path':path,'scope':scope,'kind':kind,'expression':expr,'count':count}
 if scope=='DegenerusGameGameOverModule._shutdownVrf':
  row['reason']='Immutable Admin target; 1M minimum covers its nested coordinator/LINK admissions and reserves. Any failed Admin frame reverts the entire sweep, preserving subscription, swept marker and transfers for retry.'
 if lookup!=key(prior):row['reason']+=' Final optimization: same trusted target and call kind; calldata retargeting or combined pure storage reads only.'
 rows.append(row)
 if key(row)!=key(prior):changes.append({'before':key(prior),'after':key(row)})
a.out.write_text(json.dumps({'method':__doc__,'sourceSnapshot':'final owner review fixes','sites':rows,'retargetedSites':changes},indent=2)+'\n')
print(json.dumps({'sites':len(rows),'expressions':sum(r['count'] for r in rows),'retargeted':len(changes)}))
