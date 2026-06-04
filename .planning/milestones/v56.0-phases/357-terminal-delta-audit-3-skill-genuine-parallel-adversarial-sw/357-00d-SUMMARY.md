---
phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw
plan: 00d
subsystem: testing
tags: [foundry, solidity, afking, subscribe-hardening, d-11, slot-0-idempotency, non-widening, regression-ledger, delta-audit, adversarial-sweep]

requires:
  - phase: 357-00b
    provides: "HEAD'' 61315ecd (the advance-incentive redesign) reconciled — the prior re-frozen subject; V56SubHardening 17 GREEN; ledger §9 (567/133/99)"
  - phase: 357
    provides: "HEAD''' 7b0b2a0b (slot-0 idempotency guard) + HEAD'''' 77d8bc88 (D-11 level-0 zero-horizon rejection) — the two newest 357 contract gates, committed + USER-approved"
provides:
  - "HEAD'''' = 77d8bc883048b3ba4213f94fc2ac5d830ba3f4a3 re-confirmed as the CURRENT re-frozen audit subject (audited == shipped)"
  - "V56SubHardening churn-idempotency + level-0 pass-gate proofs (17 → 22 GREEN): slot-0 accrued once across same-day churn + passless-at-L0 reverts NoPass + real-pass/deity/VAULT-sDGNRS subscribe OK at L0"
  - "REGRESSION-BASELINE-v56.md §10 reconciled to HEAD'''' (573/134/103; live − union == ∅ AND union − live == ∅ HOLD; SOLVENCY-01 leg-1 byte-anchor held; the 4 D-11-level-0 supersession reds vm.skip-dropped per §3b/§8c)"
  - "357-01-DELTA-AUDIT §3.8 records the two follow-up gates NON-WIDENING (control-flow-only / revert-only); 357-02-ADVERSARIAL-LOG records the slot-0 advisory RESOLVED + the D-11 level-0 gap (USER-caught, sweep-missed) RESOLVED — clean close with THREE resolved-in-phase items, 0 unresolved FINDING_CANDIDATE"
affects: [357-03, 357-04]

tech-stack:
  added: []
  patterns:
    - "churn-idempotency proof: subscribe -> funded cover-buy -> cancel (dailyQuantity 0, tombstone in place) -> subscribe (same day) accrues the flat per-day slot-0 BURNIE EXACTLY ONCE; a NEXT-day subscribe (lastAutoBoughtDay != today) does a fresh funded buy"
    - "level-0 boundary proof: the existing D-11 negative ran at level >= 1 (poked level); the level-0 arm requires _setLevel(0) + a funded passless EOA to hit the zero-horizon rejection specifically"
    - "revert-reason-flip detection: when a control-flow gate tightens, scan the whole tree for fixtures whose setup relied on the old behavior; vm.skip-with-reason per the §3b/§8c removed/adapted-surface discipline, re-prove the successor GREEN"

key-files:
  created:
    - .planning/phases/357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw/357-00d-SUMMARY.md
  modified:
    - test/fuzz/V56SubHardening.t.sol
    - test/fuzz/AfKingSubscription.t.sol
    - test/REGRESSION-BASELINE-v56.md
    - .planning/phases/357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw/357-01-DELTA-AUDIT.md
    - .planning/phases/357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw/357-02-ADVERSARIAL-LOG.md

