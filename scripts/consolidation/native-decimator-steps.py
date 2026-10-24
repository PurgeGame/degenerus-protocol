#!/usr/bin/env python3
"""Measure original single-step Decimator allowances on both native profiles.

The round state independently identifies runs, ranking, payments and finalization;
whole worker costs must not be mistaken for the cost of one operation.
"""
import argparse,json,pathlib,importlib.util,hashlib
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--fixtures',type=pathlib.Path,required=True);p.add_argument('--out',type=pathlib.Path,required=True);p.add_argument('--rpc',required=True);a=p.parse_args()
W=pathlib.Path(__file__).resolve().parents[2];D=a.out;D.mkdir(parents=True,exist_ok=True)
s=importlib.util.spec_from_file_location('c',W/'scripts/consolidation/native-calibration.py');c=importlib.util.module_from_spec(s);s.loader.exec_module(c);b=c.b;rpc=a.rpc
assert int(b.rpc(rpc,'eth_chainId',[]),16) in (1337,31337), 'local replay only'
F=a.fixtures;out=[]
def words(data):return [int(data[i:i+64],16) for i in range(2,len(data),64)]
for f in sorted(F.glob('decimator-*.call.json')):
 call=json.loads(f.read_text());label=f.name.removesuffix('.call.json');dump=json.loads(f.with_name(label+'.state.json').read_text());state={}
 for address,v in c.dumped_accounts(dump).items():
  nonce=v.get('nonce',0);state[address]={'code':v.get('code','0x'),'nonce':hex(int(nonce,16) if isinstance(nonce,str) else nonce),'balance':hex(int(v.get('balance','0x0'),16)),'state':{b.word(int(k,16)):b.word(int(z,16)) for k,z in v.get('storage',{}).items()}}
 bo={'time':hex(call['timestamp']),'baseFeePerGas':'0x0'}
 if call.get('number'):bo['number']=hex(call['number'])
 row={'label':label,'originalAllowance':call['workerAllowance'],'profiles':{}}
 for profile,limit in [('no-reservoir',16777216),('reservoir',500000000)]:
  try:
   tx={'from':call['from'],'to':call['to'],'data':call['input'],'gas':hex(limit),'gasPrice':'0x0'};opts={'stateOverrides':state,'blockOverrides':bo,'timeout':'60s'}
   def view(data,st):
    r=b.rpc(rpc,'debug_traceCall',[dict(tx,data=data),'0x0',dict(opts,stateOverrides=st,tracer='callTracer')]);assert not r.get('error'),r.get('error');return words(r['output'])
   lvl=view(b.topic('queue()')[:10],state)[0]&0xffffff;data=b.topic('roundOf(uint24)')[:10]+f'{lvl:064x}';before=view(data,state)
   r=b.rpc(rpc,'eth_simulateV1',[{'blockStateCalls':[{'stateOverrides':state,'blockOverrides':bo,'calls':[tx]}],'validation':False},'0x0'])[0]['calls'][0]
   assert r['status']=='0x1',r.get('error')
   delta=b.rpc(rpc,'debug_traceCall',[tx,'0x0',dict(opts,tracer='prestateTracer',tracerConfig={'diffMode':True})]);post=c.apply_delta(state,delta);after=view(data,post)
   observed=b.rpc(rpc,'debug_traceCall',[tx,'0x0',dict(opts,tracer='prestateTracer')]);missing=c.missing_prestate(observed,state,True);assert not missing,missing
   meter=b.rpc(rpc,'debug_traceCall',[tx,'0x0',dict(opts,tracer=c.gas_meter.METER)]);gas=c.gas_meter.measured_gas(meter,limit)
   kind={'runs':after[8]-before[8],'ranked':before[4]==1 and after[4]!=1,'payments':after[7]-before[7],'finalized':after[4]==3 and before[4]!=3}
   row['profiles'][profile]={'pass':True,'progressed':bool(c.result_words(r['returnData'])[0]),'gas':gas['grossFrameUpperBound' if profile=='no-reservoir' else 'frameExecutionBudgetConsumed'],'meter':gas,'before':before,'after':after,'operations':kind,'result':r['returnData'],'logs':c.events(r['logs']),'poststateSha256':hashlib.sha256(json.dumps(post,sort_keys=True).encode()).hexdigest()}
  except Exception as err:row['profiles'][profile]={'pass':False,'error':str(err)}
 out.append(row);tmp=D/'result.tmp';tmp.write_text(json.dumps(out,indent=2));tmp.replace(D/'paired.json');print(label,{p:{k:z for k,z in v.items() if k in ['pass','gas','operations','error']} for p,v in row['profiles'].items()},flush=True)
assert all(v['pass'] for row in out for v in row['profiles'].values())
