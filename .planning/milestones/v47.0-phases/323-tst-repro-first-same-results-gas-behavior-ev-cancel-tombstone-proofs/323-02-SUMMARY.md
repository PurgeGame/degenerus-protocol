---
phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs
plan: 02
subsystem: testing
tags: [hardhat, mocha, lootbox, burnie-lootbox-removal, presale-box, per-currency-spin-caps, redemption-segregation, storage-slots]

requires:
  - phase: 322-impl-the-one-batched-contract-diff-all-7-items
    provides: "the frozen v47.0 contract subject at fb29ed51 (BURNIE-lootbox removal, 2-bool _resolveLootboxCommon, Pool.PresaleBox, per-currency spin caps, 175% submit-time redemption segregation via CHECKED pullRedemptionReserve, DegenerusGame storage-layout shift)"
provides:
  - "A clean hardhat compile against the v47 ABI + every repaired *.test.js running to completion (no removed-symbol runtime aborts)"
  - "Removed-by-design deletion of the BURNIE-lootbox test surface (openBurnieLootBox / gamePurchaseBurnieLootbox / BurnieLootOpen); BURNIE->tickets KEPT"
  - "Pool.Earlybird -> Pool.PresaleBox retarget; v47 2-bool/11-arg _resolveLootboxCommon positional asserts; per-currency spin caps (ETH 25 / BURNIE 15 / WWXRP 5)"
  - "A recorded, classified non-widening v47 hardhat baseline for the in-scope files (199 pass / 3 fail / 5 pending across the 10 plan files + 1 same-surface consistency file)"
  - "AfKing shared-fixture un-brick (deployFixture.js getConstructorArgs supplies AfKing's 3 ctor args) — a pre-existing v46 break that bricked every fixture-based hardhat test"
affects: [323-04-dgas-dspin, 323-05-tomb-04, 324-terminal]

tech-stack:
  added: []
  patterns:
    - "v46-baseline worktree comparison: `git worktree add --detach 16e9668a` + symlinked node_modules to run each hardhat file at the prior milestone, giving a definitive per-file v47-vs-v46 failure diff for the non-widening attestation"
    - "Removed-by-design discipline: a test of a v47-removed surface is DELETED (replaced with a `removed-by-design` source/ABI absence assertion), never `.skip`-hidden; surviving coverage retargeted"

key-files:
  created:
    - .planning/phases/323-.../323-02-SUMMARY.md
    - .planning/phases/323-.../deferred-items.md
  modified:
    - test/unit/EventSurfaceUnification.test.js
    - test/unit/LootboxConsolation.test.js
    - test/unit/LootboxWholeTicket.test.js
    - test/unit/LootboxAutoResolveSilentColdBust.test.js
    - test/edge/LootboxAutoResolveRegression.test.js
    - test/gas/LootboxOpenGas.test.js
    - test/unit/DegenerusVault.test.js
    - test/integration/CrossSurfaceTicketMixing.test.js
    - test/unit/DegenerusStonk.test.js
    - test/gas/Phase268GasRegression.test.js
    - test/stat/DegenerettePerNEvExactness.test.js
    - test/helpers/deployFixture.js

key-decisions:
  - "BURNIE-lootbox tests removed-by-design (surface gone — terminal-paradox closure), replaced with source/ABI-absence assertions; never .skip"
  - "v47 _resolveLootboxCommon arity 5-bool/14-arg -> 2-bool/11-arg: emitLootboxEvent moved 10th->8th positional, payColdBustConsolation 11th->9th — retargeted in 3 source-structural test files (EventSurfaceUnification, LootboxAutoResolveSilentColdBust, LootboxAutoResolveRegression)"
  - "DegenerusStonk burn tests: fund claimableWinnings[SDGNRS] (slot 7 + claimablePool slot-1-upper-128) so the v47 175% segregation via CHECKED pullRedemptionReserve succeeds; the stETH-spillover preview taken BEFORE funding (preview math is byte-identical to v46) — the segregation revert is intended R3 fail-closed behavior, NOT a contract defect"
  - "AfKing 3-arg constructor supplied in the shared deployFixture.js (pre-existing v46 break, byte-identical helper v46->v47) — mirrors foundry DeployProtocol.sol:126; one-line test-helper repair that un-bricks the whole fixture-based hardhat suite"
  - "Phase268 LootboxRng slot constants shifted 35/36 -> 37/38 (forge inspect at fb29ed51), matching the 323-01 foundry slot-shift"

