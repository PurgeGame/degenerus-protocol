# Phase 292: Hero-Override Weighted Roll (HRROLL) - Context

**Gathered:** 2026-05-17
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the deterministic `_topHeroSymbol(uint32 day)` hero-override selector with a weighted random roll `_rollHeroSymbol(uint32 day, uint256 entropy) private view returns (bool hasWinner, uint8 winQuadrant, uint8 winSymbol)` across all 32 `(quadrant, symbol)` slots in `dailyHeroWagers[day]`, consumed by `_applyHeroOverride` (`contracts/modules/DegenerusGameJackpotModule.sol:1594-1621`). Ship HRROLL-01..10 with **×1.5 leader-weight bonus** (D-42N-LEADER-BONUS-01), **no min-wager floor** (D-42N-FLOOR-01), scan-order-first tie-break (q ascending → s ascending matching v41 `_topHeroSymbol`), and zero storage / public-ABI changes. Preserves v41 Phase 288 `dailyIdx` structural anchor as the single-writer day key frozen across the rng-lock window (HRROLL-05 inherits). Single USER-APPROVED batched contract commit per `feedback_batch_contract_approval.md`; zero `test/` mutations (TST-HRROLL ships at Phase 293).

</domain>

<decisions>
## Implementation Decisions

### Bonus-vs-Regular Hero-Override Entropy
- **D-42N-BONUS-ENTROPY-01:** **Preserve v41 cross-bonus invariance.** `_rollHeroSymbol(dailyIdx, randWord_raw)` consumes the RAW VRF entropy (`randWord` as it arrives into `_rollWinningTraits` at L1934, BEFORE the `keccak256(randWord, BONUS_TRAITS_TAG)` re-tag at L1938 that produces local `r`). On jackpot days that trigger both regular AND bonus trait rolls, BOTH rolls land the same hero `(quadrant, symbol)` per day (different colors only, via the existing `r`-derived bits[`quadrant*3`] color path which already differs across regular/bonus in v41). Hero-symbol winner wins their forced symbol on both rolls — matches v41 mechanic invariant of "one hero override per jackpot day." **Why:** v41 `_topHeroSymbol(dailyIdx)` is entropy-independent (deterministic on day key); both regular and bonus paths already share the same `(q, s)` hero override per v41-close mechanic semantics. The user explicit intent at 2026-05-17 discussion is to preserve this per-day lock-in mechanic, NOT to treat every RNG consumer as an independent weighted roll. Divergent-entropy alternative (use local `r` post-bonus-tag) would have meant bonus and regular rolls land in DIFFERENT quadrants on the same jackpot day — a noticeable mechanic change that dilutes hero-symbol winner EV on days with bonus rolls. **How to apply:** Plan-phase MUST refactor `_applyHeroOverride` to accept both entropies — the existing `randomWord` parameter (which carries `r` for color sampling per L1607-1613) stays UNCHANGED for the color path; a new second parameter (e.g., `uint256 heroEntropy`) carries the raw `randWord` for `_rollHeroSymbol(dailyIdx, heroEntropy)`. Both `_rollWinningTraits` callsites at L1941 update to pass `(traits, r, randWord_raw)`. Color-path bits `quadrant*3` on `r` UNCHANGED; symbol-roll bits derived from `keccak256(abi.encode(heroEntropy, day))` per HRROLL-01. The non-collision attestation in D-42N-COLOR-ENTROPY-01 (color bits sourced from `r`, symbol bits sourced from `keccak(heroEntropy, day)` — orthogonal entropy domains) is satisfied by construction.

