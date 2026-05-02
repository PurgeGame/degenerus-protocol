---
phase: 249-purchaselevel-correctness-proof
plan: 249-01
status: COMPLETE
head: acd88512
closure_signal: PHASE_249_PLV_FINAL_AT_HEAD_acd88512
deliverable: audit/v32-249-PLV.md
deliverable_status: FINAL READ-only
requirements_satisfied: [PLV-01, PLV-02, PLV-03, PLV-04, PLV-05, PLV-06]
---

# Plan 249-01 Summary — purchaseLevel Correctness Proof

## Plan Metadata

- **Phase:** 249 — purchaseLevel Correctness Proof
- **Milestone:** v32.0 Backfill Idempotency + purchaseLevel Underflow Audit
- **Plan ID:** 249-01 (single plan, 4 tasks per D-249-CF-07)
- **Anchor:** HEAD `acd88512` (inherited from Phase 247 / 248)
- **Closure signal:** `PHASE_249_PLV_FINAL_AT_HEAD_acd88512`
- **Deliverable:** `audit/v32-249-PLV.md` FINAL READ-only at HEAD `acd88512`
- **Closed:** 2026-05-01

## Atomic Commits

Each task landed its own atomic commit per D-247-14 carry-forward:

| Task | Commit SHA | Subject |
|------|------------|---------|
| Task 1 | `920a2368` | audit(249-01): Task 1 — PLV-01 + PLV-02 enumeration at HEAD acd88512 |
| Task 2 | `3ed9a77a` | audit(249-01): Task 2 — PLV-03 ternary unreachable proof + PLV-04 arithmetic flat table |
| Task 3 | `6fa97fd5` | audit(249-01): Task 3 — PLV-05 testnet walk + PLV-06 daily-jackpot no-strand + Phase 252 hand-off |
| Task 4 | (this commit — final assembly + READ-only flip + plan-close) | audit(249-01): Task 4 — Final assembly + Phase 251 hand-off + READ-only flip |

## Per-REQ Deliverable Counts

| REQ | Section | Row count | Verdict breakdown | Notes |
|-----|---------|-----------|-------------------|-------|
| PLV-01 | §1 | 41 readsite rows (V01-V30 AdvanceModule + V31-V41 cross-module) | SAFE: 41, EXCEPTION: 0, FINDING_CANDIDATE: 0 | MintModule:923 sibling-ternary row V31 resolved to SAFE via INV-PLV-B-01 + INV-PLV-C-01 composition (jackpot=T requires prior level advance via L1616) |
| PLV-02 | §2 | 24 octant cells (8 octants × 3 level bins) | REACHABLE-SAFE: 9, UNREACHABLE-by-named-invariant: 7, OOS-by-construction: 8 | INV-PLV-A-01 / B-01 / C-01 named-invariant disproofs; the load-bearing O-PLV-TTF/lvl=0 cell carries double cite (L173 turbo guard + L1607-1616 finalizeRngRequest sequence) |
| PLV-03 | §3 | 4-step guard-evaluation walk | n/a — formal proof closure | closes O-PLV-TTF/lvl=0 unreachable cell; load-bearing on L173 third conjunct + L1607-1616 sequence |
| PLV-04 | §4 | 21 arithmetic-site rows (19 sites; V07/V11 split for both-bounds coverage per D-249-09) | SAFE: 21 (the two -1 rows V07-A + V11-A carry SAFE-via-PLV-03) | both -1 sites cross-cite PLV-02 + PLV-03 + PLV-05 per D-249-08 three-link chain |
| PLV-05 | §5 | 8 walk rows (5 pre-fix V01-V05 + 3 post-fix V06-V08) | n/a — symbolic walk | testnet blocks 10759449 + 10761786 cited verbatim per D-249-CF-10 |
| PLV-06 | §6 | 5 branch rows V01-V05 + 1 hand-off row PLV-06-H01 | SAFE: 6 | strand-disproof attestation verified via grep returning only L406 break (after L404); Phase 252 POST31-02 composition target confirmed |

**Total V-rows in deliverable:** 41 (PLV-01) + 24 (PLV-02 octant cells) + 21 (PLV-04) + 8 (PLV-05) + 5 (PLV-06 V-rows) + 1 (PLV-06-H01 hand-off) = 100 rows.
**Deliverable line count:** ≥ 350 lines per must_haves min_lines (verified at plan-close).

## Scope-Guard Deferrals

**Zero scope-guard deferrals.** Every cross-module readsite enumerated in §1.2 (V31-V41) is covered by Phase 247's Consumer Index D-247-I007 per D-249-01 wider scope; no surface surfaced that was NOT already in Phase 247's catalog.

**Three line-number corrections** vs CONTEXT.md / ROADMAP prose are documented inline in the deliverable's header attribution paragraph and in the verified-line-numbers attestation under each section. These are line-number drift between planning-time prose and verified HEAD acd88512, NOT scope-guard deferrals — CONTEXT.md / ROADMAP are NOT re-edited per D-249-CF-08 spirit:

1. Turbo guard third conjunct `!rngLockedFlag` is at AdvanceModule:**173** (CONTEXT.md prose at L167 cites the IF block opener; the load-bearing conjunct is the third on L173).
2. Secondary panic site `levelPrizePool[purchaseLevel - 1]` is at AdvanceModule:**752** (ROADMAP success criterion 4 cites L748; verified line is L752).
3. L752 enclosing function is `_consolidatePoolsAndRewardJackpots` (L732-918), NOT `_distributeYieldSurplus` (L707-717, which is just a delegatecall wrapper). CONTEXT.md frontmatter `canonical_line_ranges` `distributeYieldSurplus_purchaseLevel_param: 734` reference is corrected: L734 is the `purchaseLevel` parameter of `_consolidatePoolsAndRewardJackpots`, not `_distributeYieldSurplus`.

