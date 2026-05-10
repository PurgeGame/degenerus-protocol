# Phase 263: Per-Pull Level Resample Implementation - Context

**Gathered:** 2026-05-09
**Status:** Ready for planning

<domain>
## Phase Boundary

`contracts/modules/DegenerusGameJackpotModule.sol` ships two structurally-identical flat-50 loops at `payDailyCoinJackpot` (purchase phase, ~L1713) and `payDailyJackpotCoinAndTickets` (jackpot phase, ~L593) where each pull samples its own random level via `keccak256(randomWord, COIN_LEVEL_TAG, i) % range`, rotates trait deterministically via `trait_idx = i % 4`, reads holders from `traitBurnTicket[lvl'][trait_i]`, silently skips empty `(lvl', trait_i)` buckets, and emits `JackpotBurnieWin(winner, lvl', traitId, amount, ticketIndex)` with the per-pull `lvl'`. Per-trait deity addresses are cached at loop entry into `address[4] memory deityCache`; the holder-index keccak inside the loop body uses the new salt scheme `keccak256(randomWord, trait, lvl, i)` (legacy `salt` parameter dropped from this code path). `_computeBucketCounts` is no longer called on this path. The `_awardDailyCoinToTraitWinners` helper signature changes to `(uint24 minLevel, uint24 maxLevel, uint32 winningTraitsPacked, uint256 coinBudget, uint256 randomWord)` — single shared body called from both L626 (jackpot phase, `minLevel = lvl + 1`, `maxLevel = lvl + 4`) and L1736 (purchase phase, `minLevel`/`maxLevel` from outer caller). `_randTraitTicket` (L1653) is left COMPLETELY UNTOUCHED to preserve byte-identity for its 4 other callers (SURF-01).

In scope:
- Add `bytes32 private constant COIN_LEVEL_TAG = keccak256("coin-level")` (or equivalent) alongside existing `COIN_JACKPOT_TAG` (L166).
- Rewrite `_awardDailyCoinToTraitWinners` body to flat-50 loop with per-pull level sampling, `i % 4` trait rotation, per-trait `deityCache`, inline holder-index keccak (new salt scheme), silent empty-bucket skip, preserved `coinBudget / cap` + `coinBudget % cap` cursor remainder share-math.
- Change helper signature to `(uint24 minLevel, uint24 maxLevel, uint32 winningTraitsPacked, uint256 coinBudget, uint256 randomWord)`.
- Update L626 callsite in `payDailyJackpotCoinAndTickets`: drop `coinEntropy`/`targetLevel` derivation; call helper with `(lvl + 1, lvl + 4, bonusTraitsPacked, nearBudget, randWord)`.
- Update L1736 callsite in `payDailyCoinJackpot`: drop `entropy`/`targetLevel` derivation; call helper with `(minLevel, maxLevel, bonusTraitsPacked, nearBudget, randWord)`.
- Remove the `coinEntropy`/`COIN_JACKPOT_TAG` derivations at L621-623 + L1729-1731 if no other consumer remains (verify); keep `COIN_JACKPOT_TAG` constant if the L518/L536 emit-block derivations still consume it.
- REQUIREMENTS.md amendment: AUDIT-06 widened to flag BOTH `JackpotBurnieWin.lvl` AND `DailyWinningTraits.bonusTargetLevel` semantic shift (D-AUDIT06-AMEND-01 below).

Out of scope (deferred to Phase 264 / 265 or out of milestone):
- `_randTraitTicket` body changes (left BYTE-IDENTICAL — SURF-01 trivial proof via `git diff`).
- L520 / L538 / L1756 `DailyWinningTraits` emit-site changes (BYTE-IDENTICAL bonusTargetLevel emit; semantic shift documented in AUDIT-06 widening).
- L518 / L536 `coinEntropy` derivations inside `payDailyJackpot` (untouched; they feed the BYTE-IDENTICAL bonusTargetLevel emit).
- Statistical chi² validation (per-pull level uniformity + per-trait share + empty-bucket skip rate measurement) — Phase 264 STAT-01..04.
- Cross-surface preservation tests (`_randTraitTicket` other callers, far-future BURNIE, ETH daily jackpot, ticket-distribution paths) — Phase 264 SURF-01..05.
- Gas regression (~70K–110K extra per call envelope) — Phase 264 SURF-05 (worst case derived FIRST per `feedback_gas_worst_case.md`, then tested).
- Deterministic Hardhat unit tests for the new loop — defaulted to deferred to Phase 264 per Claude's discretion (see decisions below); planner may revisit if a small fixed-seed regression is cheap to land in this phase.
- Adversarial sweep + findings consolidation (`audit/FINDINGS-v35.0.md`) — Phase 265 AUDIT-01..06 + REG-01..04.

</domain>

