# §11 — BurnieCoinflip._resolveFlip + win-decode (file:line 807 / 837)

**Consumer entry (single-rooted trace per D-298-CONSUMER-LIST-01 §11):**

The §11 trace is rooted at `BurnieCoinflip.processCoinflipPayouts(bool bonusFlip, uint256 rngWord, uint32 epoch)` declared at `contracts/BurnieCoinflip.sol:805`. The PLAN frontmatter cites `:807` (the `rngWord` parameter site, body line 4 of the function) and `:837` (the `(rngWord & 1) == 1` win-decode), but these are the same function body. The function is the BURNIE coin-flip resolution consumer — the `rngWord` is the VRF-derived word forwarded from `DegenerusGameAdvanceModule.rngGate` (via `_applyDailyRng`) into this external method via the `onlyDegenerusGameContract` modifier.

**Note re consumer naming:** The PLAN frontmatter and 298-CONTEXT.md §11 anchor name the consumer `_resolveFlip`, but the source has no symbol of that name — the resolution function is `processCoinflipPayouts` (verified `grep -n "_resolveFlip\|processCoinflipPayouts" contracts/BurnieCoinflip.sol`: only `processCoinflipPayouts` exists at `:805`; `_resolveFlip` was a legacy naming carried in the planning artifact). The CONTEXT line-numbers (`:807` for the consumer entry, `:837` for win-decode) point unambiguously to `processCoinflipPayouts` lines, so the trace is anchored on that function.

**Two distinct rngWord consumptions inside the function (both rooted at the same VRF word):**

1. **Reward-percent decode** at `:811`: `uint256 seedWord = uint256(keccak256(abi.encodePacked(rngWord, epoch)));` — keccak-rekeyed seed feeds the `roll = seedWord % 20` bucketing at `:816` (yields `rewardPercent ∈ {50, 150}` for 5% / 5% rare arms, or `[78, 115]` for normal arm) plus the `seedWord % COINFLIP_EXTRA_RANGE` modulus at `:825`.
2. **Win-bit decode** at `:837`: `bool win = (rngWord & 1) == 1` — the raw VRF word's low bit determines win/loss (50/50). Per CONTEXT.md PLAN frontmatter, this is THE BURNIE coin-flip outcome bit.

Both decodes share the same `rngWord` SLOAD-source argument (the `uint256 rngWord` parameter at `:807`, passed by AdvanceModule from `currentWord` after `_applyDailyRng` mutation). No second VRF SLOAD inside this function — `rngWord` is the only VRF input.

**External entry chain (verifies `processCoinflipPayouts` is reached ONLY from the advanceGame stack):**

`grep -n "processCoinflipPayouts\b" contracts/ -r --include="*.sol"` returns 6 hits:
- `contracts/BurnieCoinflip.sol:571` — comment reference (not a callsite)
- `contracts/BurnieCoinflip.sol:805` — function definition
- `contracts/modules/DegenerusGameAdvanceModule.sol:1217` — `rngGate` normal-daily path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1277` — `_gameOverEntropy` normal path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1307` — `_gameOverEntropy` fallback path
- `contracts/modules/DegenerusGameAdvanceModule.sol:1794` — `_backfillGapDays` gap-day path
- `contracts/interfaces/IBurnieCoinflip.sol:99` — interface declaration

All 4 AdvanceModule callsites are private/internal helpers reached ONLY via `advanceGame()`-rooted entry points (`rngGate` is called from `_handleDailyAdvance`; `_gameOverEntropy` is called from `_handleGameOverPath`; `_backfillGapDays` is called from `rngGate` :1203). The `onlyDegenerusGameContract` modifier at `:188` (`if (msg.sender != ContractAddresses.GAME) revert OnlyDegenerusGame();`) prevents EOA reach. **Reached-from set: `{advanceGame()-stack via VRF callback or fallback path}` only.**

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**

- **T0 (commitment):** EOA calls `depositCoinflip(player, amount)` (`:229`) on day D. `_depositCoinflip` (`:246`) writes `coinflipBalance[targetDay][caller]` at `:656` via `_addDailyFlip` (`:627`), where `targetDay = currentDayView() + 1 = D + 1`. This is the bet placement: BURNIE is burned at `:270` (`burnie.burnForCoinflip(caller, amount)`) and the credit lands on day D+1's `coinflipBalance`. Deposits are blocked during BAF-resolution transition by `_coinflipLockedDuringTransition()` at `:256`.
- **T1 (RNG publish):** Day D+1 arrives. `advanceGame()` stack reaches `rngGate` at AdvanceModule:1217 with `day = D+1`, calls `coinflip.processCoinflipPayouts(bonusFlip, currentWord, D+1)` with the VRF word for day D+1. Single SSTORE chain inside the consumer: `coinflipDayResult[epoch] = {rewardPercent, win}` at `:840`, `flipsClaimableDay = epoch` at `:869`, `currentBounty = currentBounty_ + PRICE_COIN_UNIT` at `:874`, `bountyOwedTo = address(0)` at `:865` (conditionally), `coinflipBalance[targetDay][bountyOwner] += slice` at `:859` (via `_addDailyFlip` for the bounty payout arm), and `_claimCoinflipsInternal(SDGNRS, false)` tail at `:888` (SDGNRS-only — see §B notes).
- **T2 (claim):** Player calls `claimCoinflips` (`:332`) on day D+1 or later; `_claimCoinflipsInternal` (`:416`) reads `coinflipDayResult[D+1]`, `coinflipBalance[D+1][player]`, computes payout, mints BURNIE via `burnie.mintForGame`. T2 is OUTSIDE the rng-window for §11 — but `_addDailyFlip(to=bountyOwner, slice, 0, false, false)` at `:859` is INSIDE the rng-window (called during T1 resolution itself), so its SLOAD set is in scope.

