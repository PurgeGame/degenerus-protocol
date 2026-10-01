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

Gas expectations are at most 10M for ordinary calls, 11M for unusual calls and 11.5M
for extreme cases; 11.5M is the hard transaction ceiling, including intrinsic gas.
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

Ticket drain pricing targets at least 99% of normal keeper calls at 10M gas or less.
The drain budget is 900 units of 10k gas: a write to a zero-valued slot costs three
units and a nonzero write one, with no first-chunk derate. With 1M fixed overhead the
drain envelope is 10M, including startup and record-volume backing growth. Charges
depend only on storage state at the start of the call. See
`test/gas/TicketDrainWorstCaseBound.t.sol`, `RoundDrainChunkGas.t.sol` and
`KeeperGasProfile.t.sol`.
