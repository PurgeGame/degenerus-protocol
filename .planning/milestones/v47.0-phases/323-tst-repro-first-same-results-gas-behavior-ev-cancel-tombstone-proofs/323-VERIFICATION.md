---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
verification: goal-backward
verdict: PASSED
date: 2026-05-25
audit-subject: fabe9e94
note: TST proofs green + a real MEDIUM insolvency surfaced, fixed (USER-approved guard), and proven closed
---

# Phase 323 — VERIFICATION (TST — Repro-First + Same-Results Gas + Behavior/EV + Cancel-Tombstone)

**Verdict: PASSED (5/5 success criteria) + 1 real finding surfaced→fixed→proven.**

Phase 323 hard-tested the v47.0 batched diff and, beyond proving the 5 planned criteria,
surfaced a real MEDIUM insolvency (which the audit then fixed). Audit subject advanced from
`fb29ed51` → **`fabe9e94`** (the v47 diff + the one-line Degenerette liveness guard).

## ROADMAP success criteria (5)
1. ✅ **REDEEM-08 repro-first** — the two-claimant unchecked-debit underflow was written FIRST and
   shown FAILING pre-fix (wraps `claimableWinnings[SDGNRS]` to 2²⁵⁶−3 ether) then PASSING post-fix;
   StakedStonkRedemption 15/15, RedemptionAccounting invariants 16/16 (BURNIE-can't-block-ETH +
   conservation + no-unchecked-claimable-debit all green). (323-03)
2. ✅ **DGAS-05 same-results** — Degenerette write-batching proven byte-identical (Tier-1 additive,
   Tier-2 identical-spin cap, per-betId lootbox, per-spin DGNRS); DegeneretteFreezeResolution 8/8. (323-04)
3. ✅ **DSPIN-02 worst-case gas** — derived-then-measured: 25-spin ETH 485k gas (62× headroom),
   max 45-spin mixed 619k; absorption proven (485k < 2.5× legacy 197k). (323-04)
4. ✅ **TOMB-04 cancel-tombstone** — 4 named tests + 4 new `didWork` cases green; H-CANCEL-SWAP-MISS
   empirically resolved; 318-04 guarantees re-confirmed; AfKing 37/37 fuzz. (323-05)
5. ✅ **TOMB-05 stale gas-test** — `testGas04` repaired to the post-OPENE-01 `Sub` shape (byte-sum 31,
   `fundingSource`, bools-folded). (323-01)

## Finding surfaced + remediated (exceeds phase scope)
- **MEDIUM insolvency (pre-existing):** `DegeneretteModule.resolveBets` lacked a `_livenessTriggered()`
  guard → a Degenerette ETH bet placed pre-game-over, resolved post-drain, credited `claimableWinnings`
  from the already-distributed `futurePool` residual → `claimablePool > balance` (unbacked).
  `323-SOLVENCY-FINDING.md`. **Fixed** (USER-approved, commit `fabe9e94`: `if (_livenessTriggered()) revert E();`
  mirroring `claimWhalePass`). **Proven closed:** `testResolveBetsRevertsPostGameOver_InsolvencyReproClosed`.
- **Bug-class sweep: 0 siblings** (`323-BUGCLASS-SWEEP.md`) — all other ETH-obligation credit paths are
  `advanceGame`-gated, self-call-only, real-ETH-backed, or backed-by-upstream-reservation; LootboxModule
  has zero ETH-credit sites. The v47 presale-credit model is solvent by construction (`presaleBoxCredit`
  is a non-monetary gate; box obligations grow only by retained ETH).
- **5 stale-harness solvency invariants re-greened** via principled obligation-formula correction
  (`SolvencyObligations.sol`: include `prizePoolPendingPacked`, exclude dead post-GO `futurePool`).

## Baseline (NON-WIDENING)
Full foundry: **598 pass / 38 fail / 16 skip** (vs v46 closure 565 / 45 / 16 — more passing, fewer
failing). Residual 38 = 32 pre-existing-v46 (byte-identical at `16e9668a`) + 5 combined-run fuzz-replay
cache noise (pass isolated) + **1 explained v47-delta**. Hardhat: 199/3 (3 pre-existing v46).

## Handoff to Phase 324 (TERMINAL)
- **VRFLifecycle calibration (the 1 v47-delta):** `test_vrfLifecycle_levelAdvancement` — the v46-calibrated
  purchase volume no longer reaches the 50-ETH level-0 bootstrap under the v47 rake-free/presale split.
  A test recalibration (SPEC-intended economics), NOT a contract defect → Phase 324 PRESALE economic re-verify.
- **OBS-1 (pre-existing, out of v47 scope):** `DecimatorModule` re-credits a sub-2.25-ETH whale `remainder`
  to `claimableWinnings` without a matching `claimablePool +=` (an UNDER-reservation, opposite direction
  from the Degenerette over-credit; pre-game-over only; byte-identical to v46) → optional Phase 324 review.
- The 0x11 ticket-queue cluster is pre-existing v46 (harness `block.timestamp` underflow), not v47.

**Phase 323: COMPLETE.** Audit subject frozen at `fabe9e94` for the Phase 324 delta-audit + sweep + closure.