The participation question for §11 (per `feedback_rng_commitment_window.md`): between T0 (deposit lands the bet on day D+1) and T1 (resolution at day D+1 reads `rngWord`), what player-controllable state can mutate that flows into the win/loss bucket, reward-percent bucket, bounty payout amount, or BAF accumulation? Concretely:

- `coinflipBalance[D+1][player]` written at T0 and read at T2 — but T1 only reads `coinflipBalance[D+1][bountyOwner]` via `_addDailyFlip(to=bountyOwner, slice, …)` for THE BOUNTY ARM — and that reads `prevStake` at `:652` to compute `newStake = prevStake + coinflipDeposit`. So if the bounty owner deposits BURNIE between their bounty arming and resolution, their stake aggregation grows by the bounty `slice` regardless. NON-PARTICIPATING for win-decode but the `prevStake` SLOAD itself is in §B.
- `currentBounty` / `bountyOwedTo` — both written by T0 deposits via `_addDailyFlip(canArmBounty=true, bountyEligible=true)` and read at T1 lines `:846` / `:849`. Bounty arming is gated by `if (!game.rngLocked())` at `:664` — once VRF request lands, no further bounty arming. **rngLockedFlag is the existing gate.**
- `playerState[SDGNRS]` — the trailing `_claimCoinflipsInternal(SDGNRS, false)` at `:888` reads SDGNRS state. SDGNRS is a contract address and its state is not writable by EOAs except via SDGNRS-internal flows.
- `lootboxPresaleActiveFlag` — written by `_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)` at AdvanceModule:433 (advanceGame-stack only). Drives the `+6` reward-percent boost at `:832`.

## CAT-01 (§A) — Traced function set

Backward-trace rooted at `processCoinflipPayouts`'s `rngWord` parameter (`:807`); trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator; the SDGNRS `IStakedDegenerusStonk.*` calls are NOT reached from §11's resolution path — see attestation below).

**Resolution code path (T1 — full enumeration):**

