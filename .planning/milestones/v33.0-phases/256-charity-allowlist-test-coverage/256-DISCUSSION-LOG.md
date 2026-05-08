# Phase 256: Charity Allowlist Test Coverage — Discussion Log

**Date:** 2026-05-06
**Phase:** 256-charity-allowlist-test-coverage
**Mode:** discuss (default)

This file is for human reference only (audits, retrospectives) and is NOT consumed by downstream agents (researcher, planner, executor).

---

## Q1 — File Layout

**Header:** File layout
**Question:** Where should the new v33.0 charity governance tests live, and what happens to the existing `test/unit/DegenerusCharity.test.js` file?

**Options presented:**
1. New `test/governance/CharityAllowlist.test.js` + prune existing — Strip the 3 stale `Governance--*` describes from the existing file; keep token / soulbound / burn / burnAtGameOver / receive / Edge Cases. Matches ROADMAP wording.
2. Rewrite `test/unit/DegenerusCharity.test.js` in place — Single file, no new directory.
3. Split: `test/governance/` for governance, `test/unit/` keeps token+burn — Cleanest separation, two files.

**User selected:** Option 1 — New `test/governance/CharityAllowlist.test.js` + prune existing.

**Rationale captured:** Matches ROADMAP wording "A new Hardhat test surface under `test/governance/` (or similar)"; clean concern-separation; existing 992-line file becomes more focused (token / soulbound / burn / receive / edge cases).

**Decision ID:** D-256-LAYOUT-01

---

## Q2 — Conservation Test Driver (TST-05)

**Header:** Conservation
**Question:** How should TST-05 conservation tests drive the level transition (so we can assert 2% GNRUS distribution + sDGNRS/DGNRS/BURNIE supply unchanged + soulbound intact)?

**Options presented:**
1. Impersonate game and call `pickCharity` directly — Fast, doesn't exercise the real wire.
2. Drive a real game level-advance (full integration) — Slow, exercises the `IGNRUSResolve.pickCharity` wire from `DegenerusGameAdvanceModule:1634`.
3. Both — Unit conservation via impersonation + ONE smoke via real game flow.

**User selected:** Option 2 — Drive a real game level-advance (full integration).

**Rationale captured:** Phase 257 AUDIT-03 conservation re-proof grep-cites integration-side coverage as evidence. Impersonate-and-call would bypass the `IGNRUSResolve` wire — only the integration-driven path proves the wire is alive at HEAD.

**Decision ID:** D-256-CONSERVATION-01

---

## Q3 — Post-Gameover Inertness (TST-06)

**Header:** Post-gameover
**Question:** TST-06 post-gameover inertness — current contract has NO `finalized` guard on `setCharity`/`vote`/`pickCharity`. What behavior should we test (and is a contract amendment needed)?

**Options presented:**
1. Test current behavior (inert by absence) — no contract change.
2. Request Phase 254/255 amendment — add `finalized` guards.
3. Test current behavior + flag as Phase 257 finding candidate.

**User answered (freeform):** "post gameover this will never run again so it doesnt really matter"

**Interpretation:** No contract amendment. Behavior is functionally inert because the game-side flow stops calling `charityResolve.pickCharity` after gameover, so `setCharity` / `vote` mutations are meaningless. Locked in via follow-up Q3b.

---

## Q3b — TST-06 Scope (follow-up)

**Header:** TST-06 scope
**Question:** Given "post-gameover never runs again, doesn't really matter" — how minimal should TST-06 be?

**Options presented:**
1. ONE smoke test — GNRUS-side consistency only.
2. ZERO new TST-06 tests — document only in CONTEXT.md.
3. Two smoke tests — burnAtGameOver state + pickCharity-after-burnAtGameOver no-op.

**User selected:** Option 1 — ONE smoke test (GNRUS-side consistency only).

**Rationale captured:** Satisfies REQUIREMENTS TST-06's "verify GNRUS-side consistency" wording with the floor coverage. `setCharity` / `vote` post-gameover are documented as inert-by-absence in CONTEXT.md prose (no test code).

