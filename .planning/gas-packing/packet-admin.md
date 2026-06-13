# Packet — DegenerusAdmin (ADMIN-09)

**Verdict:** APPROVED · storage_packing · cold · own-storage standalone contract.

## Finding
Per-voter vote direction + weight live in two parallel mappings per track:
- `votes`/`voteWeight` (governance), `feedVotes`/`feedVoteWeight` (feed governance).
- Cost today: first vote = 2 cold SLOADs + 2 zero→nonzero SSTOREs; vote change = 2 warm pairs.
- `Vote` (enum, 1 byte) + `uint40` weight (5 bytes) = 6 bytes → trivially one slot.

## Access map (live source, verified)
- `Vote` enum `{None, Approve, Reject}` @ L200.
- Decls: votes L320, voteWeight L323, feedVotes L358, feedVoteWeight L361 (all `public`).
- `vote()` L711: reads `votes[id][s]` + `voteWeight[id][s]` into `_applyVote` (L728-729); writes both (L733-734).
- `voteFeedSwap()` L540: reads `feedVotes`/`feedVoteWeight` (L554-555); writes both (L559-560).
- `_applyVote` L794 consumes `(Vote currentVote, uint40 oldWeight)` — pure, no storage.
- **Zero** cross-contract or test readers of the 4 getters (grep contracts/ + test/ = empty).

## PRE layout (forge inspect)
votes@5, voteWeight@6, activeProposalId@7, voidedUpTo@8, feedProposalCount@9, feedProposals@10, feedVotes@11, feedVoteWeight@12, activeFeedProposalId@13, feedVoidedUpTo@14, linkEthPriceFeed@15.

## Change
- New `struct VoterRecord { Vote v; uint40 w; }` (6 bytes, 1 slot).
- Replace the 4 public mappings with 2 **private** packed mappings: `voterRecords`, `feedVoterRecords`.
- **ABI preserved**: add 4 explicit external view getters with the exact current signatures — `votes(uint256,address)→Vote`, `voteWeight(uint256,address)→uint40`, `feedVotes(...)→Vote`, `feedVoteWeight(...)→uint40` — each returning the unpacked field. (No on-chain/test caller, but off-chain tooling may read them; frozen contract → preserve.)
- Access rewrite (both functions): read once into a `VoterRecord memory`, write once via a struct literal — guarantees 1 SLOAD / 1 SSTORE not optimizer-dependent:
  ```
  VoterRecord memory vr = voterRecords[id][msg.sender];   // 1 SLOAD
  (aw, rw) = _applyVote(approve, weight, vr.v, vr.w, aw, rw);
  ...
  voterRecords[id][msg.sender] = VoterRecord(approve ? Vote.Approve : Vote.Reject, weight); // 1 SSTORE
  ```

## Expected POST shift
votes+voteWeight → voterRecords (−1 slot, shifts old 7-15 down 1); feedVotes+feedVoteWeight → feedVoterRecords (−1 more, shifts old 13-15). Net −2 trailing slots. Verify via POST inspect.

## Blast radius / harness
None. Standalone contract (no delegatecall modules share its layout). No slot-hardcoded harness (grep-clean). Behavioral coverage: `test/unit/DegenerusAdmin.test.js`, `test/unit/GovernanceGating.test.js` (exercise vote() / threshold / kill paths — preserved).

## Savings
~22,100 per first-time voter per proposal (one cold SLOAD + one zero→nonzero SSTORE avoided); ~5,000 per vote change. Cold path (emergency governance). Bytecode ~neutral (Admin not EIP-170 constrained).

## Safety
Pure storage-layout change. No RNG window, no solvency, no access-control surface. `_applyVote` math byte-identical. Tightens nothing, loosens nothing.
