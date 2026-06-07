# FINDINGS — v61.0 (AfKing-as-Payment + Cashout-Curse + Deity-Smite — in-milestone TERMINAL close)

- **Hunt subject SHA (contract delta):** `b97a7a2e` (phase 376 IMPL — the ONE batched v61 contract diff). Contracts are byte-identical from `b97a7a2e` through the close HEAD: tree-hash `87e3b45b46879ec80c4fe6a689b4c17ccae482f1`, content fingerprint `fcdd999ce2ddb0cac9e04b49242522b896cf56c67c18e213cd0f6dd5b6aa8aaf` (`find contracts -name '*.sol' | sort | xargs sha256sum | sha256sum`).
- **Baseline (frozen):** `2bee6d6f` (v60.0 closure HEAD).
- **Test/proof HEAD:** `0841926a` (phase 378 close — the empirical proofs + the non-widening gate).
- **Date:** 2026-06-07.
- **v61 contract delta:** `git diff 2bee6d6f b97a7a2e -- contracts/` = 13 files, +550 / −242. The ONLY contract change in the milestone (377 GAS = Outcome-A no-diff; 378 TST = test-only). Not pushed (60 ahead of origin).
- **Methodology:** two layers. (1) **Empirical proof** (phase 378): one falsifiable proving test per surface (TST-01..06) + the hard floor (SEC-01 RNG-freeze, SEC-02 SOLVENCY-01), each RUN green and independently re-verified, plus a BY-NAME non-widening comparison vs the `2bee6d6f` baseline. (2) **Adversarial sweep** (this phase, 379): a genuine-parallel 3-lens read-only attack on the v61 delta — security+gas, economic/game-theory, and zero-day/composition — each pre-loaded with the locked threat model + by-design rulings, each verified to have made zero file edits (contract fingerprint unchanged after the sweep).

---

## Executive summary

**v61.0 ships CLEAN. Zero contract-change-needed findings.** The four features (AFPAY waterfall, PACK balance-folding, cashout-CURSE, deity-SMITE) are implemented soundly against the design-lock spec. The hard floor is proven empirically: RNG-freeze intact (the four surfaces read no VRF/block entropy in any player-manipulable window) and SOLVENCY-01 holds (`claimablePool == Σ(claimable+afking halves)` and `≤ bal + stETH`) across every afking spend path at 32,768 invariant calls / 0 reverts. The adversarial sweep's three independent lenses converged on the same verdict.

| Disposition | Count |
|---|---|
| CATASTROPHE / HIGH / MEDIUM (contract fix required) | **0** |
| LOW — accepted by-design (griefing, EV-negative, cheap cure) | 2 |
| INFO — confirmations of correct design | 10 |
| Class-(c) TEST candidates (non-bugs, test-side) | 2 (C-1, C-2) |

**No contract edit is required to ship v61.** Every empirical proof passes against the shipped `b97a7a2e` implementation; every adversarial candidate either has a structural guard that blocks it or fails the 3-condition EV lens.

### Empirical foundation (phase 378 — the hard floor, proven not asserted)

| Req | Surface | Proof (forge, all green) |
|---|---|---|
| TST-01 | AFPAY waterfall | `msg.value→claimable→afking` across all 3 pay-kinds; `AfkingSpent` at exact amounts; both-short revert; fresh-rate affiliate no-rebuy; no auto-buy double-draw. (V61AfpayWaterfall, 10) |
| TST-02 | PACK | `[afking\|claimable]` half round-trip via raw-slot reads; `claimablePool == Σ`; gameOver preserves infra afking halves; no cross-half carry. (V61Pack, 8) |
| TST-03 | CURSE SET | +2 stale-only; every exemption by contrast; `curse*100` bps floored 0 on view + frozen snapshot; `min(2N,20)` saturation, no uint8 wrap; same-day-second-claim revert. (V61CurseSet, 13) |
| TST-04 | CURE + bounty + decurse | cure on every ≥1-ticket buy path; sub-ticket stamps DAY_SHIFT but does not cure; `decurse` 100 BURNIE clears + `Decursed`. (V61CureBountyDecurse, 13) |
| TST-05 | SMITE | `ownerOf` gate, active-afker immunity, ceiling, 200-BURNIE burn, shared counter, single-cure. (V61Smite, 10) |
| TST-06 | NON-WIDENING | full forge suite BY NAME vs `2bee6d6f`: `live − (baseline ∪ documented candidates) == ∅`; 54 new proving tests green; 112 baseline names narrowed to green; zero new contract regression. (378-05 ledger + REGRESSION-BASELINE-v61.md §7) |
| SEC-01 | RNG-freeze (DOMINANT) | two-block determinism replay (perturbed prevrandao/coinbase/number/timestamp) → AFPAY/CURSE/SMITE byte-identical; backward-traced no-`rngWord` grep. (V61RngFreezeIntact, 6) |
| SEC-02 | SOLVENCY-01 (SPINE) | `claimablePool == Σ(halves)` + `≤ bal+stETH` invariants, 256×128 = 32,768 calls / 0 reverts, real slot 7, no `vm.store` fabrication; smite/decurse pool-neutral. (V61SolvencyAfpay.inv + handler, 7) |

