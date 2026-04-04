# 181-03: External Call Revert Audit (AGSAFE-03)

**Scope:** Every external call (non-delegatecall) made from any function reachable during `advanceGame` execution, including the GameOverModule path.

**Methodology:** For each call, identify: call site, target contract+function, access control, whether it can revert, failure tolerance strategy, and final verdict.

---

## External Calls from AdvanceModule (advanceGame path)

### EXT-01: coinflip.creditFlip(caller, amount)

- **Call site:** AdvanceModule lines 201-205, 243-249, 432-436 (bounty payment to advanceGame caller)
- **Target:** BurnieCoinflip.sol:895-901 (`creditFlip`)
- **Access control:** `onlyFlipCreditors` modifier (lines 194-203). Allows GAME, QUESTS, AFFILIATE, ADMIN. AdvanceModule runs via delegatecall from GAME contract, so `msg.sender` on the `creditFlip` call is GAME. **PASSES.**
- **Can revert:** NO.
  - `creditFlip` early-returns on `player == address(0) || amount == 0` (line 899).
  - Calls `_addDailyFlip(player, amount, 0, false, false)` (line 900). With `recordAmount=0`, the boon consumption branch (line 632-643) is skipped entirely.
  - `_addDailyFlip` with `canArmBounty=false` skips all bounty logic (line 659).
  - Remaining operations: mapping writes (`coinflipBalance`, `_updateTopDayBettor`) and event emit -- pure storage ops, cannot revert.
  - `amount` is computed as `(ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT * bountyMultiplier) / PriceLookupLib.priceForLevel(lvl)`. `PriceLookupLib.priceForLevel` returns a non-zero constant for any level (lookup table). Division by non-zero cannot overflow. Result is always > 0 for any level.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Pure storage operations with no revert paths after access control passes.

---

### EXT-02: coinflip.processCoinflipPayouts(bonusFlip, currentWord, day)