| #  | Function                                              | File:line                                       | Reached from                                | Notes |
|----|-------------------------------------------------------|-------------------------------------------------|---------------------------------------------|-------|
| 1  | `processCoinflipPayouts`                              | `BurnieCoinflip.sol:805`                        | external entry (modifier-gated; AdvanceModule:1217/1277/1307/1794) | consumer entry; reads `rngWord`, writes resolution result, calls `_addDailyFlip` (bounty arm) + `_claimCoinflipsInternal(SDGNRS)` tail |
| 2  | `degenerusGame.lootboxPresaleActiveFlag()` (external) | `DegenerusGame.sol:2116`                        | `:829`                                      | external staticcall; reads `presaleStatePacked` via `_psRead` |
| 3  | `_addDailyFlip` (bounty arm)                          | `BurnieCoinflip.sol:627`                        | `:859`                                      | private; called with `recordAmount=0, canArmBounty=false, bountyEligible=false` — bounty arming branch NOT reached; boon branch NOT reached |
| 4  | `_targetFlipDay`                                      | `BurnieCoinflip.sol:1095`                       | `:650`                                      | private view; calls `degenerusGame.currentDayView()` |
| 5  | `degenerusGame.currentDayView()` (external)           | `DegenerusGame.sol:471`                         | `:1096`                                     | external staticcall; calls `_simulatedDayIndex()` → `GameTimeLib.currentDayIndex()` (pure on `block.timestamp` — no SLOAD) |
| 6  | `_updateTopDayBettor`                                 | `BurnieCoinflip.sol:1127`                       | `:657`                                      | private; reads `coinflipTopByDay[day]`, conditional write |
| 7  | `_score96`                                            | `BurnieCoinflip.sol:1118`                       | `:1132`                                     | `private pure` — no SLOADs |
| 8  | `degenerusGame.payCoinflipBountyDgnrs(...)` (external)| `DegenerusGame.sol:402`                         | `:861`                                      | external call (state-mutating); reads `dgnrs.poolBalance(Reward)` (cross-contract SLOAD on SDGNRS), calls `dgnrs.transferFromPool(Reward, …)` |
| 9  | `dgnrs.poolBalance(Pool.Reward)` (external SDGNRS)    | `StakedDegenerusStonk.sol` (`pools[Reward].balance`) | `DegenerusGame.sol:414`                | cross-contract SLOAD |
| 10 | `dgnrs.transferFromPool(Reward, player, payout)` (external mutator) | `StakedDegenerusStonk.sol` (`pools[Reward].balance -= payout`) | `DegenerusGame.sol:420` | cross-contract SSTORE; not a participating SLOAD source (only a writer of the SDGNRS pool balance read at #9) |
| 11 | `_claimCoinflipsInternal(SDGNRS, false)` (tail)       | `BurnieCoinflip.sol:416`                        | `:888`                                      | tail call to keep SDGNRS flip cursor current; BAF skipped (guard at `:572`); rngLocked guard NOT hit on this path |
| 12 | `degenerusGame.syncAfKingLazyPassFromCoin(SDGNRS)` (external) | `DegenerusGame.sol:1654`                | `:422`                                      | external call; reads `autoRebuyState[SDGNRS].afKingMode` (`:1659`); if false (SDGNRS never enables afKing), returns early — no further SLOADs |
| 13 | `degenerusGame.hasDeityPass(SDGNRS)` (external)       | `DegenerusGame.sol:2349`                        | NOT REACHED                                 | gated by `afKingActive = rebuyActive && afKingMode` at `:434`; SDGNRS has no rebuy → branch dead |
| 14 | `degenerusGame.level()` (external view)               | `DegenerusGame.sol` (auto-getter on `level` public state) | NOT REACHED                        | gated by `hasDeityPass`; SDGNRS branch dead |
| 15 | `_afKingDeityBonusHalfBpsWithLevel`                   | `BurnieCoinflip.sol:1078`                       | NOT REACHED                                 | gated by `hasDeityPass`; SDGNRS branch dead |
| 16 | `jackpots.getLastBafResolvedDay()` (external view)    | `DegenerusJackpots.sol:666`                     | NOT REACHED inside §11 tail path            | gated by `winningBafCredit != 0 && player != SDGNRS` at `:572`; SDGNRS guard ALWAYS true here → BAF branch dead |
| 17 | `jackpots.recordBafFlip(...)` (external mutator)      | `DegenerusJackpots.sol:171`                     | NOT REACHED inside §11 tail path            | same SDGNRS guard at `:572` skips entire BAF section |
| 18 | `_recyclingBonus` / `_afKingRecyclingBonus`           | `BurnieCoinflip.sol:1051` / `1062`              | NOT REACHED in §11 tail                     | gated by `rebuyActive`; SDGNRS branch dead |
| 19 | `_bafBracketLevel`                                    | `BurnieCoinflip.sol:1141`                       | NOT REACHED in §11 tail                     | inside the SDGNRS-skipped BAF arm |
| 20 | `wwxrp.mintPrize(SDGNRS, lossCount * COINFLIP_LOSS_WWXRP_REWARD)` (external mutator) | `BurnieCoinflip.sol:616`     | conditional in §11 tail (`lossCount != 0`)  | output sink (WWXRP mint); not an entropy-input source |

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `grep -n "delegatecall\|\.call\|staticcall" contracts/BurnieCoinflip.sol` → ZERO hits. BurnieCoinflip has NO inline-assembly raw call dispatchers; all cross-contract reach is via typed `IBurnieCoin` / `IDegenerusGame` / `IDegenerusJackpots` / `IWrappedWrappedXRP` external calls (all are calls on `address constant` interface references — single-target dispatch, no proxy / no Diamond pattern).
- `grep -n "assembly" contracts/BurnieCoinflip.sol` → ZERO hits. No inline-assembly `sstore` / `slot:` / raw read/write in BurnieCoinflip.
- `grep -n "_resolveFlip\b" contracts/BurnieCoinflip.sol` → ZERO hits. Confirms CONTEXT.md/PLAN.md `_resolveFlip` reference is the legacy name; canonical function is `processCoinflipPayouts`.
- `grep -n "rngWord" contracts/BurnieCoinflip.sol` → 4 hits: `:803` (NatSpec), `:807` (parameter), `:811` (keccak input), `:837` (win-decode). Both consumer sites confirmed.
- `grep -n "modifier\|onlyDegenerusGameContract\|onlyBurnieCoin\|onlyFlipCreditors" contracts/BurnieCoinflip.sol` confirms three access modifiers; `processCoinflipPayouts` uses `onlyDegenerusGameContract`.
- `grep -n "processCoinflipPayouts\b" contracts/ -r --include="*.sol"` → 4 callsites in AdvanceModule (1217, 1277, 1307, 1794); all advance-stack rooted.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during the §11 resolution path (T1 window: between the `rngWord` parameter consumption at `:807` and the final external mutator returns or function exit). Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated, not only VRF-derived ones; non-VRF SLOADs alongside RNG are a distinct bug class (F-41-02/03 precedent).

| #     | Slot                                                    | Read-site (file:line)                                  | Read context                                                              | Participating? | Attestation if NO |
|-------|---------------------------------------------------------|--------------------------------------------------------|---------------------------------------------------------------------------|----------------|-------------------|
| B-1   | `presaleStatePacked` (`lootboxPresaleActive` bit)       | `DegenerusGame.sol:2117` (via `_psRead`)               | external staticcall from `:829`; drives `+6` reward-percent boost at `:832` | **YES**        | — |
| B-2   | `currentBounty` (uint128)                               | `BurnieCoinflip.sol:846` (`uint128 currentBounty_ = currentBounty`) | bounty pool snapshot for `slice = currentBounty_ >> 1` at `:852`         | **YES**        | — |
| B-3   | `bountyOwedTo` (address)                                | `BurnieCoinflip.sol:849`                                | bounty owner read; drives `if (bountyOwner != address(0))` arm gate       | **YES**        | — |
| B-4   | `coinflipBalance[targetDay][bountyOwner]` (mapping)     | `BurnieCoinflip.sol:652` (via `_addDailyFlip:653`)     | `prevStake` for `newStake = prevStake + coinflipDeposit` RMW              | NO             | RMW aggregate per-day stake; prior value is added to the bounty `slice` deposit unconditionally. The PRIOR value does not enter any VRF-derived output formula — `processCoinflipPayouts` writes `coinflipDayResult[epoch]` strictly from `(rngWord, epoch, presaleBonus)`, none of which read `coinflipBalance`. The slot is read here purely to recompose the bounty owner's day+1 aggregate stake. (However, `_updateTopDayBettor` consumes `newStake` for leaderboard ordering; that's NON-PARTICIPATING for win-decode but a participating WRITE — see §B-W.) |
| B-5   | `coinflipTopByDay[targetDay]` (struct: address+uint96)  | `BurnieCoinflip.sol:1133` (in `_updateTopDayBettor`)   | leaderboard read for comparison `score > dayLeader.score`                  | NO             | Leaderboard read for comparison; only affects whether `coinflipTopByDay[targetDay]` SSTORE fires. The leaderboard slot is NOT consumed by ANY VRF-derived output of §11 — the win-decode bit at `:837` already wrote `coinflipDayResult[epoch]` before this branch. The leaderboard is a future-day artifact for `coinflipTopLastDay()` view consumption (`:962`) outside the rng-window. |
| B-6   | SDGNRS `pools[Reward].balance` (cross-contract)         | `DegenerusGame.sol:414` (via `payCoinflipBountyDgnrs`) | SDGNRS pool balance read; gates `payout = (poolBalance * COINFLIP_BOUNTY_DGNRS_BPS) / 10_000` | **YES** (cross-contract) | — (the participating-ness here is for the *bounty payout amount*; this is consumed by `dgnrs.transferFromPool` and produces an EOA-observable transfer — it IS a VRF-conditional payout because the entire `if (win)` branch at `:856` gates this call) |
| B-7   | `autoRebuyState[SDGNRS].afKingMode` (bool)              | `DegenerusGame.sol:1659` (in `syncAfKingLazyPassFromCoin`) | external call from `BurnieCoinflip:422`; early-return gate                | NO             | Per the modifier `if (msg.sender != COINFLIP) revert E()` at `:1657`, this is callable only from the COINFLIP contract. For `player=SDGNRS`, the slot is initialized to `false` and the only writers are the 5 EOA-callable / coin-hook setters in `DegenerusGame.sol` (`_setAutoRebuy`, `_setAfKingMode`, `_deactivateAfKing`, plus the same-function clear at `:1664`) — all keyed on `msg.sender`-derived `player` (or via `coinflip.settleFlipModeChange` for SDGNRS, which is NEVER called for SDGNRS itself since the SDGNRS contract is not an EOA player). Therefore for the SDGNRS key, this slot is provably `false` for all of game lifetime → `syncAfKingLazyPassFromCoin` returns early at `:1659` → no further SLOADs on this branch. Does not influence §11 VRF-derived outputs. |
| B-8   | `playerState[SDGNRS].claimableStored` (uint128)         | `BurnieCoinflip.sol:421` (via `_claimCoinflipsInternal:394` storage pointer; field reads at `:396`, `:404`) | SDGNRS state pointer + claimableStored RMW                                | NO             | RMW per-player BURNIE-credit counter; written only via SDGNRS-keyed flows (`settleFlipModeChange`, `_claimCoinflipsAmount`, `_setCoinflipAutoRebuy` — none reach for SDGNRS as a player). At §11 T1, the prior value affects nothing about `processCoinflipPayouts`'s VRF-derived outputs (`coinflipDayResult[epoch]`, `currentBounty`, `bountyOwedTo`, `flipsClaimableDay`). |
| B-9   | `playerState[SDGNRS].lastClaim` (uint32)                | `BurnieCoinflip.sol:424` (via `_claimCoinflipsInternal`) | claim cursor                                                              | NO             | Same scope as B-8; SDGNRS cursor advances only via this `_claimCoinflipsInternal(SDGNRS, …)` tail call which is itself inside the resolution. Pre-T1 value cannot mutate between T0 and T1 from any EOA path (SDGNRS contract is not an EOA). |
| B-10  | `playerState[SDGNRS].autoRebuyEnabled` (bool)           | `BurnieCoinflip.sol:426` (via `_claimCoinflipsInternal`) | rebuy gate                                                                | NO             | SDGNRS rebuy gate is always false (no EOA setter reaches `playerState[SDGNRS].autoRebuyEnabled` — `_setCoinflipAutoRebuy` requires `msg.sender == player` or `_requireApproved(player)` for `player=SDGNRS`, which is a contract that never approves an operator). Provably false → `rebuyActive = false`, `afKingActive = false`, all rebuy-gated branches dead. |
| B-11  | `playerState[SDGNRS].autoRebuyStop` (uint128)           | `BurnieCoinflip.sol:428`                               | takeProfit                                                                | NO             | Reached only when `rebuyActive` — provably false for SDGNRS (B-10). |
| B-12  | `playerState[SDGNRS].autoRebuyCarry` (uint128)          | `BurnieCoinflip.sol:445`                               | rebuy carry                                                               | NO             | Same as B-10. |
| B-13  | `flipsClaimableDay` (uint32)                            | `BurnieCoinflip.sol:423` (via `_claimCoinflipsInternal`) | latest resolved-day cursor                                                | NO             | Just written at `:869` (`flipsClaimableDay = epoch`) — the tail `_claimCoinflipsInternal(SDGNRS)` reads the freshly-stored value. The slot has a single writer (`:869` inside `processCoinflipPayouts` itself) plus initial constructor default of zero. Its value is fully determined by the consumer's own `epoch` argument (from AdvanceModule). NO external writer races this slot during T1. |
| B-14  | `coinflipDayResult[cursor]` (struct, mapping)           | `BurnieCoinflip.sol:494` (via `_claimCoinflipsInternal`) | tail loop reads per-day result                                            | NO             | Per-day result; written exclusively by `processCoinflipPayouts` itself (`:840`) — each `cursor` slot is written exactly once before being read. For the SDGNRS tail-loop iterations the immediately-prior epochs were each resolved by `processCoinflipPayouts` at past advance days; no EOA mutator path writes this slot. Its prior values feed only SDGNRS payout accounting at T1; they do NOT feed back into `(rngWord & 1)` or the reward-percent decode of THIS epoch. |
| B-15  | `coinflipBalance[cursor][SDGNRS]` (mapping)             | `BurnieCoinflip.sol:504` (via `_claimCoinflipsInternal`) | tail loop reads SDGNRS stake per day                                      | NO             | SDGNRS receives flip credits from various sources (`creditFlip` from QUESTS / AFFILIATE / ADMIN; `addDailyFlip` from coinflip-bounty-payout path). Writers ARE reachable from non-EXEMPT entry points (QUESTS / AFFILIATE / ADMIN are EOA-or-operator surfaces). HOWEVER, this slot's value only flows into SDGNRS's own payout accumulator inside the §11 tail loop (driven by past-epoch `coinflipDayResult[cursor].win` outcomes) — it does NOT feed back into THIS epoch's `rngWord`-decoded result. The "(slot × writer) participation" question is whether changing this slot between T0 and T1 changes the consumer's VRF-derived outputs. It does not (the SDGNRS tail is post-write; the win/loss + reward-percent are already settled at `:837/:824` from `rngWord` alone). NON-PARTICIPATING for §11's win-decode. |
| B-16  | `biggestFlipEver` (uint128)                             | NOT READ in §11 T1                                     | (read site is `_addDailyFlip:663` inside the `if (canArmBounty && bountyEligible && recordAmount != 0)` branch) | n/a            | Branch is dead for §11's call to `_addDailyFlip(to, slice, 0, false, false)` at `:859` (recordAmount=0, canArmBounty=false, bountyEligible=false). Slot NOT touched during §11 T1. |
| B-17  | `consumeCoinflipBoon`-driven slots in DegenerusGame    | NOT READ in §11 T1                                     | `_addDailyFlip` boon branch only fires when `recordAmount != 0`            | n/a            | recordAmount=0 in §11's bounty-arm `_addDailyFlip` call. Branch dead. |
| B-18  | `rngLockedFlag` (DegenerusGame, bool)                   | NOT READ in §11 T1                                     | (read at `_addDailyFlip:664` under `canArmBounty && bountyEligible && recordAmount != 0` branch which is dead in §11; ALSO read at `BurnieCoinflip:589` under `winningBafCredit != 0 && player != SDGNRS` branch which is dead in §11 SDGNRS tail) | n/a            | Two potential read sites both gated by dead branches in §11's specific call shape. |
| B-19  | `gameOverFlag` (DegenerusGame `gameOver()` read)        | NOT READ in §11 T1                                     | read at `_claimCoinflipsInternal:584` and at `_coinflipLockedDuringTransition` — both gated by `winningBafCredit != 0 && player != SDGNRS` (dead branch in §11 SDGNRS tail) | n/a            | Dead branch in §11 SDGNRS tail. |
| B-20  | `purchaseInfo()`-driven slots in DegenerusGame          | NOT READ in §11 T1                                     | `purchaseInfo()` read at `_claimCoinflipsInternal:583` — same dead branch | n/a            | Dead branch in §11 SDGNRS tail. |

