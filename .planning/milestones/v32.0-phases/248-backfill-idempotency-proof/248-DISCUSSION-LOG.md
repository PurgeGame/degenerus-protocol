# Phase 248: Backfill Idempotency Proof - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md — this log preserves the alternatives considered.

**Date:** 2026-05-01
**Phase:** 248-backfill-idempotency-proof
**Areas discussed:** Proof rigor + 251 boundary

---

## Gray-Area Selection

| Option | Description | Selected |
|--------|-------------|----------|
| Plan topology | Single-plan multi-task vs split (e.g., BFL-01..04 mechanics + BFL-05..06 envelope/conservation) | |
| Proof rigor + 251 boundary | Symbolic-only / +forge fuzz / hybrid; cross-phase test boundary with Phase 251 TST-04 | ✓ |
| Row-ID + verdict scheme | V-row pattern from v31 Phase 244 vs alternative shapes; 3-bucket vs 2-bucket verdicts | |
| EXC-02/EXC-03 RE_VERIFY shape (BFL-05) | Dual-carrier attestation (v31) vs single envelope verdict per EXC vs per-trigger-condition | |

**User's choice:** Proof rigor + 251 boundary

**Notes:** The 3 unselected areas default-inherited silently per CONTEXT.md:
- Plan topology → Single-plan multi-task (D-248-11; v32 Phase 247 / v30 Phase 242 / v31 Phase 246 carry-forward)
- Row-ID + verdict scheme → V-row `BFL-NN-VMM` with 3-bucket {SAFE, EXCEPTION, FINDING_CANDIDATE} (D-248-12; v31 Phase 244 carry-forward)
- EXC envelope methodology → Dual-carrier attestation rows (D-248-13; v31 SDR-08 / GOE-01 / GOE-04 carry-forward)

---

## Proof rigor + 251 boundary

### Q1 — Test home for the multi-day VRF stall + backfill double-execution reproduction

| Option | Description | Selected |
|--------|-------------|----------|
| Phase 251 only (recommended) | Phase 248 = pure-proof phase; BFL-03 worked example is a symbolic / algebraic state-transition walk only; Phase 251 TST-04 owns all forge / hardhat reproduction per D-247-02; Phase 248 hands a test-stub design into Phase 251 | ✓ |
| Phase 248 + Phase 251 (hybrid) | Phase 248 ships forge invariant test alongside symbolic proof; Phase 251 covers same scenario via hardhat e2e — belt-and-suspenders but duplicates work and breaks D-247-02 phase-shape boundary | |
| Phase 248 forge test only | Phase 248 ships forge test; Phase 251 TST-04 says "covered by Phase 248" — tightens proof-test pairing but breaks D-247-02 contracts/-only-Phase-247 / test/-only-Phase-251 lock | |

**User's choice:** Phase 251 only (recommended)

**Notes:** Mirrors v31 phase-244 (proof) → phase-246 (test) split. Captured as D-248-05 + D-248-06 in CONTEXT.md. Phase 248 deliverable's `## Phase 251 TST-04 Hand-Off` section provides test-stub design (sketch + expected pre-fix / post-fix behavior + suggested file name). Phase 251 plan reads this hand-off as scope input for TST-04.

---

### Q2 — Representation of BFL-03 (multi-day VRF stall worked example) and BFL-04 (dailyIdx ↔ rngWordByDay[idx] ↔ _unlockRng invariant)

| Option | Description | Selected |
|--------|-------------|----------|
| State-transition table (recommended) | Tabular grep-friendly per-call rows for BFL-03 + per-write-site invariant rows for BFL-04 — matches v31 / v30 / Phase 247 tabular-no-mermaid pattern | ✓ |
| Algebraic walk + lemma chain | Prose-style algebraic walk for BFL-03; lemma chain for BFL-04 — more rigorous but harder to grep / scan | |
| Hybrid | BFL-03 as state-transition table; BFL-04 as lemma chain — mix matches the question shapes | |

**User's choice:** State-transition table (recommended)

**Notes:** Captured as D-248-07 in CONTEXT.md. BFL-03 columns: `Step | block.timestamp | day | dailyIdx | rngLockedFlag | rngRequestTime | currentWord | rngWordByDay[idx+1] | guard verdict | purchaseStartDay (post) | gapDays (post) | _backfillGapDays called?`. BFL-04 columns: `Site (file:line) | Function | Write | Guard preconditions | Holds dailyIdx-only-advances-inside-_unlockRng? | Holds rngWordByDay[idx+1]-is-correct-sentinel?` with verdicts in {HOLDS, VIOLATES, FINDING_CANDIDATE}. Use testnet block numbers 10759449 + 10761786 as concrete BFL-03 seed.

---

### Q3 — BFL-02 enumeration scope for state writes the new guard skips on re-entry