**Decision ID:** D-256-POSTGAMEOVER-01

---

## Q4 — Helpers + Scope (multi-select)

**Header:** Helpers + scope
**Question:** Which test-helper / scope decisions should we lock now?

**Options presented (multi-select):**
1. Factor `test/helpers/charityFixture.js`.
2. Add gas-worst-case derivation note + 1 measurement test.
3. Test active-count accounting drift across both branches.
4. Test edit-queue overwrite semantics explicitly.

**User selected:** Options 1 + 2 (Factor charity-specific helper + Add gas-worst-case derivation).

**NOT selected:** Options 3 + 4 — deferred. Active-count drift goes to Phase 257 AUDIT-02-(f) adversarial sweep. Edit-queue pending-overwrite is implicitly covered by cap-test scenarios; explicit stress test is overspec.

**Decision IDs:** D-256-HELPER-01 (charity fixture), D-256-GAS-01 (gas worst case + measurement).

---

## Q5 — Test Specifics (multi-select)

**Header:** Test specifics
**Question:** Which other coverage specifics should be locked now?

**Options presented (multi-select):**
1. Test contract-recipient ACCEPTED (no revert) — Phase 254 deviation lock.
2. Test cap=21 reverts in BOTH branches separately.
3. Test queued-add-then-cancel via `setCharity(slot, 0)` — non-obvious branch.
4. Concrete tie-break weights — Claude's discretion.

**User selected:** Options 1 + 3 + 4 (Contract-recipient acceptance + Queued-add-then-cancel + Tie-break Claude discretion).

**NOT selected:** Option 2 — cap=21 in BOTH branches separately. Single combined cap test scenario satisfies ROADMAP success criterion 1's "either branch" wording without overspec.

**Decision IDs:**
- D-256-CONTRACT-RECIPIENT-01 (contract-recipient acceptance positive test)
- D-256-CANCEL-QUEUED-01 (queued-add-then-cancel; planner verdicts reachability)
- D-256-TIEBREAK-01 (tie-break weights — Claude's discretion)

---

## Discussion Outcome

**CONTEXT.md sections written:**
- `<domain>` — phase boundary including the 6 TST requirements + Phase 256 boundary state at close.
- `<decisions>` — 12 decision blocks (D-256-LAYOUT-01 through D-256-CONST-CLEANUP-01) plus Claude's Discretion items.
- `<canonical_refs>` — Phase 256 anchors + Phase 254 + 255 predecessors + live `contracts/GNRUS.sol` line refs + existing test surface refs + audit baseline + feedback-memory + cross-phase context.
- `<code_context>` — reusable test assets, established patterns, integration points.
- `<specifics>` — concrete test setup specifics (vote-zero, multi-slot, tie-break, locked-slot, conservation deltas, post-gameover smoke, reason-code constants).
- `<deferred>` — 8 deferred items (active-count drift, fuzz coverage, full gas suite, etc.).

**Out-of-scope items captured in deferred:**
- Active-count accounting drift stress.
- Edit-queue pending-overwrite explicit stress.
- Cap=21 in BOTH branches as separate tests.
- Fuzz / Halmos / Foundry coverage.
- Full gas suite.
- TST-06 contract amendment.
- v32 test artifact archival.
- solidity-coverage tooling.

**Anti-patterns honored:**
- `feedback_no_history_in_comments.md` — pruned describes deleted, not commented.
- `feedback_no_dead_guards.md` — `charityFixture.js` exports only what's consumed.
- `feedback_gas_worst_case.md` — D-256-GAS-01 derives theoretical worst case in PLAN.md FIRST, then ONE measurement test.
- `feedback_no_contract_commits.md` — every `test/` modification requires explicit per-commit user approval; `<canonical_refs>` calls this out.
- `feedback_skip_research_test_phases.md` — Phase 256 is mechanical test-coverage; skip `gsd-research-phase` and plan directly.

**Next step:** `/clear` then `/gsd-plan-phase 256` (or `--skip-research` to plan without research per `feedback_skip_research_test_phases.md`).