### Pass-2 Cache Strategy
- **D-42N-CACHE-01:** **Most-gas-efficient memory cache in pass 2; final shape decided at plan-phase via theoretical-first attestation.** Pass 1 SLOADs the 4 `dailyHeroWagers[day][q]` packed uint256 slots once + computes total + identifies leader `(maxAmount, leaderIdx)`. Pass 2 reads from a memory cache (no re-SLOAD) and walks the cumulative cursor against `pick`. The specific cache shape — flat `uint32[32]` indexed `q*8 + s`, `uint64[32]` for the leader-bonus-applied weights, or packed `uint256[4]` cache with SHR+AND extracts in the hot loop — is decided at plan-phase based on the theoretical-first gas comparison per `feedback_gas_worst_case.md`. **Why:** User explicit disposition 2026-05-17 was "do whatever is most gas efficient in the long run" — that's a planner-discretion answer under the theoretical-first framework. Re-SLOAD-without-cache is explicitly REJECTED — burns ~8.4K gas per call for no benefit, violates `feedback_no_dead_guards.md` (gas waste with no design value). Gas delta between the three cache shapes is sub-1K and depends on pass-2 early-exit behavior (cursor exits on average at iteration ~16/32); the planner runs the actual numbers in `292-01-MEASUREMENT.md` and locks the shape with justification. **How to apply:** Plan-phase produces `292-01-MEASUREMENT.md` with a three-shape gas comparison table (flat uint32 array vs uint64 weights array vs packed-uint256 cache) using theoretical-first methodology; selects lowest worst-case gas; commits the choice as the inner-loop reference shape; the executor implements verbatim. The HRROLL-08 worst-case gas attestation falls out of this comparison; the D-42N-GAS-01 acceptance threshold (see Claude's Discretion below) closes against the chosen shape's theoretical worst case.

### Claude's Discretion (planner & executor latitude)

The following gray areas were considered but NOT raised for user disposition — the planner resolves at plan-phase using established patterns and the locked decisions above without re-asking the user:

- **D-42N-GAS-01 acceptance threshold form.** Mirrors Phase 291 D-291-GAS-01 pattern: theoretical-first attestation lives in `292-01-MEASUREMENT.md` (worst-case gas derived analytically against v41 `_topHeroSymbol` baseline per `feedback_gas_worst_case.md`); hard runtime regression assertion is the responsibility of Phase 293 TST-HRROLL-06 per the roadmap. D-42N-GAS-01 locks the acceptance threshold value at plan-phase based on the theoretical comparison (expected ~+5-8K per the roadmap hint; the chosen D-42N-CACHE-01 shape determines the actual figure). The Phase 292 contract phase carries the theoretical-first attestation; the Phase 293 test phase carries the empirical regression assertion. If the theoretical worst case exceeds ~+10K, planner flags it as a checkpoint for user review before proceeding to the contract patch.

- **Plan-artifact sidecar shape.** Phase 290 pattern applies verbatim: `292-01-PLAN.md` (executable plan + task breakdown) + `292-01-DESIGN-INTENT-TRACE.md` (HRROLL-10 5-section trace per `feedback_design_intent_before_deletion.md` — (i) original deterministic `_topHeroSymbol` single-leader rationale + winner-takes-all design intent, (ii) leader-bonus magnitude trade-offs (×2 monopolization risk vs ×1.5 balanced vs no-bonus pure-proportional), (iii) sybil exposure trade-offs (no-floor simplicity vs floor anti-spam), (iv) RNG commitment-window backward-trace verification per `feedback_rng_commitment_window.md` + `feedback_rng_backward_trace.md`, (v) gas budget headroom + D-42N-CACHE-01 shape comparison) + `292-01-MEASUREMENT.md` (storage byte-identity attestation via `forge inspect storageLayout` diff; public ABI byte-identity via `forge inspect methodIdentifiers` diff; theoretical gas worst-case for the chosen cache shape; D-42N-COLOR-ENTROPY-01 non-collision attestation — color bits sourced from `r` vs symbol bits from `keccak(randWord_raw, day)`). All three sidecars AGENT-COMMITTED BEFORE the contract patch lands per `feedback_design_intent_before_deletion.md`. Single USER-APPROVED batched contract commit at phase close per `feedback_batch_contract_approval.md` + `feedback_never_preapprove_contracts.md` + `feedback_manual_review_before_push.md`.

- **HRROLL-04 callsite-scope verification.** Already verified during context-gathering scout: `_rollWinningTraits` (L1933-1943) receives `randWord` as its first parameter from 12 callsites (L285, 354, 520, 531, 538, 609, 610, 689, 1180, 1734, 1754, 1756); local `r` is the post-bonus-tag variant at L1938 for `isBonus = true`, else `r == randWord`. To implement D-42N-BONUS-ENTROPY-01, the executor plumbs raw `randWord` into `_applyHeroOverride` as a new parameter. Color path (L1607-1613) continues to read bits of the EXISTING `randomWord` parameter (which carries `r`) — verbatim v41 behavior preserved. Symbol-roll path consumes the new parameter. Both callsites of `_applyHeroOverride` (currently just L1941) update to pass `(traits, r, randWord)`.

