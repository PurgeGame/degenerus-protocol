# Phase 292: Hero-Override Weighted Roll (HRROLL) - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in 292-CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-17
**Phase:** 292-hero-override-weighted-roll-hrroll
**Areas discussed:** Bonus-vs-regular hero-override entropy posture, Pass-2 cache strategy

---

## Area Selection (`present_gray_areas`)

Most Phase 292 decisions were pre-locked in ROADMAP.md + REQUIREMENTS.md (×1.5 leader bonus per D-42N-LEADER-BONUS-01, no min-wager floor per D-42N-FLOOR-01, scan-order tie-break, storage/ABI byte-identity, 5 named decision anchors, RNG commitment-window backward-trace required, design-intent 5-section trace required, single USER-APPROVED batched contract commit). Context-gathering scout surfaced 4 genuine gray areas left for user disposition.

| Option | Description | Selected |
|--------|-------------|----------|
| Bonus-vs-regular entropy posture | _rollWinningTraits' bonus path passes `r = keccak(randWord, BONUS_TRAITS_TAG)` into _applyHeroOverride; regular path passes raw `randWord`. With HRROLL, if _rollHeroSymbol consumes that `r` parameter directly, bonus+regular get DIFFERENT hero overrides per jackpot. If we plumb raw `randWord` separately, both paths get the SAME hero override (preserves v41 cross-bonus invariance). | ✓ |
| D-42N-GAS-01 threshold form | What shape is the gas acceptance threshold? Absolute delta cap, % delta cap, or 'planner picks within theoretical-first attestation, hard regression assertion lives at Phase 293 TST-HRROLL-06 per the roadmap' (mirrors Phase 291 D-291-GAS-01 disposition)? | |
| Plan-artifact shape (DESIGN-INTENT-TRACE sidecar) | Phase 290 pattern: separate `292-01-DESIGN-INTENT-TRACE.md` sidecar holds HRROLL-10 5-section trace, `292-01-MEASUREMENT.md` holds theoretical gas + storage/ABI attestations, `292-01-PLAN.md` is the executable plan. Alternative: fold trace + measurement into PLAN.md body for tighter shape. | |
| Cache strategy in pass 2 | Pass 1 SLOADs the 4 `dailyHeroWagers[day][q]` uint256 packed slots to compute total + identify leader. Pass 2 needs the same data. Cache in a 4-uint256 memory array (4 SLOAD, ~8K gas saved) vs re-SLOAD (8 SLOAD, simpler code) vs cache as 32-uint32 memory array per the roadmap hint. | ✓ |

**User's selection:** 2 of 4 areas selected for discussion. The 2 unselected areas (D-42N-GAS-01 threshold form + plan-artifact shape) were captured under Claude's Discretion in CONTEXT.md `<decisions>` with default dispositions sourced from Phase 290 + Phase 291 patterns.

---

## Bonus-vs-Regular Hero-Override Entropy Posture

**Surprise surfaced during scout:** in `_rollWinningTraits` (`contracts/modules/DegenerusGameJackpotModule.sol:1933-1943`), the bonus-path computes `r = keccak256(randWord, BONUS_TRAITS_TAG)` and passes `r` into `_applyHeroOverride`. In v41 the hero override is `_topHeroSymbol(dailyIdx)` — entropy-independent — so bonus + regular trait rolls get the SAME hero quadrant+symbol per jackpot day (different colors via `r` bits[`quadrant*3`]). HRROLL changes this depending on what entropy `_rollHeroSymbol` consumes.

| Option | Description | Selected |
|--------|-------------|----------|
| A: Preserve v41 invariance (raw randWord) | Plumb raw VRF word separately. Bonus+regular get SAME hero (q, s) per jackpot day. Hero-symbol winner wins forced symbol on both rolls (same as v41 mechanic). Anchor as D-42N-BONUS-ENTROPY-01: 'invariance-preserving; raw randWord into _rollHeroSymbol; +2 LOC plumbing in _applyHeroOverride signature.' | ✓ |
| B: Allow divergence (use `r` post-tag) | Smaller code change: _rollHeroSymbol consumes the existing `r` parameter. Bonus + regular each get an independent weighted roll. Hero-symbol winner wins regular roll but bonus is an independent draw. Mechanic intent: 'every RNG consumer is independent.' Anchor as D-42N-BONUS-ENTROPY-01: 'divergent; consume `r` directly.' | |
| C: Surface both, defer to design-intent trace | Don't lock now — require HRROLL-10 design-intent trace section (vi) to walk both options + game-theoretic implications, present at plan-phase USER-APPROVED gate. Risk: plan-phase re-opens the discussion. Useful if you want to sleep on it. | |

**User's choice:** **A — Preserve v41 invariance via raw `randWord` plumbing.**
**Notes:**
- D-42N-BONUS-ENTROPY-01 locked: `_rollHeroSymbol(dailyIdx, randWord_raw)` consumes the RAW VRF entropy as it arrives into `_rollWinningTraits` at L1934, BEFORE the L1938 bonus tag.
- Implementation: `_applyHeroOverride` signature gains a second entropy param (`uint256 heroEntropy`); the existing `randomWord` param continues to feed color via bits `quadrant*3` (UNCHANGED color path).
- Mechanic semantics preserved: hero-symbol winner wins the forced symbol on both regular AND bonus rolls per jackpot day — same as v41.
- Game-theoretic motivation: hero override is a per-jackpot-day lock-in, NOT a per-RNG-consumer independent draw. Divergent-entropy alternative would have diluted hero-symbol winner EV on days with bonus rolls — explicitly REJECTED.
- D-42N-COLOR-ENTROPY-01 non-collision attestation satisfied by construction: color bits sourced from `r` (post-bonus-tag) vs symbol bits sourced from `keccak256(abi.encode(heroEntropy, day))` — orthogonal entropy domains.

