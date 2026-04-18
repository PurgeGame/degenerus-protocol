# Phase 234: Quests / Boons / Misc Audit - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-04-17
**Phase:** 234-quests-boons-misc-audit
**Mode:** AUTO — no user-facing questions; defaults locked per authoritative scope and v29.0 ROADMAP guidance.
**Areas discussed:** Deliverable shape (1 plan vs 3 plans), fresh-ETH interaction depth for QST-01, companion test-file review scope for QST-01, boonPacked auto-getter known-non-issue handling for QST-02, BurnieCoin isolation vs conservation scope for QST-03, overlap with Phase 232 DCM-01 on commit `3ad0f8d3`.

---

## 1. Deliverable Shape — 1 Plan vs 3 Plans

| Option | Description | Selected |
|--------|-------------|----------|
| A. One consolidated plan `234-01-PLAN.md` with three per-requirement sections (QST-01 / QST-02 / QST-03) — grab-bag pattern | Matches ROADMAP Phase 234 explicit guidance; three requirements are LOW-coupling and individually tractable | ✓ |
| B. Three separate plans `234-01` (QST-01) + `234-02` (QST-02) + `234-03` (QST-03) | Matches Phases 231/232/233 expected 2-3 plan split; more orchestration overhead | |
| C. Two plans — one for QST-01 (quest wei fix, largest surface) + one combined for QST-02 + QST-03 (visibility flip + 1-line BurnieCoin change) | Hybrid | |

**Selected:** A (ROADMAP explicit default for this phase).
**Rationale:** The ROADMAP Phase 234 "Plans" line reads verbatim: "TBD expected 1 plan with per-requirement sections — grab-bag pattern per v29.0 roadmap guidance." Three requirements total; each touches a different subsystem with zero execution-level coupling (a quest wei-credit fix in the mint/quest chain, a mapping visibility flip in storage, one line of BurnieCoin). Splitting into three plans would produce three near-identical scaffolds with three separate front-matter blocks and three separate SUMMARY.md files — orchestration overhead without audit-quality benefit. One plan / three sections keeps all the verdict tables in one reviewer-scrollable file and matches the grab-bag pattern the user validated for low-coupling phases in v28.0.

**Gray area:** If during planning any single section balloons past ~200 lines of table rows (e.g., if QST-01 discovers a deeper fresh-ETH interaction than D-05 anticipates), the plan can be retro-split without re-running discuss. Threshold is informal — reviewer readability is the signal, not line count.

---

## 2. Fresh-ETH Interaction Depth for QST-01

| Option | Description | Selected |
|--------|-------------|----------|
| A. Stay strictly within the delta — audit `ticketFreshEth + lootboxFreshEth` summation in `_purchaseFor` and its single split into (earlybird award / MINT_ETH quest credit) only; do not re-audit the full quest-handler framework | READ-only milestone; `d5284be5` only touches the wei-credit path | ✓ |
| B. Full re-audit of all 8 quest-handler types (`handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`, `handlePurchase`, `awardQuestStreakBonus`) plus streak accounting and level-quest progress | Comprehensive but out of delta scope | |
| C. Medium — audit `handlePurchase` plus its direct intra-contract callers/callees within `DegenerusQuests.sol` | Intermediate | |

**Selected:** A (per `feedback_skip_research_test_phases.md` — skip research for obvious/mechanical phases, stay in delta).
**Rationale:** `d5284be5` touches exactly one quest-handler (`handlePurchase`) and exactly one caller (`_purchaseFor` plus its helper `_callTicketPurchase`). The commitment window is the unit switch (`uint32 * mintPrice → uint256 wei`). Auditing the other 7 quest types is outside the delta — they are unchanged pre-commit and unchanged post-commit. User feedback repeatedly reinforces "stay in the delta" on delta audits. Option C blurs the line without adding coverage the 230 catalog didn't already anchor.

**Gray area:** The audit DOES still need to reason about whether fresh ETH routed to MINT_ETH could also be double-credited to any OTHER companion-quest slot inside `handlePurchase` itself (e.g., whether a single purchase could trigger both MINT_ETH credit and another slot crediting the same wei). That reasoning stays inside `handlePurchase`'s existing slot switch logic — it doesn't require touching the other 7 handlers. Locked narrowly in D-05.

---

## 3. Companion Test-File Review Scope for QST-01

| Option | Description | Selected |
|--------|-------------|----------|
| A. READ-only review of whatever `test/` file is touched by `d5284be5` — confirm alignment with the wei-direct fix; flag any coverage gap as a Phase-236 test-coverage deferral | Matches milestone READ-only rule; ROADMAP SC1 "test file change reviewed" is satisfied by a read | ✓ |
| B. Author new foundry tests specifically for the wei-direct path — patch the test file to cover the removed `uint32 * mintPrice` scaling vs. the new path | VIOLATES milestone READ-only rule | |
| C. Ignore the test file entirely and rely on `forge build` + interface-drift PASS as sufficient coverage signal | Under-satisfies ROADMAP SC1 | |

