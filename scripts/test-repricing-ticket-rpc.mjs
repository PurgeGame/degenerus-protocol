// Run the production ticket worker on a local client's real gas schedule.
// Uses eth_call/debug_traceCall state overrides only; never broadcasts a transaction.
// Usage: node scripts/test-repricing-ticket-rpc.mjs OUT RPC [REPORT] [BASELINE_OUT] [osaka|amsterdam]
import fs from "node:fs";
import { createHash } from "node:crypto";
import { Interface } from "ethers";

const [out, rpcUrl, report, baselineOut, expectedSchedule] = process.argv.slice(2);
if (!out || !rpcUrl) throw new Error("Expected artifact directory and local RPC URL");
if (!["localhost", "127.0.0.1", "[::1]"].includes(new URL(rpcUrl).hostname)) {
  throw new Error("Use a local development client");
}
const artifact = JSON.parse(fs.readFileSync(`${out}/TicketCheckpointDeterminism.t.sol/TicketCheckpointHarness.json`));
const abi = new Interface(artifact.abi);
const target = "0x0000000000000000000000000000000000aabbcc";
const zero = `0x${"0".repeat(64)}`;
let overrides = { [target]: { code: artifact.deployedBytecode.object, state: {} } };
async function rpc(method, params) {
  const response = await fetch(rpcUrl, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
  });
  const result = await response.json();
  if (result.error) throw new Error(`${method}: ${JSON.stringify(result.error)}`);
  return result.result;
}
function call(method, args, gas = 60_000_000) {
  return { to: target, data: abi.encodeFunctionData(method, args), gas: `0x${gas.toString(16)}` };
}
async function read(method, args = []) {
  return abi.decodeFunctionResult(method, await rpc("eth_call", [call(method, args), "latest", overrides]));
}
async function step(method, args, gas = 60_000_000) {
  const tx = call(method, args, gas);
  const output = abi.decodeFunctionResult(method, await rpc("eth_call", [tx, "latest", overrides]));
  const diff = await rpc("debug_traceCall", [tx, "latest", {
    tracer: "prestateTracer", tracerConfig: { diffMode: true }, stateOverrides: overrides,
  }]);
  for (const address of new Set([...Object.keys(diff.pre), ...Object.keys(diff.post)])) {
    const pre = diff.pre[address] || {}, post = diff.post[address] || {};
    const account = overrides[address] ||= { state: {} };
    for (const key of Object.keys(pre.storage || {})) account.state[key] = zero;
    Object.assign(account.state, post.storage || {});
    for (const key of ["balance", "nonce", "code"]) {
      if (post[key] !== undefined) account[key] = key === "nonce" ? `0x${post[key].toString(16)}` : post[key];
    }
  }
  return output;
}
// Devnet builds can replace pricing outside their fork switch. Verify opcodes,
// rather than trusting a container name or configured activation timestamp.
const storageProbes = [];
for (const original of [0, 1]) {
  const trace = await rpc("debug_traceCall", [{ to: target, gas: "0xf42400" }, "latest", {
    stateOverrides: { [target]: { code: "0x600260005500", state: {
      [zero]: `0x${original.toString(16).padStart(64, "0")}`,
    } } },
  }]);
  if (trace.failed) throw new Error("Storage schedule probe failed");
  storageProbes.push({ original, traceGas: trace.gas,
    sstoreGasCost: trace.structLogs.find(step => step.op === "SSTORE").gasCost });
}
const schedule = storageProbes[0].sstoreGasCost === 22_100 && storageProbes[1].sstoreGasCost === 5_000
  ? "osaka" : storageProbes.every(probe => probe.sstoreGasCost === 12_100)
    && storageProbes[0].traceGas - storageProbes[1].traceGas === 97_920 ? "amsterdam" : "unknown";
