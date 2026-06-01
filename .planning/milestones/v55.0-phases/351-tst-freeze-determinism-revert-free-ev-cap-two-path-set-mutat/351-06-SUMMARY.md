---
phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat
plan: 06
subsystem: testing
tags: [foundry, fuzz, afking, redemption, steth, custody-recovery, removed-surface, D-351-02, non-widening, batchPurchase, affiliate, receive-gate]

# Dependency graph
requires:
  - phase: 351-01
    provides: "the compiling DeployProtocol fixture (GameAfkingModule at GAME_AFKING_MODULE) the two adapted files build on"
  - phase: 351-05
    provides: "the prior D-351-02 batchPurchase-leg drop precedent (the 6 KeeperNonBrick isolation tests dropped BY NAME) + the funded LOOTBOX-mode STAGE that already exercises the per-buy affiliate.payAffiliate path (the reframe target this plan judged redundant)"
  - phase: 349.2
    provides: "the frozen 453f8073 contract subject (the restored per-buy affiliate.payAffiliate at GameAfkingModule.sol:806/:816 — BURNIE flip-credit, no ETH/solvency surface)"
provides:
  - "KeeperBatchAffiliateDeltaAudit.t.sol — DROPPED whole-file (D-351-02): its entire subject was the removed `batchPurchase` + never-landed `batchPurchaseForKeeper`; the batch-aggregation byte-identity has no successor; the affiliate-conservation property survives non-redundantly in AffiliateDgnrsClaim.t.sol + 351-05's funded STAGE"
  - "RedemptionStethFallback.t.sol — ADAPTED: the 6 ETH-vs-stETH redemption-core tests (RFALL05 a-f) kept verbatim (zero AfKing coupling); the AfKing import dropped; the POOL-04 (d) burnAtGameOver-AfKing-custody-recovery leg DROPPED BY NAME (no successor); POOL-04 (a)/(b)/(c) receive() tests reframed onto the v55 GAME-only receive() gate — 9 tests green in isolation"
  - "The finalized D-351-02 removed-surface DROP LEDGER fragment (3 entries BY NAME + reason) for 351-09's REGRESSION-BASELINE-v55.md"
affects: [351-09, "REGRESSION-BASELINE-v55.md (the KeeperBatchAffiliateDeltaAudit whole-file drop + the RedemptionStethFallback POOL-04(d) custody-recovery drop, BY NAME + reason)"]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "D-351-02 whole-file drop (KeeperBatchAffiliateDeltaAudit): a fuzz file whose ENTIRE subject is a removed/never-landed surface (`batchPurchase` + the gated-but-unland `batchPurchaseForKeeper`, KEEPER_PATH_LANDED=false) with NO behavioral successor is deleted cleanly — BUT only after confirming its incidental property (affiliate-conservation `totalAffiliateScore == Σ score`) is covered non-redundantly ELSEWHERE (AffiliateDgnrsClaim.t.sol test_totalScoreAccumulates asserts `total == a + b`; the per-buy affiliate.payAffiliate path runs inside 351-05's funded LOOTBOX STAGE). Reframe was REJECTED as redundant duplication, not coverage loss."
    - "D-351-02 partial-leg drop + same-property reframe (RedemptionStethFallback): the de-custody leg (depositFor/poolOf/withdraw recovery of a PREPAID AfKing pool) drops BY NAME because sDGNRS.burnAtGameOver is now a pure local-token burn with no withdraw-fold (StakedDegenerusStonk.sol:526-535); but the surrounding POOL-04 receive()-safety properties (live-balance read / counted-once / arbitrary-vector-revert) SURVIVE — only the AUTHORIZED SENDER moved (AF_KING -> GAME under the v55 GAME-only receive() gate :433-434), so the call-site delta is `vm.prank(AF_KING)` -> `vm.prank(GAME)`, not a property deletion."
    - "GAME-only receive() reframe: the v54 sDGNRS receive() relaxation (GAME || AF_KING) is dissolved to GAME-only (the afking-funding withdraw send-back routes through GAME — the Game's `.call` carries msg.sender == GAME). The v54 `NonGameNonAfKingReceiveReverts` becomes `NonGameReceiveReverts` and is STRICTLY TIGHTER (only GAME authorized), so the arbitrary-deposit-vector guard is stronger, not weaker."

