---
phase: 327-tst-repro-same-results-no-arb-ev-regression-proofs
plan: 03
subsystem: testing
tags: [foundry, burnie, tombstone, gameover, uncirculated-supply, dgvb, vault, BTOMB]

# Dependency graph
requires:
  - phase: 326-impl-the-one-batched-contract-diff-all-7-items
    provides: "BTOMB fix (BurnieCoin.tombstoneAtGameOver one-shot 1e36 VAULT-allowance flood, _tombstoneFlooded latch, CHECKED _toUint128 add, BTOMB-01/02) + GameOverModule wiring (burnie.tombstoneAtGameOver adjacent to dgnrs.burnAtGameOver) — the applied Phase-326 diff this plan proves"
  - phase: 325-spec-design-lock-call-graph-attestation-shared-surface-recon
    provides: "325-ATTEST-BTOMB-HERO §A anchors (BURNIE_TOMBSTONE_WEI :174, Supply struct + seed :184-185, totalSupply/supplyIncUncirculated/vaultMintAllowance views :264/:271/:278, _toUint128 cap :358, B7 1e36 << uint128 max ~340x headroom, checked-add-cap resolution)"
provides:
  - "test/fuzz/BurnieTombstone.t.sol — 8 deterministic scenario tests proving the BURNIE tombstone is non-circulating + signal-localized + one-shot + GAME-gated + overflow-safe + DGVB-claim-safe"
  - "BTOMB-03 disposition: the DGVB pro-rata burnCoin claim IS reachable against a 1e36-inflated allowance and is proven overflow-safe by test (NOT a safe-by-construction fallback)"
affects: [327-06 full-suite regression gate, 328 TERMINAL delta-audit + adversarial sweep]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-test fresh full-protocol deploy (inherit DeployProtocol, _deployProtocol() in setUp) — each test_* gets a clean BurnieCoin so the one-shot latch + the uint128-boundary cases do not contaminate each other"
    - "Signal-localization assertion triplet: assert vaultMintAllowance() += EXACTLY 1e36 AND supplyIncUncirculated() += EXACTLY 1e36 AND totalSupply() UNCHANGED in the same test (mitigates T-327-03-FC1 false-confidence: a totalSupply()-only check would miss a leak into the wrong leg)"
    - "Live-cap negative control: drive the existing allowance to U128_MAX-1e36 (flood holds, result == U128_MAX) and U128_MAX-1e36+1 (flood reverts SupplyOverflow, state unchanged) — proving the checked _toUint128 add is not vacuous (mitigates T-327-03-FC3)"
    - "DGVB pro-rata reachability proof: drive a real DegenerusVault.burnCoin against the flooded reserve (CREATOR holds all 1e30 DGVB shares), burn a 1% fractional share to avoid the full-supply REFILL branch, assert coinOut == reserve*shares/supply + allowance debited exactly + uncirculated conserved (mitigates T-327-03-FC1)"

key-files:
  created:
    - "test/fuzz/BurnieTombstone.t.sol"
  modified: []

key-decisions:
  - "The DGVB pro-rata BURNIE claim is DegenerusVault.burnCoin(amount): coinOut = (coinBal * amount) / supplyBefore where coinBal includes vaultMintAllowance() (post-flood ~1e36+2M). Confirmed REACHABLE — the intermediate product 1e36*1e28 ~ 1e64 is far below uint256 max (~1.15e77), and the remainder mints via vaultMintTo (uint128 cast on the share, allowance debit) without revert. No safe-by-construction fallback needed."
  - "One-shot tested by calling tombstoneAtGameOver() TWICE as GAME and asserting allowance += EXACTLY 1e36 total (not 2e36) with NO revert on the second call — confirms the early-return latch (not a revert, so it cannot brick the gameover-drain path)"
  - "GAME gate proven against BOTH an arbitrary attacker AND the CREATOR (a token/share holder but not GAME) — both revert OnlyGame"
  - "Burn 1% of DGVB supply (not the full supply) in the claim test so the full-supply REFILL_SUPPLY re-mint branch is not triggered — coinOut is then a clean true pro-rata share of the reserve"

patterns-established:
  - "Real-contract BTOMB harness via DeployProtocol (the prior BurnieCoinInvariants.t.sol used a Mock because ContractAddresses were address(0); the patched Foundry build now gives real nonce-aligned addresses, so tombstoneAtGameOver()'s GAME gate + the real _toUint128 cap + the real DGVB burnCoin are all exercised end-to-end)"

requirements-completed: [BTOMB-03]

# Metrics
duration: 22min
completed: 2026-05-26
---

# Phase 327 Plan 03: BTOMB Gameover-Tombstone Non-Circulating + One-Shot + DGVB-Claim-Safe Proofs Summary

**The gameover BURNIE tombstone is proven non-circulating (totalSupply() untouched), signal-localized to the uncirculated leg (vaultMintAllowance() and supplyIncUncirculated() each += EXACTLY 1e36), strictly one-shot, GAME-gated, overflow-safe via the checked _toUint128 add with a live-cap negative control, and the DGVB pro-rata burnCoin claim is proven not to overflow on a 1e36-inflated allowance share — all against the applied Phase-326 diff with zero contract edits.**

## Performance

- **Duration:** ~22 min
- **Tasks:** 2 (both autonomous)
- **Files modified:** 1 (created)

## Accomplishments

`test/fuzz/BurnieTombstone.t.sol` — 8 deterministic tests, all green, `forge test --match-path test/fuzz/BurnieTombstone.t.sol` exits 0:

**Task 1 — non-circulating + signal localization + one-shot + checked-add (7 tests):**

