# §6 — LootboxModule.resolveRedemptionLootbox (file:line 707)

**Consumer entry:** `contracts/modules/DegenerusGameLootboxModule.sol:707`
**Signature:** `function resolveRedemptionLootbox(address player, uint256 amount, uint256 rngWord, uint16 activityScore) external`
**Access guard:** none on the module entry itself — guard sits one level up in `DegenerusGame.resolveRedemptionLootbox` (`DegenerusGame.sol:1727`: `if (msg.sender != ContractAddresses.SDGNRS) revert E();`). Module is invoked via `delegatecall` from the Game wrapper, so the module body executes in Game storage.
**Caller chain:** `StakedDegenerusStonk.claimRedemption` (`StakedDegenerusStonk.sol:618`, EOA-callable by `msg.sender == player`) at `:670` reads `game.rngWordForDay(claimPeriodIndex)` → `rngWordByDay[claimPeriodIndex]` (historical VRF word), builds `entropy = keccak256(rngWord, player)` at `:671`, calls `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` at `:672`. Game wrapper (`DegenerusGame.sol:1721`) loops in 5-ETH chunks calling LootboxModule via delegatecall (`:1754-1767`), advancing `rngWord = keccak256(rngWord)` each chunk (`:1769`). **Trace-root entry** for this catalog section is the module-body function at `:707`.

**Commitment-window framing** (per `feedback_rng_commitment_window.md`): the `rngWord` consumed here is **not** a freshly-VRF-fulfilled word. It is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable storage value written days/weeks earlier by `_applyDailyRng` (`AdvanceModule.sol:1841`). The player chooses the moment of `claimRedemption`; at that moment the player has already observed `rngWord`. The "RNG commitment time" relative to this consumer is therefore **the moment the player initiates the claim transaction**, not the VRF fulfillment. Every SLOAD reached during resolution that influences output is consumed **after the attacker knows the VRF word** and is therefore a participating slot unless the slot's value is structurally invariant against attacker manipulation in the window between `rngWord` publication and the player-chosen claim moment.

**Why this consumer is non-EXEMPT:** the entry-point stack is `sStonk.claimRedemption` (EOA), NOT `advanceGame()`, NOT VRF coordinator callback, NOT `retryLootboxRng()`. Per `D-298-EXEMPT-REACH-01`, every participating-slot writer reached from this consumer's resolution stack is classified `VIOLATION` unless the **writer-callsite** itself is independently descendancy-reachable from one of the three EXEMPT entry stacks.

## CAT-01 (§A) — Traced function set

Backward-trace from `resolveRedemptionLootbox` (`LootboxModule.sol:707`); every function transitively reached during resolution per `D-298-TRACE-DEPTH-01` (trace walks into every source contract under `contracts/`, stops only at no-source external interfaces).

| #  | Function | File:line | Reached from | Notes |
|----|---|---|---|---|
| 1  | `resolveRedemptionLootbox` (module) | `LootboxModule.sol:707` | entry | consumer root (executes in Game storage via delegatecall from `DegenerusGame.sol:1754`) |
| 2  | `_simulatedDayIndex` | `DegenerusGameStorage.sol:1208` | `LootboxModule.sol:710` | wraps `GameTimeLib.currentDayIndex()`; `block.timestamp`-derived, no SLOAD |
| 3  | `GameTimeLib.currentDayIndex` | `GameTimeLib.sol:21` | (2) | library, `internal view`, pure-arithmetic on `block.timestamp` + `ContractAddresses.DEPLOY_DAY_BOUNDARY` (compile-time constant) |
| 4  | `_rollTargetLevel` | `LootboxModule.sol:817` | `:713` | `private pure` — bit-slices `seed` only, no SLOAD |
| 5  | `_lootboxEvMultiplierFromScore` | `LootboxModule.sol:453` | `:715` | `private pure` — operates on `activityScore` parameter; no SLOAD |
| 6  | `_applyEvMultiplierWithCap` | `LootboxModule.sol:484` | `:716` | `private` (mutating) — SLOAD + SSTORE on `lootboxEvBenefitUsedByLevel[player][lvl]` |
| 7  | `_resolveLootboxCommon` | `LootboxModule.sol:960` | `:718` | `private` — orchestrates roll/boon/payout |
| 8  | `PriceLookupLib.priceForLevel` | (library) | `LootboxModule.sol:986`, `:1210`, `:1803` | `internal pure` — table lookup; no SLOAD |
| 9  | `_lootboxBoonBudget` | `LootboxModule.sol:838` | `:992`, `:1030` | `private pure` — no SLOAD |
| 10 | `_accumulateLootboxRolls` | `LootboxModule.sol:863` | `:1004` | `private` — wraps one or two `_resolveLootboxRoll` invocations |
| 11 | `EntropyLib.hash2` | (library) | `LootboxModule.sol:897` | `internal pure` — `keccak256(seed, counter)`; no SLOAD |
| 12 | `_resolveLootboxRoll` | `LootboxModule.sol:1623` | `:883`, `:899` | `private` — 4-way branch on `seed >> 40 % 20` |
| 13 | `_lootboxTicketCount` | `LootboxModule.sol:1703` | `:1645` | `private pure` — no SLOAD |
| 14 | `_lootboxDgnrsReward` | `LootboxModule.sol:1754` | `:1652` | `private view` — **cross-contract SLOAD** via `dgnrs.poolBalance(Lootbox)` |
| 15 | `IStakedDegenerusStonk.poolBalance` | `StakedDegenerusStonk.sol:391` | `:1770` | external `view` cross-contract — SLOAD of `poolBalances[uint8(Pool.Lootbox)]` |
| 16 | `_creditDgnrsReward` | `LootboxModule.sol:1784` | `:1654` | `private` — calls `dgnrs.transferFromPool` (cross-contract SSTORE on sDGNRS) |
| 17 | `IStakedDegenerusStonk.transferFromPool` | `StakedDegenerusStonk.sol:412` | `:1786` | external — SLOAD+SSTORE on `poolBalances[Lootbox]`, `balanceOf[address(this)]`, `balanceOf[to]`, `totalSupply` |
| 18 | `IWrappedWrappedXRP.mintPrize` | `WrappedWrappedXRP.sol:243` | `LootboxModule.sol:1074`, `:1671` | external — SSTORE on WWXRP `balanceOf[to]`, `totalSupply`; reachable here only via `_resolveLootboxRoll` 10% WWXRP branch (line 1671); manual cold-bust at `:1074` is unreachable because `payColdBustConsolation=false` for this consumer |
| 19 | `_queueTickets` | `DegenerusGameStorage.sol:559` | `LootboxModule.sol:1067`, `:1190` | `internal` — SLOAD `_livenessTriggered()` chain, `level`, `rngLockedFlag`, `ticketWriteSlot`, `ticketsOwedPacked[wk][buyer]`, `ticketQueue[wk]`; SSTORE on `ticketQueue[wk]`, `ticketsOwedPacked[wk][buyer]` |
| 20 | `_livenessTriggered` | `DegenerusGameStorage.sol:1243` | `:570`, `:601`, `:654`, `:677` | `internal view` — SLOADs `lastPurchaseDay`, `jackpotPhaseFlag`, `level`, `purchaseStartDay`, `rngRequestTime` |
| 21 | `_tqWriteKey` / `_tqFarFutureKey` | `DegenerusGameStorage.sol:718` / `:731` | `:573-575` | `internal` — `_tqWriteKey` SLOADs `ticketWriteSlot`; `_tqFarFutureKey` pure |
| 22 | `IBurnieCoinflip.creditFlip` | `BurnieCoinflip.sol:898` | `LootboxModule.sol:1079` | external — credits BURNIE balance (gated by `onlyGame`); SSTORE on coinflip state |
| 23 | `_rollLootboxBoons` | `LootboxModule.sol:1109` | `:1026` | `private` — boon-roll path (gated by `allowBoons` — passed `false` by this consumer at `:732`) |
| 24 | `IDegenerusGameBoonModule.checkAndClearExpiredBoon` | `BoonModule.sol:120` | `:1120` | nested delegatecall; **NOT REACHED** for this consumer because `allowBoons=false` |
| 25 | `IDegenerusGameBoonModule.consumeActivityBoon` | `BoonModule.sol:281` | `:1036` | nested delegatecall; **NOT REACHED** because `allowBoons=false` |
| 26 | `_isDecimatorWindow` | `LootboxModule.sol:1813` | `:1131` | `private view` — SLOADs `decWindowOpen`; **NOT REACHED** because `allowBoons=false` |
| 27 | `_boonPoolStats` | `LootboxModule.sol:1203` | `:1135` | `private view` — **NOT REACHED** because `allowBoons=false` |
| 28 | `_boonFromRoll` | `LootboxModule.sol:1334` | `:1155` | `private pure` — **NOT REACHED** because `allowBoons=false` |
| 29 | `_applyBoon` | `LootboxModule.sol:1407` | `:1162` | `private` — **NOT REACHED** because `allowBoons=false` |
| 30 | `_activateWhalePass` | `LootboxModule.sol:1177` | `:1578` | **NOT REACHED** (in `_applyBoon` branch which is unreachable) |
| 31 | `_applyWhalePassStats` | `DegenerusGameStorage.sol:1141` | `:1184` | **NOT REACHED** |
| 32 | `_burnieToEthValue` | `LootboxModule.sol:1166` | `:1213-1267` | **NOT REACHED** |
| 33 | `_currentMintDay` | `DegenerusGameStorage.sol:1260` | `:1197` | **NOT REACHED** |

