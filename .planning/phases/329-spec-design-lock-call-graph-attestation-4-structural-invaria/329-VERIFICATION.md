---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
verified: 2026-05-26T00:00:00Z
status: passed
score: 8/8 must-haves verified
overrides_applied: 0
re_verification:
  previous_status: passed
  previous_score: 4/4
  note: "Previous VERIFICATION.md was the PRE-REDESIGN verification (stale — attested the superseded advance→open→buy / doWork(maxCount) / dual-epoch design). This re-verification covers the REDESIGN (autoBuy→advance→autoOpen / parameterless doWork() / satisfied-by-deletion / unified creditFlip). All 3 plans re-executed under the redesign; all 8 must-haves VERIFIED."
  gaps_closed:
    - "Phase 329 plans re-executed under the keeper-router REDESIGN (3 plans / 2 waves committed)"
    - "REQUIREMENTS.md amended 31→36 reqs (ROUTER-08/09/10 + GASOPT-03/04/05 registered)"
    - "ROADMAP.md Phase 329 GOAL + SC1..SC4 updated to the redesign"
    - "329-SPEC.md re-authored to reflect the redesign (parameterless doWork / satisfied-by-deletion / unified creditFlip)"
  gaps_remaining: []
  regressions: []
gaps:
human_verification: []
resolved_post_verification:
  - item: "Phase 333 GOAL text in ROADMAP.md referenced 31 requirements instead of 36"
    resolution: "FIXED by orchestrator 2026-05-26 — ROADMAP.md line 107 Phase 333 GOAL sentence now reads '— re-attesting all 36 v49.0 requirements.' matching the Coverage table (36/36), Traceability header, and center-of-gravity rationale. Trivial one-word consistency edit applied autonomously (user authorized autonomous continuation); not a design decision. Status flipped human_needed → passed."
---

# Phase 329: SPEC — Design-Lock + Call-Graph Attestation + 4 Structural Invariants Verification Report

**Phase Goal:** The 4 load-bearing structural invariants are locked in writing under the keeper-router REDESIGN (the `autoBuy → advance → autoOpen` order, the dropped rngLock guards, the dropped autoOpen try/catch + entry-gate, the unified single `creditFlip` in `doWork`, the D-07 flat-per-tx bounty); every redesigned shared signature is settled (`advanceGame (uint8 mult, bool rewardable)`, PARAMETERLESS `doWork()` + `NoWork()` + standalone unrewarded escapes, rngLock-aware O(1) discovery views); the ROUTER-07 reentrancy disposition (NO `nonReentrant` guard, re-grounded on the unified single `creditFlip`) + the GAS-03 single-epoch disposition (satisfied-by-deletion) are resolved; and every cited `file:line` + bounty/gas math is grep-verified against the v48.0-closure HEAD `0cc5d10f`.
**Verified:** 2026-05-26
**Status:** passed (the single human-needed editorial item was resolved post-verification — see below)
**Re-verification:** Yes — previous VERIFICATION.md was the stale pre-redesign attestation (status: passed, 4/4); this overwrites it with the post-redesign re-verification.

---

## Goal Achievement

