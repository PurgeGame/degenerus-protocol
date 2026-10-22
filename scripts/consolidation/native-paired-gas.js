// Read-only baseline/candidate comparisons at one identical native state snapshot.
// Compile baseline-input.json with the deployment's identical address pins first.
import fs from 'node:fs';
import path from 'node:path';
import {JsonRpcProvider, toQuantity} from 'ethers';

const [rpc, directory, baselineRoot] = process.argv.slice(2);
if (!rpc || !directory) throw new Error('usage: native-paired-gas.js LOCAL_RPC DEPLOYMENT_DIRECTORY [BASELINE_ROOT_TO_PREPARE]');
process.on('uncaughtException', error => {
  console.error(error.error?.message || error.shortMessage || error.message);
  process.exit(1);
});
const provider = new JsonRpcProvider(rpc);
if ((await provider.getNetwork()).chainId !== 1337n) throw new Error('Local chain 1337 required');
const read = name => JSON.parse(fs.readFileSync(`${directory}/${name}.json`));
const deployments = read('receipts').receipts;
if (baselineRoot) {
  const input = read('input');
  const pins = input.sources['contracts/ContractAddresses.sol'];
  function sources(folder, prefix) {
    return Object.fromEntries(fs.readdirSync(folder,{withFileTypes:true}).flatMap(entry => {
      const file = path.join(folder,entry.name), name = `${prefix}/${entry.name}`;
      return entry.isDirectory() ? Object.entries(sources(file,name)) : entry.name.endsWith('.sol') ? [[name,{content:fs.readFileSync(file,'utf8')}]] : [];
    }));
  }
  input.sources = sources(path.join(baselineRoot,'contracts'),'contracts');
  input.sources['contracts/ContractAddresses.sol'] = pins;
  input.settings.outputSelection = {};
  for (const row of deployments) {
    if (row.name !== 'DegenerusGame' && !row.name.endsWith('Module')) continue;
    const file = `contracts/${row.name === 'DegenerusGame' ? '' : 'modules/'}${row.name}.sol`;
    input.settings.outputSelection[file] = {[row.name]:['evm.deployedBytecode.object']};
  }
  fs.writeFileSync(`${directory}/baseline-input.json`,JSON.stringify(input));
  console.log('Prepared baseline input with identical native pins; compile to baseline-output.json, then rerun without BASELINE_ROOT.');
  process.exit(0);
}
const baseline = read('baseline-output');
const errors = (baseline.errors || []).filter(e => e.severity === 'error');
if (errors.length) throw new Error(errors.map(e => e.formattedMessage).join('\n'));
const artifacts = Object.assign({}, ...Object.values(baseline.contracts));
const overrides = {};
for (const row of deployments) {
  if (row.name !== 'DegenerusGame' && !row.name.endsWith('Module')) continue;
  const code = artifacts[row.name]?.evm.deployedBytecode.object;
  if (!code || !/^[0-9a-f]+$/i.test(code)) throw new Error(`Missing baseline runtime: ${row.name}`);
  overrides[row.address] = {code: '0x' + code};
}
if (Object.keys(overrides).length !== 18) throw new Error('Expected Game plus 17 baseline modules');
const results = [];
const context = await provider.send('eth_getBlockByNumber', ['latest', false]);
const block = context.number;
const firstBuyer = '0x000000000000000000000000000000000000beef';
for (const purchase of read('purchase-receipts')) {
  const tx = await provider.send('eth_getTransactionByHash', [purchase.receipt.transactionHash]);
  // The deployment signer already owns this level's Foil pack. A fresh buyer keeps
  // that probe admissible without editing protocol storage.
  const from = ['first-ticket','ticket-and-foil'].includes(purchase.label) ? firstBuyer : tx.from;
  const funding = {[from]:{balance:toQuantity(1000n * 10n ** 18n)}};
  const call = {from, to:tx.to, data:tx.input, value:tx.value, gas:tx.gas, gasPrice:context.baseFeePerGas};
  const options = {blockOverrides:{number:context.number, time:context.timestamp, baseFeePerGas:context.baseFeePerGas}};
  const access = new Map();
  // Build one union access list so both variants pay the same intrinsic access-list cost.
  for (const stateOverrides of [{...overrides,...funding}, funding]) {
    const prestate = await provider.send('debug_traceCall', [call, block, {...options, stateOverrides, tracer:'prestateTracer'}]);
    for (const [address, account] of Object.entries(prestate)) {
      const keys = access.get(address) || new Set();
      for (const slot of Object.keys(account.storage || {})) keys.add(slot);
      access.set(address, keys);
    }
  }
  const accessList = [...access].sort(([a],[b])=>a.localeCompare(b)).map(([address,keys])=>({address,storageKeys:[...keys].sort()}));
  const result = {label:purchase.label, block, inputTransactionHash:tx.hash, from,
    earlierCandidateReceiptGas:Number(BigInt(purchase.receipt.gasUsed)), accessListAccounts:accessList.length,
    accessListSlots:accessList.reduce((n,a)=>n+a.storageKeys.length,0)};
  for (const [name,stateOverrides] of [['baseline',{...overrides,...funding}],['candidate',funding]]) {
    result[name] = {};
    for (const warm of [false,true]) {
      const trace = await provider.send('debug_traceCall', [warm ? {...call,accessList} : call, block,
        {...options,stateOverrides,tracer:'callTracer',tracerConfig:{onlyTopCall:true,withLog:true}}]);
      if (trace.error) throw new Error(`${purchase.label} ${name}: ${trace.error} (${trace.output || '0x'})`);
      result[name][warm ? 'warmAccessListGas' : 'coldGas'] = Number(BigInt(trace.gasUsed));
      result[name][warm ? 'warmOutput' : 'coldOutput'] = trace.output || '0x';
    }
  }
  if (result.baseline.coldOutput !== result.candidate.coldOutput || result.baseline.warmOutput !== result.candidate.warmOutput)
    throw new Error(`${purchase.label}: return mismatch`);
  result.saving = {cold:result.baseline.coldGas-result.candidate.coldGas,
    warmAccessList:result.baseline.warmAccessListGas-result.candidate.warmAccessListGas};
  results.push(result);
}
fs.writeFileSync(`${directory}/paired-gas.json`, JSON.stringify({
  client:await provider.send('web3_clientVersion',[]), baselineRuntimeOverrides:18,
  method:'Native Amsterdam debug_traceCall at one identical post-deployment state and block context. First-ticket and Foil use a fresh buyer; repeat-ticket and box use the deployer. Both sides receive the same balance override. Warm cases use a common union access list. Geth gasUsed includes native intrinsic costs; earlier candidate receipts are separate observations at different state. Constructors/bootstrap are common candidate state.',
  results}, null, 2)+'\n');
console.log(JSON.stringify(results,null,2));
