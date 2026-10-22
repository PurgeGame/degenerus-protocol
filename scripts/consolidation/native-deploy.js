// Local native-client deployment. Prepare first; compile input.json with pinned solc, then deploy.
// node scripts/consolidation/native-deploy.js prepare|deploy RPC_URL EVIDENCE_DIRECTORY
import fs from 'node:fs';
import path from 'node:path';
import { JsonRpcProvider, ContractFactory, getCreateAddress } from 'ethers';
import { DEPLOYMENTS } from '../lib/deploymentManifest.js';
import { predictAddresses, computeDeployDayBoundary } from '../lib/predictAddresses.js';
import { patchContractAddresses } from '../lib/patchContractAddresses.js';
import { wireIcons32 } from '../lib/deployHelpers.js';
const [mode, rpc, directory] = process.argv.slice(2);
if (!['prepare', 'deploy'].includes(mode) || !rpc || !directory) throw new Error('usage: native-deploy.js prepare|deploy RPC_URL EVIDENCE_DIRECTORY');
let stage = 'connect';
process.on('uncaughtException', error => {
  fs.mkdirSync(directory, { recursive: true });
  fs.writeFileSync(path.join(directory, 'failure.json'), JSON.stringify({stage, message:error.error?.message || error.shortMessage || error.message, code:error.code}, null, 2));
  console.error(`Native deployment stopped at ${stage}: ${error.error?.message || error.shortMessage || error.message}`); process.exit(1);
});
const provider = new JsonRpcProvider(rpc, undefined, { polling: true, pollingInterval: 100 });
const signer = await provider.getSigner(0);
const deployer = await signer.getAddress();
const client = await provider.send('web3_clientVersion', []);
const chain = await provider.getNetwork();
if (chain.chainId !== 1337n) throw new Error('Expected the local Geth dev chain (1337)');
const mocks = ['MockVRFCoordinator','MockStETH','MockLinkToken','MockLinkEthFeed'];
fs.mkdirSync(directory, { recursive: true });
if (mode === 'prepare') {
  const nonce = await provider.getTransactionCount(deployer, 'pending');
  const block = await provider.getBlock('latest');
  fs.cpSync('contracts', path.join(directory,'contracts'), { recursive: true });
  const mockAddresses = Object.fromEntries(mocks.map((name,i)=>[name,getCreateAddress({from:deployer,nonce:nonce+i})]));
  const predicted = predictAddresses(deployer, nonce + mocks.length);
  const pin = path.join(directory,'contracts/ContractAddresses.sol');
  const external = { CREATOR: deployer, VRF_COORDINATOR:mockAddresses.MockVRFCoordinator, STETH_TOKEN:mockAddresses.MockStETH, LINK_TOKEN:mockAddresses.MockLinkToken, LINK_ETH_FEED:mockAddresses.MockLinkEthFeed };
  patchContractAddresses(predicted, external, computeDeployDayBoundary(block.timestamp), '0x'+'ab'.repeat(32), pin);
  function sources(dir, prefix) {
    return Object.fromEntries(fs.readdirSync(dir,{withFileTypes:true}).flatMap(e => e.isDirectory() ? Object.entries(sources(path.join(dir,e.name),`${prefix}/${e.name}`)) : e.name.endsWith('.sol') ? [[`${prefix}/${e.name}`,{content:fs.readFileSync(path.join(dir,e.name),'utf8')}]] : []));
  }
  const input = {language:'Solidity',sources:sources(path.join(directory,'contracts'),'contracts'),settings:{viaIR:true,optimizer:{enabled:true,runs:1000},evmVersion:'osaka',outputSelection:{'*':{'*':['abi','evm.bytecode.object','evm.deployedBytecode.object']}}}};
  fs.writeFileSync(path.join(directory,'input.json'),JSON.stringify(input));
  fs.writeFileSync(path.join(directory,'deployment.json'),JSON.stringify({client,chainId:chain.chainId.toString(),deployer,nonce,external,predicted:Object.fromEntries(predicted),mockAddresses},null,2));
  console.log('Prepared pinned native-client compiler input; no transactions submitted.');
} else {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory,'deployment.json')));
  if (manifest.deployer !== deployer || await provider.getTransactionCount(deployer,'pending') !== manifest.nonce) throw new Error('Deployer/nonce changed after compilation');
  const raw = JSON.parse(fs.readFileSync(path.join(directory,'output.json')));
  const errors = (raw.errors || []).filter(e=>e.severity==='error');
  if(errors.length) throw new Error(JSON.stringify(errors));
  const artifacts = Object.assign({},...Object.values(raw.contracts));
  const receipts=[], contracts={};
  async function deploy(key,name,args,expected) {
    stage = `deploy:${key}`;
    const artifact=artifacts[name];
    const factory=new ContractFactory(artifact.abi,'0x'+artifact.evm.bytecode.object,signer);
    const initcode=(await factory.getDeployTransaction(...args)).data;
    if(artifact.evm.deployedBytecode.object.length/2>65536 || (initcode.length-2)/2>131072) throw new Error(`Size limit: ${name}`);
    const contract=await factory.deploy(...args,{gasLimit:500_000_000});
    const receipt=await contract.deploymentTransaction().wait();
    const address=await contract.getAddress();
    if(address.toLowerCase()!==expected.toLowerCase()) throw new Error(`Address divergence: ${key}`);
    const native=await provider.send('eth_getTransactionReceipt',[receipt.hash]);
    receipts.push({key,name,address,runtimeBytes:(await provider.getCode(address)).length/2-1,initcodeBytes:(initcode.length-2)/2,receipt:native});
    fs.writeFileSync(path.join(directory,'receipts.json'),JSON.stringify({client,chainId:chain.chainId.toString(),receipts},null,2));
    contracts[key]=contract;
    console.log(`${key}: gasUsed=${receipt.gasUsed} ${address}`);
  }
  for(const name of mocks) await deploy(name,name,name==='MockLinkEthFeed'?[4_000_000_000_000_000n]:[],manifest.mockAddresses[name]);
  for(const row of DEPLOYMENTS) await deploy(row.key,row.contract,row.key==='ICONS_32'?[true]:row.key==='AFFILIATE'?[[],[],[],[],[]]:[],manifest.predicted[row.key]);
  for(const row of DEPLOYMENTS) for(const alias of row.aliases) contracts[alias]=contracts[row.key];
  stage = 'deity-bootstrap';
  const genesis=await (await contracts.GAME.initProtocolDeity({gasLimit:500_000_000})).wait();
  fs.writeFileSync(path.join(directory,'bootstrap-receipt.json'),JSON.stringify(await provider.send('eth_getTransactionReceipt',[genesis.hash]),null,2));
  stage = 'icon-bootstrap';
  await wireIcons32(contracts.ICONS_32, JSON.parse(fs.readFileSync('scripts/data/icons32Data.symbolOrder.json')), {finalize:true});
  const purchases = [];
  const price = await contracts.GAME.mintPrice();
  const customBox = (100n << 9n) | (3n << 7n) | 1n;
  for (const [label, box, foil, value] of [
    ['first-ticket',0n,false,price], ['repeat-ticket',0n,false,price],
    ['ticket-and-box',customBox,false,price + 100_000_000_000_000_000n],
    ['ticket-and-foil',0n,true,price * 11n],
  ]) {
    stage = `purchase:${label}`;
    const sample = await (await contracts.GAME.purchase(0,400,box,'0x'+'00'.repeat(32),0,foil,{value,gasLimit:50_000_000})).wait();
    purchases.push({label,receipt:await provider.send('eth_getTransactionReceipt',[sample.hash])});
    fs.writeFileSync(path.join(directory,'purchase-receipts.json'),JSON.stringify(purchases,null,2));
    console.log(`${label}: gasUsed=${sample.gasUsed}`);
  }
  stage = 'complete';
  fs.writeFileSync(path.join(directory,'complete.json'), JSON.stringify({stage, client, chainId:chain.chainId.toString(),deployed:receipts.length,purchases:purchases.length},null,2));
  console.log('Native deployment, deity bootstrap, production icons and purchase passed.');
}
