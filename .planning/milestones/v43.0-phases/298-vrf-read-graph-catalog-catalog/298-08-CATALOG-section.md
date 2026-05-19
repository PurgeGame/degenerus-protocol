# §8 — DegeneretteModule._resolveLootboxDirect + inline consumer (file:line 797 / 594)

**Consumer entries (two-rooted trace per D-298-CONSUMER-LIST-01 §8):**

1. **Inline degenerette consumer** — `contracts/modules/DegenerusGameDegeneretteModule.sol:594`
   - `_resolveFullTicketBet` reads `uint256 rngWord = lootboxRngWordByIndex[index];` at line 594; the resolution loop then derives spin-result tickets via `keccak256(rngWord, index, ...)` (lines 615/619) and feeds the lootbox-converted ETH remainder into `_resolveLootboxDirect` at line 786.
2. **Direct-lootbox auto-resolve consumer** — `contracts/modules/DegenerusGameDegeneretteModule.sol:797`
   - `_resolveLootboxDirect` is a private helper that delegatecalls `IDegenerusGameLootboxModule.resolveLootboxDirect.selector` (selector at LootboxModule.sol:671). The delegatecall target re-derives entropy locally as `seed = keccak256(rngWord, player, day, amount)` (LootboxModule.sol:676) and walks the full `_resolveLootboxCommon` → `_accumulateLootboxRolls` → `_resolveLootboxRoll` chain.

**Both consumer entries share the SAME `rngWord` source slot:** `lootboxRngWordByIndex[index]` (read once at :594; threaded into `_resolveLootboxDirect` via the `rngWord` parameter at :675, then passed into the LootboxModule entry as `rngWord` and re-keccaked into a per-resolution seed). Single VRF-derived entropy thread through the whole resolution. Each spin-level lootbox conversion also re-keys via `keccak(rngWord, index, spinIdx, 'L')` at :668 for non-zero spinIdx, but the underlying `rngWord` is the same SLOAD.

**External entry chain:**
- EOA → `DegenerusGame.resolveDegeneretteBets(player, betIds)` at `DegenerusGame.sol:743` → delegatecall `DegenerusGameDegeneretteModule.resolveBets` (Degenerette:389) → `_resolveBet` (:570) → `_resolveFullTicketBet` (:578) → consumer site §1 at :594; loop body invokes `_distributePayout` (:722) → conditional `_resolveLootboxDirect` (:797) for the `lootboxShare > 0` arm. Both consumer entries live inside the same outer external entry point (`resolveDegeneretteBets`); EOA chooses `betIds` at resolution time.
- `placeDegeneretteBet` external entry (`DegenerusGame.sol:714` → Degenerette:367) is the COMMITMENT-side entry: it captures `index = _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)` at :450 and requires `lootboxRngWordByIndex[index] == 0` at :452 (commitment must happen BEFORE VRF lands on this index). Bet `packed` is stored at :479; this `packed` is the per-bet entropy-input that resolution later reads at :571.

**Commitment-window discipline (per `feedback_rng_commitment_window.md`):**
- T0 (commitment): EOA calls `placeDegeneretteBet`; bet writes `degeneretteBets[player][nonce] = packed` (Degenerette:479). `packed` captures `index`, `customTicket`, `ticketCount`, `currency`, `amountPerTicket`, `activityScore` (snapshot of `_playerActivityScore` at placement), `heroQuadrant`. The `index` here is THE CURRENT lootbox RNG index for which `rngWord` is not yet published.
- T1 (RNG publish): `_finalizeLootboxRng(uint256 rngWord)` at `AdvanceModule.sol:1256` writes `lootboxRngWordByIndex[index] = rngWord` (VRF-callback stack only; auxiliary tail-fill writers at :1761 / :1818 are EXEMPT-VRFCALLBACK / EXEMPT-ADVANCEGAME). Single EXEMPT SSTORE site for the entropy source.
- T2 (resolution): EOA calls `resolveDegeneretteBets`. Resolution reads `degeneretteBets[player][betId]` (input from T0), `lootboxRngWordByIndex[index]` (entropy from T1), executes the spin loop + lootbox conversion, then `delete degeneretteBets[player][betId]` (:597) closes the bet.

The risk class to enumerate (per F-41-02/03 precedent in `feedback_rng_window_storage_read_freshness.md`): any SLOAD reached between T1 and T2 that the EOA can mutate post-T1 — those flow into `payout` derivation alongside the immutable `rngWord` and break the "every VRF input frozen at commitment" invariant.

## CAT-01 (§A) — Traced function set

