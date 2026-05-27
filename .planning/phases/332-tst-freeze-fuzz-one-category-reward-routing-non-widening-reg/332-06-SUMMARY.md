---
phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
plan: 06
subsystem: testing
tags: [non-widening-regression, by-name-gate, 42-name-union, forge-test-whole-tree, net-zero-new-regression, v49-ledger, deletion-attribution, crank-keeper-rename, membership-table, frozen-subject, markdown-gate]

# Dependency graph
requires:
  - phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg
    provides: "332-01..05 — the fresh v49 green proofs (RngLockDeterminism router functions / KeeperRouterOneCategory / KeeperRewardRoutingSameResults / DegeneretteResolveRepeg) + the 17 premise-retired deletions (8041451d) + the 5 Crank*->Keeper* renames (52452fe1) the ledger records"
  - phase: 330-impl-the-one-batched-contract-diff-router-advance-rework-mic
    provides: "the v49 keeper-router source (63bc16ca) that flipped the 17 reward-rehoming reds green->red"
  - phase: 331-gas-worst-case-marginal-derivation-break-even-0-5gwei-peg-ca
    provides: "the GAS-calibrated constants (4c9f9d9b) + the two new green files RouterWorstCaseGas.t.sol (11) / KeeperBatchAffiliateDeltaAudit.t.sol (2+1skip)"
provides:
  - "TST-04 part B: test/REGRESSION-BASELINE-v49.md — the authoritative NON-WIDENING regression ledger the Phase-333 TERMINAL delta-audit consumes"
  - "the binding headline recorded BY NAME (not a bare count): the live whole-tree forge failing set == the 42 v48.0-baseline reds by NAME (strict set equality, net-zero new regression) at the v49 TST HEAD"
  - "the live whole-tree forge run captured + reconciled: 666 passed / 42 failed / 17 skipped; live failing set - 42 union == empty AND 42 union - live failing set == empty (zero new red, zero dropped baseline red)"
  - "the 17 deletions recorded with per-test re-homing + reward-shape/oracle-migration classification + v46 provenance; the 5 renames recorded with the git-mv mapping + behavior-neutrality proof; the new green files recorded with live-re-verified counts; the §6 per-suite + per-test-body last-touching-commit membership table proving all 42 reds predate v49"
affects: [333-terminal-delta-audit-3-skill-adversarial-sweep-closure]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "BY-NAME non-widening gate as a strict SET EQUALITY (T-332-06-COUNT mitigation): parse forge test --json, build the live (suite-basename, testName) failing set, assert live == the §2-enumerated 42-name v48 union EXACTLY (both live - union == empty AND union - live == empty). A bare count gate would mask a new regression that coincidentally offsets a deletion."
    - "Per-TEST-BODY attribution via git log -L /func/,/^    }/:file for the suites a v49 commit file-touched: where the file-level last-touch is a v49 commit (AfKingSubscription@331-05, AfKingFundingWaterfall@330, RngLockDeterminism@332-01), the failing test's BODY last-touch proves it is a carried-forward v48-baseline red whose premise the v49 touch did not alter (the gas-split / the new TST-01 functions / the v49 funding re-sync of an already-red test)."
    - "Live count re-verification over assumption: the new green file counts were re-derived from the run's JSON, NOT copied from RESEARCH — RouterWorstCaseGas = 11 (not the 13 the draft assumed, the 331 GAS rescope dropped 2 buy/open seeds) and KeeperBatchAffiliateDeltaAudit = 2 passing + 1 skipped (not 3 passing)."

key-files:
  created:
    - "test/REGRESSION-BASELINE-v49.md — the v49 NON-WIDENING regression ledger (358 lines), mirroring REGRESSION-BASELINE-v48.md §1-§6 (+ §7 scope): §1 the 59-17==42 / passing-flat-at-666 arithmetic, §2 the 42-name union BY NAME carried verbatim, §3 the 17 deletions + re-homing + provenance, §4 the 5 Crank*->Keeper* renames, §5 the new green files with live counts, §6 the net-zero proof + membership table + FC1-FC4 guards, §7 scope attestation"
  modified: []

