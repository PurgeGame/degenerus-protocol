import fs from 'node:fs';
import assert from 'node:assert/strict';
import { AbiCoder, Interface } from 'ethers';
const [left, right, abiFile, output] = process.argv.slice(2);
if (!output) throw new Error('usage: compare-replay.js BASELINE_LOG CANDIDATE_LOG BASELINE_CONTRACTS_JSON OUTPUT_JSON');
const abis = JSON.parse(fs.readFileSync(abiFile));
const byTopic = new Map();
const anonymous = new Map();
for (const contract of Object.values(abis)) for (const f of new Interface(contract.abi).fragments) {
  if (f.type !== 'event') continue;
  if (f.anonymous) { anonymous.set(f.format('full'), {fragment:f, iface:new Interface([f])}); continue; }
  const variants = byTopic.get(f.topicHash) || new Map();
  variants.set(f.format('full'), { fragment:f, iface:new Interface([f]) });
  byTopic.set(f.topicHash, variants);
}
const spent = new Interface(['event DegenesisVaultSpent(uint32 indexed recipientId,uint256 cost)']);
const spentEvent = spent.getEvent('DegenesisVaultSpent');
byTopic.set(spentEvent.topicHash, new Map([[spentEvent.format('full'), {fragment:spentEvent, iface:spent}]]));
const abi = AbiCoder.defaultAbiCoder();
export function parse(text) {
  const runs = [], names = new Map();
  let run, tx;
  for (const line of text.split('\n')) {
    const start = line.indexOf('DIFF');
    if (start < 0) continue;
    const [kind, ...p] = line.slice(start).trim().split('|');
    if (kind === 'DIFFNAME') {
      if (p[1] === 'player:0') {
        run = { transactions: [], checkpoints: [], slots: {}, initial: {}, eth: {}, tokens: {}, events: [], edges: {}, gas: {} };
        runs.push(run);
      }
      names.set(p[0].toLowerCase(), p[1]); continue;
    }
    if (kind === 'DIFFTX') {
      if (!run) {
        run = { transactions: [], checkpoints: [], slots: {}, initial: {}, eth: {}, tokens: {}, events: [], edges: {}, gas: {} };
        runs.push(run);
      }
      if (!run) throw new Error('Observation before first transaction');
      tx = { sequence: +p[0], label: p[1], payer: p[2], status: p[3], result: p[4], gas: +p[5], from: p[6], to: p[7] };
      run.transactions.push(tx);
      const g = run.gas[p[1]] ||= { count: 0, gas: 0, payer: p[2], failed: 0 };
      ++g.count; g.gas += tx.gas; if (tx.status !== 'ok') ++g.failed;
    } else if (kind === 'DIFFSLOT') {
      const key = `${p[0]}:${p[1]}`;
      run.initial[key] ??= p[3]; run.slots[key] = p[2];
    } else if (kind === 'DIFFETH') run.eth[p[0]] = p[1];
    else if (kind === 'DIFFTOKEN') run.tokens[`${p[0]}:${p[1]}`] = p[2];
    else if (kind === 'DIFFEVENT') {
      const [topics, data] = abi.decode(['bytes32[]', 'bytes'], p[1]);
      const variants = byTopic.get(topics[0]) || (p[0] === 'Game' ? anonymous : null);
      if (!variants) throw new Error(`Unknown event ${topics[0]}`);
      // ERC20 and ERC721 Transfer/Approval share a signature but use different
      // indexed fields. Match the complete wire layout, never the first ABI topic.
      const decoded = [];
      for (const {fragment, iface} of variants.values()) {
        if (fragment.inputs.filter(i => i.indexed).length + (fragment.anonymous ? 0 : 1) !== topics.length) continue;
        try {
          const event = fragment.anonymous
            ? {name:fragment.name,signature:fragment.format('sighash'),args:iface.decodeEventLog(fragment,data,[...topics])}
            : iface.parseLog({topics:[...topics],data});
          const encoded = iface.encodeEventLog(fragment, event.args);
          if (encoded.data === data && JSON.stringify(encoded.topics) === JSON.stringify([...topics])) decoded.push(event);
        } catch { /* incompatible indexed/data layout */ }
      }
      const layouts = new Map(decoded.map(e => [JSON.stringify([...e.args], (_,v)=>typeof v==='bigint'?v.toString():v), e]));
      if (layouts.size !== 1) throw new Error(`Ambiguous or invalid event layout ${p[0]} ${topics[0]} (${layouts.size})`);
      const event = [...layouts.values()][0];
      function normalize(v) {
        if (typeof v === 'bigint') return v.toString();
        if (Array.isArray(v)) return v.map(normalize);
        return typeof v === 'string' && /^0x[0-9a-fA-F]{40}$/.test(v) ? (names.get(v.toLowerCase()) || v.toLowerCase()) : v;
      }
      const args = [...event.args].map(normalize);
      if (event.name === 'MinerWork') {
        assert.equal(args[3], '0', 'basefee=0 workload must not pay a miner reward');
        args[2] = '<executionGas>'; // only gas-derived field excluded in this workload
      }
      let signature = event.signature;
      if (event.name === 'DegenesisVaultSpent') {
        assert.equal(p[0], 'Game');
        assert.equal(tx.label, 'degenesis-vault-spend');
        if (signature === 'DegenesisVaultSpent(uint256)') args.unshift('1');
        else assert.equal(signature, 'DegenesisVaultSpent(uint32,uint256)');
        assert.equal(args[0], '1', 'replay spending is a Vault self-purchase');
        signature = 'DegenesisVaultSpent(uint32,uint256)';
      }
      run.events.push({ emitter: p[0], signature, args });
    } else if (kind === 'DIFFEDGE') {
      const key = p.join(':'); run.edges[key] = (run.edges[key] || 0) + 1;
      run.edgesByLabel ||= {};
      const labelKey = `${tx.label}|${key}`;
      run.edgesByLabel[labelKey] = (run.edgesByLabel[labelKey] || 0) + 1;
    } else if (kind === 'DIFFCHECK') {
      run.checkpoints.push({ id: +p[0], action: p[1], level: p[2], slots: { ...run.slots }, eth: { ...run.eth }, tokens: { ...run.tokens }, events: run.events.splice(0) });
    }
  }
  if (!runs.length || runs.some(r => !r.checkpoints.length)) throw new Error('No complete checkpoint evidence');
  return runs;
}
export function differences(a, b) {
  const errors = [];
  const same = (category, x, y) => { try { assert.deepEqual(y, x); } catch { errors.push(category); } };
  same('run count', a.length, b.length);
  for (let i = 0; i < Math.min(a.length, b.length); ++i) {
    const x = a[i], y = b[i];
    same(`run ${i} checkpoints`, x.checkpoints.length, y.checkpoints.length);
    // Player calls and all return/revert payloads remain strict; worker chunking may only change at cohort checkpoints.
    const calls = r => r.transactions.map(({ gas, sequence, ...t }) => t);
    same(`run ${i} top-level results`, calls(x), calls(y));
    const keys = new Set([...Object.keys(x.initial), ...Object.keys(y.initial)]);
    for (let c = 0; c < Math.min(x.checkpoints.length, y.checkpoints.length); ++c) {
      const p = x.checkpoints[c], q = y.checkpoints[c];
      for (const key of keys) {
        const xv = p.slots[key] ?? x.initial[key] ?? y.initial[key];
        const yv = q.slots[key] ?? y.initial[key] ?? x.initial[key];
        if (xv !== yv) errors.push(`run ${i} checkpoint ${c} slot ${key}: ${xv} -> ${yv}`);
      }
      for (const field of ['action', 'level', 'eth', 'tokens', 'events']) same(`run ${i} checkpoint ${c} ${field}`, p[field], q[field]);
    }
    same(`run ${i} trailing events`, x.events, y.events);
  }
  return errors;
}
const a = parse(fs.readFileSync(left, 'utf8')), b = parse(fs.readFileSync(right, 'utf8'));
const errors = differences(a, b);
const proofs = {};
assert.deepEqual(differences(a, structuredClone(a)), []);
proofs.self = 'PASS';
for (const mutation of ['slot', 'payout', 'event', 'revert']) {
  const bad = structuredClone(a), r = bad[0];
  if (mutation === 'slot') { const c = r.checkpoints.find(c => Object.keys(c.slots).length); c.slots[Object.keys(c.slots)[0]] = '0x1234'; }
  if (mutation === 'payout') r.checkpoints[0].eth[Object.keys(r.checkpoints[0].eth)[0]] = '12345';
  if (mutation === 'event') { const c = r.checkpoints.find(c => c.events.length); c.events[0].args[0] = 'altered'; }
  if (mutation === 'revert') r.transactions[0].result = '0x12345678';
  assert(differences(a, bad).length, `Undetected ${mutation}`);
  proofs[mutation] = 'DETECTED';
}
const forbidden = [
  ['mod:Mint', 'purchase(uint32,uint256,uint256,bytes32,uint8)'],
  ['mod:Mint', 'borrow(uint32,uint24,uint256,uint256)'], ['mod:Mint', 'repay(uint32)'],
  ['mod:Mint', 'createSmurf(bytes32,uint8)'], ['mod:Mint', 'raiseSmurfBaseAllowance(uint32,uint16)'],
  ['mod:Mint', 'sweepAccounts(uint32[])'], ['mod:Mint', 'redeemFlip(uint32,uint256)'],
  ['mod:Mint', 'withdrawAfkingFunding(uint32,uint256)'],
  ['mod:Boon', 'consumePurchaseBoost(uint32)'],
  ['mod:Lootbox', 'beginBoxOrder(uint32,uint256)'], ['mod:Lootbox', 'applyBoxOrderScore(uint256,uint256)'],
  ['mod:Ticket', 'registerWallet(address,bool)'], ['mod:Ticket', 'registerWalletIdentity(address)'],
  ['mod:Afking', 'recordAfkingSecondary(uint32,uint16)'], ['mod:Afking', 'floorAfkingStreakBase(uint32,uint16)'],
];
const edges = forbidden.map(([name, sig]) => {
  const selector = new Interface([`function ${sig}`]).getFunction(sig).selector;
  return { name, signature: sig, baseline: a.reduce((n,r)=>n+(r.edges[`${name}:${selector}`]||0),0), candidate: b.reduce((n,r)=>n+(r.edges[`${name}:${selector}`]||0),0) };
});
assert(edges.every(e => e.candidate === 0), 'Candidate still delegates through an eliminated edge');
const adapterSelector = new Interface(['function purchaseWith(uint32,uint256,uint256,bytes32,uint8,uint256,uint32)']).getFunction('purchaseWith').selector;
const adapterEdges = ['foil-ticket-and-floor-hook', 'create-smurf'].map(label => ({label,
  baseline:a.reduce((n,r)=>n+(r.edgesByLabel?.[`${label}|mod:Mint:${adapterSelector}`]||0),0),
  candidate:b.reduce((n,r)=>n+(r.edgesByLabel?.[`${label}|mod:Mint:${adapterSelector}`]||0),0),
}));
for (const e of adapterEdges) {
  if (e.label === 'foil-ticket-and-floor-hook') assert.equal(e.candidate,e.baseline,'Foil must retain its explicit-value Mint adapter');
  else assert.equal(e.candidate,0,'Smurf creation must use the internal explicit-value helper');
}
const report = { differences: errors, proofs, removedEdges: edges, adapterEdges, runs: a.map((r,i) => ({ transactions: r.transactions.length, checkpoints: r.checkpoints.length, slots: Object.keys(r.initial).length, baselineGas: r.gas, candidateGas: b[i]?.gas })) };
fs.writeFileSync(output, JSON.stringify(report, null, 2)+'\n');
console.log(JSON.stringify({ differences: errors.length, firstDifferences: errors.slice(0,10), proofs, removedEdges: edges, runs: report.runs.map(({ baselineGas,candidateGas,...r })=>r) }, null, 2));
if (errors.length) process.exitCode = 1;