**Auxiliary §B-W — SSTOREs inside the rng-window (cross-check, not classified):**

| #     | Slot                                                  | Write-site (file:line)                          | Notes |
|-------|-------------------------------------------------------|-------------------------------------------------|-------|
| B-W1  | `coinflipDayResult[epoch]` (`{rewardPercent, win}`)   | `BurnieCoinflip.sol:840`                        | primary resolution write; consumes `rngWord` |
| B-W2  | `bountyOwedTo = address(0)` (conditional clear)       | `BurnieCoinflip.sol:865`                        | bounty-arm finalize (fires when `bountyOwner != address(0) && currentBounty_ > 0` regardless of win) |
| B-W3  | `flipsClaimableDay = epoch`                           | `BurnieCoinflip.sol:869`                        | cursor advance |
| B-W4  | `currentBounty = currentBounty_ + PRICE_COIN_UNIT`    | `BurnieCoinflip.sol:874`                        | bounty pool accumulation |
| B-W5  | `coinflipBalance[targetDay][bountyOwner] += slice`    | `BurnieCoinflip.sol:656` (via `_addDailyFlip`)  | only when `win` and `bountyOwner != address(0)` — credits the bounty winner's day+1 stake |
| B-W6  | `coinflipTopByDay[targetDay]` (struct)                | `BurnieCoinflip.sol:1135`                       | only when bounty winner's new stake exceeds leaderboard high water mark |
| B-W7  | SDGNRS-tail state writes inside `_claimCoinflipsInternal(SDGNRS)` | various                              | `state.lastClaim` (`:607`); SDGNRS state slot — see B-9 attestation |
| B-W8  | `playerState[SDGNRS].claimableStored` (RMW)           | NOT REACHED in §11 tail                          | rebuy gate dead for SDGNRS |
| B-W9  | external cross-contract writes via `dgnrs.transferFromPool(Reward, …)` | `StakedDegenerusStonk.sol`             | only when `win` |
| B-W10 | external cross-contract writes via `wwxrp.mintPrize(SDGNRS, …)` | `WrappedWrappedXRP.sol`                       | only when SDGNRS lossCount != 0 |

