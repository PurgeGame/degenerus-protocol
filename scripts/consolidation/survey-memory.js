// Compare production entry pointers and read-only getter costs on a local Anvil.
// Prefix-only controls are diagnostics, never deployable candidate implementations.
import fs from 'node:fs';
import path from 'node:path';
import {Interface, JsonRpcProvider, toBeHex} from 'ethers';
import {DEPLOYMENTS} from '../lib/deploymentManifest.js';
const [url, beforeDir, afterDir, output] = process.argv.slice(2);
if (!output) throw Error('usage: survey-memory.js LOCAL_ANVIL BEFORE_ARTIFACTS AFTER_ARTIFACTS OUTPUT_JSON');
if (!['localhost','127.0.0.1','[::1]'].includes(new URL(url).hostname)) throw Error('Local Anvil required');
const rpc = new JsonRpcProvider(url);
if (![1337,31337].includes(Number((await rpc.getNetwork()).chainId))) throw Error('Local development chain required');
const entries = [...DEPLOYMENTS,
  {key:'DGVF',contract:'DegenerusVaultShare',source:'DegenerusVault'},
  {key:'DGVE',contract:'DegenerusVaultShare',source:'DegenerusVault'},
  {key:'GAME_LENS',contract:'DegenerusGameLens'}, {key:'CRAPS_LENS',contract:'CrapsLens'}];
const address='0x0000000000000000000000000000000000003000';
const sender='0x0000000000000000000000000000000000004000';
function load(root,e) { return JSON.parse(fs.readFileSync(path.join(root,`${e.source||e.contract}.sol`,`${e.contract}.json`))); }
function prefix(code) {
  const hex=code.replace(/^0x/,'');const size=parseInt(hex.slice(0,2),16)-0x5f;
  if(size<1||size>32)throw Error('Unexpected initial opcode');
  return {pointer:Number(BigInt('0x'+hex.slice(2,2+size*2))),control:'0x'+hex.slice(0,2)+BigInt(128).toString(16).padStart(size*2,'0')+hex.slice(2+size*2)};
}
function zero(type) {
  if(/^u?int\d*$/.test(type)) return 0n;
  if(type==='address')return '0x0000000000000000000000000000000000000000';
  if(type==='bool')return false;
  if(/^bytes\d+$/.test(type))return '0x'+'00'.repeat(Number(type.slice(5)));
  throw Error('Unsupported probe input');
}
async function probe(code,data) {
  await rpc.send('anvil_setCode',[address,code]);
  const t=await rpc.send('debug_traceCall',[{from:sender,to:address,data,gas:'0x100000'},'latest',{disableStorage:true,disableMemory:true}]);
  if(t.failed||t.returnValue.replace(/^0x/,'').length!==64)throw Error('Not a successful scalar getter');
  if(t.structLogs.some(s=>['CALL','CALLCODE','STATICCALL','DELEGATECALL','CREATE','CREATE2','SSTORE','SELFDESTRUCT'].includes(s.op)))throw Error('Probe must stay read-only in one frame');
  return {gas:Number(t.gas),result:t.returnValue,ops:t.structLogs.map(s=>s.op).join(','),mstores:t.structLogs.filter(s=>s.op==='MSTORE').map(s=>({offset:s.stack.at(-1),cost:s.gasCost}))};
}
function memoryCost(words){return 3*words+Math.floor(words*words/512);}
const rows=[];
for(const e of entries){
  const before=load(beforeDir,e),after=load(afterDir,e);const b=prefix(before.deployedBytecode.object),a=prefix(after.deployedBytecode.object);
  const row={key:e.key,contract:e.contract,before_pointer:b.pointer,after_pointer:a.pointer,
    modeled_return32_expansion_before:memoryCost(b.pointer/32+1)-memoryCost(5),
    modeled_return32_expansion_after:memoryCost(a.pointer/32+1)-memoryCost(5)};
  const candidates=before.abi.filter(f=>f.type==='function'&&['view','pure'].includes(f.stateMutability)&&f.outputs.length===1&&/^(uint\d*|int\d*|address|bool|bytes\d+)$/.test(f.outputs[0].type)&&f.inputs.length<=1);
  candidates.sort((x,y)=>(x.name==='level'?-100:x.inputs.length)-(y.name==='level'?-100:y.inputs.length));
  for(const f of candidates){
    try{
      const iface=new Interface([f]),data=iface.encodeFunctionData(f.name,f.inputs.map(i=>zero(i.type)));
      const old=await probe(before.deployedBytecode.object,data),control=await probe(b.control,data),next=await probe(after.deployedBytecode.object,data);
      if(old.result!==control.result||old.result!==next.result||old.ops!==control.ops)continue;
      Object.assign(row,{probe:iface.getFunction(f.name).format('sighash'),measured_before_gas:old.gas,
        measured_prefix_control_gas:control.gas,measured_pointer_only_saving:old.gas-control.gas,
        measured_after_gas:next.gas,measured_actual_saving:old.gas-next.gas,
        before_mstores:old.mstores,after_mstores:next.mstores});break;
    }catch{}
  }
  if(!row.probe)row.unmeasured_reason='No eligible scalar getter without another call frame';
  rows.push(row);
}
fs.writeFileSync(output,JSON.stringify({method:'Same zero-storage scalar getter in one frame. Prefix-only control lowers the free-memory pointer without removing fixed spill accesses; it isolates a memory component, not a valid general-purpose runtime. Actual candidate comparison uses unmodified compiler output. The separate 32-byte-return expansion model is not a per-call invariant.',rows},null,2)+'\n');
console.log(JSON.stringify({rows:rows.length,measured:rows.filter(r=>r.probe).length,spilling_before:rows.filter(r=>r.before_pointer>128).length,spilling_after:rows.filter(r=>r.after_pointer>128).length}));
