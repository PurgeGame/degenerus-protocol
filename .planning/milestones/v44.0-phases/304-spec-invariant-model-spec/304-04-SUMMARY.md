---
phase: 304-spec-invariant-model-spec
plan: 04
subsystem: sStonk redemption refactor SPEC
tags: [SPEC, design-intent-trace, sStonk, redemption, v44.0, V-184-structural-elimination, deletion-walks]
requires: [INV-01, INV-02, INV-03, INV-04, INV-05, INV-06, INV-07, INV-08, INV-09, INV-10, INV-11, INV-12, SPEC-01, SPEC-02, SPEC-03, SPEC-04, SPEC-05, EDGE-01, EDGE-02, EDGE-03, EDGE-04, EDGE-07, EDGE-14, EDGE-16, EDGE-18]
provides: [§4-design-intent-walks-7-deletions, V-184-structural-elimination-attestation]
affects: [.planning/phases/304-spec-invariant-model-spec/304-SPEC.md]
tech-stack:
  added: []
  patterns: [design-intent-backward-trace, actor-game-theory-walk, structural-elimination-attestation]
key-files:
  created:
    - .planning/phases/304-spec-invariant-model-spec/304-04-SUMMARY.md
  modified:
    - .planning/phases/304-spec-invariant-model-spec/304-SPEC.md
    - .planning/STATE.md
    - .planning/ROADMAP.md
decisions:
  - "V-184 structural elimination attested as JOINT product of SPEC-01 (per-day keying) + SPEC-03 (dayToResolve arg) + SPEC-04 (c) (delete pendingByDay[D] at resolve); no single lock suffices alone"
  - "Deletion 7 (redemptionPeriodIndex reset block) is the STRUCTURAL ENABLER of V-184 — the :758 predicate cannot distinguish 'first burn of fresh day' from 'post-resolve re-burn on same wall-clock day'"
  - "Per-day keying is STRICTLY STRONGER than the RNGLOCK-FIXREC §103.C tactic-(c) 'advance redemptionPeriodIndex inside resolveRedemptionPeriod' fix (which itself regresses via the :758 reset conditional per §103.C lines 5577-5578)"
  - "Deletion 6 (UnresolvedClaim revert) becomes STRUCTURALLY UNREACHABLE under composite-keyed pendingRedemptions[player][day] — SPEC-02 removes dead code; UX-guardrail role obsoleted (cross-day claim accumulation now safe by construction)"
  - "§4 line range fixed for Plan 05 citation-manifest sweep: 676-829 (154 lines including closing attestation)"
  - "§4 honors feedback_no_history_in_comments.md as the EXCEPTION zone — pre-refactor narration appears ONLY here under explicit ORIGINAL DESIGN INTENT labels; §1/§2/§3/§5 prose remains POST-REFACTOR-state only"
metrics:
  duration: "~6 min"
  completed: "2026-05-19"
  tasks_completed: 2
  files_created: 1
  files_modified: 1
---

# Phase 304 Plan 04: §4 Design-Intent Backward-Trace + Actor Game-Theory Walk for 7 Deletions — Summary