- **`_topHeroSymbol` deletion posture.** Fully delete per `feedback_no_dead_guards.md` + `feedback_frozen_contracts_no_future_proofing.md` + `feedback_no_history_in_comments.md`. No `// @dev removed` marker, no deprecated stub. The function (L1625-1653) goes away entirely; the NatSpec comment block above it (L1623-1624) goes away with it. The `_applyHeroOverride` NatSpec at L1584-1593 gets updated to reflect the new weighted-roll mechanic (the existing wording about "top hero symbol" + the (CALL 1 / CALL 2) determinism note are no longer the relevant mechanic; the new NatSpec describes what IS — weighted roll across 32 slots with ×1.5 leader bonus, no floor, raw VRF entropy via `keccak(heroEntropy, day)`, dailyIdx as the frozen day-key carrier). No `feedback_no_history_in_comments.md` violation — the new comment describes current behavior only.

- **Pass-2 cursor walk implementation.** Cumulative-sum sweep: `cumulative += weight; if (idx == leaderIdx) cumulative += leaderBonus; if (cumulative > pick) return (true, uint8(idx >> 3), uint8(idx & 7));` — iterates idx = 0..31 in flat order matching q ascending → s ascending (q = idx / 8, s = idx % 8). Early-exit on first `cumulative > pick` match. Per D-42N-DETERMINISM-01, the exact ordering is locked: flat idx ascending = q ascending → s ascending, leader-bonus added at the leader's index (single-leader scan-order-first tie-break already captured in pass 1). Roadmap's "64-bit pick" wording reconciled: amounts are uint32 (max 4.29e9), max effectiveTotal across 32 slots with ×1.5 bonus ≈ 2.06e11 → fits in 64 bits with massive headroom; `pick = uint64(uint256(keccak256(abi.encode(heroEntropy, day))) % effectiveTotal)` produces a uniform 64-bit pick (truncation safe because effectiveTotal << 2^64; no modulo bias because effectiveTotal divides 2^256 with vanishing rounding).

- **Weight-arithmetic type widening.** Leader weight (`maxAmount + leaderBonus`) can be up to `1.5 × uint32.max ≈ 6.4e9` which exceeds uint32 (4.29e9) — implementer widens to uint64 in pass 1 + cache. effectiveTotal stored as uint64. Solidity 0.8+ checked arithmetic applies by default; no `unchecked` blocks needed except for loop-counter increments (idiomatic gas optimization, already pattern at L1644-1650 in v41 `_topHeroSymbol`).

- **D-42N-DETERMINISM-01 spec recording.** Plan-phase records in `292-01-DESIGN-INTENT-TRACE.md` §(v) the EXACT keccak input ordering (`abi.encode(heroEntropy, day)` — NOT `abi.encodePacked` to avoid type-coercion ambiguity), modulo source (`uint256(keccak) % effectiveTotal` then `uint64` truncate), cursor direction (flat idx ascending), leader-bonus application point (added to cumulative when `idx == leaderIdx`), tie-break on leader (scan-order-first via pass-1 `if (amount > maxAmount)` strict-greater — first-seen wins on ties).

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase Goal & Requirements
- `.planning/ROADMAP.md` — Phase 292 entry (success criteria 1-5; HRROLL-01..10 algorithm spec; ×1.5 leader bonus + no-floor + scan-order tie-break locks; storage/ABI byte-identity invariants; decision anchors D-42N-LEADER-BONUS-01 + D-42N-FLOOR-01 + D-42N-COLOR-ENTROPY-01 + D-42N-DETERMINISM-01 + D-42N-GAS-01 named)
- `.planning/REQUIREMENTS.md` lines 58-69 — HRROLL-01..10 detail (locked requirement set; do NOT expand scope); excluded list lines 15-18 (HRROLL min-wager floor + leader-bonus alternatives + storage/ABI excluded per user dispositions)
- `.planning/PROJECT.md` — v42.0 milestone goal + audit baseline `MILESTONE_V41_AT_HEAD_315978a0c18294e0d7fa5cd4cdfe7f8e5b9a95c4`
- `.planning/STATE.md` — phase 292 stopped_at marker + last_activity 2026-05-17

