---
phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria
plan: 02
subsystem: audit
tags: [degenerette, autoResolve, keeper-bounty, flip-credit, attestation, paper-only, BURNIE, ROUTER-05, D-05]

# Dependency graph
requires:
  - phase: v48.0 closure (HEAD 0cc5d10f)
    provides: the byte-identical baseline source tree all attestations grep against
provides:
  - "329-ATTEST-DEGENERETTE-RESOLVE.md — the BATCH-01 attestation half for the load-bearing D-05 family (autoResolve→degeneretteResolve rename + flat ~1-BURNIE re-peg)"
  - "Rename-surface enumeration (D-05a): 2 contract targets + interface-files-ABSENT correction + 5 test files / 57 refs"
  - "D-05f losing-bet-liveness grep-finding: INERT — SAFE (no SURFACE-TO-USER dependency)"
  - "D-05c CORRECTED real-gas net-loss exploitability basis (NOT the 0.5-gwei peg)"
  - "D-05b flat-payment-shape FEASIBLE verdict with pinned IMPL edit targets"
  - "ROUTER-05 non-foldability CONFIRMED (degeneretteBets nested mapping, no O(1) enumeration)"
affects: [329-03 SPEC fold-in, 330 IMPL BATCH-02 rename+re-peg, 331 GAS GAS-06 sanity-check, 332 TST TST-05]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Per-anchor grep-table attestation with MATCH/SHIFTED/ABSENT verdict legend (mirrors v48 325-ATTEST-SWAP.md)"
    - "Load-bearing liveness grep-verification with explicit inert-safe-OR-SURFACE-TO-USER finding"

key-files:
  created:
    - ".planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md"
  modified: []

key-decisions:
  - "Interface-files rename rows are ABSENT/no-op — autoResolve/_autoResolveBet are defined directly on DegenerusGame.sol, NOT in IDegenerusGame/IDegenerusGameModules (corrects the plan's claim; shrinks the rename surface)"
  - "D-05f finding = INERT, SAFE: no path requires losing Degenerette bets resolved; the delete :634 is local-idempotency-only; GameOver/Jackpot/Advance grep-CLEAN of degeneretteBets (0 hits each)"
  - "D-05c basis is REAL prevailing gas (5–50+ gwei), explicitly NOT the 0.5-gwei AUTO_GAS_PRICE_REF peg — net loss at every realistic gas price"

patterns-established:
  - "When a plan claims an interface-signature rename target, grep the interface files first — a directly-defined external/self-call fn has no interface row"

requirements-completed: [BATCH-01]

# Metrics
duration: 14min
completed: 2026-05-26
---

# Phase 329 Plan 02: DEGENERETTE-RESOLVE Attestation Summary