key-decisions:
  - "Re-ran the WHOLE-tree forge test --json at the actual TST HEAD (7d59ec16) and re-verified the numbers rather than copying 666/42 from 332-05: live = 666 passed / 42 failed / 17 skipped, and the live failing (suite,name) set == the 42 v48 union by NAME EXACTLY (both set differences empty). The HEAD had advanced past the research's 2b20f420 (the 332-01..05 proofs + deletions + renames all landed), so the 59/17 split is historical; the post-everything HEAD is 666/42."
  - "Recorded the gate as a strict NAME-set EQUALITY (live == union), stronger than the v48 ledger's 'strict subset' phrasing — at the v49 TST HEAD the failing set is exactly equal to the union (no dropped baseline red either), so the equality both prevents a new regression (FC1/FC3) AND confirms no baseline red was silently lost."
  - "Mirrored the v48 ledger §1-§5 shape but added a NOTE explaining why the v49 §1 arithmetic is a '59 - 17 deleted == 42' (failing-side) reconciliation with passing flat at 666, rather than the v48 '594 + 38 NEW_PASSING' shape: the v49 fresh-green files landed in EARLIER waves (332-01..04 + 331), so TST-04 is a delete+rename layered on top, not a same-plan green-addition. The binding 'failing == 42 by name' invariant is identical in both ledgers."
  - "Classified each of the 17 deletions reward-shape (per-item summed / per-leg premise retired by RD-4 + GAS-2) vs oracle-migration (RD-2 guard-drop / RD-5 entry-gate / GASOPT-04 no-double-buy) per the RESEARCH table, with the v46 provenance commit per row (3afbf676 / 795e679d / dfba3ac1 / 47b9d031 / b9bc5206) and the 332-05 deletion commit 8041451d, and added an explicit re-homing coverage attestation tying each retired premise to its fresh v49 proof (so the deletion provably loses zero coverage; SAFE-03 / H-CANCEL-SWAP preserved)."

patterns-established:
  - "Pattern 1: a markdown NON-WIDENING ledger whose binding gate is a NAME-set equality (not a count) over a live whole-tree forge run, with attributable deletion/rename churn and a per-suite + per-test-body membership table proving every red predates the milestone diff. The clean route for a frozen-subject regression baseline."

requirements-completed: [TST-04]

# Metrics
duration: 6min
completed: 2026-05-27
---

# Phase 332 Plan 06: TST-04 Part B — Author the v49 NON-WIDENING Regression Ledger Summary

**Authored `test/REGRESSION-BASELINE-v49.md`, the authoritative NON-WIDENING regression gate the Phase-333 TERMINAL delta-audit consumes — mirroring `REGRESSION-BASELINE-v48.md` §1-§6 (+ §7 scope). Re-ran the WHOLE-tree `forge test --json` at the v49 TST HEAD (`7d59ec16`) and re-verified the numbers: 666 passed / 42 failed / 17 skipped, with the live failing `(suite, name)` set == the 42 v48.0-baseline reds BY NAME EXACTLY (both set differences empty — zero new red, zero dropped baseline red). The binding headline is recorded BY NAME, never a bare count. Recorded the 17 premise-retired deletions (with per-test re-homing + reward-shape/oracle-migration classification + v46 provenance, commit `8041451d`), the 5 `Crank*`→`Keeper*` renames (behavior-neutral, byte-identical failing set, commit `52452fe1`), the new green proof files with live-re-verified counts (TST-01 3 / TST-02 9 / TST-03 7 / TST-05 7 / RouterWorstCaseGas 11 / KeeperBatchAffiliateDeltaAudit 2+1skip), and the §6 per-suite + per-test-body last-touching-commit membership table proving all 42 reds predate v49. ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~6 min (the load-bearing cost was the multi-minute whole-tree `forge test --json`; the authoring + reconciliation is fast)
- **Started:** 2026-05-27T18:16:39Z
- **Completed:** 2026-05-27T18:22:44Z
- **Tasks:** 2 (both `type=auto`) — Task 1 the live gate run + reconcile, Task 2 author the ledger; both produce the single `REGRESSION-BASELINE-v49.md` artifact, committed atomically
- **Files created:** 1 (`test/REGRESSION-BASELINE-v49.md`, 358 lines)

