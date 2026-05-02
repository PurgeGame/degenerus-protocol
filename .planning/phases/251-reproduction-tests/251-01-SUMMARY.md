---
phase: 251-reproduction-tests
phase_number: 251
plan: 251-01
plan_id: 251-01
status: COMPLETE
milestone: v32.0
milestone_name: Backfill Idempotency + purchaseLevel Underflow Audit
deliverable: audit/v32-251-TST.md
deliverable_status: FINAL READ-only
head_anchor: acd88512
head_at_close: c790ae45
closure_signal: PHASE_251_TST_FINAL_AT_HEAD_<plan-close-sha>
requirements_satisfied: [TST-01, TST-02, TST-03, TST-04]
verdict_counts:
  TST-01: { SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 }
  TST-02: { SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 }
  TST-03: { SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 }
  TST-04: { SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 }
total_v_rows: 8
awaiting_approval_files:
  - test/edge/LastPurchaseDayRace.test.js
  - test/edge/BackfillIdempotency.test.js
tags:
  - audit
  - reproduction-tests
  - empirical-validation
  - backfill-idempotency
  - turbo-race
  - rng-determinism
---

# Plan 251-01 Summary — Reproduction Tests

## Plan Metadata

- **Phase:** 251 — Reproduction Tests
- **Milestone:** v32.0 Backfill Idempotency + purchaseLevel Underflow Audit
- **Plan ID:** 251-01 (single plan, 4 tasks per CONTEXT.md D-251-PLN-01)
- **Anchor:** HEAD `acd88512` (inherited from Phase 247 / 248 / 249 / 250)
- **Runtime HEAD:** `c790ae45` (Phase 250 closure docs + Phase 251 STATE.md update)
- **Closure signal:** `PHASE_251_TST_FINAL_AT_HEAD_<plan-close-sha>`
- **Deliverable:** `audit/v32-251-TST.md` FINAL READ-only at HEAD `c790ae45`
- **Closed:** 2026-05-02 (Task 4 plan-close commit landing)

## Plan Execution Summary

Phase 251 empirically validated the v32.0 WIP guards (turbo at AdvanceModule:173 + backfill at AdvanceModule:1174) by executing the LastPurchaseDayRace + LivenessProductivePause + LivenessMidJackpot test files plus a newly authored BackfillIdempotency test against three guard-revert states (A: both reverted; C: backfill-only reverted; D: HEAD with both guards). All 8 V-rows resolved SAFE. Zero FINDING_CANDIDATE rows surfaced — the WIP guards are empirically load-bearing as predicted by the abstract proofs in Phase 248 (BFL-03 / BFL §7.1) and Phase 249 (PLV-03 / PLV-05). TST-03 confirmed the prior committed liveness fixes (`8bdeabc2` productive-pause + `ad41973c` regression suite) remain green under the new guards — no regression introduced.

Per `feedback_no_contract_commits.md` + `feedback_never_preapprove_contracts.md`: zero `test/edge/*.test.js` files were committed across the 4 Phase-251 atomic commits. Both `test/edge/LastPurchaseDayRace.test.js` (existing untracked WIP) and `test/edge/BackfillIdempotency.test.js` (newly authored Task 3) remain in untracked on-disk state at plan close, listed in §5 Commit-Readiness Register at status `awaiting-approval` for user manual approval per `feedback_manual_review_before_push.md`.

## Atomic Commits

Each task landed its own atomic commit per D-247-14 / D-251-CF-06 carry-forward:

| Task | Commit SHA | Subject |
|------|------------|---------|
| Task 1 | `c73c8add` | audit(251-01): Task 1 — TST-01 pre-fix panic 0x11 reproduction at HEAD acd88512 |
| Task 2 | `6bc9c525` | audit(251-01): Task 2 — TST-02 + TST-03 state-D pass at HEAD c790ae45 |
| Task 3 | `33e7d7c5` | audit(251-01): Task 3 — TST-04 backfill-idempotency state-C pre-fix fail + state-D post-fix pass |
| Task 4 | (this commit — final assembly + READ-only flip + plan-close) | audit(251-01): Task 4 — §5 register + §4.4 + final assembly + FINAL READ-only flip |

All 4 commits' `git show --stat` output contains ZERO `test/edge/*.test.js` paths (cross-commit attestation per D-251-CF-09).

