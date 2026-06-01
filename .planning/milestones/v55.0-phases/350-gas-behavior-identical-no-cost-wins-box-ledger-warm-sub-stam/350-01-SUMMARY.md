---
phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam
plan: 01
subsystem: testing
tags: [gas, solidity, afking, lootbox, claimablePool, freeze, solvency, re-pin, tst-06]

# Dependency graph
requires:
  - phase: 348-spec-design-lock-freeze-proof-discharged-invariant-carry-4-p
    provides: "the 348-GAS-INVENTORY SCAV-348-01..07 advisory candidate list + the §4 SAFE-WITH-CONDITIONS carve-out + the §5 security floor"
  - phase: 349.1
    provides: "the committed AfKing-in-Game box-redesign (77c3d9ef) — game-resident subscriber state, the per-sub Sub stamp, resolveAfkingBox"
  - phase: 349.2
    provides: "the committed lootbox quest-credit + affiliate regression fix (453f8073) — the CURRENT subject tree for this re-pin"
provides:
  - "350-RE-PIN-AND-CONFIRM.md — SCAV-348-01..07 re-pinned on the live 453f8073 tree with status verdicts + GAS-01/02 confirm-structural evidence"
  - "350-TST06-MEASUREMENT-SPEC.md — the 351 TST-06 per-buy + per-open marginal-gas measurement spec under the 16.7M ceiling"
  - "the GAS-01/GAS-02 confirmed-structural finding (no apply work at 350; measured at 351)"
  - "the recorded post-349.2 re-pin discrepancy (stamp anchors drifted; affiliate/quest restored as BURNIE-only — neither flips a GAS verdict)"
affects: [350-02-gas-skeptic, 350-03-outcome-branch, 351-tst, 352-terminal]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Re-pin-against-live-committed-tree: every advisory anchor re-grepped against the current tree (post-349.2 453f8073), not copied from research; drift recorded explicitly (T-350-01, no silent override)"
    - "Confirm-and-measure (not apply): structural gas wins delivered by the architecture relocation are CONFIRMED present + handed a 351 measurement spec, not re-implemented"

key-files:
  created:
    - ".planning/phases/350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam/350-RE-PIN-AND-CONFIRM.md"
    - ".planning/phases/350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam/350-TST06-MEASUREMENT-SPEC.md"
  modified: []

key-decisions:
  - "Re-pinned against the CURRENT committed tree (post-349.2 453f8073), not the plan's stale 77c3d9ef — STATE.md requires the post-349.2 surface; the divergence is recorded, not silently overridden (T-350-01)"
  - "GAS-01 + GAS-02 are confirmed-structural (already delivered by the 349/349.1 relocation) — NO apply work at 350; the empirical measurement is 351 TST-06"
  - "SCAV-348-03 (GAS-03, the claimablePool same-slot flush) is the SOLE residual candidate, named STILL-APPLICABLE and carried to plan 350-02 for adjudication (not adjudicated here)"
  - "The 349.2-restored quest/affiliate on the lootbox STAGE are BURNIE flip-credit only (no ETH/pool write; :710 claimablePool debit byte-unchanged) → they do NOT flip the GAS-01/02/03 verdicts"

patterns-established:
  - "Re-pin discrepancy disclosure: when the plan's anchor commit drifts from the live committed tree, record every drifted file:line + every newly-on-path symbol explicitly in the deliverable, with a verdict-impact note"

requirements-completed: [GAS-01, GAS-02]

# Metrics
duration: ~7min
completed: 2026-05-31
---

# Phase 350 Plan 01: Re-Pin + Confirm-Structural + TST-06 Spec Summary

**Re-pinned SCAV-348-01..07 against the live post-349.2 `453f8073` tree (recording the stamp-anchor drift + the BURNIE-only quest/affiliate restore), documented GAS-01 (box-ledger → one warm Sub-stamp) and GAS-02 (cross-contract staticcall → in-context SLOAD) as confirmed-structural, and authored the 351 TST-06 per-buy + per-open marginal-gas measurement spec — zero contract edits.**

## Performance

- **Duration:** ~7 min
- **Started:** 2026-05-31T10:35Z (approx, plan load)
- **Completed:** 2026-05-31T15:42Z (UTC commit window 10:40–10:42 local)
- **Tasks:** 2
- **Files modified:** 2 created (0 contract files)

## Accomplishments
- **Re-pin table (Task 1):** all seven SCAV-348-01..07 candidates grounded on the CURRENT committed tree (`453f8073`), each with a live `file:line` anchor and a status verdict from {ALREADY-DELIVERED-STRUCTURAL, DISSOLVED, STILL-APPLICABLE}. SCAV-01/02/04/05/06/07 = delivered/dissolved; SCAV-348-03 (GAS-03) = the sole residual candidate, carried to 350-02.
- **GAS-01 confirm-structural:** the afking lootbox-mode buy writes ONE warm Sub slot (`GameAfkingModule.sol:793 scorePlus1`, `:794 amount`, `:840 lastAutoBoughtDay`) and NO cold box-ledger — `enqueueBoxForAutoOpen`/`lootboxEth[`/`lootboxPurchasePacked[`/`boxPlayers.push` grep-ABSENT on the afking path (they survive only on the human MintModule/Whale/Lootbox path).
- **GAS-02 confirm-structural:** the hot path reads `afkingFunding`/`claimableWinnings` via in-context SLOAD (`:463/:464/:662/:709`) with NO STATICCALL to a different address; `afkingFundingOf`/`afkingSnapshot` survive only as Game view-helpers for the external `DegenerusVault.sol:518` consumer (NOT removal targets).
- **TST-06 measurement spec (Task 2):** names the per-buy marginal (instrument `processSubscriberStage:539` via a new-day `advanceGame` STAGE) + the per-open marginal (instrument `_openAfkingBox:888`→`resolveAfkingBox:877`), the v54 cold-ledger + human `openLootBox` oracles, the v46 CR-01 loop-N-divide MARGINAL rule, the GAS-02 no-STATICCALL trace assertion, the conditional GAS-03 oracle (Outcome-B only), and the 16.7M ceiling with `SUB_STAGE_BATCH=50`.

