// Compare the two compiled Game liveness implementations using local Geth state overrides.
import fs from 'node:fs';
import {JsonRpcProvider, id, toBeHex, zeroPadValue} from 'ethers';
const [rpc, directory, artifactPath] = process.argv.slice(2);
if (!artifactPath) throw new Error('usage: liveness-variant-gas.js LOCAL_RPC VARIANT_DIRECTORY GAME_ARTIFACT');
process.on('uncaughtException', error => { console.error(error.error?.message || error.shortMessage || error.message); process.exit(1); });
const provider = new JsonRpcProvider(rpc);
if ((await provider.getNetwork()).chainId !== 1337n) throw new Error('Local chain 1337 required');
const target = '0x000000000000000000000000000000000000bEEF';
const from = await (await provider.getSigner(0)).getAddress();
const layout = JSON.parse(fs.readFileSync(artifactPath)).storageLayout.storage;
const word = n => zeroPadValue(toBeHex(n),32);
function state(values) {
  const words = {};
  for (const [name,value] of Object.entries(values)) {
    const row=layout.find(r=>r.label===name); if(!row) throw new Error(name);
    words[row.slot]=(words[row.slot]||0n) | (BigInt(value)<<BigInt(row.offset*8));
  }
  return Object.fromEntries(Object.entries(words).map(([slot,value])=>[word(BigInt(slot)),word(value)]));
}
const cases = [
  ['before-deadline',{purchaseStartDay:99,dailyIdx:99,level:1},false],
  ['past-deadline-caught-up',{purchaseStartDay:1,dailyIdx:99,level:1},true],
  ['past-deadline-gap',{purchaseStartDay:1,dailyIdx:98,level:1},false],
  ['jackpot',{purchaseStartDay:1,dailyIdx:99,level:1,jackpotPhaseFlag:1},false],
  ['deadman',{purchaseStartDay:1,dailyIdx:69,level:1},true],
];
const results=[];
for(const [label,values,expected] of cases) {
  const pair={label,expected};
  for(const variant of ['inline','helper']) {
    const input=JSON.parse(fs.readFileSync(`${directory}/${variant}-input.json`));
    if(!/DEPLOY_DAY_BOUNDARY = 0;/.test(input.sources['contracts/ContractAddresses.sol'].content)) throw new Error('Probe expects production epoch zero');
    const output=JSON.parse(fs.readFileSync(`${directory}/${variant}-output.json`));
    const code='0x'+output.contracts['contracts/DegenerusGame.sol'].DegenerusGame.evm.deployedBytecode.object;
    const transaction={from,to:target,gas:'0xf4240',data:id('livenessTriggered()').slice(0,10)};
    const options={stateOverrides:{[target]:{code,state:state(values)}},blockOverrides:{time:toBeHex(99*86400+82620+300)},disableMemory:true,disableStorage:true};
    const cold=await provider.send('debug_traceCall',[transaction,'latest',options]);
    if(cold.failed || Boolean(BigInt('0x'+cold.returnValue.replace(/^0x/,'')))!==expected) throw new Error(`${label} ${variant}: invalid result`);
    const slots=[...new Set(cold.structLogs.filter(l=>l.op==='SLOAD').map(l=>'0x'+l.stack.at(-1).replace(/^0x/,'').padStart(64,'0')))];
    const warm=await provider.send('debug_traceCall',[{...transaction,accessList:[{address:target,storageKeys:slots}]},'latest',options]);
    if(warm.failed || warm.returnValue!==cold.returnValue) throw new Error(`${label} ${variant}: warm mismatch`);
    // Access-list intrinsic overhead is equal for both variants; compare the paired values.
    pair[variant]={coldGas:cold.gas,warmAccessListGas:warm.gas,storageKeys:slots.length};
  }
  pair.inlineMinusHelper={cold:pair.inline.coldGas-pair.helper.coldGas,warm:pair.inline.warmAccessListGas-pair.helper.warmAccessListGas};
  results.push(pair);
}
fs.writeFileSync(`${directory}/gas-results.json`,JSON.stringify({client:await provider.send('web3_clientVersion',[]),cases:results},null,2)+'\n');
console.log(JSON.stringify(results,null,2));