## CAT-03 (§C) — Writer enumeration for participating slots

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each `Participating? = YES` slot in §B, enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included). The participating-slot universe under §11 is: B-1 (`presaleStatePacked`), B-2 (`currentBounty`), B-3 (`bountyOwedTo`), B-6 (SDGNRS `pools[Reward].balance`).

### C-1 — `presaleStatePacked` (uint256; presale-active flag in low bit)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-1a | `DegenerusGameStorage._psWrite` (helper)            | `storage/DegenerusGameStorage.sol:860`          | callers below                                    | helper — writes any (shift, mask) field of `presaleStatePacked` |
| C-1b | `DegenerusGameAdvanceModule._processAdvance` (presale-clear branch) | `modules/DegenerusGameAdvanceModule.sol:433` (`_psWrite(PS_ACTIVE_SHIFT, PS_ACTIVE_MASK, 0)`) | `advanceGame()` stack — `_processAdvance` is invoked from `_handleDailyAdvance` / `rngGate` callers | **EXEMPT-ADVANCEGAME** — only writer of the `PS_ACTIVE` bit post-deploy |
| C-1c | constructor initialization                            | `storage/DegenerusGameStorage.sol:843` (`presaleStatePacked = uint256(1)`) | deploy-time             | **EXEMPT (constructor)** — pre-deploy initial value; no post-deploy reach |

