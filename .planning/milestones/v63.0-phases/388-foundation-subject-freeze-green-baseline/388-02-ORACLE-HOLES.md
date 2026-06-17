# 388-02 — Verifier Oracle-Hole Audit (FND-04, part 1)

**Subject (byte-frozen):** `a8b702a7` — verified `git diff a8b702a7 -- contracts/` empty; `git status --porcelain contracts/` empty throughout.
**Method:** For each invariant / proof test targeting a post-v62 CHANGED surface, establish that the
target code is ACTUALLY exercised (not a vacuous pass). Evidence = (a) handler/fuzz-body read to
confirm the target call is on the action set and reachable, plus (b) a targeted run with the
authoritative storage layout (`forge inspect <C> storage-layout` at the subject) to confirm the
slot constants the test reads are the live fields (a stale slot reads the WRONG field at runtime,
compile stays green — the [[storage-packing-breaks-slot-hardcoded-tests]] / FA-4 landmine).
**Classification:** EXERCISED (target frame confirmed reached) · HOLE (test passes but the target
branch never executes, or reads a stale slot) · N/A (target unchanged post-v62).
**Posture:** AUDIT + INTAKE only. Where an oracle hole requires a NEW assertion, the OWNING sweep
phase builds it — recorded here as a routed closure, NOT fixed in this plan.

> ⚠ No `hardhat compile --force` was run. `forge inspect` regenerated nothing destructive;
> `contracts/ContractAddresses.sol` was restored after each inspect/run and re-confirmed clean.

---

## Authoritative slot key derived at the subject (`forge inspect` @ `a8b702a7`)

The slot constants below are the live fields against which each harness's hardcoded slots were
checked. (Re-derived this plan; consistent with 388-01 FND-02 layout key.)

### `DegenerusGame`
| Field | Slot / offset |
|-------|----------------|
| `dailyIdx` | slot 0, byte 3 (uint24) |
| `claimablePool` | slot 1, offset 16 (uint128 high half) |
| `prizePoolsPacked` (future<<128 \| next) | slot 2 |
| `balancesPacked` (claimable low / afking high) | slot 7 |
| `rngWordByDay` | slot 10 |
| `lootboxRngPacked` (low 48 = index cursor) | slot 34 |
| `lootboxRngWordByIndex` | slot 35 |
| `decBucketOffsetPacked` | slot 44 |
| `terminalDecBucketBurnTotal` | slot 49 |

### `StakedDegenerusStonk`
| Field | Slot / offset |
|-------|----------------|
| `_totalSupply` / `_pendingRedemptionEthValue` / `_pendingResolveDay` | slot 0 (packed: off0 uint128 / off16 uint96 / off28 uint24) — read via public getters |
| `balanceOf` | slot 1 |
| `poolBalances` (uint128[5]) | slot 2 |
| `pendingRedemptions` | slot 5 |
| `redemptionPeriods` | slot 6 |
| `pendingByDay` | slot 7 |

---

## Per-test oracle-hole verdicts

