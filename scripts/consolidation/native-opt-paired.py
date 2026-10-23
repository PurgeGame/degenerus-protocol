#!/usr/bin/env python3
"""Pair unmodified compiler runtimes on native Amsterdam at identical exported prestates.

Only samples whose storage reads are covered by the exported prestate are accepted.
The old census supplies inputs, not a claim of a fresh candidate lifecycle replay.
"""
import argparse
from collections import Counter, defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time
import urllib.request
from urllib.parse import urlparse

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before', type=Path, required=True)
p.add_argument('--after', type=Path, required=True)
p.add_argument('--dataset', type=Path, required=True)
p.add_argument('--out', type=Path, required=True)
p.add_argument('--per-label', type=int, default=4)
p.add_argument('--rng-change', action='store_true')
p.add_argument('--frames', action='store_true', help='Also report native client call-frame gas by function')
p.add_argument('--rpc', default='http://127.0.0.1:19653')
a=p.parse_args();a.out.mkdir(parents=True,exist_ok=True)
assert urlparse(a.rpc).hostname in ('127.0.0.1','localhost')
def rpc(method,params):
    req=urllib.request.Request(a.rpc,json.dumps(dict(jsonrpc='2.0',id=1,method=method,params=params)).encode(),{'Content-Type':'application/json'})
    with urllib.request.urlopen(req,timeout=90) as response: result=json.load(response)
    if 'error' in result:raise RuntimeError((method,result['error']))
    return result['result']
assert int(rpc('eth_chainId',[]),16)==31337
client=rpc('web3_clientVersion',[])
codes=json.loads((a.dataset/'codes.json').read_text())
pins=dict(re.findall(r'address internal constant (\w+)\s*=\s*address\((0x[0-9a-fA-F]+)\)',Path('contracts/ContractAddresses.sol').read_text()))
deployments=json.loads(subprocess.check_output(['node','--input-type=module','-e',
    'import {DEPLOYMENTS} from "./scripts/lib/deploymentManifest.js"; console.log(JSON.stringify(DEPLOYMENTS))'],text=True))
artifacts={side:json.loads((directory/'abis.json').read_text()) for side,directory in [('before',a.before),('after',a.after)]}
targets={pins[r['key']].lower():r['contract'] for r in deployments}
selectors={side:{name:{selector:signature for signature,selector in artifact.get('evm',{}).get('methodIdentifiers',{}).items()}
    for name,artifact in contracts.items()} for side,contracts in artifacts.items()}

def frame_rows(root,side):
    rows=[]
    def walk(frame):
        address=frame.get('to','').lower();name=targets.get(address)
        if name and len(frame.get('input',''))>=10:
            rows.append({'contract':name,'function':selectors[side][name].get(frame['input'][2:10],frame['input'][:10]),
                'gas':int(frame.get('gasUsed','0x0'),16),'type':frame['type'],'failed':'error' in frame})
        for child in frame.get('calls',[]):walk(child)
    walk(root)
    return rows
overrides={side:{} for side in artifacts};changed=[]
def executable(hexcode):
    code=bytes.fromhex(hexcode)
    length=int.from_bytes(code[-2:],'big')+2
    assert length<len(code)
    return code[:-length]
for row in deployments:
    name=row['contract'];old=artifacts['before'][name]['evm']['deployedBytecode'];new=artifacts['after'][name]['evm']['deployedBytecode']
    differs = executable(old['object']) != executable(new['object'])
    if differs: changed.append(name)
    if old.get('immutableReferences') or new.get('immutableReferences'):
        if differs:
            raise AssertionError('Changed immutable runtime needs explicit constructor binding: '+name)
        # Retain the dataset's constructor bindings. All intervening optimization
        # builds leave these executable templates unchanged.
        continue
    # Install EVERY current non-immutable runtime on both sides, even if this item
    # did not change it. Dataset bytecode can predate earlier optimization items.
    address=pins[row['key']].lower()
    for side in artifacts:overrides[side][address]='0x'+artifacts[side][name]['evm']['deployedBytecode']['object']
miner=rpc('web3_sha3',['0x'+b'MinerWork(address,uint8,uint256,uint256)'.hex()])
def effects(result):
    logs=[]
    for log in result.get('logs',[]):
        if log['address'].lower()=='0xfffffffffffffffffffffffffffffffffffffffe':continue
        data=log['data']
        if log['topics'] and log['topics'][0]==miner:
            assert int(data[-64:],16)==0
            data=data[:66]+'<gas>'+data[-64:]
        logs.append([log['address'],log['topics'],data])
    return [result['status'],result.get('returnData','0x'),result.get('error',{}),logs]
