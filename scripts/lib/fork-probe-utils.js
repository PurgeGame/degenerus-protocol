// Pure audit helpers. No RPC endpoints or signing credentials are accepted here.
export function transactionIntrinsicGas(data) {
  if (!/^0x(?:[0-9a-f]{2})*$/i.test(data)) throw new Error("invalid transaction calldata");
  let gas = 21_000n;
  for (let i = 2; i < data.length; i += 2) gas += data.slice(i, i + 2) === "00" ? 4n : 16n;
  return gas;
}

export function framesMatching(frame, predicate) {
  if (!frame || typeof frame !== "object") throw new Error("missing call trace");
  return [...(predicate(frame) ? [frame] : []), ...(frame.calls || []).flatMap((child) => framesMatching(child, predicate))];
}

export function assertRequiredPasses(results, requiredIds) {
  const missing = requiredIds.filter((id) => !results.some((r) => r.id === id && r.status === "PASS"));
  if (missing.length) throw new Error(`Required probes did not PASS: ${missing.join(", ")}`);
  if (results.some((r) => r.status === "FAIL")) throw new Error("One or more fork probes failed");
}

export async function driveUntilRequest({ action, step, requestFrom, maximum = 256 }) {
  const actions = [];
  for (let i = 0; i < maximum; ++i) {
    const selected = Number(await action());
    actions.push(selected);
    if (selected === 0 || selected === 1 || selected === 2) {
      throw new Error(`No request reachable in current probe state: action=${selected}, transcript=${actions}`);
    }
    const receipt = await step(selected);
    const request = requestFrom(receipt);
    if (request) return { request, actions };
  }
  throw new Error(`Request work bound exceeded: transcript=${actions}`);
}

export async function driveUntilReadComplete({ complete, action, step, requestFrom, fulfill, maximum = 256 }) {
  const actions = [];
  for (let i = 0; i < maximum; ++i) {
    if (await complete()) return actions;
    const selected = Number(await action());
    actions.push(selected);
    if (selected === 0 || selected === 1 || selected === 2) {
      throw new Error(`Incomplete read cannot progress: action=${selected}, transcript=${actions}`);
    }
    const receipt = await step(selected);
    const request = requestFrom(receipt);
    // mineFlip may finish one cohort then request its successor in the same call.
    // Keep draining; never mistake the next request's lock for old completion.
    if (request) await fulfill(request);
  }
  if (await complete()) return actions;
  throw new Error(`Read drain work bound exceeded: transcript=${actions}`);
}