<decisions>
## Implementation Decisions

### `_randTraitTicket` Refactor Strategy
- **D-IMPL-01:** Inline the holder-index keccak + deity resolution directly inside the new flat-50 loop body. `_randTraitTicket` (L1653-1703) is left **completely untouched** — its 4 other callers (L700 lootbox, L989 / L1296 / L1399 ticket-jackpot) keep byte-identical bytecode and SURF-01 byte-identity is proven by trivial `git diff` (function definition unchanged + non-injection grep at the 4 caller lines unchanged). Deity SLOAD eliminated per pull via `deityCache[i % 4]` reuse (PPL-06 satisfied at the inline-block level). Selected over the sibling-helper option to avoid two helpers with ~70% body overlap and to keep the new salt scheme co-located with the loop that uses it. Reference shape (substituted into the helper body — see D-SHAPE-01 for the surrounding loop):
  ```solidity
  // Inside the per-pull loop body, after sampling lvl' and selecting trait_i:
  address[] storage holders = traitBurnTicket[lvlPrime][trait_i];
  uint256 len = holders.length;
  address deity = deityCache[i % 4];
  uint256 virtualCount;
  if (deity != address(0)) {
      virtualCount = len / 50;
      if (virtualCount < 2) virtualCount = 2;
  }
  uint256 effectiveLen = len + virtualCount;
  if (effectiveLen == 0) {
      // Silent skip per PPL-05; no carry-forward, no top-up.
      unchecked { ++i; ++cursor; if (cursor == cap) cursor = 0; }
      continue;
  }
  uint256 idx = uint256(keccak256(
      abi.encode(randomWord, trait_i, lvlPrime, i)
  )) % effectiveLen;
  address winner = idx < len ? holders[idx] : deity;
  uint256 ticketIdx = idx < len ? idx : type(uint256).max;
  ```

### `DailyWinningTraits.bonusTargetLevel` Semantic
- **D-INDEXER-01:** L520 / L538 / L1756 emit sites (and the L519/L537 `coinEntropy` + `bonusTargetLevel` derivations that feed L520/L538) remain **BYTE-IDENTICAL** to v34.0 baseline `6b63f6d4`. Zero contract diff at these emit-block sites. The `bonusTargetLevel = lvl + 1 + uint24(coinEntropy % 4)` formula keeps emitting a representative single-level anchor; under per-pull resample this anchor is no longer authoritative, but the field stays as an advisory pre-announcement for indexers.
- **D-AUDIT06-AMEND-01:** REQUIREMENTS.md AUDIT-06 wording is widened in this phase's batched diff to flag BOTH events: "Off-chain indexer documentation — `JackpotBurnieWin.lvl` AND `DailyWinningTraits.bonusTargetLevel` semantic shift (shared-call-level → per-pull-sampled-level for `JackpotBurnieWin.lvl`; representative single-level anchor → advisory non-authoritative pre-announcement for `DailyWinningTraits.bonusTargetLevel`) surfaced in §3 of `audit/FINDINGS-v35.0.md` and KNOWN-ISSUES.md per D-09 gating decision (default INFO unless gated upward)." Indexer team flagged for BOTH fields together at v35.0 kickoff. Mirrors the Phase 260 D-13/D-14 spec-amendment landing pattern (REQUIREMENTS.md edit lands alongside the implementation it describes).

### `_awardDailyCoinToTraitWinners` Helper Shape
- **D-SHAPE-01:** Keep the helper; rename signature to `_awardDailyCoinToTraitWinners(uint24 minLevel, uint24 maxLevel, uint32 winningTraitsPacked, uint256 coinBudget, uint256 randomWord) private`. Single shared body called from both L626 (jackpot phase: `_awardDailyCoinToTraitWinners(lvl + 1, lvl + 4, bonusTraitsPacked, nearBudget, randWord)`) and L1736 (purchase phase: `_awardDailyCoinToTraitWinners(minLevel, maxLevel, bonusTraitsPacked, nearBudget, randWord)`). One auditable body, one place to verify the salt scheme and silent-skip logic. The old `(uint24 lvl, uint32 winningTraitsPacked, uint256 coinBudget, uint256 entropy)` signature is replaced atomically — no compatibility shim per `feedback_no_dead_guards.md`.
- **D-SHAPE-02:** Per-trait deity caching block lands at the top of the new helper body, before the per-pull loop. Cache shape: `address[4] memory deityCache;` populated by a 4-iter loop reading `deityBySymbol[(traitIds[t] >> 6) * 8 + (traitIds[t] & 0x07)]` (with `fullSymId < 32` guard preserved from `_randTraitTicket` L1673). Virtual-count math (`len/50`, min 2) recomputes per pull because `len = traitBurnTicket[lvl'][trait_i].length` varies per sampled level (PPL-06).
- **D-SHAPE-03:** The flat-50 loop preserves the existing `coinBudget / cap` per-winner amount with `coinBudget % cap` cursor remainder distribution (PPL-04 byte-identical at the share-math layer). `cursor = randomWord % cap` initial seed (replaces the prior `entropy % cap` — semantically equivalent, just sourced from `randomWord` instead of the dropped `coinEntropy`). On empty-bucket silent skip the cursor still advances (the `+1` extra for that cursor slot is structurally lost — accepted underspend per PPL-05).
- **D-SHAPE-04:** Per-pull `lvl'` formula:
  ```solidity
  uint24 range = maxLevel - minLevel + 1;
  // ... inside loop ...
  uint24 lvlPrime = minLevel + uint24(uint256(keccak256(
      abi.encode(randomWord, COIN_LEVEL_TAG, i)
  )) % range);
  ```
  When `minLevel == maxLevel` (range == 1), `lvlPrime` collapses to `minLevel` for every pull — no special-case branch needed (the modulo handles it). Note that the jackpot-phase callsite (L626) always has `range == 4`; only the purchase-phase callsite (L1736) can have `range == 1`.
