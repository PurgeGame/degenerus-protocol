#!/usr/bin/env python3
"""Attach opcode-measured nested budgets to already verified native witnesses."""
import argparse,importlib.util,json,time
from pathlib import Path
spec=importlib.util.spec_from_file_location('n',Path(__file__).with_name('native-calibration.py'));n=importlib.util.module_from_spec(spec);spec.loader.exec_module(n)
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--rpc',required=True);p.add_argument('--fixtures',type=Path,required=True);p.add_argument('--input',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
report=json.loads(a.input.read_text());done={}
if a.output.exists():done={r['label']:r for r in json.load(open(a.output))['cases']}
start=time.monotonic()
for i,row in enumerate(report['cases']):
 if not all(v['pass'] for v in row['profiles'].values()): continue
 saved=done.get(row['label'])
 if saved and saved['fixtureSha256']==row['fixtureSha256'] and saved['prestateSha256']==row['prestateSha256'] and all('frames' in v['nativeGasMeter'] for v in saved['profiles'].values()):
  row.update(saved);continue
 call=json.load(open(a.fixtures/(row['label']+'.call.json')))
 dump=json.load(open(a.fixtures/(row['label']+'.state.json')))
 state={}
 for address,value in n.dumped_accounts(dump).items():
  nonce=value.get('nonce',0)
  state[address]=dict(code=value.get('code','0x'),nonce=hex(int(nonce,16) if isinstance(nonce,str) else nonce),balance=hex(int(value.get('balance','0x0'),16)),state={n.b.word(int(k,16)):n.b.word(int(v,16)) for k,v in value.get('storage',{}).items()})
 sender=call['from'].lower();state.setdefault(sender,dict(code='0x',state={},nonce='0x1',balance='0x0'))
 bo=dict(time=hex(call['timestamp']),baseFeePerGas=hex(call.get('baseFee',0)))
 if call.get('number',0):bo['number']=hex(call['number'])
 for profile,limit in [('no-reservoir',16777216),('reservoir',500000000)]:
  prior=row['profiles'][profile]
  tx=dict(to=call['to'],data=prior['calibratedInput'],gas=hex(limit),gasPrice=hex(call.get('baseFee',0)),value=hex(int(str(call.get('value',0)),0)));tx['from']=sender
  meter=n.b.rpc(a.rpc,'debug_traceCall',[tx,'0x0',dict(blockOverrides=bo,stateOverrides=state,tracer=n.gas_meter.METER,timeout='60s')])
  gas=n.gas_meter.measured_gas(meter,limit,schedule=report['schedule'])
  for key,value in prior['nativeGasMeter'].items():
   if key!='frames':assert gas[key]==value,(row['label'],profile,key,gas[key],value)
  prior['nativeGasMeter']=gas
 if i%50==0:
  a.output.write_text(json.dumps(report));print(json.dumps(dict(cases=i+1,seconds=round(time.monotonic()-start,1))),flush=True)
a.output.write_text(json.dumps(report));print('complete',len(report['cases']),flush=True)