| # | Test / harness | Target changed surface (v63) | Verdict | Evidence | Routed closure (HOLE only) |
|---|----------------|------------------------------|---------|----------|----------------------------|
| 1 | `RngWindowFreeze.inv.t.sol` + `RngWindowFreezeHandler.sol` | RNG-window freeze over the repacked slots (rngWordByDay / lootboxRngPacked cursor / lootboxRngWordByIndex / dailyIdx) | **EXERCISED** | Handler slots 10 / 34 / 35 + dailyIdx@(slot0,byte3) all MATCH the subject `forge inspect`. Built-in `afterInvariant` non-vacuity gate (`ghost_windowsOpened>0` AND `ghost_inWindowActions>0`) + falsifiability test. Focused run: `test_freezeWindowIsExercised_nonVacuous` PASS (drives open→in-window action→close, `ghost_inWindowActions>0`); `test_invariantCatchesSeededInWindowMutation` PASS (seeded in-window mutation of `rngWordByDay[snapDay]` → detector fires). | — |
| 2 | `RedemptionInvariants.inv.t.sol` + `RedemptionHandler.sol` (legacy 7-INV) | Redemption submit/claim conservation + live-vs-gameOver path under the rework | **HOLE** (two distinct holes) | (i) `setUp()` (lines 25-32) does NOT call `handler.setCoinflip()` or `handler.setStethMock()` — so the claim/resolve lifecycle and the stETH-fallback leg are never wired. Short campaign (8×24): `calls_claim: 0`, `ghost_periodsResolved: 0` after 192 calls → claim/resolve target NEVER reached; INV-08 split-conservation (`ethDirect+lootboxEth==totalRolledEth`) is a `0==0` tautology. (ii) Stale slot constants `SLOT_PENDING_BURNIE=10`, `SLOT_SUPPLY_SNAPSHOT=13`, `SLOT_PERIOD_INDEX=14`, `SLOT_PERIOD_BURNED=15` (lines 20-23): at the subject slot 13/14/15 are NOT those fields (the supply snapshot now lives inside the `pendingByDay[day]` packed struct at slot 7); INV-05 `vm.load(13)` and INV-07 `vm.load(10)` read garbage/zero → pass vacuously. | **→ 390 SOLVENCY-SPINE.** The robust redemption-rework coverage lives in test #4 + `RedemptionAccounting.t.sol` (the v44-keyed handler). Closure: either (a) retire/quarantine the legacy 7-INV harness as superseded, or (b) wire its `setUp` (`setCoinflip`+`setStethMock`) and recalibrate INV-05/07 slots to `pendingByDay`@7 packed reads, and replace the INV-08 tautology with the event-parsed `RedemptionStethFallback`-style branch assertion. Do NOT rely on this harness's green for SOLV-03/05/06. |
| 3 | `RedemptionAccounting.t.sol` (v44 per-day-keyed handler harness, Plan-306-01) | Redemption per-(player,day) accounting + roll/flipDay write-once under the rework | **EXERCISED** (shares `RedemptionHandler`; reads per-day ghosts, not the stale flat slots) | Uses the v44-keyed per-day ghost surface (`ghost_perDay_*`) + `_readPendingByDay` at `SLOT_PENDING_BY_DAY=7` (MATCHES subject). The handler's `_readPendingByDay`/`pendingRedemptions`@5 slots are subject-correct. Reads via getters for the packed scalars. (Confirm the harness's own `setUp` wires coinflip/stETH — see closure note; if it shares the legacy `setUp` omission, it inherits hole #2's wiring gap → flag to 390.) | — (verify wiring at 390 as a belt-and-suspenders check) |
| 4 | `RedemptionStethFallback.t.sol` | The CEI / stETH-before-ETH ordering (V62-03 class) + the new redemption split (direct/lootbox/dust-forfeit legs) + GAME-only receive() | **EXERCISED** | 10/10 deterministic branch-proofs PASS at the subject. EACH asserts the branch it intends WAS taken (false-confidence guard T-327-02-FC1/2/3): e.g. `(b)` asserts `gameEthBefore==0 && < maxIncrement` BEFORE asserting the stETH leg ran with `claimable[SDGNRS]/claimablePool UNCHANGED`; `(b2)` runs the REAL lootbox forward un-mocked (no-strand); `(d)` fail-closed leaks-nothing. Seed slots 7 (balancesPacked) / 1@off16 (claimablePool) MATCH subject. NOTE: the dead `vm.mockCall(claimCoinflipsForRedemption,…)` is a no-op at the subject (selector deleted, real path no longer calls it) — harmless, NOT a hole. | — |
| 5 | `EthSolvency.inv.t.sol` (+ `SolvencyObligations`, `GameHandler`, `WhaleHandler`) | claimablePool / ETH solvency master invariant | **EXERCISED for the game-side spine; N/A for the redemption-credit legs** | `invariant_ethSolvency` reads `SolvencyObligations.obligations(game)` via getters (slot-drift-immune) and asserts `balance >= obligations` — a real test driven by GameHandler/WhaleHandler/VRFHandler. BUT its action set does NOT include the sDGNRS redemption credit legs (`creditRedemptionDirect`/`resolveRedemptionLootbox`/dust-forfeit), so it does not exercise the redemption-rework credit path. | **→ 390 SOLVENCY-SPINE.** Not a hole in what it asserts (getters, real). Routed gap: the redemption-credit legs' effect on `claimablePool` is covered by tests #3/#4, not here. 390 confirms no claimablePool path is left un-netted across the two harnesses; if a sweep wants ONE always-on net over both, add a redemption action to a solvency handler (build at 390). |
| 6 | `PoolConservation.inv.t.sol` + `PoolFlowHandler.sol` | 4-pool conservation under consolidation/skim/jackpot transfers (the JackpotModule delta-fold surface) | **EXERCISED** | Invariants read the live `*View()` getters (`current/next/future/claimablePool`) — slot-drift-immune. `afterInvariant` gates `ghost_advances>0`; `test_poolTransfersExercised_nonVacuous` drives real transfers; `test_invariantIsFalsifiable_unbackedCreditMint` seeds an unbacked `futurePrizePool` inflation (slot 2 = `prizePoolsPacked`, MATCHES subject) and asserts BOTH bounds break, then restore. | — |
| 7 | `BurnieEmissionSeeds.t.sol` | The 200k/day×20d coinflip seed schedule + sDGNRS auto-rebuy latch + VAULT claim-into-allowance | **EXERCISED** | 5/5 PASS at the subject. `_stakeOf` decodes `coinflipStakePacked` at root slot 0, 2-days/slot, 128-bit lanes (MATCHES the subject pack); `_resolveDay` drives `processCoinflipPayouts` as GAME (the AdvanceModule call shape). Asserts seeds placed days 1-20 + nothing minted up front; sDGNRS win mints-to-wallet + latch arms at day 20 (one-shot); `test_VaultSeedWinsClaimIntoMintAllowance` carries an explicit `assertGt(expected,0,"non-vacuity")`. | — |
| 8 | `DecimatorOffsetIsolation.t.sol` | Terminal-decimator offset keyed at `[lvl+1]` (DEC-ALIAS fix) + the uint32 claim-seed draw path | **EXERCISED** | 1/1 PASS at the subject. Slots `decBucketOffsetPacked=44` / `terminalDecBucketBurnTotal=49` cited from `forge inspect`, MATCH subject. Self-validating: plants a SENTINEL at `[X]`, seeds every (denom,sub) burn total to force the path PAST `totalWinnerBurn==0` into the offset write, asserts `returnAmountWei==0` (winners present ⇒ pool held), `[X]` byte-unchanged, terminal offsets land at `[X+1]` (`!=0` and `!=SENTINEL`). | — |
| 9 | `StakedStonkRedemption.t.sol` (per-function fuzz; supporting evidence) | sStonk per-function redemption post-conditions (burn-lands / resolve-writes / claim-reads / same-day-aggregate / supply-cap / EV-cap) | **EXERCISED** | Slot constants `pendingByDay=7` / `pendingRedemptions=5` cited "POST RT-PACKING-12", MATCH subject; seeds slot 7 (balancesPacked) / 1 (claimablePool). Per-function fuzz isolates a single post-condition each. (Listed for completeness — not in the plan's enumerated set, but it co-covers the redemption surface that hole #2 misses.) | — |

---

## Decimator uint32 claim-seed — note on the entropy-distribution oracle

`DecClaimRound.rngWord` was narrowed uint256→uint32 (the prime RNG lead, §7b rng-freeze map / RNG-02).
Test #8 proves the SLOT-ISOLATION of the terminal write and that the claim path is reached, but **no
existing oracle asserts the per-bucket reward DISTRIBUTION is unbiased across many winners of one
level** (the 32-bit entropy floor). That is not a slot/vacuity hole — it is a MISSING property, not a
false-green one. **Routed → 391 RNG-SPINE** (RNG-02): build a distribution/grinding oracle over the
uint32 claim seed (intaken as candidate `FC-391-04` in the finding-candidate ledger).

---

## Summary

| Verdict | Tests |
|---------|-------|
| EXERCISED | #1 RngWindowFreeze · #3 RedemptionAccounting · #4 RedemptionStethFallback · #6 PoolConservation · #7 BurnieEmissionSeeds · #8 DecimatorOffsetIsolation · #9 StakedStonkRedemption |
| EXERCISED (game-side) / gap routed | #5 EthSolvency (redemption-credit legs not in its action set → 390) |
| **HOLE** | **#2 RedemptionInvariants (legacy 7-INV): (i) un-wired claim/resolve + stETH leg [`calls_claim:0`]; (ii) stale slots 10/13/14/15 → INV-05/07 vacuous; INV-08 a `0==0` tautology → 390** |
| MISSING-property (not false-green) | decimator uint32 distribution oracle → 391 (RNG-02) |

**Net:** every changed-surface invariant/proof test EXCEPT the legacy `RedemptionInvariants` 7-INV
harness is confirmed to exercise its target at the subject (slot-validated against `forge inspect` +
non-vacuity/falsifiability where the harness provides them, deterministic branch-proofs otherwise).
The single HOLE (legacy redemption 7-INV) is fully superseded by tests #3/#4 for the redemption
rework; its closure is routed to 390 and NOT fixed in this plan. One MISSING distribution property
(decimator uint32) is routed to 391. `contracts/` stayed byte-frozen at `a8b702a7` throughout.