patterns-established:
  - "Non-widening discipline: every repaired hardhat test asserts the same INTENT against the v47 surface; residual failures classified pre-existing-v46 (verified in a v46 worktree) vs v47-delta vs surfaced-defect; nothing weakened or silenced"

requirements-completed: []

duration: ~3h
completed: 2026-05-25
---

# Phase 323 Plan 02: HARDHAT Test Repair Summary

**Repaired the HARDHAT (`*.test.js`) tree against the frozen v47.0 contract subject (`fb29ed51`): removed the BURNIE-lootbox surface, retargeted Pool.PresaleBox + the 2-bool `_resolveLootboxCommon` arity + per-currency spin caps + shifted storage slots + the new 175% redemption segregation, un-bricked the shared AfKing fixture, and recorded a classified non-widening v47 hardhat baseline — zero contract edits, zero defects surfaced.**

## Performance
- **Duration:** ~3h
- **Completed:** 2026-05-25
- **Tasks:** 3/3 (Task 1 surface retarget, Task 2 spin caps, Task 3 classified baseline)
- **Files modified:** 12 (`test/**` only; zero `contracts/*.sol` mainnet edits)

## Accomplishments
- `npx hardhat compile` is clean against the v47 ABI; every in-scope `*.test.js` runs to completion (no `function does not exist` / `event fragment missing` / stale-enum runtime aborts).
- Removed the BURNIE-lootbox test surface (removed-by-design, not skipped): `openBurnieLootBox` / `gamePurchaseBurnieLootbox` / `BurnieLootOpen` describe/it blocks deleted across 5 files; `game.lootboxBurnie` view gone; **BURNIE->tickets KEPT** (`gamePurchaseTicketsBurnie` test retained).
- Retargeted the v47 deltas: `Pool.Earlybird -> Pool.PresaleBox`, the 2-bool/11-arg `_resolveLootboxCommon` positional asserts, per-currency spin caps (ETH 25 / BURNIE 15 / WWXRP 5), and the DegenerusGame `lootboxRng` storage-slot shift (35/36 -> 37/38).
- Repaired the 2 DegenerusStonk gambling-burn tests for the v47 175% submit-time segregation (fund `claimableWinnings[SDGNRS]`); proved the segregation revert is intended R3 fail-closed behavior, not a defect.
- Un-bricked the shared `deployFixture.js` (pre-existing v46 AfKing 3-arg constructor break) — a one-line test-helper fix that restored the entire fixture-based hardhat suite from 0-passing.

## Task Commits
1. **Task 1: removed-surface retarget + Pool.PresaleBox + 2-bool arity + AfKing fixture + slot shift** — `55dc8ed4` (test)
2. **Task 2: per-currency spin caps in Degenerette gas + EV tests** — `d88fc87f` (test)
3. **Same-surface consistency: LootboxAutoResolveRegression 2-bool arity** — `6f2a08b5` (test)

(Task 3 — the classified baseline — produced no file edits beyond `deferred-items.md`; results recorded below.)

## v47 HARDHAT regression baseline (Task 3 — non-widening attestation)

Per-file v47 result (each measured against the v46 closure HEAD `16e9668a` in a throwaway worktree for classification). Batched single-process run of the 10 plan files + the 1 same-surface consistency file: **199 passing / 3 failing / 5 pending**. The heavy `DegenerettePerNEvExactness` (9-min Monte Carlo) measured separately at **9 passing / 0 failing / 5 pending**.