## Per-REQ Deliverable Counts

| REQ | Section | Row count | Verdict breakdown | Notes |
|-----|---------|-----------|-------------------|-------|
| TST-01 | §1 | 2 TST-01-Vnn rows | SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 | V01 single-day `it()` block at L125 (state A — panic 0x11 reproduced); V02 multi-day-drain `it()` block at L213 (state A — panic 0x11 reproduced via testnet exact pattern). Cross-cite PLV-05 (audit/v32-249-PLV.md §5) abstract testnet panic walk; cross-cite BFL-03 (audit/v32-248-BFL.md §3) for V02. |
| TST-02 | §2 | 2 TST-02-Vnn rows | SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 | V01 + V02 covered by single state-D run (4 passing total in run log: single-day + multi-day-drain + stress + regression-normal-turbo). Cross-cite PLV-03 (audit/v32-249-PLV.md §3) ternary unreachable proof empirical confirmation. |
| TST-03 | §3 | 2 TST-03-Vnn rows | SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 | V01 LivenessProductivePause.test.js (8bdeabc2; 4 passing); V02 LivenessMidJackpot.test.js (ad41973c; 4 passing). Cross-cite SIB-04-V01 (audit/v32-250-SIB.md §4.1) productive-pause carrier. |
| TST-04 | §4 | 2 TST-04-Vnn rows | SAFE: 2, EXCEPTION: 0, FINDING_CANDIDATE: 0 | V01 state C (psdDelta=15 over-bump + downstream panic 0x11 at iter 140; D-251-06 SITE-vs-TYPE rule: SAFE because state-C panic at different code path than state-A); V02 state D (psdDelta=7, no panic, drain reaches stage 6). 53% delta reduction (15→7) is empirical L1174 sentinel load-bearing confirmation. Cross-cite BFL-03 + BFL §7.1 (audit/v32-248-BFL.md §3 + §7.1). |

**Total V-rows in deliverable:** 2 (TST-01) + 2 (TST-02) + 2 (TST-03) + 2 (TST-04) = **8**.
**Audit artifacts produced:** 2 patch files + 1 deliverable + 7 run logs (including the cancelled `lpdr-A-20260502T065016Z.log` from the initial `--reporter` mis-invocation, which was deleted before commit; net 6 retained run logs). Final run-log inventory at plan close:
- `audit/v32-251-runs/lpdr-A-20260502T065027Z.log` (TST-01-V01 state A single-day)
- `audit/v32-251-runs/lpdr-A-multi-20260502T065102Z.log` (TST-01-V02 state A multi-day-drain)
- `audit/v32-251-runs/lpdr-D-20260502T065351Z.log` (TST-02 state D LastPurchaseDayRace 4-passing)
- `audit/v32-251-runs/lpp-D-20260502T065444Z.log` (TST-03-V01 state D LivenessProductivePause 4-passing)
- `audit/v32-251-runs/lmj-D-20260502T065525Z.log` (TST-03-V02 state D LivenessMidJackpot 4-passing)
- `audit/v32-251-runs/bfl-C-20260502T070044Z.log` (TST-04-V01 state C BackfillIdempotency over-bump+panic)
- `audit/v32-251-runs/bfl-D-20260502T065952Z.log` (TST-04-V02 state D BackfillIdempotency pass)

## Patches Authored

Both patch files committed as Task 1 audit artifacts (NOT contract or test writes — patches are static audit artifacts under `audit/`):

| Patch | Purpose | sha-256 | Verification |
|-------|---------|---------|--------------|
| `audit/v32-251-prefix-revert.patch` | State A — both guards reverted (turbo L167/L173 + backfill L1167/L1174) | `dc17c607a475b3dc64fcd8f5b20aae7d6c69b2554405a08cd1256e5043da2e93` | `git apply --check -R` exits 0 against current HEAD |
| `audit/v32-251-prefix-revert-backfill-only.patch` | State C — only backfill L1167/L1174 reverted (turbo at L173 KEPT) | `8863acce1e28c403e5c046b86209da1f5401c02457dc428c2e8ac8fe68bb7b64` | `git apply --check -R` exits 0 against current HEAD |

Patch authoring source: `git diff 48554f8f acd88512 -- contracts/modules/DegenerusGameAdvanceModule.sol` (per D-251-01). Both hunks (D-247-C011 turbo at L167/L173 + D-247-C012 backfill at L1167/L1174) are derived directly from this diff.

