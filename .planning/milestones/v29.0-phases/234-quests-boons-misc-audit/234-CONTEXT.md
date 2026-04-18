# Phase 234: Quests / Boons / Misc Audit - Context

**Gathered:** 2026-04-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Adversarial audit of the three low-coupling isolated changes left in the v29.0 delta surface after the earlybird (Phase 231), decimator (Phase 232), and jackpot/BAF/entropy (Phase 233) slices are carved out. Three commits / three scopes:

1. **`d5284be5` — `mint_ETH` wei-credit fix** (QST-01). `DegenerusQuests.handlePurchase` parameter 2 retyped `uint32 ethMintQty → uint256 ethFreshWei`; `DegenerusGameMintModule._purchaseFor` + `_callTicketPurchase` rewritten to compute `ethFreshWei = ticketFreshEth + lootboxFreshEth` and pass it 1:1 to the quest; `IDegenerusQuests.handlePurchase` interface declaration updated in lockstep.
2. **`e0a7f7bc` — `boonPacked` mapping exposure** (QST-02). `mapping(address => BoonPacked) internal boonPacked;` → `public` on `DegenerusGameStorage`, auto-generating an external getter `boonPacked(address) returns (uint256 slot0, uint256 slot1)` on the `DegenerusGame` deployed address. No interface declaration added.
3. **BurnieCoin slice of `3ad0f8d3` — decimator-burn-key plumbing** (QST-03). `BurnieCoin.decimatorBurn` body: `uint24 lvl = degenerusGame.level();` → `uint24 lvl = degenerusGame.level() + 1;` (plus two rationale comment lines). The non-BurnieCoin slices of `3ad0f8d3` are owned by Phase 232 DCM-01; Phase 234 QST-03 audits ONLY the isolation property of the BurnieCoin slice (no supply-conservation impact; end-to-end BURNIE conservation is Phase 235 CONS-02).

**Deliverable shape:** single consolidated plan `234-01-PLAN.md` with three per-requirement sections (QST-01 / QST-02 / QST-03) — grab-bag pattern per ROADMAP Phase 234 explicit guidance. Three requirements are LOW-coupling and individually tractable; splitting into 3 separate plans would add orchestration overhead without audit benefit. Scope is strictly READ-only: no `contracts/` or `test/` writes; no finding-ID emission (Phase 236 owns F-29-NN assignment).

</domain>

<decisions>
## Implementation Decisions

### Deliverable Shape
- **D-01:** One consolidated plan `234-01-PLAN.md` with three top-level sections (QST-01, QST-02, QST-03) — matches ROADMAP Phase 234 explicit guidance ("1 plan with per-requirement sections — grab-bag pattern per v29.0 roadmap guidance"). Three requirements touch three different surfaces with zero execution-level coupling (a quest wei-credit fix, a mapping visibility flip, and one BurnieCoin line); splitting into three plans would produce three near-identical scaffolds. Single plan keeps the reviewer cursor in one place.

