# Phase 263: Per-Pull Level Resample Implementation - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-09
**Phase:** 263-per-pull-level-resample-implementation
**Areas discussed:** `_randTraitTicket` refactor strategy, `DailyWinningTraits.bonusTargetLevel` semantic, `_awardDailyCoinToTraitWinners` helper shape

---

## Gray-Area Selection (multi-select)

| Option | Description | Selected |
|--------|-------------|----------|
| `_randTraitTicket` refactor strategy | How to land the new salt scheme `keccak256(randomWord, trait, lvl, i)` without breaking SURF-01 byte-identity for the 4 other callers. | ✓ |
| `DailyWinningTraits.bonusTargetLevel` semantic | What the L520 / L538 / L1756 pre-announcement field means under per-pull resample (AUDIT-06 only flags `JackpotBurnieWin.lvl`; this field is not named in REQUIREMENTS.md). | ✓ |
| `_awardDailyCoinToTraitWinners` helper shape | Keep the helper with new signature (`minLevel, maxLevel, ..., randomWord`) vs. inline the loop at both callsites vs. extract a wider struct-based helper. | ✓ |
| Phase 263 test scope (deterministic unit tests vs defer to Phase 264) | ROADMAP success criterion #5 makes the unit-test plan explicitly optional; Phase 264 covers chi² + statistical validation. | |

---

## `_randTraitTicket` refactor strategy

| Option | Description | Selected |
|--------|-------------|----------|
| Inline holder-index logic directly in the new loop body | Leave `_randTraitTicket` (L1653-1703) completely untouched (zero risk to L700/L989/L1296/L1399 callers — SURF-01 byte-identity proven by trivial `git diff`). Inline ~10 lines of holder-index logic at the new flat-50 loop body, reusing `deityCache[i % 4]` to eliminate redundant SLOAD per pull. | ✓ |
| New sibling helper `_randTraitTicketLvl(... lvl, deity ...)` | Add a new private view helper alongside `_randTraitTicket` taking pre-cached `deity` and `lvl`; other callers still call original `_randTraitTicket` (signature unchanged). Pro: keeps holder-index logic in one named helper. Con: two helpers with ~70% body overlap. | |

**User's choice:** Inline holder-index logic directly in the new loop body.
**Notes:** Captured in CONTEXT.md as **D-IMPL-01**. Inline body uses `deityCache[i % 4]` (PPL-06 cache reuse), salt scheme `keccak256(randomWord, trait_i, lvlPrime, i)` (PPL-07), silent skip on `effectiveLen == 0` (PPL-05). The seed note's "or its inlined replacement" wording at `.planning/notes/2026-05-08-burnie-near-future-per-pull-level.md:70` explicitly blesses this strategy.

---

## `DailyWinningTraits.bonusTargetLevel` semantic

| Option | Description | Selected |
|--------|-------------|----------|
| Keep current emit value, expand AUDIT-06 to flag the field | L520 / L538 / L1756 keep emitting `bonusTargetLevel = lvl + 1 + uint24(coinEntropy % 4)` byte-identically. AUDIT-06 in REQUIREMENTS.md (and in `audit/FINDINGS-v35.0.md` §3) widened to disclose: "advisory, not authoritative — actual per-win lvl values come from `JackpotBurnieWin.lvl` events." Indexer team flagged for both fields together. Zero contract diff at the emit sites. | ✓ |
| Emit sentinel 0 (or `type(uint24).max`) for `bonusTargetLevel` | Event ABI byte-identical, but the field carries a sentinel value when per-pull resample applies. Cleaner on-chain signal but requires emit-site code changes and saves only the L519/L537 keccak+modulo (small gas win). | |
| Defer the `bonusTargetLevel` question to Phase 265 audit | Phase 263 ships the per-pull loop with NO change to L520 / L538 / L1756; Phase 265 decides during findings consolidation whether to widen disclosure. Lowest-risk Phase 263 scope but defers the indexer-team conversation. | |