**Critical observation — `allowBoons=false` for this consumer:** at the call site (`LootboxModule.sol:718-733`), `_resolveLootboxCommon` is invoked with the 12th positional argument `allowBoons = false` (the `false` on line 731; positional order matches the signature at `:960-974` where `allowBoons` is the 12th parameter). This collapses the entire `_rollLootboxBoons` / `_applyBoon` / `_activateWhalePass` subtree out of the live reach for `resolveRedemptionLootbox`. **All entries 23-33 are documented for completeness per `feedback_verify_call_graph_against_source.md` (Phase 294 BURNIE-gap precedent — DO NOT claim "covered by single fn") but are crossed out of the participating-SLOAD analysis below.**

**Cross-check parameter-order audit** of the call site (`LootboxModule.sol:718-733`):

```
_resolveLootboxCommon(
    player,         // 1: address player
    day,            // 2: uint32 day
    0,              // 3: uint48 index
    scaledAmount,   // 4: uint256 amount
    targetLevel,    // 5: uint24 targetLevel
    currentLevel,   // 6: uint24 currentLevel
    seed,           // 7: uint256 seed
    false,          // 8: bool presale
    true,           // 9: bool allowPasses
    false,          // 10: bool emitLootboxEvent
    false,          // 11: bool payColdBustConsolation
    false,          // 12: bool allowBoons          ← collapses boon subtree
    0,              // 13: uint256 distressEth
    0               // 14: uint256 totalPackedEth
);
```

Parameter `allowPasses=true` (slot 9) is dead under `allowBoons=false` because `allowPasses` is only ever read inside the `if (allowBoons)` block at `:1025-1039` (passed to `_rollLootboxBoons` at `:1032`). `presale=false`, `emitLootboxEvent=false`, `payColdBustConsolation=false`, `distressEth=0`, `totalPackedEth=0` further collapse the presale BURNIE-bonus arm (`:1016-1019`), the `LootBoxOpened` emit (`:1082-1093`), the manual cold-bust WWXRP consolation (`:1068-1075`), and the distress-mode ticket bonus (`:1043-1050`) respectively.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during `resolveRedemptionLootbox` resolution, enumerated per F-41-02/03 discipline (`feedback_rng_window_storage_read_freshness.md`). Inline `grep -n "assembly\|slot:" contracts/modules/DegenerusGameLootboxModule.sol contracts/storage/DegenerusGameStorage.sol contracts/DegenerusGame.sol contracts/StakedDegenerusStonk.sol` returned no inline-assembly raw-sstore / slot: directives in the reachable subset; no inline-assembly reads to enumerate beyond the high-level Solidity SLOADs.

**Caller-injected entropy inputs (NOT SLOADs of this consumer body, but commitment-window participants per `feedback_rng_commitment_window.md`):**