**Selected:** A.
**Rationale:** The ROADMAP Phase 234 SC1 text says "the companion test-file change reviewed" — the verb is "reviewed", not "extended". Milestone-wide READ-only rule prohibits `test/` writes. A careful read of the companion test file's `d5284be5` slice (does it cover the wei-direct path? does it assert the right units?) satisfies the criterion. If coverage is thin, the plan records a bullet anchor for Phase 236 to surface as a test-coverage gap — it does NOT become a blocking concern for the audit verdict on QST-01. `feedback_no_contract_commits.md` extends by practice to `test/` during an audit milestone.

**Gray area:** If `d5284be5` turns out to have NO test-file change (i.e., the commit is contracts-only), the "companion test-file change reviewed" SC1 clause is vacuously satisfied — the plan will note "no test-file change in d5284be5; SC1 vacuously PASS" and move on. Planner will confirm by running `git show --stat d5284be5 -- test/` as the first step of Section 1.

---

## 4. boonPacked Auto-Getter Known-Non-Issue Handling for QST-02

| Option | Description | Selected |
|--------|-------------|----------|
| A. Document-and-accept the 230-01-SUMMARY item-1 classification — auto-getter not on `IDegenerusGame.sol` is **by design** (UI reads concrete address) and is NOT a drift failure; no finding emitted by Phase 234 | Carries forward Phase 230 decision consistently | ✓ |
| B. Re-open the question — treat interface non-declaration as a drift candidate and emit a Phase-234 finding | Contradicts Phase 230 §3.1 D-10 classification; user feedback discourages reopening settled questions | |
| C. Add a note to `IDegenerusGame.sol` without a finding — propose the interface declaration as a "nice-to-have" | VIOLATES milestone READ-only rule | |