**User's choice:** Keep current emit value, expand AUDIT-06 to flag the field.
**Notes:** Captured in CONTEXT.md as **D-INDEXER-01** (zero-diff on emit sites) and **D-AUDIT06-AMEND-01** (REQUIREMENTS.md AUDIT-06 wording widened in this phase's batched diff to flag BOTH `JackpotBurnieWin.lvl` AND `DailyWinningTraits.bonusTargetLevel`). Mirrors the Phase 260 D-13/D-14 spec-amendment landing pattern (REQUIREMENTS.md edit lands alongside the implementation it describes). Indexer team flagged for BOTH fields at v35.0 kickoff.

---

## `_awardDailyCoinToTraitWinners` helper shape

| Option | Description | Selected |
|--------|-------------|----------|
| Keep helper, change signature to `(minLevel, maxLevel, winningTraitsPacked, coinBudget, randomWord)` | Single shared body called from both L626 (`lvl + 1, lvl + 4, ...`) and L1736 (`minLevel, maxLevel, ...`). One auditable body. Old `(uint24 lvl, ..., uint256 entropy)` signature replaced atomically (no compatibility shim per `feedback_no_dead_guards.md`). | ✓ (Recommended) |
| Inline the loop at both callsites, remove the helper | Each callsite carries a full inline copy. Pro: self-contained. Con: ~50 lines duplicated; "structurally-identical" claim must be proven by external grep/diff at audit time; SURF-05 gas analysis must account for two copies in bytecode. | |

**User's choice:** Keep helper, change signature.
**Notes:** Captured in CONTEXT.md as **D-SHAPE-01** through **D-SHAPE-06**. Per-trait deity-cache block at top of helper body (D-SHAPE-02); share-math byte-identical (D-SHAPE-03 — `cursor = randomWord % cap` replaces prior `entropy % cap`); per-pull `lvlPrime` formula uses `range = maxLevel - minLevel + 1` (D-SHAPE-04, handles `range == 1` purchase-phase corner without special-casing); new `COIN_LEVEL_TAG` constant adjacent to `COIN_JACKPOT_TAG` at L166 (D-SHAPE-05); dead-derivation cleanup at L621-623 + L1729-1731 (D-SHAPE-06).

---

## Claude's Discretion

- **Phase 263 unit-test scope** — defaulted to defer all test work to Phase 264. Rationale: (a) Phase 264 STAT-01..04 + SURF-01..05 already cover chi² + cross-surface + gas; (b) success criterion #5 in ROADMAP §"Phase 263" makes the unit-test plan explicitly optional; (c) a fixed-seed Phase 263 unit test would partially overlap Phase 264 STAT fixtures. Planner may override and land a minimal fixed-seed regression (~50 LOC) if it meaningfully reduces Phase 264 surface area; default = no Phase 263 test plan.
- **Helper body micro-shape** — Loop-body local naming (`lvlPrime` vs `sampledLvl`, `trait_i` vs `traitIdx`, `effectiveLen` vs `eligibleLen`); canonical names in CONTEXT.md `<specifics>` are reviewer-facing defaults, not locked.
- **Constant naming** — `COIN_LEVEL_TAG` is the working name; planner may rename if a stronger convention exists.
- **Dead-derivation cleanup scope** — D-SHAPE-06 expects the L621-623 and L1729-1731 `coinEntropy` derivations to become dead. If the planner finds they're still referenced elsewhere, the cleanup is dropped silently.
- **REQUIREMENTS.md AUDIT-06 final wording** — D-AUDIT06-AMEND-01 captures the SEMANTIC widening (both events flagged together); planner picks final prose. Reviewer-facing draft provided in CONTEXT.md `<specifics>`.
- **Plan slicing** — Defer to planner per **D-PLAN-01** (mirrors Phase 260 D-12). Reference shape: single plan covering helper rewrite + two callsite updates + REQUIREMENTS.md amendment, all in one commit per the roadmap's atomicity anchor.

## Deferred Ideas

- **Phase 263 deterministic unit-test plan** — defaulted DEFERRED to Phase 264.
- **`DAILY_COIN_SALT_BASE = 252` constant cleanup** — verify zero-references after rewrite; remove if dead per `feedback_no_dead_guards.md`.
- **Phase 261 chi² infrastructure reuse decision** — captured as STAT-04 / D-NN-INFRA-01 in Phase 264 (default = REUSE).
- **`_randTraitTicket` other-caller refactor** — out of scope per SURF-01; any future cleanup of the `salt` parameter belongs in v36+.
- **Indexer team kickoff communication for AUDIT-06 widening** — operational task at v35.0 milestone start; not a phase deliverable.
- **`_distributeTicketJackpot` per-pull resample** — out of milestone scope.
- **Far-future BURNIE coin jackpot audit re-verification** — Phase 265 REG-03 + Phase 264 SURF-02.
- **Gas regression test (~70K–110K extra envelope)** — Phase 264 SURF-05; worst case derived FIRST per `feedback_gas_worst_case.md`.