key-files:
  created:
    - ".planning/phases/351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat/351-06-SUMMARY.md"
  modified:
    - "test/fuzz/RedemptionStethFallback.t.sol"
  deleted:
    - "test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol"

key-decisions:
  - "KeeperBatchAffiliateDeltaAudit.t.sol is DROPPED whole-file (D-351-02), NOT reframed. Its entire subject is the removed `batchPurchase` + the never-landed `batchPurchaseForKeeper` (the `KEEPER_PATH_LANDED=false` / TODO-331-05 gated diff that never landed AND a surface v55 removed — `game.batchPurchase` does not exist anywhere in contracts/). Its UNIQUE value was the batch-aggregation byte-identity (Run A current path vs Run B proposed aggregated path) — a removed surface with NO successor. Its INCIDENTAL property (affiliate-conservation: `totalAffiliateScore == Σ affiliateScore`, no double-credit, slice-refund) is covered NON-REDUNDANTLY by AffiliateDgnrsClaim.t.sol (`test_totalScoreAccumulates` :136 `assertEq(total, a + b)`, `test_orderIndependence`, `test_proportionalDistribution`) AND the per-buy `affiliate.payAffiliate` path (GameAfkingModule.sol:806/:816) is already exercised by 351-05's V55RevertFreeEvCap funded LOOTBOX-mode STAGE. A reframe would DUPLICATE live coverage of a property that survives elsewhere, while adding nothing the batch surface uniquely tested. DROP per the D-351-02 exception (subject fully removed)."
  - "RedemptionStethFallback.t.sol: the ETH-vs-stETH redemption-fallback CORE (RFALL05 a-f, 6 tests) is KEPT VERBATIM — it has ZERO AfKing coupling (the whole :158-485 region greps clean). Only the AfKing-specific machinery is touched: (1) the `:7 import {AfKing}` is dropped (file deleted); (2) the POOL-04 (d) `test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` custody-recovery leg is DROPPED BY NAME; (3) POOL-04 (a)/(b)/(c) reframe onto the GAME-only receive() gate."
  - "POOL-04 (d) custody-recovery leg DROP rationale (BY NAME + reason): it proved sDGNRS.burnAtGameOver folded `afKing.withdraw(afKing.poolOf(this))` to recover a PREPAID AfKing pool before its bal==0 early-return. v55 removed this: (a) contracts/AfKing.sol is DELETED — depositFor/poolOf/withdraw no longer exist; (b) there is NO game-resident recovery of a PREPAID third-party pool keyed to sDGNRS (withdrawAfkingFunding/afkingFundingOf recover a player's OWN funding, not a prepaid pool); (c) sDGNRS.burnAtGameOver is now a pure local-token burn (StakedDegenerusStonk.sol:526-535: `bal=balanceOf[this]; if(bal==0)return; balanceOf[this]=0; totalSupply-=bal; delete poolBalances`) — it folds no AfKing withdraw. The property under test is GONE with no successor — a clean D-351-02 drop."
  - "POOL-04 (a)/(b)/(c) receive()-safety reframe: the v54 sDGNRS receive() relaxation (GAME || AF_KING — accepting AfKing's withdraw send-back) is dissolved to GAME-only (StakedDegenerusStonk.sol:433-434 `if (msg.sender != ContractAddresses.GAME) revert Unauthorized`). The afking-funding withdraw send-back now routes through GAME (the Game's `.call` has msg.sender == GAME). The live-balance-read / counted-once / arbitrary-vector-revert properties are ASSET- and SENDER-INDEPENDENT — only the AUTHORIZED sender changed. Reframe = `vm.prank(AF_KING)` -> `vm.prank(GAME)` for the credit; the (c) revert test becomes `NonGameReceiveReverts` (strictly tighter). NOT a coverage loss — the same three properties, exercised through the surviving sender."

