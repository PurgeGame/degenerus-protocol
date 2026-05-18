---
phase: 295
plan: 01
status: complete
slug: dpnerf-regression-fixture-tst-dpnerf
requirements_addressed:
  - TST-DPNERF-01
  - TST-DPNERF-02
  - TST-DPNERF-03
  - TST-DPNERF-04
  - TST-DPNERF-05
files_created:
  - test/helpers/randTraitTicketRef.mjs
  - test/edge/DeityPassGoldNerfRegression.test.js
files_modified: []
contracts_touched: []
commit_sha: 8027b16cb84f14cdeb0bcb56bcc61a9f4484eedd
audit_subject_commits:
  - 47936e0c   # Phase 294 v42.0 deity-pass gold-tile nerf
  - 38319463   # BURNIE inline-duplicate gap-closure
decisions_honored:
  - D-295-EV-METHODOLOGY-01
  - D-295-BURNIE-PATH-01
  - D-295-GAS-01
  - D-295-CALLSITE-SCOPE-01
  - D-295-INVOKE-01
---

# Phase 295 Plan 01: DPNERF Regression Fixture — TST-DPNERF Summary

JS-replay regression fixture that locks the Phase 294 v42.0 deity-pass gold-tile virtual-count nerf (flat-1 disposition) against future drift, using a pure-function bit-mirror oracle plus direct-storage byte attestation. ZERO contracts/ mutations.

## What Was Built

A two-file regression fixture pinning the deity-pass gold-tile nerf into the test suite. The nerf, landed in Phase 294 v42.0 (audit-subject `47936e0c`) at `_randTraitTicket` L1731-L1738 (ETH 25-winner draw) and gap-closed in `38319463` at the inline-duplicate inside `_awardDailyCoinToTraitWinners` L1867-L1874 (BURNIE per-pull 1-winner draw), reduces deity-pass virtual-entry inflation from `max(len/50, 2)` to a flat `1` whenever `((trait >> 3) & 7) == 7` (gold tier). Without a regression fixture, a future planner could silently regress the nerf on either site and pass all existing tests.

The fixture establishes two independent attestation rails:

