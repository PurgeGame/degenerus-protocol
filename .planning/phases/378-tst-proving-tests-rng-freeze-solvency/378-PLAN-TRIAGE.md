---
phase: 378-tst-proving-tests-rng-freeze-solvency
type: TST
milestone: v61.0
subject: b97a7a2e (v61.0 batched diff) + 056481ea (377 Outcome-A)
requirements: [SEC-01, SEC-02, TST-01, TST-02, TST-03, TST-04, TST-05, TST-06]
status: IN PROGRESS (foundation: failure baseline + slot-shift recalibration key)
---

# Phase 378 TST — Plan + Triage

378 owns the empirical hard floor (SEC-01 RNG-freeze, SEC-02 SOLVENCY-01) + one proving test per v61 surface (TST-01..06), PLUS the test-correctness debt the v61 PACK storage-slot shift created (runtime, deferred from 376 which was compile-only). All test-side / committable; NO contract changes expected (if a test surfaces a real v61 bug, that's a finding → fix gated at the contract boundary).

## A. The v61 storage-slot shift (recalibration key)

The PACK fold replaced two balance mappings (`claimableWinnings` + `afkingFunding`) with one (`balancesPacked`) → **net −1 storage slot**. The fold sits early in `DegenerusGameStorage` (decl ~L418), BEFORE the subscriber state (`_subOf` L2133, `_subscribers` L2145, `_subCursor` L2156). So:

- Slots **before** the balances region are UNSHIFTED — `StorageFoundation.t.sol` asserts only pre-fold slots (0 flags, 2 prizePoolsPacked, 11 prizePoolPendingPacked) → unaffected.
- Slots **after** the balances region shift by **−1** (uniform) — every harness hardcoding `_subOf`/`_subscribers`/`_subCursor` (and any post-fold slot) writes the WRONG slot now.

**Authoritative layout (do FIRST in the focused 378 session):** `forge clean && forge build` (foundry.toml has `include_storage = true`), then `forge inspect DegenerusGame storageLayout` to read the exact v61 slots. Confirm the −1 hypothesis, then recalibrate each harness's slot constants. (Do NOT `forge clean` while another forge build/test is running — artifact contention.)

## B. Slot-hardcoded harnesses to recalibrate (broken at runtime, NOT a gas/logic regression)

Confirmed broken (377): the 6 slot-hardcoded gas harnesses — `V56AfkingGasMarginal` (31 slot refs; all 16 tests revert `NoPass()` because the deity-pass grant writes a stale slot), `SweepPerPlayerWorstCaseGas` (18), `RouterWorstCaseGas` (16), `KeeperResolveBetWorstCaseGas` (12), `KeeperOpenBoxWorstCaseGas` (9), `KeeperLeversAndPacking` (5). Plus the vm.load redemption tests (376 fixed `StakedStonkRedemption` compile; runtime + `RedemptionInvariants`/`RedemptionStethFallback`/`RedemptionGas` TBD from the baseline). The full target list = the runtime-failure baseline in §C.

After recalibration: re-run `V56AfkingGasMarginal` to re-measure the binding **STAGE_2** subscriber all-evict LIVE on v61 (377 referenced it at 13.60M / 3.17M headroom; confirm it holds — structurally it should, PACK is 1-slot-neutral on the evict path).

## C. Runtime failure baseline (full `forge test` on b97a7a2e)

**525 passed / 396 failed** on v61 HEAD. Dominant failure modes (slot-shift signature in bold):
- **98 `NoPass()`** — stale-slot deity-pass grants → subscribe pass-gate rejects (the V56AfkingGasMarginal pattern, repo-wide).
- **62 `panic`** — likely wrong-slot `vm.store` → storage corruption (underflow/index/enum panics).
- 28 `BatchAlreadyTaken()` · 24 `InvalidBet()` (Degenerette — cross-check vs the AFPAY `_collectBetFunds` afking-tier change) · 16 `E()` · 14 assertion `Error` · long tail (Mid/Zero/Word/VRFPath/RngNotReady/…).
- ~32 failing test files: AfKing{Subscription,Concurrency}, Degenerette{FreezeResolution,HeroScore,ResolveRepeg}, VRF{Core,PathCoverage,StallEdgeCases,RotationLiveness,RotationOrphanIndex}, Keeper{FaucetResistance,RewardRouting,RouterOneCategory,ResolveBetGas}, Lootbox{BoonCoexistence,RngLifecycle}, PresaleBoxDrain, PrizePoolFreeze, QueueDoubleBuffer, Rng{FreezeAndRemovalProofs,LockDeterminism}, StallResilience, Ticket{EdgeCases,Lifecycle,Routing}, V56{FreezeSolvency,SecUnmanipulable,SubHardening}, AffiliateDgnrsClaim, V56AfkingGasMarginal.

**⚠ The v61-delta is NOT yet isolated.** A large red count is EXPECTED here (the PACK slot shift breaks every slot-hardcoded harness at runtime + the repo carries a known pre-existing red baseline — v56/v57 ran ~134 red-by-name). But "no v61 regression" is **NOT certified** until a NON-WIDENING comparison runs: re-run the SAME suite at baseline `2bee6d6f`, capture its red set, and confirm the v61 HEAD reds are a SUBSET of (baseline-reds ∪ accepted-slot-shift-staleness ∪ accepted-v61-behavior-changes) BY NAME — the established v55/56/57 methodology. Any HEAD red NOT in that union is a candidate v61 finding.

Triage each failure into:
- **(a) slot-stale** → recalibrate the harness's slot constants (§A/B).
- **(b) v61-behavior** → the test asserts pre-v61 behavior the feature legitimately changed (e.g. an `AfkingSpent`/`PlayerCredited` emit now present, a curse-penalized score, an afking-funded shortfall now succeeding where it used to revert) → update the test's expectation.
- **(c) potential bug** → a failure NOT explained by (a)/(b) → investigate as a possible v61 finding (would gate a contract fix).

## D. TST-01..06 — one proving test per v61 surface

| TST | Surface | Proof |
|---|---|---|
| TST-01 | PACK | balancesPacked round-trips both halves; gameOver claim-merge preserves the afking half; folding is value-identical to the old two-mapping reads |
| TST-02 | AFPAY waterfall | msg.value → claimable → afking ordering across all 3 pay-kinds; afking covers a shortfall that used to revert; `prizeContribution = ethUsed + claimableUsed + afkingUsed`; `AfkingSpent` emitted at each afking debit |
| TST-03 | AFPAY breadth | the shared `_settleShortfall` covers lootbox + presale + 3 whale sites + Degenerette ETH bet (keeps `InvalidBet()`); affiliate fresh/recycled split byte-identical for no-afking |
| TST-04 | CURSE SET/CURE | stale ghost-cashout → +2 (saturating at cap 20); a ≥priceWei buy cures to 0; active-afker / deity / whale-pass / infra bails; staleness on `_currentMintDay()` |
| TST-05 | CURSE APPLY | `curse*100` bps subtracted from the activity score, floored at 0; propagates to the public view + frozen snapshots; zero-new-SLOAD |
| TST-06 | SMITE + decurse | deity `smite` (200 BURNIE, ownerOf gate, +2 to 5-stack ceiling, protocol-skip, self-smite harmless); `decurse` (100 BURNIE, clears to 0) |

## E. SEC-01 / SEC-02 (the hard floor — proven empirically)

- **SEC-01 RNG-freeze:** prove the 3 work items read NO `rngWord` (already grep-clean per 377 — confirm empirically that no AFPAY/PACK/CURSE/SMITE path reads VRF-derived state in a player-manipulable window).
- **SEC-02 SOLVENCY-01:** prove `claimablePool == Σ(claimable + afking halves of balancesPacked[*])` holds across the new afking spend paths; the call-site pairing (USER-approved deviation: pairing at call sites, not in the accessor) maintains the identity; the `uint128` halves are supply-bound-safe.

## F. Pacing / sequencing (5h-cap discipline)

Per-unit commits (test-side, autonomous): (1) recalibration key + StorageFoundation/redemption fixes → commit; (2) gas-harness recalibration + STAGE_2 live → commit; (3) behavior-update fixes (triage b) → commit; (4) TST-01..06 → commit (per test or small batch); (5) SEC-01/02 → commit. Each unit leaves the suite greener; no unit spans the contract-commit boundary.