| File | v47 result | v46 baseline | Classification |
|------|-----------|--------------|----------------|
| EventSurfaceUnification.test.js | 26 / 0 | (broke at v47: BurnieLootOpen + 14-arg) | repaired (BURNIE-removal + 2-bool arity) |
| LootboxConsolation.test.js | 15 / 0 | passing | repaired (removed [04a] BURNIE cold-bust) |
| LootboxWholeTicket.test.js | 39 / 0 | passing | repaired (removed [05c] BurnieLootOpen) |
| LootboxAutoResolveSilentColdBust.test.js | 8 / 0 | passing | repaired (2-bool arity [02b]) |
| LootboxAutoResolveRegression.test.js | 15 / 0 (1 pend) | 15 / 0 | repaired (2-bool arity [03a/b/d]) — same v47 delta |
| LootboxOpenGas.test.js | 0 / 0 (2 pend) | n/a | repaired (removed openBurnieLootBox gas block; 2 pending = reachOpenableLootbox soft-skip) |
| DegenerusVault.test.js | 46 / **2** | 47 / **2** | repaired (-1 = removed-by-design BURNIE-lootbox test); the **2 fails are PRE-EXISTING v46** |
| CrossSurfaceTicketMixing.test.js | 11 / 0 (1 pend) | passing | repaired (comment-only openBurnieLootBox; 1 pending = soft-skip) |
| DegenerusStonk.test.js | 39 / 0 | 39 / 0 (after AfKing fix) | repaired (Pool.PresaleBox + claimable-segregation funding) |
| Phase268GasRegression.test.js | 0 / **1** (1 pend) | 0 / **1** (1 pend) | repaired (spin caps + slot shift); the **1 fail is PRE-EXISTING v46** |
| DegenerettePerNEvExactness.test.js | 9 / 0 (5 pend) | passing | repaired (dead spin-cap rename + dead-helper slot); **EV UNCHANGED (same-results)** |

**3 residual failures — ALL classified PRE-EXISTING v46 (verified failing at `16e9668a`):**
1. `DegenerusVault` `gameSetAutoRebuy reverts when caller is not vault owner` — `gameSetAutoRebuy is not a function`. The function exists in NEITHER v46 nor v47 `DegenerusVault.sol` (legacy ETH-auto-rebuy removed in v46.0); the test still references it. Failed identically at v46. Out of v47-delta scope (`deferred-items.md`).
2. `DegenerusVault` `gameSetAutoRebuyTakeProfit accessible by vault owner` — same root cause, same pre-existing classification.
3. `Phase268GasRegression` `v37.0 SURF-06 advanceGame STAGE_PURCHASE_DAILY gas within ±2K of v36.0 baseline` — measured ~694k–748k vs the stale pinned `ADVANCE_GAME_DECIMATOR_STAGE_REF = 908_320`. Failed at v46 with a near-identical measurement (693_459); v47 differs by codegen noise. A stale v36.0 gas pin on the `advanceGame` stage-6 path (NOT the Degenerette spin-cap path this plan edited). Pre-existing v46, out of scope (`deferred-items.md`).

**EV-exactness (same-results) check:** `DegenerettePerNEvExactness` STAT-01/05/07 assertions PASS UNCHANGED at v47 — the per-currency-cap rename does not move per-N EV (N<=4 is under every cap), exactly as the plan predicted. No EV drift; no STOP triggered.

## Contract defects surfaced
**None.** Two v47-delta failures (the 2 DegenerusStonk gambling-burn `panic 0x11` overflows) were investigated as potential defects and proven to be the intended v47 R3 fail-closed behavior: the gambling burn physically segregates the MAX (175%) payout out of `claimableWinnings[SDGNRS]` via the new CHECKED `pullRedemptionReserve`, which reverts by design when that segregation source is unfunded. The repair funds `claimableWinnings[SDGNRS]` (mirroring the 323-01 foundry repair at `StakedStonkRedemption.t.sol:97-105`); the contract was not touched and no assertion was weakened. No `contracts/*.sol` (mainnet) file was edited — the subject stays frozen at `fb29ed51`.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 3 - Blocking] AfKing 3-arg constructor missing from the shared hardhat fixture**
- **Found during:** Task 1 (running DegenerusStonk — all 39 tests aborted at deploy)
- **Issue:** `test/helpers/deployFixture.js` `getConstructorArgs` returned `[]` for the `AF_KING` key, but `AfKing` has a 3-arg constructor (inserted into DEPLOY_ORDER at Phase 318, v46). Every `loadFixture(deployFullProtocol)` threw `incorrect number of arguments to constructor`, bricking EVERY fixture-based hardhat test. The helper is byte-identical v46->v47, so this was a PRE-EXISTING v46 break (confirmed: the v46 worktree had the same `[]`). It blocks the entire in-scope hardhat suite from running.
- **Fix:** Return `[5_000_000_000n, 885_000_000n, 10_000_000_000n]` for `AF_KING` — the same args the foundry helper `test/fuzz/helpers/DeployProtocol.sol:126` uses (immutables only, no cross-calls, do not affect predicted address).
- **Files modified:** `test/helpers/deployFixture.js`
- **Verification:** DegenerusStonk went 0/39 -> 37/2 -> 39/0; the v46 worktree with this fix = 39/0 (proves the 2 then-failures were the v47 segregation delta, since fixed).
- **Committed in:** `55dc8ed4`