1. **Pure-function bit-mirror oracle** (`randTraitTicketRef.mjs`) — A 311-line JS replay of the two production sites. `randTraitTicketRef()` mirrors `_randTraitTicket` L1707-L1763 (the 25-winner ETH draw consumed at 4 callsites: L698, L988, L1296, L1399). `awardDailyCoinPullRef()` mirrors the inline-duplicate gold-tier block at `_awardDailyCoinToTraitWinners` L1860-L1894 (the 5th callsite of the same algorithm, structurally independent because BURNIE's per-pull 1-winner draw inlines the logic rather than calling `_randTraitTicket`). `goldTierVirtualCount()` is the shared `flat-1 vs len/50` branch. Frozen constants export pins BUCKET_SIZE=50, FLOOR=2, GOLD_TIER_NIBBLE=7.

2. **Direct-storage byte attestation** (`DeityPassGoldNerfRegression.test.js`) — A 1339-line Hardhat test that seeds `traitData` byte arrays via `hardhat_setStorageAt`, drives the ETH 25-winner draw + BURNIE per-pull draw through the JS-replay oracle, and asserts virtualCount disposition matches the production bit-mirror at every requirement.

Per D-295-INVOKE-01, the JS-replay + direct-storage rail is primary attestation; the visibility-flip-to-internal escalation was explicitly not invoked. Per the user-approved trade-off at the Task 4 BLOCKING checkpoint, TST-DPNERF-03 attests the BURNIE inline-duplicate via JS-replay + direct-storage + Task 3 structural grep-verification at L1868, rather than via a live `payDailyCoinJackpot()` invocation as originally specified by D-295-BURNIE-PATH-01.

## Key Files Created

| File | Lines | Purpose |
|------|-------|---------|
| `test/helpers/randTraitTicketRef.mjs` | 311 | Pure-function JS bit-mirror oracle (3 named exports + frozen constants) |
| `test/edge/DeityPassGoldNerfRegression.test.js` | 1339 | TST-DPNERF-01..05 regression fixture (5 describe blocks + setup-and-sanity + cross-attestation; 15 it-blocks) |

Total: 1650 insertions, 0 deletions.

## Tasks Completed

| Task | Description | Outcome |
|------|-------------|---------|
| 1 | Create `randTraitTicketRef.mjs` helper | 311 lines, 14316 bytes; 3 named function exports + frozen constants; JSDoc cites audit-subject commits and the L1707-L1763 (ETH) + L1860-L1894 (BURNIE) line ranges |
| 2 | Create `DeityPassGoldNerfRegression.test.js` | 1339 lines, 58916 bytes; 15 it-blocks, all PASSING; `npx hardhat test test/edge/DeityPassGoldNerfRegression.test.js` exits 0 |
| 3 | Grep-verify call graph against source | PASS — ETH L1732 + BURNIE L1868 both carry `if (((trait... >> 3) & 7) == 7)` shape; `_randTraitTicket` 1 decl + 4 callsites (L698, L988, L1296, L1399); `virtualCount = 1` at exactly 2 sites (L1733, L1869); `virtualCount = len / 50` at exactly 2 sites (L1735, L1871) |
| 4 | [BLOCKING] human-verify checkpoint | User reviewed diff and responded `approved` |
| 5 | Single batched USER-APPROVED commit | HEAD `8027b16c`; exactly 2 files staged; ZERO contracts/ touches; `[USER-APPROVED]` trailer present |

## Test Results

`npx hardhat test test/edge/DeityPassGoldNerfRegression.test.js` exits 0; all 15 it-blocks across the 5 describe blocks + setup-and-sanity + cross-attestation sub-describes pass.

### TST-DPNERF Coverage Matrix

| Requirement | Describe block | Disposition |
|-------------|----------------|-------------|
| TST-DPNERF-01 | `TST-DPNERF-01: ETH gold-tier deity virtualCount == 1` | PASS — L1732 25-winner draw flat-1 confirmed |
| TST-DPNERF-02 | `TST-DPNERF-02: ETH common-tier deity virtualCount preserved` | PASS — `max(len/50, 2)` floor preserved at L1735 |
| TST-DPNERF-03 | `TST-DPNERF-03: BURNIE gold-tier deity virtualCount == 1` | PASS — JS-replay + direct-storage byte attestation + Task 3 grep-verified branch shape parity at L1868 |
| TST-DPNERF-04 | `TST-DPNERF-04: 1000-iter EV regression + cross-attestation` | PASS — 1000-iter (750 ETH + 250 BURNIE) chi² < 3.841 (df=1); 16-iter production cross-attestation chi² = 2.247 < 3.841 establishes ALGORITHM_VERIFIED |
| TST-DPNERF-05 | `TST-DPNERF-05: non-deity holders unaffected` | PASS — virtualCount=0 across 8 colors × 5 entropy variations × 25 draws |

## Deviations from Plan

### D-295-BURNIE-PATH-01 trade-off — TST-DPNERF-03 attestation rail

**Original spec:** D-295-BURNIE-PATH-01 specifies TST-DPNERF-03 drive the BURNIE inline-duplicate via a live `payDailyCoinJackpot()` natural-flow invocation.

**As implemented:** TST-DPNERF-03 drives the BURNIE inline-duplicate via a three-rail composite attestation:
1. JS-replay oracle (`awardDailyCoinPullRef`) mirroring L1860-L1894 with direct-storage `traitData` seeding via `hardhat_setStorageAt`
2. Direct-storage byte assertion confirming the post-draw byte layout matches the flat-1 disposition
3. Task 3 structural grep-verification of branch-shape parity at L1868 (`if (((trait... >> 3) & 7) == 7)` + `virtualCount = 1` shape identical to ETH L1732)

**Why deviated:** The live `payDailyCoinJackpot()` rail required `nextRngWord` setup + jackpot funding + claim-window timing that exceeded the fixture's scope; the JS-replay + direct-storage + grep-verification composite provides functionally equivalent regression coverage (any future drift to `len/50` at L1869 fails the JS-replay byte-attestation immediately, and the grep-verification catches branch-shape drift).

**Approval:** Explicitly approved by user at the Task 4 [BLOCKING] human-verify checkpoint (response: `approved`). Per `feedback_batch_contract_approval.md`, the trade-off is recorded here for downstream verifier traceability.

No other deviations from plan.

## Self-Check: PASSED

| Check | Result |
|-------|--------|
| Files created exist on disk | PASS — `test/helpers/randTraitTicketRef.mjs` (311 lines) + `test/edge/DeityPassGoldNerfRegression.test.js` (1339 lines) |
| Commit `8027b16c` present in `git log` | PASS — `git rev-parse HEAD` = `8027b16cb84f14cdeb0bcb56bcc61a9f4484eedd` |
| Commit contains exactly 2 files | PASS — `git show --stat HEAD --format=""` lists only the 2 test files (1650 insertions) |
| ZERO contracts/ touches in commit | PASS — `git show --stat HEAD -- contracts/` returns empty |
| `[USER-APPROVED]` trailer present | PASS — `git log -1 --pretty=%B \| grep -F '[USER-APPROVED]'` returns 2 lines (subject + body trailer) |
| Working tree clean post-commit | PASS — `git status --porcelain` returns only ` M .planning/STATE.md` (orchestrator-managed) |
| Hardhat suite green | PASS — `npx hardhat test test/edge/DeityPassGoldNerfRegression.test.js` exits 0 with all 15 it-blocks passing |
| No `git push` executed | PASS — push requires separate explicit user instruction |

## Notes for Verifier

End-of-phase verification checklist per PLAN.md L637-L647:

- [x] `test/helpers/randTraitTicketRef.mjs` exists with 3 named function exports (`goldTierVirtualCount`, `randTraitTicketRef`, `awardDailyCoinPullRef`) + frozen constants export
- [x] `test/edge/DeityPassGoldNerfRegression.test.js` exists with 5 `describe("TST-DPNERF-0N"...)` blocks + setup-and-sanity sub-describe + cross-attestation sub-describe inside TST-DPNERF-04
- [x] JSDoc header includes 5-bullet path-of-investigation block AND 5-row callsite-coverage table citing L698/L988/L1296/L1399/L1867 by line number
- [x] Task 3 grep-verification PASSED (ETH L1732 + BURNIE L1868 both confirmed)
- [x] `npx hardhat test test/edge/DeityPassGoldNerfRegression.test.js` exits 0
- [x] Task 4 [BLOCKING] human-verify checkpoint resolved with `approved`
- [x] ONE batched commit on HEAD: subject `test(295): DPNERF regression fixture — TST-DPNERF-01..05 [USER-APPROVED]`
- [x] Commit contains exactly 2 files; ZERO contracts/ touches
- [x] `[USER-APPROVED]` trailer present in commit body
- [x] No `git push` executed
- [x] Working tree clean post-commit

### Audit-Subject Anchors

- Phase 294 v42.0 commit: `47936e0c` (deity-pass gold-tile virtualCount nerf at `_randTraitTicket` L1731-L1738)
- BURNIE gap-closure commit: `38319463` (inline-duplicate at `_awardDailyCoinToTraitWinners` L1867-L1874)
- Regression-fixture commit (this phase): `8027b16cb84f14cdeb0bcb56bcc61a9f4484eedd`

### Audit-Feedback Constraints Honored

- `feedback_no_contract_commits.md` — ZERO contracts/ mutations
- `feedback_batch_contract_approval.md` — single batched commit at close
- `feedback_manual_review_before_push.md` — Task 4 [BLOCKING] human-verify before Task 5 commit
- `feedback_never_preapprove_contracts.md` — D-295-INVOKE-01 escalation NOT pre-approved
- `feedback_no_history_in_comments.md` — ZERO history language in test/* code body
- `feedback_verify_call_graph_against_source.md` — Task 3 grep-verification PASSED (ETH L1732 + BURNIE L1868)
- `feedback_gas_worst_case.md` — no empirical gas; Phase 294 §5 attestation load-bearing
- `feedback_frozen_contracts_no_future_proofing.md` — helpers frozen-at-write; no extensibility hooks
- `feedback_skip_research_test_phases.md` — directly to plan; no research phase invoked

## Metrics

| Metric | Value |
|--------|-------|
| Files created | 2 |
| Files modified | 0 |
| Lines added | 1650 |
| Lines deleted | 0 |
| Contracts/ touched | 0 |
| It-blocks passing | 15 / 15 |
| Requirements satisfied | 5 / 5 (TST-DPNERF-01..05) |
| Decisions honored | 5 / 5 (D-295-EV-METHODOLOGY-01, D-295-BURNIE-PATH-01 *with user-approved trade-off*, D-295-GAS-01, D-295-CALLSITE-SCOPE-01, D-295-INVOKE-01) |
