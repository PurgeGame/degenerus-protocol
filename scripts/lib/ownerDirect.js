import {getAddress} from "ethers";

// Bound eth_getLogs ranges and retry smaller ranges when the provider caps results.
async function logs(governance, filter, from, to) {
  const result = [];
  let span = 50_000;
  while (from <= to) {
    const end = Math.min(to, from + span - 1);
    try {
      result.push(...await governance.queryFilter(filter, from, end));
      from = end + 1;
    } catch (error) {
      if (span === 1) throw error;
      span = Math.max(1, Math.floor(span / 2));
    }
  }
  return result;
}

/** Discover candidates from logs, then use current state as the authority for control. */
export async function controlledOwnerPositions(governance, caller, {owners, fromBlock = 0, block} = {}) {
  caller = getAddress(caller);
  const provider = governance.runner.provider ?? governance.runner;
  block ??= await provider.getBlock("latest");
  if (!Number.isSafeInteger(fromBlock) || fromBlock < 0 || fromBlock > block.number) {
    throw new Error("--from-block must be a block at or before the current block");
  }
  let candidates;
  if (owners) {
    candidates = owners.map(getAddress);
    if (new Set(candidates).size !== candidates.length) throw new Error("--owners contains a duplicate address");
  } else {
    const events = await Promise.all([
      logs(governance, governance.filters.Deposited(null, null, caller), fromBlock, block.number),
      logs(governance, governance.filters.DelegateChanged(null, null, caller), fromBlock, block.number),
    ]);
    candidates = [...new Set([caller, ...events.flat().map(log => getAddress(log.args.owner))])];
  }
  const positions = await Promise.all(candidates.map(async owner => ({
    owner, position: await governance.positions(owner, {blockTag: block.number}),
  })));
  const controlled = positions.filter(({owner, position: p}) => {
    const valid = p.amount > 0n && (owner === caller || getAddress(p.votingDelegate) === caller);
    if (!valid && owners) throw new Error(`Caller does not control an existing position for ${owner}`);
    return valid;
  }).sort((a, b) => BigInt(a.owner) < BigInt(b.owner) ? -1 : 1);
  if (controlled.length === 0) throw new Error("Caller controls no escrow positions");
  return {
    block: block.number,
    owners: controlled.map(p => p.owner),
    settledWeight: controlled.reduce((sum, {position: p}) => sum + (p.depositBlock < BigInt(block.number) ? p.amount : 0n), 0n),
  };
}
