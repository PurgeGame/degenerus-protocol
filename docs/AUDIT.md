# External audit handoff

## Target and identity

**Audit tag: `audit-2026-10-30`** (the commit this tag points to). The target is the **EIP-170
profile**, selected by `PROFILE=eip170`, with deployment order and aliases in
[deployments/eip170.json](../deployments/eip170.json). Runtime and initcode ceilings are 24,576 and
49,152 bytes per deployment. Compiler settings are Solidity 0.8.38, via IR, optimizer runs 1,000 and
EVM Osaka.

[scope.txt](../scope.txt) lists the deployment import closure plus optional lenses and readers. Its
final **display data: dependency review only** section separates artwork and renderer code;
financial dependencies and authorization remain relevant. Generated facades and the selected profile
import file are labeled with their generator.

**The Glamsterdam profile is out of scope.** Its shells, deployment manifest and compatibility
compositions remain in the repository for build and fixture compatibility. The scope checker follows
imports from the EIP-170 deployment roots; it does not infer use from module names. The four
compatibility bundles import Glamsterdam shells, while the foil compatibility bundle combines user
and worker code outside the EIP-170 deployment closure. See [out_of_scope.txt](../out_of_scope.txt)
for their exact paths.

There is one repository identity manifest: [source-sha256.txt](audit/source-sha256.txt). It hashes
scoped sources, retained compilation dependencies, build inputs, tests (including vectors, tables
and module helpers) and assurance tools.
Inclusion in the manifest does not expand audit scope or attest to test success. ETH-exit evidence
contains its own run-specific input hashes; those identify that bounded campaign, not a second audit
target.

Verify from the repository root before running a fixture that patches address constants:

```sh
sha256sum -c docs/audit/source-sha256.txt
python3 scripts/audit-snapshot.py
```

After reviewed input changes, regenerate with `python3 scripts/audit-snapshot.py --write` and repeat
verification. Use the commit/tag above to identify the frozen checkout; the hash manifest contains
no competing commit claim. No external evidence archive is needed for the handoff.

## Assumptions and trust boundaries

The mining run (`mineRun` / internal `mineFlip` chain) is assumed to be **called to completion every
game day**. Findings that require callers to stop partway or leave the chain stalled are not valid
unless the chain itself cannot complete. A reachable revert, gas-limit failure, unbounded work or
inconsistent cursor that prevents completion remains in scope.

[SECURITY.md](../SECURITY.md) defines owner powers, DGVE delegation, sDGNRS governance, supported
stETH behavior, coordinator authentication and the coordinator's one-fulfillment assumption.
[KNOWN-ISSUES.md](../KNOWN-ISSUES.md) lists the owner's accepted implementation limitations.
[ECONOMIC_DISCLOSURES.md](../ECONOMIC_DISCLOSURES.md) defines game rules and economic rights. Read
these boundaries together; neither a trusted-address label nor a healthy external asset excuses a
caller-induced accounting or authorization failure.

## Review priorities

1. Randomness commitment, publication, consumer binding and resistance to outcome selection.
2. Mining-chain completion through every resumable stage, nested call and terminal transition.
3. ETH/stETH backing, token units, entitlement, rounding and exactly-once distribution.

Gas admission uses `MineFlipGas` and `MineFlipGasBounds`. Zero calibration normalizes to 10,000
basis points. Optional continuations need their estimate and return tail to fit; the first work unit
bypasses the chunk estimate but still requires actual execution gas. Nested funding can refuse a
caller's calibration. A failed attempt alone is not a protocol stall if another caller can complete
the chain. Caller gas must not select a committed outcome or turn an out-of-gas failure into a
semantic fallback. Terminal ETH distribution is reviewed independently of unfinished FLIP
bookkeeping.

## Navigation and verification

Start with [Architecture](ARCHITECTURE.md), [Token units](TOKEN-UNITS.md) and
[Accounting](ACCOUNTING.md). [Module map](MODULE-MAP.md) follows facade and nested dispatch;
[Storage packing](STORAGE-PACKING.md) explains bit fields and compiler slots.
[Properties](PROPERTIES.md) maps review targets to assertions. [RNG domains](audit/RNG-DOMAINS.md)
identifies entropy sources and consumers. [ETH exit assurance](audit/ETH-EXIT-ASSURANCE.md)
describes the retained helper proof and its limits.

[TESTING.md](TESTING.md) is the build/test companion to this handoff: dependency setup, a sliced
build smoke test, production size/layout checks, source gates, Foundry and Hardhat groups, mainnet
forks, deep invariants and symbolic checks. Run the source hash check above before and after
fixture-driven tests. [The index](README.md) links mechanism-specific references.

Verification evidence applies only to its captured inputs. Focused regressions do not certify the
complete Foundry/Hardhat battery or the 70-partition deep invariant matrix on the final handoff.
Hosted CI and the final audit commit/tag require their own validation; see [Testing](TESTING.md).

## Project High-severity criteria

A High finding must demonstrate substantial impact that one actor can cause unilaterally without
vault-owner privileges (the executor authorized by >50.1% of DGVE, initially held by CREATOR, and
its comp delegates and battle creators), from a healthy live-game state: the game has not ended, VRF
is functional, and the mining chain is called to completion every game day unless the chain itself
cannot complete. The finding must not require an unrelated service outage, prolonged miner
inactivity or a pre-existing unhealthy state.

The completion assumption does not excuse an execution failure: an actor-induced gas/revert brick,
stall or premature game-over remains eligible when caused from those healthy conditions.
Catastrophic loss, diversion or permanent lock of terminal distributions is also eligible, even
after game-over or during VRF failure. Other findings outside these assumptions should state their
prerequisites and be assessed below High under this project's criteria.

## Vault-owner attacks — Medium

Attacks requiring vault-owner (DGVE-majority) privileges against a mature game with active
independent participants are classified as Medium, including terminal-distribution impacts.
Genesis-only self-disruption is excluded.

## Exclusions

Outcomes requiring valid sDGNRS governance approval are the governance mechanism, not audit
findings. Bypassing its authorization, voting or execution rules remains in scope. Findings about
WWXRP value, supply or draw weighting are excluded; a path where WWXRP moves ETH, stETH, sDGNRS or
tickets, or pays FLIP beyond what its draws pay by rule, remains in scope. See [the audit
boundaries](../SECURITY.md#audit-boundaries). Style-only reports and gas micro-optimizations are not
audit priorities; see [out_of_scope.txt](../out_of_scope.txt).
