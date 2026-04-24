# Phase 245: sDGNRS Redemption Gameover Safety + Pre-Existing Gameover Invariant Re-Verification — Context

**Gathered:** 2026-04-24
**Status:** Ready for planning
**Mode:** Interactive gray-area selection (user answered 2 of 4 discuss questions — claimRedemption classification + per-wei accounting rigor; plan split + GOE-06 depth auto-decided via 244 precedent)

<domain>
## Phase Boundary

Close the sDGNRS redemption lifecycle × gameover-timing matrix against the 771893d1 delta (liveness-gate shift + `pendingRedemptionEthValue` drain-subtraction + `_gameOverEntropy` redemption-resolution fallback + 14-day VRF-dead grace), AND re-verify every pre-existing gameover invariant (v24.0 33/33/34 + 30-day sweep, v11.0 `gameOverPossible` BURNIE gate, F-29-04 mid-cycle substitution envelope) still holds at HEAD `cc68bfc7`.

14 requirements across 2 buckets:

- **SDR-01..SDR-08** (8 REQs) — sDGNRS redemption deep sub-audit:
  - SDR-01 redemption state-transition × gameover-timing matrix (6 timings)
  - SDR-02 `pendingRedemptionEthValue` accounting exactness (entry/exit/dust/overshoot)
  - SDR-03 `handleGameOverDrain` full-subtraction before 33/33/34 split
  - SDR-04 `claimRedemption` post-gameOver DOS-free / starvation-free / underflow-free / race-free
  - SDR-05 per-wei ETH conservation across all 6 timings
  - SDR-06 State-1 orphan-redemption window closed (burn + burnWrapped block coverage)
  - SDR-07 sDGNRS supply conservation across full lifecycle
  - SDR-08 `_gameOverEntropy` VRF-pending-redemption fallback fairness (F-29-04 class)