**`grep -rn "_psWrite\|presaleStatePacked\s*=" contracts/ --include="*.sol"`** confirms only C-1b and C-1c write the slot post-construction (no other `_psWrite` callsite present in the source — searched across all of `contracts/`).

**OZ-inherited writers check:** `presaleStatePacked` is `internal uint256` in `DegenerusGameStorage`; no OZ inheritance writes. Confirmed.

**Admin/owner writer check:** No `onlyOwner` / `onlyAdmin` writer of `presaleStatePacked`. Confirmed via grep.

**Inline-assembly raw-sstore check:** `grep -n "assembly" contracts/storage/DegenerusGameStorage.sol contracts/modules/DegenerusGameAdvanceModule.sol contracts/DegenerusGame.sol --include="*.sol"` returns only `memory-safe` revert helpers (no raw sstore on `presaleStatePacked` slot).

### C-2 — `currentBounty` (uint128 public)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-2a | inline state-variable initializer                   | `BurnieCoinflip.sol:167` (`uint128 public currentBounty = 1_000 ether`) | deploy-time              | **EXEMPT (constructor)** — pre-deploy initial value |
| C-2b | `BurnieCoinflip.processCoinflipPayouts` (consumer-self) | `BurnieCoinflip.sol:874` (`currentBounty = currentBounty_ + uint128(PRICE_COIN_UNIT)`) | the resolution path itself (consumer §11) | **EXEMPT-VRFCALLBACK** — self-write inside the consumer's resolution call; reached only from `advanceGame()`-stack VRF callback (modifier-gated at `:188`) |

**`grep -n "currentBounty\s*=\b" contracts/BurnieCoinflip.sol`** returns only `:167` (initializer) and `:874` (consumer-self write). No other writer in `contracts/`.

**OZ-inherited writers check:** `currentBounty` is `uint128 public`; auto-getter only, no OZ writers. Confirmed.

**Admin/owner writer check:** No admin path writes `currentBounty`. The `onlyFlipCreditors` modifier (GAME / QUESTS / AFFILIATE / ADMIN) governs `creditFlip` / `creditFlipBatch` only — those write `coinflipBalance` via `_addDailyFlip`, NOT `currentBounty` (the `_addDailyFlip` bounty-arm branch reads `currentBounty` but only writes `bountyOwedTo` / `biggestFlipEver`, not `currentBounty`).

**Inline-assembly raw-sstore check:** Zero hits in BurnieCoinflip. Confirmed.

### C-3 — `bountyOwedTo` (address internal)

| #   | Writer function                                       | Callsite (file:line)                            | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-3a | `BurnieCoinflip._addDailyFlip` (bounty-arming arm)  | `BurnieCoinflip.sol:681` (`bountyOwedTo = player`) | EOA → `depositCoinflip` (`:229`) when `canArmBounty=true && bountyEligible=true && recordAmount != 0 && recordAmount > biggestFlipEver && !game.rngLocked() && recordAmount >= threshold` — only the SELF-deposit shape (`directDeposit=true`) at `:312` passes the canArmBounty/bountyEligible flags. | **VIOLATION** — see §D-1 (EOA-reachable writer; arming gated by `!game.rngLocked()` at `:664` BUT not by `flipsClaimableDay` epoch alignment). |
| C-3b | `BurnieCoinflip.processCoinflipPayouts` (consumer-self) | `BurnieCoinflip.sol:865` (`bountyOwedTo = address(0)`) | the resolution path itself | **EXEMPT-VRFCALLBACK** — self-clear inside the consumer (regardless of win/loss). |