### Audit Methodology
- **D-02:** Per-function / per-target verdict table for each of the three sections. Columns: `Target | File:Line | Attack Vector | Verdict | Evidence | SHA`. Matches v25.0 Phase 214 adversarial-audit row shape and the v27.0 Phase 220 greppability pattern the user has repeatedly validated. Targets for each section:
  - QST-01: `DegenerusQuests.handlePurchase`, `DegenerusGameMintModule._purchaseFor`, `DegenerusGameMintModule._callTicketPurchase`, `IDegenerusQuests.handlePurchase` interface declaration.
  - QST-02: `DegenerusGameStorage.boonPacked` mapping declaration, auto-generated `DegenerusGame.boonPacked(address)` external getter, storage-layout spot check (no write-path scan across the whole codebase — only within the e0a7f7bc commit's diff).
  - QST-03: `BurnieCoin.decimatorBurn` (the +1 line and its direct reads/writes).

### Scope Guard
- **D-03:** If any section uncovers a delta-surface gap (a target this phase should cite but §1/§2/§3 of `230-01-DELTA-MAP.md` doesn't catalog), record the gap as a Phase-234 scope-guard deferral in the plan's SUMMARY rather than editing `230-01-DELTA-MAP.md` in-place (Phase 230 D-06 read-only-after-commit rule). Carries the v28.0 Phase 227/228 D-227-10 → D-228-09 precedent forward.

### QST-01 Specifics
- **D-04:** Companion test-file review (ROADMAP Phase 234 SC1: "the companion test-file change reviewed") is a **read-only** inspection of whatever `test/` file is touched by `d5284be5` to confirm it aligns with the fix. No test writes this phase per milestone READ-only rule. Scope: does the companion test cover the wei-direct credit path that `handlePurchase` now exercises? If it does — pass. If it doesn't — flag as a test-coverage gap for Phase 236 to surface (not a finding in its own right at this phase).
- **D-05:** Fresh-ETH detection interaction review stays **within the delta**. The audit confirms `ticketFreshEth + lootboxFreshEth` summation in `_purchaseFor` is the sole feed into both the unified earlybird award (IM-01 — Phase 231's concern) and the MINT_ETH quest credit (IM-17 — Phase 234's concern), then reasons about whether the two consumers double-credit any single wei. It does NOT re-audit the full quest-handler framework, streak accounting, or non-delta quest types (handleMint, handleFlip, handleDecimator, handleAffiliate, handleLootBox, handleDegenerette) — those are out-of-scope for v29.0 because `d5284be5` doesn't touch them. Companion-quest audit surface is delta-only.

### QST-02 Specifics
- **D-06:** Storage-layout preservation is verified **grep-style** against the e0a7f7bc diff only — confirm no slot-placeholder lines (slots 25-41, 72-82, 85-87, 93-95) changed; confirm no new storage variable was introduced; confirm the sole semantic change is the `internal → public` keyword flip on an existing declaration. This is not a `forge inspect` storage-layout diff against v5.0 baseline (that is Phase 235/236 territory if anything) — just a diff-scoped check that `e0a7f7bc` didn't sneak in a layout change under the guise of a visibility flip.
- **D-07:** "No write path introduced" is verified by inspecting the e0a7f7bc diff itself — visibility flip on a mapping declaration cannot by itself introduce a write path, but the audit explicitly confirms the commit contains zero new `boonPacked[...] = ...` assignments and zero new functions that could write to the mapping. Existing write paths (whatever sets `BoonPacked` slots today) are pre-delta and out of scope.
- **D-08:** Known non-issue carried forward from `230-01-SUMMARY.md` item 1: the auto-generated getter `boonPacked(address)` is NOT declared on `IDegenerusGame.sol`. Phase 230 classified this as "interface-completeness gap, NOT drift" (D-10, §3.1 note). Phase 234 QST-02 **documents-and-accepts** — the auto-getter serves UI/off-chain consumers that read the concrete `DegenerusGame` address directly; on-chain consumers of the interface don't need it. No finding is emitted for this by Phase 234; if Phase 236 disagrees on aesthetic grounds it can open a Phase-236 finding, but it is not a drift failure and this phase does not reopen the question.

### QST-03 Specifics
- **D-09:** The audit confirms the BurnieCoin diff is **CONFINED to decimator-burn-key plumbing** — specifically the single line `uint24 lvl = degenerusGame.level() + 1;` inside `decimatorBurn` plus two rationale comment lines. Verification is a direct read of the e0a7f7bc-era BurnieCoin slice (actually authored by `3ad0f8d3`, see overlap note D-11) and confirmation that no other function on `BurnieCoin.sol` is touched, no `mintForGame` change, no burn-path change other than the level-key, no ERC-20 accounting change. End-to-end supply / mint-burn closure across the BurnieCoin boundary is **Phase 235 CONS-02** — QST-03 hands off the isolation evidence and does not re-do the conservation proof.

### Cross-Phase Coordination
- **D-10:** Finding-ID emission is deferred to Phase 236 FIND-01/02/03. This phase produces verdicts and evidence anchors only; `F-29-NN` IDs are assigned during consolidation. Matches v29.0 milestone-wide convention (Phase 230 SUMMARY §Known-Non-Issues + ROADMAP Phase 236 SC3).
- **D-11:** Overlap with Phase 232 DCM-01 is intentional and non-conflicting. Commit `3ad0f8d3` is split by file: Phase 232 DCM-01 owns the AdvanceModule / DecimatorModule / DegenerusGame-wrapper slices (the cause and the consuming jackpot read sites), and Phase 234 QST-03 owns only the BurnieCoin slice (the isolation property — that the BurnieCoin change is CONFINED to decimator-burn-key plumbing and doesn't drag in any supply-conservation or ERC-20-invariant side effect). Different aspects of the same commit; no scope conflict.

### Post-Phase-230 Addendum Integration
- **D-12 (Phase 230 scope extended via 230-02-DELTA-ADDENDUM.md):** Two contract commits landed AFTER Phase 230 locked its DELTA-MAP: `314443af` (MintModule `_raritySymbolBatch` keccak-seed fix — out of Phase 234 scope, no QST/BOON/MISC surface) and `c2e5e0a9` (17-site entropy-mixing fix). Phase 234 scope is MARGINALLY AFFECTED via `DegenerusGamePayoutUtils._calcAutoRebuy` which `c2e5e0a9` migrated from `entropyStep(entropy ^ uint256(uint160(beneficiary)) ^ weiAmount)` to `keccak256(abi.encode(entropy, beneficiary, weiAmount))`. PayoutUtils is consumed by whale-bundle and auto-rebuy paths which are NOT in QST-01/02/03 scope — but Plan 234-01 SHOULD include a brief per-target row in QST-01's verdict table acknowledging that the quest-wei-credit change (`d5284be5` → `ticketFreshEth + lootboxFreshEth`) is passed through `_callTicketPurchase` and the auto-rebuy derivation is a sibling path that uses the same `entropy` via the new `keccak256(...)` formulation. This is a READ-ONLY cross-reference; no re-audit of PayoutUtils within Phase 234.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents (planner, executor) MUST read these before planning or executing.**

### Phase 230 catalog (exclusive scope source — READ-only)
- `.planning/phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md`
  - **§1.4** modules/DegenerusGameMintModule.sol — `_purchaseFor` + `_callTicketPurchase` rows (`d5284be5` slice for QST-01 quest-credit wiring; `f20a2b5e` slice is Phase-231 territory and out of scope here)
  - **§1.6** core/DegenerusGame.sol — forwarder context for the boonPacked auto-getter (Phase 230 §1.10 note classifies the interface non-declaration as non-drift)
  - **§1.7** core/DegenerusQuests.sol — `handlePurchase` MODIFIED by `d5284be5` — primary QST-01 target
  - **§1.8** core/BurnieCoin.sol — `decimatorBurn` MODIFIED by `3ad0f8d3` — sole QST-03 target
  - **§1.9** storage/DegenerusGameStorage.sol — `boonPacked` mapping visibility flip by `e0a7f7bc` — primary QST-02 target
  - **§1.10** interfaces/IDegenerusGame.sol — the "Note on `boonPacked` exposure" paragraph explaining why the interface was intentionally left untouched
  - **§1.12** interfaces/IDegenerusQuests.sol — `handlePurchase` declaration MODIFIED by `d5284be5` in lockstep with §1.7 — QST-01 drift-alignment anchor
  - **§2.4** Quest/Boon/Misc chains — IM-17 (`_purchaseFor → DegenerusQuests.handlePurchase`), IM-18 (`_purchaseFor → DegenerusGame.recordMintQuestStreak`), IM-19 (UI → `DegenerusGame.boonPacked(address)` getter), IM-20 (placeholder — no cross-module chain for boon-pool transfer because that path goes through the out-of-scope DGNRS contract)
  - **§2.2** IM-09 (BurnieCoin.decimatorBurn → DegenerusGame.level getter) — the QST-03 caller-side chain
  - **§3** drift rows — §3.1 note (boonPacked interface non-declaration, QST-02) + §3.2 ID-67 (`handlePurchase` drift-free lockstep update, QST-01)
  - **§4 Consumer Index** — QST-01 / QST-02 / QST-03 rows naming the exact section/row anchors this phase will cite
- `.planning/phases/230-delta-extraction-scope-map/230-01-SUMMARY.md`
  - **Known Non-Issues item 1** — `boonPacked` auto-generated getter not on `IDegenerusGame.sol` is **by design** (UI reads the concrete address; not a drift failure). QST-02 carries this forward per D-08.

### Milestone scope
- `.planning/REQUIREMENTS.md` — **QST-01**, **QST-02**, **QST-03** (this phase's three in-scope requirements). Also REG-01/REG-02 (Phase 236 consumers) cite §1.7/§1.8/§1.9 surfaces.
- `.planning/ROADMAP.md` — **Phase 234** block (Goal, Depends on: Phase 230, four Success Criteria, Plans: "TBD expected 1 plan with per-requirement sections — grab-bag pattern per v29.0 roadmap guidance"). Phase 234 success criteria 1–4 drive D-01 / D-02 / D-04 / D-10.
- `.planning/PROJECT.md` — Current Milestone section lists the 10 in-scope commits, including the three relevant to Phase 234: `d5284be5`, `e0a7f7bc`, and the BurnieCoin slice of `3ad0f8d3`.
- `.planning/STATE.md` — current phase pointer (read-only for this context; Phase 234 does not update it).

### Methodology precedent
- `.planning/milestones/v25.0-phases/214-adversarial-audit/214-CONTEXT.md` — adversarial audit CONTEXT shape; the per-function verdict row layout (Target / File:Line / Attack Vector / Verdict / Evidence / SHA) derives from 214-01/02/03/04/05's sub-plan tables.
- `.planning/phases/230-delta-extraction-scope-map/230-CONTEXT.md` — CONTEXT structure template used as shape reference for this file.

### User-feedback rules actively enforced this phase
- `feedback_contract_locations.md` — read contracts only from `contracts/` (NOT stale copies elsewhere).
- `feedback_no_contract_commits.md` + milestone READ-only rule — no `contracts/` or `test/` writes.
- `feedback_skip_research_test_phases.md` — Phase 234 IS the kind of "obvious / mechanical" phase that skips research; we plan directly from the 230 catalog.
- `feedback_rng_backward_trace.md` + `feedback_rng_commitment_window.md` — not directly applicable (no RNG consumers in QST-01/02/03), but remain in force if any sub-analysis strays into RNG territory.

### Phase 236 downstream consumer
- Findings anchors produced here feed the Phase-236 finding-candidate pool (ROADMAP Phase 236 SC3 — every `F-29-NN` ID cites source phase + file:line + severity + resolution).

</canonical_refs>

<code_context>
## Existing Code Insights

Observations pulled directly from the Phase 230 Consumer Index (§4 rows QST-01, QST-02, QST-03) and the referenced §1 / §2 / §3 rows — no independent re-discovery required.

### QST-01: `mint_ETH` wei-credit fix (`d5284be5`)
- `DegenerusQuests.handlePurchase` parameter 2 retyped `uint32 ethMintQty → uint256 ethFreshWei`; in-body `uint256 delta = uint256(ethMintQty) * mintPrice;` removed. `ethFreshWei` is now passed directly as the MINT_ETH quest delta (1:1 wei credit). Zero CEI / side-effect change beyond the unit switch (§1.7).
- `DegenerusGameMintModule._purchaseFor` computes `uint256 ethFreshWei = ticketFreshEth + lootboxFreshEth` and passes it to `quests.handlePurchase`; the conditional `if (ethMintUnits > 0 && questType == 1)` became `if (ethFreshWei > 0 && questType == 1)` (§1.4). The `recordMintQuestStreak` predicate on IM-18 flipped in lockstep.
- `DegenerusGameMintModule._callTicketPurchase` return tuple swapped `uint32 ethMintUnits → uint256 freshEth`; the in-body `questUnits * freshEth / costWei` scaling block was removed (§1.4).
- `IDegenerusQuests.handlePurchase` interface declaration mirrored the param retype in the same commit — drift-free lockstep update (§1.12, §3.2 ID-67 PASS).
- Cross-module chains: IM-17 (the `quests.handlePurchase` external call) + IM-18 (the `recordMintQuestStreak` self-call predicate flip).

### QST-02: `boonPacked` mapping exposure (`e0a7f7bc`)
- Single declaration change on `DegenerusGameStorage`: `mapping(address => BoonPacked) internal boonPacked;` → `mapping(address => BoonPacked) public boonPacked;` (§1.9). Storage layout unchanged — slot placeholders 25-41, 72-82, 85-87, 93-95 preserved.
- Auto-generated external getter signature: `boonPacked(address) external view returns (uint256 slot0, uint256 slot1)` on the `DegenerusGame` deployed address (the getter is public on the storage contract; inherited through `DegenerusGame`'s inheritance chain).
- `IDegenerusGame.sol` was NOT touched by `e0a7f7bc` — the getter is intentionally off-interface per D-08 and the Phase 230 §1.10 note / §3.1 classification.
- Cross-module chain: IM-19 (UI / off-chain readers → `DegenerusGame.boonPacked(address)` auto-getter). No in-contract consumer.
- No write-path change anywhere in the commit — this is a read-surface extension only.

### QST-03: BurnieCoin slice of `3ad0f8d3` (decimator-burn-key plumbing)
- Single semantic line change on `BurnieCoin.decimatorBurn` (§1.8): `uint24 lvl = degenerusGame.level();` → `uint24 lvl = degenerusGame.level() + 1;`. Plus two comment lines documenting the rationale (burns during window level N land in `decBurn[N+1]` so they match the jackpot-resolution read side, which runs after the N→N+1 bump).
- Side effect noted in the catalog: `DECIMATOR_MIN_BUCKET_100` now activates at the L100 jackpot (previously `lvl % 100 == 0` was dead code against `level()=99`). The activation-at-L100 is the intended fix, not an unintended consequence.
- Cross-module chain: IM-09 (`BurnieCoin.decimatorBurn → DegenerusGame.level` getter). Call-site itself unchanged — the MODIFIED caller's use of the return value is the load-bearing surface.
- NO change to `mintForGame`, NO change to any burn path other than the level-key, NO change to ERC-20 balance/supply accounting, NO change to any other function in `BurnieCoin.sol`. Isolation scope is the claim QST-03 verifies.

### Automated gates that already cover parts of this surface (from 230-01 §3.4/§3.5)
- `make check-interfaces` — PASS (includes the `IDegenerusQuests.handlePurchase` drift-free lockstep check that QST-01 relies on).
- `make check-delegatecall` — PASS 44/44 (not directly relevant to any of the three QST sections — no new delegatecall sites introduced by these three commits).
- `forge build` — PASS (warnings are pre-existing `unsafe-typecast` on `BurnieCoin.sol` among others; none introduced by the delta).
- These gates form the automated floor; Phase 234's contribution is the adversarial verdict layer on top.

</code_context>

<specifics>
## Specific Ideas

Single consolidated `234-01-PLAN.md` with three top-level sections mirroring the three requirement IDs (grab-bag shape):

1. **Section 1 — QST-01 (mint_ETH wei-credit fix, `d5284be5`).** Per-target verdict table covering `DegenerusQuests.handlePurchase`, `DegenerusGameMintModule._purchaseFor`, `DegenerusGameMintModule._callTicketPurchase`, and the `IDegenerusQuests.handlePurchase` interface declaration. Anchors in 230-01 §1.4, §1.7, §1.12, §2.4 IM-17/IM-18, §3.2 ID-67, §4 QST-01 row. Attack-vector columns: double-credit with companion quests, precision loss in the removed `uint32 * mintPrice` scaling vs. the new `uint256` wei-direct path, interaction with fresh-ETH detection in `_purchaseFor`, CEI/ordering of the `quests.handlePurchase` external call relative to state writes. Companion test-file read-only review per D-04.

2. **Section 2 — QST-02 (boonPacked mapping exposure, `e0a7f7bc`).** Per-target verdict table covering the mapping declaration on `DegenerusGameStorage`, the auto-generated `DegenerusGame.boonPacked(address)` external getter, and the diff-scoped storage-layout-preservation check. Anchors in 230-01 §1.9, §1.10 note, §2.4 IM-19, §3.1 note on §3.1, §4 QST-02 row. Attack-vector columns: read-only-accessor safety (can the returned `(uint256 slot0, uint256 slot1)` leak any information not already visible via existing boon-consuming externals?), storage layout preservation (diff-scoped, per D-06), no-write-path-introduced (per D-07), slot accessibility matches intent (the auto-getter returns the raw packed slots, which is the UI contract). Known non-issue from 230-01-SUMMARY item 1 documented and accepted per D-08.

3. **Section 3 — QST-03 (BurnieCoin slice of `3ad0f8d3`).** Per-target verdict table covering only `BurnieCoin.decimatorBurn`. Anchors in 230-01 §1.8, §2.2 IM-09, §4 QST-03 row. Attack-vector columns: isolation (is the diff confined to the decimator-burn-key line and its comments?), no supply-conservation side effect (no `mintForGame` change, no balance/supply accounting change), no ERC-20 invariant drift, no unintended behavior change outside decimator-burn keying. Supply conservation end-to-end across the BurnieCoin boundary is **deferred to Phase 235 CONS-02** per D-09.

Per-section structure inside the plan:
- **Scope anchors** — 230-01 section/row references + commit SHA.
- **Per-target verdict table** — Target | File:Line | Attack Vector | Verdict | Evidence | SHA.
- **Narrative** — 2-4 paragraphs per requirement explaining the verdicts, not re-deriving the delta.
- **Finding candidates for Phase 236** — bullet list of anchors only (no `F-29-NN` IDs assigned here per D-10).

Verdict column vocabulary: `SAFE` / `INFO` / `FINDING-CANDIDATE`. No `VULNERABLE` verdict at this phase — escalations become Phase-236 finding candidates with severity to-be-assigned during consolidation.

</specifics>

<deferred>
## Deferred Ideas

- **Phase 235 CONS-02** — End-to-end BURNIE supply / mint-burn closure across the `BurnieCoin.sol` change and the quest changes. QST-03 verifies the BurnieCoin slice is CONFINED to decimator-burn-key plumbing (no supply-accounting touchpoint inside the commit); CONS-02 proves the broader invariant across every burn-path and mint-path that the delta reaches. Handoff: Phase 234 SUMMARY cites the isolation evidence; Phase 235 consumes it and closes the conservation proof.
- **Phase 236 FIND-01/02/03** — All finding-ID assignment, severity classification, resolution-status tracking, and `audit/FINDINGS-v29.0.md` consolidation. Phase 234 emits zero `F-29-NN` IDs. Finding candidates surfaced by this phase's verdict tables are handed to Phase 236 as evidence-anchored bullets only.
- **Phase 236 REG-01 / REG-02** — v27.0 INFO + v25.0/v26.0 findings regression sweep across the §1.7 / §1.8 / §1.9 surfaces this phase audits fresh. Phase 234 does not re-derive any regression verdict against prior milestones; it reports on the delta only.
- **Full quest-framework re-audit** — explicitly OUT of scope per D-05. The non-delta quest handlers (`handleMint`, `handleFlip`, `handleDecimator`, `handleAffiliate`, `handleLootBox`, `handleDegenerette`), streak accounting, level-quest progress, and quest-roll entropy were untouched by `d5284be5`; they are not audited here. If Phase 236 decides a companion-quest re-audit is warranted, that is a new phase outside v29.0.
- **Full DegenerusGameStorage layout diff against v5.0 baseline** — explicitly OUT of scope per D-06. The QST-02 check is a diff-scoped preservation verification against the e0a7f7bc commit only. A whole-layout diff is a Phase 235/236 decision if ever taken.
- **Interface-completeness decision on `boonPacked` auto-getter** — per D-08, this phase documents-and-accepts the Phase 230 §3.1 classification. If a downstream reviewer wants the getter declared on `IDegenerusGame.sol` on aesthetic grounds, that is a Phase-236 finding candidate, NOT a Phase-234 re-opening.

</deferred>

---

*Phase: 234-quests-boons-misc-audit*
*Context gathered: 2026-04-17*
