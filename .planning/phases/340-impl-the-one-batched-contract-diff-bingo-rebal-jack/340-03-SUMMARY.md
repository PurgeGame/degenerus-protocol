---
phase: 340-impl-the-one-batched-contract-diff-bingo-rebal-jack
plan: 03
subsystem: contracts
tags: [contracts, rebal, jack, deletion, contract-boundary, held-uncommitted]
requires:
  - "339-REBAL-JACK-ATTESTATION (the BPS-sum-10000 + clean-orphan + preserved-plumbing locks)"
  - "339-GREP-ATTESTATION-EDIT-ORDER (the 22-anchor table; REBAL :295/:297, JACK :112/:191/:1339-1352)"
provides:
  - "REBAL: StakedDegenerusStonk Pool.Reward doubled 50B->100B (REWARD_POOL_BPS 500->1000), funding the continuous claimBingo distribution surface; affiliate 350B->300B; BPS-sum invariant intact (10000)"
  - "JACK: the jackpot final-day Pool.Reward one-shot removed from _handleSoloBucketWinner; Pool.Reward now flows only through claimBingo + the existing Degenerette path"
affects:
  - "contracts/StakedDegenerusStonk.sol (constructor pool allocation)"
  - "contracts/modules/DegenerusGameJackpotModule.sol (solo-bucket winner payout; final-day branch)"
tech-stack:
  added: []
  patterns: ["BPS-sum-conservation (net-zero affiliate<->reward swap)", "clean-orphan deletion (sole-use constant + sole-emit event)", "unnamed-positional-param to silence unused-param warning"]
key-files:
  created:
    - ".planning/phases/340-impl-the-one-batched-contract-diff-bingo-rebal-jack/340-03-SUMMARY.md"
  modified:
    - "contracts/StakedDegenerusStonk.sol (UNCOMMITTED — held for 340-04 hand-review)"
    - "contracts/modules/DegenerusGameJackpotModule.sol (UNCOMMITTED — held for 340-04 hand-review)"
decisions:
  - "REBAL is exactly two single-token edits (:295 AFFILIATE 3500->3000, :297 REWARD 500->1000); CREATOR_BPS=2000 (:291) is the BPS-sum completeness term and was NOT touched (per the 339 grep-table drift correction that the visible :294-298 block sums to only 8000)"
  - "JACK orphan-param handled by ELIDING the param NAME (kept the bool positional type unnamed) — the lightest choice; the :1184 call site still passes isFinalDay positionally and the upstream isFinalDay chain (compute :608, lvl+1 gate :611, doc :1079, params :1089/:1155, calls :1129/:1184) is byte-untouched"
  - "NO contracts/ file committed — BATCH-02 contract-commit HARD STOP; the working-tree diff is HELD for explicit user hand-review at Plan 340-04; only this SUMMARY doc is committed"
metrics:
  duration: "~6m"
  completed: "2026-05-28T23:53:21Z"
  tasks: 2
  files-touched: 2
---

# Phase 340 Plan 03: REBAL + JACK Co-Requisites Summary

The two ISOLATED economic co-requisites of the v51.0 claimBingo bundle landed as a faithful transcription of the LOCKED 339 REBAL-JACK attestation: the `StakedDegenerusStonk` constructor REBAL doubling `Pool.Reward` 50B->100B (net-zero affiliate<->reward swap, complete pool-BPS set still sums to exactly 10000) and the `DegenerusGameJackpotModule` JACK deletion removing the final-day `Pool.Reward` one-shot (branch + orphaned constant + event, no dangling refs, no orphan-param warning), with all other `isFinalDay` plumbing preserved untouched. Both diffs are HELD UNCOMMITTED for the 340-04 user hand-review (BATCH-02 contract-commit HARD STOP).

## What Was Built

### Task 1 — REBAL (`contracts/StakedDegenerusStonk.sol`)
Two single-token constant edits in the constructor pool-allocation block:
- `AFFILIATE_POOL_BPS` `3500` -> `3000` (was `:295`)
- `REWARD_POOL_BPS` `500` -> `1000` (was `:297`)

Net-zero (+500 reward / -500 affiliate). The COMPLETE pool-BPS set is now `{CREATOR 2000, WHALE 1000, AFFILIATE 3000, LOOTBOX 2000, REWARD 1000, PRESALE_BOX 1000} = 10000` — the BPS-sum invariant holds (10000 before and after). `INITIAL_SUPPLY` and `BPS_DENOM` byte-unchanged, so total sDGNRS supply is unchanged; only the affiliate<->reward split shifts. `Pool.Reward` doubles 50B -> 100B (funds the continuous claimBingo distribution); affiliate pool takes a ~14% haircut (350B -> 300B). `CREATOR_BPS = 2000` (the completeness term flagged by the 339 grep table, since the visible `:294-298` block sums to only 8000) was deliberately NOT touched.