Verifier independently re-ran all 8 and recomputed the non-widening set-diff by name (`live − UNION == 0`). Contracts byte-identical throughout.

### Adversarial sweep verdict (379 — three independent read-only lenses)

| Lens | Findings | Contract-change-needed |
|---|---|---|
| Security + gas (1000-ETH attacker) | 1 LOW (by-design grief) + 6 INFO | **NONE** |
| Economic / game-theory (EV lens) | 1 LOW + 4 INFO | **NONE** |
| Zero-day / composition (bug-shapes) | 0 real (all INFO) | **NONE** |

All three lenses verified byte-identical contracts after their sweep (no rogue edits).

---

## 1. AFPAY waterfall — solvency exact across all spend paths — INFO

`shortfall = amount − ethUsed − claimableUsed ≥ 0` for all three pay-kinds (Combined guards `msg.value > amount`; DirectEth/Claimable cap each tier at `amount`), so `prizeContribution == ethUsed + claimableUsed + afkingUsed == amount` exactly, or it reverts when afking is short. All 6 `_settleShortfall` sites migrated; the old `_settleClaimableShortfall` is fully removed. Every claimable/afking debit pairs exactly one `claimablePool -=`. DirectEth can now be partially afking-funded (the intended feature) and still skips claimable; the affiliate `freshEth` for a DirectEth+afking buy correctly equals the full cost (own principal). **No contract change.** (`DegenerusGameStorage.sol:_settleShortfall`, `DegenerusGame.sol:_processMintPayment`, `DegeneretteModule.sol`.)

## 2. PACK — uint128 halves overflow/borrow-safe — INFO

Per-player ETH ≤ total ETH supply (~1.2e26 wei ≈ 2^86.6), so each 128-bit half stays ≤ ~2^88 ≪ 2^128 — `_creditClaimable` cannot carry into the afking half and `_debitAfking` cannot borrow from the claimable half. `_debitClaimable` guards `uint128(low) < weiAmount` before the full-word subtract; `_debitAfking` is fail-loud (whole-word underflow reverts) when afking is short. Borrows propagate up, never down. **No contract change.** (`DegenerusGameStorage.sol` accessors.)

## 3. RNG-freeze holds — curse/smite mutate only the LIVE score — INFO (DOMINANT class)

Every activity-score consumer that touches a VRF word **snapshots** the score into frozen storage at request/submit time (Degenerette `FT_ACTIVITY_SHIFT`, sDGNRS `claim.activityScore`, afking box `sub.scorePlus1`, decimator `e.bucket`) and resolution reads the snapshot, never the live `_playerActivityScore`. The curse counter only changes the live score → affects FUTURE snapshots only. A smite/cure applied between an RNG request and fulfillment is a no-op on the pending outcome. AFPAY/PACK read no VRF word. No 5th `rngWord` surface in the delta. Confirms SEC-01. **No contract change.**

## 4. Deity SMITE — profitless capped grief, free target cure — LOW (accepted by-design)

A deity burns 200 BURNIE per +2 stack (smite ceiling = 5 stacks / −1000 bps) to lower a target's activity score. The activity score is a **self-multiplier** (BurnieCoin bonus, lootbox EV taper, Degenerette ROI, sDGNRS redemption EV) — not competitive winner-selection — so the deity gains nothing; pure spite at a BURNIE sink cost. The one zero-sum consumer (the decimator pool) reads the score **live at burn time**, so the target erases the entire penalty with a single ≥1-ticket buy (auto-cure) or 100 BURNIE `decurse` — a 200–1000 BURNIE attack inflicting a ≤3.3% weight reduction the victim removes for ~100 BURNIE, and only on victims below the 23,500-bps cap. Fails the EV lens; matches the SPEC's accepted self-smite/grief disposition. **No contract change.**

## 5. SMITE/CURSE → decimator weight — the only zero-sum path, not profitable — LOW (accepted)

The decimator is the lone mechanic where one player's lower weight raises others' pro-rata share of a fixed pool. Three compounding frictions kill the attack: (1) live-read at burn time → trivially curable; (2) the attacker captures only a diluted slice of a ~3% reduction, not the victim's lost share; (3) it only bites uncapped victims. Certain 200–1000 BURNIE sink vs. tiny, curable, diluted, probabilistic gain. **No contract change.**

## 6. Active-afker curse/smite immunity is gated behind FUNDED participation — INFO