### Contract Source (load-bearing for the patch)
- `contracts/modules/DegenerusGameJackpotModule.sol:1594-1621` — `_applyHeroOverride` (callsite swap target; signature gains second entropy param for D-42N-BONUS-ENTROPY-01; color path L1607-1613 UNCHANGED)
- `contracts/modules/DegenerusGameJackpotModule.sol:1625-1653` — `_topHeroSymbol` (DELETE entirely per `feedback_no_dead_guards.md`)
- `contracts/modules/DegenerusGameJackpotModule.sol:1933-1943` — `_rollWinningTraits` (callsite at L1941 updates to pass raw `randWord` as third arg; 12 upstream callers of `_rollWinningTraits` UNCHANGED — `randWord` already in scope at every caller per scout verification)
- `contracts/modules/DegenerusGameDegeneretteModule.sol:484-501` — `placeDegeneretteBet` wager-time write to `dailyHeroWagers[dailyIdx][q]` (HRROLL-05 backward-trace start anchor — wager-amount commitment site)
- `contracts/storage/DegenerusGameStorage.sol:1478` — `dailyHeroWagers[uint32 => uint256[4]]` storage layout (HRROLL-06 byte-identity target; UNCHANGED)

### Sister Phase Artifacts (pattern reference)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-PLAN.md` — pattern for `292-01-PLAN.md` shape (executable plan + task breakdown + USER-APPROVED contract-commit gate at close)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-DESIGN-INTENT-TRACE.md` — pattern for `292-01-DESIGN-INTENT-TRACE.md` (HRROLL-10 5-section trace shape; AGENT-COMMITTED pre-patch gate per `feedback_design_intent_before_deletion.md`; planning-doc historical-rationale exemption noted at top)
- `.planning/phases/290-mint-batch-event-sig-cleanup-mintcln/290-01-MEASUREMENT.md` — pattern for `292-01-MEASUREMENT.md` (theoretical gas + storage byte-identity attestation + public ABI byte-identity attestation; sections numbered §2 storage / §3 gas / §4 selectors / §5 events-if-any / §6 callsite diff)
- `.planning/phases/291-mintcln-regression-fixture-tst-mintcln/291-CONTEXT.md` — D-291-GAS-01 pattern (theoretical-first attestation at contract phase; runtime regression assertion deferred to sister test phase) — directly mirrored for D-42N-GAS-01 at Phase 292 ↔ TST-HRROLL-06 at Phase 293

### Inherited Decision Anchors (carry-forward; do NOT re-derive)
- **v41 Phase 288 D-288-FIX-SHAPE-01** — `dailyIdx` structural anchor as single-writer day key frozen across rng-lock window (HRROLL-05 inherits)
- **v41 Phase 281 D-281-FIX-SHAPE-01** — owed-salt cross-call seed-separation pattern (referenced in HRROLL audit-story for RNG-consumer non-collision attestation per D-42N-COLOR-ENTROPY-01)
- **v40 D-40N-MINTBOOST-OUT-01** — UNCHANGED; HRROLL doesn't touch mint-boost path
- **v34 D-271-ADVERSARIAL-01 + D-271-ADVERSARIAL-03** — 3-skill PARALLEL adversarial spawn pattern (Phase 296 SWEEP will red-team HRROLL alongside MINTCLN + DPNERF)
- **v34 D-271-ADVERSARIAL-02** — `/degen-skeptic` OUT OF SCOPE (carry-forward to Phase 296)