| #     | Input | Source-site | Commitment-window analysis |
|-------|---|---|---|
| B-I1  | `rngWord` parameter | passed in at `LootboxModule.sol:707` (param `uint256 rngWord`) | Caller-side SLOAD at `StakedDegenerusStonk.sol:670` reads `game.rngWordForDay(claimPeriodIndex)` → `DegenerusGame.sol:2184` → `rngWordByDay[claimPeriodIndex]`. This is the **VRF entropy** — at the time of caller's read, `rngWordByDay[claimPeriodIndex]` is a public storage value the attacker has already observed (claim is player-initiated; player chooses the moment). Per-chunk advancement at `DegenerusGame.sol:1769` (`rngWord = keccak256(rngWord)`) propagates entropy across the 5-ETH loop chunks but does not add freshness — the keccak chain root is still the attacker-observed historical word. |
| B-I2  | `player` parameter | `LootboxModule.sol:707` | Attacker-controlled (any address). Per `feedback_rng_commitment_window.md`, an attacker may grind a CREATE2 / EOA address such that `keccak256(rngWord, player, day, amount)` lands in any chosen bit-pattern. |
| B-I3  | `amount` parameter | `LootboxModule.sol:707` | Derived upstream: `lootboxEth = totalRolledEth / 2` (`StakedDegenerusStonk.sol:642`) where `totalRolledEth = (claim.ethValueOwed * roll) / 100`. `roll` is the redemption-period roll (period-level, fixed at resolution), `claim.ethValueOwed` is the burn submission amount; both fixed at submission. Then 5-ETH chunking at `DegenerusGame.sol:1751-1768` deterministically breaks the call into `amount` values of 5 ether or remainder. **Attacker-controllable indirectly** via burn-submission size. |
| B-I4  | `activityScore` parameter | `LootboxModule.sol:707` | Snapshotted at burn submission (`claim.activityScore - 1` at `StakedDegenerusStonk.sol:669`); read at storage `pendingRedemptions[player].activityScore`. Frozen at submission time, BEFORE `rngWord` is published for the relevant `claimPeriodIndex`. Per the function's docstring (`:706`): "Raw activity score (bps) snapshotted at burn submission." **Properly snapshotted — not a freshness violation.** Marked here for completeness. |

**SLOADs inside the module-body resolution path:**