## Scope-Guard Deferrals

Per CONTEXT.md D-251-CF-07 carry-forward (Phase 247 NOT re-edited; gaps route to Phase 253):

| ID | Item | Disposition |
|----|------|-------------|
| SG-251-CF-01 | HEAD divergence: anchor `acd88512` vs runtime HEAD `c790ae45`. Only contract-tree delta is `contracts/modules/DegenerusGameMintModule.sol` (the post-anchor `98e78404` mint commit, recorded as SG-250-01). AdvanceModule line ranges L167/L173 + L1167/L1174 are byte-identical between `acd88512` and `c790ae45`; hunk-revert patches apply cleanly to current HEAD's working tree. State-D runs document the runtime HEAD + the SG-250-01 carry-forward. | Recorded; no audit verdict change. Carry-forward of Phase 250 SG-250-01. |
| SG-251-01 (transient) | Deploy fixture `deployFullProtocol` regenerates `contracts/ContractAddresses.sol` during test runs (patches predicted deploy addresses + recompiles). The file briefly shows `M` in `git status` during the state-C test run; restored via `git checkout` post-run. Not committed in any task. Per `feedback_contractaddresses_policy.md`, `ContractAddresses.sol` is modifiable by fixtures without per-commit approval; documented in §5 working-tree-dirty window documentation block. | No audit impact; standard fixture behavior. |

No NEW scope-guard deferrals beyond the carry-forward and the documented `ContractAddresses.sol` transient-fixture-regen behavior. Zero divergences in AdvanceModule line ranges that would have invalidated the patch authoring source.

## Commit-Readiness Carry-Forward

§5 of `audit/v32-251-TST.md` lists TST-FILE-01 + TST-FILE-02 at status `awaiting-approval`:

- **TST-FILE-01** — `test/edge/LastPurchaseDayRace.test.js` (existing untracked WIP). Inherited from Phase 247 D-247-02 carry-forward; remains untracked through Phase 251 close per D-251-07.
- **TST-FILE-02** — `test/edge/BackfillIdempotency.test.js` (newly authored Phase 251 Task 3 per BFL §7.1; sha-256 `03aecc8329a2520e38abeb5f942648a50abf8de1dad23f0efe28dd92eab7ab72`). Written to disk by Task 3 to enable state-C and state-D run execution; NOT committed by any agent per D-251-08.

Both rows route to Phase 253 FIND-04 commit-readiness register at milestone close per the Phase 251 → Phase 253 hand-off in CONTEXT.md `<canonical_refs>`. If the user approves manual commits between Phase 251 close and v32.0 milestone close, FIND-04 records the `approved-and-committed` SHAs in the milestone-closure register.

## Hand-Off Signals

- **→ Phase 252 (Post-v31.0 Landed-Commit Sanity):** TST-03-V01 + TST-03-V02 SAFE verdicts confirm the `8bdeabc2` productive-pause carrier composes correctly with the new turbo + backfill guards. Phase 252 POST31-02 inherits this empirical evidence for the productive-pause × turbo-guard × backfill-guard three-way composition proof.
- **→ Phase 253 (Findings Consolidation):** Zero FINDING_CANDIDATE rows surfaced in Phase 251. The lean regression appendix REG-01 inherits the empirical PASS verdicts for any prior finding referencing `_backfillGapDays`, `purchaseLevel`, `rngLockedFlag`, `lastPurchaseDay`, `dailyIdx`, or the turbo block. Phase 253 FIND-04 commit-readiness register inherits the awaiting-approval rows from §5.
- **→ Milestone close:** `MILESTONE_V32_AT_HEAD_<sha>` will be emitted by Phase 253 once any approved WIP guard / test commits land. Phase 251 contributes the empirical confirmation that the WIP guards are load-bearing — necessary input for the milestone-closure attestation.

## Closure Signal

`PHASE_251_TST_FINAL_AT_HEAD_<plan-close-sha>`

The `<plan-close-sha>` placeholder reflects this Task 4 plan-close commit's SHA (recorded in the commit message itself; see Task 4 commit log line). Per D-251-PLN-01 closure-recursion artifact handling, the file content uses the placeholder and the commit message carries the canonical resolved SHA.
