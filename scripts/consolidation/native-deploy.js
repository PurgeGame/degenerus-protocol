import { usesAffiliateBootstrap } from "../lib/deploymentManifest.js";
// Local native-client deployment. Prepare first; compile input.json with pinned solc, then deploy.
// node scripts/consolidation/native-deploy.js prepare|deploy RPC_URL EVIDENCE_DIRECTORY
import fs from 'node:fs';
import { selectProfile } from '../lib/selectProfile.js';
import path from 'node:path';
import { JsonRpcProvider, Contract, ContractFactory, getCreateAddress, keccak256, encodeBytes32String } from 'ethers';
import { DEPLOYMENTS, PROFILE } from '../lib/deploymentManifest.js';
import { predictAddresses, computeDeployDayBoundary, reserveDeploymentNonces } from '../lib/predictAddresses.js';
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
const optional = process.env.NATIVE_DEPLOY_OPTIONS === 'true';
const runtimeLimit = PROFILE === 'eip170' ? 24576 : 65536;
const initcodeLimit = PROFILE === 'eip170' ? 49152 : 131072;
const transactionGas = PROFILE === 'eip170' ? 16_777_216 : 500_000_000;
const mocks = ['MockVRFCoordinator','MockStETH','MockLinkToken','MockLinkEthFeed', ...(optional ? ['NativeEnsRegistrar'] : [])];
fs.mkdirSync(directory, { recursive: true });
if (mode === 'prepare') {
  selectProfile();
  const nonce = await provider.getTransactionCount(deployer, 'pending');
  const block = await provider.getBlock('latest');
  fs.cpSync('contracts', path.join(directory,'contracts'), { recursive: true });
  const mockAddresses = Object.fromEntries(mocks.map((name,i)=>[name,getCreateAddress({from:deployer,nonce:nonce+i})]));
  const predicted = predictAddresses(deployer, nonce + mocks.length);
  const pin = path.join(directory,'contracts/ContractAddresses.sol');
  const external = { CREATOR: deployer, VRF_COORDINATOR:mockAddresses.MockVRFCoordinator, STETH_TOKEN:mockAddresses.MockStETH };
  if (optional) external.ENS_REVERSE_REGISTRAR = mockAddresses.NativeEnsRegistrar;
  patchContractAddresses(predicted, external, computeDeployDayBoundary(block.timestamp), '0x'+'ab'.repeat(32), pin);
  function sources(dir, prefix) {
    return Object.fromEntries(fs.readdirSync(dir,{withFileTypes:true}).flatMap(e => e.isDirectory() ? Object.entries(sources(path.join(dir,e.name),`${prefix}/${e.name}`)) : e.name.endsWith('.sol') ? [[`${prefix}/${e.name}`,{content:fs.readFileSync(path.join(dir,e.name),'utf8')}]] : []));
  }
  const input = {language:'Solidity',sources:sources(path.join(directory,'contracts'),'contracts'),settings:{viaIR:true,optimizer:{enabled:true,runs:1000},evmVersion:'osaka',outputSelection:{'*':{'*':['abi','evm.bytecode.object','evm.deployedBytecode.object']}}}};
  if (optional) input.sources['test/NativeEnsRegistrar.sol'] = {content: `// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
contract NativeEnsRegistrar {
  mapping(address => string) public names;
  function setName(string calldata name) external returns (bytes32) {
    names[msg.sender] = name; return keccak256(bytes(name));
  }
}`};
  fs.writeFileSync(path.join(directory,'input.json'),JSON.stringify(input));
  fs.writeFileSync(path.join(directory,'deployment.json'),JSON.stringify({client,chainId:chain.chainId.toString(),deployer,nonce,external,predicted:Object.fromEntries(predicted),mockAddresses,optional},null,2));
  console.log('Prepared pinned native-client compiler input; no transactions submitted.');
} else {
  const manifest = JSON.parse(fs.readFileSync(path.join(directory,'deployment.json')));
  if (Boolean(manifest.optional) !== optional) throw new Error('Deployment option differs from prepared compiler input');
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
    if(artifact.evm.deployedBytecode.object.length/2>runtimeLimit || (initcode.length-2)/2>initcodeLimit) throw new Error(`Size limit (${PROFILE}): ${name}`);
    const contract=await factory.deploy(...args,{gasLimit:transactionGas});
    const receipt=await contract.deploymentTransaction().wait();
    const address=await contract.getAddress();
    if(address.toLowerCase()!==expected.toLowerCase()) throw new Error(`Address divergence: ${key}`);
    const native=await provider.send('eth_getTransactionReceipt',[receipt.hash]);
    const runtime = await provider.getCode(address);
    const trace = await provider.send('debug_traceTransaction', [receipt.hash, {tracer:'callTracer'}]);
    if (trace.output?.toLowerCase() !== runtime.toLowerCase()) throw new Error(`Constructor runtime divergence: ${key}`);
    receipts.push({key,name,address,predicted:expected,runtimeCodeHash:keccak256(runtime),initcodeHash:keccak256(initcode),
      runtimeBytes:runtime.length/2-1,initcodeBytes:(initcode.length-2)/2,constructorReturnMatches:true,receipt:native});
    fs.writeFileSync(path.join(directory,'receipts.json'),JSON.stringify({client,chainId:chain.chainId.toString(),receipts},null,2));
    contracts[key]=contract;
    console.log(`${key}: gasUsed=${receipt.gasUsed} ${address}`);
  }
  for(const name of mocks) await deploy(name,name,name==='MockLinkEthFeed'?[4_000_000_000_000_000n]:[],manifest.mockAddresses[name]);
  for(const row of DEPLOYMENTS) {
    await reserveDeploymentNonces(signer,row.key,manifest.nonce+mocks.length);
    const affiliateArgs = optional ? [[deployer],[encodeBytes32String('P7B')],[10],['0x000000000000000000000000000000000000b007'],[encodeBytes32String('P7B')]] : [[],[],[],[],[]];
    await deploy(row.key,row.contract,row.key==='ICONS_32'?[true]:row.bootstrap?affiliateArgs:[],manifest.predicted[row.key]);
  }
  for(const row of DEPLOYMENTS) for(const alias of row.aliases) contracts[alias]=contracts[row.key];
  const shares=[];
  for (const [nonce,symbol] of [[1,'DGVF'],[2,'DGVE']]) {
    const address=getCreateAddress({from:manifest.predicted.VAULT,nonce});
    const share=new Contract(address,artifacts.DegenerusVaultShare.abi,signer);
    const supply=await share.totalSupply();
    if (await share.symbol()!==symbol || supply===0n || await share.balanceOf(deployer)!==supply) throw new Error(`Vault share bootstrap: ${symbol}`);
    shares.push({address,symbol,supply:supply.toString(),runtimeCodeHash:keccak256(await provider.getCode(address))});
  }
  fs.writeFileSync(path.join(directory,'vault-shares.json'),JSON.stringify(shares,null,2));
  if (optional) {
    const code=await contracts.AFFILIATE.affiliateCode(encodeBytes32String('P7B'));
    if (code[0]!==deployer || code[1]===0n || code[2]!==10n) throw new Error('Affiliate bootstrap mismatch');
    const ens=[];
    for (const [address,expected] of [[manifest.predicted.VAULT,'vault.degenerus.eth'],[shares[0].address,'dgvf.degenerus.eth'],[shares[1].address,'dgve.degenerus.eth'],[manifest.predicted.ADMIN,'admin.degenerus.eth']]) {
      const actual=await contracts.NativeEnsRegistrar.names(address);
      if(actual!==expected) throw new Error(`ENS bootstrap mismatch: ${address}`);
      ens.push({address,expected,actual});
    }
    fs.writeFileSync(path.join(directory,'optional-bootstrap.json'),JSON.stringify({affiliate:{owner:code[0],ownerId:code[1].toString(),kickback:code[2].toString()},ens},null,2));
  }
  stage = 'deity-bootstrap';
  const genesis=await (await contracts.GAME.initProtocolDeity({gasLimit:transactionGas})).wait();
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
    const sample = await (await contracts.GAME.purchaseOrderFor(0,400,box,'0x'+'00'.repeat(32),0,foil,{value,gasLimit:transactionGas})).wait();
    purchases.push({label,receipt:await provider.send('eth_getTransactionReceipt',[sample.hash])});
    fs.writeFileSync(path.join(directory,'purchase-receipts.json'),JSON.stringify(purchases,null,2));
    console.log(`${label}: gasUsed=${sample.gasUsed}`);
  }
  stage = 'complete';
  fs.writeFileSync(path.join(directory,'complete.json'), JSON.stringify({stage, client, chainId:chain.chainId.toString(),deployed:receipts.length,purchases:purchases.length,vaultShares:shares.length,optional},null,2));
  console.log('Native deployment, deity bootstrap, production icons and purchase passed.');
}