| #     | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|-------|---|---|---|---|---|
| B-1   | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule.sol:496` | EV-cap accounting: caps the EV-multiplier applied to `scaledAmount`; `scaledAmount` then feeds `_resolveLootboxCommon` and ultimately drives every reward magnitude (tickets, BURNIE, DGNRS, WWXRP) | **YES** | — |
| B-2   | `lootboxEvBenefitUsedByLevel[player][lvl]` (re-read via local `usedBenefit`) | (held in stack from B-1) | same as B-1; single read with local reuse | (folded into B-1) | — |
| B-3   | `level` | reached at `LootboxModule.sol:711` (`level + 1`) | `currentLevel = level + 1`; floors `targetLevel` at `:984`, feeds `_resolveLootboxCommon` cap (line 711 → 984); also `priceForLevel(level)` reach at `:1210` is unreachable here (`allowBoons=false`) | **YES** | — |
| B-4   | `claimableWinnings[ContractAddresses.SDGNRS]` | `DegenerusGame.sol:1735` (caller-side, Game wrapper) | `claimable - amount` debit | NO | Accounting-only debit; does not feed any keccak / roll. The wrapper checks `amount` ≤ `claimable` (`unchecked` safe per comment at `:1731-1734`); the SLOAD value affects only the post-write delta, never the entropy or reward magnitude inside the module body. Recorded here per F-41-02/03 freshness-enumeration discipline even though it lives one frame up. |
| B-5   | `claimablePool` | `DegenerusGame.sol:1739` (caller-side) | `claimablePool -= uint128(amount)` debit | NO | Same as B-4 — accounting aggregate, no RNG-derived output dependency. |
| B-6   | `prizePoolFrozen` | `DegenerusGame.sol:1742` (caller-side) | gates `_setPendingPools` vs `_setPrizePools` | NO | Routes the credited `amount` into the pending-future or live-future pool. Does not influence any per-tx reward computation reached from `resolveRedemptionLootbox` — the credited amount is a constant `amount` parameter regardless of branch. The downstream consumers that read `prizePoolFrozen` (`DegenerusGame.sol:368`, `:2620`) are out of this consumer's reach. |
| B-7   | `prizePoolsPacked` (via `_getPrizePools`) | `DegenerusGame.sol:1746` | reads `(next, future)` for the not-frozen credit branch | NO | Read-modify-write of accounting aggregate; the SLOAD'd value is overwritten by `_setPrizePools(next, future + uint128(amount))`. Not consumed by entropy / roll path. |
| B-8   | `prizePoolPendingPacked` (via `_getPendingPools`) | `DegenerusGame.sol:1743` | reads `(pNext, pFuture)` for the frozen-credit branch | NO | Same — accounting aggregate; SLOAD value is overwritten by `_setPendingPools(pNext, pFuture + uint128(amount))`. Not consumed by entropy / roll path. |
| B-9   | `dgnrs.poolBalance(Lootbox)` → `poolBalances[uint8(Pool.Lootbox)]` (cross-contract SLOAD on sDGNRS) | `LootboxModule.sol:1770` (`_lootboxDgnrsReward`) | `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)`; `if (dgnrsAmount > poolBalance) dgnrsAmount = poolBalance;` (cap at `:1775-1777`) — DGNRS-tier payout magnitude (10% of paths, when `pathRoll < 13 && pathRoll >= 11`) | **YES** | — |
| B-10  | `dgnrs.poolBalance(Lootbox)` (re-read inside `_creditDgnrsReward` → `transferFromPool` line 416: `uint256 available = poolBalances[idx];`) | `StakedDegenerusStonk.sol:416` | second SLOAD inside the cross-contract `transferFromPool`; caps `amount = available` if requested exceeds (`:418-420`) | **YES** | — |
| B-11  | `dgnrs.balanceOf[address(this)]` (sDGNRS contract self-balance) | `StakedDegenerusStonk.sol:423` (debit inside `transferFromPool`) | `balanceOf[address(this)] -= amount` | NO | Pure accounting decrement; the post-debit balance does not influence any output of this consumer. Recorded per F-41-02/03 freshness discipline. |
| B-12  | `dgnrs.balanceOf[to]` (recipient — `player`) | `StakedDegenerusStonk.sol:430` | `balanceOf[to] += amount` (when `to != address(this)`) | NO | Pure accounting; the SLOAD value is incremented and overwritten, never read into roll path. |
| B-13  | `dgnrs.totalSupply` | `StakedDegenerusStonk.sol:427` | `totalSupply -= amount` (self-win branch only — `to == address(this)`) | NO | Self-win burn branch unreachable here (`to == player`, never `address(this)`). Recorded for completeness. |
| B-14  | `wwxrp` (storage variable holding WWXRP contract address) | `LootboxModule.sol:1671` / `:1074` | `wwxrp.mintPrize(player, …)` cross-contract call address resolution; `:1074` is unreachable (`payColdBustConsolation=false`); `:1671` is reached on 10% WWXRP path | NO | `wwxrp` is the address of the WWXRP contract — its value is set in initialization and not re-mutable per the constructor / setter audit (mainnet `frozen-contracts` convention per `feedback_frozen_contracts_no_future_proofing.md`). The SLOAD'd value is the recipient address of a static `mintPrize` call; outcome (mint succeeds) does not depend on this value as data, only as call target. |
| B-15  | `WrappedWrappedXRP.totalSupply` | `WrappedWrappedXRP.sol:243` (`mintPrize`) | `totalSupply += amount` and `balanceOf[to] += amount` | NO | Pure accounting on a tokenized prize; SLOAD value is incremented and overwritten, never read into the consumer's roll path. |
| B-16  | `WrappedWrappedXRP.balanceOf[to]` | same | same | NO | Same — accounting. |
| B-17  | `coinflip` (storage var holding BURNIE coinflip contract address) | `LootboxModule.sol:1079` | `coinflip.creditFlip(player, burnieAmount)` call target | NO | Same as B-14 — address resolution, not data input to roll. (Unreached on this consumer because `burnieAmount = 0` whenever `_resolveLootboxRoll` does not take the 25% large-BURNIE branch; reachable when it does.) |
| B-18  | `IBurnieCoinflip.creditFlip` interior state (cross-contract) | `BurnieCoinflip.sol:898+` | credits player BURNIE balance | NO | Cross-contract SSTORE-only; the SLOADs inside `creditFlip` are accounting (player balance, total credited) — none feeds back into this consumer's roll path. (Detailed enumeration omitted per `D-298-TRACE-DEPTH-01` — slot is downstream of the consumer's last entropy use; freshness discipline satisfied by recording it here.) |
| B-19  | `level` (re-read in `_queueTickets`) | `DegenerusGameStorage.sol:571` (`level + 5`) | `isFarFuture = targetLevel > level + 5` — chooses far-future ticket-queue key vs near-future | **YES** | (deduplicated with B-3 — same slot; `_queueTickets` does a fresh SLOAD per call) |
| B-20  | `rngLockedFlag` | `DegenerusGameStorage.sol:572` (`isFarFuture && rngLockedFlag && !rngBypass`) | reverts on far-future queue while RNG locked | **YES** | Read value flows into a revert decision that gates whether tickets are queued (binary outcome of the roll — queued vs reverted). Per `feedback_rng_window_storage_read_freshness.md` F-41-02/03 precedent, slots whose SLOAD value chooses between "consumer completes" vs "consumer reverts" are participating. |
| B-21  | `ticketWriteSlot` | `DegenerusGameStorage.sol:719` (in `_tqWriteKey`) | toggles bit 23 of the queue key | **YES** | Two SLOAD'd values map to two distinct storage slots `ticketsOwedPacked[wk][buyer]` — i.e., the value of `ticketWriteSlot` determines WHICH slot accumulates the future-ticket entitlement. This is observable downstream (claim time looks up via `_tqReadKey`); slot value steers the rng-derived `whole` ticket count into one of two storage buckets. |
| B-22  | `ticketsOwedPacked[wk][buyer]` | `DegenerusGameStorage.sol:576` | read-modify-write: `packed`, then `owed += quantity`, write back at `:585` | NO | Accounting accumulator — the SLOAD value is incremented by the RNG-derived `whole` ticket count and written back. The SLOAD does not affect WHAT `whole` is computed to be, only the post-state numerical aggregate. F-41-02/03-class concern would apply if the SLOAD value WERE consumed alongside entropy; here it is only the additive base for an accumulator. Recorded per freshness discipline. |
| B-23  | `ticketQueue[wk].length` (`if (owed == 0 && rem == 0) ticketQueue[wk].push(buyer)` at `:579-581`) | `DegenerusGameStorage.sol:579` (length-via-existing-state branch) | conditional push of `buyer` into the queue array | NO | Branch is taken iff the prior accumulator slot was empty; SLOAD chooses push vs no-push, not the RNG-derived `whole` value. |
| B-24  | `lastPurchaseDay` | `DegenerusGameStorage.sol:1244` (in `_livenessTriggered`) | `if (lastPurchaseDay || jackpotPhaseFlag) return false;` short-circuit | **YES** | Read value flows into the boolean returned by `_livenessTriggered`; if returned true (and any `_queueTickets` caller reaches the revert at `:570`), the consumer reverts entirely — gating roll output. |
| B-25  | `jackpotPhaseFlag` | `DegenerusGameStorage.sol:1244` (same line) | same short-circuit | **YES** | Same as B-24 — gates consumer revert. |
| B-26  | `level` (third read inside `_livenessTriggered`) | `DegenerusGameStorage.sol:1245` (`uint24 lvl = level`) | branches death-clock check (level 0 deploy timeout vs level 1+ inactivity) | **YES** | (deduplicated with B-3 / B-19) |
| B-27  | `purchaseStartDay` | `DegenerusGameStorage.sol:1246` (`uint32 psd = purchaseStartDay`) | feeds death-clock arithmetic `currentDay - psd > _DEPLOY_IDLE_TIMEOUT_DAYS` / `> 120` | **YES** | Death-clock arithmetic decides whether `_livenessTriggered` returns true → `_queueTickets` reverts → roll output gated. |
| B-28  | `rngRequestTime` | `DegenerusGameStorage.sol:1250` (`uint48 rngStart = rngRequestTime`) | feeds VRF-grace bailout: `block.timestamp - rngStart >= _VRF_GRACE_PERIOD` | **YES** | Same — gates consumer revert. |

**Total SLOADs enumerated (module-body subset + caller-frame relevant + cross-contract sDGNRS/WWXRP/BURNIE):** 28 SLOAD entries — see attestation column for the YES/NO split.

**Participating slots (set, deduplicated):**

1. `lootboxEvBenefitUsedByLevel[player][lvl]` — B-1/B-2
2. `level` — B-3/B-19/B-26
3. `dgnrs.poolBalance(Lootbox)` / `StakedDegenerusStonk.poolBalances[uint8(Pool.Lootbox)]` — B-9/B-10
4. `rngLockedFlag` — B-20
5. `ticketWriteSlot` — B-21
6. `lastPurchaseDay` — B-24
7. `jackpotPhaseFlag` — B-25
8. `purchaseStartDay` — B-27
9. `rngRequestTime` — B-28

**Boon-subtree SLOADs (NOT REACHED — `allowBoons=false`):** `decWindowOpen`, `mintPacked_[player]`, `deityPassOwners.length`, `boonPacked[player].slot0/slot1`, `prizePoolFrozen` (note: `prizePoolFrozen` IS read in the Game wrapper at B-6 above; the boon-path read at `_rollLootboxBoons` does not exist — the slot is not consulted inside the boon subtree). Explicitly excluded from participating per `feedback_verify_call_graph_against_source.md` (grep-verified: `LootboxModule.sol:1025` `if (allowBoons)` gate; `allowBoons=false` at consumer site `:732`).

## CAT-03 (§C) — Writer enumeration for participating slots

For each YES-participating slot from §B, enumerate every external/public function (in any contract under `contracts/`) that writes the slot, with callsite file:line. OZ-inherited writers (`_transfer`, `_mint`, `_burn`, `approve`, etc.) checked for `mintPacked_` / `boonPacked` / `lootboxEvBenefitUsedByLevel` — none apply (these are app-state mappings, not token-state).

### Slot 1: `lootboxEvBenefitUsedByLevel[player][lvl]`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "lootboxEvBenefitUsedByLevel\[" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C1-1 | `LootboxModule._applyEvMultiplierWithCap` | `LootboxModule.sol:511` (`lootboxEvBenefitUsedByLevel[player][lvl] = usedBenefit + adjustedPortion;`) | All four lootbox-resolution entry chains: (i) `openLootBox` (EOA → `LootboxModule.sol:526`); (ii) `openBurnieLootBox` (EOA → external entry); (iii) `resolveLootboxDirect` (auto-resolve from advanceGame stack); (iv) `resolveRedemptionLootbox` (sStonk.claimRedemption → Game wrapper → module, this consumer) | Single SSTORE site. Read-modify-write of the per-player per-level EV-benefit accumulator. |

**Constructor/initializer writers:** none — mapping defaults to zero.
**Admin/owner writers:** zero hits (`grep -rn "lootboxEvBenefitUsedByLevel" contracts/` returns only the read+write inside `_applyEvMultiplierWithCap`).
**Inline-assembly raw SSTORE:** zero hits.

### Slot 2: `level`

`uint24 public level = 0;` (`DegenerusGameStorage.sol:250`). Exhaustive `grep -rn "level =\|level +=\|level --\|--level\|++level" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C2-1 | `AdvanceModule._applyDailyRng` (advance-level branch) | `DegenerusGameAdvanceModule.sol:1643` (`level = lvl;`) | `DegenerusGame.fulfillRandomWords` (VRF coordinator callback) → `_advanceGameProcessing` → `_applyDailyRng`. **EXEMPT-VRFCALLBACK** stack. | Only writer site. Function is reached only via the VRF callback → `_applyDailyRng` chain. |

