# External audit handoff

## Subject

Review the production Solidity files listed in [scope.txt](../scope.txt). This handoff describes a
**frozen source revision at annotated tag `audit-2026-10-10`**.
[The freeze record](audit/freeze.json) identifies the tested input revisions and verification
results. Exact SHA-256 hashes and the source base commit are recorded in
[the snapshot manifest](audit/snapshot.json).

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
6. [Current readiness review](AUDIT-READINESS.md): security conclusions, repaired
   verification gaps, campaign results and remaining limits.

## Review priorities

1. **RNG non-manipulability.** Players, operators and transaction ordering must not bias,
   select or reroll outcomes. Check commitment boundaries, mutable settlement inputs,
   entropy reuse and caller-controlled batching or gas.
2. **mineFlip chain liveness.** No reachable state may leave the mineFlip chain (advance,
   settlement and terminal processing) unable to complete. Gas is one way to break it,
   alongside reverts, external-call failures, stale or inconsistent cursors and worst-case
   state. Check cold accesses, finalization and every stage's failure paths; partial work
   must resume without skipping or duplicating entries.
3. **Accurate accounting and prize distribution.** Reconcile ETH/stETH obligations, token
   balances, credits, backing, allowances and prize pools. Verify award calculations,
   eligibility, recipients, rounding and exactly-once settlement across all games.

Operational assumptions, including scheduled progression, are disclosed in Known Issues.

Gas admission is caller-calibrated. Optional continuations reserve the next chunk's
estimated cost and complete call/return/flush envelope, scaled by the caller's multiplier,
against the remaining worker allowance and actual available gas. The first mandatory
checkpoint is not vetoed by that estimate, so conservative calibration cannot prevent
progress. The gas floor always holds every ancestor's return tail: the first unit may run
below it, and once that unit has progressed later units must fit above it again. Once the
first unit fits in the supplied gas, `mineFlip` is designed not to revert for gas. Larger
supplied budgets may admit more chunks. Network transaction/block limits remain separate
constraints. Caller gas may select a safe continuation checkpoint, never a committed game
outcome.
At game over, fair ETH distribution and completion take priority. FLIP has no
post-game value by design; unfinished Craps or other FLIP bookkeeping does not
justify adding prerequisites to ETH release.

## Project High-severity criteria

A High finding must demonstrate substantial impact that one actor can cause unilaterally
without vault-owner privileges (the >50.1% DGVE holder, initially CREATOR, and its comp
delegates and battle creators), from a healthy live-game state: the game has not ended, VRF
is functional, and `mineFlip(uint32)` is attempted on schedule.
The finding must not require an unrelated service outage, prolonged miner inactivity
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

Ticket work uses `MineFlipGas` admission bounds and deterministic checkpoints.
After the first mandatory checkpoint, the engine admits the next chunk only when
its caller-scaled estimate, including the call, return and checkpoint envelope,
fits both the remaining worker allowance and actual available gas. Otherwise it
stops at a safe checkpoint before starting that chunk. Zero calibration means
10,000 basis points; callers may select a larger multiplier after gas repricing.
Only estimate-admitted work is held to the floor when a worker finishes; a first unit
that ran below the floor is not an estimate failure.
A transaction can perform several admitted operations. Review the
declared bounds against reachable worst cases, nested EIP-150 forwarding and full
return tails. A caller choosing too little gas must not change an outcome or cause
an out-of-gas failure to be accepted as a semantic fallback.