---

## Pass-2 Cache Strategy

Refresher: `dailyHeroWagers[day]` is `uint256[4]` — one packed uint256 per quadrant, each holding 8 × uint32 symbol amounts. Pass 1 needs all 32 cells; pass 2 walks with a cumulative cursor against the keccak-derived pick.

| Option | Description | Selected |
|--------|-------------|----------|
| Cache 4 uint256 packed slots in memory | Pass 1 SLOADs 4 packed slots into `uint256[4] memory cache`; pass 2 reads via bit-shift extracts. 4 SLOAD total (~8.4K gas saved vs re-SLOAD). Smallest memory footprint. Identical bit-extract idiom to v41 `_topHeroSymbol`. | |
| Cache 32 uint32 amounts in a uint32[] memory array | Per the roadmap's '32-entry memory array' hint. Pass 1 unpacks into `uint32[32]`; pass 2 walks the array directly. 4 SLOAD + 32 array writes + 32 array reads. More memory, simpler pass-2 cursor loop. | |
| Re-SLOAD in pass 2 (no cache) | Pass 1 SLOADs for total + leader; pass 2 re-SLOADs the same 4 slots. 8 SLOAD total (~+8.4K gas vs cache). Smallest code, no memory allocation. Doesn't fit `feedback_no_dead_guards.md` spirit. | |
| Planner's discretion | Lock 'memory-cached pass 2; specific shape decided at plan-phase based on theoretical-gas comparison.' Anchor as D-42N-CACHE-01: 'memory-cached pass 2; shape per plan-phase gas measurement.' | (effective) |

**User's choice (free-text):** **"do whatever is most gas efficient in the long run"**
**Notes:**
- Interpreted as planner-discretion under the theoretical-first framework per `feedback_gas_worst_case.md`.
- D-42N-CACHE-01 locked: most-gas-efficient memory cache in pass 2; final shape (flat `uint32[32]` vs `uint64[32]` weights vs packed `uint256[4]`) decided at plan-phase via `292-01-MEASUREMENT.md` three-shape gas comparison.
- Re-SLOAD-without-cache explicitly REJECTED — burns ~8.4K gas per call for no benefit, violates `feedback_no_dead_guards.md` (gas waste with no design value).
- Gas delta between the three cache shapes is sub-1K and depends on pass-2 early-exit behavior (cursor exits on average at iteration ~16/32). Planner runs the actual numbers and commits the choice with justification.
- D-42N-GAS-01 acceptance threshold (in Claude's Discretion) closes against the chosen shape's theoretical worst case.

---

## Claude's Discretion (areas not selected for user discussion)

- **D-42N-GAS-01 acceptance threshold form** — defaulted to Phase 291 D-291-GAS-01 pattern: theoretical-first attestation in `292-01-MEASUREMENT.md`; hard runtime regression assertion at Phase 293 TST-HRROLL-06. Threshold value locked at plan-phase based on D-42N-CACHE-01 chosen shape's theoretical worst case. Planner flags to user if theoretical worst case exceeds ~+10K vs v41 baseline.
- **Plan-artifact sidecar shape** — defaulted to Phase 290 pattern: separate `292-01-PLAN.md` + `292-01-DESIGN-INTENT-TRACE.md` + `292-01-MEASUREMENT.md` sidecars. Both AGENT-COMMITTED sidecars land BEFORE the contract patch per `feedback_design_intent_before_deletion.md`.
- **HRROLL-04 callsite-scope verification** — completed during context-gathering scout: `randWord` is in scope at every `_rollWinningTraits` callsite (12 sites verified at L285, 354, 520, 531, 538, 609, 610, 689, 1180, 1734, 1754, 1756). Plumbing raw `randWord` into `_applyHeroOverride` as a new parameter is mechanical.
- **`_topHeroSymbol` deletion posture** — defaulted to full deletion per `feedback_no_dead_guards.md` + `feedback_frozen_contracts_no_future_proofing.md` + `feedback_no_history_in_comments.md`. No stub, no marker; the function + NatSpec block removed entirely.
- **Pass-2 cursor walk implementation** — defaulted to flat idx 0..31 ascending (q = idx >> 3, s = idx & 7) with leader-bonus added when `idx == leaderIdx`. Early-exit on first `cumulative > pick` match. Recorded under D-42N-DETERMINISM-01 spec at plan-phase.
- **Weight-arithmetic type widening** — defaulted to uint64 for leader weight (`maxAmount + leaderBonus` can be up to ~6.4e9 which exceeds uint32). effectiveTotal as uint64. Solidity 0.8+ checked arithmetic by default; `unchecked` only for loop counters (existing v41 idiom).
- **`pick` modulo bias** — non-issue by construction: amounts are uint32, max effectiveTotal across 32 slots with ×1.5 bonus ≈ 2.06e11, fits in 64 bits with massive headroom; `pick = uint64(uint256(keccak(...)) % effectiveTotal)` is uniform.

---

## Deferred Ideas

- **D-42N-GAS-01 acceptance threshold value** — set at plan-phase based on D-42N-CACHE-01 chosen shape's theoretical worst case.
- **Divergent-entropy alternative for bonus rolls** — explicitly REJECTED at D-42N-BONUS-ENTROPY-01. Not deferred; not a future-phase candidate.
- **Cache-shape A/B benchmark in production** — only theoretical worst-case at plan-phase + empirical worst-case at TST-HRROLL-06 are in scope.
- **Adversarial pass on HRROLL in isolation** — deferred to Phase 296 SWEEP per D-271-ADVERSARIAL-01 carry (combined 3-skill pass across MINTCLN + HRROLL + DPNERF).