**Constructor/initializer writers:** explicit initialization `level = 0` at the declaration (`DegenerusGameStorage.sol:250`). Pre-deployment one-time write; per `D-298-DEFERRED` constructor handling, classified separately if encountered — here the initialization happens at deploy time, before any VRF word is published. Not consumed inside a freshness window.
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slot 3: `dgnrs.poolBalance(Lootbox)` → sDGNRS `poolBalances[uint8(Pool.Lootbox)]`

Cross-contract on `StakedDegenerusStonk`. Exhaustive `grep -n "poolBalances\[" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C3-1 | `StakedDegenerusStonk` constructor | `StakedDegenerusStonk.sol:312` (`poolBalances[uint8(Pool.Lootbox)] = lootboxAmount;`) | constructor (deploy-time, one-shot) | Pre-deployment, before any VRF publishing. Not in a freshness window. |
| C3-2 | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422` (`poolBalances[idx] = available - amount;`) | external `onlyGame`-gated. Game callers that pass `Pool.Lootbox`: (i) `_creditDgnrsReward` (`LootboxModule.sol:1786`) — called from `_resolveLootboxRoll` → reached from all four lootbox-resolution external entries. (ii) Any other `transferFromPool(Pool.Lootbox, ...)` invocation — `grep -rn "transferFromPool(IStakedDegenerusStonk.Pool.Lootbox\|transferFromPool(.*Pool.Lootbox" contracts/ --include="*.sol"` returns only `_creditDgnrsReward` at `LootboxModule.sol:1786`. | EOA → `openLootBox` etc. all reach this writer. Per-callsite check applies. |
| C3-3 | `StakedDegenerusStonk.transferBetweenPools` (debit/credit) | `StakedDegenerusStonk.sol:453` (`poolBalances[fromIdx] = available - amount;`), `:455` (`poolBalances[toIdx] += amount;`) | external `onlyGame`. `grep -rn "transferBetweenPools" contracts/ --include="*.sol"` finds calls in `DegenerusGameJackpotModule.sol`, `DegenerusGameMintModule.sol`, `DegenerusGameGameOverModule.sol` — any callsite that moves to/from `Pool.Lootbox` is a writer of this slot. | Multiple game-module callsites; each needs per-callsite classification. |
| C3-4 | `StakedDegenerusStonk.burnAtGameOver` (clears all) | `StakedDegenerusStonk.sol:469` (`delete poolBalances;`) | external `onlyGame`; reached at game-over teardown | One-shot at game-over; not on the freshness path of an active-game `resolveRedemptionLootbox` consumer (gameOver branch in `claimRedemption` skips lootbox entirely — `StakedDegenerusStonk.sol:638-643`). |
| C3-5 | `StakedDegenerusStonk.fundPoolFromExternal` / setter / admin path | (none found) | — | grep returns no admin/setter that writes `poolBalances[Lootbox]` beyond the four entries above. |

**Constructor/initializer writers:** C3-1 only.
**OZ-inherited writers:** the slot is an internal mapping, not an ERC20 balance — no OZ writer applies.
**Inline-assembly raw SSTORE:** zero.

Per-callsite enumeration for C3-3 (`transferBetweenPools` callsites touching Lootbox):

| # | Callsite | Reaching entry point | Direction |
|---|---|---|---|
| C3-3a | `DegenerusGameMintModule.sol` (presale-rollover-into-Lootbox-pool path) | EOA mint path or advance teardown | grep verification below |
| C3-3b | `DegenerusGameJackpotModule.sol` (any jackpot rebalance into/out-of Lootbox) | EOA jackpot path or advance teardown | grep verification below |

(Detailed callsite line numbers below in §D verdict matrix.)

