// Replay exported, initialized protocol states through production mineFlip on a local Geth.
// Read-only eth_call/debug_traceCall; no transactions are broadcast.
// Usage: node scripts/test-repricing-afking-rpc.mjs OUT STATE_DIR RPC REPORT [osaka|amsterdam]
// Export test/gas/AfkingRepricingFixtures.t.sol with AFKING_REPRICING_STATE_DIR and a
// test-only Foundry fs_permissions entry granting that directory read-write access.
// AFKING_RPC_FULL_CYCLE=1 follows the buy fixture through request, mock VRF callback,
// ticket generation and opening. Reported cycle gas excludes the mock callback transaction.
import fs from "node:fs";
import { createHash } from "node:crypto";
import { Interface, id, keccak256, toBeHex, zeroPadValue } from "ethers";

const [out, directory, url, report, expectedSchedule] = process.argv.slice(2);
if (!report || !["localhost", "127.0.0.1", "[::1]"].includes(new URL(url).hostname)) {
  throw new Error("Expected artifact directory, fixture directory, local RPC, and report path");
}
const artifact = JSON.parse(fs.readFileSync(`${out}/DegenerusGame.sol/DegenerusGame.json`));
const abi = new Interface(artifact.abi);
const layout = artifact.storageLayout.storage;
const word = n => zeroPadValue(toBeHex(n), 32);
const zero = word(0);
const quantity = n => `0x${BigInt(n).toString(16)}`;
const caller = "0x00000000000000000000000000000000aabbccdd";
const sha = data => createHash("sha256").update(data).digest("hex");
const purchaseTopic = id("AfkingDelivered(uint32,uint256)");
const openTopic = id("LootBoxOpened(uint32,uint48,uint256,uint24,uint32,uint256,bool)");
const spinTopic = id("BoxSpin(uint32,uint64,uint256,uint256,uint256)");
const outcomeTopics = new Set([purchaseTopic, openTopic, spinTopic]);
for (const contract of ["DegenerusGameLootboxModule", "DegenerusGameDegeneretteModule"]) {
  const data = JSON.parse(fs.readFileSync(`${out}/${contract}.sol/${contract}.json`));
  for (const fragment of new Interface(data.abi).fragments) if (fragment.type === "event"
    && /^(LootBox|BoxSpin$|EntriesQueued|PlayerCredited$)/.test(fragment.name)) outcomeTopics.add(fragment.topicHash);
}
const reservoirTracer = `{first:null,last:null,step:function(log){if(log.getDepth()==1){
  if(this.first===null)this.first=log.getGas();this.last=log.getGas()-log.getCost();}},
  fault:function(){},result:function(){return {entry:this.first,exit:this.last};}}`;
async function rpc(method, params) {
  const response = await fetch(url, { method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }) });
  const value = await response.json();
  if (value.error) throw new Error(`${method}: ${JSON.stringify(value.error)}`);
  return value.result;
}

// Verify opcode prices: merely disabling Amsterdam on a devnet build is not an Osaka control.
const storageProbes = [];
for (const original of [0, 1]) {
  const trace = await rpc("debug_traceCall", [{ to: caller, gas: quantity(10_000_000) }, "latest", {
    stateOverrides: { [caller]: { code: "0x600260005500", state: { [zero]: word(original) } } },
  }]);
  if (trace.failed) throw new Error("Storage probe failed");
  storageProbes.push({ original, gas: trace.gas, sstore: trace.structLogs.find(s => s.op === "SSTORE").gasCost });
}
const schedule = storageProbes[0].sstore === 22_100 && storageProbes[1].sstore === 5_000 ? "osaka"
  : storageProbes.every(p => p.sstore === 12_100) && storageProbes[0].gas - storageProbes[1].gas === 97_920
    ? "amsterdam" : "unknown";
if (schedule === "unknown" || expectedSchedule && schedule !== expectedSchedule) throw new Error(`Wrong schedule: ${schedule}`);

const gasLimit = schedule === "osaka" ? 16_777_216 : 60_000_000;