`maybeCurse`/`smite` exempt `dailyQuantity != 0`. `subscribe()` needs no `msg.value`, but an unfunded sub is funding-killed on the first processing pass (`_finalizeAfking` → `delete _subOf[player]` → `dailyQuantity = 0`), so durable immunity requires genuinely funded daily auto-buys — the honest participation the curse rewards. Self-aligning. **No contract change.**

## 7. AFPAY afking-funded buys earn fresh-rate affiliate by design, not arbitrage — INFO

Afking funding is the player's own pre-deposited principal; spending it genuinely moves principal into the prize pool, so "fresh-rate" is economically accurate (fresh principal, just pre-deposited). Affiliate rewards are minted BURNIE (inflation, not extraction); self-referral is blocked. The "no rebuy bonus" exclusion is correct — that bonus keys on `claimableWinnings` deltas, which afking is not, so it is excluded automatically. **No contract change.**

## 8. `_settleShortfall` does not enable value-extractive buying — INFO

Every tier debits the buyer's own balance and pairs an equal `claimablePool -=` (pool-neutral); `prizeContribution` only ever equals what was actually drawn. You can only spend value you already hold; nothing is created. SOLVENCY-01 preserved. **No contract change.**

## 9. Curse-counter slot-clobber via shared `mintPacked_` writers — INFO (clobber-free)

All 14 full-word `mintPacked_` writers start from a fresh read and mutate only their own fields via mask-clear-then-OR (field-isolated); none touches the curse bits 215-222. `_clearCurse` runs LAST in `_purchaseForWith` (so a curing buy scores un-penalized) and does its own fresh RMW; nothing after it writes the slot. The PACK balances mapping is a different slot. Producer-before-consumer discipline held. **No contract change.**

## 10. AFPAY-spend × gameOver claimable-zeroing — no double-spend — INFO

Every afking-spend path reverts when `_livenessTriggered()`; the post-gameOver afking-claim merge only fires when `gameOver == true`. Liveness, once triggered, stays true through gameOver, so buys are dead exactly when the merge is live — mutually exclusive. **No contract change.**

## 11. SMITE/decurse direct-call neutralization + reentrancy — INFO

Called directly on the deployed module (not via the Game's delegatecall), `coin.burnCoin(...)` carries `msg.sender == module ≠ GAME` → BurnieCoin's `onlyGame` reverts; no state mutated. CEI: `burnCoin` (a pure balance decrement, no external callback) precedes the curse write, but re-entry would only re-burn the attacker's own BURNIE against the capped counter — self-funded, bounded, no profit. **No contract change.**

## 12. Gas — AFPAY/SMITE add no advanceGame-chain regression — INFO (HIGH class, no finding)

The 305-winner jackpot ETH leg is still one SLOAD + one SSTORE + one event per winner (PACK touches the same single paired slot). Paths touching both halves for one player now touch ONE slot (savings). The curse penalty rides an already-loaded `packed` SLOAD (zero new SLOAD). No AFPAY/SMITE code on an unbounded advance loop. STAGE_2 worst case re-measured LIVE = **13.61M / 3.09M headroom** under the 16.7M ceiling. Confirms the 377 Outcome-A gas-neutral ruling. **No contract change.**

---

## Class-(c) TEST candidates (test-side, NOT contract bugs)

- **C-1 — `testFuzzTwoBlockOpenNoBlockEntropy` (V56FreezeSolvency):** the deferred afking box does not materialize a `LootBoxOpened` event under the `_openAfkingBoxAt` fixture driver. Shares its root with two in-union baseline-red siblings (red at `2bee6d6f`); lootbox queue-then-materialize is intentional UX. Resolution is a fixture-driver upgrade, not a contract fix.
- **C-2 — gap-backfill word-derivation fuzz variants (VRFStallEdgeCases / VRFPathCoverage):** the TEST computes the expected gap word as `keccak256(abi.encodePacked(resumeWord, uint32(day)))` while the contract uses `uint24(gapDay)` (`DegenerusGameAdvanceModule.sol:1844`, typing predates v61). The test is wrong, not the contract; its in-union siblings are carried-red by the non-widening discipline. No RNG-manipulability angle.

Both carried forward as known test-side non-bugs; neither is a v61 contract finding.

---

## Verdict

**v61.0 is sound and ships without any contract change.** RNG-freeze and SOLVENCY-01 — the milestone's dominant and spine invariants — are proven empirically, not asserted; the non-widening gate confirms zero new contract regression vs `2bee6d6f` by name; and a three-lens adversarial sweep found nothing that survives a structural-guard check or the EV lens. The two LOW items are accepted-by-design griefing (EV-negative, trivially cured); the two class-(c) candidates are test-side. Contract tree byte-identical to the hand-reviewed `b97a7a2e` IMPL throughout. Not pushed.