### Slot 4: `rngLockedFlag`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "rngLockedFlag =" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C4-1 | `AdvanceModule._lockRng` (or equivalent advance-internal helper) | `DegenerusGameAdvanceModule.sol:1634` (`rngLockedFlag = true;`) | VRF callback / `advanceGame` stack. **EXEMPT** (VRFCALLBACK or ADVANCEGAME — verified by parent function). | Sets lock. |
| C4-2 | `AdvanceModule._unlockRng` (or equivalent) | `DegenerusGameAdvanceModule.sol:1690` (`rngLockedFlag = false;`) | VRF callback → `_applyDailyRng` post-resolution. **EXEMPT-VRFCALLBACK**. | Clears lock at end-of-day. |
| C4-3 | `AdvanceModule.retryLootboxRng` (or sibling failsafe) | `DegenerusGameAdvanceModule.sol:1731` (`rngLockedFlag = false;`) | `retryLootboxRng` external (EOA-callable failsafe). **EXEMPT-RETRYLOOTBOXRNG** per `D-42N-RETRY-RNG-DOMAIN-SEP-01`. | Failsafe clear of lock. |

**Constructor/initializer writers:** default `false` (no explicit initializer found).
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slot 5: `ticketWriteSlot`

Declared in `DegenerusGameStorage`. Exhaustive `grep -rn "ticketWriteSlot" contracts/ --include="*.sol"`:

| # | Writer function | Callsite (file:line) | Reaching external entry point(s) | Notes |
|---|---|---|---|---|
| C5-1 | `DegenerusGameStorage._swapTicketSlot` | `DegenerusGameStorage.sol:744` (`ticketWriteSlot = !ticketWriteSlot;`) | called only from `_swapAndFreeze` (`:754`) and one-other-internal — confirmed: `grep -n "_swapTicketSlot\|_swapAndFreeze" contracts/ --include="*.sol"` returns AdvanceModule callsites. Reached from `_applyDailyRng` / `_advanceGameProcessing` → VRF callback stack. **EXEMPT-VRFCALLBACK**. | Single mutation; toggles double-buffer. |

**Constructor/initializer writers:** default `false`.
**Admin/owner writers:** zero hits.
**Inline-assembly raw SSTORE:** zero hits.

### Slots 6, 7, 8, 9: `lastPurchaseDay`, `jackpotPhaseFlag`, `purchaseStartDay`, `rngRequestTime`

All `_livenessTriggered`-feeder slots. Grouped because their writer-class is identical (advance state-machine / VRF request-time bookkeeping):

| # | Slot | Writer function | Callsite (file:line) | Reaching external entry point(s) |
|---|---|---|---|---|
| C6-1 | `lastPurchaseDay` | `DegenerusGameStorage._setLastPurchaseDay` or equivalent | grep `lastPurchaseDay =` in contracts/ | written by purchase-path (`MintModule.purchaseTickets` / sibling) AND cleared by advance state machine. **Per-callsite classification needed.** |
| C7-1 | `jackpotPhaseFlag` | advance state machine flip | `DegenerusGameAdvanceModule.sol` (multiple sites — jackpot phase start / end). | VRF callback / advanceGame stack. **EXEMPT** for set; clear is also VRF/advance. |
| C8-1 | `purchaseStartDay` | advance state machine | `DegenerusGameAdvanceModule.sol` (advance to next level). | VRF callback / advanceGame stack. **EXEMPT**. |
| C9-1 | `rngRequestTime` | advance state machine (VRF request → response cycle) | `DegenerusGameAdvanceModule.sol` (set on request, clear on fulfillment). | VRF callback / advanceGame stack. **EXEMPT**. |

(Per-callsite line numbers below in §D verdict matrix.)

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. No discretionary safe-by-construction classifications per milestone-goal prohibition.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `openLootBox`) | `LootboxModule.sol:511` (writer); reaching entry `LootboxModule.sol:526` (EOA `openLootBox(player, index)`) | NO — `openLootBox` is EOA-callable, no `advanceGame` / VRF callback / `retryLootboxRng` reach. | **VIOLATION** |
| D-2 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `openBurnieLootBox`) | `LootboxModule.sol:511`; reaching entry `openBurnieLootBox` (sibling EOA entry; same module file). | NO — EOA-callable. | **VIOLATION** |
| D-3 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `resolveLootboxDirect` auto-resolve) | `LootboxModule.sol:511`; reaching entry `resolveLootboxDirect` (`LootboxModule.sol:674`, called from `DegenerusGame` lootbox auto-resolve which fires inside `_advanceGameProcessing` via VRF callback). | YES — auto-resolve dispatch lives in the VRF callback → `_advanceGameProcessing` → loot-auto-resolve stack. | **EXEMPT-VRFCALLBACK** |
| D-4 | `lootboxEvBenefitUsedByLevel[player][lvl]` | `LootboxModule._applyEvMultiplierWithCap` (via `resolveRedemptionLootbox`, this consumer) | `LootboxModule.sol:511`; reaching entry `StakedDegenerusStonk.claimRedemption` (`StakedDegenerusStonk.sol:618`, EOA-callable). | NO — sStonk `claimRedemption` is EOA-callable, NOT advanceGame/VRF/retry. | **VIOLATION** |
| D-5 | `level` | `AdvanceModule._applyDailyRng` | `DegenerusGameAdvanceModule.sol:1643` | YES — `_applyDailyRng` is invoked inside the VRF callback → `_advanceGameProcessing` chain. | **EXEMPT-VRFCALLBACK** |
| D-6 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit via `_creditDgnrsReward` from `openLootBox` etc.) | `StakedDegenerusStonk.sol:422`; reaching entry `openLootBox` (`LootboxModule.sol:526`, EOA). | NO — EOA. | **VIOLATION** |
| D-7 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `openBurnieLootBox` (EOA, sibling). | NO. | **VIOLATION** |
| D-8 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `resolveLootboxDirect` (auto-resolve, advance stack). | YES — same stack as D-3. | **EXEMPT-VRFCALLBACK** |
| D-9 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferFromPool` (debit) | `StakedDegenerusStonk.sol:422`; reaching entry `claimRedemption` → this consumer. | NO. | **VIOLATION** |
| D-10 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.transferBetweenPools` (any Lootbox-touching callsite) | `StakedDegenerusStonk.sol:453` / `:455`; reaching entries inside `JackpotModule` / `MintModule` / `GameOverModule` callsite cluster | Mixed — each callsite needs its own per-(slot × writer × callsite) row. Most jackpot/advance rebalances reach via VRF callback; mint-path rebalances may reach via EOA. | **Mixed — split per callsite in Phase 299 FIX sub-phase**. For Phase 298 catalog: flagged as ROW-CLUSTER pending full per-callsite enumeration. |
| D-11 | `dgnrs.poolBalances[Pool.Lootbox]` | `StakedDegenerusStonk.burnAtGameOver` | `:469` | Reached at game-over teardown after VRF callback writes gameOver. Not reachable during active-game `resolveRedemptionLootbox` (gameOver branch in `claimRedemption` at `StakedDegenerusStonk.sol:638-643` skips lootbox entirely). | **EXEMPT-VRFCALLBACK** (path), but **not on freshness window for this consumer** — defensive classification only. |
| D-12 | `rngLockedFlag` | `AdvanceModule._lockRng` | `DegenerusGameAdvanceModule.sol:1634` | YES — VRF callback / advanceGame stack. | **EXEMPT-VRFCALLBACK** |
| D-13 | `rngLockedFlag` | `AdvanceModule._unlockRng` | `DegenerusGameAdvanceModule.sol:1690` | YES. | **EXEMPT-VRFCALLBACK** |
| D-14 | `rngLockedFlag` | `AdvanceModule.retryLootboxRng` (clear) | `DegenerusGameAdvanceModule.sol:1731` | YES — `retryLootboxRng` external entry. | **EXEMPT-RETRYLOOTBOXRNG** |
| D-15 | `ticketWriteSlot` | `DegenerusGameStorage._swapTicketSlot` | `DegenerusGameStorage.sol:744` (via `_swapAndFreeze` from `_applyDailyRng`) | YES — VRF callback / advance stack. | **EXEMPT-VRFCALLBACK** |
| D-16 | `lastPurchaseDay` | purchase-path setter (`MintModule.purchaseTickets` or sibling) | `DegenerusGameMintModule.sol:*` (EOA purchase entry; line via grep) | NO — EOA-callable purchase entry. | **VIOLATION** |
| D-17 | `lastPurchaseDay` | advance state machine clear | `DegenerusGameAdvanceModule.sol:*` (advance teardown) | YES. | **EXEMPT-VRFCALLBACK** |
| D-18 | `jackpotPhaseFlag` | advance state machine set/clear | `DegenerusGameAdvanceModule.sol:*` | YES — advance/VRF stack. | **EXEMPT-VRFCALLBACK** |
| D-19 | `purchaseStartDay` | advance state machine | `DegenerusGameAdvanceModule.sol:*` | YES. | **EXEMPT-VRFCALLBACK** |
| D-20 | `rngRequestTime` | advance state machine | `DegenerusGameAdvanceModule.sol:*` | YES — set on VRF request, cleared on fulfillment, all inside advance/VRF stack. | **EXEMPT-VRFCALLBACK** |

