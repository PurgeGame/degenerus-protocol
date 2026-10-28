# External audit handoff

## Subject

Review the production Solidity files listed in [scope.txt](../scope.txt). This handoff describes a
**candidate source snapshot, not a tagged final freeze**. Verify the supplied hashes below;
do not substitute a historical audit tag for these inputs.
The primary audit and deployment target is the `eip170` build profile
(`contracts/profiles/eip170`); the `glamsterdam` profile (`contracts/profiles/glamsterdam`) is the
maintained alternate. `scripts/select-profile.js` selects the profile, and the deployment tables are
`deployments/eip170.json` and `deployments/glamsterdam.json`.
[The readiness record](audit/freeze.json) identifies the tested input revisions, verification
results and outstanding release checks. Exact SHA-256 hashes and the source base commit are recorded in
[the snapshot manifest](audit/snapshot.json).

Read the [preparation findings](AUDIT-READINESS.md#preparation-review--2026-10-28)
alongside the scope: they record dependency advisories and outstanding verification evidence.
The project's disposition of a failed stETH balance read is in
[Security](../SECURITY.md#external-dependencies-and-settlement). The specific external-failure
disposition does not exclude caller-induced loss with healthy supported dependencies.

From the repository root, verify the supplied source/build inputs before patching pins:

```sh
sha256sum -c docs/audit/source-sha256.txt
```

Any source change requires refreshed hashes and appropriately scoped verification.
[Verification](VERIFICATION.md) explains how to build and run checks independently,
including their known limitations. The snapshot identifies source inputs, not test
results or a deployed instance.

Include `native-evidence-2026-10-28.tar.gz` with the repository handoff. The readiness
record gives its checksum and size; the archive contains the retained native recorder,
capture inputs, runtime artifacts, results and reproduction guide. It is deliberately
kept outside Git, so a clone alone does not include it. Its assembly verified provenance
and hashes without rerunning the historical native replay.

## Read in this order

1. This handoff, [scope.txt](../scope.txt) and [out_of_scope.txt](../out_of_scope.txt), the
   hash check above, and the current-revision and handoff sections of the
   [readiness review](AUDIT-READINESS.md).
2. [Token units](TOKEN-UNITS.md), then [Security](../SECURITY.md) (authorities, trusted
   dependencies, VRF callback trust, audit boundaries) and [Known issues](../KNOWN-ISSUES.md).
3. [Architecture](ARCHITECTURE.md): contract boundaries, value flow, miner action order,
   commitment and settlement boundaries, the ending and invariants.
4. [Accounting](ACCOUNTING.md): custody, obligation equations and reservations by phase.
5. [Properties](PROPERTIES.md): critical properties, implementation symbols and test assertions.
6. [Owner governance](OWNER_GOVERNANCE.md).
7. [RNG domains](audit/RNG-DOMAINS.md): request/callback/publication, words and their consumers,
   intended sharing and mutable payout inputs.
8. [Verification](VERIFICATION.md): setup, evidence limits and the focused suites for the area
   under review.
9. [Economic disclosures](../ECONOMIC_DISCLOSURES.md) and the mechanism references, alongside the
   corresponding contracts.

Mechanism references ([Architecture details](ARCHITECTURE-DETAILS.md), loans, Craps, Decimator,
Degenerette, deity passes, WWXRP boons, Vault actions, storage reuse) and historical evidence are
indexed in [the documentation index](README.md).

## Review priorities

1. **RNG non-manipulability.** Players, operators and transaction ordering must not bias,
   select or reroll outcomes. Check commitment boundaries, mutable settlement inputs,
   entropy reuse and caller-controlled batching or gas.
2. **mineRun chain liveness.** No reachable state may leave the `mineRun` chain (advance,
   settlement and terminal processing) unable to complete. Gas is one way to break it,
   alongside reverts, external-call failures, stale or inconsistent cursors and worst-case
   state. Check cold accesses, finalization and every stage's failure paths; partial work
   must resume without skipping or duplicating entries.
3. **Accurate accounting and prize distribution.** Reconcile ETH/stETH obligations, token
   balances, credits, backing, allowances and prize pools. Verify award calculations,
   eligibility, recipients, rounding and exactly-once settlement across all games.

Authority and external-service assumptions are documented in [Security](../SECURITY.md),
and game rules in [Economic Disclosures](../ECONOMIC_DISCLOSURES.md). Accepted implementation
limitations are listed separately in [Known Issues](../KNOWN-ISSUES.md). Scheduled progression
is a prerequisite for the High-severity criteria below, not an exclusion of actor-induced stalls.

Gas admission is caller-calibrated. Optional continuations reserve the next chunk's
estimated cost and complete call/return/flush envelope, scaled by the caller's multiplier,
against the remaining worker allowance and actual available gas. The first eligible unit
is exempt from the chunk estimate; nested call admission still applies after the worker
marks progress. This distinction matters in subscriber preparation: excessive calibration
can make nested funding revert `InsufficientExecutionGas` before any stETH call, even
within the first outer subscriber unit. Retained-state checks at the transaction cap show
that these failed attempts commit no protocol changes and a different caller using normal
calibration can continue. A valid multiplier argument therefore does not guarantee progress
at every supplied gas budget. The gas floor holds ancestor return tails; later admitted
units must fit above it. When the first unit is a VRF request, the supplied gas must cover
the request minimum plus its tail, otherwise the call reverts before the coordinator call. Larger
supplied budgets may admit more chunks. Network transaction/block limits remain separate
constraints. Caller gas may select a safe continuation checkpoint, never a committed game
outcome.

Chunked work (ticket rounds, settlement, terminal processing) uses `MineFlipGas` admission
with the estimates declared in `MineFlipGasBounds` and stops at a deterministic checkpoint
before any chunk it does not admit. Zero calibration means 10,000 basis points. Default bounds include Glamsterdam new-state gas
without a reservoir unless a constant says otherwise. Callers may choose a larger
multiplier for more conservative batching, or a factor down to 2,500 for cheaper schedules
at their own transaction's risk. Only estimate-admitted work is held to the floor when a
worker finishes; a first unit that ran below the floor is not an estimate failure.
A transaction can perform several admitted operations. Review the declared bounds against
reachable worst cases, nested EIP-150 forwarding and full return tails. A caller choosing
too little gas must not change an outcome or cause an out-of-gas failure to be accepted as
a semantic fallback.

At game over, fair ETH distribution and completion take priority. FLIP has no
post-game value by design; unfinished Craps or other FLIP bookkeeping does not
justify adding prerequisites to ETH release.

## Project High-severity criteria

A High finding must demonstrate substantial impact that one actor can cause unilaterally
without vault-owner privileges (the executor authorized by >50.1% of DGVE, initially held by CREATOR, and its comp
delegates and battle creators), from a healthy live-game state: the game has not ended, VRF
is functional, and `mineRun(uint32)` is attempted on schedule.
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

## Exclusions

Outcomes requiring valid sDGNRS governance approval are the governance mechanism, not
audit findings. Bypassing its authorization, voting or execution rules remains in scope.
Findings about WWXRP value, supply or draw weighting are excluded; a path where WWXRP moves
ETH, stETH, sDGNRS or tickets, or pays FLIP beyond what its draws pay by rule, remains in
scope. See [the audit boundaries](../SECURITY.md#audit-boundaries). Style-only reports and
gas micro-optimizations are not audit priorities; see [out_of_scope.txt](../out_of_scope.txt).