## Task Commits

Each task was committed atomically:

1. **Task 1: Re-pin SCAV-348-01..07 + confirm GAS-01/02 structural-present** - `6d52c043` (docs)
2. **Task 2: Author the 351 TST-06 marginal-gas measurement spec** - `45507ac8` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) — see final commit.

## Files Created/Modified
- `.planning/phases/350-.../350-RE-PIN-AND-CONFIRM.md` - the re-pin table (SCAV-348-01..07 → live `453f8073` anchors + status) + GAS-01/02 confirm-structural evidence + the recorded post-349.2 discrepancy
- `.planning/phases/350-.../350-TST06-MEASUREMENT-SPEC.md` - the 351 TST-06 per-buy + per-open marginal-gas spec under the 16.7M ceiling

## Decisions Made
- **Subject tree = post-349.2 `453f8073`, not the plan's `77c3d9ef`.** The plan + 350-RESEARCH anchor against 349.1 (`77c3d9ef`), but 349.2 (`453f8073`) landed after and mutated `GameAfkingModule.sol` (+104/−29). STATE.md explicitly requires 350 to re-confirm "GAS-01 net of the restored side-effects on the post-349.2 surface", so the live committed tree is the correct subject. Recorded the divergence explicitly (T-350-01 mitigation — no silent override).
- **GAS-01/GAS-02 = confirmed-structural, no apply work.** They materialized the moment subscriber state went game-resident at 349/349.1; 350 confirms + measures (351), does not re-implement. Both REQUIREMENTS (GAS-01, GAS-02) are satisfied by the confirm.
- **SCAV-348-03 (GAS-03) carried to 350-02.** Named STILL-APPLICABLE here; APPROVE/REJECT deferred to the `/gas-skeptic` gate (plan 350-02). The 350-RESEARCH direction is NEGATIVE/marginal (warm SSTORE ~100 gas × (N−1) on the only batchable shared slot, `claimablePool:710`).

## Deviations from Plan

None - plan executed exactly as written. (The two markdown deliverables were authored per the Task 1/Task 2 actions; both automated verifications and all acceptance criteria passed; no contract files touched.)

## Issues Encountered
- **Plan/research anchor commit (`77c3d9ef`) drifted from the live committed tree (`453f8073`).** This is the planned re-pin work surfacing a tracked discrepancy (exactly what the re-pin task exists to catch), not a problem requiring an auto-fix. Resolved by re-grepping every anchor against the live tree and recording the drift in §0 of `350-RE-PIN-AND-CONFIRM.md`: stamp anchors `:747/:748/:756 → :793/:794/:840`; view-helpers `:1590/:2656 → :1579/:2645`; the funding anchors (`:464/:662/:709/:710`) held. Key load-bearing finding: 349.2 RESTORED `quests.handlePurchase`/`recordMintQuestStreak`/`affiliate.payAffiliate`/`creditFlip` onto the lootbox STAGE branch — making the research's "affiliate/quest NOT on the hot path" claim PARTIALLY STALE for the lootbox branch — but these are ALL BURNIE flip-credit (no ETH/pool write; the `:710` `claimablePool` debit is byte-unchanged), so they do NOT flip the GAS-01/02/03 verdicts. Documented in §0 + §B.3.
- **`.planning/` is gitignored.** New planning files require `git add -f` (tracked planning files like STATE.md/ROADMAP.md are unaffected). Used `-f` for both new docs — consistent with prior GSD plan commits (e.g., the `349.2-01-SUMMARY.md` add).

## User Setup Required
None - no external service configuration required. (Read-only analysis + documentation; no contract edits, no test run, no package install.)

## Next Phase Readiness
- **Plan 350-02 (`/gas-skeptic` validation gate)** is ready: the re-pin doc hands it the live anchors + the carried §4 carve-out + the GAS-03 candidate (`claimablePool:710`) with the NEGATIVE/marginal research direction. SCAV-348-03 awaits adjudication there.
- **Plan 350-03 branches on the 350-02 verdict:** Outcome A (expected — record NEGATIVE/all-confirmed, no diff) or Outcome B (contingency — the penny-exact `claimablePool` flush diff, held at the contract-commit boundary `autonomous: false`).
- **Phase 351 (TST)** is ready: `350-TST06-MEASUREMENT-SPEC.md` names the exact instrumentation sites, txs, marginal units, oracles, and the 16.7M ceiling for TST-06. (351 also owns the stale AfKing.sol-import / `_afkingEpoch` / ABI test-red sweep — TST-05 — EXPECTED now, NOT a 350 blocker.)
- **No blockers.** `git diff --name-only -- contracts/` is EMPTY — the read-only confirm success criterion holds.

## Self-Check: PASSED
- FOUND: `.planning/phases/350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam/350-RE-PIN-AND-CONFIRM.md`
- FOUND: `.planning/phases/350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam/350-TST06-MEASUREMENT-SPEC.md`
- FOUND commit: `6d52c043` (Task 1)
- FOUND commit: `45507ac8` (Task 2)
- CONFIRMED: `git diff --name-only -- contracts/` EMPTY (read-only)

---
*Phase: 350-gas-behavior-identical-no-cost-wins-box-ledger-warm-sub-stam*
*Completed: 2026-05-31*