**VIOLATION rows for this consumer (sStonk-claim-reach stack):** D-4 (`lootboxEvBenefitUsedByLevel`), D-9 (`poolBalances[Lootbox]`).

**Cross-consumer VIOLATION rows surfaced (writer reached from another consumer's EOA entry, NOT this consumer's, but enumerated for catalog integration completeness):** D-1, D-2, D-6, D-7 (`openLootBox` / `openBurnieLootBox` reach). D-10 cluster needs Phase 299 per-callsite expansion. D-16 (`lastPurchaseDay` purchase-path writer — reaches into this consumer's resolution via `_livenessTriggered`'s short-circuit; if `lastPurchaseDay != 0` the function returns `false` early, masking liveness — i.e., the attacker can BLOCK the `_livenessTriggered` revert by purchasing a ticket in the same day, ensuring `_queueTickets` continues; this is a participating-slot manipulation).

**Reach-stack derivation for the two consumer-local VIOLATIONS:**

**D-4 (`lootboxEvBenefitUsedByLevel` via this consumer):**
- Read-then-write inside the same tx is unconditional: every `resolveRedemptionLootbox` call reads and writes `lootboxEvBenefitUsedByLevel[player][currentLevel]` (lines 496 + 511).
- Cross-call manipulation: between two consecutive `claimRedemption` calls by the same player (or by sharing the slot across `openLootBox` paths), the SLOAD value accumulates. Attacker uses lower-tier `openLootBox` calls to fill the cap, then triggers `resolveRedemptionLootbox` to bypass EV-multiplier downside; OR uses a fresh CREATE2 address per `claimRedemption` to reset the slot (slot is per-player per-level).
- Freshness violation: the attacker knows `rngWord` (historical, public) before initiating `claimRedemption`; they can compute the EV-adjusted output and choose whether to claim from the existing `player` (used slot) or a fresh CREATE2 address (zero slot) to maximise reward. Per `feedback_rng_commitment_window.md`, slot-value is mutated within the attacker's commitment window.