**2. [Rule 1 - v47-delta classification] LootboxAutoResolveRegression 2-bool arity (file not in the plan's listed set)**
- **Found during:** Task 3 (representative-subset sanity run of the `test:evt-uni` bundle)
- **Issue:** `test/edge/LootboxAutoResolveRegression.test.js` asserts the OLD 5-bool/14-arg `_resolveLootboxCommon` positional layout (reading `emitLootboxEvent` at the v46 10th positional). It is the SAME v47 contract delta the plan charters across the lootbox-event surface, but the file was not in the plan's `files_modified` list. Was 15/0 at v46 — a genuine v47-delta, not pre-existing.
- **Fix:** Retargeted the 3 positional asserts ([03a]/[03b]/[03d]) to the v47 2-bool layout (emitLootboxEvent 8th, payColdBustConsolation 9th), identical to the EventSurfaceUnification [03c] repair.
- **Files modified:** `test/edge/LootboxAutoResolveRegression.test.js`
- **Verification:** 15/0 at v47 (matches v46 baseline 15/0; non-widening).
- **Committed in:** `6f2a08b5`

---

**Total deviations:** 2 ([Rule 3] shared-fixture un-brick, [Rule 1] same-surface arity consistency). Both directly attributable to a v47 contract delta (AfKing-ctor break surfaced by the deploy path; the 2-bool arity delta). No scope creep beyond the v47 lootbox-event/redemption surface; pre-existing v46 failures were classified and deferred, never fixed or hidden.

## Issues Encountered
- **Concurrent-hardhat slowdown + transient `ContractAddresses.sol` patch:** `deployFixture.js` patches `contracts/ContractAddresses.sol` during fixture deploys (and restores via an `after()` hook). The mocha post-run file-unloader throws a harmless `MODULE_NOT_FOUND` cleanup error that can prevent the restore from firing, leaving `ContractAddresses.sol` transiently dirty. Resolved by `git checkout -- contracts/ContractAddresses.sol` before each commit; the final working tree is clean and zero mainnet contracts changed. Running tests one-at-a-time (not concurrently) avoided the in-process EDR fixture contention that earlier inflated a run to 11 minutes.

## Next Phase Readiness
- Both test frameworks now compile + run against the frozen v47 subject (foundry via 323-01, hardhat via 323-02) — the Wave-2 proof plans (323-04 DGAS-05/DSPIN-02, 323-05 TOMB-04) have a clean, classified baseline.
- The 3 pre-existing-v46 hardhat residuals (`deferred-items.md`) are a future test-hygiene concern (out of the v47-delta repair scope), not a v47 regression.

## Self-Check: PASSED
- `323-02-SUMMARY.md` + `deferred-items.md` created — verified on disk.
- 3 task commits exist (`55dc8ed4`, `d88fc87f`, `6f2a08b5`) — verified in `git log`.
- All 12 modified files present + non-empty; all changes confined to `test/` (`git diff --name-only 0dd8a461 HEAD` is 100% `test/`).
- Zero `contracts/*.sol` (mainnet) edits vs frozen `fb29ed51` — `git diff --name-only fb29ed51 HEAD -- contracts/ | grep -v contracts/test/` is empty.
- v47 hardhat baseline recorded + every residual classified (3 pre-existing-v46 verified against the `16e9668a` worktree; 0 surfaced defects; EV same-results preserved).

---
*Phase: 323-tst-repro-first-same-results-gas-behavior-ev-cancel-tombstone-proofs*
*Completed: 2026-05-25*
