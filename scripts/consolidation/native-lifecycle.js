// Stateful native execution from an actual fresh deployment. No protocol storage is seeded:
// overrides contain only state changes returned by the native client's previous transactions.
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import {JsonRpcProvider, Interface, toQuantity, keccak256, AbiCoder} from 'ethers';

const [rpc, directory] = process.argv.slice(2);
assert(['localhost','127.0.0.1'].includes(new URL(rpc).hostname));
const provider = new JsonRpcProvider(rpc);
assert.equal((await provider.getNetwork()).chainId,1337n);
const manifest=JSON.parse(fs.readFileSync(path.join(directory,'deployment.json')));
const artifacts=Object.assign({},...Object.values(JSON.parse(fs.readFileSync(path.join(directory,'output.json'))).contracts));
const interfaces=Object.fromEntries(Object.entries(artifacts).map(([name,a])=>[name,new Interface(a.abi)]));
const game=manifest.predicted.GAME.toLowerCase(), vrf=manifest.mockAddresses.MockVRFCoordinator.toLowerCase();
const sender=manifest.deployer.toLowerCase();
const purchases=JSON.parse(fs.readFileSync(path.join(directory,'purchase-receipts.json')));
// The deployment state persists at the current tip. Pin it before simulating;
// a dev node configured with period 0 does not prune it with empty blocks.
const base=await provider.send('eth_blockNumber',[]);
const originalBlock=await provider.send('eth_getBlockByNumber',[base,false]);
const pinnedSource=JSON.parse(fs.readFileSync(path.join(directory,'input.json'))).sources['contracts/ContractAddresses.sol'].content;
const boundary=Number(pinnedSource.match(/DEPLOY_DAY_BOUNDARY\s*=\s*(\d+)/)[1]);
let time=Number(BigInt(originalBlock.timestamp))+12, number=Number(BigInt(base))+1;
const state={}, rows=[], counts={}, days=[];
const abi=AbiCoder.defaultAbiCoder();
const out=path.join(directory,'lifecycle.json');
function save(extra={}) {
  fs.writeFileSync(out,JSON.stringify({client:manifest.client,baseBlock:base,method:'Native eth_simulateV1 and debug_traceCall diffMode chained from mined deployment; protocol state is never seeded or runtime-overridden. Calendar advances through block overrides. Dependencies are deployment mocks.',
    rows,counts,days,...extra},(_,v)=>typeof v==='bigint'?v.toString():v,2));
}
function block(){return {number:toQuantity(number),time:toQuantity(time),baseFeePerGas:'0x0'};}
async function execute(label,target,name,fn,args=[],value=0n,commit=true) {
  const tx={from:sender,to:target,data:interfaces[name].encodeFunctionData(fn,args),value:toQuantity(value),gas:toQuantity(500_000_000),gasPrice:'0x0'};
  const result=(await provider.send('eth_simulateV1',[{blockStateCalls:[{blockOverrides:block(),stateOverrides:state,calls:[tx]}],validation:false},base])).at(-1);
  const call=result.calls[0];
  if(call.status!=='0x1') {save({failure:{label,fn,call,time,number}});throw Error(`${label}: ${JSON.stringify(call.error)} ${call.returnData}`);}
  if(!commit) return interfaces[name].decodeFunctionResult(fn,call.returnData);
  const delta=await provider.send('debug_traceCall',[tx,base,{blockOverrides:block(),stateOverrides:state,tracer:'prestateTracer',tracerConfig:{diffMode:true}}]);
  for(const [address,account] of Object.entries(delta.pre)) {
    state[address]??={stateDiff:{}};
    for(const slot of Object.keys(account.storage??{})) if(!(slot in (delta.post[address]?.storage??{}))) state[address].stateDiff[slot]='0x'+'00'.repeat(32);
  }
  for(const [address,account] of Object.entries(delta.post)) {
    state[address]??={stateDiff:{}};
    for(const key of ['balance','nonce','code']) if(key in account) state[address][key]=typeof account[key]==='number'?toQuantity(account[key]):account[key];
    Object.assign(state[address].stateDiff,account.storage??{});
  }
  const events=[];
  for(const log of call.logs??[]) {
    for(const iface of [interfaces.DegenerusGame,interfaces.DegenerusGameBoxModule,interfaces.Coinflip]) {
      try {const parsed=iface.parseLog(log);if(parsed){events.push(parsed.name);counts[parsed.name]=(counts[parsed.name]??0)+1;break;}}catch{}
    }
  }
  rows.push({label,target,function:fn,time,number,gas:BigInt(call.gasUsed),blockGasUsedMaxDimension:BigInt(result.gasUsed),events});
  number++;time+=12;save();
  return call;
}
const read=async(fn,args=[]) => (await execute('view',game,'DegenerusGame',fn,args,0n,false))[0];
async function crank(day) {
  for(let i=0;i<200;i++) {
    const action=Number(await read('nextMinerAction'));
    if(action===0)return;
    if(action===2) {
      const id=(await execute('view',vrf,'MockVRFCoordinator','lastRequestId',[],0n,false))[0];
      assert(id>0n,'Wait requires an actual VRF request');
      const word=BigInt(keccak256(abi.encode(['uint256','uint256'],[day,number])))|1n;
      await execute('vrfFulfill',vrf,'MockVRFCoordinator','fulfillRandomWords',[id,word]);
    } else await execute(`mineFlip:${action}`,game,'DegenerusGame','mineFlip',[0]);
  }
  throw Error('Lifecycle crank did not reach idle within 200 calls');
}
try {
  await execute('fundSubscription',vrf,'MockVRFCoordinator','fundSubscription',[1,1000n*10n**18n]);
  await crank(1);
  for(let day=2;day<=24;day++) {
    time=(boundary+day-1)*86400+82620+600;
    await crank(day);
    const price=await read('mintPrice');
    let tickets=400n;
    if(day>=9) {
      const target=await read('prizePoolTargetView'), next=await read('nextPrizePoolView');
      const need=target>next?(target-next)*2n+10n**18n:10n**18n;
      tickets=(need/price+1n)*400n;
    }
    const boxValue=100_000_000_000_000_000n, box=(100n<<9n)|(3n<<7n)|1n;
    await execute('purchase',game,'DegenerusGame','purchase',[0,tickets,box,'0x'+'00'.repeat(32),0,false],price*tickets/400n+boxValue);
    if(day<=8) {
      const credit=await read('degenesisCreditOf',[sender]);
      const amount=credit<10n**16n?credit:10n**16n;
      assert(amount>0n,'Degenesis purchase needs earned credit');
      await execute('buyDegenesisBox',game,'DegenerusGame','buyDegenesisBox',[0,amount],amount);
    }
    time+=6*3600;await crank(day);
    const claimable=await read('claimableWinningsOf',[sender]);
    if(claimable>1n) await execute('claimWinnings',game,'DegenerusGame','claimWinnings(uint32)',[0]);
    const level=await read('level');days.push({day,level,claimableBeforeClaim:claimable});save();
    if(level>=1n && (counts.LootBoxOpened??0)>0 && rows.some(r=>r.label==='claimWinnings'))break;
  }
  const level=await read('level');
  assert(level>=1n,'No level transition');
  assert((counts.LootBoxOpened??0)>0,'No boxes opened');
  assert(rows.some(r=>r.label==='claimWinnings'),'No positive claim');
  assert(rows.some(r=>r.label==='buyDegenesisBox'),'No Degenesis purchase');
  save({passed:true,finalLevel:level,finalStateAccounts:Object.keys(state).length});
  console.log(JSON.stringify({passed:true,transactions:rows.length,finalLevel:level.toString(),boxes:counts.LootBoxOpened,claims:rows.filter(r=>r.label==='claimWinnings').length}));
} catch(error) {save({passed:false,error:error.error?.message??error.shortMessage??error.message});console.error(error.error?.message??error.shortMessage??error.message);process.exitCode=1;}