function field(state, game, label, bits) {
  const entry = layout.find(f => f.label === label);
  return BigInt(state[game].state[word(BigInt(entry.slot))] || zero) >> BigInt(entry.offset * 8) & ((1n << BigInt(bits)) - 1n);
}
function applyDiff(state, diff) {
  for (const address of new Set([...Object.keys(diff.pre), ...Object.keys(diff.post)])) {
    const pre = diff.pre[address] || {}, post = diff.post[address] || {};
    const account = state[address] ||= { state: {} };
    for (const slot of Object.keys(pre.storage || {})) account.state[slot] = zero;
    Object.assign(account.state, post.storage || {});
    for (const key of ["balance", "nonce", "code"]) if (post[key] !== undefined) {
      account[key] = key === "nonce" && typeof post[key] === "number" ? quantity(post[key]) : post[key];
    }
  }
}
function resultsFromTrace(trace, game) {
  const found = [];
  function visit(frame) {
    // Geth positions each log between child calls. Preserve actual event order,
    // including ETH-spin recursion, rather than walking all parent logs first.
    const calls = frame.calls || [];
    for (let i = 0; i <= calls.length; ++i) {
      for (const log of frame.logs || []) if (Number(log.position || 0) === i
        && log.address.toLowerCase() === game && outcomeTopics.has(log.topics[0])) found.push([log.topics, log.data]);
      if (i < calls.length) visit(calls[i]);
    }
  }
  visit(trace);
  return found;
}
function subscriberDigest(state, game) {
  const root = layout.find(f => f.label === "_subOf").slot;
  const idsRoot = layout.find(f => f.label === "_subscribers").slot;
  const base = BigInt(keccak256(word(BigInt(idsRoot))));
  const count = Number(field(state, game, "_subscribers", 256));
  const boxes = layout.some(f => f.label === "_subBoxCount")
    ? Number(field(state, game, "_subBoxCount", 16)) : count;
  const records = [];
  for (let i = 0; i < count; ++i) {
    const physical = i < boxes ? i : 2000 - (i - boxes);
    const packed = BigInt(state[game].state[word(base + BigInt(physical >> 3))] || zero);
    const member = packed >> BigInt((physical & 7) * 32) & 0xffffffffn;
    if (member === 0n) throw new Error("Missing member");
    const slot = keccak256(word(member) + word(BigInt(root)).slice(2));
    records.push([member.toString(), state[game].state[slot] || zero]);
  }
  return sha(JSON.stringify(records));
}