| Option | Description | Selected |
|--------|-------------|----------|
| Whole guarded fresh-word branch (recommended) | Enumerate every state write inside `if (day > idx + 1 && rngWordByDay[idx + 1] == 0)` block (L1174-1186) — _backfillGapDays writes + _backfillOrphanedLootboxIndices + purchaseStartDay increment + gapDays assignment | ✓ |
| _backfillGapDays body only | Strictly L1752-1773 — tighter scope but misses the testnet-bug-trigger purchaseStartDay write at L1184 | |
| Whole rngGate fresh-word branch | Includes always-executed writes (_applyDailyRng / quests / sdgnrs / _finalizeLootboxRng) — broader but mis-classifies always-executed writes as "guard-protected" | |

**User's choice:** Whole guarded fresh-word branch (recommended)

**Notes:** Captured as D-248-09 in CONTEXT.md. The `purchaseStartDay += gapCount` at L1184 sits OUTSIDE `_backfillGapDays` but is the literal testnet-bug-trigger write (REQUIREMENTS.md trigger context: "doubling purchaseStartDay"). Restricting BFL-02 to the function body would miss it. Always-executed writes (`_applyDailyRng`, `quests.rollDailyQuest`, `sdgnrs.resolveRedemptionPeriod`, `_finalizeLootboxRng`) are recorded as "OUT-of-scope-by-construction" rows so the boundary is visibly deliberate.

---

### Q4 — External-call boundary handling for BFL-02 + BFL-06

| Option | Description | Selected |
|--------|-------------|----------|
| Boundary record + behavioral cite (recommended) | Single boundary write row per external call with one-line semantic cite; BFL-06 walks into BurnieCoinflip storage writes only enough for per-call ETH-pool credit math; non-delta-surface conservation NOT re-litigated per OUT OF SCOPE | ✓ |
| Walk every callee | Enumerate every storage write inside processCoinflipPayouts + nested calls — most rigorous but blows up row count and duplicates v25/v29 BurnieCoinflip audits | |
| Boundary record only — no behavioral cite | Single line per external call without per-callee semantic detail; loses the ETH-coinflip-pool conservation arithmetic the testnet bug actually triggered | |

**User's choice:** Boundary record + behavioral cite (recommended)

**Notes:** Captured as D-248-10 in CONTEXT.md. v25/v29/v30/v31 already proved coinflip-pool conservation; v32.0 OUT OF SCOPE confirms "ETH/BURNIE/sDGNRS/DGNRS conservation on non-delta surfaces — covered in v25.0/v29.0/v30.0/v31.0; not re-proven globally."

---

### Q5 — BFL-01 path enumeration: how to cover the 3 advanceGame entry paths from Phase 247 D-247-X027..X029

| Option | Description | Selected |
|--------|-------------|----------|
| Single rngGate walk + 3-path multiplier (recommended) | One state-transition table walks rngGate fresh-word branch reachability (path-invariant); separate 1-row attestation notes 3 advanceGame entry paths funnel into the same dispatcher | ✓ |
| Per-entry-path table | Three tables, one per entry path — more rigorous but ~3× row count for the same inner proof; entry-path preconditions don't change which rngGate branch fires | |
| Per-entry-path summary card | One main rngGate table + 3-row summary card listing each entry path's preconditions — compromise that documents non-widening of outer preconditions | |

**User's choice:** Single rngGate walk + 3-path multiplier (recommended)

**Notes:** Captured as D-248-08 in CONTEXT.md. rngGate's branch selection is purely on `rngWordByDay[day]` / `currentWord` / `rngRequestTime`, none of which the 3 entry paths (DegenerusGame:289 delegatecall + Vault:503 cross-contract + sDGNRS:355 cross-contract) set differently — so the inner proof is path-invariant.

---

## Claude's Discretion

Captured under `<decisions>` "Claude's Discretion" subsection in CONTEXT.md:

- Final section ordering within `audit/v32-248-BFL.md`
- Whether the BFL-04 invariant table uses one row per write site or groups same-function multi-write sites under a single row
- Whether Task 4's lock-window conservation algebra is presented inline in the per-REQ section or as a small companion appendix
- Whether the test-stub design hand-off names the file `BackfillIdempotency.test.js` or extends `test/edge/LastPurchaseDayRace.test.js` — Phase 251 final call
- Whether finding-candidate severity is suggested (recommended INFO baseline) or left blank for Phase 253 D-08 5-bucket rubric
- Per-REQ section header naming

## Deferred Ideas

Captured in CONTEXT.md `<deferred>` section:

- Forge fuzz invariant test for `dailyIdx ↔ rngWordByDay` bijection (flag for Phase 251 TST-04 if planner judges value)
- Cross-milestone delta chain audit for `_backfillGapDays` (out of v32.0 scope per REQUIREMENTS.md Out of Scope)
- Automated CI gate for VRF lock-window invariants (future-milestone candidate)
- Phase 250 SIB-01 sibling sweep promotion path (via D-248-14 scope-guard deferral)
- Storage-layout add-row for any future backfill-guard hardening that introduces a new state-var (none expected; routes to Phase 252 POST31-01 if it happens)