patterns-established:
  - "Whole-file removed-surface drop demands a REDUNDANCY PROOF, not just a 'no successor' claim: before deleting KeeperBatchAffiliateDeltaAudit, confirmed its incidental affiliate-conservation property is covered elsewhere (AffiliateDgnrsClaim.t.sol + 351-05's STAGE). The D-351-02 bias=adapt is honored by proving the surviving property is not orphaned, THEN dropping the genuinely-removed batch subject."
  - "A receive()-gate tightening (GAME||AF_KING -> GAME-only) reframes as a sender-swap, not a property deletion: the deposit-accounting properties (live read, counted-once, arbitrary-vector-revert) are sender-agnostic, so the test moves to the surviving authorized sender and the negative test (stranger reverts) gets STRONGER (fewer authorized senders)."

requirements-completed: [TST-04, TST-05]

# Metrics
duration: 30min
completed: 2026-05-31
---

# Phase 351 Plan 06: D-351-02 Removed-Surface Adjudication (KeeperBatchAffiliateDeltaAudit + RedemptionStethFallback) Summary

**Adjudicated the two D-351-02 removed-surface fuzz files and finalized the drop ledger 351-09 consumes. `KeeperBatchAffiliateDeltaAudit.t.sol` was DROPPED whole-file: its entire subject is the removed `batchPurchase` + the never-landed `batchPurchaseForKeeper` (the `KEEPER_PATH_LANDED=false`/TODO-331-05 gated diff that never landed AND a surface v55 removed — `game.batchPurchase` exists nowhere in contracts/), its unique value (batch-aggregation byte-identity) has no successor, and its incidental affiliate-conservation property (`totalAffiliateScore == Σ score`) is covered non-redundantly by `AffiliateDgnrsClaim.t.sol` + the per-buy `affiliate.payAffiliate` path already exercised in 351-05's funded LOOTBOX STAGE — so a reframe would duplicate live coverage, not preserve it. `RedemptionStethFallback.t.sol` was ADAPTED: the 6 ETH-vs-stETH redemption-core tests (RFALL05 a–f) are kept verbatim (zero AfKing coupling), the `AfKing` import is dropped, the POOL-04 (d) `burnAtGameOver`-recovers-the-AfKing-prepaid-pool custody leg is DROPPED BY NAME (sDGNRS.burnAtGameOver is now a pure local-token burn — `depositFor`/`poolOf`/`withdraw` are gone with no successor), and the POOL-04 (a)/(b)/(c) receive() tests are reframed onto the v55 GAME-only receive() gate (the v54 AF_KING relaxation dissolved; the credit sender moves AF_KING→GAME, the negative test gets strictly tighter). 9 RedemptionStethFallback tests green in isolation; ZERO `contracts/*.sol` mutation.**

## Performance

- **Duration:** ~30 min
- **Completed:** 2026-05-31
- **Tasks:** 2
- **Files:** 1 deleted (`KeeperBatchAffiliateDeltaAudit.t.sol`, 338 lines) + 1 modified (`RedemptionStethFallback.t.sol`, 643→645 lines)
- **Tests:** RedemptionStethFallback 9/9 green in isolation (6 RFALL05 ETH-vs-stETH core + 3 reframed POOL-04 receive); KeeperBatchAffiliateDeltaAudit dropped (3 batchPurchase tests removed)

## Accomplishments