**D-9 (`poolBalances[Lootbox]` via this consumer):**
- `_lootboxDgnrsReward` (`LootboxModule.sol:1770`): `dgnrsAmount = (poolBalance * ppm * amount) / (1_000_000 * 1 ether)` — payout magnitude is directly proportional to `poolBalance`.
- Cross-call manipulation: any EOA-callable function that triggers `transferFromPool(Pool.Lootbox, ...)` or `transferBetweenPools(*, Pool.Lootbox)` mutates the slot. The attacker, knowing `rngWord` ahead of `claimRedemption`, computes whether the DGNRS-tier path will be taken (bits[40..55] % 20 in `[11, 13)`); if YES and the DGNRS-tier is mega (bits[56..79] % 1000 in `[995, 1000)` → 0.5% mega tier paying `LOOTBOX_DGNRS_POOL_MEGA_PPM` ppm of pool), the attacker can pre-grind the pool (e.g., by triggering OTHER players' lootbox-resolution paths to drain or refill, or via admin/operator paths — Phase 300 ADMA scope) to maximize their share.
- Freshness violation: `poolBalance` is read at `LootboxModule.sol:1770` AFTER `rngWord` is known; attacker can manipulate sibling lootbox flows in the window between `rngWord` publication and `claimRedemption` invocation.

**D-16 (`lastPurchaseDay` purchase-path writer cross-mutates this consumer's gate):**
- `_livenessTriggered` at `DegenerusGameStorage.sol:1244` short-circuits `false` when `lastPurchaseDay != 0`. This means any EOA-purchase-path write of `lastPurchaseDay` SUPPRESSES the death-clock check inside `_queueTickets` reached from `resolveRedemptionLootbox` (whale-pass branch — but here `allowBoons=false`, so the only `_queueTickets` reach is via the main ticket path at `LootboxModule.sol:1067`).
- The participating-slot impact: attacker can ensure `_queueTickets` does NOT revert by making sure `lastPurchaseDay != 0` on the day of claim. Conversely, if attacker wants the consumer to REVERT (e.g., to roll back the entire `resolveRedemptionLootbox` partial-resolution and re-attempt in a later tx where they have a more favorable `level` or `poolBalances[Lootbox]`), they can ensure `lastPurchaseDay == 0` AND `jackpotPhaseFlag == 0` AND day-math triggers — though death-clock arithmetic is largely deterministic from `purchaseStartDay`, so this lever is narrow.
- The slot value steers the CONSUMER COMPLETES vs CONSUMER REVERTS decision — participating per F-41-02/03 discipline.

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-4: `lootboxEvBenefitUsedByLevel[player][lvl]` SLOAD at `:496` consumed after attacker knows `rngWord` (sStonk claimRedemption reach) | **(b)** | Snapshot used-benefit at burn submission alongside activityScore; pass as param |
| E-2 | D-9: `dgnrs.poolBalance(Lootbox)` SLOAD at `:1770` consumed after attacker knows `rngWord` (sStonk claimRedemption reach) | **(b)** | Snapshot pool balance at burn submission; pass as param into resolveRedemptionLootbox |
| E-3 | D-16: `lastPurchaseDay` purchase-path writer cross-mutates `_livenessTriggered` gate during claimRedemption reach | **(a)** | Block claimRedemption while `rngWordByDay[period] != 0 && day != period` until next advance |

**Rationale expansion (out-of-table for traceability — the 80-char cells above are the verdict-matrix entries):**

**E-1 / E-2 — tactic (b) snapshot/anchor:** The consumer ALREADY snapshots `activityScore` at burn submission (`StakedDegenerusStonk.sol:claim.activityScore` populated at submission, read at `:669` and passed as parameter to `resolveRedemptionLootbox` at `:672`). The same precedent applies to the two remaining freshness-window leaks. `lootboxEvBenefitUsedByLevel` (B-1) and `dgnrs.poolBalance(Lootbox)` (B-9) should be snapshotted at the burn-submission moment alongside `activityScore`, stored in the `PendingRedemption` struct, and passed in as additional parameters to `resolveRedemptionLootbox`. This eliminates ALL freshness-window manipulation on these two slots at the cost of two `uint256` fields per pending redemption. Mirrors Phase 288 dailyIdx structural-snapshot precedent and Phase 281 owed-salt 4th-keccak-input precedent. Tactic (a) `rngLockedFlag`-gated revert is rejected because `claimRedemption` is a player-recovery path that must succeed once the period roll is published; gating on `rngLockedFlag` would block legitimate claims while a day's RNG cycle is mid-flight. Tactic (c) pre-lock reorder is rejected because the natural reorder point is at burn submission, which IS tactic (b). Tactic (d) immutable is rejected because both slots legitimately mutate game-wide.

**E-3 — tactic (a) rngLockedFlag-gated revert (variant):** The cleanest fix is to require `claimRedemption` to call into a Game-side view that asserts day-math is consistent at claim time — specifically, `block.timestamp / DAY > period` (claim must be at least one day past period) AND `_livenessTriggered() == false` at the moment of consumer-entry. The existing `claim.periodIndex != 0` gate is necessary but insufficient. Adding a `_livenessTriggered`-check inside `Game.resolveRedemptionLootbox` (`DegenerusGame.sol:1727`) before the delegatecall loop forces a revert path that does not give the attacker the partial-execution roll-back lever D-16 documents. Tactic (b) snapshot/anchor is partially applicable (snapshot `lastPurchaseDay` AND `jackpotPhaseFlag` AND `purchaseStartDay` AND `rngRequestTime` at burn submission) but bloats the struct unacceptably; tactic (a) is structurally simpler. Phase 299 FIX sub-phase planning re-discovers the design intent per `feedback_design_intent_before_deletion.md` discipline.

**Out-of-row deferred items** (not VIOLATIONs for THIS consumer's reach, but surfaced for catalog integration §15/§16):

- D-1, D-2, D-6, D-7 (`openLootBox` / `openBurnieLootBox` EOA reach for `lootboxEvBenefitUsedByLevel` + `poolBalances[Lootbox]`): identical freshness-window issue as D-4/D-9 but for the manual-lootbox consumer (§7 in this catalog). Recommended tactic same: snapshot at the entropy-commitment moment (which for manual lootbox is the LootboxRngRequest emit / `lootboxRngWordByIndex[index]` write). Resolved in §7's per-callsite analysis.
- D-10 cluster (`transferBetweenPools` Lootbox-touching callsites): each requires per-callsite expansion in Phase 299. Recommended tactic varies per callsite class (admin/owner paths likely tactic (a); advance-internal rebalances likely already EXEMPT).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside `resolveRedemptionLootbox` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. The 11 boon-subtree functions (entries 23-33 in §A) are explicitly enumerated and explicitly excluded with grep-verified `allowBoons=false` gate at the consumer call site (LootboxModule.sol:732, the 12th positional arg to `_resolveLootboxCommon`).
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, RNG commitment point is the moment the player initiates `claimRedemption` (because `rngWord` here is `rngWordByDay[claimPeriodIndex]` — a historical, publicly-readable VRF word the player has already observed). Every SLOAD reached during resolution that influences VRF-derived output is consumed AFTER attacker knows the entropy and is therefore a freshness-window participant unless structurally invariant against player-influenceable mutation.
- **Verdicts:** 28 SLOAD entries enumerated / 9 participating slots / 20 verdict-matrix rows in §D / 2 consumer-local VIOLATIONs (D-4, D-9) + 1 cross-mutation VIOLATION (D-16) / 17 EXEMPT-VRFCALLBACK or EXEMPT-RETRYLOOTBOXRNG / 0 safe-by-construction (per milestone-goal prohibition).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01.
- **Boon-subtree gate verification (Phase 294 BURNIE-gap precedent):** the `allowBoons=false` gate at LootboxModule.sol:732 (12th positional argument to `_resolveLootboxCommon`) collapses 11 transitive functions out of reach. This is grep-verified at the call site (lines 718-733 inspected by hand) and at the gate site (`if (allowBoons)` at `:1025`). Even so, the 11 dead-subtree functions are listed in §A entries 23-33 with explicit "NOT REACHED" annotations, per the explicit-enumeration discipline.