- **GOE-01..GOE-06** (6 REQs) — pre-existing gameover invariant RE_VERIFIED_AT_HEAD `cc68bfc7`:
  - GOE-01 F-29-04 RNG-consumer determinism envelope at new HEAD
  - GOE-02 claimablePool 33/33/34 split + 30-day sweep (v24.0) against new `pendingRedemptionEthValue` drain
  - GOE-03 purchase blocking entry-point coverage at current surface (updated from v24.0's "10 entry points")
  - GOE-04 VRF-available vs prevrandao fallback gameover-jackpot branches given new 14-day grace
  - GOE-05 `gameOverPossible` BURNIE endgame gate (v11.0) across all new liveness paths
  - GOE-06 NEW cross-feature emergent behavior from liveness × redemption × drain-subtraction interaction

Scope source is `audit/v31-244-PER-COMMIT-AUDIT.md` (FINAL READ-only, 2,858 lines at HEAD `cc68bfc7`) + `audit/v31-243-DELTA-SURFACE.md` (FINAL READ-only, Phase 243 catalog). The Phase 244 `§Phase-245-Pre-Flag` subsection (L2470-2521 of v31-244-PER-COMMIT-AUDIT.md, 17 bullets across all 14 REQs) is ADVISORY input — Phase 245 plans consume it as pre-derived observation pool but are NOT bound by it (Phase 245 may surface entirely new vectors).

Scope is strictly READ-only: no `contracts/` or `test/` writes (v28/v29/v30/243/244 carry-forward + project `feedback_no_contract_commits.md`). Finding-ID emission is deferred to Phase 246 (FIND-01/02/03); Phase 245 produces per-REQ verdicts + finding-candidate blocks with `SEVERITY: <bucket>` prose blocks.

**Not in Phase 245:** F-31-NN finding ID assignment + severity reclassification + KNOWN-ISSUES.md promotion + regression appendix (Phase 246 FIND-01..03 + REG-01..02); per-commit adversarial audit of EVT/RNG/QST/GOX buckets (Phase 244, FINAL at cc68bfc7); delta-surface catalog edits (Phase 243 `audit/v31-243-DELTA-SURFACE.md` is FINAL READ-only per D-20 carry).

</domain>

<decisions>
## Implementation Decisions

### Plan Split & Wave Topology
- **D-01 (2 plans — one per REQ bucket, matches ROADMAP "Plans: TBD" flexibility + 244 D-01 per-bucket precedent):** Mirrors Phase 244's 1-plan-per-commit-bucket shape adapted to Phase 245's 2-bucket scope (SDR = new-surface deep sub-audit; GOE = pre-existing-invariant re-verify).
  - `245-01-PLAN.md` SDR — SDR-01..SDR-08 (8 REQs) → contributes `audit/v31-245-SDR.md` working file → consumes Phase 244 `§Phase-245-Pre-Flag` bullets 1-9 (SDR-grouped) as advisory
  - `245-02-PLAN.md` GOE — GOE-01..GOE-06 (6 REQs) → contributes `audit/v31-245-GOE.md` working file → consumes Phase 244 `§Phase-245-Pre-Flag` bullets 10-17 (GOE-grouped) as advisory; 245-02 ALSO owns final consolidation of `audit/v31-245-SDR-GOE.md` (both bucket files + Consumer Index + Reproduction Recipe Appendix) per D-05 carry from 244-04's consolidation role
- **D-02 (single-wave parallel — both 245-01 and 245-02 concurrent):** SDR and GOE are scope-disjoint at the row-data level (SDR audits NEW `pendingRedemptionEthValue` + sDGNRS redemption lifecycle; GOE re-verifies pre-existing v24.0/v11.0/F-29-04 invariants against the delta). Plan 245-02 GOE consolidation task naturally lands after 245-01 SDR working file is committed because the terminal consolidation task assembles both bucket files at SUMMARY-commit time — matches 244-04's role exactly. Single-wave parallel honors the user directive carried through 238/244: "run all the parallel shit you can."
- **D-03 (SDR-01 matrix representation — per-REQ re-walk, no mega-matrix):** SDR-01 enumerates 6 redemption-state-transition timings (a-f per REQUIREMENTS.md). Rather than a monolithic 6-timings × 8-REQs matrix (48 rows), each of SDR-02..08 re-walks the 6 timings within its own verdict table. SDR-01 itself produces a foundation enumeration (6 timing rows identifying the reachable transition sequences + gameover-latch point per timing); SDR-02..08 cite back to SDR-01 row IDs as shared-context but produce their own verdicts per timing × REQ cell. Cleaner grep per REQ (a Phase 246 reviewer can grep "SDR-04" and see every verdict without untangling mega-matrix cells). Matches 244 D-07's per-REQ closure pattern.

### Deliverable Shape
- **D-04 (single consolidated `audit/v31-245-SDR-GOE.md`):** Matches Phase 230 D-05 / Phase 237 D-08 / Phase 243 D-07 / Phase 244 D-04 single-file precedent. 4 sections:
  1. SDR — SDR-01 timing-matrix foundation + SDR-02..08 per-REQ verdict tables + finding-candidate blocks
  2. GOE — GOE-01..06 per-REQ RE_VERIFIED_AT_HEAD verdict tables + finding-candidate blocks (if any) + GOE-06 emergent-behavior closures for the 2 Pre-Flag candidates
  3. Consumer Index — v31.0 REQ-ID (SDR-01..GOE-06) → Phase 245 verdict-row mapping + cross-ref to source D-243-X/F/C/S row IDs from v31-243-DELTA-SURFACE.md §6 + Phase 244 V-row cross-ref where shared-scope (e.g., SDR-06 shares State-1 revert coverage with GOX-02)
  4. Reproduction recipe appendix — all `git show -L` / `grep` / reach-path enumeration commands concatenated for reviewer replay (POSIX-portable per D-22 carry)
- **D-05 (per-plan working file pattern with consolidation in 245-02, matches 244 D-05 exactly):** Each plan writes its bucket section to a working file (`audit/v31-245-SDR.md`, `audit/v31-245-GOE.md`) during execution. The terminal plan in the wave (245-02 GOE, smaller REQ count but owns consolidation per D-01) consolidates both bucket files into `audit/v31-245-SDR-GOE.md`, appends Consumer Index + reproduction recipe, and flips it FINAL READ-only at SUMMARY commit (frontmatter `status: FINAL — READ-ONLY`). Working files remain on disk as appendices (cross-ref only, not deleted).
- **D-06 (tabular 8-column verdict format — 244 D-06 carry):** Per-REQ verdict columns: `Verdict Row ID | REQ-ID | Source Row(s) | File:Line | Adversarial Vector | Verdict | Evidence | Owning Commit SHA`. `Source Row(s)` cites both Phase 244 V-rows (EVT-NN-V##, RNG-NN-V##, QST-NN-V##, GOX-NN-V##) AND Phase 243 D-243-X/F/C/S rows AND — for GOE — prior-milestone artifacts (Phase 239 RNG rows, Phase 240 GO-240-NNN rows, v24.0 / v11.0 as corroborating per D-17 discipline). One row per REQ × adversarial vector × timing (multiple vectors per REQ produce multiple rows; per-REQ closure aggregation in a separate REQ-summary table). Finding-candidate prose blocks follow the table per bucket section.

### Verdict Taxonomy & Cross-REQ Overlap
- **D-07 (per-REQ closure with explicit shared-row cross-cite — 244 D-07 carry):** Many SDR REQs share adversarial vectors (e.g., SDR-02/SDR-05 both walk the per-wei conservation; SDR-04/SDR-06 both touch State-1 revert coverage). Each REQ gets its own verdict block — re-read same code through each REQ's adversarial lens, even if duplicative. Where two REQs share a vector exactly, the second REQ's verdict cell may cross-cite the first row's evidence with explicit `(see Verdict Row ID SDR-NN-V##)` reference instead of full re-derivation. Phase 244 V-rows are citable as shared-context (e.g., SDR-06 State-1 revert enumeration cross-cites GOX-02-V01/V02/V03 as primary evidence).
- **D-08 (per-REQ verdict from the 6-bucket taxonomy, 244 D-08 carry):** Every audited REQ receives a closed verdict `{SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL}`. KI exception rows (GOE-01 F-29-04 envelope check; SDR-08 `_gameOverEntropy` fallback interaction with EXC-03) use `RE_VERIFIED_AT_HEAD cc68bfc7` annotation, NOT a verdict bucket — envelope-non-widening checks only per D-22 carry. Discrimination bar same as 244 D-08; severity classification follows v29.0 Phase 236 D-04 / v30.0 Phase 242 D-05 calibration.

### claimRedemption Ungated State (Gray Area 1 — user-selected)
- **D-09 (property-to-prove SAFE, no standalone INFO finding-candidate):** Per 244 Pre-Flag L2477, `StakedDegenerusStonk.sol:618 claimRedemption()` is NOT gated by `livenessTriggered()` or `gameOver()` — it is the back-half of the 2-step redemption flow with implicit gate `redemptionPeriods[claim.periodIndex].roll != 0`. This is absorbed into SDR-01 (matrix foundation: claimRedemption reachable in all 3 states by design), SDR-04 (DOS/starvation/race vectors), and SDR-05 (per-wei conservation: ETH was already segregated into `pendingRedemptionEthValue` on the front-half request, so the back-half is an OUT-only lookup against a known ledger). Each of SDR-01/04/05 enumerates the adversarial vectors explicitly and confirms the `roll != 0` implicit gate holds under all attacker models (player / admin / validator / VRF oracle per 238 D-07 4-actor taxonomy). No standalone `SEVERITY: INFO` finding-candidate is emitted — the ungated-but-intentional shape is a property proven SAFE, not a convention drift worth flagging. Rationale: the implicit `roll != 0` gate is algorithmically load-bearing (a redemption cannot claim what has not been resolved), not a convention accident. If a future patch breaks the implicit invariant, Phase 246 REG-01 regression coverage catches it. Matches 244 D-07 per-REQ closure philosophy (audit trail stays clean of hedged observations).

### Per-Wei Accounting Rigor (Gray Area 2 — user-selected)
- **D-10 (prose + spot-check format — 244 style):** SDR-02 `pendingRedemptionEthValue` accounting exactness + SDR-05 per-wei ETH conservation across all 6 gameover timings use verdict blocks with prose evidence citing specific code lines + one worked example per timing showing wei-in == wei-out. Matches Phase 244's depth exactly (prose + code citation + argument-trace). Rigor bounded by exhaustiveness of prose — reviewer-scannable, grep-friendly, fast to produce.
- **D-11 (concrete methodology for per-wei proofs):** Each SDR-02 / SDR-05 verdict row enumerates (a) the ENTRY site where wei enters `pendingRedemptionEthValue` (e.g., `_submitGamblingClaim*` paths); (b) every POSSIBLE EXIT site (roll-adjustment at `resolveRedemptionPeriod` sDGNRS:585-593 / claim payout at `claimRedemption` sDGNRS:619-700 / drain subtraction at `handleGameOverDrain` GameOverModule:94 + :157 / final-sweep interaction at `handleFinalSweep` GameOverModule:196-216 / `_deterministicBurnFrom` subtraction at sDGNRS:535 for post-gameOver deterministic-burn accounting); (c) per-timing which exit path fires and whether the wei reaches claimer OR returns to pool (exactly one exit per entry invariant); (d) one worked example per timing showing the ledger closes (entry wei = sum of exits). Formal invariant-lemma style is deferred to a future milestone if Phase 246 reviewer finds prose-style insufficient (see D-28 Deferred Ideas).

### GOE-06 Emergent-Behavior Depth (Auto-decided per 244 precedent)
- **D-12 (close the 2 Phase-244-Pre-Flag candidates, no exhaustive sweep):** Phase 244 `§Phase-245-Pre-Flag` bullets 16 + 17 (L2518-2519 of v31-244-PER-COMMIT-AUDIT.md) pre-flag 2 GOE-06 candidates:
  - **Candidate 1:** cc68bfc7 BAF skipped-pool preservation in futurePool × `handleGameOverDrain` subtraction interaction — does the skipped-BAF pool get correctly swept by drain, or stranded?
  - **Candidate 2:** `burnWrapped` divergence (`livenessTriggered() && !gameOver()` at sDGNRS:507) — a player holding DGNRS wrapper tokens at liveness retains them for post-gameOver deterministic-burn; verify DGNRS wrapper supply ↔ sDGNRS wrapper-held backing conservation across State-0/1/2 transitions.
  Phase 245 GOE-06 closes these 2 candidates with closed verdicts. Exhaustive negative-space sweep (construct cross-feature scenarios from scratch) is deferred — if either of the 2 pre-flagged candidates produces a non-SAFE verdict, the sweep expands in-place; if both close SAFE, exhaustive sweep is deferred to Phase 246 FIND-01 / a future milestone (see D-28). Rationale: 3-5x audit-time cost for exhaustive-sweep not justified unless the 2 pre-flagged candidates surface real issues; matches Phase 244 D-02 cost-effective rigor philosophy.
- **D-13 (GOE-06 verdict taxonomy):** Each of the 2 candidates ends in closed verdict `{SAFE / INFO / LOW / MEDIUM / HIGH / CRITICAL}`. Combined GOE-06 REQ-closure verdict = worst of the 2 individual candidate verdicts (GOE-06 is "NEW edge case" aggregate — any surfaced emergent-behavior issue is a REQ-level floor). If either candidate escalates to MEDIUM+, Phase 245 expands GOE-06 scope in-place to sweep adjacent scenarios (bounded to the specific cross-feature triple touched by the escalated candidate).

### Methodology Per Plan

#### SDR (245-01)
- **D-14 (SDR adversarial vectors — planner MUST cover at minimum):**
  - **SDR-01:** (a) enumerate all 6 gameover-timing transitions (a) pre-liveness all 3 steps / (b) request pre-liveness, resolve/claim in State-1 / (c) request pre-liveness, resolve State-1, claim post-gameOver / (d) resolved pre-gameOver, claim post-gameOver / (e) request post-gameOver blocked / (f) VRF-pending at liveness, resolves via `_gameOverEntropy` fallback; (b) per-timing identify the reachable code paths (burn → submitGamblingClaim → resolveRedemptionPeriod → claimRedemption OR handleGameOverDrain sweep); (c) per-timing identify the gameover-latch point (which STATE transition latches gameOver); (d) foundation rows consumed by SDR-02..08 as shared-context
  - **SDR-02:** (a) per-entry-site exact accounting (`_submitGamblingClaim*` adds wei; `resolveRedemptionPeriod` adjust-by-roll at sDGNRS:593 — `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth`); (b) per-exit-site exact accounting (`claimRedemption` sDGNRS:619-700 subtract-on-payout; `handleGameOverDrain` GameOverModule:94 + :157 subtract-on-drain-subtract; `_deterministicBurnFrom` sDGNRS:535 subtract-from-payout-base); (c) one worked example per timing showing ledger closes (no dust, no overshoot)
  - **SDR-03:** (a) confirm `handleGameOverDrain` reads `pendingRedemptionEthValue()` (not a snapshot) at L94 AND L157 (pre- and post-refund loop); (b) confirm 33/33/34 split math at `_sendToVault` GameOverModule:225-233 operates on L158 `available` (post-subtraction); (c) enumerate multi-tx drain edges (STAGE_TICKETS_WORKING partial drain, L80 `GO_JACKPOT_PAID` idempotency bit) — prove no path re-enters drain in a way that double-subtracts OR skips subtraction
  - **SDR-04:** (a) DOS vectors — can any actor (player / admin / validator / VRF oracle) force `claimRedemption` to revert, stall, or miscompute?; (b) starvation — can the 30-day `handleFinalSweep` window close before a claimer can call?; (c) underflow — does any path decrement `pendingRedemptionEthValue` below the claimer's entitlement?; (d) race vs 30-day sweep — prove no ordering between drain + claim + sweep leaves wei stranded
  - **SDR-05:** (a) per-timing ledger close (each of the 6 timings from SDR-01); (b) one worked example per timing showing `sum(ENTRIES) == sum(EXITS)` invariant; (c) cross-cite SDR-02 entry/exit enumeration for the wei-level primitives
  - **SDR-06:** (a) enumerate every reach-path to `_submitGamblingClaim*` (burn entry at sDGNRS:486-516, burnWrapped entry at :506-516, cross-chain forward-import if applicable, admin paths, constructor paths); (b) prove each path has the `BurnsBlockedDuringLiveness` error at State-1 (livenessTriggered && !gameOver); (c) cross-cite Phase 244 GOX-02-V01/V02/V03 which already closed the reach-path enumeration at 244 depth — 245 SDR-06 may dig DEEPER into negative-space (e.g., admin-triggered `purchaseStartDay` manipulation, level transitions mid-window per Pre-Flag bullet 14)
  - **SDR-07:** (a) sDGNRS supply mutations — enumerate `_mint` constructor, `transferFromPool` pool-to-recipient distributions, `burn → _deterministicBurnFrom` L539-541, `burnAtGameOver` L462 (zeros contract balance); (b) prove every sDGNRS token has exactly one mint + at most one burn (no ghost tokens, no dust mint from `transferFromPool` rounding); (c) cross-cite v29.0 / v24.0 supply-conservation proofs as corroborating evidence (RE_VERIFIED_AT_HEAD discipline per D-17)
  - **SDR-08:** (a) `_gameOverEntropy` at AdvanceModule:1263-1296 includes `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` at L1286 — new consumption of fallback entropy on the gameover-path; (b) prove no redemption can hang in pending limbo post-gameOver (fallback resolve reaches every VRF-pending redemption); (c) verify no over-substitution (fallback fires multiple times for same redemption) or under-resolution (fallback skips a pending redemption); (d) cross-cite Phase 244 RNG-01-V11 (EXC-03 envelope disjoint at `_unlockRng` removal scope) — SDR-08 is the NEW consumption site within the same EXC-03 envelope; verify the envelope does NOT widen (SDR-08's `_gameOverEntropy` redemption-resolve path stays within EXC-03's mid-cycle-substitution acceptance boundary)

- **D-15 (SDR-01 matrix foundation row IDs):** SDR-01 produces 6 rows `SDR-01-T{a-f}` (one per timing) that SDR-02..08 cite back. Each SDR-02..08 V-row identifies which of the 6 timings it covers (e.g., `SDR-04-V03` might cite `SDR-01-Te` for the "request post-gameOver blocked" timing). Per-REQ verdict tables list their own V-rows monotonically (`SDR-NN-V##`); the SDR-01 foundation rows use the `SDR-01-T{a-f}` sub-scheme to distinguish them from regular V-rows.

#### GOE (245-02)
- **D-16 (GOE adversarial vectors — planner MUST cover at minimum):**
  - **GOE-01:** (a) F-29-04 RNG-consumer determinism envelope at HEAD cc68bfc7 (mid-cycle ticket-buffer swap → `_gameOverEntropy` substitution); (b) does the new 14-day grace Tier-1 gate at Storage:1242 introduce a NEW way for mid-cycle swap to trigger `_gameOverEntropy` consumption? Enumerate day-14-to-day-120 scenarios where Tier-1 gate fires liveness but day-math has not; (c) cross-cite Phase 244 RNG-01-V11 (envelope check at `_unlockRng` removal scope) — 245 GOE-01 owns the DEEPER 14-day-grace × F-29-04 interaction check; (d) `RE_VERIFIED_AT_HEAD cc68bfc7` annotation per D-22
  - **GOE-02:** (a) 33/33/34 split at `_sendToVault` GameOverModule:225-233 operates on L158 `available` after L94 + L157 subtractions; (b) `handleFinalSweep` 30-day window at L196-216 does NOT re-subtract `pendingRedemptionEthValue` — relies on claimRedemption being called before the window closes; (c) prove 30-day window is SUFFICIENT for all pending redemptions to be claimed (no realistic actor scenario leaves reserved wei stranded); (d) cross-cite v24.0 33/33/34 precedent + Phase 239/240 GO-240 rows as corroborating evidence
  - **GOE-03:** (a) full sweep of all externally-callable functions in Game contracts + modules (DegenerusGame.sol, DegenerusGameMintModule.sol, DegenerusGameWhaleModule.sol, DegenerusGameAdvanceModule.sol, DegenerusGameGameOverModule.sol); (b) for each, verify (i) has `_livenessTriggered` / `gameOver` gate, (ii) is state-read-only, or (iii) is admin-only with safe state mutation; (c) cross-cite Phase 244 GOX-01 (closed the 8-path entry-gate claim — 245 GOE-03 extends to ALL entry points including `_purchaseBurnieLootboxFor` internal callees, `_claim*` paths, admin-only entries)
  - **GOE-04:** (a) matrix of `{day range (1-14, 14-120, 120-365, 365+), level (0, 1-9, 10+), VRF state (healthy, stalled < grace, stalled ≥ grace, intermittent), rngLockedFlag state}` — verify every cell resolves correctly; (b) VRF-available vs prevrandao-fallback branch disjointness at the new 14-day grace; (c) cross-cite Phase 244 GOX-04-V02 (EXC-02 envelope RE_VERIFIED_AT_HEAD at 244 depth) — 245 GOE-04 owns deeper stall-tail enumeration including multi-level transitions where VRF comes back partially
  - **GOE-05:** (a) `gameOverPossible` gate at `_purchaseCoinFor` MintModule:894 (BURNIE ticket blocking); (b) 771893d1 did NOT change `gameOverPossible` logic, but SHIFT to `_livenessTriggered` at MintModule:890 means `gameOverPossible` now fires AFTER liveness — verify ordering correctness (no State-1 caller bypasses `gameOverPossible` because they're already rejected at L890); (c) enumerate all paths to a BURNIE ticket purchase to ensure the gate remains effective; (d) cross-cite v11.0 original BURNIE gate spec + Phase 244 GOX-01 entry-gate enumeration
  - **GOE-06:** (a) close the 2 Pre-Flag candidates per D-12 (skipped-BAF-pool × drain interaction; DGNRS wrapper ↔ sDGNRS wrapper-held-backing conservation across State-0/1/2); (b) if either candidate escalates ≥ MEDIUM, expand sweep in-place per D-13; (c) otherwise both SAFE = GOE-06 SAFE floor; deeper exhaustive sweep deferred to Phase 246 / future milestone per D-12

- **D-17 (RE_VERIFIED_AT_HEAD methodology carry from 240 D-17 + 244 D-22):** Every GOE verdict re-derived at HEAD `cc68bfc7` from `contracts/` primitives. Cross-cites prior-milestone artifacts as corroborating evidence only, never as sole warrant:
  - Phase 243 `audit/v31-243-DELTA-SURFACE.md` — FINAL scope anchor (D-20 carry); all GOE verdicts cite relevant D-243-C/F/X/S/I rows
  - Phase 244 `audit/v31-244-PER-COMMIT-AUDIT.md` — FINAL per-commit verdict catalog (D-24); GOE verdicts cite relevant V-rows (EVT-NN-V## / RNG-NN-V## / QST-NN-V## / GOX-NN-V##) for shared-scope context
  - Phase 240 `audit/v30-GAMEOVER-JACKPOT-SAFETY.md` — GO-240-NNN rows for GOE-04 VRF-available branch determinism
  - Phase 239 `audit/v30-RNGLOCK-STATE-MACHINE.md` + `audit/v30-ASYMMETRY-RE-JUSTIFICATION.md` — rngLockedFlag + phase-transition-gate for GOE-01 / GOE-04
  - Phase 238 `audit/v30-FREEZE-PROOF.md` — 19-row Gameover-Flow Freeze-Proof Subset for GOE-01 / GOE-04
  - `audit/KNOWN-ISSUES.md` — EXC-01..04 for GOE-01 / GOE-04 envelope framing
  - v24.0 claimablePool 33/33/34 split spec for GOE-02
  - v11.0 BURNIE endgame gate spec for GOE-05
  - v29.0 Phase 232.1 / Phase 235 F-29-04 commitment-window trace for GOE-01 envelope

### Phase 246 Hand-Off
- **D-18 (245-02 pre-flags Phase 246 FIND-01..FIND-03 candidates as a dedicated section):** When Phase 245 SDR/GOE work surfaces a finding candidate (any verdict ≠ SAFE/RE_VERIFIED_AT_HEAD), it is written as a `SEVERITY: <bucket>` prose block in the relevant bucket section. 245-02 aggregates all finding candidates into a "Phase 246 Input" subsection at the end of the consolidated deliverable. Format: `- FIND-01 candidate | SEVERITY: <bucket> | <one-line observation> | <file:line> | <source REQ> | <suggested Phase 246 action>`. Phase 246 FIND-01 (finding-ID assignment) + FIND-02 (severity reclassification with full milestone context) + FIND-03 (KI promotion / Non-Promotion Ledger entry) consume this subsection. If zero finding candidates surface (Phase 245 all-SAFE outcome), the subsection explicitly states "Zero finding candidates emitted — Phase 246 FIND-01 pool from Phase 245 is empty; FIND-02 has no candidates to reclassify; FIND-03 KI delta is zero."
- **D-19 (REFACTOR_ONLY evidence burden carry from 244 D-17 / Phase 243 D-04):** If any Phase 245 plan proves behavioral equivalence between code at baseline `7ab515fe` and head `cc68bfc7` (e.g., SDR-07 supply conservation invariant proof re-derived at both baselines), methodology is side-by-side prose diff naming specific source elements proven byte-equivalent. NOT bytecode-diff — that is Phase 244 QST-05's exclusive methodology. Where REFACTOR_ONLY claim has any doubt, escalate to MODIFIED_LOGIC + separate verdict per 243 D-04 burden-of-proof rule.

### Scope Boundaries
- **D-20 (READ-only scope, no `contracts/` or `test/` writes):** Carries v28/v29/v30/Phase 243 D-22 / Phase 244 D-18 + project-level `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`. Writes confined to `.planning/phases/245-*/` + `audit/v31-245-*.md` files. `KNOWN-ISSUES.md` is NOT touched in Phase 245 — KI promotions / Non-Promotion Ledger are Phase 246 FIND-03 only.
- **D-21 (HEAD anchor `cc68bfc7` locked in every plan frontmatter):** Carries Phase 243 D-03 amended HEAD + Phase 244 D-19 anchor. Every `245-0N-PLAN.md` frontmatter freezes `baseline=7ab515fe`, `head=cc68bfc7`. If any FURTHER new contract commit lands before Phase 245 begins OR mid-execution, baseline resets and Phase 245 may re-open for an addendum (Phase 230 D-06 / Phase 237 D-17 / Phase 243 D-03 / Phase 244 D-19 pattern). Phase 245 plan-start verifies `git diff cc68bfc7..HEAD -- contracts/` is empty before locking frontmatter.
- **D-22 (`audit/v31-243-DELTA-SURFACE.md` + `audit/v31-244-PER-COMMIT-AUDIT.md` are READ-only — scope-guard deferral rule):** Carries Phase 243 D-21 + Phase 244 D-20. If any Phase 245 plan finds a changed function / state-var / event / interface method / call site NOT in the Phase 243 catalog OR a finding not closed in Phase 244, it records a scope-guard deferral in its own plan SUMMARY (file:line + path-family proposal + KI cross-ref if applicable). Upstream artifacts are NOT re-edited in place. Gaps become Phase 246 finding candidates.
- **D-23 (no F-31-NN finding-ID emission — Phase 246 owns it):** Carries Phase 230 D-06 / Phase 237 D-15 / Phase 243 D-20 / Phase 244 D-21 pattern. Phase 245 produces per-REQ verdicts + finding-candidate blocks with `SEVERITY: <bucket>` annotations; Phase 246 FIND-01 assigns F-31-NN IDs and FIND-02 may re-classify severity with full milestone context.
- **D-24 (KI exception RE_VERIFIED_AT_HEAD only — no re-litigation):** Carries Phase 244 D-22. The 4 accepted RNG exceptions per `KNOWN-ISSUES.md` (affiliate non-VRF roll / prevrandao fallback EXC-02 / F-29-04 mid-cycle substitution EXC-03 / EntropyLib XOR-shift EXC-04) are RE_VERIFIED at HEAD `cc68bfc7` for envelope-non-widening only. GOE-01 verifies EXC-03 envelope stays within mid-cycle-substitution acceptance under the new 14-day grace. GOE-04 verifies EXC-02 envelope stays within prevrandao-fallback acceptance under the new grace Tier-1 gate. SDR-08 verifies `_gameOverEntropy` new redemption-resolve consumption does NOT widen EXC-03 past the mid-cycle-substitution boundary. Acceptance is NOT re-litigated; only the envelope is re-verified per Phase 238 D-11 / Phase 241 EXC-01..04 / Phase 244 D-22 pattern.
- **D-25 (Phase 244 Pre-Flag advisory-only, NOT binding):** Phase 244 `§Phase-245-Pre-Flag` (L2470-2521 of v31-244-PER-COMMIT-AUDIT.md, 17 bullets) is ADVISORY input per CONTEXT.md D-16 carry. Phase 245 plans consume the Pre-Flag as pre-derived observation pool but are NOT bound by it — Phase 245 may surface entirely new vectors NOT pre-flagged, AND Phase 245 may close a Pre-Flag observation with a different verdict than the pre-flag's suggested vector (e.g., a Pre-Flag might suggest "Phase 245 should verify X"; Phase 245 may respond "X is verified SAFE via vector Y" OR "X is SAFE by cross-cite to Phase 244 Z, no re-verify needed"). Every Pre-Flag bullet gets a one-line closure note in the relevant bucket section's cross-walk (SAFE / INFO / closed-in-244 / rolled-forward-to-246 / scope-out-of-245).

### Claude's Discretion
- Exact within-section ordering of per-REQ verdict tables vs prose blocks (table-first vs preamble-first per bucket section)
- Whether to inline 245-02 GOE consolidation into 245-02 SUMMARY commit OR a separate `245-02-CONSOLIDATION.md` follow-up artifact (planner may pick either; Phase 243 used a single SUMMARY commit; Phase 244-04 used a dedicated consolidation commit — either matches precedent)
- Whether to include a "per-REQ closure heatmap" at the top of `audit/v31-245-SDR-GOE.md` (REQ × verdict matrix as a readability aid) — optional, not required; Phase 244 did not include one
- SDR-01 foundation-row format — one row per timing (6 rows) vs one row per timing × reachable-path (could expand to 10-15 rows if multiple paths per timing); planner-discretion as long as every timing is covered and each SDR-02..08 V-row can cite back to a specific SDR-01 row
- Severity pre-classification for finding-candidate blocks (if any surface) — Phase 245 may pre-classify `{SAFE / INFO / LOW / MED / HIGH / CRITICAL}` or leave `SEVERITY: TBD-246` for Phase 246; recommended pre-classify per D-08 unless ambiguous (matches 244 Claude's Discretion carry)
- Whether to add a one-line "change count card" at the top of each bucket section (mirroring Phase 244's per-bucket cards) for Phase 246 FIND-01 convenience — planner-discretion, not mandated
- GOE-06 sweep-expansion scope (if triggered per D-13) — planner-discretion on which adjacent cross-feature scenarios to add; bounded to the specific cross-feature triple touched by the escalated candidate
- Phase 246 Input subsection format — bullet-grouped by REQ OR by severity OR by file — planner-discretion as long as every finding candidate has required fields per D-18

</decisions>

<specifics>
## Specific Ideas

- **Per-wei ledger spot-checks**: Each of the 6 timings gets at least one concrete wei example. The user values cost-effective rigor over exhaustive formal proofs (matches Phase 244 QST-05 methodology lock where user chose BYTECODE-DELTA-ONLY over theoretical-gas-WC).
- **claimRedemption treatment**: The user wants this proven SAFE via adversarial enumeration, NOT emitted as a convention-drift INFO. Matches 244 D-07 per-REQ closure philosophy — audit trail stays clean of hedged observations; reviewer sees only verdicts that require action.
- **Phase 244 Pre-Flag consumption**: The 17 advisory bullets at L2470-2521 of v31-244-PER-COMMIT-AUDIT.md are pre-derived observations. Each bullet gets a one-line closure note in Phase 245's bucket cross-walk — NOT re-discovery from scratch.
- **Cross-milestone cross-cites**: GOE plan leans heavily on Phase 238/239/240 + v24.0/v11.0 artifacts for corroborating evidence. Every verdict re-derived fresh at HEAD per D-17 carry, but prior artifacts shorten the argument chain.

</specifics>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Phase 245 scope anchors (MANDATORY — READ-only per D-22)
- `audit/v31-243-DELTA-SURFACE.md` — FINAL READ-only; §6 Consumer Index maps v31.0 REQs to D-243-X/F/C/S rows
- `audit/v31-244-PER-COMMIT-AUDIT.md` — FINAL READ-only; §Phase-245-Pre-Flag at L2470-2521 is ADVISORY input per D-25; V-rows (EVT-NN-V## / RNG-NN-V## / QST-NN-V## / GOX-NN-V##) citable as shared-context evidence
- `audit/KNOWN-ISSUES.md` — 4 accepted RNG exceptions (EXC-01 affiliate / EXC-02 prevrandao fallback / EXC-03 F-29-04 mid-cycle / EXC-04 EntropyLib XOR-shift); envelope RE_VERIFIED_AT_HEAD only per D-24

### Prior milestone corroborating artifacts (per D-17 discipline)
- `.planning/milestones/v30.0-phases/237-consumer-rng-inventory/` — Consumer Index foundation
- `.planning/milestones/v30.0-phases/238-per-consumer-determinism-proof/` — 19-row Gameover-Flow Freeze-Proof Subset
- `.planning/milestones/v30.0-phases/239-rnglock-state-machine/` — rngLockedFlag state-machine + asymmetry re-justification
- `.planning/milestones/v30.0-phases/240-gameover-jackpot-safety/` — GO-240-NNN consumer inventory + VRF-available branch determinism proofs
- `.planning/milestones/v30.0-phases/241-exception-closure/` — EXC-01..04 acceptance
- `.planning/milestones/v29.0-phases/232.1-rng-consumer-audit/` — F-29-04 commitment-window trace
- `.planning/milestones/v29.0-phases/235-trnx-rng/` — `rngLocked` 4-path walk
- v24.0 claimablePool 33/33/34 split + 30-day sweep spec (in PROJECT.md history)
- v11.0 BURNIE endgame gate spec (in PROJECT.md history)

### Phase 245 working files (produced by plans, NOT pre-existing)
- `audit/v31-245-SDR.md` — produced by 245-01; SDR-01 matrix foundation + SDR-02..08 verdict tables
- `audit/v31-245-GOE.md` — produced by 245-02; GOE-01..06 RE_VERIFIED verdict tables + 2 Pre-Flag-candidate closures
- `audit/v31-245-SDR-GOE.md` — produced by 245-02 consolidation task; 4 sections per D-04; flipped FINAL READ-only at 245-02 SUMMARY commit

### Project-level constraints (MANDATORY)
- `/home/zak/Dev/PurgeGame/degenerus-audit/CLAUDE.md` (if exists) — project instructions
- `.planning/PROJECT.md` — core value, evolution rules, milestone history
- `.planning/REQUIREMENTS.md` — SDR-01..08 + GOE-01..06 definitions (lines 72-94)
- `.planning/ROADMAP.md` — Phase 245 Success Criteria SC-1..SC-6
- Project memory: `feedback_no_contract_commits.md`, `feedback_never_preapprove_contracts.md`, `feedback_rng_backward_trace.md`, `feedback_rng_commitment_window.md`, `feedback_wait_for_approval.md`, `feedback_manual_review_before_push.md`, `feedback_no_history_in_comments.md`

### Contract surface references (HEAD cc68bfc7)
- `contracts/StakedDegenerusStonk.sol` — sDGNRS full redemption lifecycle (primary SDR target)
- `contracts/DegenerusStonk.sol` — DGNRS wrapper interaction (GOE-06 wrapper-backing candidate)
- `contracts/modules/DegenerusGameGameOverModule.sol` — `handleGameOverDrain` + `_sendToVault` + `handleFinalSweep`
- `contracts/modules/DegenerusGameAdvanceModule.sol` — `_handleGameOverPath` + `_gameOverEntropy` + `_livenessTriggered` callers
- `contracts/modules/DegenerusGameMintModule.sol` — entry-point gating (GOE-03 + GOE-05)
- `contracts/modules/DegenerusGameWhaleModule.sol` — entry-point gating (GOE-03)
- `contracts/storage/DegenerusGameStorage.sol` — `_livenessTriggered` + `_VRF_GRACE_PERIOD` + slot layout
- `contracts/DegenerusJackpots.sol` — cc68bfc7 BAF-coupling (GOE-06 skipped-BAF-pool × drain candidate)

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- Phase 244 V-row verdict pool (87 rows across 19 REQs, all SAFE floor): Phase 245 cross-cites for shared-scope context
- Phase 244 Pre-Flag subsection (17 bullets): pre-derived observation pool consumed as advisory input per D-25
- Phase 243 Consumer Index §6 (41 D-243-I### rows): REQ-to-source mapping; SDR/GOE verdicts cite back to relevant subsets
- Phase 240 GO-240-NNN gameover-VRF-consumer inventory (19 rows): GOE-04 cross-cite scaffolding

### Established Patterns
- `audit/v31-24N-*.md` naming convention — SDR + GOE working files follow (`audit/v31-245-SDR.md`, `audit/v31-245-GOE.md`, `audit/v31-245-SDR-GOE.md`)
- Per-REQ closure with monotonic V-row IDs (`SDR-NN-V##` / `GOE-NN-V##`) — Phase 244 D-06 / D-07 carry
- 8-column verdict table format — Phase 244 D-06 carry
- FINAL READ-only frontmatter flip at consolidation SUMMARY commit — Phase 243/244 carry
- Cross-cite prior-milestone artifacts as corroborating (never sole warrant) — Phase 240 D-17 carry

### Integration Points
- Phase 246 FIND-01 consumes Phase 245's Phase 246 Input subsection (per D-18)
- Phase 246 FIND-03 consumes KI envelope re-verify outcomes (SDR-08 + GOE-01 + GOE-04) for KI delta decisions
- Phase 246 REG-01 / REG-02 consumes the 6-timing SDR-01 matrix + GOE-06 2-candidate closure as regression-appendix input (if any non-SAFE verdicts surface)

</code_context>

<deferred>
## Deferred Ideas

The following ideas surfaced during analysis but were explicitly deferred from Phase 245 scope:

- **Exhaustive GOE-06 negative-space sweep** — construct cross-feature scenarios from scratch beyond the 2 pre-flagged candidates. Deferred per D-12 unless either pre-flag candidate escalates ≥ MEDIUM. If deferred and Phase 246 reviewer finds GOE-06 under-sampled, defer to a future milestone (e.g., v32.0 cross-feature emergent-behavior enumeration phase).
- **Formal invariant-lemma style for per-wei conservation** — explicit algebraic ∑_ins == ∑_outs proofs for SDR-02 / SDR-05. Deferred per D-10 — user chose prose + spot-check. If Phase 246 reviewer finds prose insufficient, a future milestone could layer the formal ledger on top (READ-only-compatible, just more write-up time).
- **claimRedemption as standalone INFO finding-candidate** — document the ungated entry point as convention-drift INFO. Deferred per D-09 — user chose property-to-prove SAFE. If Phase 246 FIND-02 reclassifies any SDR verdict touching claimRedemption, the convention-drift framing can be added to the FIND-02 rationale without reopening Phase 245.
- **SDR-01 mega-matrix representation** — 6-timings × 8-REQs monolithic table. Deferred per D-03 — user's auto-locked choice was per-REQ re-walk. Mega-matrix could be added as a readability appendix in a future audit-tooling milestone without changing verdicts.
- **Multi-tx drain STAGE_TICKETS_WORKING formal re-entry model** — SDR-03 covers this via prose per D-14; if Phase 246 REG-01 wants a state-machine-style model of drain re-entry, that's a future-milestone candidate.
- **Phase 245 Pre-Flag → Phase 246 FIND-02 severity calibration protocol** — D-18 specifies the hand-off format; if Phase 246 finds the format insufficient, protocol refinement is a future-milestone candidate.

</deferred>

---

*Phase: 245-sdgnrs-redemption-gameover-safety*
*Context gathered: 2026-04-24*
*HEAD anchor: cc68bfc7 (verified zero contracts/ drift at CONTEXT-lock time; current HEAD 333b7420)*