### Audit Methodology Feedback (enforce at plan-phase)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_commitment_window.md` — HRROLL-05 backward-trace methodology (trace from `_rollHeroSymbol` consumer back to `placeDegeneretteBet` wager-time write; verify every input committed before VRF request)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_rng_backward_trace.md` — HRROLL-05 backward-trace methodology (every RNG audit traces BACKWARD from each consumer)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_gas_worst_case.md` — D-42N-GAS-01 theoretical-first methodology (derive theoretical worst case FIRST in `292-01-MEASUREMENT.md`; D-42N-CACHE-01 three-shape comparison uses this); empirical confirmation deferred to TST-HRROLL-06
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_design_intent_before_deletion.md` — HRROLL-10 5-section design-intent trace REQUIRED in `292-01-DESIGN-INTENT-TRACE.md` BEFORE contract patch lands
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_dead_guards.md` — `_topHeroSymbol` fully deleted (no deprecated stub)
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_no_history_in_comments.md` — `_applyHeroOverride` NatSpec rewritten to describe what IS (weighted roll); no "previously" / "used to" / "v41 form" wording in source comments
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_frozen_contracts_no_future_proofing.md` — no extensibility hooks, no flag-gated alternative algorithms; ship the locked one shape
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_batch_contract_approval.md` — single USER-APPROVED batched contract commit at phase close
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_never_preapprove_contracts.md` — planner MUST NOT tell executor the contract patch is pre-approved; user reviews diff before commit
- `~/.claude/projects/-home-zak-Dev-PurgeGame-degenerus-audit/memory/feedback_manual_review_before_push.md` — executor presents the contract diff and waits for explicit user approval before commit

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- **`_topHeroSymbol` bit-extract idiom (L1633-1651)** — reused verbatim in pass 1 of `_rollHeroSymbol` for decomposing `dailyHeroWagers[day][q]` packed uint256 into 8 uint32 amounts via `uint32((packed >> (uint256(s) * 32)) & 0xFFFFFFFF)`. Inner-loop `unchecked { ++s; ++q; }` counter-increment idiom preserved.
- **`_applyHeroOverride` color-sampling logic (L1605-1614)** — UNCHANGED. Per D-42N-BONUS-ENTROPY-01, the existing `randomWord` parameter (which carries `r` for both regular and bonus paths) continues to feed the color via `(randomWord >> (q * 3)) & 7`. Only the symbol-roll path gains a new entropy source (`heroEntropy` parameter sourced from raw `randWord`).
- **Existing `keccak256(abi.encode(...))` domain-separation idiom** — pattern reused at multiple jackpot sites (BONUS_TRAITS_TAG at L1938; COIN_JACKPOT_TAG + COIN_LEVEL_TAG references at L170-171 + L1761-1767; salt patterns at L1697 + L1824). `_rollHeroSymbol`'s `keccak256(abi.encode(heroEntropy, day))` follows the same idiom.

### Established Patterns
- **Theoretical-first gas attestation** — Phase 290 `290-01-MEASUREMENT.md` §3 established the pattern; D-42N-CACHE-01 three-shape comparison + D-42N-GAS-01 acceptance threshold both follow it. Run the analytical numbers BEFORE writing the patch.
- **AGENT-COMMITTED pre-patch artifacts (DESIGN-INTENT-TRACE.md + MEASUREMENT.md)** — Phase 290 pattern; both files land BEFORE the contract diff in the plan execution order. Plan 01 produces the sidecars; Plan 02 (if split) or Plan 01's final task produces the contract patch.
- **Single USER-APPROVED batched contract commit at phase close** — Phase 281 + Phase 288 + Phase 290 pattern; all HRROLL contract edits collapse into one commit; user reviews the full diff once.
- **`dailyIdx` as the frozen day-key carrier** — v41 Phase 288 structural anchor; consumed verbatim at HRROLL-04 callsite as `_rollHeroSymbol(dailyIdx, randWord)`. No modification to `dailyIdx` writers (still `_unlockRng` exclusive).
- **3-skill PARALLEL adversarial spawn deferred to Phase 296 SWEEP** — HRROLL is NOT red-teamed in isolation at Phase 292; per D-271-ADVERSARIAL-01 carry, all 3 v42.0 surfaces (MINTCLN + HRROLL + DPNERF) get a single combined SWEEP pass at Phase 296. Plan 292 does NOT spawn adversarial skills.