### Task 2 — JACK (`contracts/modules/DegenerusGameJackpotModule.sol`)
Three coherent deletions inside `_handleSoloBucketWinner` and its supporting symbols:
- Deleted the whole `if (isFinalDay) { ... }` final-day `Pool.Reward` draw branch (was `:1339-1352`): the `poolBalance(Pool.Reward)` read -> `(dgnrsPool * FINAL_DAY_DGNRS_BPS)/10_000` -> the `reward != 0` guard -> `transferFromPool(Pool.Reward, w, reward)` -> `emit JackpotDgnrsWin(w, reward)`.
- Deleted the now-orphaned `FINAL_DAY_DGNRS_BPS = 100` constant (was `:191`; sole use was inside the deleted branch).
- Deleted the `JackpotDgnrsWin` event declaration (was `:112`; sole emit was inside the deleted branch).
- ELIDED the `_handleSoloBucketWinner` `isFinalDay` parameter NAME (kept `bool` positional, unnamed) so the parameter — now unread inside the function — raises no unused-parameter compiler warning, while the `:1184` call site stays unaffected (still passes `isFinalDay` positionally) and the upstream `isFinalDay` chain is byte-untouched.

PRESERVED untouched (verified by grep): the `isFinalDay` compute (`:608`), the `lvl + 1` ticket-index gate (`isFinalDay ? lvl + 1 : lvl`, `:611`), the `_processDailyEth`/`_processBucket` doc + params + pass-through (`:1079/:1089/:1129/:1155/:1184`), the whale-pass-on-final-day branch (`emit JackpotWhalePassWin`, 5 refs survive), and the read-side `traitBurnTicket[lvl]` consumer.

## How To Verify
- `grep -c 'AFFILIATE_POOL_BPS = 3000' contracts/StakedDegenerusStonk.sol` == 1; `... = 3500` == 0.
- `grep -c 'REWARD_POOL_BPS = 1000' contracts/StakedDegenerusStonk.sol` == 1; `... = 500;` == 0.
- BPS-sum: 2000 + 1000 + 3000 + 2000 + 1000 + 1000 == 10000.
- `grep -c 'JackpotDgnrsWin' contracts/modules/DegenerusGameJackpotModule.sol` == 0; `grep -c 'FINAL_DAY_DGNRS_BPS' ...` == 0.
- `grep -c 'isFinalDay ? lvl + 1 : lvl' ...` == 1 (the preserved gate); `grep -c 'JackpotWhalePassWin' ...` == 5 (>=1, whale-pass branch survives).
- No `Pool.Reward` draw remains inside `_handleSoloBucketWinner` (sed slice -> grep -c 'Pool.Reward' == 0).
- `forge build` clean (the no-dangling-ref + no-orphan-param-warning compile check) is verified at Plan 340-04 per D-340-03 — NOT run here.

All plan `<verify>` automated gates returned `OK`.

## Deviations from Plan

None — plan executed exactly as written. The plan offered author's choice for the orphan parameter (elide name OR drop the param + update the call site/`_processBucket` chain); the lighter elide-the-name option was chosen, leaving the entire upstream `isFinalDay` chain byte-untouched. No bugs, missing functionality, or blocking issues encountered (Rules 1-3 not triggered); no architectural decisions (Rule 4 not triggered).

## Contract-Boundary Posture (BATCH-02)
- NO `contracts/*.sol` file was committed. The REBAL + JACK working-tree diffs are HELD UNCOMMITTED for explicit user hand-review at Plan 340-04, where they will be committed by the orchestrator (after approval) as ONE batched `feat(340)` commit alongside the BINGO producers.
- The pre-existing UNCOMMITTED 340-01 BINGO edits (`contracts/ContractAddresses.sol`, `contracts/storage/DegenerusGameStorage.sol`, the untracked `contracts/modules/DegenerusGameBingoModule.sol`) were left untouched — not staged, reverted, or modified.
- Only `340-03-SUMMARY.md` was committed (docs-only).
- STATE.md / ROADMAP.md were NOT updated — the orchestrator owns those.

## Known Stubs
None — these are pure constant edits and a deletion; no placeholder/empty-value/TODO surface introduced.

## Threat Flags
None — REBAL touches only constructor constants (no new runtime surface); JACK removes a payout branch (no new surface). The plan `<threat_model>` (T-340-11..14) fully covers this diff's security record; no surface outside it was introduced.

## Self-Check: PASSED
- FOUND: `contracts/StakedDegenerusStonk.sol` (REBAL edits present: AFFILIATE_POOL_BPS = 3000, REWARD_POOL_BPS = 1000)
- FOUND: `contracts/modules/DegenerusGameJackpotModule.sol` (JACK clean-orphaned: JackpotDgnrsWin == 0, FINAL_DAY_DGNRS_BPS == 0)
- FOUND: `.planning/phases/340-impl-the-one-batched-contract-diff-bingo-rebal-jack/340-03-SUMMARY.md`
- No commit-hash check applicable for the contract edits (intentionally UNCOMMITTED per the BATCH-02 HARD STOP); the SUMMARY docs commit hash is recorded by the executor in its completion report.