Filled `## §4 — Design-Intent Backward-Trace + Actor Game-Theory Walk` with introductory paragraph + 7 deletion subsections + closing V-184 joint-elimination attestation. Each deletion carries the 4-field structure required by `feedback_design_intent_before_deletion.md`: **ORIGINAL DESIGN INTENT** (v43.0 baseline at HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2`) + **ACTOR GAME-THEORY WALK** (across timing × state combinations) + **POST-REFACTOR REPLACEMENT** (naming the SPEC-NN lock that subsumes the deletion) + **DELETION SAFETY ATTESTATION** (proving no game-theoretic scenario re-introduces the deleted behavior). §4 is the audit-trail proof that each of the 7 v44.0 deletions enumerated in §2.7 has been reasoned through BEFORE the lock — Phase 305 IMPL has the design walks as its load-bearing input for materializing the deletions in the actual contract diff.

## What was built

### Task 1 — §4 introduction + Deletions 1-3 (commit `20f3d439`)

Replaced the `_To be filled by Plan 04_` placeholder with:

**§4 introductory paragraph (1 paragraph):** cites `feedback_design_intent_before_deletion.md`; states the 4-field per-deletion structure; calls out §4 as the EXCEPTION zone for `feedback_no_history_in_comments.md` (pre-refactor narration appears ONLY here under explicit `ORIGINAL DESIGN INTENT` labels; §1/§2/§3/§5 describe POST-REFACTOR state only).

**Deletion 1: `redemptionPeriodIndex` storage slot (`:230`).** ORIGINAL DESIGN INTENT cites RNGLOCK-FIXREC §103.A line 5414 single-writer attestation + the dual-role usage (period key into `redemptionPeriods[period]` + storage key embedded in `pendingRedemptions[player].periodIndex`). ACTOR GAME-THEORY WALK reproduces V-184 verbatim across 9 (timing × state) combinations: setup → day-D advance (index NOT mutated) → decision point (informed-attacker filter) → re-arm → re-roll fire → claim → EV asymmetry ~19% per round → collateral damage to Player C → rngWordByDay same-day short-circuit doesn't help → supply cap binds volume not count. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 + SPEC-03 + SPEC-04 (c) — per-day mapping eliminates indirection slot. DELETION SAFETY ATTESTATION: INV-01 + INV-06 + INV-07 + EDGE-07 jointly; structural closure, no runtime revert added.

**Deletion 2: `redemptionPeriodSupplySnapshot` storage slot (`:229`).** ORIGINAL DESIGN INTENT explains the lazy-init defense against auto-tightening cap denominator from progressive `totalSupply` decrease. ACTOR GAME-THEORY WALK covers 5 combinations: honest first-of-day burner → late-day honest burner → hypothetical front-running attacker (no public mint path post-launch) → V-184 attacker interaction → cross-day legitimate burner. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 (`pendingByDay[D].supplySnapshot` `uint128`) + SPEC-05 (slot-zero lazy-init predicate). DELETION SAFETY ATTESTATION: INV-10 + EDGE-14.

**Deletion 3: `redemptionPeriodBurned` storage slot (`:231`).** ORIGINAL DESIGN INTENT explains the per-period cumulative-burn accumulator paired with the snapshot denominator. ACTOR GAME-THEORY WALK covers 6 combinations: honest same-day sequence → mid-day reset attempt (blocked) → many-small-burns attempt (cap is amount-aggregate) → V-184 attacker (cap binds volume, not count) → cross-day reset → skipped-advance edge. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 (`pendingByDay[D].burned` `uint128`); cross-day reset becomes STRUCTURAL (Solidity default-zero) rather than block-conditional. DELETION SAFETY ATTESTATION: INV-10 + EDGE-14 + EDGE-16; structural-reset property is strictly safer than the `:761` block-conditional reset.

### Task 2 — §4 Deletions 4-7 + closing V-184 joint-elimination attestation (commit `d3c2aea5`)

Appended the remaining 4 deletion subsections + a closing paragraph.

**Deletion 4: `pendingRedemptionEthBase` storage slot (`:226`).** ORIGINAL DESIGN INTENT explains the "what's at stake on the next roll" register lifecycle (cleared at `:594`, incremented at `:790`, read at `:589`/`:592`). ACTOR GAME-THEORY WALK covers 6 combinations: honest same-day burner → day-D advance resolution → V-184 attacker same-day post-resolve re-burn (the single-pool nature is what enables the cross-day re-roll) → day-D+1 advance re-roll fire → honest cross-day burner → `hasPendingRedemptions()` reader behavior. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 (`pendingByDay[D].ethBase` `uint256` slot 0). DELETION SAFETY ATTESTATION: INV-04 + INV-08 + EDGE-01 + EDGE-02 + EDGE-07.

**Deletion 5: `pendingRedemptionBurnieBase` storage slot (`:227`).** ORIGINAL DESIGN INTENT explains the BURNIE analog — same `roll` applied to both bases per resolver computation at `:592`/`:597`, lifecycle paired with `pendingRedemptionEthBase`. ACTOR GAME-THEORY WALK covers 5 combinations: honest BURNIE-claimer → V-184 BURNIE-side exploit (same R scales both bases) → coinflip-decoupled actor (combined EV = re-roll × coinflip = ~9.5% on the BURNIE side) → BURNIE-pool insufficient at claim (`_payBurnie` fallback chain at `:842-852`) → `pendingRedemptionBurnie` cumulative reserve accounting. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 (`pendingByDay[D].burnieBase` `uint256` slot 1). DELETION SAFETY ATTESTATION: INV-03 + INV-04 + EDGE-04 + EDGE-18.

**Deletion 6: `UnresolvedClaim` revert (`:796-797`).** ORIGINAL DESIGN INTENT explains the dual role: UX guardrail (forcing claim-before-cross-day-burn) + safety guardrail (preventing single-mapping-entry overwrite that would clobber `ethValueOwed_D` with `ethValueOwed_{D+1}`). ACTOR GAME-THEORY WALK covers 6 combinations: honest cross-day accumulator (hits revert) → honest same-period accumulator (bypasses; permitted stacking) → first-ever burner (`periodIndex == 0` sentinel bypass) → deliberate-stall mid-period attacker (revert NOT the defense here; symmetric exposure to unknown roll) → cross-day stall + claim-skip attacker (revert blocks this overwrite) → `periodIndex == 0` sentinel ambiguity. POST-REFACTOR REPLACEMENT: subsumed by SPEC-02 — composite-key `pendingRedemptions[player][day]` mapping makes the revert STRUCTURALLY UNREACHABLE; SPEC-02 removes dead code; cross-day claim accumulation becomes safe by construction (day-D and day-D+1 claims live in separate mapping entries). DELETION SAFETY ATTESTATION: INV-07 + EDGE-03 + EDGE-16; the UX-guardrail role is strictly improved (claiming day-D and burning day-D+1 are now independent operations with no ordering constraint).

**Deletion 7: `redemptionPeriodIndex` reset block (`:757-762`).** ORIGINAL DESIGN INTENT shows the literal 6-line deleted block verbatim with line-by-line breakdown (`:757` `currentPeriod` read → `:758` predicate → `:759-761` reset writes → `:762` close brace). Per RNGLOCK-FIXREC §103.A line 5414 attestation, `:760` is the ONLY writer of `redemptionPeriodIndex` (single-writer). ACTOR GAME-THEORY WALK covers 5 combinations: honest first-of-day burner → honest subsequent same-day burner → **V-184 STRUCTURAL ENABLER** (predicate cannot distinguish "first burn of fresh day D" from "post-resolve re-burn on same wall-clock day D" — both look identical because `redemptionPeriodIndex == currentPeriod == D` in both cases) → RNGLOCK-FIXREC §103.C tactic-(c) v43-baseline proposed fix (`redemptionPeriodIndex = period + 1` inside resolver) and its failure mode (`:758` reset regresses the advance per §103.C lines 5577-5578; per-day keying is STRICTLY STRONGER) → skipped-advance edge. POST-REFACTOR REPLACEMENT: subsumed by SPEC-01 + SPEC-05; index-advance role is ELIMINATED (no index slot to advance), lazy-init role moves to SPEC-05 slot-zero predicate. DELETION SAFETY ATTESTATION: INV-01 + INV-10 + EDGE-07 + EDGE-14 + EDGE-16.

**§4 closing attestation paragraph.** Explicit attestation that V-184 structural elimination is the JOINT product of SPEC-01 + SPEC-03 + SPEC-04 (c); no single lock suffices alone. With SPEC-01 alone but WITHOUT SPEC-03: resolver reading from a "current period" indirection slot could still go stale. With SPEC-03 alone but WITHOUT SPEC-01: per-day pool that still shared a single ETH base slot would re-introduce cross-day conflation. With SPEC-04 (c) alone but WITHOUT SPEC-01: no per-day entry to delete. EDGE-07 in §3 + Deletions 1, 4, 5, 7 in §4 are the canonical closure artifacts; Phase 305 IMPL ships the diff; Phase 306 TST-04 + TST-05 + EDGE-07 fuzz test prove it; Phase 308 §3.D records RESOLVED-AT-V44 disposition.

## 7 Deletion → SPEC-NN replacement mapping (Plan 05 cross-checks)

| # | Deletion | v43.0 baseline location | Subsumed by |
|---|----------|-------------------------|-------------|
| 1 | `redemptionPeriodIndex` storage slot | `StakedDegenerusStonk.sol:230` | SPEC-01 + SPEC-03 + SPEC-04 (c) |
| 2 | `redemptionPeriodSupplySnapshot` storage slot | `StakedDegenerusStonk.sol:229` | SPEC-01 + SPEC-05 |
| 3 | `redemptionPeriodBurned` storage slot | `StakedDegenerusStonk.sol:231` | SPEC-01 |
| 4 | `pendingRedemptionEthBase` storage slot | `StakedDegenerusStonk.sol:226` | SPEC-01 |
| 5 | `pendingRedemptionBurnieBase` storage slot | `StakedDegenerusStonk.sol:227` | SPEC-01 |
| 6 | `UnresolvedClaim` revert | `StakedDegenerusStonk.sol:796-797` (error decl `:108`) | SPEC-02 |
| 7 | `redemptionPeriodIndex` reset block | `StakedDegenerusStonk.sol:757-762` | SPEC-01 + SPEC-05 |

## File:line citations made in §4 that Plan 05 must verify against HEAD `8111cfc5189f628b64b500c881f9995c3edf0ed2`

**`contracts/StakedDegenerusStonk.sol`:**

- `:108` — `error UnresolvedClaim();` declaration (Deletion 6 source line)
- `:212` — `uint32 periodIndex` field in `PendingRedemption` (removed under SPEC-02 since outer mapping key carries the day)
- `:221` — `mapping(address => PendingRedemption) public pendingRedemptions` (pre-refactor single-key declaration; Deletion 6 walk)
- `:222` — `mapping(uint32 => RedemptionPeriod) public redemptionPeriods` (Deletion 1 walk — public auto-getter is the attacker's read site)
- `:226` — `pendingRedemptionEthBase` slot (Deletion 4)
- `:227` — `pendingRedemptionBurnieBase` slot (Deletion 5)
- `:229` — `redemptionPeriodSupplySnapshot` slot (Deletion 2)
- `:230` — `redemptionPeriodIndex` slot (Deletion 1)
- `:231` — `redemptionPeriodBurned` slot (Deletion 3)
- `:578` — `hasPendingRedemptions()` returns `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0` (Deletion 4 walk)
- `:588` — `uint32 period = redemptionPeriodIndex;` (resolver reads stale index; Deletion 1 walk + Deletion 7 walk)
- `:589` — `if (pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0) return;` early-return (Deletion 4 walk)
- `:592` — `(pendingRedemptionEthBase * roll) / 100` rolled ETH (Deletion 4 walk)
- `:593` — `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;` (Deletion 4 walk)
- `:594` — `pendingRedemptionEthBase = 0` clear-on-resolve (Deletion 4)
- `:597` — `(pendingRedemptionBurnieBase * roll) / 100` rolled BURNIE (Deletion 5 walk)
- `:600` — `pendingRedemptionBurnie -= pendingRedemptionBurnieBase` release (Deletion 5 walk)
- `:601` — `pendingRedemptionBurnieBase = 0` clear-on-resolve (Deletion 5)
- `:604` — `redemptionPeriods[period] = RedemptionPeriod({roll: roll, flipDay: flipDay})` (Deletion 1 walk — the OVERWRITE site)
- `:609` — `emit RedemptionResolved(period, roll, burnieToCredit, flipDay)` (Deletion 5 walk)
- `:649-654` — `coinflip.previewClaimCoinflips()` + `redemptionPeriods[period].flipDay` lookup (Deletion 5 walk)
- `:757` — `uint32 currentPeriod = game.currentDayView();` (Deletion 7 verbatim block opener)
- `:757-762` — full reset block (Deletion 7 literal verbatim quote)
- `:758` — `if (redemptionPeriodIndex != currentPeriod) {` (Deletion 7 predicate)
- `:759` — `redemptionPeriodSupplySnapshot = totalSupply;` (Deletion 7 line 3)
- `:760` — `redemptionPeriodIndex = currentPeriod;` (Deletion 7 line 4; single-writer per RNGLOCK-FIXREC §103.A line 5414)
- `:761` — `redemptionPeriodBurned = 0;` (Deletion 7 line 5; Deletion 3 cross-day reset)
- `:762` — close brace
- `:763` — `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2` cap check (Deletion 2 + Deletion 3 walks)
- `:764` — `redemptionPeriodBurned += amount;` increment (Deletion 3)
- `:784` — `totalSupply -= amount;` (Deletion 2 walk — the only `totalSupply` mutator post-launch)
- `:790` — `pendingRedemptionEthBase += ethValueOwed` increment (Deletion 4)
- `:791` — `pendingRedemptionBurnie += burnieOwed` reserve accumulation (Deletion 5 walk)
- `:792` — `pendingRedemptionBurnieBase += burnieOwed` increment (Deletion 5)
- `:796-797` — `UnresolvedClaim` revert (Deletion 6)
- `:803` — `claim.ethValueOwed += uint96(ethValueOwed)` same-period stacking (Deletion 6 walk)
- `:842-852` — `_payBurnie` fallback chain via `coinflip.claimCoinflipsForRedemption` (Deletion 5 walk)

**`contracts/modules/DegenerusGameAdvanceModule.sol`:**

- `:1187` — `if (rngWordByDay[day] != 0) return (rngWordByDay[day], 0);` same-day short-circuit (Deletion 1 walk — does NOT defend against V-184)
- `:1225` — `if (sdgnrs.hasPendingRedemptions())` gate (Deletion 4 walk — returns TRUE post-V-184-re-arm)
- `:1226-1228` — `redemptionRoll = uint16(((currentWord >> 8) % 151) + 25)` roll derivation (range 25-175)

**External references cited in §4 (RNGLOCK-FIXREC.md line numbers, for Plan 05 verification against the FIXREC source):**

- `RNGLOCK-FIXREC.md:5414` — `redemptionPeriodIndex` single-writer attestation (Deletion 1 + Deletion 7)
- `RNGLOCK-FIXREC.md:5445-5449` — day-D player A burn setup steps (Deletion 1)
- `RNGLOCK-FIXREC.md:5455` — "redemptionPeriodIndex NOT mutated" verbatim (Deletion 1 + Deletion 7)
- `RNGLOCK-FIXREC.md:5457-5461` — same-day re-burn step (Deletion 1)
- `RNGLOCK-FIXREC.md:5472-5474` — EV asymmetry computation (Deletion 1)
- `RNGLOCK-FIXREC.md:5476` — rngWordByDay short-circuit attestation (Deletion 1)
- `RNGLOCK-FIXREC.md:5478` — collateral damage to Player C (Deletion 1)
- `RNGLOCK-FIXREC.md:5494` — re-arm step 4 verbatim (Deletion 1)
- `RNGLOCK-FIXREC.md:5500-5506` — re-roll fire step 5 verbatim (Deletion 1)
- `RNGLOCK-FIXREC.md:5511` — cap-bounds-magnitude-not-count attestation (Deletion 1 + Deletion 2 + Deletion 3)
- `RNGLOCK-FIXREC.md:5567` — tactic-(c) `redemptionPeriodIndex = period + 1` proposal (Deletion 7)
- `RNGLOCK-FIXREC.md:5577-5578` — tactic-(c) reset regression failure mode (Deletion 7)

## §4 line range (for Plan 05 citation-manifest sweep)

`§4 — Design-Intent Backward-Trace + Actor Game-Theory Walk` occupies **lines 676-829** of `304-SPEC.md` (154 lines including the closing attestation paragraph). Plan 05 grep-verifies every `StakedDegenerusStonk.sol:NNN` and `DegenerusGameAdvanceModule.sol:NNN` citation within this range against source HEAD per `feedback_verify_call_graph_against_source.md`.

## Per-deletion V-184 walk coverage (§4 acceptance check)

| Deletion | V-184 mechanic cited in walk? | Cross-reference |
|----------|-------------------------------|-----------------|
| Deletion 1 (redemptionPeriodIndex slot) | YES — full V-184 trace verbatim from RNGLOCK-FIXREC §103 | Same-day post-resolve re-burn → stale index → next-day advance overwrite + ~19% EV + collateral damage |
| Deletion 2 (supplySnapshot slot) | YES — V-184 interaction subsection | Cap binds volume not re-roll count; snapshot stays frozen through re-arm |
| Deletion 3 (redemptionPeriodBurned slot) | YES — V-184 attacker interaction subsection | Cap binds volume not count of 1-wei re-burns |
| Deletion 4 (pendingRedemptionEthBase slot) | YES — same-day post-resolve re-burn re-arms slot; cross-day pool conflation enabler | Single-pool nature is what enables V-184 |
| Deletion 5 (pendingRedemptionBurnieBase slot) | YES — BURNIE-side of V-184; same R scales both bases | ~9.5% BURNIE EV per round (coinflip-decoupled) |
| Deletion 6 (UnresolvedClaim revert) | N/A — composite keying makes revert STRUCTURALLY UNREACHABLE (not a V-184 mechanic) | Cross-cuts SPEC-02 composite-key safety |
| Deletion 7 (redemptionPeriodIndex reset block) | YES — STRUCTURAL ENABLER of V-184; cites tactic-(c) failure mode | Per-day keying STRICTLY STRONGER than §103.C tactic-(c) |

Deletions 1 + 4 + 5 + 7 carry the V-184 mechanic verbatim per plan acceptance criteria. Deletions 2 + 3 cross-reference V-184 in the supply-cap context (cap binds magnitude not count). Deletion 6 is structurally unrelated to V-184 (composite-keying safety, not stale-index re-roll).

## Closing-paragraph joint-elimination attestation (acceptance check)

The §4 closing paragraph satisfies the load-bearing attestation: V-184 structural elimination is the JOINT product of three SPEC-NN locks, no single lock suffices alone.

| Lock | Removes | Without this lock, the V-184 surface re-emerges via... |
|------|---------|--------------------------------------------------------|
| SPEC-01 (per-day keying) | Single-pool indirection | A "current period" indirection slot could still go stale |
| SPEC-03 (dayToResolve arg) | Contract-state-read of target day | A per-day pool sharing a single ETH base slot would re-introduce cross-day conflation |
| SPEC-04 (c) (delete at resolve) | Same-wall-clock-day re-arm window | No per-day entry to delete; the entry would persist after resolve and be re-armable |

This is the load-bearing closure attestation Phase 308 §3.D will cite as the RESOLVED-AT-V44 disposition for V-184 (HANDOFF-111..117).

## Cross-cutting notes for Plan 05

1. **`:761` reset block line range** — Plan 05 must grep-verify `:757-762` against HEAD; if the line range has drifted (e.g., source-level reflow), update the SPEC-04 (c) line-range cite accordingly. The §4 closing-paragraph attestation does not depend on exact line numbers, only on the existence of the reset block at the cited region.
2. **RNGLOCK-FIXREC §103 line citations** — §4 references specific RNGLOCK-FIXREC line numbers (5414, 5445-5449, 5455, 5457-5461, 5472-5474, 5476, 5478, 5494, 5500-5506, 5511, 5567, 5577-5578). Plan 05 should grep-verify these against the FIXREC source file. If FIXREC content has shifted, the cited line numbers should be updated in §4 (or replaced with stable section labels like §103.A / §103.B / §103.C if line drift is expected).
3. **`pendingRedemptionBurnie` cumulative reserve interaction at `:791`** — §4 Deletion 5 walk asserts that the same-day post-resolve 1-wei re-burn at `:791` (`pendingRedemptionBurnie += burnieOwed`) is correctly balanced by the next-day advance's `:600` (`pendingRedemptionBurnie -= pendingRedemptionBurnieBase`). Plan 05 should grep-verify both line numbers and confirm the reserve-balance accounting matches.
4. **Deletion 7 verbatim quote of `:757-762`** — §4 reproduces the 6-line block literally. Plan 05 must grep-verify byte-for-byte against source HEAD (`uint32 currentPeriod = game.currentDayView();` + `if (redemptionPeriodIndex != currentPeriod) {` + `redemptionPeriodSupplySnapshot = totalSupply;` + `redemptionPeriodIndex = currentPeriod;` + `redemptionPeriodBurned = 0;` + closing brace).

## §4 honors comment-policy + design-intent-trace feedback

- **`feedback_design_intent_before_deletion.md`** — every deletion traced with design intent + actor game-theory across timing/state combinations BEFORE the deletion is locked. The §4 closing paragraph attests "every deletion was reasoned through BEFORE the lock — Phase 305 IMPL materializes the 7 deletions in the actual contract diff with the design walk above as its load-bearing input."
- **`feedback_no_history_in_comments.md`** — §4 introductory paragraph explicitly calls out that §4 is the EXCEPTION zone; pre-refactor narration appears ONLY here under explicit `ORIGINAL DESIGN INTENT` labels. §1/§2/§3/§5 remain POST-REFACTOR-state-only per their respective Plan 01/02/03/05 acceptance criteria. Plan 05 has a cross-section "what changed" leakage check on its acceptance list.
- **`feedback_frozen_contracts_no_future_proofing.md`** — every POST-REFACTOR REPLACEMENT field describes the v44.0 storage shape directly; no migration-friendly fallback prose; no "for future extensibility" speculation. Pre-launch redeploy-fresh posture honored.

## Deviations from Plan

None — plan executed exactly as written. Both task acceptance criteria pass on first verify:

- Task 1: `DELETIONS_1_2_3_PRESENT` + 3 each of ORIGINAL DESIGN INTENT / ACTOR GAME-THEORY WALK / POST-REFACTOR REPLACEMENT / DELETION SAFETY ATTESTATION labels in the Deletion 1-3 region + V-184 mechanic in Deletion 1 + ~19% EV cite + introductory paragraph cites `feedback_design_intent_before_deletion.md`.
- Task 2: `ALL_7_DELETIONS_PRESENT` + 7 of each label across all 7 deletions + V-184 mechanic in Deletions 4, 5, 7 walks (5/7/3 occurrences respectively) + Deletion 6 explicit "STRUCTURALLY UNREACHABLE" + Deletion 7 cites §103.C tactic-(c) failure mode + closing paragraph attests joint elimination via "SPEC-01 + SPEC-03 + SPEC-04" (2 occurrences) + placeholder removed (0 remaining matches for `_To be filled by Plan 04_`).

The 8th `ORIGINAL DESIGN INTENT` count (vs expected 7) is the one in the §4 introductory paragraph where the 4 field labels are introduced — harmless over-match, not a duplicate deletion subsection.

## Self-Check: PASSED

- File `.planning/phases/304-spec-invariant-model-spec/304-SPEC.md` exists (FOUND; modified at commits `20f3d439` + `d3c2aea5`).
- File `.planning/phases/304-spec-invariant-model-spec/304-04-SUMMARY.md` exists (FOUND, written before final commit).
- Commit `20f3d439` Task 1 §4 introduction + Deletions 1-3 (FOUND in `git log --oneline`).
- Commit `d3c2aea5` Task 2 §4 Deletions 4-7 + closing attestation (FOUND in `git log --oneline`).
- 7 `### Deletion N:` subsections present (verified via per-N grep loop returning ALL_7_DELETIONS_PRESENT; `grep -c "^### Deletion [1-7]:"` returns 7).
- All 4 labeled fields appear 7× each (ORIGINAL DESIGN INTENT, ACTOR GAME-THEORY WALK, POST-REFACTOR REPLACEMENT, DELETION SAFETY ATTESTATION) — verified by per-label `grep -c` returning ≥7 (ORIGINAL DESIGN INTENT count is 8 because the §4 introduction also names the field; harmless over-match).
- V-184 mechanic explicitly traced in Deletions 1 + 4 + 5 + 7 (verified by region-scoped grep returning 5/7/3 occurrences in those regions; Deletion 1 carries the full RNGLOCK-FIXREC §103 verbatim trace).
- Deletion 6 explicitly states composite-keying makes the revert STRUCTURALLY UNREACHABLE (verified by grep returning 2 matches in the Deletion 6 region).
- Deletion 7 cites tactic-(c) failure mode (verified by grep returning 1 match for `tactic-(c)` or `§103.C` in Deletion 7 region).
- §4 closing paragraph cites joint elimination via SPEC-01 + SPEC-03 + SPEC-04 (verified — 2 occurrences of the exact string `SPEC-01 + SPEC-03 + SPEC-04` across the SPEC; one in §3 EDGE-07, one in §4 closing).
- §4 placeholder `_To be filled by Plan 04_` removed (verified — `grep -c` returns 0).
- §5 placeholder `_To be filled by Plan 05 — see PLAN.md_` intact for Plan 05 (verified — still present at the SPEC tail).
- §4 spans lines 676-829 (154 lines); total SPEC.md now 832 lines.
- STATE.md updated: progress 4/5 (80%), Current Position Plan 5 of 5, Performance Metrics row added for P04, 5 D-304-04-NN decisions appended.
- ROADMAP.md updated: 304-04-PLAN.md flipped from `[ ]` to `[x]` with commit hashes + SUMMARY path.
