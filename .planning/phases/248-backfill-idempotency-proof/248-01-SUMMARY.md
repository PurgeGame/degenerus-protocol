---
phase: 248-backfill-idempotency-proof
plan: 248-01
status: FINAL — READ-ONLY at HEAD acd88512
head: acd88512
deliverable: audit/v32-248-BFL.md
plan_close_timestamp: 2026-05-02T00:43:20Z
closure_signal: PHASE_248_BFL_FINAL_AT_HEAD_acd88512
requirements_completed: [BFL-01, BFL-02, BFL-03, BFL-04, BFL-05, BFL-06]
---

# Phase 248 Plan 248-01 — SUMMARY

## Plan Metadata

- **Phase:** 248 — Backfill Idempotency Proof
- **Plan ID:** 248-01
- **Audit head:** `acd88512` (Phase 247 anchor; both WIP guards already inside this SHA — turbo at advanceGame:173 + backfill at rngGate:1174)
- **Status:** FINAL — READ-ONLY (closure signal `PHASE_248_BFL_FINAL_AT_HEAD_acd88512` emitted in deliverable EOF)
- **Plan-close timestamp:** 2026-05-02T00:43:20Z
- **Deliverable:** `audit/v32-248-BFL.md` (single file, READ-only on disk via `chmod -w` after this commit per D-247-22 carry-forward)
- **Topology:** Single-plan multi-task (5 atomic per-task commits + 1 plan-close commit) per D-248-11
- **Pure-proof discipline:** Zero `contracts/` writes, zero `test/` writes, KNOWN-ISSUES.md UNCHANGED throughout (D-248-04 / D-248-05)

## Atomic Commits (5 per-task + 1 plan-close per D-247-14 carry-forward)

| # | Task | Commit Subject | SHA |
|---|---|---|---|
| 1 | Task 1 — BFL-01 + BFL-02 enumeration | `audit(248-01): Task 1 — BFL-01 + BFL-02 enumeration at HEAD acd88512` | `b79f3eac` |
| 2 | Task 2 — BFL-03 + BFL-04 invariant proof | `audit(248-01): Task 2 — BFL-03 worked numeric example + BFL-04 dailyIdx ↔ rngWordByDay invariant table` | `838631a8` |
| 3 | Task 3 — BFL-05 EXC envelope RE_VERIFY | `audit(248-01): Task 3 — BFL-05 EXC-02 + EXC-03 dual-carrier RE_VERIFY (NON-WIDENING)` | `3be95bfe` |
| 4 | Task 4 — BFL-06 conservation + Phase 251 hand-off | `audit(248-01): Task 4 — BFL-06 conservation algebra + Phase 251 TST-04 hand-off appendix` | `5545b125` |
| 5 | Task 5 — Final assembly + plan-close SUMMARY | `docs(248-01): plan-close SUMMARY — Phase 248 BFL FINAL READ-only at HEAD acd88512` | (this commit) |

## Per-REQ Deliverable Counts

Verified at plan-close via `grep -v '^#' audit/v32-248-BFL.md | grep -c "^| BFL-${r}-V"`:

| REQ ID | V-row count | Verdict mix | Anchor file:line |
|---|---|---|---|
| BFL-01 | 7 | 7 SAFE / 0 EXCEPTION / 0 FINDING_CANDIDATE | AdvanceModule:1174 (guard) + AdvanceModule:1176 (call site) |
| BFL-02 | 6 | 6 SAFE / 0 EXCEPTION / 0 FINDING_CANDIDATE | AdvanceModule:1174-1186 (guarded block) + 1761-1772 (`_backfillGapDays` loop) + 1779-1798 (`_backfillOrphanedLootboxIndices`) |
| BFL-03 | 15 | BFL-03-V01..V08 are pre-fix narrative-only (SAFE-IF-POST-FIX-APPLIED); BFL-03-V09..V15 are post-fix proof rows (7 SAFE) | testnet blocks 10759449 + 10761786 |
| BFL-04 | 4 | 4 HOLDS / 0 VIOLATES / 0 FINDING_CANDIDATE | DegenerusGame.sol:219 (constructor init) + AdvanceModule:1703 (`_unlockRng` runtime sole writer) + AdvanceModule:1814 (`_applyDailyRng` current-day write) + AdvanceModule:1766 (`_backfillGapDays` gap-day write) |
| BFL-05 | 2 | 2 NON-WIDENING / 0 WIDENING-detected | AdvanceModule:1329 (EXC-02 — `_getHistoricalRngFallback`) + AdvanceModule:1238 (EXC-03 — `_gameOverEntropy`) |
| BFL-06 | 10 | 10 TRUE conservation closure / 0 FALSE | AdvanceModule:1184 (`purchaseStartDay`) + 1766-1768 (`_backfillGapDays` per-day writes) + 1180 (`_backfillOrphanedLootboxIndices`) + 1185 (`gapDays` local) + boundary cite to BurnieCoinflip.sol:838-865 |

**Totals:** 44 V-rows + 3 multiplier (BFL-01-M01..M03) rows + 5 out-of-scope-for-boundary-clarity (BFL-02-X01..X05) rows.

**Finding Candidates:** Zero rows classified `FINDING_CANDIDATE` across all 6 per-REQ sections. The `## Finding Candidates` subsection is OMITTED entirely from `audit/v32-248-BFL.md` per CONTEXT.md D-248-03 (no v32 finding-ID emission in Phase 248; Phase 253 FIND-01..04 owns ID assignment).

## Scope-Guard Deferrals (per D-248-14)

One scope-guard refinement surfaced during BFL-04 enumeration; it does NOT contradict Phase 247's catalog and is recorded here per D-248-14 instead of re-editing Phase 247:

- **`dailyIdx` constructor write at `DegenerusGame.sol:219`.** Phase 248 PLAN.md frontmatter `canonical_line_ranges.dailyIdx_sole_writer_line: 1703` cited "sole writer" referring to runtime mutation. The `git grep -n '\bdailyIdx\s*=' acd88512 -- 'contracts/*.sol' 'contracts/**/*.sol'` enumeration cited verbatim in `audit/v32-248-BFL.md` §4 returns 2 results: `DegenerusGame.sol:219` (constructor init — `dailyIdx = currentDay` set to deploy-day index, runs exactly once at deploy) and `AdvanceModule:1703` (the runtime sole writer inside `_unlockRng`). The constructor write is structurally outside any VRF lock window; the runtime sole-writer attestation for `dailyIdx` therefore narrows to AdvanceModule:1703 with the constructor row recorded for completeness as BFL-04-V01 (verdict HOLDS — deploy-time bootstrap, no runtime path can reach this line again after deploy). This refinement does NOT invalidate the BFL-04 invariant; it strengthens it by explicitly bounding the universe-of-write-sites attestation. Phase 247 catalog is unchanged.

No other scope-guard deferrals — Phase 247 catalog (D-247-I001..I006) fully covered by Phase 248 BFL-01..06 sections; no additional Phase 247 catalog gaps surfaced during execution.

## Hand-Off Signals

- **Phase 251 TST-04** — Test-stub design hand-off block lives at `audit/v32-248-BFL.md::## Phase 251 TST-04 Hand-Off`. Sub-blocks: §251.1 symbolic spec (pre-state setup + 8-step call sequence + expected pre-fix `purchaseStartDay` over-application + expected post-fix single application; concrete assertion target `purchaseStartDay == startBefore + 2` post-Step 7 in the simplest 2-day-gap shape) + §251.2 suggested test file (`test/edge/BackfillIdempotency.test.js` OR extend `test/edge/LastPurchaseDayRace.test.js`) + §251.3 Phase 247 row anchors (D-247-C012 + D-247-F011 + D-247-X030). Phase 251 plan reads this appendix as TST-04 scope input.

- **Phase 252 POST31-02** — Productive-pause cross-cite: this BFL deliverable closes the backfill-idempotency proof, freeing Phase 252 to focus on remaining post-31-rollup gaps without re-litigating the rngGate L1174 surface. Phase 252 inherits BFL-05 NON-WIDENING attestation (no EXC-02 / EXC-03 envelope updates required). The BFL-04 invariant table's `_unlockRng` write-site row (BFL-04-V02) cross-cites the productive-pause path so Phase 252 inherits the composition target per CONTEXT.md `code_context > Integration Points`.

- **Phase 253 FIND/REG routing** — Zero rows in `audit/v32-248-BFL.md` were classified `FINDING_CANDIDATE` (the `## Finding Candidates` subsection is OMITTED entirely from the deliverable per D-248-03 default-omit rule). Phase 253 FIND-01..04 has no Phase 248 candidates to promote to v32 finding IDs. KNOWN-ISSUES.md is UNCHANGED throughout Phase 248 (BFL-05 verdicts both NON-WIDENING — no Phase 253 D-09 gating walk required for either EXC envelope).

## Closure Signal

`PHASE_248_BFL_FINAL_AT_HEAD_acd88512` emitted in `audit/v32-248-BFL.md` at EOF (HTML comment form per D-247-22 carry-forward).

## Self-Check: PASSED

- File `audit/v32-248-BFL.md` exists and is read-only on disk (`[ ! -w audit/v32-248-BFL.md ]` returns true)
- Frontmatter `status: FINAL — READ-ONLY at HEAD acd88512` present
- Body `**Status:** FINAL — READ-ONLY at HEAD acd88512` present
- Closure signal `PHASE_248_BFL_FINAL_AT_HEAD_acd88512` present at EOF
- All 6 per-REQ sections (`## Section 1 — BFL-01` through `## Section 6 — BFL-06`) populated; each has ≥1 BFL-NN-VMM row (counts: 7 / 6 / 15 / 4 / 2 / 10)
- `## Phase 251 TST-04 Hand-Off` appendix populated with §251.1 + §251.2 + §251.3
- All 3 Phase 247 row anchors cited (D-247-C012, D-247-F011, D-247-X030)
- Zero `RESERVED FOR TASK` markers remain
- Zero `F-32-` substrings anywhere in the deliverable (D-248-03 enforcement)
- Zero `<fill from`, `REPLACE-WITH`, `REPLACE WITH` placeholder tokens remain
- Atomic commits exist for Tasks 1-4: `b79f3eac` (Task 1) + `838631a8` (Task 2) + `3be95bfe` (Task 3) + `5545b125` (Task 4) — all subjects matching `audit\(248-01\): Task [1-4] —`
- KNOWN-ISSUES.md UNCHANGED throughout (`git status --porcelain KNOWN-ISSUES.md` empty)
- Working tree contains only the 2 pre-existing lines from start of Phase 248 execution (` M contracts/ContractAddresses.sol` per D-247-03 + `?? test/edge/LastPurchaseDayRace.test.js` per D-247-02) — zero Phase 248 induced contracts/ or test/ writes
- Phase 247 anchor sanity: `git rev-parse acd88512` resolves to `acd88512c516bef51981d8b6f49de9878aba9159`; `git diff acd88512..HEAD -- contracts/ test/` is EMPTY across all docs-only commits ABOVE the anchor

---

*Phase: 248-backfill-idempotency-proof*
*Plan: 248-01*
*Completed: 2026-05-02*