## Accomplishments

### Task 1 — run the authoritative whole-tree forge test + reconcile the net-zero red-set

- **Whole-tree run (NOT `--match-path`)** at the TST HEAD `7d59ec16`: `forge test --json` → **666 passed / 42 failed / 17 skipped** (708 run). The HEAD had advanced past the research's `2b20f420` — the 332-01..05 proofs + the 17 deletions + the 5 renames all landed — so the historical 59/17 split is now the post-everything 666/42.
- **Strict BY-NAME set comparison** against the §2 42-name v48 union (built from `REGRESSION-BASELINE-v48.md §2` Buckets A/B/C + B13): `live − union == ∅` (zero NEW regression outside baseline) AND `union − live == ∅` (zero dropped baseline red) → `live == union BY NAME` TRUE. The plan's Task-1 verify (`exactly 42: True`) passed. No `## STOP — NEW REGRESSION OUTSIDE BASELINE` block needed.
- **New-green counts re-verified live** (NOT assumed): TST-01 RngLockDeterminism = 3 router functions (4 pass / 1 A7 red / 16 skip on the contract), TST-02 KeeperRouterOneCategory = 9, TST-03 KeeperRewardRoutingSameResults = 7, TST-05 DegeneretteResolveRepeg = 7, RouterWorstCaseGas = **11** (NOT 13 — the 331 GAS rescope dropped the 2 buy/open seeds), KeeperBatchAffiliateDeltaAudit = **2 passing + 1 skipped** (NOT 3 passing).
- **Per-suite AND per-test-body last-touching commits captured** for the §6 membership table (`git log -1 --format=%h <file>` + `git log -L /func/,/^    }/:<file>` for the 3 v49-file-touched suites).

### Task 2 — author test/REGRESSION-BASELINE-v49.md mirroring the v48 ledger

- **§1** the arithmetic: `59 − 17 deleted == 42` (failing side) with passing flat at 666 across the deletion, + a NOTE explaining why the v49 reconciliation shape differs from v48's `594 + 38 NEW_PASSING` (the v49 fresh-green files landed in earlier waves; TST-04 is delete+rename layered on top).
- **§2** the AUTHORITATIVE 42-red union BY NAME carried VERBATIM from v48 §2 (Buckets A 8 / B 34 / C 0), with the A7 / B9 / B10 carried-forward notes; per-suite reconciliation == 42.
- **§3** the 17 deletions BY NAME with per-test re-homing (→ the fresh 332-02/03/04 + 331 proofs), reward-shape vs oracle-migration classification, the v46 provenance commit per row, the deletion commit `8041451d`, and an explicit re-homing coverage attestation (SAFE-03 / H-CANCEL-SWAP preserved, `testCrankBoxOpenStaysPostUnlock` preserved GREEN).
- **§4** the 5 `Crank*`→`Keeper*` renames (the `git mv` mapping, commit `52452fe1`, the byte-identical-failing-set behavior-neutrality proof, the single deliberate `Crank` residual note).
- **§5** the new green proof files with live counts + the TST-05 Hardhat Degenerette stat secondary gate (24 passing / 1 pending, v48 parity, recorded at 332-04).
- **§6** the net-zero PROOF: the live set-equality result, the FC1-FC4 false-confidence guards (gate by NAME not count; deletions/renames attributable; full tree run; never green over a real regression), and the per-suite + per-test-body membership table with the net-zero attribution conclusion.
- **§7** scope attestation (whole tree run, zero `contracts/*.sol` mutation, frozen subject, the ledger is the authoritative gate).

## Task Commits

Both tasks produce the single `REGRESSION-BASELINE-v49.md` deliverable (Task 1 = the live run that feeds §1/§5/§6; Task 2 = the authored ledger), committed atomically (mirrors the coupled-task commits of 332-02/03/04):

1. **Task 1 (run + reconcile) + Task 2 (author the ledger)** — `11d1b1f5` (test) — 1 file changed, 358 insertions