- **Call site:** AdvanceModule line 876 (rngGate), line 944/948 (_gameOverEntropy normal), line 983/984 (_gameOverEntropy fallback), line 1548 (_backfillGapDays loop)
- **Target:** BurnieCoinflip.sol:802-886 (`processCoinflipPayouts`)
- **Access control:** `onlyDegenerusGameContract` modifier (lines 187-190). Requires `msg.sender == GAME`. AdvanceModule is delegatecalled from GAME, so external calls from AdvanceModule have `msg.sender == GAME` from the callee's perspective. **PASSES.**
- **Can revert:** NO (with one callback consideration).
  - Line 808: `keccak256` + modular arithmetic -- pure computation, no revert.
  - Lines 815-831: Roll computation, percentage assignment -- pure arithmetic, no revert.
  - Line 826: `game.lootboxPresaleActiveFlag()` -- view call on GAME contract (returns bool from storage). Cannot revert.
  - Line 837-840: Storage write (`coinflipDayResult`) -- cannot revert.
  - Lines 843-863: Bounty resolution path. `_addDailyFlip(to, slice, 0, false, false)` -- same analysis as EXT-01, cannot revert. **Callback: `game.payCoinflipBountyDgnrs(to, slice, currentBounty_)` at line 858.** Target: DegenerusGame.sol:396-419. Access: requires `msg.sender == COIN || msg.sender == COINFLIP`. Caller is BurnieCoinflip (COINFLIP). **PASSES.** Function body: early-returns on `player == address(0)`, `winningBet < threshold`, `bountyPool < threshold`, `poolBalance == 0`, `payout == 0` (lines 405-413). Otherwise calls `dgnrs.transferFromPool` which caps to available balance and cannot revert (see EXT-10). **Cannot revert.**
  - Line 866: `flipsClaimableDay = epoch` -- storage write.
  - Lines 869-871: `currentBounty` update -- unchecked wrapping addition, explicitly acceptable per comment.
  - Line 885: `_claimCoinflipsInternal(ContractAddresses.SDGNRS, false)` -- internal call. This processes sDGNRS auto-claims. It calls `game.syncAfKingLazyPassFromCoin(player)` and potentially `game.hasDeityPass(player)` -- both view-like calls on GAME that return storage values. The `mintable` result is not minted in this context (sDGNRS doesn't mint BURNIE). All operations are storage writes. **Cannot revert.**
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- All internal paths are pure computation and storage writes. The `payCoinflipBountyDgnrs` callback is guarded by multiple early-return checks and uses capped `transferFromPool`.

---

### EXT-03: quests.rollDailyQuest(day, rngWord)

- **Call site:** AdvanceModule line 275
- **Target:** DegenerusQuests.sol:331-348 (`rollDailyQuest`)
- **Access control:** `onlyGame` modifier (lines 318-321). Requires `msg.sender == GAME`. **PASSES.**
- **Can revert:** NO.
  - Line 333: Idempotent guard `if (quests[0].day == day) return;` -- returns early if already rolled for this day.
  - Lines 336-345: `_seedQuestType` writes storage. `_bonusQuestType` is pure computation (weighted random selection from entropy). No external calls. No revert paths.
  - Lines 347-348: Event emissions.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Idempotent, pure computation + storage writes.

---

### EXT-04: quests.rollLevelQuest(questEntropy)

- **Call site:** AdvanceModule line 401
- **Target:** DegenerusQuests.sol:1776-1780 (`rollLevelQuest`)
- **Access control:** `onlyGame` modifier. **PASSES.**
- **Can revert:** NO.
  - Line 1778: `_bonusQuestType(entropy, type(uint8).max, decAllowed)` -- pure computation.
  - Line 1779: `++levelQuestVersion` -- unchecked increment, cannot overflow in practice (uint256).
  - Two storage writes total. No external calls.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Pure computation + two storage writes.

---

### EXT-05: quests.clearLevelQuest()

- **Call site:** AdvanceModule line 269
- **Target:** DegenerusQuests.sol:1783-1785 (`clearLevelQuest`)
- **Access control:** `onlyGame` modifier. **PASSES.**
- **Can revert:** NO.
  - Line 1784: `levelQuestType = 0;` -- single storage write. That's it.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Single storage write, no possible revert.

---

### EXT-06: sdgnrs.hasPendingRedemptions()

- **Call site:** AdvanceModule rngGate line 883, _gameOverEntropy lines 955, 994
- **Target:** StakedDegenerusStonk.sol:566-568 (`hasPendingRedemptions`)
- **Access control:** None (view function). No modifier.
- **Can revert:** NO.
  - Returns `pendingRedemptionEthBase != 0 || pendingRedemptionBurnieBase != 0` -- two storage reads and a boolean comparison. Pure view.
- **Failure tolerance:** VIEW (cannot fail)
- **Verdict:** SAFE -- View function, pure storage reads.

---

### EXT-07: sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)

- **Call site:** AdvanceModule rngGate lines 888-891, _gameOverEntropy lines 960-961, 999-1000
- **Target:** StakedDegenerusStonk.sol:575-600 (`resolveRedemptionPeriod`)
- **Access control:** `if (msg.sender != ContractAddresses.GAME) revert Unauthorized()` (line 576). Caller is GAME (AdvanceModule delegatecalled from GAME). **PASSES.**
- **Can revert:** NO.
  - Line 579: Early return if no pending redemptions (`pendingRedemptionEthBase == 0 && pendingRedemptionBurnieBase == 0`). This is the same check `hasPendingRedemptions` performs, so this path is only reached when there ARE pending redemptions (EXT-06 returned true).
  - Lines 582-583: `rolledEth` arithmetic. `roll` is always in range [25, 175] (computed as `(currentWord >> 8) % 151 + 25`). Division by 100. `pendingRedemptionEthBase > 0` (confirmed by guard). No overflow risk (ETH amounts * 175 / 100 fits uint256).
  - Lines 583: `pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth`. Since `pendingRedemptionEthValue >= pendingRedemptionEthBase` (invariant maintained by `_submitGamblingClaim` which adds to both), subtraction cannot underflow. Addition of `rolledEth` cannot overflow.
  - Lines 587-590: BURNIE computation, same pattern. Safe arithmetic.
  - Lines 594-598: Storage write for period result.
  - Line 599: Event emission.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Arithmetic within proven bounds, storage writes only. Only called after hasPendingRedemptions() returns true.

---

### EXT-08: affiliate.affiliateTop(lvl)

- **Call site:** AdvanceModule line 562 (inside `_rewardTopAffiliate`)
- **Target:** DegenerusAffiliate.sol:629-632 (`affiliateTop`)
- **Access control:** None (view function). No modifier.
- **Can revert:** NO.
  - Returns `affiliateTopByLevel[lvl]` -- mapping read, returns `(address(0), 0)` if no affiliate exists.
- **Failure tolerance:** VIEW (cannot fail)
- **Verdict:** SAFE -- View function, pure mapping read.

---

### EXT-09: dgnrs.poolBalance(Pool.Affiliate)

- **Call site:** AdvanceModule lines 565-566 and 580-581 (inside `_rewardTopAffiliate`)
- **Target:** StakedDegenerusStonk.sol:384-386 (`poolBalance`)
- **Access control:** None (view function). No modifier.
- **Can revert:** NO.
  - Returns `poolBalances[_poolIndex(pool)]`. `_poolIndex` maps the Pool enum to an array index -- pure computation. Array access is bounds-checked at compile time via the enum.
- **Failure tolerance:** VIEW (cannot fail)
- **Verdict:** SAFE -- View function, pure storage read.

---

### EXT-10: dgnrs.transferFromPool(Pool.Affiliate, top, dgnrsReward)

- **Call site:** AdvanceModule line 570-574 (inside `_rewardTopAffiliate`)
- **Target:** StakedDegenerusStonk.sol:405-424 (`transferFromPool`)
- **Access control:** `onlyGame` modifier. Caller is GAME. **PASSES.**
- **Can revert:** ONLY if `to == address(0)` (line 407: `revert ZeroAddress()`). But `to` is `top` from `affiliate.affiliateTop(lvl)`, and the call is guarded by `if (top != address(0))` at line 564. **Cannot revert in practice.**
  - Line 406: `if (amount == 0) return 0` -- safe early return. `dgnrsReward` could be 0 if `poolBalance` is 0, but `poolBalance` check at line 564 is not an explicit guard. However, even if `dgnrsReward == 0`, `transferFromPool` returns 0 harmlessly.
  - Lines 408-416: `_poolIndex` + bounds-capped transfer. `if (available == 0) return 0` (line 410). `if (amount > available) amount = available` (line 411-413). Unchecked subtraction is safe since `amount <= available`.
  - Lines 418-424: Self-win burn vs transfer. Pure storage writes.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Capped to available balance, guarded against zero address by caller, cannot revert.

---

### EXT-11: charityResolve.pickCharity(lvl - 1)

- **Call site:** AdvanceModule line 1424 (inside `_finalizeRngRequest`)
- **Target:** GNRUS.sol:452-501 (`pickCharity`)
- **Access control:** `onlyGame` modifier (lines 244-247). Caller is GAME. **PASSES.**
- **Can revert:** CONDITIONAL -- two revert paths exist:
  - Line 453: `if (level != currentLevel) revert LevelNotActive()` -- The game passes `lvl - 1` where `lvl` is the NEW level (old level + 1). GNRUS.currentLevel tracks the current governance level starting at 0 and incremented by `pickCharity` itself (line 458). The game calls `pickCharity(0)` at the first level transition, `pickCharity(1)` at the second, etc. Since GNRUS increments `currentLevel` after each call, the invariant `lvl - 1 == currentLevel` is maintained. **Cannot revert in normal flow.**
  - Line 454: `if (levelResolved[level]) revert LevelAlreadyResolved()` -- Since `pickCharity` is only called once per level transition (inside `_finalizeRngRequest` on fresh request, not retry), and `levelResolved` is set to true within `pickCharity`, this can only trigger if `pickCharity` is called twice for the same level. The `!isRetry` guard at line 1413 prevents double-calling. **Cannot revert in normal flow.**
  - Lines 460-501: Loop over proposals, compute winner, transfer tokens. All pure computation and storage writes. `balanceOf` transfers cannot overflow (total supply is capped).
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Invariant-protected: GNRUS.currentLevel stays in sync with game level transitions. Double-call prevented by `!isRetry` guard.

---

### EXT-12: vrfCoordinator.requestRandomWords(...)

- **Call site:** AdvanceModule line 1340-1348 (inside `_requestRng`)
- **Target:** Chainlink VRF V2.5 coordinator (external contract)
- **Access control:** N/A (external protocol)
- **Can revert:** YES.
  - VRF coordinator reverts if: subscription underfunded, subscription not found, key hash invalid, callback gas too low, etc.
  - This is **INTENTIONAL** -- the game is designed to halt until VRF funding/config is fixed. Comment at line 1339: "Hard revert if Chainlink request fails; this intentionally halts game progress until VRF funding/config is fixed."
- **Failure tolerance:** HARD (intentional -- halts game until VRF operational)
- **Note:** `_tryRequestRng` (lines 1353-1380) wraps the same call in try/catch for the gameover fallback path. The hard-revert `_requestRng` is used on the normal path where VRF availability is a hard requirement.
- **Verdict:** INTENTIONAL -- VRF unavailability halts advanceGame by design. Gameover path uses `_tryRequestRng` with fallback.

---

### EXT-13: steth.submit{value: stakeable}(address(0))

- **Call site:** AdvanceModule line 1327-1331 (inside `_autoStakeExcessEth`)
- **Target:** Lido stETH contract (external protocol)
- **Access control:** N/A (external protocol, accepts any caller with ETH)
- **Can revert:** YES (Lido could be paused, contract limit reached, etc.)
- **Failure tolerance:** WRAPPED -- `try/catch` at lines 1327-1331. Failure emits `StEthStakeFailed(stakeable)` event and continues.
- **Verdict:** SAFE -- Fully wrapped in try/catch. Game continues normally if stETH staking fails.

---

## Self-Calls from GameOverModule

GameOverModule is reached via `advanceGame -> _handleGameOverPath -> delegatecall GameOverModule`. These are **regular calls** (not delegatecall) from address(this) to DegenerusGame, which then delegatecalls the appropriate module.

### EXT-14: IDegenerusGame(address(this)).runTerminalDecimatorJackpot(decPool, lvl, rngWord)

- **Call site:** GameOverModule line 156
- **Target:** DegenerusGame.sol:1109-1130 (`runTerminalDecimatorJackpot`) -> delegatecall to DecimatorModule
- **Access control:** `if (msg.sender != address(this)) revert E()` (line 1114). This is a self-call from address(this) (GameOverModule runs in the GAME contract's context via delegatecall, so `address(this) == GAME`). The regular call to `runTerminalDecimatorJackpot` has `msg.sender == GAME`. **PASSES.**
- **Can revert:** CONDITIONAL.
  - Line 1115-1127: delegatecall to DecimatorModule. If delegatecall fails, `_revertDelegate(data)` propagates the error.
  - Line 1128: `if (data.length == 0) revert E()` -- guards against empty return.
  - DecimatorModule's `runTerminalDecimatorJackpot` performs: winner selection from terminal decimator entries, pro-rata ETH distribution via `_addClaimableEth`. All pure computation and storage writes. If no entries exist, returns the full `poolWei` as refund. **Cannot revert under gameover conditions** (no external calls, just storage operations + event emissions).
- **Failure tolerance:** HARD (but cannot revert -- delegatecall target performs only storage ops)
- **Verdict:** SAFE -- DecimatorModule terminal jackpot is pure computation and storage writes. Returns full refund if no winners.

---

### EXT-15: IDegenerusGame(address(this)).runTerminalJackpot(remaining, lvl + 1, rngWord)

- **Call site:** GameOverModule line 168-169
- **Target:** DegenerusGame.sol:1147-1166 (`runTerminalJackpot`) -> delegatecall to JackpotModule
- **Access control:** `if (msg.sender != address(this)) revert E()` (line 1152). Same analysis as EXT-14. `msg.sender == GAME == address(this)`. **PASSES.**
- **Can revert:** CONDITIONAL.
  - Lines 1153-1163: delegatecall to JackpotModule. `_revertDelegate` propagates failure.
  - Line 1164: `if (data.length == 0) revert E()` -- guards against empty return.
  - JackpotModule's `runTerminalJackpot` performs: Day-5-style bucket distribution to ticketholders via `_distributeJackpotEth`. All operations are: ticket reading, winner selection, `_addClaimableEth` storage writes. **No external calls.** If no tickets exist at `targetLvl`, returns 0 paid. **Cannot revert under gameover conditions.**
- **Failure tolerance:** HARD (but cannot revert -- delegatecall target performs only storage ops)
- **Verdict:** SAFE -- JackpotModule terminal jackpot is pure computation and storage writes. Handles empty ticket queues gracefully.

---

## Additional External Calls from GameOverModule

### EXT-16: charityGameOver.burnAtGameOver()

- **Call site:** GameOverModule line 126
- **Target:** GNRUS.sol:340-352 (`burnAtGameOver`)
- **Access control:** `onlyGame` modifier (lines 244-247). GameOverModule runs via delegatecall from GAME, so the external call comes from the GAME address. **PASSES.**
- **Can revert:** CONDITIONAL.
  - Line 341: `if (finalized) revert AlreadyFinalized()` -- Reverts if called twice. `handleGameOverDrain` has a guard at line 80: `if (gameOverFinalJackpotPaid) return;`, and sets `gameOverFinalJackpotPaid = true` at line 142. This ensures `handleGameOverDrain` (and thus `burnAtGameOver`) is called at most once. **Cannot revert in normal flow.**
  - Lines 342-351: Sets `finalized = true`, burns unallocated balance, emits events. Pure storage writes.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Single-execution guarantee from `gameOverFinalJackpotPaid` guard prevents `AlreadyFinalized` revert.

---

### EXT-17: dgnrs.burnAtGameOver()

- **Call site:** GameOverModule line 127
- **Target:** StakedDegenerusStonk.sol:455-464 (`burnAtGameOver`)
- **Access control:** `onlyGame` modifier. **PASSES.**
- **Can revert:** NO.
  - Line 456: `if (bal == 0) return;` -- early return if nothing to burn.
  - Lines 458-463: Zero out balance, reduce total supply, delete pool balances, emit Transfer. Pure storage writes. No revert paths.
  - Notably: **no finalization guard** unlike GNRUS. But it's idempotent -- if called twice, `bal == 0` on the second call triggers early return.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Idempotent, pure storage writes, no revert paths.

---

### EXT-18: admin.shutdownVrf()

- **Call site:** GameOverModule line 194 (`handleFinalSweep`)
- **Target:** DegenerusAdmin.sol:958-973 (`shutdownVrf`)
- **Access control:** `if (msg.sender != ContractAddresses.GAME) revert NotAuthorized()` (line 959). Caller is GAME. **PASSES.**
- **Can revert:** YES (access control passes, but internal calls could fail)
  - Line 961: `if (subId == 0) return;` -- safe early return.
  - Line 966: `try IVRFCoordinatorV2_5Owner(coordinator).cancelSubscription(subId, target)` -- wrapped in try/catch. Cannot propagate.
  - Lines 970-973: `try linkToken.transfer(target, bal)` -- wrapped in try/catch. Cannot propagate.
- **Failure tolerance:** WRAPPED -- `try admin.shutdownVrf() {} catch {}` at GameOverModule line 194. Double-wrapped: even if `shutdownVrf` itself reverted (which it won't due to internal try/catch), the outer catch handles it.
- **Verdict:** SAFE -- Double-wrapped in try/catch (outer at call site, inner at target). Cannot block final sweep.

---

## Additional External Call from rngGate path (coinflip.creditFlip for sDGNRS)

### EXT-19: coinflip.creditFlip(ContractAddresses.SDGNRS, burnieToCredit)

- **Call site:** AdvanceModule rngGate lines 893-896, _gameOverEntropy lines 964-968, 1003-1007
- **Target:** BurnieCoinflip.sol:895-901 (`creditFlip`)
- **Access control:** Same as EXT-01 -- `onlyFlipCreditors`, caller is GAME. **PASSES.**
- **Can revert:** NO.
  - Same analysis as EXT-01. `player = ContractAddresses.SDGNRS` (non-zero address). `amount = burnieToCredit` (could be 0, but `creditFlip` returns early on amount=0). Pure storage writes.
- **Failure tolerance:** HARD (no try/catch)
- **Verdict:** SAFE -- Same safety profile as EXT-01.

---

## Overall Verdict

- **AGSAFE-03: VERIFIED** -- 19 external calls audited

| Category | Count | Calls |
|----------|-------|-------|
| SAFE | 17 | EXT-01 through EXT-11, EXT-13 through EXT-17, EXT-19 |
| INTENTIONAL | 1 | EXT-12 (VRF requestRandomWords -- halts game by design when VRF unavailable) |
| WRAPPED | 2 | EXT-13 (steth.submit), EXT-18 (admin.shutdownVrf) -- also counted as SAFE |
| FINDING | 0 | None |

**Summary:** All 19 external calls from the advanceGame execution path are either provably non-reverting (17 calls) or intentionally reverting by design (1 call -- VRF). No external call can cause an unexpected revert that blocks game progression. The stETH staking and VRF shutdown paths are wrapped in try/catch for failure tolerance. The gameover fallback path uses `_tryRequestRng` (try/catch) instead of `_requestRng` (hard revert) to ensure game-over processing completes even without VRF.

**Key safety mechanisms identified:**
1. `transferFromPool` caps to available balance (prevents underflow reverts)
2. `creditFlip` early-returns on zero amount/player (prevents wasted gas, no revert)
3. `processCoinflipPayouts` callback `payCoinflipBountyDgnrs` has 5 early-return guards before any state mutation
4. GNRUS.pickCharity level invariant maintained by synchronized `currentLevel` increments
5. GameOverModule guards (`gameOverFinalJackpotPaid`) prevent double-entry into burn/distribute paths
6. `_tryRequestRng` provides try/catch VRF fallback for gameover path
7. stETH staking is fully non-blocking via try/catch