### Integration Points
- **`_applyHeroOverride` signature change** — only 1 callsite (`_rollWinningTraits` L1941); update is mechanical. `_rollWinningTraits`'s caller surface (12 callsites) is UNCHANGED because `randWord` is already the first parameter of `_rollWinningTraits`.
- **No new public/external surface** — `_rollHeroSymbol` is `private view`; `_applyHeroOverride` stays `private view`; zero new modifiers, admin, upgrade hooks per HRROLL-07.
- **No new storage** — only reads existing `dailyHeroWagers[day][q]` (4 SLOAD per call) + `dailyIdx` (1 SLOAD; already loaded by `_applyHeroOverride`'s caller). Zero new SSTORE callsites per HRROLL-06.
- **VRF bit-slice attestation surface** — HRROLL adds a new RNG consumer (`keccak256(abi.encode(heroEntropy, day))` for the symbol-roll pick); D-42N-COLOR-ENTROPY-01 attestation in `292-01-MEASUREMENT.md` confirms non-collision with: bits[0..12] jackpot path-select / bits[152..167] lootbox/Bernoulli / bits[200..215] jackpot Bernoulli / bits `quadrant*3` color sample. Non-collision is by construction (keccak output is orthogonal to raw randWord bits).

</code_context>

<specifics>
## Specific Ideas

- **The v41 cross-bonus invariance must hold post-HRROLL.** D-42N-BONUS-ENTROPY-01 is the load-bearing user decision: raw `randWord` (pre-bonus-tag) feeds `_rollHeroSymbol`; bonus + regular trait rolls on the same jackpot day land the SAME hero `(q, s)`. Per-jackpot-day lock-in of the hero override is the mechanic intent — hero-symbol winner wins their forced symbol on both rolls, not an independent draw per RNG consumer.
- **Cache shape decision belongs at plan-phase** (D-42N-CACHE-01), not now. The planner runs the analytical three-shape comparison in `292-01-MEASUREMENT.md` and locks. Re-SLOAD-without-cache is the only shape explicitly rejected — wastes ~8.4K gas per call.
- **HRROLL-04 verification is COMPLETE** at context-gathering. Scout confirmed `randWord` is in scope at every `_rollWinningTraits` callsite (12 sites at L285, 354, 520, 531, 538, 609, 610, 689, 1180, 1734, 1754, 1756); plumbing raw `randWord` into `_applyHeroOverride` as a new parameter is straightforward.
- **HRROLL-05 backward-trace destination is `DegenerusGameDegeneretteModule.sol:484-501`** — the `placeDegeneretteBet` site writes `dailyHeroWagers[dailyIdx][q]` at wager time. `dailyIdx` is written ONLY at `_unlockRng` (per L1587-1593 NatSpec — verified during context-gathering scout). Wager amounts for day D are LOCKED before day D+1's VRF request fires; `randWord` (the symbol-roll entropy) is unknown at wager time. Player-controllable input committed before randomness available → RNG commitment-window invariant SAFE.
- **D-42N-COLOR-ENTROPY-01 non-collision is by construction.** Color path consumes bits `quadrant*3` of `r` (3 bits per quadrant; bits 0-11 in v41 form, UNCHANGED). Symbol-roll consumes `uint64(uint256(keccak256(abi.encode(randWord_raw, dailyIdx))) % effectiveTotal)` — derived via keccak from an orthogonal entropy domain. The two bit-slices CANNOT overlap because they're sourced from independent values (`r` vs `keccak(randWord_raw, dailyIdx)`). Attestation in `292-01-MEASUREMENT.md` is one-line.
- **`_topHeroSymbol` deletion is unconditional.** Per `feedback_no_dead_guards.md` + `feedback_frozen_contracts_no_future_proofing.md`: no stub, no marker, no preserved alternative. The function (L1625-1653) and its NatSpec (L1623-1624) go away.

</specifics>

<deferred>
## Deferred Ideas

- **D-42N-GAS-01 acceptance threshold value** — set at plan-phase based on D-42N-CACHE-01 chosen shape's theoretical worst case. Planner picks the value; if >+10K vs v41 baseline, planner flags to user as a checkpoint before proceeding to contract patch. Mirrors Phase 291 D-291-GAS-01 pattern: theoretical attestation at contract phase, hard regression at sister test phase (TST-HRROLL-06).
- **Divergent-entropy alternative for bonus rolls** — explicitly REJECTED at D-42N-BONUS-ENTROPY-01. Not deferred to a future phase; not promoted to a v43+ backlog item. If a future milestone wants per-RNG-consumer independent hero rolls, that is a separate mechanic-design decision under its own anchor.
- **Cache-shape A/B benchmark in production** — only the theoretical worst-case at plan-phase + empirical worst-case at TST-HRROLL-06 are in scope. Not deferred to any further validation.
- **Adversarial pass on HRROLL in isolation** — deferred to Phase 296 SWEEP per D-271-ADVERSARIAL-01 carry. Phase 292 does NOT spawn `/contract-auditor` + `/zero-day-hunter` + `/economic-analyst`; that combined pass red-teams all 3 v42.0 surfaces (MINTCLN + HRROLL + DPNERF) together at Phase 296.

</deferred>

---

*Phase: 292-hero-override-weighted-roll-hrroll*
*Context gathered: 2026-05-17*
