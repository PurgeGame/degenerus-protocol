#!/usr/bin/env python3
"""Stream exact checkpoint comparison without formatting multi-megabyte assertion errors."""
import argparse
from collections import Counter, defaultdict
import json
from pathlib import Path
import re
import subprocess

MINER = subprocess.check_output(['node','--input-type=module','-e',
    'import {id} from "ethers";console.log(id("MinerWork(address,uint8,uint256,uint256)"))'],text=True).strip()[2:]

def event(value):
    owner, encoded = value
    data=encoded[2:]
    topics=int(data[:64],16)*2
    if data[topics+64:topics+128] == MINER:
        at=int(data[64:128],16)*2+64
        assert int(data[at+128:at+192],16)==0, 'Only zero-basefee rewards may be normalized'
        data=data[:at+64]+'g'*64+data[at+128:]
    return owner,data

def runs(path):
    test=None;run=None
    with path.open() as file:
        for line in file:
            match=re.match(r'^\[(?:PASS|FAIL[^\]]*)\] (\w+)\(',line)
            if match:test=match[1]
            at=line.find('DIFF')
            if at<0:continue
            kind,*v=line[at:].strip().split('|')
            if kind=='DIFFNAME' and v[1]=='player:0':
                if run:yield run
                run={'test':test,'tx':[],'slots':{},'initial':{},'eth':{},'tokens':{},'events':[],
                     'checkpoints':[],'gas':defaultdict(lambda:{'count':0,'gas':0,'failed':0})}
            if run is None:continue
            if kind=='DIFFTX':
                _,label,payer,status,output,gas,from_,to=v
                run['tx'].append([label,payer,status,output,from_,to])
                row=run['gas'][label];row['count']+=1;row['gas']+=int(gas);row['payer']=payer;row['failed']+=status!='ok'
            elif kind=='DIFFSLOT':
                key=v[0]+':'+v[1];run['initial'].setdefault(key,v[3]);run['slots'][key]=v[2]
            elif kind=='DIFFETH':run['eth'][v[0]]=v[1]
            elif kind=='DIFFTOKEN':run['tokens'][v[0]+':'+v[1]]=v[2]
            elif kind=='DIFFEVENT':run['events'].append(event(v))
            elif kind=='DIFFCHECK':
                run['checkpoints'].append({'id':v[0],'action':v[1],'level':v[2],
                    'slots':run['slots'].copy(),'eth':run['eth'].copy(),'tokens':run['tokens'].copy(),'events':run['events']})
                run['events']=[]
        if run:yield run

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('before',type=Path);p.add_argument('after',type=Path);p.add_argument('out',type=Path)
    p.add_argument('--rng-inventory',action='store_true',help='Record intended RNG differences; does not certify invariant acceptance')
    a=p.parse_args();left={r['test']:r for r in runs(a.before)}
    expected={'testLongRunCensus'} | {f'test{mode}{flow}' for mode in ('Focused','Warm')
        for flow in ('Boxes','Craps','Daily','HotEntries','Purchases')}
    assert set(left)==expected, ('incomplete baseline scenarios', sorted(left))
    report={'mode':'RNG differences inventory; invariant acceptance is separate' if a.rng_inventory else 'strict', 'runs':[]}
    failures=0
    for right in runs(a.after):
        old=left.pop(right['test']);differences=Counter();examples=[]
        def difference(category,detail):
            differences[category]+=1
            if len(examples)<12:examples.append([category,detail])
        if old['tx']!=right['tx']:
            for i in range(max(len(old['tx']),len(right['tx']))):
                x=old['tx'][i] if i<len(old['tx']) else None;y=right['tx'][i] if i<len(right['tx']) else None
                if x!=y:difference('transactions',i)
        if len(old['checkpoints'])!=len(right['checkpoints']):difference('checkpoint-count',[len(old['checkpoints']),len(right['checkpoints'])])
        keys=old['initial'].keys()|right['initial'].keys()
        for index,(x,y) in enumerate(zip(old['checkpoints'],right['checkpoints'])):
            for key in keys:
                before=x['slots'].get(key,old['initial'].get(key,right['initial'].get(key)))
                after=y['slots'].get(key,right['initial'].get(key,old['initial'].get(key)))
                if before!=after:difference('slots',[index,key])
            for field in ['action','level','eth','tokens','events']:
                if x[field]!=y[field]:difference(field,index)
        if old['events']!=right['events']:difference('trailing-events',None)
        failures+=sum(differences.values())
        report['runs'].append({'test':right['test'],'baselineTransactions':len(old['tx']),'candidateTransactions':len(right['tx']),
            'baselineCheckpoints':len(old['checkpoints']),'candidateCheckpoints':len(right['checkpoints']),
            'baselineGas':old['gas'],'candidateGas':right['gas'],'differenceCounts':dict(differences),'examples':examples})
    assert not left,('missing runs',list(left))
    report['differences']=failures
    a.out.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'runs':len(report['runs']),'differences':failures,'mode':report['mode']}))
    return 0 if a.rng_inventory else bool(failures)

if __name__=='__main__':raise SystemExit(main())