key-decisions:
  - "The D-11 level-0 fix introduced ONE revert-reason flip (4 AfKingSubscription fixtures that subscribed a passless EOA at level 0, 8/8 GREEN @ HEAD'' -> NoPass() @ HEAD''''). These are STALE-ASSERTION supersession reds (their own comment cited 'a no-pass sub clears D-11 (validThroughLevel 0 < level 0 is false)') -> vm.skip-with-reason per the §3b/§8c discipline, level-0 successors re-proven GREEN by the new V56SubHardening proofs. NOT a contract bug."
  - "The binding gate live − union == ∅ AND union − live == ∅ HOLD by NAME at HEAD'''' (the live 134 == the §2 134-name 453f8073 union, byte-identical) — NON-WIDENING. The 134==134 vs HEAD'' 133 is within the documented run-variance of the non-deterministic Bucket A/F cluster (neither gate touches VRF/RNG-window code)."
  - "SOLVENCY-01 leg-1 byte-anchor holds: both gates are revert-only / control-flow-only — the debit two-liner (afkingFunding[src] -= ethValue; claimablePool -= uint128(ethValue);) is byte-frozen, only RELOCATED :690-691 -> :702-703 by the +12-line slot-0/comment insertion above it (last touched by 77c3d9ef v349.1, long predating the two gates)."
  - "The 357-02 sweep marked D-11 NEGATIVE-VERIFIED but ran D-11 only at level >= 1 — it MISSED the level-0 boundary. Honestly disclosed (357-02 §B.3-addendum probe 11) as a USER-caught sweep gap, RESOLVED-AT-357 — not papered over."

patterns-established:
  - "When a tightening control-flow gate flips an existing fixture's revert reason, the fixture's OLD-behavior premise is a removed/adapted surface: vm.skip-with-reason + re-prove the successor in the dedicated suite (the §3b/§8c precedent), then re-confirm live − union == ∅. Do NOT 'fix' the contract or count the flip as a new red."
  - "A sweep's NEGATIVE-VERIFIED disposition is only as strong as its coverage: a boundary the probes never exercised (here level 0) is a coverage gap, not a proof. Record the gap honestly when a later review catches it."

requirements-completed: [AUDIT-01]

duration: ~25min
completed: 2026-06-03
---

# Phase 357 / Plan 00d: Subscribe-Hardening Reconciliation @ HEAD'''' Summary

**Reconciled the v56.0 terminal-audit artifacts to the CURRENT re-frozen subject HEAD'''' = `77d8bc88`, covering the two newest subscribe-hardening contract gates: HEAD''' `7b0b2a0b` (the NEW-run slot-0 per-day idempotency guard) + HEAD'''' `77d8bc88` (the USER-caught D-11 LEVEL-0 zero-horizon rejection). Added 5 positive proofs to V56SubHardening (17 -> 22 GREEN), caught + adapted the ONE revert-reason flip the D-11 level-0 fix introduced (4 AfKingSubscription passless-at-level-0 fixtures vm.skip-dropped), reconciled the NON-WIDENING ledger §10 to 573/134/103 with `live − union == ∅` AND `union − live == ∅` HOLDING, and recorded both items RESOLVED-IN-PHASE in the delta-audit + adversarial log. ZERO contract mutation: `git diff 77d8bc88 HEAD -- contracts/` is EMPTY.**

## Performance

- **Duration:** ~25 min
- **Completed:** 2026-06-03
- **Tasks:** 3/3
- **Files modified:** 5 (2 test files, 1 ledger, 2 audit deliverables) + 1 SUMMARY created

## HEAD'''' (the CURRENT re-frozen subject)

```
77d8bc883048b3ba4213f94fc2ac5d830ba3f4a3
```

The FOURTH `contracts/*.sol` commit of phase 357, layered on HEAD'' `61315ecd`:
- **HEAD''' `7b0b2a0b`** — the NEW-run subscribe per-day **slot-0 idempotency guard** (`GameAfkingModule.sol:451` `else if (s.lastAutoBoughtDay == uint24(today)) { _setStreakBase(s, snap); }`). A `subscribe → funded-buy → cancel → subscribe` loop (the cancel tombstones in place, retaining the stamp) no longer re-accrues the flat per-day `QUEST_SLOT0_REWARD`. Closes the 357-02 zero-day-hunter probe-7 EV-negative ADVISORY.
- **HEAD'''' `77d8bc88`** — the USER-caught **D-11 LEVEL-0 zero-horizon rejection** (`GameAfkingModule.sol:372` `if (!exemptSub && (s.validThroughLevel == 0 || s.validThroughLevel < level)) revert NoPass();`). The `< level` arm was vacuous at level 0 (`0 < 0` false), so a funded PASSLESS EOA (horizon 0) cleared `NoPass()` at level 0; a zero horizon is now rejected at every level. The 357-02 sweep marked D-11 NEGATIVE-VERIFIED but ran only at level ≥ 1 — it MISSED the level-0 boundary; the USER's review caught it.

