---
phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc
plan: 03
subsystem: audit
tags: [rebal, jack, bps-sum, final-day-deletion, grep-attestation, edit-order, design-lock, spec, batch-01]

# Dependency graph
requires:
  - phase: 339-CONTEXT (discuss-phase)
    provides: D-11 (REBAL complete pool-BPS set sums to 10000), D-12 (JACK clean-orphan + preserved plumbing), D-13 (grep-attest every anchor vs 812abeee + producer-before-consumer edit-order)
  - phase: 339-01 (prior plan, this wave)
    provides: D-13 anchor correction — sole traitBurnTicket writer = DegenerusGameMintModule.sol:603-643; cited :2701/:2730/:2813/:654 are READ-side (carried forward into the grep table + edit-order map)
provides:
  - 339-REBAL-JACK-ATTESTATION.md — the REBAL BPS-sum invariant (complete set incl CREATOR_BPS=2000 :291 sums to 10000 before+after, net-zero, supply unchanged) + the JACK final-day deletion side-effects attestation (cleanly orphaned targets + preserved isFinalDay plumbing) (SC4, BATCH-01)
  - 339-GREP-ATTESTATION-EDIT-ORDER.md — the empty-diff shortcut + a 22-anchor per-anchor table vs 812abeee with drift corrections + the 4-step producer-before-consumer edit-order map binding for BATCH-02 at Phase 340 (SC5, BATCH-01, D-13)
affects: [340-IMPL, 341-TST, 342-TERMINAL, v52-consolidated-audit]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Complete-set BPS-sum enumeration (locate the missing constant in source, prove sum=10000 before AND after, never hand-wave 'by construction')"
    - "Clean-orphan deletion attestation (grep the WHOLE file for sole-use/sole-emit inside the deleted branch) + preserved-plumbing attestation"
    - "Empty-diff shortcut + per-anchor line-by-line grep table with read-vs-write + REF-vs-MOD classification"
    - "Producer-before-consumer edit-order map for a single batched diff (no intermediate broken state)"

key-files:
  created:
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-REBAL-JACK-ATTESTATION.md
    - .planning/phases/339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc/339-GREP-ATTESTATION-EDIT-ORDER.md
  modified: []

key-decisions:
  - "REBAL BPS-sum HOLDS (D-11): the COMPLETE pool-BPS set is { CREATOR 2000 (:291), WHALE 1000 (:294), AFFILIATE 3500 (:295), LOOTBOX 2000 (:296), REWARD 500 (:297), PRESALE_BOX 1000 (:298) } = 10000 before; the missing 2000 the plan flagged is CREATOR_BPS=2000 at :291 (the :294-298 block alone sums to only 8000). Post-REBAL { ...AFFILIATE 3000, REWARD 1000... } = 10000; net-zero (+500/-500); only :295/:297 change"
  - "REBAL supply UNCHANGED (D-11): grounded in the :354-359 (INITIAL_SUPPLY * X_POOL_BPS)/BPS_DENOM derivations + the :360-372 mint; Pool.Reward 50B->100B (x2); affiliate ~14% haircut (350B->300B); INITIAL_SUPPLY (:285) + BPS_DENOM (:288) untouched"
  - "JACK deletion CLEANLY ORPHANED (D-12): FINAL_DAY_DGNRS_BPS sole use :1343 + JackpotDgnrsWin sole emit :1350, both inside the deleted :1339-1352 branch (whole-file grep confirms no other use/emit)"
  - "JACK plumbing PRESERVED (D-12): the lvl+1 ticket-index gate :617 + the six caller sites :1085/:1095/:1135/:1161/:1190/:1312 are UNTOUCHED; the whale-pass-on-final-day branch (:1335-1338) survives; only the Pool.Reward draw is removed"
  - "Empty-diff shortcut (D-13): git diff 812abeee HEAD -- contracts/ is EMPTY (only v51 doc commits since 812abeee) -> grep HEAD == grep 812abeee; still shown line-by-line per the no-by-construction rule"
  - "Producer-before-consumer edit-order (D-13): Step1 producers (storage+module+ContractAddresses) -> Step2 consumer (DegenerusGame.claimBingo entrypoint+interface) -> Step3 REBAL -> Step4 JACK; binding for BATCH-02 at Phase 340"