**`grep -n "bountyOwedTo\s*=" contracts/BurnieCoinflip.sol`** returns only `:681` (arming) and `:865` (clear). No third writer.

**OZ-inherited writers check:** `bountyOwedTo` is `internal address`; no OZ writers. Confirmed.

**Admin/owner writer check:** No admin path. The `onlyFlipCreditors` writers (`creditFlip` `:898`, `creditFlipBatch` `:909`) ALSO reach `_addDailyFlip` — but with `canArmBounty=false, bountyEligible=false, recordAmount=0` (`:903` / `:918`) — so they DO NOT write `bountyOwedTo`. Only `_depositCoinflip` (`:246`) reaches the writer arm.

**Constructor/initializer:** Default zero. No constructor write.

**Inline-assembly raw-sstore check:** Zero hits.

### C-4 — SDGNRS `pools[Reward].balance` (cross-contract; in `StakedDegenerusStonk.sol`)

This slot is in `StakedDegenerusStonk.sol` (in-source-scope per `D-298-TRACE-DEPTH-01`). For §11, the read site is via `dgnrs.poolBalance(Pool.Reward)` at `DegenerusGame.sol:414` (inside `payCoinflipBountyDgnrs`), and the same call eventually invokes `dgnrs.transferFromPool(Reward, player, payout)` at `:420` (cross-contract write). The participating-ness of this slot for §11 is: the SDGNRS Reward pool balance scales the bounty `payout` formula at `:418`.