- **D-SHAPE-05:** Add `bytes32 private constant COIN_LEVEL_TAG = keccak256("coin-level");` adjacent to existing `COIN_JACKPOT_TAG` declaration at L166. Distinct tag from `COIN_JACKPOT_TAG` so a `(randomWord, COIN_JACKPOT_TAG, i)` keccak (still produced by the L518/L536 emit-block derivations) cannot collide with any `(randomWord, COIN_LEVEL_TAG, i)` keccak from the new loop.
- **D-SHAPE-06:** Verify whether `coinEntropy` / `COIN_JACKPOT_TAG` derivations at L621-623 and L1729-1731 still have any consumer after the helper-callsite rewrite. Expected outcome: those derivations become dead at L621-623 + L1729-1731 (the `coinEntropy` local was previously passed into the helper's old `entropy` parameter; the new helper takes `randomWord` directly). Remove the dead derivations per `feedback_no_dead_guards.md`. The L518/L536 derivations inside `payDailyJackpot` remain — they feed the BYTE-IDENTICAL `bonusTargetLevel` emit. `COIN_JACKPOT_TAG` constant stays declared (still referenced by L518/L536).

### Approval & Commit Posture (carried forward)
- **D-APPROVAL-01:** All `contracts/` and `test/` edits in this phase are batched and presented as one diff at the end of the phase per `feedback_batch_contract_approval.md`; user approval is explicit per commit (no orchestrator pre-approval) per `feedback_no_contract_commits.md` and `feedback_never_preapprove_contracts.md`. Roadmap's "Single batched contract diff" anchor for Phase 263 is satisfied by this discipline.
- **D-APPROVAL-02:** Skip research-agent dispatch per `feedback_skip_research_test_phases.md` — phase is fully specified in REQUIREMENTS.md (PPL-01..08) and the seed note (`.planning/notes/2026-05-08-burnie-near-future-per-pull-level.md`) with exact line numbers, exact salt scheme, exact share-math, and exact silent-skip semantics. Plan directly. Mirrors Phase 259 D-11 + Phase 260 D-11 mechanical-phase posture.
- **D-APPROVAL-03:** No history comments per `feedback_no_history_in_comments.md`. The header comment block above `_awardDailyCoinToTraitWinners` (and above the two callsites) describes the per-pull-resample behavior as what IS — no "previously was" / "changed from" / "v34.0 used to". `_computeBucketCounts` is described as "not called from this path" in its own header (not as "removed for this path") since the helper itself stays for the lootbox L914 caller.
- **D-APPROVAL-04:** No dead guards per `feedback_no_dead_guards.md`. The silent-skip path inside the loop body has no `else { revert }` or unreachable safety branch — empty bucket is a valid, accepted outcome.

### Plan Slicing
- **D-PLAN-01:** Defer plan slicing decision to the planner (mirrors Phase 260 D-12). Reference shape: P1 = constant addition + helper rewrite + L626 / L1736 callsite updates + dead-derivation removal + REQUIREMENTS.md AUDIT-06 amendment, all in one commit (the two callsites and helper body MUST land atomically per the roadmap's "Single batched contract diff" anchor — partial landing breaks the salt scheme). Single-plan packing is the natural shape; multi-plan acceptable only if every plan's commits stay co-batched at the end-of-phase approval gate.

### Claude's Discretion
- **Phase 263 unit-test scope** — Defaulted to **defer all test work to Phase 264** (matches the seed-note implicit position and Phase 264 STAT/SURF requirements). Rationale: (a) Phase 264 already covers chi² + cross-surface + gas regression with `test/stat/` infra; (b) a deterministic fixed-seed unit test in Phase 263 would partially overlap STAT-01 / STAT-02 fixtures; (c) success criterion #5 in ROADMAP §"Phase 263" makes the unit-test plan EXPLICITLY OPTIONAL ("if Phase 263 lands its own unit-test plan, those tests are green"). Planner may override and land a minimal fixed-seed regression if it's cheap (~50 LOC) and meaningfully reduces Phase 264 surface area; default = no Phase 263 test plan.
- **Helper body micro-shape** — Loop-body local naming (`lvlPrime` vs `sampledLvl`, `trait_i` vs `traitIdx`, `effectiveLen` vs `eligibleLen`); the canonical names from D-IMPL-01's reference snippet are reviewer-facing defaults, not locked.
- **Constant naming** — `COIN_LEVEL_TAG` is the working name (mirrors `COIN_JACKPOT_TAG` / `FAR_FUTURE_COIN_TAG` style). Planner may rename if a stronger convention exists at adjacent declaration sites; semantics locked.
- **Dead-derivation cleanup scope** — D-SHAPE-06 expects the L621-623 and L1729-1731 `coinEntropy` derivations to become dead. If the planner finds they're still referenced elsewhere (e.g., by future commits not in scope), the cleanup is dropped silently (no commented-out leave-behind).
- **REQUIREMENTS.md AUDIT-06 wording** — exact prose of the widened AUDIT-06 text is reviewer-facing; D-AUDIT06-AMEND-01 captures the SEMANTIC widening (both events flagged together). Planner picks final wording.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements & roadmap
- `.planning/REQUIREMENTS.md` — PPL-01..08 (per-pull level sampling formula, flat-50 loop, deterministic trait rotation, share-math preservation, empty-bucket silent skip, per-trait deity caching, salt scheme, `JackpotBurnieWin.lvl` semantic shift) + AUDIT-06 (off-chain indexer documentation — **NOTE D-AUDIT06-AMEND-01 widening above; AUDIT-06 wording is amended in this phase's batched diff to flag BOTH `JackpotBurnieWin.lvl` AND `DailyWinningTraits.bonusTargetLevel`**) + SURF-01 (`_randTraitTicket` byte-identity for other callers — left UNTOUCHED per D-IMPL-01) + the v35.0 milestone scope/baseline anchors. Locked source of truth.
- `.planning/ROADMAP.md` §"Phase 263: Per-Pull Level Resample Implementation" — Goal statement, Success Criteria 1-5, Depends-on (none — first impl phase; baseline v34.0 source-tree HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`), atomicity note ("Single batched contract diff per `feedback_batch_contract_approval.md` (two call sites are tightly coupled; partial landing breaks the salt scheme)").
- `.planning/notes/2026-05-08-burnie-near-future-per-pull-level.md` — **Seed note with all locked decisions** (empty-bucket semantics, flat-50 loop with deterministic trait rotation, deity caching, salt scheme `keccak256(randomWord, trait, lvl, i)` with `salt` parameter dropped, gas budget envelope ~70K–110K, indexer flag for `JackpotBurnieWin.lvl`). The phrase "or its inlined replacement" at L70 explicitly blesses the D-IMPL-01 inline strategy.

### Contracts under change
- `contracts/modules/DegenerusGameJackpotModule.sol` — Module being modified (helper signature change + body rewrite + L626 + L1736 callsite updates + new `COIN_LEVEL_TAG` constant + dead-derivation cleanup at L621-623 + L1729-1731). Production v34.0 baseline at HEAD `6b63f6d4daf346a53a1d463790f637308ea8d555`.

### Surfaces preserved (byte-identical, no edits)
- `contracts/modules/DegenerusGameJackpotModule.sol:1653-1703` — `_randTraitTicket` body LEFT UNTOUCHED per D-IMPL-01. SURF-01 byte-identity proven by trivial `git diff` of the function block.
- `contracts/modules/DegenerusGameJackpotModule.sol:518-520, 536-538, 1750-1756` — `DailyWinningTraits` emit blocks BYTE-IDENTICAL per D-INDEXER-01. The `bonusTargetLevel = lvl + 1 + uint24(coinEntropy % 4)` formula at L519 / L537 keeps emitting; semantic shift handled by AUDIT-06 widening, not by code change.
- `contracts/modules/DegenerusGameJackpotModule.sol:282, 349, 524, 1147` — v34.0 `_pickSoloQuadrant` injection sites (ETH daily jackpot) BYTE-IDENTICAL per SURF-03 (out of scope).
- `contracts/modules/DegenerusGameJackpotModule.sol:1839+` — `_awardFarFutureCoinJackpot` BYTE-IDENTICAL per SURF-02 (out of scope; already samples per-pull random level upstream).
- `contracts/modules/DegenerusGameJackpotModule.sol:_distributeTicketJackpot` — BYTE-IDENTICAL per SURF-04 (out of scope).
- `contracts/modules/DegenerusGameJackpotModule.sol:_computeBucketCounts` (L1030) — function body UNCHANGED. Still consumed by `_distributeLootboxAndTickets` (L914) and other lootbox/ticket paths. Only the call from `_awardDailyCoinToTraitWinners` is removed (the helper rewrite drops it from the new loop body).
- `contracts/libraries/JackpotBucketLib.sol` — UNCHANGED.
- `contracts/libraries/EntropyLib.sol` — UNCHANGED. (KI EXC-04 EntropyLib XOR-shift gets explicit attention in Phase 265 REG-03 because the new per-pull-level keccak `keccak256(randomWord, COIN_LEVEL_TAG, i) % range` consumes high-entropy bits — Phase 264 STAT-01 chi² covers the uniformity claim end-to-end.)

### Caller surfaces (no change required)
- `contracts/modules/DegenerusGameAdvanceModule.sol` — calls `payDailyCoinJackpot` and `payDailyJackpotCoinAndTickets`. Public function signatures preserved; per-pull-resample is internal to the jackpot module. No edits.

### Memory / feedback governing this phase
- `feedback_no_contract_commits.md` — explicit per-commit user approval for all `contracts/` + `test/` changes (D-APPROVAL-01).
- `feedback_batch_contract_approval.md` — batch all phase edits, present one diff at the end (D-APPROVAL-01). Roadmap's atomicity anchor for the two-callsite refactor.
- `feedback_never_preapprove_contracts.md` — orchestrator must NOT tell agents anything is pre-approved (D-APPROVAL-01).
- `feedback_no_history_in_comments.md` — comments describe what IS; no "previously was" or "changed from" in the new helper / callsite blocks (D-APPROVAL-03).
- `feedback_no_dead_guards.md` — no unreachable safety branches in the silent-skip path; no compatibility shim on the helper signature change (D-APPROVAL-04 + D-SHAPE-01).
- `feedback_skip_research_test_phases.md` — skip research-agent dispatch for mechanical phases (D-APPROVAL-02).
- `feedback_wait_for_approval.md` — present fix and wait for explicit approval before editing.
- `feedback_manual_review_before_push.md` — never push contract changes without diff review.
- `feedback_rng_backward_trace.md` — Phase 265 RNG audit will trace backward from each consumer (`JackpotBurnieWin.winner` from the loop body) to verify each keccak input was unknown at VRF commitment time. Inputs: `randomWord` (post-VRF-fulfillment), `trait_i` (from `_rollWinningTraits(randWord, true)` — same VRF-fulfillment commitment), `lvlPrime` (derived from `randomWord` keccak), `i` (loop index, deterministic).
- `feedback_rng_commitment_window.md` — Phase 265 will check what player-controllable state can change between VRF request and fulfillment for the new consumer. The new keccak inputs all derive from VRF-fulfillment objects; no new player-controllable input introduced (matches v34.0 commitment window for this code path).
- `feedback_gas_worst_case.md` — Phase 264 SURF-05 worst-case 4-gold gas analysis derived FIRST, then tested. Phase 263 itself does not run gas tests; the helper rewrite cost envelope is bounded by the seed-note budget (~70K–110K extra per call).

### Prior-phase context
- `.planning/milestones/v34.0-phases/259-trait-distribution-split/259-CONTEXT.md` — Phase 259 introduced color==7 (gold) tier and the `traitFromWord` / `packedTraitsFromSeed` byte-stable signatures consumed by `_rollWinningTraits` (still consumed unchanged here).
- `.planning/milestones/v34.0-phases/260-gold-solo-priority-injection/260-CONTEXT.md` — Phase 260 introduced `_pickSoloQuadrant` + the 4 ETH-distribution `effectiveEntropy` injection sites (L282 / L349 / L524 / L1147). All BYTE-IDENTICAL in Phase 263 per SURF-03. Reference pattern for batched contract approval (D-10) + skip-research-for-mechanical-phase posture (D-11) + spec-amendments-land-with-implementation pattern (D-13/D-14, mirrored here as D-AUDIT06-AMEND-01).
- `.planning/milestones/v34.0-phases/261-statistical-validation-cross-surface-verification/261-CONTEXT.md` — Phase 261's chi²/Monte Carlo infrastructure (`test/stat/`) is reusable per the seed-note cross-milestone dependency note; Phase 264 STAT-04 confirms the reuse decision.

### Milestone & state
- `.planning/PROJECT.md` — v35.0 milestone goal and v34.0 source-tree HEAD anchor `6b63f6d4daf346a53a1d463790f637308ea8d555` (audit baseline).
- `.planning/STATE.md` — current focus (planning Phase 263).
- `KNOWN-ISSUES.md` — EXC-04 EntropyLib XOR-shift envelope (Phase 265 REG-03 explicit-attention re-verification, cross-cited with Phase 264 STAT-01 chi² empirical evidence). Otherwise UNMODIFIED unless a Phase 265 D-09 gating decision promotes a candidate.

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_randTraitTicket` (L1653-1703)** — body kept BYTE-IDENTICAL per D-IMPL-01; serves as the reference shape for the inlined holder-index keccak block (the inline body in D-IMPL-01 mirrors L1664-1702 with three deltas: (1) `lvl` is the sampled `lvlPrime`, not a closure of the surrounding caller; (2) salt scheme is `keccak256(randomWord, trait, lvl, i)` not `keccak256(randomWord, trait, salt, i)`; (3) deity comes from pre-cached `deityCache[i % 4]`, not a per-call `deityBySymbol[fullSymId]` SLOAD).
- **`JackpotBucketLib.unpackWinningTraits(uint32) → uint8[4]`** — already used at L770 / L990 / L1297 / L1400 / L1770 etc. The new helper consumes it identically (`uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(winningTraitsPacked);`); no library change.
- **`COIN_JACKPOT_TAG` constant (L166)** — declaration kept; consumed by L518 / L536 emit-block derivations. The new path uses a sibling constant `COIN_LEVEL_TAG` (D-SHAPE-05) declared adjacent.
- **`DAILY_COIN_MAX_WINNERS = 50` (L224)** — preserved as the cap. The flat-50 loop iterates `for (uint256 i; i < cap; ++i)` with `cap = min(DAILY_COIN_MAX_WINNERS, coinBudget)`.
- **`DAILY_COIN_SALT_BASE = 252` (L227)** — becomes dead constant if no other caller references it. Verify during planning; if dead, remove per `feedback_no_dead_guards.md`. The legacy L1800 site (`uint8(DAILY_COIN_SALT_BASE + traitIdx)`) is the salt arg passed to `_randTraitTicket` from the OLD `_awardDailyCoinToTraitWinners` body — disappears with the helper rewrite. `_randTraitTicket` itself still has its `salt` parameter (other callers use it: L700 lootbox passes `25 + t`, etc.) so the constant declaration stays only if a non-rewritten caller still references it; expected outcome = constant becomes dead → remove.
- **`deityBySymbol` mapping (read at L1044, L1674)** — per-trait read in the new helper's deity-cache block at loop entry. PPL-06 caching reuses the cached value across all 50 pulls of that trait.
- **`coinflip.creditFlip(winner, amount)` (L1819)** — preserved at the per-pull emit-and-credit site.

### Established Patterns
- **Site-local block discipline** — Phase 260 D-08 canonical site-local block shape (`uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(...); uint256 entropy = EntropyLib.hash2(randWord, lvl); ...`) is the model for the L626 / L1736 callsite blocks here, simplified to the helper invocation: `_awardDailyCoinToTraitWinners(minLevel, maxLevel, bonusTraitsPacked, nearBudget, randWord);`.
- **Internal-pure / private helper convention** — `_awardDailyCoinToTraitWinners` stays `private`; no external test wrapper needed at Phase 263 scope (test work deferred to Phase 264; Phase 264 may add a `JackpotCoinPullTester.sol` analog to Phase 260's `JackpotSoloTester.sol` if the chi² infra needs an external entry point for fixed-randWord scenarios).
- **Empty-bucket silent-skip discipline** — matches the existing `if (effectiveLen == 0 || numWinners == 0) return (new address[](0), new uint256[](0));` pattern in `_randTraitTicket` L1682-1684 (single-pull early return). The new loop's `continue;` per pull is the multi-pull analog with no carry-forward.
- **Cursor remainder distribution** — preserves the existing L1804-1827 cursor pattern (`if (extra != 0 && cursor < extra) amount += 1; ... ++cursor; if (cursor == cap) cursor = 0;`) byte-identically at the share-math layer per PPL-04.
- **Tag constant convention** — `bytes32 private constant XYZ_TAG = keccak256("xyz-tag");` at the top-of-file constants block (L166-180 area). New `COIN_LEVEL_TAG` follows the same shape.

### Integration Points
- **L626 (`payDailyJackpotCoinAndTickets`)** — `randWord` is the VRF entropy; jackpot-phase always has `range == 4` (`minLevel = lvl + 1`, `maxLevel = lvl + 4`). The local `coinEntropy` derivation at L621-623 becomes dead (D-SHAPE-06); local `targetLevel` at L624 is removed; the helper invocation at L626 takes `randWord` directly. The `bonusTraitsPacked` local at L607 is reused unchanged. Surrounding ticket-distribution flow (L636-663) BYTE-IDENTICAL.
- **L1736 (`payDailyCoinJackpot`)** — `randWord` is the VRF entropy; purchase-phase has `range = maxLevel - minLevel + 1` (caller-determined). The local `entropy` derivation at L1729-1731 becomes dead (D-SHAPE-06); local `targetLevel` at L1732-1734 is removed; the helper invocation at L1736 takes `randWord` directly. Surrounding `coinBudget` / `farBudget` / `_awardFarFutureCoinJackpot` flow (L1714-1722) BYTE-IDENTICAL.
- **L1760-1834 (old `_awardDailyCoinToTraitWinners` body)** — entire body replaced. The function header comment is rewritten to describe the per-pull-resample behavior as what IS (no history-comment). The `_computeBucketCounts(lvl, traitIds, cap, entropy)` call at L1773-1778 disappears with the rewrite (call site removed; `_computeBucketCounts` itself stays for L914 lootbox caller).
- **`_randTraitTicket` (L1653-1703)** — UNTOUCHED. The 4 other callers (L700 lootbox, L989 / L1296 / L1399 ticket-jackpot) keep byte-identical bytecode. SURF-01 proven by `git diff` of the function block + grep at the 4 caller lines.
- **L518 / L536 / L1756 `DailyWinningTraits` emits** — UNTOUCHED. AUDIT-06 widening (D-AUDIT06-AMEND-01) is a REQUIREMENTS.md amendment, not a contract change.

</code_context>

<specifics>
## Specific Ideas

- **Helper body skeleton (locked semantics; planner picks final naming/style):**
  ```solidity
  /// @dev Awards BURNIE to per-pull random ticket holders across [minLevel, maxLevel].
  ///      Each pull samples its own random level; trait rotates deterministically i % 4.
  ///      Empty (lvl', trait_i) buckets silently skip (no carry-forward, no top-up).
  function _awardDailyCoinToTraitWinners(
      uint24 minLevel,
      uint24 maxLevel,
      uint32 winningTraitsPacked,
      uint256 coinBudget,
      uint256 randomWord
  ) private {
      if (coinBudget == 0) return;
      uint16 cap = DAILY_COIN_MAX_WINNERS;
      if (cap > coinBudget) cap = uint16(coinBudget);

      uint8[4] memory traitIds = JackpotBucketLib.unpackWinningTraits(winningTraitsPacked);

      // Per-trait deity cache (PPL-06). Eliminates redundant SLOAD per pull.
      address[4] memory deityCache;
      for (uint8 t; t < 4; ) {
          uint8 trait = traitIds[t];
          uint8 fullSymId = (trait >> 6) * 8 + (trait & 0x07);
          if (fullSymId < 32) {
              deityCache[t] = deityBySymbol[fullSymId];
          }
          unchecked { ++t; }
      }

      uint256 baseAmount = coinBudget / cap;
      uint256 extra = coinBudget % cap;
      uint256 cursor = randomWord % cap;
      uint24 range = maxLevel - minLevel + 1;

      for (uint256 i; i < cap; ) {
          uint8 traitIdx = uint8(i % 4);
          uint8 trait_i = traitIds[traitIdx];

          // Per-pull level sampling (PPL-01, PPL-02).
          uint24 lvlPrime = minLevel + uint24(uint256(keccak256(
              abi.encode(randomWord, COIN_LEVEL_TAG, i)
          )) % range);

          // Inline holder-index logic (D-IMPL-01) using cached deity (PPL-06).
          address[] storage holders = traitBurnTicket[lvlPrime][trait_i];
          uint256 len = holders.length;
          address deity = deityCache[traitIdx];
          uint256 virtualCount;
          if (deity != address(0)) {
              virtualCount = len / 50;
              if (virtualCount < 2) virtualCount = 2;
          }
          uint256 effectiveLen = len + virtualCount;
          if (effectiveLen == 0) {
              // Silent skip (PPL-05). Cursor advances; the +1 extra for this slot is structurally lost.
              unchecked { ++i; ++cursor; if (cursor == cap) cursor = 0; }
              continue;
          }

          // Salt scheme: keccak256(randomWord, trait, lvl, i) — drops legacy salt parameter (PPL-07).
          uint256 idx = uint256(keccak256(
              abi.encode(randomWord, trait_i, lvlPrime, i)
          )) % effectiveLen;
          address winner;
          uint256 ticketIdx;
          if (idx < len) {
              winner = holders[idx];
              ticketIdx = idx;
          } else {
              winner = deity;
              ticketIdx = type(uint256).max;
          }

          uint256 amount = baseAmount;
          if (extra != 0 && cursor < extra) {
              amount += 1;
          }

          if (winner != address(0) && amount != 0) {
              // PPL-08: lvl field reflects per-pull sampled level.
              emit JackpotBurnieWin(winner, lvlPrime, trait_i, amount, ticketIdx);
              coinflip.creditFlip(winner, amount);
          }

          unchecked { ++i; ++cursor; if (cursor == cap) cursor = 0; }
      }
  }
  ```
- **Constant addition (D-SHAPE-05):**
  ```solidity
  bytes32 private constant COIN_LEVEL_TAG = keccak256("coin-level");
  ```
  Adjacent to existing `bytes32 private constant COIN_JACKPOT_TAG = keccak256("coin-jackpot");` at L166.
- **L626 callsite shape:**
  ```solidity
  // --- Coin Jackpot ---
  uint256 coinBudget = _calcDailyCoinBudget(lvl);
  if (coinBudget != 0) {
      uint256 farBudget = (coinBudget * FAR_FUTURE_COIN_BPS) / 10_000;
      _awardFarFutureCoinJackpot(lvl, farBudget, randWord);

      uint256 nearBudget = coinBudget - farBudget;
      if (nearBudget != 0) {
          _awardDailyCoinToTraitWinners(
              lvl + 1,
              lvl + 4,
              bonusTraitsPacked,
              nearBudget,
              randWord
          );
      }
  }
  ```
- **L1736 callsite shape:**
  ```solidity
  uint32 bonusTraitsPacked = _rollWinningTraits(randWord, true);

  _awardDailyCoinToTraitWinners(
      minLevel,
      maxLevel,
      bonusTraitsPacked,
      nearBudget,
      randWord
  );
  ```
- **REQUIREMENTS.md AUDIT-06 amendment text (D-AUDIT06-AMEND-01) — reviewer-facing draft, planner picks final wording:**
  > **AUDIT-06**: Off-chain indexer documentation — `JackpotBurnieWin.lvl` AND `DailyWinningTraits.bonusTargetLevel` semantic shifts surfaced in §3 of FINDINGS-v35.0.md and KNOWN-ISSUES.md per D-09 gating decision (default INFO unless gated upward). `JackpotBurnieWin.lvl` shifts from shared-call-level to per-pull-sampled-level (~50 distinct values per call instead of 1). `DailyWinningTraits.bonusTargetLevel` shifts from authoritative single-level anchor to advisory non-authoritative pre-announcement (the `lvl + 1 + uint24(coinEntropy % 4)` formula keeps emitting byte-identically; downstream `payDailyJackpotCoinAndTickets` no longer targets that single level under per-pull resample).

</specifics>

<deferred>
## Deferred Ideas

- **Phase 263 deterministic unit-test plan** — defaulted DEFERRED to Phase 264 per Claude's discretion (above). Planner may revisit if a small fixed-seed regression (~50 LOC) meaningfully reduces Phase 264 surface area; default = no Phase 263 test plan, all test work in Phase 264.
- **`DAILY_COIN_SALT_BASE = 252` constant cleanup** — if the `_awardDailyCoinToTraitWinners` rewrite leaves this constant with zero remaining references in `contracts/`, remove per `feedback_no_dead_guards.md`. If any other caller still uses it (verify via grep during planning), keep. Carries forward to Phase 264 SURF-01 byte-identity verification (the constant appears in `_randTraitTicket` other callers' bytecode only via the `salt` arg they pass — those callers stay unchanged, so the constant declaration's removal does not change their bytecode).
- **Phase 261 chi² infrastructure reuse decision** — captured as STAT-04 / D-NN-INFRA-01 in Phase 264 (default branch = REUSE since seed-note assumption is reusable; planner extends with one new fixture if needed). Out of Phase 263 scope.
- **`_randTraitTicket` other-caller refactor** — explicitly out of scope per SURF-01 (Phase 264 verifies BYTE-IDENTICAL preservation). Any future cleanup of the `salt` parameter across all callers belongs in a v36+ refactor phase, not v35.0.
- **Indexer team kickoff communication for AUDIT-06 widening** — operational task at v35.0 milestone start (PROJECT.md anchor); not a phase deliverable. Phase 265 documents the surface in `audit/FINDINGS-v35.0.md`.
- **`_distributeTicketJackpot` per-pull resample** — out of milestone scope (REQUIREMENTS.md "Out of Scope" table). Future phase if ever scoped.
- **Far-future BURNIE coin jackpot audit re-verification** — Phase 265 REG-03 (KI envelope re-verifications); Phase 264 SURF-02 (byte-identity sweep). Out of Phase 263 scope.
- **Gas regression test (~70K–110K extra envelope)** — Phase 264 SURF-05; worst case derived FIRST per `feedback_gas_worst_case.md`, then tested. Phase 263 ships the helper rewrite without gas tests.

</deferred>

---

*Phase: 263-per-pull-level-resample-implementation*
*Context gathered: 2026-05-09*