const cases = [];
const maximumBoxOutcomes = [];
for (const name of (process.env.AFKING_RPC_FULL_CYCLE ? ["full-cycle"] : ["buy", "open-max", "open-mixed-cap"])) {
  const fixture = name === "full-cycle" ? "buy" : name;
  const file = fs.readFileSync(`${directory}/${fixture}.json`);
  const metadata = JSON.parse(fs.readFileSync(`${directory}/${fixture}.meta.json`));
  const game = metadata.game.toLowerCase();
  const initial = {};
  for (const [address, account] of Object.entries(JSON.parse(file))) {
    initial[address.toLowerCase()] = { balance: account.balance, nonce: account.nonce,
      code: account.code, state: account.storage || {} };
  }
  if (initial[game].code.toLowerCase() !== artifact.deployedBytecode.object.toLowerCase()) {
    throw new Error("Exported Game runtime does not match the supplied build");
  }
  initial[caller] = { balance: quantity(10n ** 20n), state: {} };
  const block = { time: quantity(metadata.timestamp), baseFeePerGas: "0x0" };
  const vrfArtifact = JSON.parse(fs.readFileSync(`${out}/MockVRFCoordinator.sol/MockVRFCoordinator.json`));
  const vrf = Object.keys(initial).find(address => initial[address].code === vrfArtifact.deployedBytecode.object);
  const vrfAbi = new Interface(vrfArtifact.abi);
  const runs = [];
  let reference;
  for (const factor of (name === "full-cycle" ? [0, 50_000] : [0, 10_000, 50_000, 4_294_967_295])) {
    const state = structuredClone(initial);
    const calls = [], delivered = [];
    let error;
    const done = () => name === "full-cycle"
      ? field(state, game, "dailyIdx", 24) === field(state, game, "_afkingResetDay", 24)
        && (field(state, game, "rngFlagsAndNudges", 16) & 256n) !== 0n
      : name === "buy" ? field(state, game, "subsFullyProcessed", 8) !== 0n
      : field(state, game, "_pendingBoxCount", 16) === 0n;
    for (let n = 0; n < 100 && !done(); ++n) {
      if (name === "full-cycle" && (field(state, game, "rngFlagsAndNudges", 16) & (1n << 14n)) !== 0n
        && field(state, game, "rngWordCurrent", 256) <= 1n) {
        if (!vrf) throw new Error("Missing fixture VRF coordinator");
        const fulfill = { from: caller, to: vrf, gas: quantity(2_000_000), gasPrice: "0x0",
          data: vrfAbi.encodeFunctionData("fulfillRandomWords", [field(state, game, "vrfRequestId", 256), 0xC0FFEE]) };
        await rpc("eth_call", [fulfill, "latest", state, block]);
        const callback = await rpc("debug_traceCall", [fulfill, "latest", { tracer: "prestateTracer",
          tracerConfig: { diffMode: true }, stateOverrides: state, blockOverrides: block }]);
        applyDiff(state, callback);
      }
      const tx = { from: caller, to: game, gas: quantity(gasLimit), gasPrice: "0x0",
        data: abi.encodeFunctionData("mineFlip", [factor]) };
      try {
        await rpc("eth_call", [tx, "latest", state, block]);
        const trace = await rpc("debug_traceCall", [tx, "latest", { tracer: "callTracer",
          tracerConfig: { withLog: true }, stateOverrides: state, blockOverrides: block }]);
        if (trace.error) throw new Error(trace.error);
        const diff = await rpc("debug_traceCall", [tx, "latest", { tracer: "prestateTracer",
          tracerConfig: { diffMode: true }, stateOverrides: state, blockOverrides: block }]);
        let newSlots = 0, writtenSlots = 0;
        for (const [address, account] of Object.entries(diff.post)) for (const [slot, value] of Object.entries(account.storage || {})) {
          ++writtenSlots;
          if (BigInt(value) !== 0n && BigInt(state[address]?.state?.[slot] || zero) === 0n) ++newSlots;
        }
        const executionReservoir = await rpc("debug_traceCall", [tx, "latest", { tracer: reservoirTracer,
          stateOverrides: state, blockOverrides: block }]);
        calls.push({ gas: Number(BigInt(trace.gasUsed)), executionReservoir, newSlots, writtenSlots,
          netNewSlotStateGas: schedule === "amsterdam" ? newSlots * 97_920 : 0 });
        delivered.push(...resultsFromTrace(trace, game));
        const before = JSON.stringify(Object.entries(state).map(([address, account]) => [address, account.state]));
        applyDiff(state, diff);
        if (!done() && before === JSON.stringify(Object.entries(state).map(([address, account]) => [address, account.state]))) throw new Error("No checkpoint progress");
      } catch (e) { error = e.message; break; }
    }
    const digest = subscriberDigest(state, game);
    const outcomeDigest = sha(JSON.stringify(delivered));
    if (!error && !done()) error = "Did not finish within 100 calls";
    if (error && factor !== 0) throw new Error(`${name}, factor ${factor}: ${error}`);
    if (!error) {
      reference ??= [digest, outcomeDigest];
      if (digest !== reference[0] || outcomeDigest !== reference[1]) throw new Error(`${name}: calibration changed subscriber state or ordered delivery events`);
    }
    runs.push({ factor, calls, completed: done(), digest, outcomeDigest, deliveredEvents: delivered.length, error });
  }
  if (name === "open-max") {
    const root = BigInt(keccak256(word(BigInt(layout.find(f => f.label === "_subscribers").slot))));
    const member = BigInt(initial[game].state[word(root)]) & 0xffffffffn;
    const day = field(initial, game, "dailyIdx", 24);
    const rng = layout.find(f => f.label === "rngWordCurrent");
    const seedFor = value => BigInt(keccak256(word(value) + word(member).slice(2)
      + word(0x41666b696e67426f78n).slice(2) + word(day).slice(2)));
    let winningEthSpin = false;
    let candidate = 2n;
    for (let roll = 0; roll < 20 || !winningEthSpin; ++roll) {
      if (roll > 83) throw new Error("No funded ETH-spin recursion exercised");
      const desired = Math.min(roll, 19);
      while (Number(seedFor(candidate) >> 40n & 0xffffn) % 20 !== desired) ++candidate;
      const state = structuredClone(initial);
      state[game].state[word(BigInt(rng.slot))] = word(candidate);
      const tx = { from: caller, to: game, gas: quantity(gasLimit), gasPrice: "0x0",
        data: abi.encodeFunctionData("mineFlip", [4_294_967_295]) };
      const trace = await rpc("debug_traceCall", [tx, "latest", { tracer: "callTracer",
        tracerConfig: { withLog: true }, stateOverrides: state, blockOverrides: block }]);
      if (trace.error) throw new Error(`Maximum box roll ${desired}: ${trace.error}`);
      const events = resultsFromTrace(trace, game);
      const ethWin = events.some(([topics, data]) => topics[0] === spinTopic
        && (BigInt("0x" + data.slice(2, 66)) >> 60n & 7n) === 2n
        && BigInt("0x" + data.slice(130, 194)) > 0n);
      winningEthSpin ||= ethWin;
      const diff = await rpc("debug_traceCall", [tx, "latest", { tracer: "prestateTracer",
        tracerConfig: { diffMode: true }, stateOverrides: state, blockOverrides: block }]);
      let newSlots = 0;
      for (const [address, account] of Object.entries(diff.post)) for (const [slot, value] of Object.entries(account.storage || {})) {
        if (BigInt(value) !== 0n && BigInt(state[address]?.state?.[slot] || zero) === 0n) ++newSlots;
      }
      const executionReservoir = await rpc("debug_traceCall", [tx, "latest", { tracer: reservoirTracer,
        stateOverrides: state, blockOverrides: block }]);
      applyDiff(state, diff);
      if (field(state, game, "_pendingBoxCount", 16) !== 0n) throw new Error("Maximum box did not checkpoint");
      maximumBoxOutcomes.push({ roll: desired, word: candidate.toString(), gas: Number(BigInt(trace.gasUsed)),
        executionReservoir, newSlots, netNewSlotStateGas: schedule === "amsterdam" ? newSlots * 97_920 : 0, ethWin });
      ++candidate;
    }
  }
  // Deliberately starve the complete public first-operation path. The transaction must revert.
  const starved = { from: caller, to: game, gas: quantity(50_000), gasPrice: "0x0",
    data: abi.encodeFunctionData("mineFlip", [4_294_967_295]) };
  const failed = await rpc("debug_traceCall", [starved, "latest", { tracer: "callTracer",
    stateOverrides: initial, blockOverrides: block }]);
  if (!failed.error) throw new Error("Underfunded first operation unexpectedly succeeded");
  const rolledBack = await rpc("debug_traceCall", [starved, "latest", { tracer: "prestateTracer",
    tracerConfig: { diffMode: true }, stateOverrides: initial, blockOverrides: block }]);
  if (Object.values(rolledBack.post).some(a => Object.keys(a.storage || {}).length)) throw new Error("Failed transaction persisted storage");
  cases.push({ name, fixtureSha256: sha(file), timestamp: metadata.timestamp, runs, underfundedRollback: true });
  console.log(`${name}: ${runs.map(r => `${r.factor}=${r.completed ? r.calls.length + " calls" : r.error}`).join(", ")}`);
}
const result = { client: await rpc("web3_clientVersion", []), schedule, storageProbes,
  runnerSha256: sha(fs.readFileSync(new URL(import.meta.url))),
  gasLimit, gameRuntimeSha256: sha(artifact.deployedBytecode.object), cases, maximumBoxOutcomes };
fs.writeFileSync(report, JSON.stringify(result, null, 2) + "\n");
