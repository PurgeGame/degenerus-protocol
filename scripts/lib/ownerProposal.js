import {AbiCoder, getAddress, keccak256} from "ethers";

/** Recover the immutable action from its creation log and verify it against storage. */
export async function readOwnerProposalAction(governance, id, proposal, block) {
  if (proposal.expiresAt === 0n) throw new Error(`Unknown proposal ${id}`);
  const provider = governance.runner.provider ?? governance.runner;
  block ??= await provider.getBlock("latest");
  const createdAt = proposal.expiresAt - await governance.PROPOSAL_LIFETIME();
  // Locate the creation timestamp using headers, then use eth_getLogs over just
  // those blocks. This avoids RPC limits on scans from genesis to the latest block.
  const headers = new Map([[block.number, block]]);
  async function firstBlockAt(timestamp) {
    let low = 0, high = block.number + 1;
    while (low < high) {
      const mid = Math.floor((low + high) / 2);
      let header = headers.get(mid);
      if (!header) {
        header = await provider.getBlock(mid);
        if (!header) throw new Error(`RPC cannot read block ${mid}`);
        headers.set(mid, header);
      }
      if (BigInt(header.timestamp) < timestamp) low = mid + 1;
      else high = mid;
    }
    return low;
  }
  const fromBlock = await firstBlockAt(createdAt);
  const toBlock = await firstBlockAt(createdAt + 1n) - 1;
  if (fromBlock > toBlock) throw new Error(`No creation block for proposal ${id}`);
  const logs = await governance.queryFilter(governance.filters.ProposalCreated(id), fromBlock, toBlock);
  if (logs.length !== 1) throw new Error(`Expected one ProposalCreated log for ${id}, found ${logs.length}`);
  const event = logs[0].args;
  const address = await governance.getAddress();
  const {chainId} = await provider.getNetwork();
  const actionHash = keccak256(AbiCoder.defaultAbiCoder().encode(
    ["uint256", "address", "uint256", "address", "uint256", "bytes", "uint256"],
    [chainId, address, id, proposal.target, proposal.value, event.data, proposal.expiresAt],
  ));
  if (keccak256(event.data) !== proposal.dataHash || event.actionHash !== actionHash
      || getAddress(event.proposer) !== getAddress(proposal.proposer)
      || getAddress(event.target) !== getAddress(proposal.target)
      || event.value !== proposal.value || event.expiresAt !== proposal.expiresAt) {
    throw new Error(`Proposal ${id} creation log does not match its stored action`);
  }
  return {data: event.data, actionHash, createdAt, creationBlock: logs[0].blockNumber};
}