**Grep-attested the load-bearing D-05 family (autoResolve→degeneretteResolve rename + flat ~1-BURNIE "lose" re-peg) at v48.0-closure HEAD `0cc5d10f`: rename surface fully enumerated (with an interface-files-ABSENT correction), the D-05f losing-bet-liveness question answered from source as INERT-SAFE (no SURFACE-TO-USER), the D-05c exploitability basis re-derived against REAL gas as a net-loss, the D-05b flat-payment shape proven FEASIBLE, and ROUTER-05 non-foldability CONFIRMED — zero `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~14 min
- **Started:** 2026-05-26 (worktree agent-a0de40ca353ad5ec2)
- **Completed:** 2026-05-26
- **Tasks:** 2
- **Files modified:** 1 created (the ATTEST doc), 0 contracts

## Accomplishments
- **Section A (rename surface, D-05a):** enumerated the only 2 contract rename targets (`autoResolve` `DegenerusGame.sol:1587` → `degeneretteResolve`; `_autoResolveBet` :1684 → `_degeneretteResolveBet`) + the self-call site :1606; **CORRECTED the plan**: the interface-file rename rows are ABSENT (`grep -rln autoResolve contracts/interfaces/` → ZERO — both are defined directly on `DegenerusGame.sol`, never via `IDegenerusGame`/`IDegenerusGameModules`); enumerated all 5 test files / 57 references incl. the `CrankLeversAndPacking.t.sol` literal source-string assertions (:277/:290/:381/:415) that BREAK without atomic update. AUTO-02 probe / per-item try-catch / WWXRP `currency==3` exclusion / self-resolve / one-creditFlip-CEI-last all grep-confirmed PRESERVED (D-05d).
- **Section B (payment-shape feasibility, D-05b):** FEASIBLE verdict — flat ~1 BURNIE (1e18) once/tx, ≥3-NON-WWXRP success gate, revert `NoWork()` at 0, resolve-always-pay-at-≥3-revert-only-at-0 lean are all expressible on the current `:1587-1622` per-item loop (per-item-accumulate → count-and-flat-pay-at-≥3). Pinned IMPL edit targets (remove peg :1611-1614, swap :1622 to flat+gate+revert); exact literal deferred to GAS (D-05e).
- **Section C (real-gas basis, D-05c):** NET-LOSS — 1 BURNIE ≤ `mintPrice/1000` ≤ 0.00024 ETH (derived by inverting `PRICE_COIN_UNIT = 1000 ether`, `DegenerusAdmin.sol:393`) AND illiquid (coinflip flip-credit, not ETH) vs REAL prevailing gas (≥220k for the ≥3 minimum × 5–50+ gwei = 0.0011–0.011+ ETH = ~4.6–46× the peg). Stated EXPLICITLY the basis is REAL gas, NOT the 0.5-gwei `AUTO_GAS_PRICE_REF` peg (USER-corrected). GAS-06 sanity-check handed to Phase 331 (D-05e, not a blocker).
- **Section D (losing-bet liveness, D-05f — the load-bearing deliverable):** PERFORMED the grep-verification. Enumerated all 8 `degeneretteBets` consumers (Storage:1449 decl + submission :526 + read :605 + delete :634 + AUTO-02 :1596 + per-item :1601 + view :2319) with a per-row require-resolved verdict — every one treats an unresolved losing bet as INERT cruft; the `delete` :634 is local-idempotency-only (the `packed==0` revert + AUTO-02 probe), nothing consumes it. GameOver/Jackpot/Advance modules are grep-CLEAN of `degeneretteBets` (0 hits each); no outstanding-bet counter / per-day tally / require-empty anywhere. **FINDING: inert — safe; SURFACE-TO-USER NONE.** Flat reward mildly IMPROVES backlog liveness (clears the whole backlog per paid tx).
- **Section E (non-foldability, ROUTER-05):** CONFIRMED — `degeneretteBets` is a nested mapping (`Storage:1449`) with no O(1) enumeration and no pending-count sidecar; on-chain discovery is impossible-or-unbounded (ROUTER-04 violation), so `degeneretteResolve` stays a SEPARATE caller-supplied-arrays call. The unified one-button is a frontend concern.

## Task Commits

Each task was committed atomically:

1. **Task 1: rename surface + payment-shape feasibility + non-foldability (A/B/E)** - `d10dbd87` (docs)
2. **Task 2: D-05f losing-bet-liveness grep-verification + D-05c real-gas basis (C/D + Roll-up)** - `5c473bf6` (docs)

**Plan metadata:** this SUMMARY commit (docs: complete plan)

## Files Created/Modified
- `.planning/phases/329-spec-design-lock-call-graph-attestation-4-structural-invaria/329-ATTEST-DEGENERETTE-RESOLVE.md` - the BATCH-01 D-05-family attestation (sections A/B/C/D/E + Verdict legend + Roll-up; byte-identical-to-0cc5d10f header)

## Decisions Made
- **Interface-files rename rows are ABSENT (no-op):** the plan `<interfaces>` and CONTEXT D-05a both assumed an `IDegenerusGame`/`IDegenerusGameModules` signature to rename; grep proved none exists. `autoResolve` is defined directly on `DegenerusGame.sol` and called as `game.autoResolve(...)` (concrete-type); `_autoResolveBet` is a `this._autoResolveBet(...)` self-call. This SHRINKS the BATCH-02 rename surface and removes a false IMPL target. Recorded as the ABSENT verdict in §A.2.
- **D-05f answered as INERT-SAFE from source:** no `degeneretteBets` consumer requires a losing bet's `delete` to fire; the three flagged candidate modules (GameOver/Jackpot/Advance) are all grep-CLEAN. No SURFACE-TO-USER block emitted (correctly — none warranted).
- **D-05c re-derived against REAL gas** per `feedback_bounty_exploit_uses_real_gas_not_peg_ref`, NOT the 0.5-gwei peg ref.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Bug / source-of-truth correction] Plan's interface-file rename targets do not exist**
- **Found during:** Task 1 (Section A rename-surface enumeration)
- **Issue:** The plan `<interfaces>` block and CONTEXT D-05a both asserted that `autoResolve`/`_autoResolveBet` signatures live in `IDegenerusGame.sol` + `IDegenerusGameModules.sol` and must be renamed there. Grep (`grep -rln "autoResolve\|_autoResolveBet" contracts/interfaces/`) returns ZERO matches.
- **Fix:** Recorded the verdict as **ABSENT** in §A.2 with the grep evidence and the explanation (directly-defined external + `this.`-self-call resolve against the concrete contract ABI, not an imported interface). Explicitly noted BATCH-02 must NOT add/chase an interface edit here. This is an attestation correction, not a code change.
- **Files modified:** `329-ATTEST-DEGENERETTE-RESOLVE.md` (§A.2)
- **Verification:** `grep -rln "autoResolve\|_autoResolveBet" contracts/interfaces/` → 0; only `DegenerusGame.sol` defines the two symbols.
- **Committed in:** `d10dbd87` (Task 1 commit)

---

**Total deviations:** 1 auto-fixed (1 source-of-truth correction caught by grep-attestation — exactly the job of this paper-only plan).
**Impact on plan:** The correction shrinks the rename surface (one fewer edit class for BATCH-02). No scope creep; all D-05 attestation objectives met.

## Issues Encountered
- `.planning/` is gitignored (per `feedback_contract_commit_guard_hook`); used `git add -f` to force-add the planning docs. STATE.md/ROADMAP.md intentionally NOT modified (orchestrator owns those in worktree mode). No `contracts/*.sol` touched, so the commit-guard hook was never engaged.

## User Setup Required
None - paper-only attestation, no external service configuration.

## Next Phase Readiness
- **For Plan 03 (329-SPEC fold-in):** all five D-05 attestations are ready to fold into `329-SPEC.md` — rename surface (note the interface-ABSENT correction), the inert-safe D-05f finding, the D-05c net-loss basis, the D-05b feasibility + pinned edit targets, and the ROUTER-05 non-foldability.
- **For Plan 330 (IMPL BATCH-02):** rename targets pinned (`DegenerusGame.sol:1587`/`:1684`/`:1606` only — NO interface edit); re-peg edit targets pinned (remove :1611-1614, swap :1622); the 5 test files / source-string assertions to update atomically are enumerated; `AUTO_RESOLVE_BET_GAS_UNITS` :1545 likely goes dead (IMPL housekeeping).
- **For Plan 331 (GAS GAS-06):** the D-05e sanity-check is handed off — confirm the literal ~1 BURNIE stays sub-real-gas across the gas-band; NOT a blocker.
- **No blockers. No SURFACE-TO-USER dependency.**

## Self-Check: PASSED

- FOUND: `329-ATTEST-DEGENERETTE-RESOLVE.md`
- FOUND: `329-02-SUMMARY.md`
- FOUND commit `d10dbd87` (Task 1 A/B/E)
- FOUND commit `5c473bf6` (Task 2 C/D + Roll-up)
- FOUND commit `e5284e67` (SUMMARY)
- `git diff --name-only 0cc5d10f HEAD -- 'contracts/*.sol'` → EMPTY (zero contracts mutation)

---
*Phase: 329-spec-design-lock-call-graph-attestation-4-structural-invaria*
*Completed: 2026-05-26*
