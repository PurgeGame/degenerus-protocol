# Phase 237: VRF Consumer Inventory & Call Graph — Context

**Gathered:** 2026-04-18
**Status:** Ready for planning
**Mode:** Auto-decided via Phase 230/235 precedents (user chose "Auto-decide using precedents")

<domain>
## Phase Boundary

Produce the authoritative v30.0 audit scope catalog: the universe list of every VRF-consuming call site in `contracts/` at HEAD `7ab515fe`, typed by path family, with per-consumer request→fulfillment→consumption call graph. Phases 238-241 consume this inventory as their scope definition — no additional discovery required downstream.

Scope is READ-only: no `contracts/` or `test/` writes. Finding-ID emission is deferred to Phase 242 (FIND-01/02/03); Phase 237 produces rows + subcategories + call-graphs + reconciliation + Consumer Index that become the finding-candidate pool.

Three requirements:
- **INV-01** — Exhaustive universe list of every VRF-consuming call site, no sampling
- **INV-02** — Path-family classification (`daily` / `mid-day-lootbox` / `gap-backfill` / `gameover-entropy` / `other` with named subcategory)
- **INV-03** — Per-consumer call graph from VRF request origination through `rawFulfillRandomWords` to consumption site, including intermediate storage touchpoints

Fresh-eyes mandate: prior-milestone artifacts (v25.0, v29.0 Plans 235-03/04, v3.7, v3.8) may be *referenced as context* but MUST NOT be *relied upon* — every row re-derived at HEAD `7ab515fe`, with a post-hoc reconciliation pass against prior lists for completeness (D-07).

</domain>

<decisions>
## Implementation Decisions

### Consumer Row Granularity
- **D-01 (fine-grained, each file:line consumption site = one row):** Each distinct consumption site where a VRF-derived word (or derivative) is read gets its own inventory row. Matches v29.0 Phase 235 D-07 precedent exactly ("each site is its own table row, no equivalence-class shortcuts"). The 17 `EntropyLib.hash2` / `keccak256(abi.encode(...))` entropy-mixing sites from commit `c2e5e0a9` each get their own row. Expected ~40-80 rows total.
- **D-02 (EntropyLib XOR-shift treatment — classify by caller):** `EntropyLib.entropyStep()` is a PRNG primitive, not a standalone consumer; each CALLER of `entropyStep()` is an inventory row, classified by the calling site's path family. Library internals do not inflate the row count — the call sites do.
- **D-03 (dual-trigger consumers get one row per trigger context):** If the same function is reached from multiple path-family contexts (e.g., a trait-roll helper called from both daily and gameover paths), each distinct trigger context is a separate row. Collapsing would mask divergent freeze behavior between contexts.

### Path-Family Taxonomy
- **D-04 (5 families + named-subcategory rule for `other`):** Assign one of `daily` / `mid-day-lootbox` / `gap-backfill` / `gameover-entropy` / `other` per row. Any row classified `other` MUST carry a named subcategory plus a one-line justification. Matches ROADMAP success criterion 2.
- **D-05 (taxonomy rules — by triggering path):**
  - `daily`: coinflip outcome, daily lootbox ticket resolution, boons resolved at daily VRF fulfillment, quest resolution tied to daily RNG
  - `mid-day-lootbox`: mid-day lootbox VRF fulfillment + all downstream consumers (trait rolls, rarity, BAF sentinel emission, bonus outcomes)
  - `gap-backfill`: `_backfillGapDays` + `keccak256(vrfWord, gapDay)` derivation + orphaned lootbox index fallback
  - `gameover-entropy`: `_gameOverEntropy` + every consumer of the gameover VRF word (winner selection, trait rolls, terminal drain, final burn/coinflip resolution, sweep distribution)
  - `other`: anything that doesn't fit cleanly — use subcategory (e.g., `exception-non-VRF-seed`, `exception-prevrandao-fallback`, `exception-mid-cycle-substitution`, `library-wrapper`)
- **D-06 (KNOWN-ISSUES exceptions ARE in the inventory with KI cross-ref column):** Affiliate winner roll, gameover prevrandao fallback (`_getHistoricalRngFallback`), F-29-04 mid-cycle substitution path, and EntropyLib XOR-shift sites each appear as inventory rows with subcategory naming the exception and a KI cross-ref. Rationale: Phase 241 (EXC-01..04) needs inventory rows as its proof subjects; omitting exceptions would break the "inventory is the scope definition" invariant. Rows are IN the inventory; their determinism-invariant violation is accepted per KI, not hidden.
- **D-07 (prior-artifact cross-check — two-pass, fresh first):** Plan 01 enumerates FRESH at HEAD with NO glance at prior lists (zero-glance pass). Plan 01's second pass reconciles the fresh list against `v29.0 Phase 235 Plans 03-04` + `v25.0 Phase 215` + `v3.7/v3.8` artifacts. Every delta is a reconciliation row with verdict: `confirmed-fresh-matches-prior` / `was-missed-now-added` / `was-spurious-before-not-at-HEAD` / `new-since-prior-audit`. Gets the fresh-eyes signal without losing the safety net.