Plus one runtime-writer correction: the sole runtime writer of `level` storage variable is at AdvanceModule:**1616** `level = lvl;` (CONTEXT.md prose cited L1609 — that line at HEAD acd88512 is a comment; the actual write is L1616, gated by `if (isTicketJackpotDay && !isRetry)` at L1612).

## Hand-Off Signals

- **→ Phase 250 (Sibling-Pattern Sweep):** PLV-01 wider scope V31 (MintModule:923 sibling ternary `cachedJpFlag ? cachedLevel : cachedLevel + 1`) classified SAFE via INV-PLV-B-01 + INV-PLV-C-01 composition. Phase 250 SIB-01 inherits this verdict as the input target for re-verification with fresh eyes; if Phase 250 finds the reachability composition does NOT hold under fresh adversarial scrutiny, the row promotes to FINDING_CANDIDATE for Phase 253 routing.
- **→ Phase 251 (Reproduction Tests):** Phase 249 deliverable §7.2 emits a 5-sub-block hand-off appendix:
  - 7.2.1 — TST-01 symbolic spec (pre-fix panic 0x11 reproduction at L173-reverted state)
  - 7.2.2 — TST-02 symbolic spec (post-fix pass at HEAD acd88512)
  - 7.2.3 — TST-03 symbolic spec (regression on `LivenessProductivePause.test.js` from 8bdeabc2 + `LivenessMidJackpot.test.js` from ad41973c)
  - 7.2.4 — Suggested test file `test/edge/LastPurchaseDayRace.test.js` (currently untracked at HEAD acd88512 per D-247-02 carry-forward)
  - 7.2.5 — Phase 247 row anchors D-247-C011 + D-247-F010 + D-247-X027..X029 + D-247-I007..I012
- **→ Phase 252 (Post-v31.0 Landed-Commit Sanity):** Phase 249 deliverable §6.3 emits PLV-06-H01 composition hand-off row confirming `8bdeabc2` productive-pause `_livenessTriggered` short-circuit on `lastPurchaseDay || jackpotPhaseFlag` composes non-interfering with daily-jackpot resolution at L370-407. Phase 252 POST31-02 RE_VERIFIES this composition with PLV-06-H01 as the confirmed input target, plus the new turbo guard at L173.
- **→ Phase 253 (Findings Consolidation):** Zero FINDING_CANDIDATE rows surfaced in Phase 249. Phase 253 FIND-01..04 consumes Phase 249 as a clean input (no candidates to route from this phase). If downstream phases (250 SIB / 251 TST / 252 POST31) surface candidates that trace back to Phase 249's surface, those route to Phase 253 directly without re-entering Phase 249.

## Verifier Reproduction

Reproduction recipe at HEAD `acd88512`:

1. `git rev-parse acd88512` → `acd88512c516bef51981d8b6f49de9878aba9159`
2. Read `audit/v32-249-PLV.md` end-to-end; every PLV-NN-VMM row has a verifier-reproducible grep recipe in the Evidence column.
3. Universe-of-readsites grep:
   ```
   git grep -n 'purchaseLevel' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol' 'contracts/storage/*.sol'
   ```
   Expected: 59 hits across 9 files at HEAD acd88512 (38 in AdvanceModule, 15 in cross-module + storage, 6 in interface / NatSpec / comment-only sites).
4. Universe-of-arithmetic grep:
   ```
   git grep -nE 'purchaseLevel\s*[+\-]\s*[0-9]|purchaseLevel\s*%' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol'
   git grep -n 'levelPrizePool\[purchaseLevel' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol'
   ```
5. Sole-writer grep for the 3 named invariants:
   ```
   git grep -nE '\blastPurchaseDay\s*=' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol'
   git grep -nE '\brngLockedFlag\s*=' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol'
   git grep -nE '\bjackpotPhaseFlag\s*=' acd88512 -- 'contracts/*.sol' 'contracts/modules/*.sol'
   git grep -nE '\blevel\s*=|\blevel\s*\+=|\blevel\+\+|\+\+level' acd88512 -- 'contracts/storage/*.sol' 'contracts/modules/*.sol' 'contracts/*.sol'
   ```
   Expected writers (verified at HEAD acd88512):
   - lastPurchaseDay T-writers: AdvanceModule:178 (turbo block, L173-guarded), AdvanceModule:399 (daily-jackpot region); F-writer: AdvanceModule:444
   - rngLockedFlag T-writer: AdvanceModule:1607 (`_finalizeRngRequest`); F-writers: AdvanceModule:1663 (admin) + AdvanceModule:1704 (`_unlockRng`)
   - jackpotPhaseFlag T-writer: AdvanceModule:442 (sole T-writer); F-writer: AdvanceModule:335
   - level writers: DegenerusGameStorage:250 (init `= 0`) + AdvanceModule:1616 (runtime `= lvl`, gated by L1612)

## Closure Attestation

Closure signal `PHASE_249_PLV_FINAL_AT_HEAD_acd88512` emitted in:
- `audit/v32-249-PLV.md` frontmatter `closure_signal:` field
- `audit/v32-249-PLV.md` Section 7 trailing line
- `.planning/phases/249-purchaselevel-correctness-proof/249-01-SUMMARY.md` frontmatter `closure_signal:` field (this file)

Pure-proof phase boundary held: 4 atomic commits all touch ONLY `audit/v32-249-PLV.md` (Tasks 1-4) + `.planning/phases/249-purchaselevel-correctness-proof/249-01-SUMMARY.md` (Task 4 only). Zero `contracts/` or `test/` writes throughout the plan per D-249-CF-04 / D-249-CF-05.