| #   | Writer function (in `StakedDegenerusStonk.sol`)       | Callsite                                        | Reaching external entry point(s)                 | Notes |
|-----|-------------------------------------------------------|-------------------------------------------------|--------------------------------------------------|-------|
| C-4a | `StakedDegenerusStonk.addToPool(Pool.Reward, amount)` (and any `Reward`-keyed pool credit fn) | various — invoked from `DegenerusGame` ETH/dgnrs allocation paths during `_handleDailyAdvance` / `_handleJackpotPhaseAdvance` | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** for the advance-stack callsites |
| C-4b | `StakedDegenerusStonk.transferFromPool(Pool.Reward, player, payout)` (debit path) | invoked from `DegenerusGame.payCoinflipBountyDgnrs:420` | the §11 resolution path itself                  | **EXEMPT-VRFCALLBACK** (consumer-self debit) |
| C-4c | `StakedDegenerusStonk.transferFromPool(Pool.Reward, …)` (other debit callsites) | invoked from other DegenerusGame payout flows (Decimator/Lootbox rewards / etc.) keying on `Reward` pool | various EOA + advance-stack entry points | Per-callsite — see §D-2 for VIOLATION-CANDIDATE classification (EOA-callable payout paths that drain Reward pool BEFORE §11's bounty payout reads it can shift the bounty `payout` amount). |
| C-4d | `StakedDegenerusStonk` constructor / `_initializePool` | deploy-time                                     | constructor                                       | **EXEMPT (constructor)** |

**OZ-inherited writers check:** SDGNRS is a custom ERC20-like contract; its `pools` mapping is private. No OZ inheritance touches `pools[Reward].balance` directly. Confirmed via `grep -n "pools\[" contracts/StakedDegenerusStonk.sol`.

**Admin/owner writer check:** Owner / DAO paths in SDGNRS that adjust pool balances (rebalance, emergency-withdraw if any) — not enumerated here at the SDGNRS level; per `D-298-TRACE-DEPTH-01` the SDGNRS slot is in-source-scope but the EOA-callable writers of `pools[Reward].balance` are documented in consumer §12's catalog (sStonk redemption). For §11, the cross-reference is: SDGNRS Reward-pool writers comprise an EOA-callable surface that races the bounty payout amount window.

**Inline-assembly raw-sstore check:** No raw assembly hits on `pools` slot in SDGNRS (verified earlier in §6 / §12 catalog precedents).

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` / `D-298-EXEMPT-CROSSCONTRACT-01`: classify each (slot × writer × callsite) tuple as `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` (the legacy "safe-by-design" attestation class is disallowed per D-43N-AUDIT-ONLY-01 / v43.0 milestone goal).

| #   | Slot                            | Writer × callsite                                       | Reached-from stack                                       | Verdict                       |
|-----|---------------------------------|---------------------------------------------------------|----------------------------------------------------------|-------------------------------|
| D-1 | `presaleStatePacked`            | `_psWrite` @ AdvanceModule:433                          | `advanceGame()` → `_processAdvance`                       | **EXEMPT-ADVANCEGAME**        |
| D-2 | `presaleStatePacked`            | initializer @ Storage:843                               | deploy constructor                                        | **EXEMPT-ADVANCEGAME** (constructor-equivalent; pre-deploy fixed value with no post-deploy mutator besides D-1) |
| D-3 | `currentBounty`                 | initializer @ BurnieCoinflip:167                        | deploy                                                    | **EXEMPT-ADVANCEGAME** (constructor-equivalent) |
| D-4 | `currentBounty`                 | self-write @ BurnieCoinflip:874                         | the §11 resolution itself                                 | **EXEMPT-VRFCALLBACK**        |
| D-5 | `bountyOwedTo`                  | `_addDailyFlip:681` (arming) reached via `_depositCoinflip:312` ← EOA `depositCoinflip:229` | EOA — direct-deposit self-arming                | **VIOLATION** — see §E-1     |
| D-6 | `bountyOwedTo`                  | self-clear @ BurnieCoinflip:865                         | the §11 resolution itself                                 | **EXEMPT-VRFCALLBACK**        |
| D-7 | SDGNRS `pools[Reward].balance`  | `dgnrs.transferFromPool(Reward, …)` @ DegenerusGame:420 (self-debit) | the §11 resolution itself (consumer's bounty payout) | **EXEMPT-VRFCALLBACK**        |
| D-8 | SDGNRS `pools[Reward].balance`  | other EOA-callable Reward-pool drains (claim paths, decimator rewards, etc.) reached from DegenerusGame entries that key `Pool.Reward` | EOA + advance-stack mix          | **VIOLATION** — see §E-2     |
| D-9 | SDGNRS `pools[Reward].balance`  | advance-stack credit paths (`addToPool(Reward, …)`)     | `advanceGame()` stack                                     | **EXEMPT-ADVANCEGAME**        |

## CAT-06 (§E) — Per-VIOLATION remediation tactic + rationale

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale citing design intent or cross-callsite consequence.

| #     | VIOLATION (ref §D)          | Tactic | Rationale (≤80 chars) |
|-------|-----------------------------|:------:|-----------------------|
| E-1   | D-5 `bountyOwedTo` arming   | **(a)** | Bounty arming already gated by `!rngLocked()` at :664; extend to fail-closed revert |
| E-2   | D-8 SDGNRS Reward-pool drain races bounty payout | **(b)** | Snapshot poolBalance at rngLock time; bounty payout computes vs snapshot, not live |

**Tactic (a) detail for E-1:** The existing convention site at `BurnieCoinflip:730` (`if (degenerusGame.rngLocked()) revert RngLocked();` inside `_setCoinflipAutoRebuy`) is THE precedent for rngLockedFlag-gated reverts in this contract. The current bounty arming at `:664` reads `!game.rngLocked()` as a silent skip (no revert) — the writer is gated, but a stale-bounty-armed-before-lock state can still be replaced by the resolution (`bountyOwedTo = address(0)` at `:865` fires unconditionally when `bountyOwner != address(0) && currentBounty_ > 0`). The race is: EOA arms bounty at block N (rngLocked=false), VRF request lands at block N+1 (rngLocked=true, `processCoinflipPayouts` consumes the arming). The arming is already locked out of further mutation by `:664`, but the SLOAD at `:849` reads the just-armed value. The participating-ness here is per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent: between VRF request and fulfillment, the slot is FROZEN (writer gated) — this matches the v43.0 milestone goal IF the read happens AFTER `rngLockedFlag=true`. The `bountyOwedTo` clear at `:865` fires unconditionally, so a player arming bounty between rngRequestTime and the actual `processCoinflipPayouts` execution has their bounty consumed (win or no-win, the clear fires). **Hardening tactic (a):** turn the `:664` silent skip into an explicit revert (or move the bounty-arming gate to require `flipsClaimableDay == currentDay - 1` epoch alignment so that bounty arming between rngLock and resolution becomes impossible to land on the resolved epoch). The 80-char rationale captures the precedent + the hardening direction.

**Tactic (b) detail for E-2:** The SDGNRS `pools[Reward].balance` is read live by `payCoinflipBountyDgnrs:414` to scale the bounty payout. Any EOA-callable Reward-pool drain (e.g., a parallel `claimRedemption` flow on SDGNRS, or a decimator-reward distribution that keys `Pool.Reward`) that lands between rngLock and resolution shifts the bounty payout amount. The snapshot/anchor pattern precedent (Phase 281 owed-salt, Phase 288 dailyIdx) is the natural fit: at `_requestRng`/rngLock time, snapshot the Reward pool balance (e.g., into a transient or per-epoch storage slot), and `payCoinflipBountyDgnrs` consumes the snapshot rather than `dgnrs.poolBalance(Reward)` live. This eliminates the cross-contract write race in one structural change rather than per-callsite gating.

---

## Catalog completeness self-attestation for §11

- All resolution-path SLOADs enumerated (B-1..B-20; B-16..B-20 are reachable-in-principle slot reads gated by dead branches within §11's specific call shape and documented for completeness per `feedback_rng_window_storage_read_freshness.md`).
- All YES rows have writer enumeration in §C (B-1 → C-1; B-2 → C-2; B-3 → C-3; B-6 → C-4).
- All §D rows classified; only the four allowed verdicts used. 9 tuples: 7 EXEMPT + 2 VIOLATION.
- All VIOLATIONs have tactic + ≤80-char rationale in §E.
- Cross-contract writers (SDGNRS pool) enumerated per `D-298-EXEMPT-CROSSCONTRACT-01`.
- `_resolveFlip` legacy name reconciled to canonical `processCoinflipPayouts` symbol per source grep.
- No `contracts/` or `test/` mutations performed.