| Test | Property | Asserted delta |
|------|----------|----------------|
| `test_BTOMB03_TotalSupplyUntouched` | (a) non-circulating | `totalSupply()` AFTER == BEFORE (== 2M circulating seed); flood touches 0 of circulating supply |
| `test_BTOMB03_SignalLandsOnlyInUncirculated` | (b) signal localization | `vaultMintAllowance()` += EXACTLY 1e36; `supplyIncUncirculated()` += EXACTLY 1e36; `totalSupply()` unchanged; supply identity `uncirc == total + allowance` holds post-flood |
| `test_BTOMB03_OneShot` | (c) one-shot | two `tombstoneAtGameOver()` calls as GAME → allowance += EXACTLY 1e36 total (NOT 2e36); second call does NOT revert (early-return latch) |
| `test_BTOMB03_GameGated` | (d) GAME-gated | non-GAME attacker reverts `OnlyGame`; CREATOR (a holder, not GAME) reverts `OnlyGame`; allowance untouched by failed attempts |
| `test_BTOMB03_CheckedAddNoOverflow` | (e) checked add | seeded 2M + 1e30-wei escrow, flood holds: result == existing + 1e36 |
| `test_BTOMB03_CheckedAddAtBoundary` | (e) boundary | existing driven to `U128_MAX - 1e36`, flood holds exactly at the boundary: result == `uint128` max |
| `test_BTOMB03_CheckedAddCapIsLive` | (e) live cap | existing driven to `U128_MAX - 1e36 + 1`, flood reverts `SupplyOverflow`; reverted state leaves allowance unchanged (negative control proves the cap is not vacuous) |

**Task 2 — DGVB pro-rata claim-safe (1 test):**

| Test | Property | Asserted |
|------|----------|----------|
| `test_BTOMB03_DgvbClaimNoOverflowOn1e36Share` | (f) DGVB claim-safe | flood +1e36, then CREATOR burns 1% of DGVB supply via `DegenerusVault.burnCoin`: no overflow/revert; `coinOut == reserve*shares/supply` (correct magnitude, nonzero, ≤ reserve); CREATOR balance += coinOut; allowance debited by exactly coinOut; `supplyIncUncirculated()` conserved across the claim (allowance → circulating) |

## Exact deltas asserted

- **totalSupply() delta from the flood: 0** (circulating seed = 2_000_000 ether before and after).
- **vaultMintAllowance() delta: +1e36 exactly** (2_000_000 ether seed → 2_000_000 ether + 1e36).
- **supplyIncUncirculated() delta: +1e36 exactly** (4_000_000 ether → 4_000_000 ether + 1e36).
- **One-shot result:** allowance += EXACTLY 1e36 across two calls (no 2e36; no revert on the second call).
- **Checked-add boundary tested:** flood-holds at `U128_MAX - 1e36` (result == `U128_MAX`); flood-reverts `SupplyOverflow` at `U128_MAX - 1e36 + 1`.

## DGVB claim disposition

**Proven-safe-by-test** (not proven-unreachable-by-construction). The DGVB pro-rata BURNIE-claim path is `DegenerusVault.burnCoin(amount)` (`contracts/DegenerusVault.sol:746`): `coinOut = (coinBal * amount) / supplyBefore` where `coinBal` includes `coinToken.vaultMintAllowance()` (post-flood ≈ 1e36 + 2M seed). The claim is reachable by any DGVB holder; CREATOR holds the entire 1e30 share supply. The test drives a real `burnCoin` of 1% of the supply against the flooded reserve: the intermediate product `coinBal * amount ≈ 1e36 * 1e28 = 1e64` is far below `uint256` max (~1.15e77), the remainder mints via `vaultMintTo` (uint128 cast on the share + allowance debit, `:597`) without revert, and the payout is a correct-magnitude pro-rata share.

## Verification

- `forge test --match-path test/fuzz/BurnieTombstone.t.sol` exits 0 — 8 passed, 0 failed, 0 skipped.
- `git status --porcelain contracts/ | grep -v '/test/'` empty — zero `contracts/*.sol` (mainnet) modifications; subject FROZEN at the Phase-326 diff (HEAD).
- The only Phase-326 contract anchors read: `tombstoneAtGameOver()` (:583), the `Supply` struct + seed (:177-185), `totalSupply`/`supplyIncUncirculated`/`vaultMintAllowance` views (:264/:271/:278), `_toUint128` cap (:358), `vaultEscrow` (:565), `vaultMintTo` (:597); the DGVB claim `DegenerusVault.burnCoin` (:746) + `_coinReservesView` (:949).

## Deviations from Plan

None - plan executed exactly as written. Tasks 1 and 2 both author `test/fuzz/BurnieTombstone.t.sol`; the file compiles + passes only with both task bodies present, so both tasks landed in one atomic commit. The plan's optional safe-by-construction DGVB fallback was NOT needed (the claim path is reachable and proven by test).

## Known Stubs

None - the test file wires real contracts end-to-end (no mock token, no hardcoded placeholder data). The prior `BurnieCoinInvariants.t.sol` Mock approach is superseded here by the patched-address `DeployProtocol` harness, so the real `tombstoneAtGameOver()` GAME gate, the real `_toUint128` cap, and the real DGVB `burnCoin` math are all exercised.

## Self-Check: PASSED

- FOUND: test/fuzz/BurnieTombstone.t.sol
- FOUND commit: f0c98063 (test(327-03): BTOMB-03 tombstone non-circulating + one-shot + DGVB-claim-safe)
- 8/8 tests PASS; `forge test --match-path test/fuzz/BurnieTombstone.t.sol` exits 0
- Zero `contracts/*.sol` (mainnet) mutations