- **Task 1 — KeeperBatchAffiliateDeltaAudit DROPPED whole-file (D-351-02).** Confirmed empirically that `batchPurchase` and `batchPurchaseForKeeper` exist NOWHERE in `contracts/` (`grep -rn "batchPurchase" contracts/` == empty). All 3 of the file's functions (`testBaselineDgnrsBatchMoneyOutcomes`, `testFuzz_BaselinePoisonPositionMoneyInvariant`, `testPathEquivalence_DgnrsBatchByteIdentical`) drive `game.batchPurchase{value}(...)` — a removed surface that won't compile against the v55 game. The file's unique subject (the batch-aggregation byte-identity of the current path vs the proposed aggregated `batchPurchaseForKeeper`) has NO behavioral successor (the per-buy work folded into `advanceGame()`'s required-path STAGE). Deleted via `git rm` after confirming no dangling code references (the only non-source ref is in the historical `REGRESSION-BASELINE-v49.md` doc).
- **Task 1 — redundancy proof (the D-351-02 bias=adapt honored).** Before dropping, confirmed the file's INCIDENTAL property (affiliate-conservation: aggregate == sum-of-successful-units, no double-credit) is covered NON-REDUNDANTLY by `AffiliateDgnrsClaim.t.sol` — `test_totalScoreAccumulates` (:136 `assertEq(total, a + b, "...total should equal sum")`), `test_orderIndependence`, `test_proportionalDistribution` — AND the per-buy `affiliate.payAffiliate` path itself (GameAfkingModule.sol:806/:816) is already exercised by 351-05's `V55RevertFreeEvCap` funded LOOTBOX-mode STAGE. A reframe onto the per-buy path would DUPLICATE live coverage of a surviving property while adding nothing the removed batch surface uniquely tested.
- **Task 2 — RedemptionStethFallback ETH-vs-stETH core PRESERVED verbatim.** The 6 RFALL05 tests (`EthLeg_HappyPath`, `StethFallback_MidGameEthDepletion`, `DonationRobust_StethForceFeed`, `FailClosed_NeitherLegCovers`, `TwoSamePeriodClaimants_BothPaid`, `BurnieCannotBlockEth`) — the POOL-04a/b ETH-segregation + stETH-fallback + fail-closed + paired-debit-solvency asserts — are KEPT unchanged. The whole `:158-485` region greps clean of any AfKing coupling, so it needed no call-site delta. All 6 green.
- **Task 2 — POOL-04 (d) custody-recovery leg DROPPED BY NAME.** `test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` proved sDGNRS.burnAtGameOver folded `afKing.withdraw(afKing.poolOf(this))` to recover a PREPAID AfKing pool. v55 removed this with NO successor: contracts/AfKing.sol is DELETED (`depositFor`/`poolOf`/`withdraw` gone); there is NO game-resident recovery of a prepaid third-party pool (withdrawAfkingFunding recovers a player's OWN funding); and `sDGNRS.burnAtGameOver` is now a pure local-token burn (StakedDegenerusStonk.sol:526-535). Replaced the function with an in-file BY-NAME drop-marker comment block (for the 351-09 ledger).
- **Task 2 — POOL-04 (a)/(b)/(c) receive() tests reframed onto the v55 GAME-only gate.** The v54 sDGNRS receive() relaxation (GAME || AF_KING, accepting AfKing's withdraw send-back) dissolved to GAME-only (StakedDegenerusStonk.sol:433-434). The afking-funding withdraw send-back now routes through GAME (the Game's `.call` carries msg.sender == GAME). Reframe: `(a) ReceiveReadsLiveBalance_NoRunningCounter` and `(b)` (renamed `GameCreditNotDoubleCounted`) swap the credit sender `vm.prank(AF_KING)` -> `vm.prank(GAME)` — the live-balance-read + counted-once properties are sender-agnostic and unchanged. `(c)` (renamed `NonGameReceiveReverts`) is STRICTLY TIGHTER under GAME-only (only GAME authorized), so the arbitrary-deposit-vector guard is stronger. All 3 green.
- **Task 2 — import dropped.** The `:7 import {AfKing} from "../../contracts/AfKing.sol"` (a hard compile break — the file is deleted) is removed; the redemption core does not need the AfKing type. Replaced with a comment documenting the drop rationale.
- **ZERO `contracts/*.sol` mutation.** `git diff --name-only 453f8073 HEAD -- contracts/` is EMPTY (committed AND working-tree); `ContractAddresses.sol` restored byte-identical (sha256 `80fe0dac…`) after each `patchForFoundry` round-trip; the `.bak` cleaned up (no untracked artifact).

## Task Commits

Each task was committed atomically (test/ only — no contracts/):

1. **Task 1: DROP KeeperBatchAffiliateDeltaAudit (D-351-02 removed surface)** — `c5f600bd` (test) — 1 file changed, 338 deletions.
2. **Task 2: adapt RedemptionStethFallback — keep ETH-vs-stETH core, drop AfKing custody leg** — `aad3aad8` (test) — 1 file changed, 68 insertions / 66 deletions.

**Plan metadata:** (this SUMMARY + STATE/ROADMAP/REQUIREMENTS) committed separately.

## Files Created/Modified/Deleted

- `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (DELETED, was 338 lines) — whole-file D-351-02 drop. Entire subject = `batchPurchase`/`batchPurchaseForKeeper` (removed/never-landed). No dangling code refs after deletion.
- `test/fuzz/RedemptionStethFallback.t.sol` (MODIFIED, 645 lines) — the `:7 AfKing` import dropped; the POOL-04 (d) custody-recovery leg dropped BY NAME (replaced with a drop-marker comment block); POOL-04 (a)/(b)/(c) reframed onto the GAME-only receive() gate (credit sender AF_KING→GAME; (b)→`GameCreditNotDoubleCounted`, (c)→`NonGameReceiveReverts`); the title docstring + the `receive()` helper comment updated; the 6 RFALL05 ETH-vs-stETH core tests untouched. Zero executable AF_KING/AfKing refs at HEAD; 59 `stETH` markers (core preserved). 9 tests (6 unit-shaped RFALL05 + 3 POOL-04).

## Decisions Made

- **KeeperBatchAffiliateDeltaAudit DROPPED whole-file, NOT reframed (D-351-02 exception, with a redundancy proof).** The bias=adapt is satisfied not by reframing onto the per-buy affiliate (which would duplicate `AffiliateDgnrsClaim.t.sol` + 351-05's STAGE coverage) but by confirming the surviving property is covered elsewhere, THEN dropping the genuinely-removed batch-aggregation subject. The unique thing this file tested — that the proposed aggregated `batchPurchaseForKeeper` produces byte-identical accumulators to the current `batchPurchase` try/catch path — is a never-landed, since-removed surface with literally no contract to run against.
- **RedemptionStethFallback adapted with a partial-leg drop + a same-property reframe.** Two distinct AfKing dependencies were handled differently per their successor status: the custody-recovery leg (POOL-04 d) DROPS because it has no successor; the receive()-safety properties (POOL-04 a/b/c) REFRAME because they survive — the gate merely tightened (GAME||AF_KING → GAME-only), which is a sender-swap, not a property loss. The ETH-vs-stETH core is orthogonal to AfKing entirely and stays verbatim.
- **The GAME-only receive() reframe makes the negative test stronger.** Under the v54 relaxation, a stranger reverting proved "the relaxation didn't open an arbitrary vector beyond GAME+AF_KING." Under v55 GAME-only, the same stranger revert proves the strictly-tighter "only GAME is authorized" — the v54 AF_KING sender would now ALSO revert. Renaming `NonGameNonAfKingReceiveReverts` → `NonGameReceiveReverts` reflects the tighter invariant.
- **TST-04 + TST-05 advanced (this plan's frontmatter requirements).** TST-04 (the surviving redemption + receive()-safety properties) and TST-05 (the D-351-02 drops finalized BY NAME for the non-widening ledger) are the slice this plan owns. The two drop-ledger fragments below are explicit for 351-09's `REGRESSION-BASELINE-v55.md`.

## Deviations from Plan

### Auto-fixed Issues

None. Both files behaved as the plan's interfaces predicted; the only judgment call (DROP vs REFRAME for KeeperBatchAffiliateDeltaAudit) was made per the plan's explicit "(a) reframe OR (b) drop if batchPurchase is its sole subject — the executor decides based on what the file actually asserts" directive, and resolved to DROP with the redundancy proof above. No bugs, no blocking issues, no contract edits.

### Plan-directive enrichment (within scope, noted for transparency)

The plan's interface text flagged only the POOL-04 (d) `:564-589` leg as the RedemptionStethFallback drop and said to "apply any call-site delta it needs (likely none beyond the import)." In practice the surviving POOL-04 (a)/(b)/(c) receive() tests ALSO referenced the deleted `ContractAddresses.AF_KING` (the v54 AF_KING-relaxation sender), so the call-site delta was the AF_KING→GAME sender reframe (the plan's "reframe / keep every other property" instruction). This is the documented adaptation, not a deviation — the plan's bias=adapt explicitly covers reframing a surviving property's call site.

**Total deviations:** 0 auto-fixed. No architectural changes; no contract edits.

## Authentication Gates

None.

## Known Stubs

None. Every kept test asserts a non-vacuous outcome: the 6 RFALL05 core tests each EXPLICITLY assert the branch they intend (e.g. (b) asserts game ETH was 0 < maxIncrement BEFORE the pull so the stETH leg ran, AND claimable/pool UNCHANGED after — the T-327-02-FC false-confidence guards); the 3 reframed POOL-04 tests assert the GAME credit moves the live balance + previewBurn base (a), is counted exactly once via the proportional-share delta (b), and a non-GAME sender reverts Unauthorized (c). No hardcoded empty value flows to an assertion.

## Removed-Surface / Reframe Notes (for the 351-09 REGRESSION-BASELINE-v55 ledger)

**D-351-02 REMOVED-SURFACE DROPS (BY NAME + reason) — this plan finalizes 2 entries:**

1. **WHOLE FILE — `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol` (3 tests + the `_drive`/`KEEPER_PATH_LANDED`/`_buildMixedBatch`/`_snap`/`_commissionFromSender`/`_assertEquivalent` machinery).** Reason: the entire subject is the removed `batchPurchase` + the never-landed `batchPurchaseForKeeper` (`KEEPER_PATH_LANDED=false`, TODO-331-05 gated diff that never landed; `game.batchPurchase` exists nowhere in v55 contracts/). The batch-aggregation byte-identity property has NO behavioral successor (per-buy work folded into advanceGame()'s required-path STAGE). The incidental affiliate-conservation property survives non-redundantly in `AffiliateDgnrsClaim.t.sol` (`test_totalScoreAccumulates` asserts `total == a + b`) + the per-buy `affiliate.payAffiliate` path is exercised by 351-05's funded LOOTBOX STAGE — reframe rejected as redundant. The 3 dropped tests:
   - `testBaselineDgnrsBatchMoneyOutcomes`
   - `testFuzz_BaselinePoisonPositionMoneyInvariant`
   - `testPathEquivalence_DgnrsBatchByteIdentical`

2. **PARTIAL LEG — `test/fuzz/RedemptionStethFallback.t.sol` :: `test_POOL04_BurnAtGameOverRecoversPool_ZeroPoolTokenSafe` (1 test).** Reason: it proved sDGNRS.burnAtGameOver folded `afKing.withdraw(afKing.poolOf(this))` to recover a PREPAID AfKing pool before its bal==0 early-return — v54 de-custody machinery v55 removed with NO successor. contracts/AfKing.sol is DELETED (`depositFor`/`poolOf`/`withdraw` gone); there is no game-resident recovery of a prepaid third-party pool (withdrawAfkingFunding recovers a player's OWN funding); sDGNRS.burnAtGameOver is now a pure local-token burn (StakedDegenerusStonk.sol:526-535).

**REFRAMES (renamed/relocated, NOT removed — kept) — RedemptionStethFallback POOL-04 receive()-safety, onto the v55 GAME-only receive() gate (StakedDegenerusStonk.sol:433-434; the v54 GAME||AF_KING relaxation dissolved, the withdraw send-back routes through GAME):**
   - `test_POOL04_ReceiveReadsLiveBalance_NoRunningCounter` — credit sender AF_KING→GAME (live-read property unchanged).
   - `test_POOL04_AfKingCreditNotDoubleCounted` → RENAMED `test_POOL04_GameCreditNotDoubleCounted` — credit sender AF_KING→GAME (counted-once property unchanged).
   - `test_POOL04_NonGameNonAfKingReceiveReverts` → RENAMED `test_POOL04_NonGameReceiveReverts` — strictly tighter under GAME-only (only GAME authorized; the old AF_KING sender now also reverts).

**KEPT VERBATIM (no AfKing coupling) — the RedemptionStethFallback ETH-vs-stETH redemption core (6 tests):** `test_RFALL05_EthLeg_HappyPath`, `test_RFALL05_StethFallback_MidGameEthDepletion`, `test_RFALL05_DonationRobust_StethForceFeed`, `test_RFALL05_FailClosed_NeitherLegCovers`, `test_RFALL05_TwoSamePeriodClaimants_BothPaid`, `test_RFALL05_BurnieCannotBlockEth`.

## Sibling Files NOT Compile-Verified Here (Wave-3 / 351-09 charge)

Per the Wave-2 isolation note, the still-broken siblings owned by OTHER 351 plans were sidelined-and-restored (NOT edited) for the isolation build: `test/gas/KeeperLeversAndPacking.t.sol`, `test/gas/RouterWorstCaseGas.t.sol`, `test/gas/SweepPerPlayerWorstCaseGas.t.sol`, `test/gas/KeeperResolveBetWorstCaseGas.t.sol`, `test/gas/KeeperOpenBoxWorstCaseGas.t.sol` (restored to `test/gas/` after the run). The whole-tree compile + full run is 351-09's charge. My `RedemptionStethFallback.t.sol` compiled + ran green alongside the already-adapted corpus (the deleted `KeeperBatchAffiliateDeltaAudit` no longer participates).

## Issues Encountered

- **No pretest patch hook** — `patchForFoundry.js` is not auto-invoked. Each isolation run requires `node scripts/lib/patchForFoundry.js` first (predict the CREATE addresses), then restore `contracts/ContractAddresses.sol` byte-identical from the `.bak` to keep contracts/ frozen. The still-broken gas siblings were sidelined to `/tmp/sidelined_351_06` (forge compiles the WHOLE tree) and restored after.
- **`ContractAddresses.AF_KING` is GONE (not just `AfKing.sol`)** — the surviving POOL-04 receive() tests referenced `ContractAddresses.AF_KING`, not only the deleted `AfKing.sol` import, so the reframe had to repoint the credit SENDER (AF_KING→GAME), not merely drop an import. The GAME symbol (`ContractAddresses.GAME`) is the surviving authorized receive() sender.

## User Setup Required

None.

## Self-Check: PASSED

Created/modified/deleted files:
- FOUND: `test/fuzz/RedemptionStethFallback.t.sol` (modified)
- DELETED (confirmed gone): `test/fuzz/KeeperBatchAffiliateDeltaAudit.t.sol`
- FOUND: `.planning/phases/351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat/351-06-SUMMARY.md`

Task commits exist:
- FOUND: `c5f600bd` (Task 1 — KeeperBatchAffiliateDeltaAudit dropped, 338 deletions)
- FOUND: `aad3aad8` (Task 2 — RedemptionStethFallback adapted)

Scope guard: `git diff --name-only 453f8073 HEAD -- contracts/` = EMPTY (committed AND working-tree); `ContractAddresses.sol` restored byte-identical (sha256 `80fe0dac5203db7d241d5f636ca0b67323262476a36713407ed1529f9073afee`); RedemptionStethFallback 9/9 green in isolation; zero executable `AF_KING`/`AfKing(`/`depositFor`/`.poolOf(`/`.withdraw(` refs at HEAD (the 3 grep hits are drop-marker COMMENTS); `import.*AfKing.sol` count == 0; the 6 RFALL05 ETH-vs-stETH core tests present + green; the two D-351-02 drop-ledger fragments recorded BY NAME + reason for 351-09.

---
*Phase: 351-tst-freeze-determinism-revert-free-ev-cap-two-path-set-mutat*
*Completed: 2026-05-31*