def missing_reads(trace,state):
    missing=[]
    for address,account in trace.items():
        for slot in account.get('storage',{}):
            known=state.get(address,{}).get('state',{})
            key='0x'+slot.removeprefix('0x').zfill(64)
            if key not in known:missing.append([address,key])
    return missing
seen=Counter();counts=Counter();results=[];start=time.monotonic()
for line in gzip.open(a.dataset/'calls.jsonl.gz','rt'):
    row=json.loads(line);counts[row['label']]+=1
    if seen[row['label']]>=a.per_label:continue
    seen[row['label']]+=1
    base={address:{'code':codes[address],**{k:v for k,v in state.items() if k!='codeHash'}} for address,state in row['state'].items()}
    bo={'number':hex(row['number']),'time':hex(row['timestamp']),'baseFeePerGas':'0x0'}
    record={k:row[k] for k in ['seq','label','payer','success']};record['profiles']={}
    for profile,limit in [('no-reservoir',16_777_216),('reservoir',500_000_000)]:
        call={'from':row['from_'],'to':row['to'],'data':row['data'],'value':row['value'],'gas':hex(limit),'gasPrice':'0x0'}
        pair={};effect={}
        for side in ['before','after']:
            state={address:dict(s) for address,s in base.items()}
            for address,code in overrides[side].items():state[address]=dict(state.get(address,{}),code=code)
            options={'blockOverrides':bo,'stateOverrides':state,'tracer':'prestateTracer','timeout':'60s'}
            prestate=rpc('debug_traceCall',[call,'0x0',options])
            missing=missing_reads(prestate,base)
            block=rpc('eth_simulateV1',[{'blockStateCalls':[{'blockOverrides':bo,'stateOverrides':state,'calls':[call]}],'validation':False},'0x0'])[0]
            result=block['calls'][0];effect[side]=effects(result)
            pair[side]={'gas':int(result['gasUsed'],16),'maxUsedGas':int(result['maxUsedGas'],16),
                'blockExecutionGas':int(block['gasUsed'],16),'status':result['status'],
                'effectHash':hashlib.sha256(json.dumps(effect[side],sort_keys=True).encode()).hexdigest(),
                'missingPrestateSlots':missing}
            if a.frames:
                trace=rpc('debug_traceCall',[call,'0x0',dict(options,tracer='callTracer')])
                pair[side]['frames']=frame_rows(trace,side)
        pair['covered']=not pair['before']['missingPrestateSlots'] and not pair['after']['missingPrestateSlots']
        pair['effectsEqual']=effect['before']==effect['after']
        pair['saving']=pair['before']['gas']-pair['after']['gas']
        record['profiles'][profile]=pair
    results.append(record)
    if len(results)%25==0:print(len(results),'paired samples',round(time.monotonic()-start,1),'seconds',flush=True)
summary={}
for profile in ['no-reservoir','reservoir']:
    groups=defaultdict(list)
    for row in results:
        pair=row['profiles'][profile]
        if pair['covered']:groups[(row['payer'],row['label'])].append(pair)
    summary[profile]=[dict(payer=payer,label=label,samples=len(pairs),censusCount=counts[label],
        baselineMean=sum(p['before']['gas'] for p in pairs)/len(pairs),candidateMean=sum(p['after']['gas'] for p in pairs)/len(pairs),
        meanSaving=sum(p['saving'] for p in pairs)/len(pairs),equalEffects=sum(p['effectsEqual'] for p in pairs),
        matchedMeanSaving=(sum(p['saving'] for p in pairs if p['effectsEqual'])/sum(p['effectsEqual'] for p in pairs)
            if any(p['effectsEqual'] for p in pairs) else None))
        for (payer,label),pairs in sorted(groups.items())]
report={'client':client,'changedRuntimes':changed,'inputMethod':__doc__,'rngOutcomeChangesAllowed':a.rng_change,
        'profiles':summary,'samples':results,'counts':counts,
        'gasNote':'gas is native simulated receipt total; blockExecutionGas is the one-call block execution dimension. Refund/state decomposition is not inferred from gasleft().'}
(a.out/'paired.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps({'samples':len(results),'covered':{p:sum(r['profiles'][p]['covered'] for r in results) for p in summary},'seconds':round(time.monotonic()-start,1)}),flush=True)
assert results and all(pair['covered'] for row in results for pair in row['profiles'].values()), 'Uncovered native prestate'
if not a.rng_change:
    assert all(pair['effectsEqual'] for row in results for pair in row['profiles'].values()), 'Native effects differ'