Everything downstream (357-03 FINDINGS, 357-04 closure) re-freezes against HEAD''''. **`git diff 77d8bc88 HEAD -- contracts/` is EMPTY.**

## Accomplishments

1. **V56SubHardening extended with 5 new proofs (17 → 22 GREEN)** —
   - `testChurnSameDayAccruesSlot0Once` (HEAD''' slot-0 guard): a pass-holding + funded EOA's `subscribe → cover-buy → cancel → subscribe` loop accrues `pendingBurnie` EXACTLY ONCE across 5 same-day churn cycles (asserts unchanged per cycle, not 5×); a NEXT-day subscribe (`lastAutoBoughtDay != today`) does a fresh funded buy + accrues again.
   - `testD11PasslessEoaRevertsNoPassAtLevelZero` (HEAD'''' D-11 level-0): at `_setLevel(0)` a FUNDED PASSLESS EOA reverts `NoPass()` (the boundary the existing level-5 negative never reached).
   - `testD11RealPassSubscribesAtLevelZero` / `testD11DeityHolderSubscribesAtLevelZero` / `testD13VaultSdgnrsExemptAtLevelZero`: the level-0 positives — a real finite pass (horizon 99), a deity holder, and VAULT/sDGNRS all subscribe OK at level 0 (the `== 0` arm rejects only a ZERO horizon; the D-13 exemption gates the whole predicate).
   - `forge test --match-contract V56SubHardening` = **22 passed / 0 failed / 0 skipped**.
2. **Caught + adapted the ONE revert-reason flip** — the whole-tree re-run surfaced 4 `AfKingSubscription` fixtures (`testCrossingNoPassEvictedViaTombstone`, `testSubscribeNoBurnieChargeRegardlessOfPass`, `testUnapprovedFundingSourceRefusedThenHonored`, `testRevokeDoesNotStopActiveSub`) that subscribe a **passless EOA at level 0** relying on the pre-HEAD'''' vacuity (their own comment: "a no-pass sub clears D-11 (validThroughLevel 0 < level 0 is false)"). They were verified **8/8 GREEN @ HEAD''** (`/tmp/ft357.log`) and now revert `NoPass()`. Per the §3b/§8c removed/adapted-surface discipline each is `vm.skip`-with-reason (Skipped, not Failure → genuinely NON-WIDENING), each level-0 successor re-proven GREEN by the new V56SubHardening proofs. NONE is a contract bug.
3. **REGRESSION-BASELINE-v56.md §10 reconciled to HEAD''''** — counts **573 passed / 134 failed / 103 skipped** (810 run); the binding gate `live − union == ∅` AND `union − live == ∅` HOLD BY NAME (the live 134 == the §2 134-name `453f8073` union, byte-identical — name-keyed set-diff both directions EMPTY); the 4 D-11-level-0 supersession reds DROP table (§10c); the SOLVENCY-01 leg-1 byte-anchor re-confirmed (§10d); the HEAD'''' top banner added.
4. **357-01-DELTA-AUDIT §3.8 + 357-02-ADVERSARIAL-LOG reconciled** — the delta-audit attests both follow-up gates NON-WIDENING (control-flow-only / revert-only, SOLVENCY-01 untouched), updates the delta range to `453f8073 → HEAD''''`, and re-references the frozen subject. The adversarial log records the slot-0 churn advisory RESOLVED-AT-357 (HEAD''') and adds probe-11 §B.3-addendum for the D-11 level-0 gap as USER-caught / sweep-missed, RESOLVED-AT-357 (HEAD''''). Clean-closure now has THREE resolved-in-phase items (F-356-01 + slot-0 advisory + level-0 gap), still 0 unresolved FINDING_CANDIDATE.

## Task Commits

1. **Task 1: churn-idempotency + level-0 pass-gate proofs** — `30ea4b89` (test)
2. **Task 2: NON-WIDENING ledger reconcile to HEAD'''' + the 4 AfKingSubscription skips** — `519f6e00` (test)
3. **Task 3: delta-audit §3.8 + adversarial-log probe-11/RESOLVED reconciliation** — `b541c445` (docs)

## Reconciled Forge Counts @ HEAD''''

```
forge test --match-contract V56SubHardening  → 22 passed / 0 failed / 0 skipped
forge test (WHOLE tree, /tmp/ft357d2.json)   → 573 passed / 134 failed / 103 skipped  (810 run)
live − union == ∅ (the 134 failing names == the §2 134-name 453f8073 union, BY NAME)  → NON-WIDENING HOLDS
union − live == ∅ (no baseline name missing this run)                                → byte-identical by NAME
ContractAddresses.sol restored sha256 f7206e6c…   git diff 77d8bc88 HEAD -- contracts/ EMPTY
```

## Decisions Made

- **The 4 AfKingSubscription NoPass reds are a STALE-ASSERTION supersession, not a contract bug.** Their setup subscribes a passless EOA at level 0 relying on the exact vacuity the USER-caught D-11 fix closed (verified 8/8 GREEN @ HEAD'', NoPass() @ HEAD''''). They are the §3b/§8c removed/adapted-surface case: `vm.skip`-with-reason, the level-0 successor properties re-proven GREEN by the new V56SubHardening proofs. They are NOT in the §2 `453f8073` baseline union (the v55 layout + v55 behavior matched there), so the drops add nothing to the ceiling and close the only `live − union ≠ ∅` delta.
- **The 134==134 vs HEAD'' 133 is run-variance, not a new red.** The set-diff `live − union == ∅` AND `union − live == ∅` confirm the live 134 is byte-identical by NAME to the baseline 134. The HEAD'' run happened to have 133 (one Bucket-A/F member not firing that run); HEAD'''' has all 134. Both gates are revert-only / control-flow-only and touch no VRF/RNG-window code, so neither can deterministically change a Bucket-A red — the variance is the documented non-deterministic invariant/`vm.assume` cluster (ledger §4).
- **SOLVENCY-01 leg-1 byte-frozen.** `git diff 61315ecd HEAD -- GameAfkingModule.sol | grep -c <debit>` = 0; the two-liner relocated `:690-691 → :702-703` only (the +12-line insertion above it). Last touched by `77c3d9ef` (v349.1).
- **The churn test asserts the tombstone-in-place semantics correctly.** Cancel (`subscribe(…, dailyQuantity 0)`) does NOT remove the sub from `_subscriberIndex` — it writes `dailyQuantity = 0` in place (the swap-pop happens later in the STAGE), so the re-subscribe is a NEW run (`wasActive == false`) that hits the HEAD''' `lastAutoBoughtDay == today` guard. The test asserts `_dailyQtyOf == 0` after cancel (not removal from set).

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking issue] The D-11 level-0 fix flipped 4 AfKingSubscription fixtures to NoPass()**
- **Found during:** Task 2 (the whole-tree forge re-run — 138 failed before the adapt, 4 outside the §2 union)
- **Issue:** `testCrossingNoPassEvictedViaTombstone`, `testSubscribeNoBurnieChargeRegardlessOfPass`, `testUnapprovedFundingSourceRefusedThenHonored`, `testRevokeDoesNotStopActiveSub` subscribe a passless EOA at level 0 relying on the pre-HEAD'''' vacuity; the USER-caught D-11 fix now reverts `NoPass()`, making them NEW reds outside the `453f8073` union (which would trip `live − union ≠ ∅`).
- **Fix:** `vm.skip(true, "<357-00d HEAD'''' supersession reason>")` per the established §3b/§8c removed/adapted-surface DROP discipline (mirrors the 357-00b §8c D-11/D-12 supersession drops); the level-0 successor properties are re-proven GREEN by the new `V56SubHardening` proofs (the negative + the real-pass/deity/VAULT-sDGNRS positives). These were verified 8/8 GREEN @ HEAD'' first, confirming they contribute zero baseline reds.
- **Files modified:** `test/fuzz/AfKingSubscription.t.sol`
- **Commit:** `519f6e00`

This is the exact revert-reason flip the orchestrator brief anticipated ("a passless-UNFUNDED EOA at level 0 now reverts NoPass FIRST … check the whole tree"). The flip was caught by the binding NAME-set gate, traced to ground (stale-assertion supersession, not a bug), and adapted per the documented discipline — net-zero new regression.

### Out-of-scope discoveries

None new. (The 357-00b-logged pre-existing Hardhat `GovernanceGating ADMIN-02` red remains out of scope — Hardhat is not part of the forge NON-WIDENING ledger.)

---

**Total deviations:** 1 auto-fixed (Rule 3 — the revert-reason flip adapt); 0 new out-of-scope items.
**Impact on plan:** None on the NON-WIDENING gate or the contract freeze. All 3 tasks complete; `live − union == ∅` HOLDS.

## Issues Encountered

- **`testChurnSameDayAccruesSlot0Once` initially red** ("cancel tombstoned the sub out of the set: 3 != 0") — the test wrongly asserted cancel REMOVES the sub from `_subscriberIndex`. The cancel branch tombstones IN PLACE (`c.dailyQuantity = 0`, record + index kept; the swap-pop is deferred to the STAGE). Fixed the assertion to `_dailyQtyOf(p) == 0` (the tombstone) + `_dailyQtyOf(p) == 1` after re-subscribe. Re-ran → GREEN. This also confirmed the re-subscribe is a NEW run (`wasActive == false`) that correctly hits the HEAD''' idempotency guard.
- **The whole-tree run showed 138 failed (4 over the union)** before the adapt — resolved by the §3b/§8c `vm.skip` of the 4 D-11-level-0 supersession reds; the re-run then showed 134 == the union BY NAME.

## Threat Flags

None. This plan introduces no contract code; the HEAD''' slot-0 guard + the HEAD'''' D-11 level-0 rejection are both revert-only / control-flow-only and PROVEN (not modified). SOLVENCY-01 leg-1 byte-frozen. The two surfaced items (slot-0 churn advisory + D-11 level-0 gap) are BOTH RESOLVED at a 357 contract gate.

## Next Phase Readiness

- The audit subject is re-frozen at HEAD'''' `77d8bc88`. 357-03 (author `audit/FINDINGS-v56.0.md`) + 357-04 (closure flip) run READ-ONLY against it.
- The NON-WIDENING ledger §10 + the V56SubHardening 22-proof suite are the regression/behavior gate 357-03 consumes.
- 357-03 FINDINGS must record THREE resolved-in-phase items: F-356-01 (HEAD'), the slot-0 churn advisory (HEAD'''), the D-11 level-0 gap (HEAD'''') — all RESOLVED-AT-357, 0 unresolved FINDING_CANDIDATE. The level-0 gap should be honestly noted as a sweep coverage gap the USER caught.
- The closure flip (357-04) re-freezes against HEAD'''' and must re-attest SOLVENCY-01 byte-frozen + the NON-WIDENING `live − union == ∅` at HEAD''''.

## Self-Check: PASSED

- `test/fuzz/V56SubHardening.t.sol` — FOUND (22/22 GREEN @ HEAD'''')
- `test/fuzz/AfKingSubscription.t.sol` — FOUND (4 D-11-level-0 fixtures vm.skip-dropped; 4 pass / 4 skip)
- `test/REGRESSION-BASELINE-v56.md` — FOUND (§10 reconciled to HEAD''''; top banner added)
- `.planning/.../357-01-DELTA-AUDIT.md` — FOUND (§3.8 + HEAD'''' supersession banner)
- `.planning/.../357-02-ADVERSARIAL-LOG.md` — FOUND (probe-7 RESOLVED + probe-11 §B.3-addendum + §D.2b + the three-items close)
- `.planning/.../357-00d-SUMMARY.md` — FOUND (this file)
- Commit `30ea4b89` — FOUND
- Commit `519f6e00` — FOUND
- Commit `b541c445` — FOUND
- `git diff 77d8bc88 HEAD -- contracts/` — EMPTY (subject re-frozen at HEAD'''')

---
*Phase: 357-terminal-delta-audit-3-skill-genuine-parallel-adversarial-sw*
*Completed: 2026-06-03*