**Plan metadata:** (this SUMMARY + STATE/ROADMAP) — see the final docs commit.

## Files Created/Modified

- `test/REGRESSION-BASELINE-v49.md` — the v49 NON-WIDENING regression ledger (created; 358 lines). `test/` is not gitignored, commits normally. Authored with the Write tool (no heredoc).

## Verification

- **Task 1 verify (plan automated):** `python3 ... d=json.load(.../forge332-final.json) ... failing count: 42 / exactly 42: True`.
- **Task 2 verify (plan automated):** `test -f test/REGRESSION-BASELINE-v49.md` → exists; `grep -c "Bucket A\|Bucket B\|Bucket C"` → 6; `grep -ic "42 v48\|42 .*baseline\|net-zero"` → 8.
- **Strict BY-NAME set equality:** `live failing set == the 42 v48 union` (both `live − union` and `union − live` empty) — re-verified this run.
- **§1-§7 headers present** (the §1-§6 v48 mirror + §7 scope): all confirmed.
- `git diff --name-only contracts/` → empty (ZERO mainnet mutation, FROZEN subject honored).
- Post-commit deletion check: no files deleted by `11d1b1f5` (358-insertion create only).

## Deviations from Plan

None affecting scope. The plan executed as written. Three records worth noting (no scope change):

1. **[Live HEAD advanced past research]** The research recorded a `2b20f420` HEAD at 640/59 (pre-332-01..05). At the actual TST HEAD `7d59ec16`, all the 332 proofs + the deletions + the renames have landed, so the authoritative run is the post-everything **666 passed / 42 failed / 17 skipped** (matching the 332-05 post-rename gate exactly). The ledger records the live post-everything numbers, not the historical mid-execution split — per the standing instruction to re-run `forge test` at the actual TST HEAD (Pitfall 1).
2. **[Live count correction over the research draft]** `RouterWorstCaseGas` = 11 passing (the research draft said 13) and `KeeperBatchAffiliateDeltaAudit` = 2 passing + 1 skipped (the draft said 3) — re-counted from the run's JSON, NOT assumed, per the plan's explicit "re-count ... do not assume 13/3" directive.
3. **[Per-test-body attribution for v49-file-touched suites]** Three failing suites were file-touched by a v49 commit (AfKingSubscription@`4c9f9d9b` 331-05, AfKingFundingWaterfall@`63bc16ca` 330, RngLockDeterminism@`41a49223` 332-01). To keep the membership net-zero airtight, the ledger records the per-test BODY last-touch via `git log -L` (f50cc634 / 63bc16ca-but-red-at-v48 / b102bc0f respectively), proving each FAILING test is a carried-forward v48-baseline red whose premise the v49 file-touch did not alter.

No CLAUDE.md present in the project root (global instructions only).

## Contract Defects Surfaced

None. This plan authors a markdown ledger and re-runs the existing suite; no proof surfaced a CONTRACT defect. The subject stayed byte-frozen (zero `contracts/*.sol` mutation; `git diff --name-only contracts/` empty).

## Known Stubs

None — this is a markdown gate ledger, no code, no placeholders, no unwired data. Every recorded number is a live `forge test --json` measurement or a `git log` provenance fact captured this run; the 42-name union is carried verbatim from the v48 ledger.

## Threat Flags

None — this plan authors a documentation ledger and introduces zero security-relevant surface (no endpoints, auth paths, file access, or schema changes). The phase is `test/` + `.planning/` only, subject frozen.

## Self-Check: PASSED

- `test/REGRESSION-BASELINE-v49.md` — FOUND (358 lines, §1-§7)
- commit `11d1b1f5` (the ledger) — FOUND
- `332-06-SUMMARY.md` — FOUND
- live whole-tree `forge test` — 666 passed / 42 failed / 17 skipped; failing set == the 42 v48 union by NAME (strict set equality, net-zero new regression)
- `git diff --name-only contracts/` — empty (zero mainnet mutation)

---
*Phase: 332-tst-freeze-fuzz-one-category-reward-routing-non-widening-reg*
*Completed: 2026-05-27*
