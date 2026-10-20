#!/usr/bin/env node
/** Owner governance CLI. Amounts and ETH values are integer base units (wei). */
import fs from "node:fs";
import {parseArgs} from "node:util";
import {Contract, Interface, JsonRpcProvider, Wallet, ZeroAddress, getAddress} from "ethers";
import {readOwnerProposalAction} from "./lib/ownerProposal.js";
import {controlledOwnerPositions} from "./lib/ownerDirect.js";

const {values, positionals} = parseArgs({allowPositionals: true, options: Object.fromEntries(
  ["rpc", "governance", "owner", "owners", "from-block", "proposal", "target", "data", "value", "amount", "delegate"].map(k => [k, {type: "string"}])
)});
const command = positionals[0];
const valid = ["inspect", "approve", "deposit", "set-delegate", "propose", "support", "clear", "withdraw", "execute", "direct", "direct-action"];
if (!valid.includes(command)) {
  console.error(`Usage: node scripts/owner-governance.js <${valid.join("|")}> --governance ADDRESS [--rpc URL] [options]\nAmounts/value: base units. Writes require PRIVATE_KEY. No delegation grants token allowances to the delegate.`);
  process.exit(1);
}
function integer(name, fallback) {
  const raw = values[name] ?? fallback;
  if (raw === undefined || !/^\d+$/.test(raw)) throw new Error(`--${name} must be an unsigned integer`);
  return BigInt(raw);
}
function calldata() {
  const data = values.data;
  if (!data || !/^0x(?:[0-9a-fA-F]{2}){4,}$/.test(data)) throw new Error("--data must contain complete ABI calldata");
  return data;
}
function abi(name) {
  const paths = [`artifacts/contracts/${name}.sol/${name}.json`, `forge-out/${name}.sol/${name}.json`];
  const file = paths.find(p => fs.existsSync(p));
  if (!file) throw new Error(`Compile contracts first: no ${name} ABI`);
  return JSON.parse(fs.readFileSync(file)).abi;
}
const provider = new JsonRpcProvider(values.rpc ?? process.env.RPC_URL ?? "http://127.0.0.1:8545");
const address = getAddress(values.governance ?? process.env.OWNER_GOVERNANCE_ADDRESS ?? "");
const read = new Contract(address, abi("DegenerusOwnerGovernance"), provider);
const stringify = value => JSON.stringify(value, (_, v) => typeof v === "bigint" ? v.toString() : v, 2);
const token = new Contract(await read.dgve(), [
  "function totalSupply() view returns(uint256)", "function balanceOf(address) view returns(uint256)",
  "function allowance(address,address) view returns(uint256)", "function approve(address,uint256) returns(bool)",
], provider);
if (command === "inspect") {
  // Pin all reads to the same block so a newly mined block cannot make the totals disagree.
  const block = await provider.getBlock("latest");
  const at = {blockTag: block.number};
  const report = {governance: address, block: block.number, dgve: await token.getAddress(), supply: await token.totalSupply(at), totalEscrowed: await read.totalEscrowed(at)};
  report.custodyNote = "Use deposit/propose/support to escrow DGVE. Direct token transfers create no position or votes and cannot be recovered.";
  if (values.owner) {
    const owner = getAddress(values.owner);
    const p = await read.positions(owner, at);
    report.position = {owner, proposalId: p.proposalId, amount: p.amount, assignedBlock: p.assignedBlock, depositBlock: p.depositBlock, votingDelegate: p.votingDelegate,
      directPlayerEligible: p.amount > 0n && p.depositBlock < BigInt(block.number),
      state: p.amount === 0n ? "absent" : p.proposalId === 0n ? "idle" : p.assignedBlock === BigInt(block.number) ? "current-block support" : "settled support",
      walletBalance: await token.balanceOf(owner, at), allowanceToGovernance: await token.allowance(owner, address, at)};
  }
  if (values.proposal) {
    const id = integer("proposal"); const p = await read.proposal(id, at);
    const action = await readOwnerProposalAction(read, id, p, block);
    report.proposal = {id, proposer: p.proposer, target: p.target, value: p.value, dataHash: p.dataHash, ...action,
      expiresAt: p.expiresAt, lockedWeight: p.lockedWeight,
      settledWeight: await read.settledWeight(id, at), currentBlockSupport: p.recentBlock === BigInt(block.number) ? p.recentWeight : 0n,
      recentBlock: p.recentBlock, recentWeight: p.recentWeight,
      executed: p.executed, approvalSuffices: await read.canExecute(id, at)};
  }
  console.log(stringify(report));
} else {
  if (!process.env.PRIVATE_KEY) throw new Error("PRIVATE_KEY is required for a transaction");
  const signer = new Wallet(process.env.PRIVATE_KEY, provider);
  const gov = read.connect(signer);
  const owner = getAddress(values.owner ?? signer.address);
  let tx;
  switch (command) {
    case "approve": tx = await token.connect(signer).approve(address, integer("amount")); break;
    case "deposit": tx = await gov.deposit(integer("amount"), getAddress(values.delegate ?? ZeroAddress)); break;
    case "set-delegate": tx = await gov.setVotingDelegate(getAddress(values.delegate ?? ZeroAddress)); break;
    case "propose": {
      const target = getAddress(values.target ?? ""); const data = calldata();
      console.log(stringify({owner, target, value: integer("value", "0"), data}));
      tx = await gov.propose(owner, target, integer("value", "0"), data, integer("amount", "0")); break;
    }
    case "support": tx = await gov.support(owner, integer("proposal"), integer("amount", "0")); break;
    case "clear": tx = await gov.clearVote(owner); break;
    case "withdraw": tx = await gov.withdraw(); break;
    case "execute": {
      const id = integer("proposal"); const p = await gov.proposal(id);
      const action = await readOwnerProposalAction(gov, id, p);
      console.log(stringify({id, target: p.target, value: p.value, dataHash: p.dataHash, ...action}));
      tx = await gov.execute(id, action.data, {value: p.value}); break;
    }
    case "direct":
    case "direct-action": {
      const data = calldata();
      const candidates = values.owners ?? values.owner;
      const selection = await controlledOwnerPositions(read, signer.address, {
        owners: candidates?.split(",").map(a => a.trim()), fromBlock: Number(integer("from-block", "0")),
      });
      const value = integer("value", "0");
      console.log(stringify({data, ...selection, supply: await token.totalSupply({blockTag: selection.block}), suppliedEth: value}));
      tx = await gov.directAction(data, selection.owners, {value}); break;
    }
  }
  const receipt = await tx.wait();
  console.log(stringify({transactionHash: receipt.hash, status: receipt.status}));
  for (const log of receipt.logs) {
    try { const event = new Interface(abi("DegenerusOwnerGovernance")).parseLog(log); if (event) console.log(event.name, stringify(event.args)); } catch {}
  }
}
