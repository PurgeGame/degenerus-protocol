#!/usr/bin/env python3
"""Replay Lane A exported prestates on a local native Glamsterdam client, without transactions."""
import argparse, hashlib, importlib.util, json
from pathlib import Path

spec=importlib.util.spec_from_file_location('benchmark',Path(__file__).resolve().parents[1]/'audit/benchmark-storage-reuse.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)
meter_spec=importlib.util.spec_from_file_location('native_meter',Path(__file__).with_name('native-gas-meter.py'))
gas_meter=importlib.util.module_from_spec(meter_spec);meter_spec.loader.exec_module(gas_meter)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--rpc',required=True);p.add_argument('--fixtures',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
a=p.parse_args()
assert int(b.rpc(a.rpc,'eth_chainId',[]),16) in (1337,31337),'local dev chain only'
block=b.rpc(a.rpc,'eth_getBlockByNumber',['0x0',False]);rows=[]
miner_topic=b.topic('MinerWork(address,uint8,uint256,uint256)')
bounty_topic=b.topic('MinerBounty(uint8,address,uint256)')
stake_topic=b.topic('CoinflipStakeUpdated(uint32,uint24,uint256,uint256)')

def normalize(logs,case,positive=True):
 logs=[{k:l[k].lower() if isinstance(l[k],str) else [t.lower() for t in l[k]] for k in ['address','data','topics']} for l in logs]
 meter=None
 if case in ('vault_miner_checkpoint_76','human_miner_reward_100','human_miner_reward_300','battle_first_checkpoint'):
  work=[l for l in logs if l['topics'][0]==miner_topic];assert len(work)==1
  fields=[int(work[0]['data'][2+i:2+i+64],16) for i in range(0,192,64)]
  action,used,reward=fields
  # Both fixtures start at their request timestamp, with no miner pass and a 1 gwei basefee.
  # Vault: locked, level 0. Human FIFO: unlocked, active ticket level 100 (0.24 ETH).
  human=case.startswith('human_miner_reward_')
  price,multiplier=(24*10**16,3000) if human else (8*10**16,6000) if case=='battle_first_checkpoint' else (10**16,6000)
  expected=max(1,(used-1_000_000)*500_000_000*1000*multiplier//(price*10_000)) if used>1_000_000 else 0
  if human and positive: assert expected>0,'positive-reward fixture must remain non-vacuous'
  assert reward==expected,(used,reward,expected)
  meter={'action':action,'executionGas':used,'rewardFlip':reward,'rewardFormula':'PASS'}
  work[0]['data']='0x'+b.word(action)[2:]+'<gas><reward>'
  bounty=[i for i,l in enumerate(logs) if l['topics'][0]==bounty_topic]
  if reward:
   assert len(bounty)==1
   i=bounty[0];assert int(logs[i]['data'][-64:],16)==reward
   logs[i]['data']=logs[i]['data'][:-64]+'<reward>'
   assert logs[i-1]['topics'][0]==stake_topic
   assert logs[i-1]['data']=='0x'+b.word(reward)[2:]*2,'new miner stake must equal measured bounty'
   logs[i-1]['data']='<reward><reward>'
  else:assert not bounty
 return logs,meter

def work_logs(logs,meter):
 # A gas-bounded native call may finish a shorter, committed prefix. Only the
 # independently checked miner credit at the end is removed for that comparison.
 if not meter:return logs
 return logs[:-3] if meter['rewardFlip'] else logs[:-1]

for file in sorted(a.fixtures.glob('*.call.json')):
 case=file.name.removesuffix('.call.json');call=json.loads(file.read_text());dump=json.loads((a.fixtures/(case+'.state.json')).read_text());state={}
 for address,v in dump.get('accounts',dump).items():
  state[address.lower()]={'code':v.get('code','0x'),'balance':hex(int(v.get('balance','0x0'),16)),'nonce':hex(int(v.get('nonce',0))),'state':{b.word(int(k,16)):b.word(int(x,16)) for k,x in v.get('storage',{}).items()}}
 sender=call['from'].lower();state.setdefault(sender,{'code':'0x','state':{},'nonce':'0x1'})['balance']=hex(10**30)
 bo={'time':hex(call['timestamp']),'baseFeePerGas':hex(call.get('baseFee',0))}
 def tx(gas):return {'from':sender,'to':call['to'],'input':call['input'],'gas':hex(gas),'gasPrice':hex(call.get('baseFee',0))}
 def simulate_block(gas):
  params=[{'blockStateCalls':[{'blockOverrides':bo,'stateOverrides':state,'calls':[tx(gas)]}],'validation':False},block['number']]
  return b.rpc(a.rpc,'eth_simulateV1',params)[0]
 def simulate(gas):return simulate_block(gas)['calls'][0]
 for profile,limit in [('no-reservoir',16_777_216),('reservoir',500_000_000)]:
  native_block=simulate_block(limit);result=native_block['calls'][0]
  assert int(result['status'],16)==1,(case,profile,result)
  options={'blockOverrides':bo,'stateOverrides':state,'tracer':'prestateTracer'}
  prestate=b.rpc(a.rpc,'debug_traceCall',[tx(limit),block['number'],options])
  for address,account in prestate.items():
   exported=state.get(address.lower(),{})
   assert account.get('code','0x').lower()==exported.get('code','0x').lower(),(case,address,'uncovered code')
   for slot,value in account.get('storage',{}).items():
    assert slot in exported.get('state',{}) and int(value,16)==int(exported['state'][slot],16),(case,address,slot,'uncovered storage')
  options['tracer']='callTracer'
  trace=b.rpc(a.rpc,'debug_traceCall',[tx(limit),block['number'],options])
  assert 'error' not in trace,(case,profile,trace.get('error'))
  assert result['returnData']==call['expectedReturn'],case
  actual,meter=normalize(result['logs'],case);expected,expected_meter=normalize(json.loads(call['expectedLogs']),case)
  same=actual==expected
  if not same:
   assert case.startswith('human_miner_reward_'),(case,'ordered native logs differ')
   committed=work_logs(actual,meter);reference=work_logs(expected,expected_meter)
   assert committed and committed==reference[:len(committed)],(case,'native work is not an exact committed prefix')
  row={'case':case,'profile':profile,'suppliedGas':limit,
   'targetKind':'test-host worker probe' if case=='vault_checkpoint_76' else 'production entry',
   'gasUsed':int(result['gasUsed'],16),'maxUsedGas':int(result['maxUsedGas'],16),
   'blockGasUsedMaxDimension':int(native_block['gasUsed'],16),'callTracerGasUsed':int(trace['gasUsed'],16),
   'returnAndOrderedLogs':'PASS' if same else 'PASS: exact committed work prefix',
   'workLogs':len(work_logs(actual,meter)),'referenceWorkLogs':len(work_logs(expected,expected_meter)),
   'prestateCoverage':'PASS','prestateSha256':hashlib.sha256(json.dumps(state,sort_keys=True).encode()).hexdigest()}
  options['tracer']=gas_meter.METER
  measured=b.rpc(a.rpc,'debug_traceCall',[tx(limit),block['number'],options])
  native_gas=gas_meter.measured_gas(measured,limit)
  row['nativeGasMeter']=native_gas
  row['nativeFrameGas']=native_gas['grossFrameUpperBound' if profile=='no-reservoir' else 'frameExecutionBudgetConsumed']
  if meter:
   charged=native_gas['frameExecutionBudgetConsumed']
   assert meter['executionGas']<=charged,(case,profile,'miner exceeds independently measured native charged gas')
   meter['nativeComparisonGas']=charged
   meter['nativeComparisonDimension']='root execution-budget consumption before refunds'
   assert meter['executionGas']<=row['callTracerGasUsed'],(case,profile,'miner exceeds native call expenditure')
   meter['nativeUndercount']='PASS';row['miner']=meter
  rows.append(row);print(json.dumps(row),flush=True)
 # Admission boundaries use the finite execution-only profile. The reservoir
 # sample above separately verifies native execution accounting and preserved work.
 result=simulate(16_777_216)
 assert result['returnData']==call['expectedReturn'],case
 actual,meter=normalize(result['logs'],case);expected,_=normalize(json.loads(call['expectedLogs']),case)
 row=rows[-2]
 if meter:
  lo,hi=21_000,16_777_216
  while hi-lo>1000:
   mid=(lo+hi)//2
   if int(simulate(mid)['status'],16)==1:hi=mid
   else:lo=mid
  admitted=simulate(hi)
  admitted_logs,admitted_meter=normalize(admitted['logs'],case,positive=False)
  row['admission']={'lastFailedGas':lo,'firstSuccessfulGas':hi,'resolutionGas':1000,
   'sameFullEffects':admitted['returnData']==result['returnData'] and admitted_logs==actual,
   'miner':admitted_meter}
  if not row['admission']['sameFullEffects']:
   # A successful bounded worker may commit a shorter prefix. Measure full effects
   # separately so the first admitted transaction is never advertised as completion.
   full_lo,full_hi=hi,16_777_216
   while full_hi-full_lo>1000:
    mid=(full_lo+full_hi)//2;sample=simulate(mid)
    complete=int(sample['status'],16)==1 and sample['returnData']==result['returnData'] and normalize(sample['logs'],case,positive=False)[0]==actual
    if complete:full_hi=mid
    else:full_lo=mid
   row['fullEffects']={'lastDifferentGas':full_lo,'firstMatchingGas':full_hi,'resolutionGas':1000}
assert rows,'no fixtures'
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps({'client':b.rpc(a.rpc,'web3_clientVersion',[]),'method':'Native eth_simulateV1, prestateTracer and callTracer under both profiles, with gasPrice matching basefee in every trace. Every accessed code/slot is covered. Miner rewards use an independent formula and must undercount native charged gas (root frame execution-budget consumption measured by opcode tracer in both profiles) and call expenditure. Human FIFO may commit an exact shorter prefix; all other ordered logs and all returns are exact.','cases':rows},indent=2)+'\n')