patterns-established:
  - "Locate-the-missing-constant: when a cited BPS subset doesn't sum to the denominator, find the remaining constant(s) in source and include them — never accept a partial set"
  - "Function-name + line-region drift recorded as informational (not contract drift) when the diff vs baseline is empty — clarify plan-text vs source so no by-construction citation ships uncorrected"

requirements-completed: [BATCH-01]

# Metrics
duration: ~22min
completed: 2026-05-28
---

# Phase 339 Plan 03: REBAL+JACK Attestation + Grep-Attestation/Edit-Order Map Summary

**Discharged the SPEC's two satellite verification charges and the call-graph close-out: PROVED (not assumed) the REBAL pool-BPS set sums to exactly 10000 before and after the net-zero swap — locating the plan-flagged missing 2000 as CREATOR_BPS=2000 at StakedDegenerusStonk.sol:291 — with total sDGNRS supply unchanged (Pool.Reward 50B→100B); attested the JACK final-day Pool.Reward deletion is cleanly orphaned (sole-use/sole-emit inside the deleted :1339-1352 branch) with the rest of the isFinalDay plumbing preserved; and grep-attested all 22 milestone anchors vs 812abeee with drift corrections plus the 4-step producer-before-consumer edit-order map binding for BATCH-02 at Phase 340.**

## Performance

- **Duration:** ~22 min
- **Started:** 2026-05-28 (Phase 339 Plan 03 execution start)
- **Completed:** 2026-05-28
- **Tasks:** 2 completed
- **Files created:** 2 (both attestation docs); 0 contract/test files touched

## Accomplishments

- **339-REBAL-JACK-ATTESTATION.md** (SC4 / BATCH-01). PART 1 (REBAL, D-11): enumerated the COMPLETE pool-BPS set and proved it sums to exactly 10000 — the five constants in the `:294-298` block sum to only 8000, and the missing 2000 was LOCATED in source as `CREATOR_BPS = 2000` at `StakedDegenerusStonk.sol:291` (confirmed via a whole-file `grep "_BPS\|BPS_DENOM\|INITIAL_SUPPLY"` that the set is complete and CREATOR_BPS is the only non-`:294-298` member). Showed both the before set (sum 10000) and the after set (`AFFILIATE 3500→3000` :295 / `REWARD 500→1000` :297 → sum 10000), stated the swap is net-zero (+500/−500), and grounded the supply-unchanged claim in the `:354-359` `(INITIAL_SUPPLY * X_POOL_BPS)/BPS_DENOM` derivations + the `:360-372` mint (Pool.Reward 50B→100B ×2; affiliate ~14% haircut 350B→300B; only :295/:297 change, no other pool/constant perturbed). PART 2 (JACK, D-12): attested the deletion targets are cleanly orphaned — `FINAL_DAY_DGNRS_BPS` sole use `:1343` and `JackpotDgnrsWin` sole emit `:1350`, both inside the deleted `:1339-1352` branch (whole-file grep confirms no other use/emit) — and the preserved plumbing (the `:617` lvl+1 ticket-index gate + the six caller sites `:1085/:1095/:1135/:1161/:1190/:1312`, plus the whale-pass-on-final-day branch :1335-1338) is UNTOUCHED, so no non-Pool.Reward final-day behavior breaks.
- **339-GREP-ATTESTATION-EDIT-ORDER.md** (SC5 / BATCH-01 / D-13). PART 1: stated AND verified the empty-diff shortcut (`git diff --stat 812abeee HEAD -- contracts/` EMPTY; only v51 doc commits since `812abeee`; HEAD `d022cc9e`), then per the cross-cutting "no by-construction claim survives un-checked" rule showed all 22 milestone anchors line-by-line in a per-anchor table (Anchor | Cited content | Confirmed at HEAD≡812abeee? | Kind {MOD/NEW/REF/READ/WRITER} | Drift correction). Recorded the drift corrections: CREATOR_BPS-at-:291 completeness, the read-side reclassification of `:2701/:2730/:2813` + `JackpotModule:654` (sole writer = `MintModule:603-643`, D-13/339-01), the `_handleSoloBucketWinner`-not-`_paySoloBucket` function name, and the reference-pattern line shifts (Degenerette transferFromPool call :1154-1155 + guard :1148; creditFlip :1322; derivations :354-359) — noting which are modification targets (REBAL :295/:297, JACK :112/:191/:1339-1352/:1350) vs reference patterns. PART 2: the producer-before-consumer 4-step edit-order map (Step 1 producers: 3 storage mappings + new `DegenerusGameBingoModule.sol` + `GAME_BINGO_MODULE` in `ContractAddresses.sol`; Step 2 consumer: `DegenerusGame.claimBingo` delegatecall entrypoint + interface signature; Step 3 isolated REBAL; Step 4 isolated JACK), with the rationale for why the order yields no intermediate broken state, named the binding edit-order for BATCH-02 at Phase 340.

