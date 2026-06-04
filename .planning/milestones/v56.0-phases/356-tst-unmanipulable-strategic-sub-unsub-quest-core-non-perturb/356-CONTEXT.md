# Phase 356: TST — Unmanipulable (strategic sub/unsub) + Quest-Core Non-Perturbation + Two-Path-Open + Liveness Valve + Gap-Decouple + Gas Marginals + Non-Widening - Context

**Gathered:** 2026-06-02
**Status:** Ready for planning

<domain>
## Phase Boundary

Phase 356 is the **v56.0 TST proof phase** — prove the milestone behaviorally correct and the
hard security floor EMPIRICALLY against the v55-frozen baseline tree. **Test-only: ZERO
`contracts/*.sol` mutation** (the audit subject stays byte-frozen; this is a `test/` +
`.planning/` phase like v55's 351). Owns **SEC-01, SEC-02, LIVE-01, GAS-06**.

**What is being proven (the SHIPPED v56 surface, not the stale SPEC text):** the IMPL diff
`e18af451` + the 355 gas tune + the two USER liveness adds (`414c8260`→`3d969621`, PUSHED). The
afking streak shipped as **compute-on-read** (decay-on-read + gap-reset-on-resume) — **there is
NO settle day**; the "per-settle marginal" wording in the old ROADMAP/REQUIREMENTS 356 text is
STALE. Reward is the per-day **`pendingBurnie`** accrual pulled via permissionless
**`claimAfkingBurnie`**; the STAGE uses a **single weighted `SUB_STAGE_WEIGHT_BUDGET=1000`** (the
two-batch split was obviated by compute-on-read); `OPEN_BATCH=130`; single-roll open;
**`openBoxes(maxCount)`** unified valve + the **gap/jackpot decouple** (`STAGE_GAP_BACKFILLED`).

**In scope:** SEC-01 (unmanipulable, esp. strategic sub/unsub — the PRIMARY concern) + SEC-02
(SOLVENCY-01 byte-unchanged + RNG-freeze intact) + quest-core non-perturbation (QST-04) + two-path
open coexistence + LIVE-01 (`openBoxes` valve) + GAS-06 (gap/jackpot decouple) + per-advance /
per-buy / per-open gas marginals under the 16.7M HARD per-tx ceiling + the NON-WIDENING regression
ledger (`REGRESSION-BASELINE-v56.md`) + the stale-Sub-offset fuzz migration.

**Out of scope:** any `contracts/*.sol` change; the 3-skill genuine-PARALLEL adversarial sweep +
XMODEL cross-model close + delta-audit + `audit/FINDINGS-v56.0.md` + the closure flip (all
**Phase 357 / AUDIT-01**); the v50/v51/v52 consolidated cross-model audit debt.

</domain>

<decisions>
## Implementation Decisions

### SEC-01 — unmanipulable / strategic sub/unsub (the PRIMARY concern)
- **D-01 (method):** Prove the property with **BOTH stateful property-fuzz invariants AND named
  repro tests.** Fuzz drives random `sub`/`unsub`/`buy`/`claim`/`open` sequences asserting global
  invariants (no churn sequence increases total credited BURNIE/affiliate beyond honest continuous
  play; effective streak never exceeds the funded-delivered-day span). Named repros anchor each
  designed-against vector as a legible "this exact vector is closed" regression. Matches the v55
  fuzz+repro pattern.
- **D-02 (named repro set — ALL FOUR required):**
  1. **Affiliate re-claim churn** — sub → accrue `affiliateBase` → unsub → re-sub repeatedly:
     prove total credited to uplines (`claimAfkingBurnie` / the affiliate `drain`/`claim` path)
     EQUALS honest continuous-sub accrual. `affiliateBase` persists across unsub (NOT flushed on
     mutation) → **forfeit-nothing-gain-nothing**; churn neither forfeits nor duplicates.
  2. **Streak decay / gap dodge** — compute-on-read: miss ONE funded day → effective streak reads
     0 (decay-on-read, `afkCovered < currentDay-1` → 0); resume after a gap → `afkingStartDay`/
     `streakAtAfkingStart` reset on the delivered day (no stale-span credit); the per-window streak
     advances ONLY on debit-DELIVERED days (the C3-a non-funded dodge stays closed).
  3. **pendingBurnie double-claim idempotency** — `claimAfkingBurnie` double-call in one block /
     re-entrancy attempt / claim→unsub→claim pays the accrued balance EXACTLY ONCE, zeroed
     **CEI-before-credit** (`s.pendingBurnie = 0` precedes the external `creditFlip`,
     `GameAfkingModule.sol:1277`). No harvest / duplicate settlement.
  4. **4 finalize hooks before slot-delete** — each sub-ending path (explicit cancel
     `subscribe(_,0)`; cancel-reclaim that DELETES `_subOf`; pass-eviction crossing; funding-kill)
     writes the **decay-applied final streak** to `DegenerusQuests` BEFORE the slot is deleted
     (`_finalizeAfking`, load-bearing ordering since the afking streak state lives in the Sub slot);
     funding-kill zeroes ONLY if `lastValidMintDay <= currentDay-2` (a sub that kept minting
     MANUALLY is NOT wrongly zeroed — the `currentDay-1` grace + any-valid-mint decay).
- **D-03 (accepted-by-design, NOT a finding):** the first-sub-only `+0..+9` `+daysToNextSettle`
  head-start (QST-02) is **USER-ACCEPTED-BY-DESIGN** — 356 treats it as accepted (the activity-score
  still reads the actual `state.streak`); do NOT flag it as a missed control.

### QST-04 — shared DegenerusQuests-core non-perturbation (FULL empirical coverage in 356)
- **D-04:** Prove non-perturbation EMPIRICALLY in 356 (not deferred to 357):
  - **slot-1 (the player's own random/manual quest) stays FULLY ACCESSIBLE every day during afking**
    and is **STREAK-NEUTRAL** — a slot-1 completion during afking must NOT advance the afking
    compute-on-read streak (`afkingActive` flag gates it; a cheap slot-1 bump must not re-open the
    C3-a non-funded streak dodge). For a NON-afking player, slot-1 advances the streak normally.
  - **manual / bingo / degenerette / boon quest callers** (`awardQuestStreakBonus`, etc.) produce
    **byte-identical results with afking subs present vs absent** — the new `beginAfking` +
    finalize-write entrypoints added to the shared core do not perturb the other callers.

### SEC-02 — SOLVENCY-01 byte-unchanged + RNG-freeze intact
- **D-05:** Prove with **byte-diff assertion + freeze/solvency fuzz** (three legs):
  1. **ETH/`claimablePool` debit path byte-unchanged vs `453f8073`** — a grep/diff anchor recorded
     in the test ledger (the v55 pattern); the affiliate/quest rewards remain BURNIE flip-credit
     OFF the ETH/pool path.
  2. **Solvency invariant fuzz** — `balance + steth.balanceOf(this) >= claimablePool` holds across
     churn / accrue / `pendingBurnie` claim sequences.
  3. **RNG-freeze determinism fuzz** — the new surfaces (the subscribe **min-buy** that STAMPS
     for-later-open and NEVER inline-resolves pre-RNG, the single-roll open, the `pendingBurnie`
     BURNIE credit) consume ONLY the frozen day-word; no entropy added between RNG request and
     unlock.

### GAS-06 + the 16.7M per-tx ceiling (the deferred per-tx measure)
- **D-06 (per-advance ceiling proof):** Add a forge harness that drives a worst-case **multi-day
  VRF-stall resume** and asserts EACH `advanceGame` tx is `< 16,777,216` INDIVIDUALLY — the
  gap-backfill advance N AND the jackpot-paying advance N+1 (the existing
  `test_gapBackfillMaxGap_fuzz` only bounds the ~25M TOTAL resume, not per-tx). ALSO empirically pin
  the proof's 4 named residuals (currently estimates in the LOCAL `audit/PROOF-...`): level-crossing
  STAGE iteration, mixed-stamp-day `OPEN_BATCH` (cache-defeating), heaviest single
  `processTicketBatch` entry, [the 4th residual].
- **D-07 (decouple regression — FULL idempotent-resume invariants):** advance N sets
  `STAGE_GAP_BACKFILLED` + pays NO jackpot; advance N+1 pays the day's jackpot **with the SAME frozen
  word**; `rngGate` returns `gapDays == 0` on re-entry (no re-backfill); `dailyIdx` NOT advanced so
  `advanceDue()` stays true; `purchaseStartDay` bumped EXACTLY ONCE across the resume; no double
  jackpot, no skipped day. Closes the Codex-found protocol-forced composition breach.

### LIVE-01 — openBoxes valve + two-path-open coexistence
- **D-08:** Prove (drain + bound + coexist + byte-unchanged):
  - bounded `openBoxes(maxCount)` chunks each `< 16.7M`; **repeated bounded calls fully DRAIN** any
    backlog of EITHER box type (both persistent cursors advance, no stuck box);
  - **afking-first-then-human** ordering with the remaining budget; uncapped/unrewarded/permissionless;
  - **two-path coexistence** — the afking-stamp open and the human open share no mutable state that
    lets one corrupt or double-open the other (the shared per-`(player,level)` budget holds; the
    `lastOpenedDay` monotone no-double-open holds);
  - **individual `openLootBox(player,index)` + the rewarded `mintBurnie` open path byte-unchanged**;
    `drainAfkingBoxes` reachable ONLY via the `openBoxes` delegatecall (no `autoOpen` selector
    collision).

### Gas marginals — regression-lock posture
- **D-09:** **Re-assert the GAS-01..04 wins as regression locks** (guard future drift): the per-buy
  (lootbox ~130–140k; ticket off the ~262k `purchaseWith` heavyweight) + per-open marginals asserted
  against a recorded LOOSE bound (a ceiling, not a brittle exact number) so a regression fails the
  gate. **Extend `test/gas/V56AfkingGasMarginal.t.sol`** (+ `KeeperOpenBoxWorstCaseGas.t.sol`) rather
  than authoring a new suite — land the per-tx gap-resume + GAS-06 + LIVE-01 cases there.

### Claude's Discretion (the two unselected gray areas — defaults locked)
- **D-10 (fuzz-offset migration — MIGRATE ALL):** the ~10 `test/fuzz/` files still carrying the
  stale `OFF_LASTBOUGHT = 21`/uint32 layout (`AfKingConcurrency`, `AfKingFundingWaterfall`,
  `AfKingSubscription`, `KeeperRouterOneCategory`, `KeeperFaucetResistance`,
  `KeeperRewardRoutingSameResults`, `KeeperNonBrick`, `V55SetMutationOpenE`, `V55RevertFreeEvCap`,
  `V55FreezeDeterminism`) are **all migrated to `OFF_LASTBOUGHT = 11`/uint24** (+ the re-packed
  32-byte 13-field Sub layout), the SAME mechanical fix already applied to the gas suites in
  `08e59a4a`. These are the ~13+ `6555125 != 3774873600` garbage-read reds. Rationale: deterministic
  test-only fix, low risk, removes false-green risk (SweepPerPlayer was a false green), and makes the
  NON-WIDENING ledger legible (red→green is a NARROWING, never a widening).
- **D-11 (framework + baseline anchoring):** new v56 proofs authored in **Foundry forge** (matches
  the V56 harness + the fuzz corpus + the existing gas suites; the security/fuzz/freeze/gas
  properties are forge-native). `REGRESSION-BASELINE-v56.md` is anchored by **empirically checking
  out `453f8073`** (the v55 frozen subject) and running its FULL tree to establish the baseline-red
  union BY NAME — the same method v55 used off `20ca1f79` (the v56 contract tree DIFFERS from
  `453f8073`: the IMPL diff + gas tune + `openBoxes` + decouple). The binding headline is **"by NAME,
  never a bare count": at the v56 TST HEAD, the live `forge test` failing set − the `453f8073`
  baseline red union == ∅.** Enumerate BOTH the forge AND the hardhat suites (v55's ledger was
  603/134/16 spanning both). The offset migration's red→green deltas are recorded as NARROWING.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (researcher, planner) MUST read these before planning or implementing.**

### v56 milestone scope + requirements
- `.planning/ROADMAP.md` — Phase 356 entry + the v56.0 milestone shape (NOTE: the 356 "per-settle
  marginal" text is STALE; the shipped design is compute-on-read with no settle day — see D-06/domain).
- `.planning/REQUIREMENTS.md` — SEC-01, SEC-02, LIVE-01, GAS-06 (the 4 owned requirements) +
  Traceability.
- `.planning/phases/355-gas-measure-tune-per-buy-per-open-per-settle-marginals-accum/355-CONTEXT.md` —
  **the SUPERSEDING compute-on-read design** (decay-on-read, gap-reset-on-resume, the 4 finalize
  hooks + slot-delete ordering, the subscribe min-buy, manual-neutral slot-1, the weighted budget,
  the one-slot 32-byte Sub layout). The authoritative description of WHAT shipped.
- `.planning/phases/353-spec-design-lock-unmanipulable-solvency-re-attestation-xmode/353-CONTEXT.md` —
  the SPEC-era decisions (O1/QST-05 fix D-01..05, AFF leaderboard D-06/07, century-parity D-10).

### The shipped contracts under test (frozen — do NOT edit)
- `contracts/modules/GameAfkingModule.sol` — `subscribe` (+ min-buy + `beginAfking`),
  `_streakOf`/`_finalizeAfking` (compute-on-read + decay), `pendingBurnie` accrue,
  `claimAfkingBurnie` (CEI), `drainAfkingBoxes`, `openBoxes`, `_openAfkingBox`/`resolveAfkingBox`,
  `OPEN_BATCH=130`.
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `STAGE_GAP_BACKFILLED`, `rngGate`
  (idempotent gap backfill), `payDailyJackpot` decouple, `SUB_STAGE_WEIGHT_BUDGET=1000` + the weighted
  STAGE chunker.
- `contracts/storage/DegenerusGameStorage.sol` — the re-packed 32-byte/13-field Sub slot
  (`OFF_LASTBOUGHT` = byte 11, uint24 day markers, `afkingStartDay`/`streakAtAfkingStart`,
  `pendingBurnie`, `amount` uint24/milli-ETH). Confirm offsets via
  `forge inspect DegenerusGame storageLayout`.
- `contracts/DegenerusQuests.sol` — `beginAfking` + the finalize-write entrypoint + the
  manual/bingo/degenerette/boon callers (`awardQuestStreakBonus`); the O1 `:890` double-credit fix.

### The test corpus + the NON-WIDENING precedent
- `test/REGRESSION-BASELINE-v55.md` — the EXACT pattern to follow for `REGRESSION-BASELINE-v56.md`
  (by NAME, empirical baseline-union checkout, narrowing accounting, the binding headline).
- `test/gas/V56AfkingGasMarginal.t.sol` — the existing v56 gas-marginal harness to EXTEND (D-09).
- `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` — open worst-case (already on the uint24 layout).
- `test/fuzz/` — the ~10 stale-offset files to migrate (D-10) + the v55 freeze/EV-cap/set-mutation
  proofs to adapt for the compute-on-read surface.

### The worst-case proof (LOCAL, gitignored — will NOT persist in git)
- `audit/PROOF-V56-16P7M-GAS-CEILING.md` — the 3-model worst-case loop audit; 356 empirically pins
  its per-tx gap-resume estimate + the 4 named residuals (D-06).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`test/gas/V56AfkingGasMarginal.t.sol`** (already uint24/`OFF_LASTBOUGHT=11`) — extend for the
  per-tx gap-resume ceiling, GAS-06, LIVE-01, and the marginal regression locks (D-06/07/08/09).
- **`test/REGRESSION-BASELINE-v55.md`** — copy the structure verbatim for v56 (the "by NAME"
  headline, the empirical-checkout method, the narrowing ledger).
- **v55 fuzz proofs** (`V55FreezeDeterminism`, `V55RevertFreeEvCap`, `V55SetMutationOpenE`) — the
  freeze-determinism + set-mutation + two-path patterns are the closest analogs for the SEC-01/02
  fuzz invariants; adapt to the compute-on-read + `pendingBurnie` + `openBoxes` surface.

### Established Patterns
- **NON-WIDENING by NAME, never a bare count** — the v55/v49 gate: live failing set − baseline union
  == ∅; the baseline union is established EMPIRICALLY by checking out the baseline commit and running
  its tree (because the contract trees differ). Baseline = `453f8073`.
- **Zero contract mutation in a TST phase** — the audit subject stays byte-frozen; all work lands in
  `test/` + `.planning/`.
- **CEI-before-credit** — `claimAfkingBurnie` zeroes `pendingBurnie` before the external `creditFlip`
  (the idempotency/reentrancy anchor for D-02.3).
- **Sub-slot direct-storage probing in tests** — fuzz tests read the packed Sub slot via the
  `OFF_LASTBOUGHT` offset constant; the migration (D-10) fixes the stale 21/uint32 → 11/uint24.

### Integration Points
- The compute-on-read streak crosses `GameAfkingModule` (Sub slot, the per-buy local compute) ↔
  `DegenerusQuests` (the subscribe-time `beginAfking` snapshot + the finalize-write on the 4 ending
  paths). The non-perturbation tests (D-04) exercise this boundary.
- The two-path open: `openBoxes` (delegatecall → `drainAfkingBoxes` then the human leg) ↔ the
  individual `openLootBox` + the rewarded `mintBurnie` open; the coexistence test (D-08) asserts no
  shared-state hazard.

</code_context>

<specifics>
## Specific Ideas

- **The shipped design is compute-on-read, NOT settle-day** — this is the single most important
  grounding fact for the test author. Any test that assumes a "settle day" / `SETTLE_PERIOD` streak
  write / two-batch split is testing a SUPERSEDED design. Streak = computed on read with decay;
  reward = per-day `pendingBurnie` pulled via `claimAfkingBurnie`; the STAGE is a single weighted
  budget.
- **`453f8073` is the NON-WIDENING baseline anchor** (the v55 frozen subject), reached the v55 way:
  empirical checkout + full-tree run for the red union by NAME.
- **The 16.7M proof is LOCAL/gitignored** — its per-tx gap-resume number (est. STAGE ~6.8M + backfill
  ~9M ≈ 15.8M) is an ESTIMATE; 356 makes it an empirical per-advance assertion.
- **The 4th proof residual** (D-06) should be read from `audit/PROOF-V56-16P7M-GAS-CEILING.md` at
  research time and named explicitly in the plan.

</specifics>

<deferred>
## Deferred Ideas

- **The 3-skill genuine-PARALLEL adversarial sweep + XMODEL Codex/Gemini cross-model close +
  delta-audit + `audit/FINDINGS-v56.0.md` + the closure flip** → **Phase 357 / AUDIT-01** (the FULL
  in-milestone close). 356 is the EMPIRICAL gate; 357 is the adversarial re-confirmation.
- **The v50/v51/v52 consolidated cross-model audit debt** → the separate v52 track (NOT v56).
- **The O1 lootbox-quest double-credit** was FIXED in the v56 IMPL (`353-CONTEXT` D-03) — not a 356
  open item; the regression that it stays single-credit is covered by the quest-core non-perturbation
  + solvency fuzz.

None — discussion stayed within phase scope.

</deferred>

---

*Phase: 356-tst-unmanipulable-strategic-sub-unsub-quest-core-non-perturb*
*Context gathered: 2026-06-02*