**Selected:** A (per D-08 + 230-01-SUMMARY item 1 + `feedback_wait_for_approval.md` — don't reopen settled design decisions without explicit user direction).
**Rationale:** Phase 230 classified the non-declaration as "interface-completeness gap, NOT drift" in §3.1 D-10. The UI / off-chain consumer contract is: read `DegenerusGame.boonPacked(address)` directly off the concrete deployed address. On-chain consumers that go through `IDegenerusGame` don't need the boon slots. The decision is architecturally coherent. Phase 234 documents the known-non-issue in its SUMMARY (for audit-trail completeness) and moves on. If a future reviewer disagrees, the avenue is a Phase-236 finding, not a Phase-234 re-open.

**Gray area:** If during audit we discover an on-chain consumer (a module, a library, anything inside `contracts/` other than the UI/off-chain surface) that needs to read `boonPacked` through `IDegenerusGame` rather than through the concrete address, THAT would be a legitimate Phase-234 finding candidate (interface-completeness actually blocks something). The plan will include this as a Section-2 attack-vector check: "any in-contract consumer that routes boon reads through `IDegenerusGame`?" Answer expected: no (because the auto-getter was introduced precisely because no on-chain consumer existed), but the check is cheap.

---

## 5. BurnieCoin Isolation vs Conservation Scope for QST-03

| Option | Description | Selected |
|--------|-------------|----------|
| A. Phase 234 QST-03 audits ISOLATION only — diff is CONFINED to decimator-burn-key plumbing, no supply-accounting touchpoint inside the commit; end-to-end supply/mint-burn closure is deferred to Phase 235 CONS-02 | Matches ROADMAP Phase 234 SC3 wording ("isolated cause/effect" + "no supply conservation impact" read as a locality claim) | ✓ |
| B. Full end-to-end BURNIE supply proof inside Phase 234 — absorb CONS-02's BurnieCoin coverage into QST-03 | Duplicates Phase 235 scope; violates Phase 230 consumer-index boundary for CONS-02 | |
| C. Phase 234 QST-03 skipped entirely and the BurnieCoin slice folded into Phase 232 DCM-01 | Contradicts ROADMAP's explicit QST-03 scope; also leaves Phase 234 with only 2 requirements instead of 3 | |

**Selected:** A.
**Rationale:** The ROADMAP SC3 text is "The `BurnieCoin.sol` change is audited for isolated cause/effect — the change is confined to decimator-burn-key plumbing with no supply-conservation impact." That sentence is a locality/isolation claim, not a conservation proof. Phase 235 CONS-02 explicitly owns "BURNIE conservation is verified across the `BurnieCoin.sol` change and the quest changes — no new mint site bypasses `mintForGame`, and mint/burn accounting closes end-to-end" (ROADMAP Phase 235 SC2). Two phases, two aspects; Phase 234 hands off the isolation evidence that CONS-02 then builds on. Doing CONS-02's job inside QST-03 would duplicate effort and blur the consumer index.

**Gray area:** If QST-03's isolation check turns up something that breaks isolation — e.g., an accidental change to `mintForGame` inside the same commit, or a ripple through an ERC-20 invariant — the verdict flips from SAFE to FINDING-CANDIDATE and Phase 235 CONS-02 inherits a harder problem. Not expected given Phase 230 §1.8 already characterized the diff as "3 insertions / 1 deletion — one 3-line hunk (2 comment lines + 1 semantic line inside `decimatorBurn`)", but the audit still looks.

---

## 6. Overlap with Phase 232 DCM-01 on Commit `3ad0f8d3`

| Option | Description | Selected |
|--------|-------------|----------|
| A. Different aspects, no scope conflict — Phase 232 DCM-01 owns the AdvanceModule / DecimatorModule / DegenerusGame-wrapper slices (the cause and the consuming jackpot read sites); Phase 234 QST-03 owns only the BurnieCoin slice (the isolation property) | Matches Phase 230 Consumer Index split (DCM-01 → §1.3 / §1.1 / §1.8 / §2.2 IM-06..09; QST-03 → §1.8 / §2.2 IM-09 only) | ✓ |
| B. Move the BurnieCoin slice into DCM-01 entirely; Phase 234 becomes 2-requirement | Contradicts ROADMAP explicit QST-03 scope | |
| C. Duplicate the BurnieCoin audit across both DCM-01 and QST-03 (redundancy for safety) | Wasted effort; confuses Phase-236 findings anchoring | |

**Selected:** A (per D-11).
**Rationale:** Commit `3ad0f8d3` touches multiple files with a unified cause (key burns by resolution level) but the audit aspects differ: DCM-01 audits the CAUSE (what the key-by-resolution-level refactor does to pool math, event emission, pro-rata share calc) + the non-BurnieCoin consumers; QST-03 audits the ISOLATION property on the BurnieCoin slice (that the BurnieCoin change doesn't bleed into supply-conservation territory). Phase 230 Consumer Index §4 already carves the overlap cleanly — DCM-01 cites §1.3 (Decimator module entirety) + §1.1 (AdvanceModule `_consolidatePoolsAndRewardJackpots`) + §1.8 (BurnieCoin for key-alignment reads) + §2.2 IM-06..09; QST-03 cites only §1.8 + IM-09 for the isolation lens. No duplication; no gap.

**Gray area:** If Phase 232 DCM-01 planner tries to expand into QST-03 territory (or vice versa), the phase owning the verdict for "is the BurnieCoin change confined?" is Phase 234. DCM-01's concern with §1.8 is narrow: "does the `+1` key match the `N+1` read side in Decimator module?" — that's a key-alignment question, not an isolation question. If confusion arises at plan time, Phase 234's plan asserts ownership of the isolation verdict explicitly.

---

## Auto-mode defaults used (for audit trail)

Per `auto_mode_rules` in the task prompt:
1. Default to v25.0 Phase 214 precedent for per-function verdict row shape → locked via D-02.
2. Default to narrowest scope satisfying ROADMAP SC1-4 → locked via D-05 (QST-01 depth), D-06 (QST-02 layout scope), D-09 (QST-03 isolation vs. conservation).
3. Default to per-function verdict table columns (Target / File:Line / Attack Vector / Verdict / Evidence / SHA) → locked via D-02.
4. Default to 1 consolidated plan per ROADMAP explicit guidance → locked via D-01.
5. Default to `230-01-DELTA-MAP.md` as exclusive scope source → locked via the canonical-refs block of CONTEXT.md.
6. QST-01 companion-test-file review is READ-only per milestone rule → locked via D-04.
7. QST-02 storage-layout preservation is diff-scoped (grep-style), no write-path scan → locked via D-06/D-07.
8. QST-03 isolation scope (confined to decimator-burn-key plumbing; end-to-end supply → Phase 235 CONS-02) → locked via D-09.

## Deferred Ideas

- See CONTEXT.md `<deferred>` section. Summary: Phase 235 CONS-02 (BurnieCoin supply end-to-end), Phase 236 FIND-01/02/03 (finding-ID assignment), Phase 236 REG-01/02 (regression sweep), full quest-framework re-audit (out of scope — non-delta handlers), full storage-layout diff against v5.0 baseline (out of scope — not a diff-scoped concern), interface-completeness re-opening on `boonPacked` getter (out of scope — Phase 230 D-10 settles it).

---

*Phase: 234-quests-boons-misc-audit*
*Log closed: 2026-04-17*