## Task Commits

Each task was committed atomically:

1. **Task 1: REBAL BPS-sum invariant + JACK final-day deletion side-effects (SC4, D-11/D-12)** — `5760e4bc` (docs)
2. **Task 2: grep-attest every cited file:line vs 812abeee + producer-before-consumer edit-order map (SC5, D-13)** — `c6264d3d` (docs)

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately as the final docs commit.

## Files Created/Modified

- `.planning/phases/339-.../339-REBAL-JACK-ATTESTATION.md` — REBAL BPS-sum invariant (10000 before+after, net-zero, supply unchanged) + JACK clean-orphan + preserved-plumbing attestation (SC4 / BATCH-01).
- `.planning/phases/339-.../339-GREP-ATTESTATION-EDIT-ORDER.md` — empty-diff shortcut + 22-anchor per-anchor table vs 812abeee with drift corrections + 4-step producer-before-consumer edit-order map (SC5 / BATCH-01 / D-13).

No `contracts/*.sol` or `test/` files touched (paper-only SPEC plan). `git diff 812abeee HEAD -- contracts/` is EMPTY; `git diff --name-only -- contracts/ test/` is empty.

## Decisions Made

- Every cited `file:line` was read from source at HEAD (≡ `812abeee` for `contracts/`) before attesting — not transcribed from the plan/CONTEXT text. The REBAL constants (`:291/:294-298`), the derivations (`:354-359`), `poolBalance`/`transferFromPool` (`:464/:485`), the JACK targets (`:112/:191/:1339-1352/:1350`), the preserved plumbing (`:617` + the six callers), the Storage/TraitUtils/DegenerusGame/Degenerette/MintModule anchors, and the `ContractAddresses` module block (`:13-31`) were all confirmed live.
- Honored the 339-01 D-13 anchor correction throughout: the grep table classifies `DegenerusGame.sol:2701/2730/2813` + `JackpotModule:654` as READ-side and names `MintModule:603-643` as the sole writer; the edit-order map's producer is MintModule's writer + the new storage, and the consumer is the new claimBingo read path.
- The two satellite REQs REBAL-01 and JACK-01/02 are the IMPL-340 modification targets; this plan VERIFIES their soundness at SPEC (per the verification charge) but does not flip them complete — they land at IMPL 340. Only BATCH-01 (this SPEC's deliverable requirement) is the requirement this plan owns/completes.
- Per `.gitignore:22` (`.planning/` is directory-ignored), both docs were committed via `git add -f`, consistent with the established 339-01/339-02 convention.

## Deviations from Plan

None — plan executed exactly as written. All anchors verified live; the only adjustments were recording (not introducing) anchor/text drift as informational drift corrections per the plan's own instruction (Task 2 action explicitly directs recording drift between the plan-doc-cited line and the actual confirmed line):

- The plan/CONTEXT name the JACK deletion's containing function `_paySoloBucket`; source has `_handleSoloBucketWinner` (`:1305`). Recorded as a function-name drift; the branch/constant/event/gate/caller lines are all confirmed at the cited line numbers.
- The REBAL derivations are at `:354-359` (CREATOR on :354), not the plan/CONTEXT `:355-359`. Recorded as a region drift.
- The Degenerette `transferFromPool` ref is precisely `:1154-1155` (guard `:1148`), and the MintModule `creditFlip` ref is `:1322` (CONTEXT cited `:1319`). Recorded as reference-pattern line shifts (not modification targets).

None of these is a contract drift between `812abeee` and HEAD (that diff is empty); all are plan-text-vs-source clarifications captured so no "by construction" citation ships uncorrected into IMPL 340.

**Total deviations:** 0 (drift recorded as instructed, not a corrective deviation)
**Impact on plan:** None. Paper-only, zero contract edits, all locked decisions (D-11/D-12/D-13) honored; the 339-01 D-13 read-vs-write correction carried into the grep table + edit-order map per the cross-plan note.

## Issues Encountered

None.

## Known Stubs

None. No placeholder / TODO / FIXME patterns in either doc. Both are settled, source-attested verification documents.

## Threat Flags

None. This plan introduces no new security-relevant surface — it records verification attestations over the existing v51 design surface already enumerated in the plan's `<threat_model>`. T-339-06 (REBAL pool-BPS tampering) is MITIGATED by the complete-set sum=10000 enumeration grounded in the :354-359 derivations; T-339-07 (JACK dangling references) is MITIGATED by the whole-file sole-use/sole-emit orphan-check + the preserved-plumbing attestation; T-339-08 (un-attested anchors / drift) is MITIGATED by the 22-anchor grep table vs 812abeee + the recorded drift corrections; T-339-SC (package installs) is moot — paper-only Markdown authoring, no installs.

## User Setup Required

None — no external service configuration required.

## Next Phase Readiness

- **For IMPL 340 (REBAL-01 / JACK-01/02 / BATCH-02 + the BINGO portion):** the two attestation docs are the binding verification floor for the satellite items. IMPL must (a) change ONLY `:295` (3500→3000) and `:297` (500→1000) for REBAL — touching no other pool constant, `INITIAL_SUPPLY`, or `BPS_DENOM` — keeping the BPS-sum at 10000; (b) delete the JACK `:1339-1352` branch + `:191` constant + `:112` event in full, leaving the lvl+1 gate `:617`, the six isFinalDay callers, and the whale-pass-on-final-day branch UNTOUCHED; (c) author the single batched diff in the 4-step producer-before-consumer order (storage + module + ContractAddresses → entrypoint + interface → REBAL → JACK) so no intermediate compile state has a dangling reference; (d) treat `MintModule:603-643` as the authoritative `traitBurnTicket` writer and `claimBingo` as a strict read-only consumer.
- **For the v52 consolidated audit:** the REBAL Pool.Reward doubling, the JACK final-day deletion side-effects, and the freeze/soundness/tier-precedence proofs from 339-01/02 are the v51 surface enumerated for the deferred v52 charge.
- No blockers.

## Self-Check: PASSED

- FOUND: 339-REBAL-JACK-ATTESTATION.md
- FOUND: 339-GREP-ATTESTATION-EDIT-ORDER.md
- FOUND: 339-03-SUMMARY.md
- FOUND commit: `5760e4bc` (Task 1)
- FOUND commit: `c6264d3d` (Task 2)
- Task 1 automated verify: PASS · Task 2 automated verify: PASS
- Contract guard: `git diff 812abeee HEAD -- contracts/` EMPTY (zero contract edits); `git diff --name-only -- contracts/ test/` empty

---
*Phase: 339-spec-design-lock-rng-freeze-safety-proof-tier-precedence-loc*
*Completed: 2026-05-28*