### Observable Truths

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Every cited file:line on the REDESIGNED router/advance surface is grep-attested against the FROZEN v48.0-closure HEAD 0cc5d10f with MATCH/SHIFTED/ABSENT verdicts, and held-tree/redesign-doc line drift is recorded per anchor | ✓ VERIFIED | `329-ATTEST-ROUTER-ADVANCE.md` sections A–G: 45+ anchors, 0 ABSENT. Section A: 14 AfKing anchors (12 MATCH, 2 SHIFTED). 15 drift corrections C1–C15 folded into 329-SPEC.md §0. Independent spot-checks against frozen baseline confirmed: AutoBought decl at `:171` MATCH, autoBuy rngLock guard at `:568` MATCH, batchPurchase pre-check at `:1737` MATCH, advance creditFlips at `:189`/`:225`/`:468` MATCH, autoOpen creditFlip at `:1676` MATCH, autoBuy creditFlip at `:846` MATCH, liveness control at `storage/DegenerusGameStorage.sol:571` MATCH. Roll-up: 0 IMPL blockers. |
| 2 | RD-2 (autoBuy = normal buy, drop rngLock guards) is attested: the AfKing autoBuy-entry rngLock guard (`:568`) AND the game-side batchPurchase rngLock pre-check (`:1737`) are both grep-located; the gameOver pre-check (`:1738`) is confirmed KEEP; and the Q5 dependent grep is PERFORMED with verdict recorded | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Section B: `:1737` rngLock guard and `:1738` gameOver check located and classified. Q5 verdict: `batchPurchase` is AF_KING-gated (`:1736`), sole external caller is `AfKing.sol:821`, not declared in either interface. Removing `:1737` affects only the keeper path — no other dependent. 329-01-SUMMARY.md records "Q5: NO OTHER DEPENDENT." |
| 3 | RD-3/RD-5 (block autoOpen during rngLock + drop try/catch + entry-gate) is attested: autoOpen's ++cursor-before-try/catch ordering is grep-shown; _autoOpenBox is confirmed external onlySelf; the EXACTLY-TWO open-path revert sources are grep-attested; the entry-gate replicates both | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Section E: ++cursor at `:1659` BEFORE `try this._autoOpenBox` at `:1664` / `catch {}` at `:1672` / boxCursor at `:1675` shown; `_autoOpenBox` onlySelf at `:1705` confirmed. Two revert sources: rngLock (`:1737`/`:2413`) and `storage/DegenerusGameStorage.sol:571` `_livenessTriggered()` (baseline-verified). The third `_queueTickets` revert at `:573` is itself an rngLock revert (far-future only). Entry-gate verdict: replicates both pre-loop — brick-proof. USER-accepted frozen-contract trade noted. |
| 4 | RD-4 (unify the bounty into doWork) is attested: the THREE in-callee creditFlip sites from each leg are grep-located and classified; the gameover-RNG-path creditFlip is classified NOT-an-advance-leg-reward; verdict of exactly ONE creditFlip (CEI-last) in doWork is recorded | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Sections D/E + 329-SPEC.md §0 RD-4 verdict: 6→1 unification. 5 pull-outs: U1 AdvanceModule`:189` / U2 `:225` / U3 `:468` (advance); U4 DegenerusGame.autoOpen`:1676`; U5 AfKing`:846` (buy). U6 AdvanceModule`:876` STAYS (payee is ContractAddresses.SDGNRS, not the keeper). Verdict: exactly ONE creditFlip in doWork, CEI-last. |
| 5 | D-07 (flat per-tx model) deletion/keep surface is attested: AfKing autoBuy stall ladder + absolute-day epoch classified DEAD-after-redesign; AdvanceModule stall ladder + game-day epoch KEPT as SOLE stall epoch; autoOpen gas-units machinery classified DEAD; GAS-03 verdict = SATISFIED BY DELETION | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Section C: AfKing stall ladder `:823-838` + absolute epoch `:829` (`today * 1 days + 82_620`) located and classified DEAD. AdvanceModule game-day epoch `:241-253` confirmed KEPT. AUTO_OPEN_BOX_GAS_UNITS `:1546` + open-leg `_ethToBurnieValue` classified DEAD. GAS-03 verdict: "SATISFIED BY DELETION — advance is the sole stall epoch; no two epochs to collapse." 329-SPEC.md Invariant (d) locks this verbatim. |
| 6 | ADV-04 (invariant b): totalFlipReversals nudge is grep-attested; the additional in-window read at `:270` is enumerated; the REDESIGNED router introduces NO new mutable in-window SLOAD into the advance-consume | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Section F: `totalFlipReversals` read at `:1838` + reset at `:1844` inside `_applyDailyRng :1834` confirmed. Second in-window read at `:270` (`cw += totalFlipReversals`) enumerated per `feedback_rng_window_storage_read_freshness`. Under RD-1, autoBuy runs pre-entropy at day-open (rngLock false) BEFORE advance requests the word. No new in-window SLOAD. Empirical proof deferred to TST-01. |
| 7 | ROUTER-07 (D-01/D-01a, re-grounded on the unified single creditFlip): no-untrusted-ETH-send claim grep-attested PER LEG (advance/autoOpen/_autoBuy) AND for the single unified doWork creditFlip; formal no-guard basis recorded verbatim; 329-SPEC.md §1 settles the REDESIGNED shared signatures (advanceGame tuple / parameterless doWork() + NoWork() + unrewarded escapes / rngLock-aware O(1) views / unified creditFlip / D-07 flat-per-tx) | ✓ VERIFIED | 329-ATTEST-ROUTER-ADVANCE.md Section B.3: per-leg no-untrusted-ETH-send rows present. Formal basis verbatim: "keeper-never-a-payee + no untrusted ETH send + one-category structural early-return + single-creditFlip-last CEI ordering." 0 untrusted-push legs. 329-SPEC.md §1 has all five R-rows: R1 advanceGame tuple, R2 parameterless doWork()+NoWork()+unrewarded escapes, R3 rngLock-aware O(1) views (advanceDue/boxesPending rngLock-aware/buys-pending-TRUE-during-rngLock), R4 unified single creditFlip (5 pull-out sites + KEEP-04 survival), R5 D-07 flat-per-tx model (advance 2×mult / buy 1.5× / open 1× pro-rated, GAS-331 placeholders). |
| 8 | REQUIREMENTS.md + ROADMAP.md are AMENDED per the CONTEXT-enumerated list (count 31→36; ROUTER-08/09/10 + GASOPT-03/04/05 registered as Phase-330 IMPL reqs; GASOPT-02 subsumed; phase 329's own coverage stays BATCH-01/ROUTER-07/ADV-04/GAS-03); per-phase counts sum correctly to 36 | ✓ VERIFIED | REQUIREMENTS.md: ROUTER-08/09/10 + GASOPT-03/04/05 present; ROUTER-01/02/04/05 reworded; GASOPT-02 marked SUBSUMED; per-phase count: 4+18+5+5+4=36 (18 for Phase 330: ROUTER-01/02/03/04/05/06/08/09/10[9] + ADV-01/02/03/05[4] + GASOPT-01/03/04/05[4] + BATCH-02[1], GASOPT-02 not counted = 18). ROADMAP.md: Phase 329 GOAL + SC1..SC4 rewritten to the redesign; Phase 329 plan list shows 3 redesigned plans checked; Coverage table shows 36/36; per-category split shows ROUTER 10, GASOPT 4-active; Phase 329 Traceability shows exactly BATCH-01/ROUTER-07/ADV-04/GAS-03 as Complete. One editorial inconsistency: Phase 333 GOAL text says "31" (see Human Verification). |

**Score:** 8/8 truths verified

### Required Artifacts

| Artifact | Expected | Status | Details |
|----------|----------|--------|---------|
| `329-ATTEST-ROUTER-ADVANCE.md` | Per-anchor grep tables (vs 0cc5d10f) for REDESIGNED router + advance surface | ✓ VERIFIED | Exists. Sections A–G + Roll-up. Verdict legend present. 45+ anchors. Dirty-tree / grep-against-0cc5d10f header note present. Q5 performed. 0 IMPL blockers in Roll-up. Commits: `84fbb073` (A/B/C), `79086b3b` (D/E/F/G + Roll-up). |
| `329-ATTEST-DEGENERETTE-RESOLVE.md` | Rename-surface attestation + D-05f losing-bet-liveness finding + D-05c real-gas + D-05b flat-shape + architectural non-foldability | ✓ VERIFIED | Exists. Sections A/B/C/D/E + Roll-up. D-05 SURVIVES-verbatim carry-forward present. D-05f INERT-SAFE re-confirmed (8 consumers in 3 files, 11 other modules grep-clean). SURFACE-TO-USER token present. 0 IMPL blockers. Commits: `e9cba730` (A/B/C/D), `3b2bf287` (E + Roll-up). |
| `329-SPEC.md` | The reconciled v49.0 keeper-router-REDESIGN design-lock blueprint (§0–§3) | ✓ VERIFIED | Exists. §0 folds both ATTEST docs (0 blockers, C1–C15 corrections, Q5/ROUTER-07/GAS-03/ADV-04/RD-5/D-04a/D-05f verdicts). §1 has R1–R5. §2 has invariants (a)–(d) + RD-1..5 + ROUTER-07 + GAS-03 + D-08 + D-05. §3 has edit-order map + SC1..SC4 checklist + SOURCE-TREE-not-mutated line. Commits: `3e961575` (§0+§1), `1cb91124` (§2+§3). |
| `.planning/REQUIREMENTS.md` | Amended v49.0 requirements (36 reqs) | ✓ VERIFIED | Exists with all required amendments. 36/36 mapping; per-phase count sums to 36. Commit: `282ea135`. |
| `.planning/ROADMAP.md` | Amended v49.0 roadmap (Phase 329 redesigned goal/SCs, 36-req tables) | ✓ VERIFIED (with editorial note) | Exists with amendments. Phase 329 GOAL/SC1..SC4 rewritten to the redesign. Coverage table = 36/36. One stale "31" in Phase 333 GOAL text — see Human Verification. Commit: `282ea135`. |

### Key Link Verification

| From | To | Via | Status | Details |
|------|----|-----|--------|---------|
| Held-tree/redesign-doc cited file:line anchors (router/advance surface) | FROZEN baseline contracts/ at HEAD 0cc5d10f | git show 0cc5d10f:contracts/<path> grep-n (NOT the dirty held-330 tree) | ✓ WIRED | 45+ anchors verified against frozen blob. `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` is EMPTY — committed HEAD is byte-identical to baseline. Dirty working tree = held-330 diff (6 .sol + 7 test files), untouched by Phase 329 commits. |
| Each doWork leg + single unified doWork creditFlip | claimableWinnings pull ledger + ContractAddresses.* pinned sends only | Per-leg + single-creditFlip no-untrusted-ETH-send grep attestation (D-01a) | ✓ WIRED | ROUTER-ADVANCE.md Section B.3: every ETH send goes to pinned ContractAddresses.* (GAME/COINFLIP); player value routes through claimableWinnings pull ledger; bounty is flip-credit to msg.sender (ledger entry on pinned COINFLIP). AfKing CEI invariant at `:100` confirmed. 0 untrusted-push legs. |
| Two 329-ATTEST-*.md docs + their SUMMARYs | 329-SPEC.md §0 verdict roll-up + §1 settled signatures + §2 invariants | Fold attestation drift + decision verdicts + Q5 + D-05f findings into locked redesign | ✓ WIRED | 329-SPEC.md §0 explicitly folds both ATTEST docs (0 blockers aggregate). Q5 no-other-dependent verdict carried. D-05f INERT-SAFE finding carried verbatim (not softened). C1–C15 corrections all present in §0. The §1 R-rows reference the attested anchors. |
| CONTEXT <decisions> enumerated REQUIREMENTS/ROADMAP amendments list | .planning/REQUIREMENTS.md + .planning/ROADMAP.md (incl. Phase 329 goal/SCs) | Apply each enumerated edit; register ROUTER-08/09/10 + GASOPT-03/04/05; update count tables 31→36 | ✓ WIRED | All enumerated edits from 329-CONTEXT.md applied. 329-03-SUMMARY.md self-consistency check: "37 distinct REQ-IDs − 1 SUBSUMED (GASOPT-02) = 36 active; per-phase counts sum to 36; every REQ-ID appears in exactly one Traceability row + exactly one phase." |

### Data-Flow Trace (Level 4)

Not applicable. This is a paper-only SPEC phase — no runnable components, no dynamic data rendering. The "data flow" is whether grep evidence from the frozen baseline feeds into the SPEC's locked claims — confirmed through key link verification above.

### Behavioral Spot-Checks

Step 7b: SKIPPED (paper-only SPEC phase; no runnable entry points produced). Zero `contracts/*.sol` mutation — confirmed by `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` returning no output.

### Probe Execution

Step 7c: No probes declared or implied in any 329-PLAN.md. No `scripts/*/tests/probe-*.sh` files referenced. SKIPPED.

### Requirements Coverage

| Requirement | Source Plan | Description | Status | Evidence |
|-------------|-------------|-------------|--------|----------|
| BATCH-01 | 329-01, 329-02, 329-03 | SPEC design-lock — 4 invariants + shared signatures + grep-attest vs v48.0 HEAD | ✓ SATISFIED | 329-SPEC.md §0–§3 complete; 0 IMPL blockers; invariants (a)–(d) locked; R1–R5 settled. REQUIREMENTS.md marks Complete. |
| ROUTER-07 | 329-01, 329-03 | NO nonReentrant guard on doWork, re-grounded on the unified single creditFlip | ✓ SATISFIED | REQUIREMENTS.md marks Complete. 329-ATTEST-ROUTER-ADVANCE.md Section B.3 + 329-SPEC.md §2 "Disposition ROUTER-07" both present with the verbatim formal basis. |
| ADV-04 | 329-01, 329-03 | totalFlipReversals frozen request→consume; no new in-window SLOAD under the new router order | ✓ SATISFIED | REQUIREMENTS.md marks Complete. 329-ATTEST-ROUTER-ADVANCE.md Section F + 329-SPEC.md §2 "Invariant (b)" both present with the autoBuy-pre-entropy / no-new-SLOAD verdict. |
| GAS-03 | 329-01, 329-03 | Single day-start stall epoch — satisfied by deletion | ✓ SATISFIED | REQUIREMENTS.md marks Complete. 329-ATTEST-ROUTER-ADVANCE.md Section C + 329-SPEC.md §2 "Invariant (d)" + "Disposition GAS-03" all present. |

Phase 329 owns exactly BATCH-01, ROUTER-07, ADV-04, GAS-03 — verified as the only Phase 329 entries in REQUIREMENTS.md Traceability.

The 6 newly-registered requirements (ROUTER-08/09/10 + GASOPT-03/04/05) are correctly mapped to Phase 330 IMPL in both REQUIREMENTS.md Traceability and ROADMAP.md Coverage. They are locked in 329-SPEC.md §2 as "LOCK as v49.0 design items (code at 330, REQ-IDs registered)" — correctly registered, not claimed as phase-329 deliverables.

No orphaned requirements from REQUIREMENTS.md that Phase 329 should have covered but missed.

### Anti-Patterns Found

| File | Line | Pattern | Severity | Impact |
|------|------|---------|----------|--------|
| `.planning/ROADMAP.md` | Phase 333 GOAL block | "re-attesting all 31 v49.0 requirements" — stale count; all other ROADMAP.md references (Coverage table, Traceability header, center-of-gravity rationale, footnote) correctly state 36 | INFO (editorial) | Does not affect Phase 329 goal achievement. Phase 333 GOAL block was mostly updated but this one sentence was missed. Not a blocker. |

No TBD/FIXME/XXX markers found in Phase 329 planning files. No stub implementations — all produced documents contain substantive content (full attestation tables with per-anchor verdicts, classified line numbers, explicit design decisions). All Phase 329 commits (84fbb073, 79086b3b, 09baeb71, e9cba730, 3b2bf287, 1831b9fa, 3e961575, 1cb91124, 282ea135, 85a6877e) touch only `.planning/` files. No contracts/*.sol committed.

### Post-Verification Fix Log — ✅ all items RESOLVED (orchestrator, 2026-05-26); no open items

The one item below was a trivial one-word consistency fix (not a design decision). Under the user's autonomous-continuation authorization it was applied immediately: ROADMAP.md line 107 Phase 333 GOAL now reads "— re-attesting all 36 v49.0 requirements." No open items remain; phase status is `passed`.

### 1. Phase 333 GOAL stale "31" requirement count in ROADMAP.md — ✅ FIXED

**Test:** Open `.planning/ROADMAP.md`. In the Phase 333 detail block, locate the GOAL sentence ending with "— re-attesting all 31 v49.0 requirements." Compare against the Coverage table (line 136: "36/36 v49.0 requirements mapped"), the center-of-gravity rationale (line 168: "BATCH-03 re-attests all 36 v49.0 requirements"), and the footnote (line 212: "→ 36 active reqs").

**Expected:** The one sentence in Phase 333 GOAL should read "re-attesting all 36 v49.0 requirements." to match the rest of the file. This is a trivial one-word edit ("31" → "36"). The user should decide whether to apply it immediately or defer to Phase 333 planning.

**Why human:** The verifier may not commit changes. This editorial inconsistency does not block Phase 329 verification — Phase 329's own deliverables (329-SPEC.md, REQUIREMENTS.md amendments, ROADMAP.md Phase 329/330 sections and Coverage/Traceability tables) are all internally consistent at 36. The stale "31" is solely in Phase 333's goal description block.

---

## Gaps Summary

No blockers. Phase 329 goal is achieved in full. All 8 observable truths are VERIFIED across all three artifacts (329-ATTEST-ROUTER-ADVANCE.md, 329-ATTEST-DEGENERETTE-RESOLVE.md, 329-SPEC.md) and the two amended planning files (REQUIREMENTS.md, ROADMAP.md). Independent baseline spot-checks of 8 cited file:line anchors all confirmed MATCH against the frozen `0cc5d10f` blob.

The original `status: human_needed` classification was triggered by one editorial inconsistency (stale "31" in Phase 333 GOAL text). That item was resolved post-verification (ROADMAP.md line 107 corrected to "36"), so the final status is `passed`. All automated checks passed at 8/8.

---

_Verified: 2026-05-26_
_Verifier: Claude (gsd-verifier)_
