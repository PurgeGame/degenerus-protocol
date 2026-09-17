# External audit handoff

## Subject

Review the production Solidity files listed in [scope.txt](../scope.txt). This handoff describes a
**working-tree snapshot**. Exact SHA-256 hashes and the
base Git commit are recorded in [the snapshot manifest](audit/snapshot.json).

From the repository root, verify the supplied source/build inputs before patching pins:

```sh
sha256sum -c docs/audit/source-sha256.txt
```

Any source change requires a new manifest and appropriately scoped verification. The
test and static-analysis results recorded in [Verification](VERIFICATION.md) apply to the
manifest's base revision only. The audit snapshot does not identify or certify any
deployed instance.

## Read in this order

1. [Architecture](ARCHITECTURE.md): modules, funding and settlement boundaries.
2. [Security](../SECURITY.md): who can do what and which dependencies are trusted.
3. [Known issues](../KNOWN-ISSUES.md) and [economic disclosures](../ECONOMIC_DISCLOSURES.md).
4. [Verification](VERIFICATION.md): reproduce the build and select relevant tests.

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

## Project High-severity criteria

A High finding must demonstrate substantial impact that one actor can cause unilaterally
without creator privileges, from a healthy live-game state: the game has not ended, VRF
is functional, and `mineFlip()` is attempted on schedule.
The finding must not require an unrelated service outage, prolonged keeper inactivity
or a pre-existing unhealthy state.

Scheduled attempts do not imply successful execution: an actor-induced gas/revert brick,
stall or premature game-over remains eligible when caused from those healthy conditions.
Catastrophic loss, diversion or permanent lock of terminal distributions is also eligible,
even after game-over or during VRF failure. Other findings outside these assumptions should
state their prerequisites and be assessed below High under this project's criteria.

## Creator attacks — Medium

Attacks requiring creator privileges against a mature game with active independent
participants are classified as Medium, including terminal-distribution impacts.
Genesis-only self-disruption is excluded.

## Governance exclusion

Outcomes requiring valid sDGNRS governance approval are the governance mechanism, not
audit findings. Bypassing its authorization, voting or execution rules remains in scope.