if (schedule === "unknown" || (expectedSchedule && schedule !== expectedSchedule)) {
  throw new Error(`Unexpected storage schedule: ${schedule}; ${JSON.stringify(storageProbes)}`);
}
await step("initialize", [1]);
// More than one aligned solo group, with a fractional tail.
await step("credit", ["0x0000000000000000000000000000000000010000", 1, 64075]);
await step("commit", [0x12902fc2cb1a37n, false]);
const initial = structuredClone(overrides);
const runs = [];
for (const factor of [50_000n, 4_294_967_295n]) {
  overrides = structuredClone(initial);
  const budget = (1n << 255n) | (factor << 192n) | (1n << 224n) | 16_000_000n;
  let done = false, calls = 0;
  for (; calls < 100 && !done; ++calls) {
    const [result] = await step("runTicketWork", [2, budget]);
    if (!result.progressed && !result.done) throw new Error("No mandatory progress");
    done = result.done;
  }
  if (!done) throw new Error("Ticket drain stalled");
  const [digest, count] = await read("digest", [1]);
  const [control] = await read("control");
  runs.push({ factor: factor.toString(), calls, digest, count: count.toString(), control });
}
if (runs[0].digest !== runs[1].digest || runs[0].control !== runs[1].control) {
  throw new Error("Calibration changed ticket outcomes");
}
// Verify the callback's separately supplied 300k limit against the real facade.
const game = JSON.parse(fs.readFileSync(`${out}/DegenerusGame.sol/DegenerusGame.json`));
const gameAbi = new Interface(game.abi);
const coordinator = "0x000000000000000000000000000000000000f00d";
const callbacks = [];
for (const daily of [false, true]) {
  const state = {};
  function seed(label, value) {
    const field = game.storageLayout.storage.find(f => f.label === label);
    if (!field) throw new Error(`Missing layout field ${label}`);
    const slot = `0x${BigInt(field.slot).toString(16).padStart(64, "0")}`;
    const packed = BigInt(state[slot] || 0) | (BigInt(value) << BigInt(field.offset * 8));
    state[slot] = `0x${packed.toString(16).padStart(64, "0")}`;
    return slot;
  }
  seed("vrfCoordinator", coordinator);
  seed("vrfRequestId", 7);
  seed("rngFlagsAndNudges", (1 << 14) | 3);
  seed("rngLockedFlag", daily ? 1 : 0);
  const wordSlot = seed("rngWordCurrent", 1);
  const tx = { from: coordinator, to: target, gas: "0x493e0",
    data: gameAbi.encodeFunctionData("rawFulfillRandomWords", [7, [0xBEEFn]]) };
  const stateOverrides = { [target]: { code: game.deployedBytecode.object, state } };
  await rpc("eth_call", [tx, "latest", stateOverrides]);
  const diff = await rpc("debug_traceCall", [tx, "latest", {
    tracer: "prestateTracer", tracerConfig: { diffMode: true }, stateOverrides,
  }]);
  const actual = BigInt(diff.post[target]?.storage?.[wordSlot] || 0);
  if (actual !== 0xBEEFn + (daily ? 3n : 0n)) throw new Error("Callback did not store the bound word");
  const trace = await rpc("debug_traceCall", [tx, "latest", { tracer: "callTracer", stateOverrides }]);
  callbacks.push({ daily, callbackLimit: 300_000, traceGasUsed: Number(BigInt(trace.gasUsed)), word: actual.toString() });
}
const benchmark = [];
if (baselineOut) {
  const baseline = JSON.parse(fs.readFileSync(`${baselineOut}/TicketCheckpointDeterminism.t.sol/TicketCheckpointHarness.json`));
  overrides = { [target]: { code: artifact.deployedBytecode.object, state: {} } };
  await step("initialize", [1]);
  await step("credit", ["0x0000000000000000000000000000000000010000", 1, 16075]);
  await step("commit", [0x12902fc2cb1a37n, false]);
  const benchmarkState = structuredClone(overrides);
  let referenceDigest;
  for (const [label, code, budget] of [
    ["baseline_raw_allowance", baseline.deployedBytecode.object, 16_600_000n],
    ["caller_calibrated_1x", artifact.deployedBytecode.object, (1n << 255n) | (10_000n << 192n) | (1n << 224n) | 16_600_000n],
    ["caller_calibrated_5x", artifact.deployedBytecode.object, (1n << 255n) | (50_000n << 192n) | (1n << 224n) | 16_600_000n],
    ["caller_calibrated_max", artifact.deployedBytecode.object, (1n << 255n) | (4_294_967_295n << 192n) | (1n << 224n) | 16_600_000n],
  ]) {
    overrides = structuredClone(benchmarkState);
    overrides[target].code = code;
    const gasPerCall = [];
    let completedEntries = 0n, done = false;
    for (let i = 0; i < 100 && !done; ++i) {
      const tx = call("runTicketWork", [2, budget], 16_700_000);
      const trace = await rpc("debug_traceCall", [tx, "latest", { tracer: "callTracer", stateOverrides: overrides }]);
      if (trace.error) throw new Error(`Benchmark trace failed: ${trace.error}`);
      gasPerCall.push(Number(BigInt(trace.gasUsed)));
      const [result] = await step("runTicketWork", [2, budget], 16_700_000);
      if (!result.progressed && !result.done) throw new Error("Benchmark stalled");
      completedEntries += result.rewardBasis;
      done = result.done;
    }
    if (!done) throw new Error("Benchmark did not complete the identical cohort");
    const [digest] = await read("digest", [1]);
    referenceDigest ??= digest;
    if (digest !== referenceDigest) throw new Error("Benchmark changed baseline ticket outcomes");
    benchmark.push({ label, calls: gasPerCall.length, gasPerCall,
      traceGasUsed: gasPerCall.reduce((sum, gas) => sum + gas, 0),
      completedEntries: completedEntries.toString(), digest });
  }
}
const gasProbe = await rpc("eth_call", [{ to: target, gas: "0x3938700" }, "latest", {
  [target]: { code: "0x5a60005260206000f3" },
}]);
const result = { client: await rpc("web3_clientVersion", []), rpc: rpcUrl,
  schedule, storageProbes,
  workerRuntimeSha256: createHash("sha256").update(artifact.deployedBytecode.object).digest("hex"),
  executionGasAt60MillionTotal: Number(BigInt(gasProbe)), runs, callbacks, benchmark };
const json = JSON.stringify(result, null, 2);
if (report) fs.writeFileSync(report, `${json}\n`);
console.log(json);