### Output Shape
- **D-08 (single consolidated file, `audit/v30-CONSUMER-INVENTORY.md`):** One consolidated deliverable matching Phase 230 D-05 single-file pattern. Sections (order is planner's discretion):
  1. Universe list (tabular) — one row per consumer
  2. Path-family classification key + subcategory legend
  3. Per-consumer call graphs (tabular rows, one per consumer)
  4. Prior-artifact reconciliation table (per D-07)
  5. Consumer Index — v30.0 requirement → row-ID mapping (per D-10)
- **D-09 (tabular, grep-friendly, no mermaid):** Follows Phase 230 D-08 convention. Universe-list columns: `Row ID | Consumption File:Line | Consumer Function | Path Family | Subcategory | VRF Request Origin File:Line | Fulfillment Site File:Line | Call Graph Ref | KI Cross-Ref | Notes`. Downstream phases grep inventory rows by Row ID.
- **D-10 (Consumer Index at end — requirement→row mapping, Phase 230 D-11 pattern):** Inventory ends with a Consumer Index section mapping every v30.0 requirement (INV-01..03, BWD-01..03, FWD-01..03, RNG-01..03, GO-01..05, EXC-01..04, REG-01..02, FIND-01..03) to the specific Row IDs it will cite. Saves Phase 238-242 planners lookup work.
- **D-11 (call-graph depth — stop at consumption site, trace delegatecalls to target, trace library calls to library):** Call graph covers request origination → `rawFulfillRandomWords` → intermediate storage touchpoints → consumption site. STOPS at consumption — downstream SSTORE effects are Phase 238 FWD scope, not 237. Delegatecalls are traced to the target module; library calls (`EntropyLib`, `BitPackingLib`, `JackpotBucketLib`) are traced to the library function signature and back.
- **D-12 (companion callgraph files only for oversized graphs):** If a per-consumer call graph exceeds ~30 lines, hive off to `audit/v30-237-CALLGRAPH-<slug>.md` and link from the inventory row via Call Graph Ref column. Otherwise inline. Soft threshold — planner's discretion.

### Plan Split
- **D-13 (3 plans, matching ROADMAP "expected 2-3 plans"):**
  - `237-01-PLAN.md` INV-01 — Enumeration sweep: zero-glance fresh-eyes pass + prior-artifact reconciliation → produces the universe row list
  - `237-02-PLAN.md` INV-02 — Classification + path-family + subcategory + KI cross-ref → types every row committed by 237-01
  - `237-03-PLAN.md` INV-03 — Per-consumer call graphs + Consumer Index → full request→fulfillment→consumption traces for every row
- **D-14 (wave topology — 237-01 wave 1, 237-02/237-03 wave 2 parallel):** 237-01 must commit first (universe list stabilizes scope). 237-02 and 237-03 run in parallel after 237-01 commits — each operates on the committed row list independently (classification vs call-graph). Matches v29.0 Phase 233/234 "all parallel after enumeration" pattern.

### Finding-ID Emission
- **D-15 (no `F-30-NN` emission, Phase 235 D-14 / Phase 230 D-06 pattern):** Phase 237 does NOT emit `F-30-NN` finding IDs. Produces rows + subcategories + call-graphs + reconciliation that become the finding-candidate pool. Any row discovered fresh-eyes that isn't covered by existing KI entries is flagged in a "Finding Candidates" subsection with file:line + proposed severity for Phase 242 routing. Phase 242 (FIND-01/02/03) owns ID assignment, severity classification, and consolidation into `audit/FINDINGS-v30.0.md`.

### Scope-Guard Handoff
- **D-16 (237 output READ-only after commit — scope-guard deferral rule, Phase 230 D-06 / Phase 235 D-15 pattern):** `audit/v30-CONSUMER-INVENTORY.md` and any companion `audit/v30-237-CALLGRAPH-*.md` files are READ-only after Phase 237 commit. If Phase 238/239/240/241 finds a consumer not in the inventory, it records a scope-guard deferral in its own plan SUMMARY; Phase 237 output is not re-edited in place. Inventory gaps become Phase 242 finding candidates.
- **D-17 (HEAD anchor = `7ab515fe` at phase start, locked in every plan's frontmatter — Phase 230 D-06 / Phase 235 D-05 pattern):** ROADMAP/STATE already lock HEAD `7ab515fe`. Every Phase 237 plan's frontmatter freezes the SHA. Contract tree is identical to v29.0 `1646d5af`; all post-v29 commits are docs-only and do not invalidate. Any contract change after `7ab515fe` resets the baseline and requires a scope addendum.
- **D-18 (READ-only scope, no `contracts/` or `test/` writes):** Carries forward v28/v29 cross-repo READ-only pattern and project-level `feedback_no_contract_commits.md` rule. Writes confined to `.planning/` and `audit/` (creating `v30-*` files). `KNOWN-ISSUES.md` is not touched in Phase 237 — KI promotions are Phase 242 FIND-03 only.

### Claude's Discretion
- Exact section ordering within `audit/v30-CONSUMER-INVENTORY.md` (planner picks most readable order of the 5 sections in D-08)
- Whether to produce a small companion "path-family reference card" markdown as one-line-per-family quick reference
- Whether a given consumer's call graph is inline vs hived off to a companion file (D-12 soft threshold)
- Whether to preserve raw `grep` commands in plan SUMMARIES for reviewer sanity-checking (encouraged when non-obvious)
- Row ID format (e.g., `CONS-237-NNN` vs `INV-NNN` vs other) — planner picks, used consistently across all sections

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Milestone scope (MUST read)
- `.planning/REQUIREMENTS.md` — v30.0 requirements: INV-01, INV-02, INV-03 (this phase) + full requirement catalog including downstream BWD/FWD/RNG/GO/EXC/REG/FIND Phase 237 is defining the scope for
- `.planning/ROADMAP.md` — Phase 237 success criteria (4 items) + execution-order narrative + prior-artifact-reference ban
- `.planning/PROJECT.md` — Current milestone section + write-policy statement

### Accepted RNG exceptions (MUST read — these are inventory rows with KI cross-ref)
- `KNOWN-ISSUES.md` — 4 accepted RNG exception entries:
  - "Non-VRF entropy for affiliate winner roll"
  - "Gameover prevrandao fallback" (`_getHistoricalRngFallback`, `DegenerusGameAdvanceModule.sol:1301`, gating at `:1252` / delay `:109`)
  - "Gameover RNG substitution for mid-cycle write-buffer tickets" (F-29-04; `_swapAndFreeze` at `DegenerusGameAdvanceModule.sol:292`; `_swapTicketSlot` at `:1082`; `_gameOverEntropy` at `:1222-1246`)
  - "EntropyLib XOR-shift PRNG for lootbox outcome rolls" (`EntropyLib.entropyStep()`, VRF-seeded per keccak)
  - "Lootbox RNG uses index advance isolation instead of rngLockedFlag" (re-justified Phase 239)

### Prior-milestone artifacts — CROSS-CHECK ONLY (D-07), NOT RELIED UPON
- `.planning/milestones/v29.0-phases/235-conservation-rng-commitment-re-proof-phase-transition/` — Plans 03-04 for post-hoc reconciliation only; D-07/D-08 per-site backward-trace + commitment-window patterns inform row granularity (already applied as D-01)
- `.planning/milestones/v29.0-phases/230-delta-extraction-scope-map/230-01-DELTA-MAP.md` — single-file catalog format precedent (D-05, D-08, D-11) applied as D-08/D-09/D-10
- `audit/FINDINGS-v29.0.md` — F-29-03, F-29-04 context for exception taxonomy
- `audit/FINDINGS-v25.0.md` — v25.0 RNG fresh-eyes sweep row list for reconciliation
- Any v3.7 / v3.8 VRF path audit artifacts present in archived milestone phases — reconciliation only

### Project feedback rules (apply across all plans)
- `memory/feedback_no_contract_commits.md` — READ-only scope enforcement, no `contracts/` or `test/` writes without explicit approval
- `memory/feedback_rng_backward_trace.md` — backward-trace methodology (inherited scope definition for Phase 238)
- `memory/feedback_rng_commitment_window.md` — commitment-window methodology (inherited scope definition for Phase 238)
- `memory/feedback_contract_locations.md` — `contracts/` is the only authoritative source; stale copies elsewhere are ignored

### In-scope contract tree (`contracts/`) — HEAD `7ab515fe`
- Top-level: `DegenerusGame.sol`, `DegenerusJackpots.sol`, `DegenerusQuests.sol`, `DegenerusAffiliate.sol`, `DegenerusAdmin.sol`, `DegenerusStonk.sol`, `StakedDegenerusStonk.sol`, `DegenerusVault.sol`, `DegenerusDeityPass.sol`, `DegenerusTraitUtils.sol`, `DeityBoonViewer.sol`, `BurnieCoin.sol`, `BurnieCoinflip.sol`, `GNRUS.sol`, `Icons32Data.sol`, `WrappedWrappedXRP.sol`, `ContractAddresses.sol`
- `contracts/modules/` (11): `DegenerusGameAdvanceModule.sol`, `DegenerusGameBoonModule.sol`, `DegenerusGameDecimatorModule.sol`, `DegenerusGameDegeneretteModule.sol`, `DegenerusGameGameOverModule.sol`, `DegenerusGameJackpotModule.sol`, `DegenerusGameLootboxModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameMintStreakUtils.sol`, `DegenerusGamePayoutUtils.sol`, `DegenerusGameWhaleModule.sol`
- `contracts/libraries/` (5): `BitPackingLib.sol`, `EntropyLib.sol`, `GameTimeLib.sol`, `JackpotBucketLib.sol`, `PriceLookupLib.sol`
- `contracts/interfaces/`, `contracts/storage/`, `contracts/mocks/` — read for interface-drift and storage-layout context only; `mocks/` is out-of-scope for consumer inventory (production contracts only)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **Phase 230 `230-01-DELTA-MAP.md` catalog format** — single-file tabular structure with Consumer Index at end; directly reusable pattern for `audit/v30-CONSUMER-INVENTORY.md`
- **Phase 235 D-07 per-site-row convention** — every consumption site gets its own row; already locked as D-01
- **Existing `audit/` deliverables** — `STORAGE-WRITE-MAP.md`, `ETH-FLOW-MAP.md`, `ACCESS-CONTROL-MATRIX.md`, `FINDINGS-v*.md` — provide file-format precedent; `v30-*` namespace is fresh for this milestone

### Established Patterns
- **HEAD anchor in plan frontmatter** — Phase 230 D-06 / Phase 235 D-05; already applied as D-17
- **READ-only scope on audit milestones** — v28/v29 pattern; already applied as D-18
- **No finding-ID emission in enumeration phases** — Phase 230 / 235 pattern; already applied as D-15
- **Scope-guard deferral rule** — downstream phases record deferrals instead of editing prior-phase output; already applied as D-16
- **Two-pass fresh-eyes + reconciliation** — same structure as v25.0 Phase 215 D-03 + Phase 216 D-01 ("fresh from scratch" then cross-cite); applied as D-07

### Integration Points
- `audit/v30-CONSUMER-INVENTORY.md` is the scope anchor for Phase 238 (BWD/FWD proofs — per row), Phase 239 (RNG invariant — rows used for permissionless sweep classification), Phase 240 (GO-01 consumer inventory — gameover rows subset), Phase 241 (EXC-01..04 — subcategory-flagged rows), Phase 242 (regression + consolidation — all rows)
- Row IDs flow as stable citations into `audit/v30-FREEZE-PROOF.md` (Phase 238), `audit/v30-RNGLOCK-STATE-MACHINE.md` + `audit/v30-PERMISSIONLESS-SWEEP.md` (Phase 239), `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` (Phase 240), `audit/v30-EXCEPTION-CLOSURE.md` (Phase 241), `audit/FINDINGS-v30.0.md` (Phase 242)
- KI cross-ref column in every inventory row provides Phase 241 (EXC-01..04) its direct evidence lookup

</code_context>

<specifics>
## Specific Ideas

- **Row ID format suggestion:** `INV-237-NNN` (zero-padded three-digit index, e.g., `INV-237-001`) for stable, greppable citations across Phases 238-242. Planner's final call.
- **Reconciliation table is part of Plan 01's deliverable, not a separate file** — it is how fresh-eyes is proven to be fresh-eyes (a fresh list that matches priors without having seen them is stronger evidence than one that copied them).
- **KNOWN-ISSUES entries get cited by exact quoted header** — avoids drift if KNOWN-ISSUES sections are later reorganized.

</specifics>

<deferred>
## Deferred Ideas

- **Row-count ceiling / floor enforcement** — auto-decide did not set a hard bound. If Plan 01's fresh pass produces a row count that diverges wildly from the v29.0 Phase 235 list (e.g., 2× or 0.5×), the reconciliation section should investigate — but the enforcement threshold is planner-discretion, not locked here.
- **Cross-cycle VRF chaining audit** (one-VRF-word seeds entropy for multiple dependent consumers across days) — out of this phase's INV-03 call-graph depth (which stops at consumption site). If pertinent, Phase 238 FWD-01/02 surfaces it as a forward-mutation question. Noted here so it isn't forgotten.
- **Automated invariant runner against inventory rows** — converting the inventory into a Foundry/Halmos-queryable format. Out of v30.0 scope (READ-only, no test writes). Flag as future-milestone candidate.

</deferred>

---

*Phase: 237-vrf-consumer-inventory-call-graph*
*Context gathered: 2026-04-18*