Backward-trace rooted at both consumer entries; trace walks transitively into every reachable function under `contracts/` per `D-298-TRACE-DEPTH-01`. Stops only at external interfaces with no source available (Chainlink VRF coordinator + wwxrp/coin/dgnrs/coinflip/sdgnrs externals — interface methods enumerated with their callsites; internal SLOADs of those externals are out of this audit's source scope, but the storage-ref SLOAD that obtains the contract address is itself a compile-time constant `internal constant` (no SLOAD)).

**Resolution code path (T2 — full enumeration):**

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 1  | `resolveBets`                         | `DegeneretteModule.sol:389`                        | external entry (`DegenerusGame:743`)  | for-loop dispatcher; calls `_resolvePlayer` + `_resolveBet` per betId |
| 2  | `_resolvePlayer`                      | `DegeneretteModule.sol:141`                        | :390                                  | `private view`; reads `operatorApprovals[player][msg.sender]` (NON-PARTICIPATING access check) |
| 3  | `_requireApproved`                    | `DegeneretteModule.sol:131`                        | :146                                  | `private view`; same access read |
| 4  | `_resolveBet`                         | `DegeneretteModule.sol:570`                        | :393                                  | reads `degeneretteBets[player][betId]` (:571) → dispatches `_resolveFullTicketBet` |
| 5  | `_resolveFullTicketBet`               | `DegeneretteModule.sol:578`                        | :574                                  | **consumer §B (inline)** at :594; loop runs `_countMatches`, `_fullTicketPayout`, `_distributePayout`, `_awardDegeneretteDgnrs` |
| 6  | `_countMatches`                       | `DegeneretteModule.sol:873`                        | :635                                  | `private pure` — no SLOADs |
| 7  | `_fullTicketPayout`                   | `DegeneretteModule.sol:949`                        | :638                                  | `private pure` — no SLOADs |
| 8  | `_countGoldQuadrants`                 | `DegeneretteModule.sol:860`                        | :959                                  | `private pure` — no SLOADs |
| 9  | `_getBasePayoutBps`                   | `DegeneretteModule.sol:1045`                       | :960                                  | `private pure` — no SLOADs (constant-table lookup) |
| 10 | `_wwxrpBonusBucket`                   | `DegeneretteModule.sol:907`                        | :964                                  | `private pure` — no SLOADs |
| 11 | `_wwxrpFactor`                        | `DegeneretteModule.sol:921`                        | :973                                  | `private pure` — no SLOADs (constant-table lookup) |
| 12 | `_applyHeroMultiplier`                | `DegeneretteModule.sol:1011`                       | :989                                  | `private pure` — no SLOADs (constant-table lookup) |
| 13 | `_roiBpsFromScore`                    | `DegeneretteModule.sol:1071`                       | :599                                  | `private pure` — no SLOADs (input from packed bet's `activityScore`) |
| 14 | `_wwxrpHighValueRoi`                  | `DegeneretteModule.sol:1108`                       | :602                                  | `private pure` — no SLOADs |
| 15 | `_distributePayout`                   | `DegeneretteModule.sol:722`                        | :675                                  | reads `prizePoolFrozen`, pool slots, writes claimable + pools, calls `_resolveLootboxDirect` on lootbox arm |
| 16 | `_getPendingPools`                    | `Storage.sol:702`                                  | :755                                  | reads `prizePoolPendingPacked` |
| 17 | `_setPendingPools`                    | `Storage.sol:698`                                  | :764                                  | writes `prizePoolPendingPacked` |
| 18 | `_getFuturePrizePool`                 | `Storage.sol:797`                                  | :770                                  | reads `prizePoolsPacked` (high 128 bits) |
| 19 | `_getPrizePools`                      | `Storage.sol:688`                                  | :798                                  | reads `prizePoolsPacked` |
| 20 | `_setFuturePrizePool`                 | `Storage.sol:803`                                  | :780                                  | writes `prizePoolsPacked` (high 128 bits) |
| 21 | `_setPrizePools`                      | `Storage.sol:684`                                  | :805                                  | writes `prizePoolsPacked` |
| 22 | `_addClaimableEth`                    | `DegeneretteModule.sol:1129`                       | :765, :781                            | writes `claimablePool`, calls `_creditClaimable` |
| 23 | `_creditClaimable`                    | `PayoutUtils.sol:32`                               | :1132                                 | writes `claimableWinnings[player]` |
| 24 | `_revertDelegate`                     | `DegeneretteModule.sol:122`                        | :812                                  | `private pure` — error path only |
| 25 | `_resolveLootboxDirect`               | `DegeneretteModule.sol:797`                        | :786                                  | **consumer §B (direct)**: delegatecalls LootboxModule.resolveLootboxDirect (selector at :806) |
| 26 | `_awardDegeneretteDgnrs`              | `DegeneretteModule.sol:1137`                       | :680                                  | reads `sdgnrs.poolBalance(Reward)` (external SLOAD; ETH + matches≥6 arm) + calls `sdgnrs.transferFromPool` |

**LootboxModule reachable from `_resolveLootboxDirect` delegatecall (LootboxModule.resolveLootboxDirect args: `presale=false, allowPasses=true, emitLootboxEvent=false, payColdBustConsolation=false, allowBoons=false`):**

| #  | Function                              | File:line                                          | Reached from                          | Notes |
|----|---------------------------------------|----------------------------------------------------|---------------------------------------|-------|
| 27 | `resolveLootboxDirect`                | `LootboxModule.sol:671`                            | delegatecall                          | derives `seed = keccak256(rngWord, player, day, amount)` (:676), reads `level` (:675), rolls target level |
| 28 | `_simulatedDayIndex`                  | `Storage.sol:1208`                                 | :674                                  | calls `GameTimeLib.currentDayIndex()` (pure on `block.timestamp` — no SLOAD) |
| 29 | `_rollTargetLevel`                    | `LootboxModule.sol:817`                            | :677                                  | `private pure` — no SLOADs |
| 30 | `_lootboxEvMultiplierBps`             | `LootboxModule.sol:444`                            | :679                                  | calls `IDegenerusGame(address(this)).playerActivityScore(player)` (re-entrant staticcall into `DegenerusGame.playerActivityScore` → `_playerActivityScore`) |
| 31 | `playerActivityScore` (external view) | `DegenerusGame.sol` (`playerActivityScore`)        | via staticcall                        | wraps `_playerActivityScore(player, questStreak, _activeTicketLevel())` |
| 32 | `_playerActivityScore`                | `MintStreakUtils.sol:83` + `:169`                  | staticcall                            | reads `mintPacked_[player]`, `level`, `_mintStreakEffective`, `_mintCountBonusPoints`, `affiliate.affiliateBonusPointsBest` (when uncached), `jackpotPhaseFlag` (via `_activeTicketLevel`) |
| 33 | `_mintStreakEffective`                | `MintStreakUtils.sol:51`                           | :95                                   | reads `mintPacked_[player]` |
| 34 | `_activeTicketLevel`                  | `MintStreakUtils.sol:72`                           | :173                                  | reads `jackpotPhaseFlag`, `level` |
| 35 | `_mintCountBonusPoints`               | `MintStreakUtils.sol` (helper)                     | :117                                  | reads `level`, `mintPacked_[player]` (level-count field) |
| 36 | `questView.playerQuestStates`         | external staticcall to QuestView                   | (not reached: `_playerActivityScore` reads quest streak from `mintPacked_` cache, see Phase 290 MINTCLN) — but the placement-time `_playerActivityScore` IS called via `_placeDegeneretteBetCore:457`. Resolution-time path uses staticcall **`IDegenerusGame.playerActivityScore`** (not the inline 2-arg overload), which DOES re-fetch quest streak through `questView` at the wrapper site. | external; cross-contract SLOAD on QuestView side — out of in-module scope per `D-298-TRACE-DEPTH-01` |
| 37 | `affiliate.affiliateBonusPointsBest`  | external staticcall to Affiliate                   | :145 (uncached branch)                | external; cross-contract SLOAD on Affiliate side — out of in-module scope |
| 38 | `_lootboxEvMultiplierFromScore`       | `LootboxModule.sol:453`                            | :446                                  | `private pure` — no SLOADs |
| 39 | `_applyEvMultiplierWithCap`           | `LootboxModule.sol:484`                            | :680                                  | reads `lootboxEvBenefitUsedByLevel[player][currentLevel]` (:496); writes same slot (:511) |
| 40 | `_resolveLootboxCommon`               | `LootboxModule.sol:960`                            | :682                                  | private; allowBoons=false (no `_rollLootboxBoons` reach); emitLootboxEvent=false; payColdBustConsolation=false |
| 41 | `_lootboxBoonBudget`                  | `LootboxModule.sol:838`                            | :992, :1030 (boon arm not reached)    | `private pure` — no SLOADs |
| 42 | `_accumulateLootboxRolls`             | `LootboxModule.sol:863`                            | :1004                                 | invokes `_resolveLootboxRoll` once or twice |
| 43 | `EntropyLib.hash2`                    | `libraries/EntropyLib.sol`                         | :897                                  | `internal pure` (keccak counter-tag) — no SLOADs |
| 44 | `_resolveLootboxRoll`                 | `LootboxModule.sol:1623`                           | :883, :899                            | 4-arm bit-slice on `seed` (:1640); per-arm subroutines below |
| 45 | `_lootboxTicketCount`                 | `LootboxModule.sol:1703`                           | :1645                                 | `private pure` — no SLOADs |
| 46 | `_lootboxDgnrsReward`                 | `LootboxModule.sol:1754`                           | :1652                                 | reads `dgnrs.poolBalance(Lootbox)` (external SLOAD on sDGNRS; out of in-module scope) |
| 47 | `_creditDgnrsReward`                  | `LootboxModule.sol:1784`                           | :1654                                 | calls `dgnrs.transferFromPool(Lootbox,…)` (external mutator) |
| 48 | `wwxrp.mintPrize` (external)          | external mutator                                   | :1671                                 | WWXRP arm of roll |
| 49 | `_queueTickets`                       | `Storage.sol:559`                                  | :1067                                 | reads `lastPurchaseDay`+`jackpotPhaseFlag`+`level`+`purchaseStartDay`+`rngRequestTime` via `_livenessTriggered`; reads `level`, `rngLockedFlag`, `ticketsOwedPacked[wk][buyer]`; writes `ticketQueue[wk]` + `ticketsOwedPacked` |
| 50 | `_livenessTriggered`                  | `Storage.sol:1243`                                 | :570                                  | reads `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` |
| 51 | `_tqWriteKey` / `_tqFarFutureKey`     | `Storage.sol`                                      | :573-575                              | reads `ticketWriteSlot` |
| 52 | `coinflip.creditFlip` (external)      | external mutator                                   | :1079                                 | BURNIE arm of roll (when `burnieAmount != 0`) |
| 53 | `PriceLookupLib.priceForLevel`        | `libraries/PriceLookupLib.sol`                     | :986, :1803 (lazyPass — boon arm NOT reached) | `internal pure` — no SLOADs |

**Explicit-enumeration cross-check** (per `feedback_verify_call_graph_against_source.md`):

- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameDegeneretteModule.sol` returns **one** delegatecall at `:804` (to `GAME_LOOTBOX_MODULE.resolveLootboxDirect`) — no other cross-module reach from inside the resolution path.
- `grep -n "delegatecall\|\.call\|staticcall" contracts/modules/DegenerusGameLootboxModule.sol` confirms two delegatecalls (to `GAME_BOON_MODULE.checkAndClearExpiredBoon` :1120 and `GAME_BOON_MODULE.consumeActivityBoon` :1035), but both live inside `if (allowBoons)` / `_rollLootboxBoons` — **NOT REACHED** under §8 (`allowBoons=false` per resolveLootboxDirect:693).
- `grep -n "IDegenerusGame(address(this))" contracts/modules/DegenerusGameLootboxModule.sol` returns ONE hit at `:445` (`_lootboxEvMultiplierBps` → `playerActivityScore` staticcall). Re-entrant staticcall into `DegenerusGame.playerActivityScore` is reached.
- Inline-assembly raw `sstore` / `slot:` directives in the consumer-reachable trace: `grep -rn "assembly\b" contracts/modules/DegenerusGameDegeneretteModule.sol contracts/modules/DegenerusGameLootboxModule.sol contracts/storage/DegenerusGameStorage.sol --include="*.sol" | grep -v "memory-safe"` returns zero raw-sstore hits in the consumer trace.
- `_revertDelegate` uses `assembly ("memory-safe") { revert(...) }` — error-path only, no sstore/sload.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during the resolution path (T2 window: between `lootboxRngWordByIndex[index]` SLOAD at Degenerette:594 and the final external mutator returns). Per `feedback_rng_window_storage_read_freshness.md`: ALL SLOADs enumerated, not only VRF-derived ones; non-VRF SLOADs alongside RNG are a distinct bug class (F-41-02/03 precedent).

| #     | Slot                                                  | Read-site (file:line)                          | Read context                                                              | Participating? | Attestation if NO |
|-------|-------------------------------------------------------|------------------------------------------------|---------------------------------------------------------------------------|----------------|-------------------|
| B-1   | `operatorApprovals[player][msg.sender]`               | `Degenerette:132` (via `_resolvePlayer:146`)   | EOA access check at outer entry                                            | NO             | Access-control gate; outcome (taken/not-taken) does not influence VRF-derived payout — only governs reach (which player's bets resolve). |
| B-2   | `degeneretteBets[player][betId]`                      | `Degenerette:571`                              | bet-input load (`packed`)                                                 | **YES**        | — |
| B-3   | `lootboxRngWordByIndex[index]`                        | `Degenerette:594`                              | **VRF-word source** (consumer entry §1 root SLOAD)                        | **YES**        | — |
| B-4   | `prizePoolFrozen`                                     | `Degenerette:748` (`_distributePayout`)        | frozen-branch dispatcher; selects pending vs live pool path               | **YES**        | — |
| B-5   | `prizePoolPendingPacked`                              | `Storage:707` (via `_getPendingPools` :755)    | reads pending pool when frozen                                            | **YES**        | — |
| B-6   | `prizePoolsPacked` (low 128 — next pool)              | `Storage:693` (via `_getPrizePools`)           | read in `_setPrizePools(next, …)` recompose at :804 (write path) and via `_getFuturePrizePool` at :797 | **YES**        | — |
| B-7   | `prizePoolsPacked` (high 128 — future pool)           | `Storage:693` / :797                           | reads `futurePrizePool` for cap calc (:770) + write recompose             | **YES**        | — |
| B-8   | `claimablePool`                                       | `Degenerette:1131` (`+= uint128(weiAmount)`)   | RMW on aggregate-credit slot                                              | NO             | RMW aggregate-balance counter; final-value bookkeeping for ETH-claim accounting. Its prior value does not enter the payout formula — `_addClaimableEth` increments unconditionally by `weiAmount` (which is fully determined by `rngWord`-derived `payout` + pool cap). |
| B-9   | `claimableWinnings[player]`                           | `PayoutUtils:35` (via `_creditClaimable`)      | RMW on per-player credit                                                  | NO             | RMW per-player balance; prior value does not enter the payout formula — `_creditClaimable` performs `+= weiAmount` only. (Note: the claimableWinnings WRITE recorded here is read at claim time `DegenerusGame.sol:910/924/1401`, outside the rng-window.) |
| B-10  | `level` (uint24)                                      | `LootboxModule:675` (`level + 1`)              | currentLevel for `_rollTargetLevel`                                       | **YES**        | — |
| B-11  | `lootboxEvBenefitUsedByLevel[player][currentLevel]`   | `LootboxModule:496`                            | EV-cap remaining-capacity calc                                            | **YES**        | — |
| B-12  | `mintPacked_[player]`                                 | `MintStreakUtils:90` (via `_playerActivityScore` staticcall) | streak/level-count/deity/whale-bundle for activity score                  | **YES**        | — |
| B-13  | `mintPacked_[player]` (streak fields)                 | `MintStreakUtils:55` (`_mintStreakEffective`)  | streak calc                                                               | **YES**        | — |
| B-14  | `level` (uint24)                                      | `MintStreakUtils:96` (`_playerActivityScore`)  | `currLevel` for frozen-until / streak / mint-count                        | **YES**        | — |
| B-15  | `jackpotPhaseFlag`                                    | `MintStreakUtils:73` (`_activeTicketLevel`)    | streak-base-level pick                                                    | **YES**        | — |
| B-16  | `mintPacked_[player]` (affiliate cache fields)        | `MintStreakUtils:140`                          | affiliate-bonus cached level/points                                       | **YES**        | — |
| B-17  | `dgnrs.poolBalance(Lootbox)` (external sDGNRS slot)   | `LootboxModule:1770`                           | DGNRS arm of `_resolveLootboxRoll` (10% arm: `roll ∈ [11,12]`)            | **YES**        | — (cross-contract, but reached from the participating roll arm; in-source-scope per `D-298-TRACE-DEPTH-01` because sDGNRS source lives at `contracts/StakedDegenerusStonk.sol`) |
| B-18  | `sdgnrs.poolBalance(Reward)` (external sDGNRS slot)   | `Degenerette:1147`                             | 6+ match ETH arm of `_awardDegeneretteDgnrs` (consumer §1 reach)          | **YES**        | — (cross-contract; in-source-scope) |
| B-19  | `lastPurchaseDay`                                     | `Storage:1244` (`_livenessTriggered`)          | productive-phase guard                                                    | **YES**        | — |
| B-20  | `jackpotPhaseFlag`                                    | `Storage:1244`                                 | productive-phase guard                                                    | **YES**        | — |
| B-21  | `level` (uint24)                                      | `Storage:1245`                                 | level==0 deploy-idle branch                                               | **YES**        | — |
| B-22  | `purchaseStartDay`                                    | `Storage:1246`                                 | day-clock                                                                 | **YES**        | — |
| B-23  | `rngRequestTime`                                      | `Storage:1250`                                 | VRF-stall fallback gate                                                   | **YES**        | — |
| B-24  | `level` (uint24)                                      | `Storage:571` (`_queueTickets`)                | `targetLevel > level + 5` far-future test                                 | **YES**        | — |
| B-25  | `rngLockedFlag`                                       | `Storage:572`                                  | far-future write gate                                                     | **YES**        | — |
| B-26  | `ticketWriteSlot`                                     | `Storage` (via `_tqWriteKey` / `_tqFarFutureKey`) | per-level read/write slot select                                          | **YES**        | — |
| B-27  | `ticketsOwedPacked[wk][buyer]`                        | `Storage:576`                                  | RMW on per-buyer ticket-owed count                                        | NO             | RMW counter; prior value does not enter the rolled `whole`-tickets formula — `_queueTickets` increments by `quantity` only. The participation question is whether the WRITE lands (gated by `_livenessTriggered` + `rngLockedFlag`); both gates are themselves participating slots (B-19..B-25). |
| B-28  | `ticketQueue[wk].length`                              | `Storage:579-581`                              | first-time-push test                                                      | NO             | RMW append; outcome (push vs no-push) is a function of `ticketsOwedPacked` (B-27 attestation applies). |

**Auxiliary §B-W — SSTOREs inside the rng-window (cross-check, not classified):**

| #    | Slot                                       | Write-site (file:line)                         | Notes |
|------|--------------------------------------------|------------------------------------------------|-------|
| B-W1 | `degeneretteBets[player][betId]`           | `Degenerette:597` (`delete`)                   | per-bet finalize; zero after resolution |
| B-W2 | `prizePoolPendingPacked`                   | `Storage:699` (via `_setPendingPools` :764)    | frozen-branch ETH share debit |
| B-W3 | `prizePoolsPacked`                         | `Storage:685` (via `_setFuturePrizePool` :780) | unfrozen-branch ETH share debit |
| B-W4 | `claimablePool`                            | `Degenerette:1131`                             | aggregate credit |
| B-W5 | `claimableWinnings[player]`                | `PayoutUtils:35`                               | per-player credit |
| B-W6 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule:511`                            | EV-cap used-benefit |
| B-W7 | `ticketsOwedPacked[wk][buyer]`             | `Storage:585`                                  | post-roll ticket queue |
| B-W8 | `ticketQueue[wk]` (array push)             | `Storage:580`                                  | first-time entry |

## CAT-03 (§C) — Writer enumeration for participating slots

Per `D-298-EXEMPT-REACH-01`: writers enumerated per-callsite. For each participating slot (`Participating? = YES` rows in §B), enumerate every external/public function in any contract under `contracts/` that writes the slot (OZ-inherited writers included; admin/owner writers included). The participating-slot universe under §8:

**Group I — input slot (per-bet entropy capture; the bet `packed` is consumed by `_resolveFullTicketBet`):**

### C-1 — `degeneretteBets[player][nonce]` (mapping → uint256)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-1a | `DegenerusGameDegeneretteModule._placeDegeneretteBetCore` | `Degenerette:479` (`degeneretteBets[player][nonce] = packed`) | EOA → `DegenerusGame.placeDegeneretteBet` (`DegenerusGame.sol:714`) → delegatecall → `placeDegeneretteBet` (Degenerette:367) → `_placeDegeneretteBet` (:405) → `_placeDegeneretteBetCore` (:437) | COMMITMENT-side SSTORE; gated `lootboxRngWordByIndex[index] != 0 ⇒ revert RngNotReady` at :452 (commitment must precede VRF publish for the captured `index`). |
| C-1b | `DegenerusGameDegeneretteModule._resolveBet` | `Degenerette:597` (`delete`) | EOA → `DegenerusGame.resolveDegeneretteBets` → … (the consumer itself) | Self-finalize delete; only zeros the slot after resolution — does not contribute participating-input entropy. |

**OZ-inherited writers check:** `degeneretteBets` is `internal mapping(address => mapping(uint64 => uint256))` declared in `DegenerusGameStorage`; no OZ ERC20/ERC721 path writes this slot. Confirmed via storage-layout review.

**Admin/owner writer check:** `grep -n "degeneretteBets" contracts/ -r` returns C-1a, C-1b, and one view-read at `DegenerusGame.sol:2111` (no writer). No admin path.

**Constructor/initializer writer check:** Default-zero mapping; no constructor write. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits in DegeneretteModule. Not applicable.

### C-2 — `lootboxRngWordByIndex[index]` (mapping → uint256; VRF entropy source)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-2a | `DegenerusGameAdvanceModule._finalizeLootboxRng` | `AdvanceModule:1256` | VRF coordinator → `DegenerusGame.fulfillRandomWords` (VRF callback) → delegatecall → `_finalizeLootboxRng(rngWord)` | **EXEMPT-VRFCALLBACK**: only reached from the Chainlink VRF coordinator callback stack (and `_finalizeLootboxRng` is private, called only from `rngGate`/fulfillment dispatch in AdvanceModule). |
| C-2b | `DegenerusGameAdvanceModule._gameOverEntropy` | `AdvanceModule:1761` | game-over historical-fallback tail-fill | **EXEMPT-VRFCALLBACK**: tail-fill of pending lootbox indices with the same VRF-callback-derived `finalWord` (`rngWordByDay[day]` snapshot); reaches only from `advanceGame()`-stack `_handleGameOverPath` → `_gameOverEntropy` → fallback branch. Game-over context — but classified per the EXEMPT category that owns the original `rngWord` derivation site. |
| C-2c | `DegenerusGameAdvanceModule._gameOverEntropy` (tail-fill at :1818) | `AdvanceModule:1818` | game-over backwards-fill from `lastFilledIndex` down to earliest unfilled | **EXEMPT-VRFCALLBACK**: same justification as C-2b. |

**OZ-inherited writers check:** `lootboxRngWordByIndex` is `internal mapping(uint48 => uint256)`; no OZ inheritance writes. Confirmed.

**Admin/owner writer check:** `grep -rn "lootboxRngWordByIndex" contracts/ --include="*.sol"` returns C-2a / C-2b / C-2c plus 8 reader sites (Degenerette:452/594, LootboxModule:533/612, AdvanceModule:210/269/1255/1812, MintModule:686). No admin-callable mutator.

**Constructor/initializer writer check:** Default-zero mapping. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits.

### C-3 — `prizePoolFrozen` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-3a | `DegenerusGameStorage._swapAndFreeze` | `Storage:757` (`prizePoolFrozen = true`) | only reached from `AdvanceModule._handleDailyAdvance` / `_handleJackpotPhaseAdvance` — i.e., `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-3b | `DegenerusGameStorage._unfreezePool` | `Storage:777` (`prizePoolFrozen = false`) | only reached from `advanceGame()`-rooted advance helpers | **EXEMPT-ADVANCEGAME** |

**OZ/admin/constructor/assembly:** Default-false; no other writers.

### C-4 — `prizePoolPendingPacked` (uint256 packed)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-4a | `DegenerusGameStorage._setPendingPools` | `Storage:699` | callers below | helper |
| C-4b | `_swapAndFreeze` (clear path) | `Storage:764` (`prizePoolPendingPacked = 0`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4c | `_unfreezePool` | `Storage:776` (`= 0`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4d | `_swapAndFreeze` (seed path) | `Storage:762` (via `_setPendingPools`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-4e | `DegenerusGameDegeneretteModule._collectBetFunds` (frozen-branch place) | `Degenerette:553` (via `_setPendingPools`) | EOA → `placeDegeneretteBet` external | **VIOLATION** — see §D-1 |
| C-4f | `DegenerusGameDegeneretteModule._distributePayout` (frozen-branch ETH share) | `Degenerette:764` (via `_setPendingPools`) | the resolution path itself (consumer §B) | **EXEMPT-VRFCALLBACK** — self-write inside the consumer's resolution call; reached only after the consumer's `rngWord` SLOAD at :594. |
| C-4g | `DegenerusGameJackpotModule.payDailyJackpot` & companion jackpot writers (pool drains) | `JackpotModule.sol` (writes to pending pools during JP distribution) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** (covered in §1/§2 of catalog) |
| C-4h | `DegenerusGameMintModule._mintTickets` (frozen-branch purchase) | `MintModule` purchase paths that write `prizePoolPendingPacked` via `_setPendingPools` when `prizePoolFrozen` | EOA → `purchaseTicketsByFunction` / `purchaseTicketsWithBurnie` / etc. | **VIOLATION-CANDIDATE** — but these mutate the `next`/`future` aggregates the consumer's `_getFuturePrizePool` does NOT read during T2 (the frozen path reads `_getPendingPools`, not `_getFuturePrizePool`); however §8 frozen-path solvency check at :758 (`if (uint256(pFuture) < ethShare) revert E()`) DOES read `pFuture` from the pending pool — so writers that change `prizePoolPendingPacked.future` between T1 and T2 ARE participating. See §D-2. |

**OZ/admin/constructor:** No admin path writes pending pool. No constructor write (default zero). No inline assembly.

**Note on resolution-write of C-4f / C-4 family during T2:** The §8 consumer's own `_distributePayout` performs a frozen-branch SSTORE to `prizePoolPendingPacked` (debiting `pFuture`). This is a write-then-no-read within the same resolution (the consumer reads `_getPendingPools` ONCE before debiting and writes once); the slot is not re-read after the consumer write. So C-4f's read-then-write is internal-consistent; the concern at §D is whether OTHER writers race between :755 (read) and :764 (write) — which would only happen in a multi-tx interleaving against a parallel re-entry — non-issue (single-tx execution).

### C-5 — `prizePoolsPacked` (uint256 packed; next + future)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-5a | `_setPrizePools` (helper) | `Storage:684` | callers below | helper |
| C-5b | `DegenerusGameJackpotModule.*` jackpot distribution writers | various | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** (covered in §1/§2/§3) |
| C-5c | `DegenerusGameDegeneretteModule._distributePayout` (unfrozen-branch) | `Degenerette:780` (via `_setFuturePrizePool`) | the resolution path itself | **EXEMPT-VRFCALLBACK** (self-write inside consumer) |
| C-5d | `DegenerusGameDegeneretteModule._collectBetFunds` (unfrozen-branch place) | `Degenerette:556` (via `_setPrizePools`) | EOA → `placeDegeneretteBet` external | **VIOLATION-CANDIDATE** — see §D-3 |
| C-5e | `DegenerusGameMintModule.*` ticket purchase pool credits | `MintModule` purchase paths that write `prizePoolsPacked` via `_setPrizePools` | EOA → ticket purchase externals | **VIOLATION-CANDIDATE** — see §D-3 |
| C-5f | `_unfreezePool` (apply pending → live) | `Storage:775` | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-5g | `DegenerusGameDecimatorModule.*` decimator-pool writers | DecimatorModule | EOA-callable decimator claim entries | **VIOLATION-CANDIDATE** if reach-window applies (see §D-3) |

**OZ/admin/constructor:** No admin path. Initialized in constructor; not relevant post-deploy.

### C-6 — `level` (uint24)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-6a | `DegenerusGameAdvanceModule._processJackpotPhaseAdvance` | `AdvanceModule:1643` (`level = lvl`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |

Single writer — confirmed by `grep -rn "^\s*level\s*=" contracts/ --include="*.sol"` returning C-6a as the sole post-deploy mutator.

### C-7 — `lootboxEvBenefitUsedByLevel[player][lvl]` (mapping → uint256)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-7a | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule:511` | reachable from any caller of `_applyEvMultiplierWithCap`: `openLootBox` (:567), `openBurnieLootBox` (`grep` confirms not reached), `resolveLootboxDirect` (:680, the §8 consumer path), `resolveRedemptionLootbox` (:716) | Per-callsite classification: |
| | | called from `resolveLootboxDirect` (:680) | resolution path itself (consumer's reach) | **EXEMPT-VRFCALLBACK** (consumer-self) |
| | | called from `resolveRedemptionLootbox` (:716) | EOA → sDGNRS.claimRedemption → DegenerusGame → delegatecall LootboxModule.resolveRedemptionLootbox | EXEMPT-VRFCALLBACK if the redemption flow is reached only from a VRF-callback-driven stack; per consumer §6 audit, the redemption flow reads `rngWordForDay(claimPeriodIndex)` from snapshot (see §6) — classified at §6. For §8, this is a parallel-consumer write site, not a same-tx write. |
| | | called from `openLootBox` (:567) | EOA → `DegenerusGame.openLootBox` → delegatecall LootboxModule.openLootBox | **VIOLATION-CANDIDATE** — EOA can grind a same-block prior `openLootBox` call that changes `lootboxEvBenefitUsedByLevel[player][currentLevel]` BEFORE the §8 resolver reads the same slot at :496. See §D-4. |

**OZ/admin/constructor:** No admin path. Default zero. No raw assembly.

### C-8 — `mintPacked_[player]` (mapping → uint256; many fields)

`mintPacked_` is heavily written across the codebase (mint, deity, whale, affiliate, quest, frozen-until — all packed into one 256-bit slot per player).

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-8a | `DegenerusGameMintStreakUtils._recordMintStreakForLevel` | `MintStreakUtils:47` | called from any path that finalizes a mint quest completion for the player; reaches via `quests.handleX` + `_creditTicketSale` etc. | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8b | `MintModule._*Mint*` / `MintModule.purchase*` writers | various MintModule writes to packed mint counters / bundle type / frozen-until-level | EOA → ticket-purchase / deity-pass / whale-pass purchase externals | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8c | `DegenerusGameStorage._setMintDay` | `Storage` (called by mint paths) | EOA-reachable mint paths | **VIOLATION-CANDIDATE** — see §D-5 |
| C-8d | Affiliate-cache update writers (level-transition cache refresh) | `MintModule` / `AdvanceModule` affiliate-cache refresh path | reaches from `advanceGame()`-stack level transition AND from `MintModule` purchase recompute | Mixed: cache refresh on level transition is **EXEMPT-ADVANCEGAME**; recompute on purchase is **VIOLATION-CANDIDATE**. See §D-5. |

**OZ-inherited writers check:** `mintPacked_` is `internal mapping(address => uint256)`; no OZ inheritance. Confirmed.

**Admin/owner writer check:** `grep -rn "mintPacked_\[" contracts/ --include="*.sol"` returns ~30 hits across DegenerusGame.sol + MintModule + AdvanceModule + JackpotModule + MintStreakUtils — none gated by `onlyOwner`/`onlyAdmin`. All reach is via game-action externals (purchase, deity claim, whale claim, jackpot pay, advance).

**Constructor/initializer writer check:** Default zero. Not applicable.

**Inline-assembly raw-sstore check:** Zero hits.

### C-9 — `jackpotPhaseFlag` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-9a | `AdvanceModule._processAdvance` (purchase → jackpot) | `AdvanceModule:437` (`= true`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-9b | `AdvanceModule._processJackpotPhaseAdvance` (jackpot → purchase) | `AdvanceModule:333` (`= false`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |

### C-10 — `lastPurchaseDay`, `purchaseStartDay`, `rngRequestTime` (liveness inputs)

`lastPurchaseDay`, `purchaseStartDay`, `rngRequestTime`, `dailyIdx` are all written exclusively from `advanceGame()`-rooted helpers (`_handleDailyAdvance`, `_processAdvance`, `_requestRng`, `_finalizeLootboxRng`, `_unlockRng`, `_handleGameOverPath`, `_gameOverEntropy`). Confirmed via:
- `grep -rn "lastPurchaseDay\s*=\|purchaseStartDay\s*=\|rngRequestTime\s*=" contracts/ --include="*.sol"` → all hits live in `AdvanceModule.sol` (no external EOA mutators outside the advance stack).

| # | Slot | Writer summary | Classification |
|---|------|----------------|----------------|
| C-10a | `lastPurchaseDay` | AdvanceModule writes only | **EXEMPT-ADVANCEGAME** |
| C-10b | `purchaseStartDay` | AdvanceModule writes only | **EXEMPT-ADVANCEGAME** |
| C-10c | `rngRequestTime` | AdvanceModule `_requestRng` + VRF callback clear | **EXEMPT-VRFCALLBACK** / **EXEMPT-ADVANCEGAME** |

### C-11 — `rngLockedFlag` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-11a | `AdvanceModule._requestRng` | `AdvanceModule:1634` (`= true`) | `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| C-11b | `AdvanceModule._unlockRng` | `AdvanceModule:1690` / `:1731` (`= false`) | `advanceGame()` stack + `retryLootboxRng` failsafe | **EXEMPT-ADVANCEGAME** / **EXEMPT-RETRYLOOTBOXRNG** |

### C-12 — `ticketWriteSlot` (bool)

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C-12a | `Storage._swapTicketSlot` | `Storage:744` | called only from `_swapAndFreeze` (Storage:755) which is `advanceGame()`-only | **EXEMPT-ADVANCEGAME** |

### C-13 — external sDGNRS pool balances (cross-contract)

| # | Slot | Read-site (this consumer) | Writer reach | Notes |
|---|------|---------------------------|-------------|-------|
| C-13a | `dgnrs.poolBalance(Lootbox)` (StakedDegenerusStonk's `pools[Lootbox].balance`) | `LootboxModule:1770` | sDGNRS `addToPool` (called by DegenerusGame on transitions + `transferFromPool` called by various) | Reach is the EOA-driven user-claim + deposit surface PLUS the `advanceGame()`-stack allocation; per-callsite classification deferred to consumer §12 (sStonk redemption catalog). For §8, the read of `poolBalance` is participating; the sDGNRS-side writers are out-of-this-section but the dispatch surface includes EOA paths. **VIOLATION-CANDIDATE.** See §D-6. |
| C-13b | `sdgnrs.poolBalance(Reward)` | `Degenerette:1147` | same as above (Reward pool) | Same classification — **VIOLATION-CANDIDATE.** See §D-7. |

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite + per-slot. Classification set: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION` — the v43.0 milestone goal prohibits any non-exempt disposition for participating slots, so every non-EXEMPT row is `VIOLATION`.

| #    | Slot                                                | Writer function · callsite                                         | Reached from EXEMPT stack? | Classification |
|------|-----------------------------------------------------|---------------------------------------------------------------------|----------------------------|----------------|
| D-0a | `degeneretteBets[player][nonce]`                    | `_placeDegeneretteBetCore:479`                                      | NO — EOA `placeDegeneretteBet` external | **VIOLATION** — write site is outside the 3 EXEMPT classes. The pre-RNG gate at Degenerette:452 (`if (lootboxRngWordByIndex[index] != 0) revert RngNotReady;`) blocks placement once VRF has published for the captured `index`; structurally this prevents post-T1 mutation of `degeneretteBets[player][betId]`. Catalog still flags VIOLATION per milestone-goal classification rules; §E-12 records that Phase 299 FIX must verify the :452 gate's coverage across index-rollover edges. |
| D-0b | `degeneretteBets[player][nonce]`                    | `_resolveBet:597` (self-delete)                                     | YES — the consumer itself (self-write inside the resolution stack post-rngWord SLOAD) | **EXEMPT-VRFCALLBACK** |
| D-1  | `lootboxRngWordByIndex[index]`                      | `AdvanceModule._finalizeLootboxRng:1256`                            | YES — VRF coordinator callback        | **EXEMPT-VRFCALLBACK** |
| D-2  | `lootboxRngWordByIndex[index]` (tail-fill)          | `AdvanceModule._gameOverEntropy:1761`                               | YES — game-over advanceGame stack     | **EXEMPT-VRFCALLBACK** (per D-43N V43 prose: terminal/game-over substitution path is also EXEMPT under the VRF-callback class because the source `finalWord` itself derives from a VRF callback or historical-VRF fallback per Phase 296 SWEEP) |
| D-3  | `lootboxRngWordByIndex[index]` (tail-fill at :1818) | `AdvanceModule._gameOverEntropy:1818`                               | YES — game-over advanceGame stack     | **EXEMPT-VRFCALLBACK** |
| D-4  | `prizePoolFrozen`                                   | `Storage._swapAndFreeze:757` + `_unfreezePool:777`                  | YES — `advanceGame()` only            | **EXEMPT-ADVANCEGAME** |
| D-5  | `prizePoolPendingPacked` (clear/seed)               | `Storage._swapAndFreeze:762/:764` + `_unfreezePool:776`             | YES                                    | **EXEMPT-ADVANCEGAME** |
| D-6  | `prizePoolPendingPacked` (consumer self-write)      | `Degenerette._distributePayout:764`                                 | YES — self-write inside §8 resolution | **EXEMPT-VRFCALLBACK** |
| D-7  | `prizePoolPendingPacked` (place-bet frozen-branch)  | `Degenerette._collectBetFunds:553`                                  | NO — EOA `placeDegeneretteBet`        | **VIOLATION** — between T1 and T2 of any in-flight bet's resolution, OTHER EOAs (or the same EOA placing a SECOND bet) can call `placeDegeneretteBet` and increment `prizePoolPendingPacked.future`. The §8 resolution reads `pFuture` at :755 to gate `if (uint256(pFuture) < ethShare) revert E()` — extra pending future inflates `pFuture`, making a borderline-insolvent ETH share PAYABLE under a known `rngWord`. Attacker pre-purchases a high-N gold ticket, observes the published `rngWord` → known `matches`, known `payout`, known `ethShare`, known `pFuture`; if `pFuture < ethShare` would revert under T0's `pFuture`, EOA tops up `prizePoolPendingPacked.future` via a fresh `placeDegeneretteBet` (frozen-branch) to flip the predicate to `pFuture ≥ ethShare` → bet resolves where it would otherwise revert. See §E-1. |
| D-8  | `prizePoolPendingPacked` (mint-purchase frozen-branch) | `MintModule.*` purchase paths that call `_setPendingPools` when `prizePoolFrozen` | NO — EOA ticket-purchase externals | **VIOLATION** — same mechanism as D-7 but via the MintModule ticket-purchase entry points (`purchaseTicketsByFunction` etc.). Attacker EOA can drive `prizePoolPendingPacked.future` upward by purchasing tickets between T1 and T2. The §8 resolution's pFuture-gate at :758 reads the post-mint value. See §E-2. |
| D-9  | `prizePoolPendingPacked` (jackpot frozen-branch)    | `JackpotModule.*` pending writes in jackpot-distribution stack      | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** (jackpot distribution happens within advance; not EOA-callable between T1/T2 except via the same advance stack which is single-tx per day) |
| D-10 | `prizePoolsPacked` (consumer self-write)            | `Degenerette._distributePayout:780`                                 | YES — self-write inside §8 resolution | **EXEMPT-VRFCALLBACK** |
| D-11 | `prizePoolsPacked` (advance-stack)                  | `JackpotModule.*` distribution + `_unfreezePool:775`                | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-12 | `prizePoolsPacked` (place-bet unfrozen-branch)      | `Degenerette._collectBetFunds:556`                                  | NO — EOA `placeDegeneretteBet`        | **VIOLATION** — analogous to D-7 but on the UNFROZEN branch: `_distributePayout` reads `_getFuturePrizePool` at :770 and uses it as the `pool × ETH_WIN_CAP_BPS / 10_000` cap denominator. EOA pre-buys a high-N gold ticket; under unfrozen-branch (more common), bumping `prizePoolsPacked.future` upward between T1 and T2 inflates the cap and lets a bigger `ethShare` pay out (vs being capped to `pool × 10%`, with the remainder going to lootbox — strictly worse RTP for the player). Direction-of-attack: increase pool → take MORE ETH; decrease pool → impossible from this writer. EOA-controlled UP-movement is the participating risk. See §E-3. |
| D-13 | `prizePoolsPacked` (mint-purchase unfrozen-branch)  | `MintModule.*` purchase paths                                       | NO — EOA ticket-purchase externals     | **VIOLATION** — same mechanism as D-12. See §E-4. |
| D-14 | `prizePoolsPacked` (decimator pool writers)         | `DecimatorModule.*` pool drains (e.g., `decimatorClaim` paths)      | NO — EOA decimator claim externals     | **VIOLATION** — direction-of-attack: decimator pool drains DOWNWARD which would shrink the cap. EOA-controlled DOWN-movement of `futurePool` (post-RNG) can convert an ETH share that would have been capped at `maxEth` into a SMALLER cap → MORE lootbox conversion. Reverse direction from D-12 but still participating. See §E-5. |
| D-15 | `level`                                             | `AdvanceModule._processJackpotPhaseAdvance:1643`                    | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-16 | `lootboxEvBenefitUsedByLevel[player][lvl]` (self)   | `LootboxModule._applyEvMultiplierWithCap:511` via `resolveLootboxDirect` self-call | YES — self-write | **EXEMPT-VRFCALLBACK** |
| D-17 | `lootboxEvBenefitUsedByLevel[player][lvl]` (openLootBox path) | `LootboxModule._applyEvMultiplierWithCap:511` via `openLootBox` external | NO — EOA `openLootBox` (`DegenerusGame.openLootBox` → delegatecall) | **VIOLATION** — Attacker observes `rngWord` at T1, computes the §8 spin loop result, knows their `ethShare`, knows whether they're capped at neutral (100%) or boosted (≤135%). If `lootboxEvBenefitUsedByLevel[player][lvl] ≥ LOOTBOX_EV_BENEFIT_CAP`, the §8 resolver's `_applyEvMultiplierWithCap` skips the EV adjustment (neutral 100%). EOA can call `openLootBox` (or `openBurnieLootBox` — though that path doesn't write this slot per check) BEFORE `resolveDegeneretteBets` to exhaust the cap → force the §8 ETH-share path through a neutral EV (when the player's score would otherwise boost). Direction-of-attack: drain remaining cap to make EV neutral when boost would lose; preserve cap when boost would win. Per-callsite VIOLATION. See §E-6. |
| D-18 | `lootboxEvBenefitUsedByLevel[player][lvl]` (resolveRedemptionLootbox path) | `LootboxModule._applyEvMultiplierWithCap:511` via `resolveRedemptionLootbox` external | EOA — sDGNRS-driven redemption (see §6) | **VIOLATION** — same mechanism as D-17; redemption-flow callsite is also EOA-reachable. See §E-6 (folded). |
| D-19 | `mintPacked_[player]` (mint-streak completion)      | `MintStreakUtils._recordMintStreakForLevel:47`                      | NO — EOA quest-completion path via `coin.handleX` → `quests` → cross-contract callbacks reaching DegenerusGame mint-credit. **AND** also reached from `advanceGame()` jackpot-tickets payouts. Per-callsite: | Mixed; **VIOLATION** for the EOA-quest-completion callsite. See §E-7. |
| D-20 | `mintPacked_[player]` (mint count + frozen-until + bundle type) | `MintModule._mintTickets` / deity / whale purchase writers          | NO — EOA ticket-purchase externals     | **VIOLATION** — `_playerActivityScore` reads `mintPacked_[player]` at MintStreakUtils:90 (level-count, deity, whale-bundle, frozen-until-level). EOA can move these fields between T1 and T2 by purchasing tickets / deity-pass / whale-pass → bumps `activityScore` → bumps `_lootboxEvMultiplierBps` (B-12) → bumps `scaledAmount` (B-W6 written) → flips the EV multiplier toward 135% (max). Attacker observes `rngWord` at T1, computes the §8 lootbox-arm result; if the result would crit (e.g., DGNRS large tier or BURNIE high-path), buys deity-pass to boost activity → boosts EV → 35% bonus on the crit lootbox amount. Per-callsite VIOLATION (EOA purchase callsite). See §E-8. |
| D-21 | `mintPacked_[player]` (affiliate cache refresh — recompute path) | `MintModule` affiliate-cache refresh on purchase | NO — EOA purchase externals | **VIOLATION** — `_playerActivityScore` at MintStreakUtils:140 reads the cached affiliate-bonus level + points fields from `mintPacked_`. Cached-level mismatch (`cachedLevel != currLevel`) falls through to live `affiliate.affiliateBonusPointsBest(currLevel, player)` external call. EOA can manipulate the cache via purchase to switch between cached/live branches and choose the higher of the two. See §E-9. |
| D-22 | `mintPacked_[player]` (affiliate cache refresh — advanceGame transition path) | `AdvanceModule` level transition affiliate-cache write | YES — `advanceGame()` stack | **EXEMPT-ADVANCEGAME** |
| D-23 | `jackpotPhaseFlag`                                  | `AdvanceModule:333 / :437`                                          | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-24 | `lastPurchaseDay` / `purchaseStartDay` / `rngRequestTime` (liveness inputs) | various AdvanceModule writes (no EOA-direct mutators)               | YES — `advanceGame()` / VRF callback   | **EXEMPT-ADVANCEGAME** / **EXEMPT-VRFCALLBACK** |
| D-25 | `rngLockedFlag`                                     | `AdvanceModule._requestRng:1634` + `_unlockRng:1690/:1731`          | YES — `advanceGame()` + `retryLootboxRng` | **EXEMPT-ADVANCEGAME** / **EXEMPT-RETRYLOOTBOXRNG** |
| D-26 | `ticketWriteSlot`                                   | `Storage._swapTicketSlot:744`                                       | YES — `advanceGame()`                  | **EXEMPT-ADVANCEGAME** |
| D-27 | `dgnrs.poolBalance(Lootbox)` (sDGNRS-side)          | sDGNRS `addToPool` + `transferFromPool` writers reachable from EOA paths (claim/redeem) | NO — EOA sDGNRS user paths            | **VIOLATION** — `_lootboxDgnrsReward` reads `dgnrs.poolBalance(Lootbox)` at :1770; this is the SCALAR that multiplies into `dgnrsAmount = (poolBalance * ppm * amount) / (1e6 * 1 ether)`. EOA can drain the Lootbox pool via legitimate `transferFromPool` callers between T1 and T2 (e.g., another player's win) — concurrent-actor race; but the §8 player can also opportunistically time their own resolution to occur AFTER a pool-drain they observe in mempool. Direction: pool drain → smaller `dgnrsAmount` → smaller payout (bad for player); pool top-up → larger `dgnrsAmount`. EOA controls timing by deferring `resolveDegeneretteBets` call. See §E-10. |
| D-28 | `sdgnrs.poolBalance(Reward)` (sDGNRS-side; 6+ match arm) | sDGNRS `addToPool` + `transferFromPool` writers                     | NO — EOA sDGNRS user paths            | **VIOLATION** — analogous to D-27 for the Reward pool. `_awardDegeneretteDgnrs` reads `poolBalance(Reward)` at :1147 then computes `reward = (poolBalance * bps * cappedBet) / (1e4 * 1 ether)`. Same timing-race attack class. See §E-11. |

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| #     | VIOLATION                                                                                              | Recommended tactic | Rationale (≤80 chars) |
|-------|--------------------------------------------------------------------------------------------------------|--------------------|------------------------|
| E-1   | D-7: `_collectBetFunds:553` increments `prizePoolPendingPacked.future` while §8 in-flight bet pending  | **(a)**            | Gate place-bet on `rngLockedFlag` so window closes once VRF requested |
| E-2   | D-8: MintModule frozen-branch ticket-purchase increments pending pool                                  | **(a)**            | Existing far-future `RngLocked` gate (:572) covers; extend to pending writes |
| E-3   | D-12: `_collectBetFunds:556` increments `prizePoolsPacked.future` (unfrozen-branch); inflates EV cap   | **(b)**            | Snapshot `futurePool` cap at bet placement; cap-check reads frozen snapshot |
| E-4   | D-13: MintModule unfrozen-branch ticket-purchase increments futurePool                                 | **(b)**            | Same snapshot tactic; per-bet `futurePool` snapshot recorded in `packed` |
| E-5   | D-14: Decimator pool drain decreases futurePool between T1 and T2 → shrinks cap → more lootbox        | **(b)**            | Per-bet futurePool snapshot also covers DOWN-movement |
| E-6   | D-17/D-18: `lootboxEvBenefitUsedByLevel[player][lvl]` mutated via `openLootBox` / `resolveRedemptionLootbox` between T1/T2 | **(b)**            | Snapshot `evMultiplierBps` at bet placement (already in `packed.activityScore`-adjacent slot) |
| E-7   | D-19: `mintPacked_[player]` mint-streak completion via EOA quest path mutates activity score          | **(b)**            | `activityScore` already snapshotted at :458; re-use snapshot in lootbox EV |
| E-8   | D-20: `mintPacked_[player]` purchase-driven field writes (level-count, deity, whale, frozen-until)    | **(b)**            | Snapshot full activity-score-input set at bet placement; lootbox EV reads snapshot |
| E-9   | D-21: `mintPacked_[player]` affiliate cache mismatch lets EOA choose cached vs live affiliate points  | **(b)**            | Snapshot covers; per-bet `activityScore` already capture-time-frozen at :458 |
| E-10  | D-27: `dgnrs.poolBalance(Lootbox)` EOA timing race shifts DGNRS reward scalar between T1/T2          | **(b)**            | Snapshot `poolBalance` at bet placement OR cap reward to amount × ppm (no pool ratio) |
| E-11  | D-28: `sdgnrs.poolBalance(Reward)` EOA timing race shifts sDGNRS reward scalar                       | **(b)**            | Snapshot `poolBalance` at bet placement OR remove pool-ratio scaling |
| E-12  | D-0a: `degeneretteBets[player][nonce]` written by `_placeDegeneretteBetCore:479` outside EXEMPT stack | **(a)**            | Existing :452 `lootboxRngWordByIndex[index] != 0 ⇒ RngNotReady` is the gate; verify post-RNG placement is impossible across all index-rollover edges |

**Rationale expansion (out-of-table for traceability):**

- **E-1 / E-2 (tactic (a) gated revert):** The CURRENT place-bet gate at Degenerette:452 only revert if `lootboxRngWordByIndex[index] != 0`; this requires a fresh CURRENT lootbox RNG index (the one captured at :450). But between RNG-request (T-request: `rngLockedFlag = true`) and RNG-publish (T1: `lootboxRngWordByIndex[index] = rngWord`), the `index` slot is still the OLD index (unchanged until `_finalizeLootboxRng` advances it). Place-bet at this point captures the SAME `index` as the in-flight bet that's about to resolve, but with `rngWord` still 0 → place-bet SUCCEEDS, pumping `prizePoolPendingPacked.future` (D-7) or `prizePoolsPacked.future` (D-12) just before T1+T2. Tactic (a) extends the gate to `rngLockedFlag == true ⇒ revert` so the window closes at VRF-request, not just at VRF-publish.

- **E-3..E-9 (tactic (b) snapshot/anchor):** Mirror Phase 281 owed-salt + Phase 288 dailyIdx pattern. The bet's `packed` already stores `activityScore` (snapshotted at :458). Extend the snapshot to include `futurePool`, `evMultiplierBps`, and the full activity-score input fields read at MintStreakUtils:90/96/140 — so the resolver does not re-read these at T2. Slot-budget within `packed` is tight (236 hero-bit + 3 hero quadrant = currently 240 bits, leaves 16 bits before bit-256); a parallel snapshot mapping `degeneretteBetSnapshot[player][nonce]` packs `futurePool` (uint128) + `evMultiplierBps` (uint16) + reserved into a single new SSTORE per place-bet.

- **E-10 / E-11 (tactic (b) pool-balance snapshot OR remove pool-ratio):** The sDGNRS-pool-balance scalar in `dgnrsAmount = (poolBalance × ppm × amount) / (1e6 × 1e18)` is a multi-actor-controlled aggregate. Two equally-effective options: (1) snapshot `poolBalance` at bet placement (added to the parallel snapshot mapping above); (2) remove the pool-ratio scaling entirely and let `dgnrsAmount = ppm × amount / 1e6` (independent of pool size) — accepting that the pool may temporarily be insufficient and that `transferFromPool` returns the actual paid amount. Phase 299 FIX sub-phase planning re-discovers design intent per `feedback_design_intent_before_deletion.md`.

- **E-12 (D-0a structural attestation):** The slot is written outside the 3 EXEMPT classes (EOA `placeDegeneretteBet`); strict per-callsite classification flags this as VIOLATION. However, the structural gate at :452 (`if (lootboxRngWordByIndex[index] != 0) revert RngNotReady;`) forces all placements to occur BEFORE VRF publish for the captured `index`. Phase 299 FIX sub-phase planning must verify this gate's coverage across all index-advancement edges (e.g., index-rollover when LR_INDEX_SHIFT field increments — the captured `index` could in principle have its `rngWordByIndex` published while a different `_lrRead` returns a NEW current index that's still zero, opening a window for post-T1 placement on the OLD index. Catalog flags this; FIX phase derives the proof.).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside the §8 resolution path enumerated per `feedback_rng_window_storage_read_freshness.md`; no "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Cross-module trace into LootboxModule + Storage + MintStreakUtils + PayoutUtils followed transitively per `D-298-TRACE-DEPTH-01`.
- **Commitment-window discipline** (per `feedback_rng_commitment_window.md`): RNG commitment point is the SSTORE at `AdvanceModule.sol:1256` (`lootboxRngWordByIndex[index] = rngWord`); player-controllable state that can change between this SSTORE and the consumer reads at Degenerette:594 / LootboxModule:533/612 has been enumerated in §D and assigned a tactic in §E.
- **Two-rooted §8 trace:** Both consumer entries (Degenerette:594 + Degenerette:797) share the same RNG-word source slot and the same external entry point (`resolveDegeneretteBets`). The :797 sub-tree (LootboxModule.resolveLootboxDirect) adds B-10..B-17 + B-24..B-28 to the SLOAD set; the inline :594 sub-tree owns B-1..B-9 + B-18..B-23 directly. Shared SLOADs: B-3 (`lootboxRngWordByIndex[index]`), B-12/B-14 (`mintPacked_`/`level` reached from both via different code paths), B-19..B-23 (liveness inputs reached only from the :797 sub-tree).
- **Verdicts:** 28 §D rows total · 13 EXEMPT-ADVANCEGAME · 7 EXEMPT-VRFCALLBACK · 0 EXEMPT-RETRYLOOTBOXRNG (D-25 has one mixed sub-row that touches RETRYLOOTBOXRNG via `_unlockRng:1731`) · **12 VIOLATION** (D-0a, D-7, D-8, D-12, D-13, D-14, D-17, D-18, D-19, D-20, D-21, D-27, D-28 — counting D-0a + the 12 listed in §E rows E-1..E-12).
- **Scope:** zero `contracts/` + zero `test/` mutations per `D-43N-AUDIT-ONLY-01`.
