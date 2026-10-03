# External audit handoff

## Subject

Review the production Solidity files listed in [scope.txt](../scope.txt). This handoff describes a
**working-tree snapshot**. Exact SHA-256 hashes and the
base Git commit are recorded in [the snapshot manifest](audit/snapshot.json).

From the repository root, verify the supplied source/build inputs before patching pins:

```sh
sha256sum -c docs/audit/source-sha256.txt
```

Any source change requires refreshed hashes and appropriately scoped verification.
[Verification](VERIFICATION.md) explains how to build and run checks independently,
including their known limitations. The snapshot identifies source inputs, not test
results or a deployed instance.

## Read in this order

1. [Architecture](ARCHITECTURE.md): modules, funding and settlement boundaries.
2. [Security](../SECURITY.md): who can do what and which dependencies are trusted.
3. [Known issues](../KNOWN-ISSUES.md) and [economic disclosures](../ECONOMIC_DISCLOSURES.md).
4. [RNG domains](audit/RNG-DOMAINS.md): seeds, intentional shared outcomes and retained exceptions.
5. [Verification](VERIFICATION.md): reproduce the build and select relevant tests.

## Review priorities

1. **RNG non-manipulability.** Players, operators and transaction ordering must not bias,
   select or reroll outcomes. Check commitment boundaries, mutable settlement inputs,
   entropy reuse and caller-controlled batching or gas.
2. **No-brick gas safety.** Advance, settlement and terminal processing must complete
   within reachable gas limits. Check worst-case state, cold accesses, finalization and
   external-call failures; partial work must resume without skipping or duplicating entries.
3. **Accurate accounting and prize distribution.** Reconcile ETH/stETH obligations, token
   balances, credits, backing, allowances and prize pools. Verify award calculations,
   eligibility, recipients, rounding and exactly-once settlement across all games.

Operational assumptions, including scheduled progression, are disclosed in Known Issues.

The 10M gas figure is a sizing guideline for indivisible work, not a runtime cap.
Each checkpoint must reserve the next chunk's conservative worst-case cost, its
complete call/return/flush envelope and a safety margin against both the remaining
worker allowance and actual available gas. Larger supplied budgets may admit larger
chunks. Network transaction/block limits remain separate constraints. Caller gas
may select a safe continuation checkpoint, never a committed game outcome.
At game over, fair ETH distribution and completion take priority. FLIP has no
post-game value by design; unfinished Craps or other FLIP bookkeeping does not
justify adding prerequisites to ETH release.

## Project High-severity criteria

A High finding must demonstrate substantial impact that one actor can cause unilaterally
without vault-owner privileges (the >50.1% DGVE holder, initially CREATOR, and its comp
delegates and battle creators), from a healthy live-game state: the game has not ended, VRF
is functional, and `mineFlip()` is attempted on schedule.
The finding must not require an unrelated service outage, prolonged keeper inactivity
or a pre-existing unhealthy state.

Scheduled attempts do not imply successful execution: an actor-induced gas/revert brick,
stall or premature game-over remains eligible when caused from those healthy conditions.
Catastrophic loss, diversion or permanent lock of terminal distributions is also eligible,
even after game-over or during VRF failure. Other findings outside these assumptions should
state their prerequisites and be assessed below High under this project's criteria.

## Vault-owner attacks — Medium

Attacks requiring vault-owner (DGVE-majority) privileges against a mature game with active independent
participants are classified as Medium, including terminal-distribution impacts.
Genesis-only self-disruption is excluded.

## Governance exclusion

Outcomes requiring valid sDGNRS governance approval are the governance mechanism, not
audit findings. Bypassing its authorization, voting or execution rules remains in scope.

Ticket work now uses `MineFlipGas` admission bounds and deterministic checkpoints.
The former fixed 900-unit ticket budget and 11.5M transaction ceiling are retired.
The engine admits the next chunk only when its declared cost, including the call,
return and checkpoint envelope, fits the remaining gas; otherwise it stops at a
checkpoint instead of running out of gas. Chunks between checkpoints are sized to
cost at most 10M gas in about 99% of realistic cases, and no chunk may exceed 13M in
the absolute worst case. Review cold native execution, nested EIP-150 forwarding, and
full return tails.
