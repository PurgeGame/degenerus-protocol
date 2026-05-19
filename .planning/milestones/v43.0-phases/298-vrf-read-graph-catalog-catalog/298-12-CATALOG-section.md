# §12 — StakedDegenerusStonk.resolveRedemptionPeriod + rngWordForDay re-read (file:line 585 / 670)

**Consumer entry (advance-stack):** `contracts/StakedDegenerusStonk.sol:585`
**Signature:** `function resolveRedemptionPeriod(uint16 roll, uint32 flipDay) external` — access guard `msg.sender != ContractAddresses.GAME` revert (sStonk:586).
**Consumer entry (EOA-stack):** `contracts/StakedDegenerusStonk.sol:670` — `uint256 rngWord = game.rngWordForDay(claimPeriodIndex)` inside `claimRedemption()` (sStonk:618), which has NO access guard (any holder with `pendingRedemptions[msg.sender].periodIndex != 0` may call).
**Caller chain (advance side):** `AdvanceModule.advanceGame` (`AdvanceModule.sol:158`) → `rngGate` (`:1179`) writes `rngWordByDay[day]` via `_applyDailyRng` (`:1841`) → derives `redemptionRoll = uint16(((currentWord >> 8) % 151) + 25)` (`:1226-1228`) and `flipDay = day + 1` (`:1229`) → `sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay)` (`:1230`). Mirrored in `_gameOverEntropy` paths at `:1293` (fresh VRF word) and `:1323` (historical-fallback word). Three call-sites all originate from the SAME advance-stack root (`advanceGame()` → `rngGate` / `_handleGameOverPath` → `_gameOverEntropy`).
**Caller chain (claim side):** EOA calls `claimRedemption()` (sStonk:618). `claim.periodIndex` was committed during a previous `burn()` / `burnWrapped()` call at `_submitGamblingClaimFrom` (sStonk:752), itself gated by `!game.gameOver()` (sStonk:487), `!game.livenessTriggered()` (sStonk:491), and `!game.rngLocked()` (sStonk:492) — the `sStonk:492` line is the existing rngLockedFlag-gate convention site referenced in `feedback_rng_window_storage_read_freshness.md` discipline. The line-670 SLOAD is a **cross-call re-read** of the same `rngWordByDay[claimPeriodIndex]` slot the advance-stack used at line 1226-1227 to derive `roll`; per F-41-02/03 precedent (`feedback_rng_window_storage_read_freshness.md`), this is the distinct-class cross-call SLOAD pattern.

## CAT-01 (§A) — Traced function set

Two consumer entries are covered per the §12 entry-list (D-298-CONSUMER-LIST-01 entry 12): the advance-stack writer `resolveRedemptionPeriod` (sStonk:585) AND the EOA-stack re-read `rngWordForDay(claimPeriodIndex)` inside `claimRedemption` (sStonk:670). Both are part of the same gambling-burn resolution lifecycle. The trace walks every reachable function inside both entries' resolution code paths per D-298-TRACE-DEPTH-01, stopping only at external interfaces with no source available.

| # | Function | File:line | Reached from | Notes |
|---|---|---|---|---|
| 1 | `resolveRedemptionPeriod` | `StakedDegenerusStonk.sol:585` | advance-stack entry (callsites `AdvanceModule.sol:1230 / :1293 / :1323`) | consumer root — writes `redemptionPeriods[redemptionPeriodIndex]` |
| 2 | `claimRedemption` | `StakedDegenerusStonk.sol:618` | EOA entry | re-read consumer root — line 670 re-loads `rngWordByDay[claimPeriodIndex]` |
| 3 | `IDegenerusGamePlayer.gameOver` (view) | (game-side, called at `:635`) | `claimRedemption:635` | reads `gameOver` flag in `DegenerusGameStorage.sol:290` (`bool public gameOver`) |
| 4 | `IBurnieCoinflipPlayer.getCoinflipDayResult` (view) | `BurnieCoinflip.sol:370` | `claimRedemption:649` | reads `coinflipDayResult[flipDay]` struct (`BurnieCoinflip.sol:162`) |
| 5 | `IDegenerusGamePlayer.rngWordForDay` (view) | `DegenerusGame.sol:2183` | `claimRedemption:670` | reads `rngWordByDay[claimPeriodIndex]` (`DegenerusGameStorage.sol:435`) |
| 6 | `IDegenerusGameModules.resolveRedemptionLootbox` | `DegenerusGame.sol:1721` → `LootboxModule.resolveRedemptionLootbox` (`LootboxModule.sol:707`) | `claimRedemption:672` | TRACE-STOP at §12 boundary — `resolveRedemptionLootbox` is the §6 consumer (D-298-CONSUMER-LIST-01 entry 6), traced under that section. §12 hands `entropy` + `actScore` + `amount` + `player` to §6 and stops. |
| 7 | `_payBurnie` | `StakedDegenerusStonk.sol:842` | `claimRedemption:677` | reads `coin.balanceOf(this)` (BURNIE ERC20 balance — does not affect VRF-derived output, see §B-13/14); may invoke `coinflip.claimCoinflipsForRedemption` (token movement only — no VRF input) |
| 8 | `_payEth` | `StakedDegenerusStonk.sol:817` | `claimRedemption:683` | reads `address(this).balance` and `_claimableWinnings()`; may invoke `game.claimWinnings(address(0))` (no VRF input read inside §12 scope) |
| 9 | `_claimableWinnings` | `StakedDegenerusStonk.sol:857` | `_payEth:820`, `_payBurnie` does not read it | reads `game.claimableWinningsOf(address(this))` — view-only against game accounting, not a VRF-influenced slot for THIS consumer |

**Explicit-enumeration discipline** per `feedback_verify_call_graph_against_source.md`: confirmed by full read of `resolveRedemptionPeriod` (sStonk:585-610) and `claimRedemption` (sStonk:618-684) — no `delegatecall`, no inline assembly, no library-state mutation, no `for`/`while` loops with state reads. Helper invocations enumerated above (`_payBurnie`, `_payEth`, `_claimableWinnings`, three view-only cross-contract calls). No "by construction" / "single fn reaches all paths" shortcuts.

**TRACE-STOP boundary for §12:** `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` at sStonk:672 hands the keccak-derived `entropy` to `DegenerusGame.resolveRedemptionLootbox` (DegenerusGame.sol:1721) → `LootboxModule.resolveRedemptionLootbox` (LootboxModule.sol:707). That consumer entry is §6 in D-298-CONSUMER-LIST-01 and is audited under section 6's CATALOG file. §12 records the call as a TRACE-STOP at the contract boundary and lists §6 as the downstream consumer of the `entropy` value derived from `rngWordByDay[claimPeriodIndex]`.

## CAT-02 (§B) — SLOAD table

Every SLOAD reached during `resolveRedemptionPeriod` (advance-stack consumer) AND `claimRedemption` (EOA-stack consumer) execution, per F-41-02/03 enumeration discipline. Inline-assembly slot directives + raw `sstore` grep returned zero hits in `StakedDegenerusStonk.sol` (confirmed via `grep -n "assembly\|slot:" contracts/StakedDegenerusStonk.sol`).

### §B-A — `resolveRedemptionPeriod` (advance-stack entry; sStonk:585)

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-A1 | `ContractAddresses.GAME` (compile-time constant) | sStonk:586 | `msg.sender != ContractAddresses.GAME` access guard | NO | Compile-time `library` constant in `ContractAddresses.sol`; resolved at link time; no SLOAD. Access guard outcome governs reach, not VRF-derived output. |
| B-A2 | `redemptionPeriodIndex` (sStonk) | sStonk:588 | `uint32 period = redemptionPeriodIndex;` — selects which `redemptionPeriods[period]` slot to WRITE | **YES** | Determines which historical period gets the new roll value written; if stale (set on an earlier player-submit day), the roll lands in a period that was already resolved — causing the §D-VIOL re-roll pattern below. |
| B-A3 | `pendingRedemptionEthBase` | sStonk:589, sStonk:592 | early-return gate (`== 0 && Burnie == 0 return`) + multiplicand for `rolledEth = base * roll / 100` | **YES** | Multiplier on the VRF-derived `roll` → contributes magnitude to the rolled-ETH state update. |
| B-A4 | `pendingRedemptionBurnieBase` | sStonk:589, sStonk:597 | early-return gate + multiplicand for `burnieToCredit = base * roll / 100` | **YES** | Multiplier on `roll` → contributes to `RedemptionResolved` event payload `rolledBurnie` (observable VRF-derived output). |
| B-A5 | `pendingRedemptionEthValue` | sStonk:593 | RMW: `pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;` | **YES** | Running total whose post-resolution value depends on `roll`; consumed by `previewBurn` / `_deterministicBurnFrom` (`sStonk:535`, `:705`) and by `_submitGamblingClaimFrom` (`:772`) — feeds back into per-share proportional math for future burns. |
| B-A6 | `pendingRedemptionBurnie` | sStonk:600 | RMW: `pendingRedemptionBurnie -= pendingRedemptionBurnieBase;` | **YES** | Running total subtracted in same path; consumed by `burnieReserve()` (`:736`), `_submitGamblingClaimFrom` (`:778`), `previewBurn` (`:725`). Influences sizing of future gambling burns whose claims will be VRF-multiplied. |

### §B-B — `claimRedemption` (EOA-stack entry; sStonk:618 with line-670 cross-call re-read)

| # | Slot | Read-site (file:line) | Read context | Participating? | Attestation if NO |
|---|---|---|---|---|---|
| B-B1 | `pendingRedemptions[msg.sender]` (struct slot — `periodIndex`) | sStonk:621 (`claim.periodIndex == 0` gate) + sStonk:627 (`claimPeriodIndex = claim.periodIndex`) | NoClaim gate + value used as both lookup-key for `redemptionPeriods[claim.periodIndex]` (line 623) AND as `day` argument to `game.rngWordForDay(claimPeriodIndex)` (line 670) | **YES** | Drives which period's roll is consumed AND which day's rngWord seeds lootbox entropy. |
| B-B2 | `pendingRedemptions[msg.sender].ethValueOwed` | sStonk:632 | `totalRolledEth = (claim.ethValueOwed * roll) / 100` | **YES** | Direct multiplicand of the VRF-derived `roll`; produces `lootboxEth` (passed to game.resolveRedemptionLootbox at :672) and `ethDirect` (paid via `_payEth`). |
| B-B3 | `pendingRedemptions[msg.sender].activityScore` | sStonk:628 | `claimActivityScore = claim.activityScore` → passed as `actScore` to `game.resolveRedemptionLootbox(player, lootboxEth, entropy, actScore)` (line 672) | **YES** | Per §6 LootboxModule consumer (`resolveRedemptionLootbox` at `LootboxModule.sol:707`), `actScore` modulates lootbox rarity weighting — therefore feeds a VRF-derived output. |
| B-B4 | `pendingRedemptions[msg.sender].burnieOwed` | sStonk:652 | `burniePayout = (claim.burnieOwed * roll * (100 + rewardPercent)) / 10000` | **YES** | Multiplicand of `roll` and `rewardPercent` → produces `burniePayout` (transferred via `_payBurnie`). |
| B-B5 | `redemptionPeriods[claim.periodIndex]` (struct — `roll`) | sStonk:623, sStonk:624, sStonk:626 | NotResolved gate + `roll = period.roll` consumed in multiplications at :632 and :652 | **YES** | Direct VRF-derived input to ETH/BURNIE payout math. |
| B-B6 | `redemptionPeriods[claim.periodIndex]` (struct — `flipDay`) | sStonk:649 | `(rewardPercent, flipWon) = coinflip.getCoinflipDayResult(period.flipDay)` | **YES** | Determines which coinflip day's result feeds `rewardPercent` and `flipWon` into the burnie multiplication and dispatch (`flipResolved`). |
| B-B7 | `gameOver` (DegenerusGameStorage.sol:290) — read via `game.gameOver()` external view | sStonk:635 (`isGameOver = game.gameOver()`) | gates the `ethDirect = totalRolledEth` vs `ethDirect = totalRolledEth / 2; lootboxEth = totalRolledEth - ethDirect` dispatch | **YES** | Determines whether `lootboxEth != 0` branch executes (the `resolveRedemptionLootbox` call at :672 is gated on `lootboxEth != 0`) — i.e., gates whether the §6 VRF-consumer is invoked at all from this claim. |
| B-B8 | `coinflipDayResult[period.flipDay]` (BurnieCoinflip.sol:162) — read via `coinflip.getCoinflipDayResult(flipDay)` external view | sStonk:649 | yields `(rewardPercent, flipWon)` → both consumed in burniePayout math at :650-:653 | **YES** | `rewardPercent` is a multiplicand on roll·burnieOwed; `flipWon` gates the multiplication; their AND with `rewardPercent != 0` sets `flipResolved` (controls full-claim vs partial-clear dispatch at sStonk:659-665). |
| B-B9 | `rngWordByDay[claimPeriodIndex]` (DegenerusGameStorage.sol:435) — read via `game.rngWordForDay(claimPeriodIndex)` external view | sStonk:670 — `uint256 rngWord = game.rngWordForDay(claimPeriodIndex);` | hashed with `player` to produce `entropy = uint256(keccak256(abi.encode(rngWord, player)))` (line 671), passed to game.resolveRedemptionLootbox (line 672) | **YES** | The cross-call SLOAD called out in the prompt as the F-41-02/03 distinct-class re-read. The slot value is the SAME `rngWordByDay[day]` that was used at AdvanceModule:1226-1227 to derive the `roll` already stored in `period.roll`; here it is re-loaded for use as lootbox entropy. |
| B-B10 | `pendingRedemptionEthValue` | sStonk:657 (`pendingRedemptionEthValue -= totalRolledEth`) | RMW reduction by the player's claimed share | NO | Read for the subtraction-write; the post-value does NOT influence VRF-derived output of THIS claim — it only affects later burns' proportional math (already covered as a participating SLOAD inside `_submitGamblingClaimFrom` / `previewBurn`, which are separate write-then-read sites; here the SLOAD only sources the subtraction operand). Listed for completeness per `feedback_rng_window_storage_read_freshness.md`. |
| B-B11 | `pendingRedemptions[msg.sender]` (the whole struct — read again for `delete` / partial clear) | sStonk:661 (`delete pendingRedemptions[player]`), sStonk:664 (`claim.ethValueOwed = 0`) | branch on `flipResolved` to clear claim | NO | Pure SSTOREs (delete / partial clear); the dispatch was already decided from B-B6/B-B8. The "read" here is just the storage handle (already loaded into `claim`); no new value influences output. |
| B-B12 | `address(this).balance` (intrinsic, not SLOAD) | `_payEth:819`, `_payEth:824`, `_deterministicBurnFrom:532` reachable only from `burn()`, not §12 | balance lookup for payout sizing | NO | EVM-intrinsic balance opcode, not an SLOAD. Influences ETH-vs-stETH split inside `_payEth` (sStonk:817-839) but does NOT influence the VRF-derived `entropy` / `roll` / `rewardPercent` / `flipWon` / `gameOver` outputs already decided upstream. |
| B-B13 | `coin.balanceOf(address(this))` (cross-contract BURNIE ERC20 balance) — via `_payBurnie:843` | `_payBurnie:843` | determines ETH-vs-coinflip-claim split in BURNIE payout | NO | Affects payout SOURCE (this contract's BURNIE vs. coinflip-claim drain), not the VRF-derived AMOUNT (already fixed at burniePayout). Per `feedback_rng_window_storage_read_freshness.md` D-298-SLOT-CLASSIFICATION-01: value does not influence VRF-derived output. |
| B-B14 | `coin.balanceOf(address(this))` (stETH balance via `steth.balanceOf` — not reached in §12) | not reached in §12 paths | (n/a) | NO | `_payEth` reads `address(this).balance` not stETH; stETH is only read inside `_deterministicBurnFrom` which is a `burn()`-only path, not reachable from §12's `claimRedemption`. Listed for completeness. |
| B-B15 | `game.claimableWinningsOf(address(this))` via `_claimableWinnings` (sStonk:857) | `_payEth:820` (cross-contract view, not SLOAD on sStonk slot) | sources `claimableEth` for `_payEth`'s ETH-vs-stETH split | NO | Same rationale as B-B12: affects payout SOURCING (whether to drain claimable winnings vs use raw balance), not VRF-derived AMOUNT. The amount was fixed at `ethDirect`/`burniePayout` computation upstream. |

**Auxiliary §B-W — SSTOREs inside the consumer bodies (cross-check, not classified):**

| # | Slot | Write-site (file:line) | Notes |
|---|---|---|---|
| B-W1 | `pendingRedemptionEthValue` | sStonk:593 (resolve) | RMW. Already a participating SLOAD at B-A5; write derives from `roll`. |
| B-W2 | `pendingRedemptionEthBase` | sStonk:594 (resolve) | Cleared to 0 after consumption. |
| B-W3 | `pendingRedemptionBurnie` | sStonk:600 (resolve) | RMW; cleared by base subtraction. |
| B-W4 | `pendingRedemptionBurnieBase` | sStonk:601 (resolve) | Cleared to 0. |
| B-W5 | `redemptionPeriods[period]` | sStonk:604 (resolve) | Struct write `{roll, flipDay}`. **Overwritable** if `redemptionPeriodIndex == period` is reached again with non-zero base (see §D-VIOL). |
| B-W6 | `pendingRedemptionEthValue` | sStonk:657 (claim) | Reduction by `totalRolledEth`. |
| B-W7 | `pendingRedemptions[player]` (`delete`) | sStonk:661 (claim) | Full-clear if `flipResolved`. |
| B-W8 | `pendingRedemptions[player].ethValueOwed = 0` | sStonk:664 (claim) | Partial-clear if `!flipResolved`. |

## CAT-03 (§C) — Writer enumeration for participating slots

For each PARTICIPATING slot identified in §B, every external/public function (in any contract under `contracts/`) that writes the slot — per-callsite, with file:line. Includes OZ-inherited writers where applicable + admin/owner writers + cross-contract writers.

### §C-1 — `redemptionPeriodIndex` (sStonk; participating per B-A2)

Storage slot declared at `StakedDegenerusStonk.sol:230` (`uint32 internal redemptionPeriodIndex`). Exhaustive `grep -n "redemptionPeriodIndex" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-1a | `_submitGamblingClaimFrom` | sStonk:760 (`redemptionPeriodIndex = currentPeriod;` inside `if (redemptionPeriodIndex != currentPeriod) { ... }` block) | `burn()` (sStonk:486) and `burnWrapped()` (sStonk:506) — both external EOA-callable. | EOA writer. Gated by `!game.gameOver()` (sStonk:487), `!game.livenessTriggered()` (sStonk:491), `!game.rngLocked()` (sStonk:492). Not gated against post-resolution / mid-window re-writes on the same wall-clock day. |

OZ-inherited writers: `redemptionPeriodIndex` is a private uint32 — no ERC20/ERC721 inheritance touches it. Admin/owner writers: zero hits — `grep -n "onlyOwner\|onlyAdmin\|onlyGame" contracts/StakedDegenerusStonk.sol` shows only the `onlyGame` modifier on `receive`, `depositSteth`, `transferFromPool`, `transferBetweenPools`, `burnAtGameOver` — none of which touch `redemptionPeriodIndex`. Constructor: not written in constructor (default zero). Inline-assembly: zero hits.

### §C-2 — `pendingRedemptionEthBase` (sStonk; participating per B-A3)

Storage at `StakedDegenerusStonk.sol:226`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-2a | `resolveRedemptionPeriod` | sStonk:594 (`pendingRedemptionEthBase = 0;`) | `AdvanceModule.advanceGame` → `rngGate` / `_gameOverEntropy` (advance-stack only; sStonk:586 access guard `msg.sender == ContractAddresses.GAME`). | EXEMPT-ADVANCEGAME stack writer. |
| C-2b | `_submitGamblingClaimFrom` | sStonk:790 (`pendingRedemptionEthBase += ethValueOwed;`) | `burn()` (sStonk:486) / `burnWrapped()` (sStonk:506) — external EOA-callable. | EOA writer; same gates as C-1a. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-3 — `pendingRedemptionBurnieBase` (sStonk; participating per B-A4)

Storage at `StakedDegenerusStonk.sol:227`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-3a | `resolveRedemptionPeriod` | sStonk:601 (`pendingRedemptionBurnieBase = 0;`) | advance-stack only (access guard sStonk:586). | EXEMPT-ADVANCEGAME stack writer. |
| C-3b | `_submitGamblingClaimFrom` | sStonk:792 (`pendingRedemptionBurnieBase += burnieOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-4 — `pendingRedemptionEthValue` (sStonk; participating per B-A5)

Storage at `StakedDegenerusStonk.sol:224` (`uint256 public pendingRedemptionEthValue`). Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-4a | `resolveRedemptionPeriod` | sStonk:593 (`pendingRedemptionEthValue = pendingRedemptionEthValue - pendingRedemptionEthBase + rolledEth;`) | advance-stack only. | EXEMPT-ADVANCEGAME. |
| C-4b | `claimRedemption` | sStonk:657 (`pendingRedemptionEthValue -= totalRolledEth;`) | EOA-callable via `claimRedemption()` — NO access guard. | EOA writer. |
| C-4c | `_submitGamblingClaimFrom` | sStonk:789 (`pendingRedemptionEthValue += ethValueOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |

The slot is `public` (auto-getter), but writers are limited to these three sites. OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-5 — `pendingRedemptionBurnie` (sStonk; participating per B-A6)

Storage at `StakedDegenerusStonk.sol:225`. Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-5a | `resolveRedemptionPeriod` | sStonk:600 (`pendingRedemptionBurnie -= pendingRedemptionBurnieBase;`) | advance-stack only. | EXEMPT-ADVANCEGAME. |
| C-5b | `_submitGamblingClaimFrom` | sStonk:791 (`pendingRedemptionBurnie += burnieOwed;`) | `burn()` / `burnWrapped()` external EOA. | EOA writer. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-6 — `pendingRedemptions[player]` struct slot (B-B1/B-B2/B-B3/B-B4 — `periodIndex`, `ethValueOwed`, `activityScore`, `burnieOwed`)

Storage mapping at `StakedDegenerusStonk.sol:221` (`mapping(address => PendingRedemption) public pendingRedemptions`). Struct packs `ethValueOwed` (uint96) + `burnieOwed` (uint96) + `periodIndex` (uint32) + `activityScore` (uint16) = 240 bits into one slot. Exhaustive grep `grep -n "pendingRedemptions\[" contracts/StakedDegenerusStonk.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-6a | `_submitGamblingClaimFrom` (writes `claim.ethValueOwed`, `claim.burnieOwed`, `claim.periodIndex`, `claim.activityScore`) | sStonk:803, sStonk:805, sStonk:806, sStonk:810 | `burn()` / `burnWrapped()` external EOA. | EOA writer; same gates as C-1a. |
| C-6b | `claimRedemption` (delete) | sStonk:661 (`delete pendingRedemptions[player]`) | EOA-callable; no guard. | EOA writer (clear). |
| C-6c | `claimRedemption` (partial clear) | sStonk:664 (`claim.ethValueOwed = 0`) | EOA-callable; no guard. | EOA writer (partial clear). |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-7 — `redemptionPeriods[period]` struct slot (B-B5/B-B6 — `roll`, `flipDay`)

Storage mapping at `StakedDegenerusStonk.sol:222` (`mapping(uint32 => RedemptionPeriod) public redemptionPeriods`). Exhaustive grep:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-7a | `resolveRedemptionPeriod` | sStonk:604 (`redemptionPeriods[period] = RedemptionPeriod({roll, flipDay});`) | advance-stack only (access guard sStonk:586). | Only writer. EXEMPT-ADVANCEGAME callsites at AdvanceModule.sol:1230 / :1293 / :1323. **However:** if `redemptionPeriodIndex` SLOAD at sStonk:588 returns a stale value pointing at an already-resolved period (because `redemptionPeriodIndex` was not advanced after the prior resolution), this WRITE overwrites the prior `redemptionPeriods[period]` struct with a new roll. See §D-VIOL-1. |

OZ-inherited: none. Admin/owner: zero. Constructor: not written. Inline-assembly: zero.

### §C-8 — `gameOver` (DegenerusGameStorage.sol:290) — read via `game.gameOver()` external view at sStonk:635

Storage declared as `bool public gameOver;` Exhaustive `grep -n "gameOver\s*=\s*true\|gameOver\s*=\s*false\|gameOver =" contracts/ -r --include="*.sol"` (excluding comments and `gameOverPossible`, `gameOverFlag`, etc.):

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-8a | `GameOverModule.handleGameOverDrain` | `GameOverModule.sol:139` (`gameOver = true;`) | Called via `DegenerusGame.handleGameOverDrain` (`DegenerusGame.sol`) ← via `AdvanceModule._handleGameOverPath` (`AdvanceModule.sol:185` → `:522` → `:600`) ← `advanceGame()` (`AdvanceModule.sol:158`). | EXEMPT-ADVANCEGAME stack writer. The single SSTORE site for `gameOver`. |

OZ-inherited: none. Admin/owner: not directly settable. Constructor: default false. Inline-assembly: zero hits.

### §C-9 — `coinflipDayResult[flipDay]` (BurnieCoinflip.sol:162) — read via `coinflip.getCoinflipDayResult(flipDay)` external view at sStonk:649

Storage `mapping(uint32 => CoinflipDayResult) internal coinflipDayResult;` Exhaustive `grep -n "coinflipDayResult\[" contracts/BurnieCoinflip.sol`:

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-9a | `BurnieCoinflip._resolveDay` (called inside `processCoinflipPayouts` at `BurnieCoinflip.sol:805`) | `BurnieCoinflip.sol:840` (`coinflipDayResult[epoch] = CoinflipDayResult({rewardPercent, win})`) | `processCoinflipPayouts` is called only from `AdvanceModule.sol:1217` (rngGate), `:1277` (`_gameOverEntropy` fresh path), `:1307` (`_gameOverEntropy` fallback path), `:1794` (`_backfillGapDays`) — all reached only from `advanceGame()` stack. | EXEMPT-ADVANCEGAME stack writer. Confirmed by `grep -n "function processCoinflipPayouts\b" contracts/BurnieCoinflip.sol` (single definition at :805) and `grep -rn "processCoinflipPayouts\b" contracts/` (four callers, all in AdvanceModule, all advance-stack). |

OZ-inherited: none. Admin/owner: zero. Constructor: default zero per mapping. Inline-assembly: zero.

### §C-10 — `rngWordByDay[day]` (DegenerusGameStorage.sol:435) — read via `game.rngWordForDay(claimPeriodIndex)` external view at sStonk:670

Storage `mapping(uint32 => uint256) internal rngWordByDay;` Exhaustive `grep -rn "rngWordByDay\[" contracts/ --include="*.sol"` filtered to WRITE sites (mapping LHS of `=` not `==`):

| # | Writer function | Callsite (file:line) | External reach | Notes |
|---|---|---|---|---|
| C-10a | `AdvanceModule._applyDailyRng` | `AdvanceModule.sol:1841` (`rngWordByDay[day] = finalWord;`) | Called from `rngGate:1216` and `_gameOverEntropy:1275` (fresh) / `:1305` (fallback) — all advance-stack. | EXEMPT-ADVANCEGAME. |
| C-10b | `AdvanceModule._backfillGapDays` | `AdvanceModule.sol:1793` (`rngWordByDay[gapDay] = derivedWord;`) | Called from `rngGate:1203` — advance-stack. | EXEMPT-ADVANCEGAME. |

OZ-inherited: none. Admin/owner: zero (no setter). Constructor: default zero. Inline-assembly: zero. **The slot is write-once-per-day:** once `rngWordByDay[day] != 0`, no subsequent SSTORE overwrites it (gate at AdvanceModule:1187 / :1201 / :1271 / :1187 short-circuits). Thus the cross-call re-read at sStonk:670 reads a permanently-frozen value once non-zero — the F-41-02/03-class "value mutability between commit and re-consumption" risk is fully absent for THIS slot.

## CAT-04 (§D) — Per-tuple verdict matrix

Per `D-298-EXEMPT-REACH-01` strict + per-callsite classification. Classification set per `D-298-CONSUMER-LIST-01` + v43.0 milestone goal: `EXEMPT-ADVANCEGAME` | `EXEMPT-VRFCALLBACK` | `EXEMPT-RETRYLOOTBOXRNG` | `VIOLATION`. The discretionary fifth-class disposition is prohibited by milestone-goal prose.

| # | Slot | Writer function | Callsite (file:line) | Reached from EXEMPT stack? | Classification |
|---|---|---|---|---|---|
| D-1 | `redemptionPeriodIndex` (sStonk) | `_submitGamblingClaimFrom` | sStonk:760 (via `burn()` / `burnWrapped()`) | NO — EOA-callable; rngLockedFlag gate at sStonk:492 covers `game.rngLocked() == true` (VRF in-flight) but does NOT cover the post-resolution window where `redemptionPeriodIndex` is stale-pointing at a just-resolved period. | **VIOLATION** |
| D-2 | `pendingRedemptionEthBase` | `resolveRedemptionPeriod` | sStonk:594 (advance-stack root sStonk:586) | YES — sole reaching entry is `advanceGame()` stack (callsites AdvanceModule.sol:1230 / :1293 / :1323). | **EXEMPT-ADVANCEGAME** |
| D-3 | `pendingRedemptionEthBase` | `_submitGamblingClaimFrom` | sStonk:790 (via `burn()` / `burnWrapped()`) | NO — EOA-callable; rngLockedFlag-gated against in-flight VRF (sStonk:492) BUT not against post-resolution / pre-next-advance window where this base feeds a re-roll of an already-resolved period. | **VIOLATION** |
| D-4 | `pendingRedemptionBurnieBase` | `resolveRedemptionPeriod` | sStonk:601 (advance-stack) | YES — same as D-2. | **EXEMPT-ADVANCEGAME** |
| D-5 | `pendingRedemptionBurnieBase` | `_submitGamblingClaimFrom` | sStonk:792 (via `burn()` / `burnWrapped()`) | NO — same reach analysis as D-3. | **VIOLATION** |
| D-6 | `pendingRedemptionEthValue` | `resolveRedemptionPeriod` | sStonk:593 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-7 | `pendingRedemptionEthValue` | `claimRedemption` | sStonk:657 (EOA-callable) | NO — EOA stack. However, the WRITE here is a SUBTRACTION of `totalRolledEth` already-derived-from-VRF-output; it does not introduce attacker-controlled entropy. Still listed as VIOLATION per D-298-EXEMPT-REACH-01 strict rule (writer-callsite is non-EXEMPT). Severity downgraded in §E rationale. | **VIOLATION** |
| D-8 | `pendingRedemptionEthValue` | `_submitGamblingClaimFrom` | sStonk:789 (via `burn()` / `burnWrapped()`) | NO — same reach as D-3. | **VIOLATION** |
| D-9 | `pendingRedemptionBurnie` | `resolveRedemptionPeriod` | sStonk:600 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-10 | `pendingRedemptionBurnie` | `_submitGamblingClaimFrom` | sStonk:791 (via `burn()` / `burnWrapped()`) | NO — same reach as D-3. | **VIOLATION** |
| D-11 | `pendingRedemptions[player].*` | `_submitGamblingClaimFrom` | sStonk:803/805/806/810 (via `burn()` / `burnWrapped()`) | NO — EOA-callable. Note: by `_submitGamblingClaimFrom` design, write to `claim.*` only proceeds if `claim.periodIndex == 0` OR `claim.periodIndex == currentPeriod` (sStonk:796-798); same-period growth is feature-by-design but participates in the D-1/D-3/D-5 re-roll vector. | **VIOLATION** |
| D-12 | `pendingRedemptions[player]` (delete / partial clear) | `claimRedemption` | sStonk:661 / sStonk:664 | NO — EOA stack. However, these are CLEARS of the player's own claim (`msg.sender`); they cannot alter another player's VRF-derived output for a current claim cycle. Severity downgraded in §E. | **VIOLATION** |
| D-13 | `redemptionPeriods[period]` (`{roll, flipDay}`) | `resolveRedemptionPeriod` | sStonk:604 (advance-stack) | YES — sole writer is advance-stack. | **EXEMPT-ADVANCEGAME** (write itself), but the OVERWRITE-vulnerability arises from D-1/D-3/D-5 stale-`redemptionPeriodIndex` letting this slot be re-written on a future advance — captured under D-1/D-3/D-5. |
| D-14 | `gameOver` | `GameOverModule.handleGameOverDrain` | GameOverModule.sol:139 (advance-stack root `_handleGameOverPath`) | YES — only reaching root is `advanceGame()` → `_handleGameOverPath` → `handleGameOverDrain`. Single SSTORE site. | **EXEMPT-ADVANCEGAME** |
| D-15 | `coinflipDayResult[flipDay]` | `BurnieCoinflip._resolveDay` (via `processCoinflipPayouts`) | BurnieCoinflip.sol:840 (advance-stack — 4 callsites all under `advanceGame` per §C-9) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-16 | `rngWordByDay[day]` | `AdvanceModule._applyDailyRng` | AdvanceModule.sol:1841 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |
| D-17 | `rngWordByDay[gapDay]` | `AdvanceModule._backfillGapDays` | AdvanceModule.sol:1793 (advance-stack) | YES — advance-stack. | **EXEMPT-ADVANCEGAME** |

**§D-VIOL — Cross-cutting VIOLATION pattern (D-1 / D-3 / D-5 / D-11 root cause):**

The methodology note for §12 flagged a "first-time audit of this consumer's storage-write surface for rngLockedFlag freeze coverage." This analysis confirms a concrete VIOLATION pattern unique to gambling-burn resolution:

1. **Trigger sequence (intra-day re-burn after public roll):**
   - Day D, player A submits `burn(amount_A)` → sStonk:760 sets `redemptionPeriodIndex = D`; sStonk:790 sets `pendingRedemptionEthBase = ethValueOwed_A`. Gates at sStonk:487/491/492 ALL pass (no VRF in-flight at submit time).
   - Day D advance() fires → `rngGate` writes `rngWordByDay[D]`, derives `redemptionRoll_D = uint16(((currentWord >> 8) % 151) + 25)` (AdvanceModule:1226-1228), calls `sdgnrs.resolveRedemptionPeriod(redemptionRoll_D, D+1)` → sStonk:604 writes `redemptionPeriods[D] = {roll_D, D+1}`; sStonk:594 zeros `pendingRedemptionEthBase`. `redemptionPeriodIndex` REMAINS at `D` (no write to it in `resolveRedemptionPeriod`). `_unlockRng(D)` clears `rngLockedFlag` (AdvanceModule:1731) — `game.rngLocked()` now returns `false`.
   - Wall-clock day is STILL D (advanceGame closes day D's events on day D itself or later, but the wall-clock check `currentDayView()` is purely time-derived; if advance fires early in day D+1 wall-clock, the scenario uses day D+1, but the SAME logic applies one day shifted).
   - Player B reads `redemptionPeriods[D].roll = roll_D` (mapping is `public` per sStonk:222 → auto-getter); if roll_D is unfavorable (e.g., 25–80), proceeds to step 4.
   - Player B calls `burn(1 wei)` on day D (post-resolution) → sStonk:487 `!gameOver()` passes; sStonk:491 `!livenessTriggered()` passes; sStonk:492 `!game.rngLocked()` passes (cleared by `_unlockRng`). `_submitGamblingClaimFrom` runs:
     - sStonk:757 `currentPeriod = D`; sStonk:758 `redemptionPeriodIndex (D) == currentPeriod (D)` → no reset of `redemptionPeriodSupplySnapshot` / `redemptionPeriodBurned`.
     - sStonk:790 `pendingRedemptionEthBase += newOwed` → now NON-ZERO again. sStonk:792 same for burnie base.
     - sStonk:803/805 `claim.ethValueOwed += newOwed` — Player B's existing claim grows. (Or, if Player B already called `claimRedemption` and the claim was deleted, this re-creates the claim with `claim.periodIndex = D`.)
2. **Next advance re-resolves the same period:**
   - Day D+1 (or next advance interval), `advanceGame` fires → `rngGate` writes `rngWordByDay[D+1]`, derives `redemptionRoll_{D+1}`, calls `sdgnrs.resolveRedemptionPeriod(redemptionRoll_{D+1}, D+2)`.
   - Inside: sStonk:588 `period = redemptionPeriodIndex = D` (still D — never advanced). sStonk:589 early-return-skipped because `pendingRedemptionEthBase != 0`. sStonk:604 writes `redemptionPeriods[D] = {roll: redemptionRoll_{D+1}, flipDay: D+2}` — **OVERWRITES** the original `roll_D`.
3. **Strategy / asymmetric payoff:**
   - Player B can examine `roll_D`, claim immediately if favorable (lock in roll_D), or re-burn 1 wei to force a re-roll on the next advance. The re-roll applies to BOTH the original `claim_B.ethValueOwed` and the trivial new portion — effectively re-rolling the ENTIRE original stake with a fresh independent random outcome.
   - With unbounded re-rolls, EV approaches the max (175%) modulo budget. Even one re-roll lifts EV from `(25+175)/2 = 100` to `0.5 · E[roll | roll ≥ 100] + 0.5 · 100 = 0.5 · 137.5 + 50 = 118.75` — a ~19% free EV gain per round of re-roll.
   - Cost of one re-roll: 1 wei of sDGNRS (negligible). 50% supply cap (sStonk:763 `redemptionPeriodBurned + amount > redemptionPeriodSupplySnapshot / 2`) bounds intra-period growth, but does NOT block 1-wei re-burns (`redemptionPeriodBurned += amount` accumulates negligibly).
   - Collateral damage: any OTHER player C who submitted on day D with `claim_C.periodIndex = D` and has not yet called `claimRedemption` will ALSO have `period.roll` overwritten. Player C sees a different roll at their claim time than was published at the original resolution event. This is data-corruption-class behavior even ignoring the EV asymmetry.
4. **Existing rngLockedFlag gate at sStonk:492 is structurally INSUFFICIENT:** the gate covers ONLY the in-flight VRF window (`game.rngLocked() == true`). It does NOT cover the post-resolution / pre-next-advance window where `redemptionPeriodIndex` is stale-pointing at a closed period and `rngLockedFlag = false`.
5. **Gap-day re-resolution edge case:** the `_backfillGapDays` (AdvanceModule:1779) NOTE-comment at AdvanceModule:1772-1774 says "resolveRedemptionPeriod is NOT called for backfilled gap days." The current code path supports this (no resolve call inside `_backfillGapDays`). However, if `redemptionPeriodIndex` was set to a pre-stall day D and a post-stall advance fires after gap-fill, `period = D` could still resolve with the FUTURE day's roll — a separate flavor of the same data-corruption pattern.

**Reach-stack summary for D-1/D-3/D-5/D-11 (the actionable VIOLATION cluster):** EOA → `burn()` / `burnWrapped()` (sStonk:486 / :506) → `_submitGamblingClaimFrom` (sStonk:752); only gates are `!gameOver` (`game.gameOver()`), `!livenessTriggered` (`game.livenessTriggered()`), and `!rngLocked` (`game.rngLocked()`). None of these gate against "current `redemptionPeriodIndex` already resolved — wait for `_submitGamblingClaim` to advance the index before allowing new base accumulation."

**Severity downgrade rationale for D-7/D-12:** These are non-EXEMPT-stack writes inside `claimRedemption` of slots the player already controls or that subtract VRF-derived (not VRF-influencing) values. They are listed VIOLATION per D-298-EXEMPT-REACH-01 strict rule but the FIX is structurally subsumed by closing the D-1/D-3/D-5/D-11 window (no separate remediation needed — see §E).

## CAT-06 (§E) — Per-VIOLATION recommended tactic

Per `D-298-RECOMMEND-DEPTH-01`: ONE recommended tactic from `(a) rngLockedFlag-gated revert | (b) snapshot/anchor pattern | (c) pre-lock reorder | (d) immutable` + ≤80-char rationale.

| # | VIOLATION row | Recommended tactic | Rationale (≤80 chars) |
|---|---|---|---|
| E-1 | D-1: `redemptionPeriodIndex` re-pointable to closed period via post-resolution `_submitGamblingClaimFrom` | **(a)** | Revert in `_submitGamblingClaimFrom` if `redemptionPeriods[redemptionPeriodIndex].roll != 0` |
| E-2 | D-3: `pendingRedemptionEthBase` grown after period resolved | **(a)** | Same gate as E-1 — base-growth and index-pointing are co-mutated; one check covers both |
| E-3 | D-5: `pendingRedemptionBurnieBase` grown after period resolved | **(a)** | Subsumed by E-1's revert (same writer fn, same callsite). |
| E-4 | D-7: `pendingRedemptionEthValue` subtraction inside `claimRedemption` | **(a)** | Subsumed by E-1 — pre-resolution-window writes are blocked, so subtraction operand stays consistent |
| E-5 | D-8: `pendingRedemptionEthValue` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 — same writer fn revert covers all base/value/burnie growths |
| E-6 | D-10: `pendingRedemptionBurnie` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 |
| E-7 | D-11: `pendingRedemptions[player].*` grown inside `_submitGamblingClaimFrom` | **(a)** | Subsumed by E-1 |
| E-8 | D-12: `pendingRedemptions[player]` clear inside `claimRedemption` | **(a)** | Subsumed by E-1; once index-advance is enforced, clear-write is the legitimate downstream effect |

**Rationale expansion (out-of-table for traceability; the 80-char cells above are the verdict-matrix entries):**

Tactic **(a) rngLockedFlag-gated revert** at the `_submitGamblingClaimFrom` entry is the structurally minimal fix. The precedent is the `sStonk:492` line (`if (game.rngLocked()) revert BurnsBlockedDuringRng();`) which already exists — the methodology note cited this as the convention. The fix extends the gate from "block burns while VRF in-flight" to "block burns whenever a `_submitGamblingClaimFrom` would extend a same-day period whose `redemptionPeriods[redemptionPeriodIndex].roll != 0`." Two implementation shapes:

1. **Direct gate at _submitGamblingClaimFrom (sStonk:752):** insert `if (redemptionPeriods[redemptionPeriodIndex].roll != 0 && currentPeriod == redemptionPeriodIndex) revert BurnsBlockedAfterResolution();` immediately after `currentPeriod = game.currentDayView();` at sStonk:757. The new error (or reused `BurnsBlockedDuringRng`) revert closes the post-resolution intra-day window.
2. **Advance-index protocol shape:** alternatively, advance `redemptionPeriodIndex` to `currentPeriod` inside `resolveRedemptionPeriod` itself OR clear `redemptionPeriodIndex` to zero at end of resolveRedemptionPeriod, then make `_submitGamblingClaimFrom` always initialize a fresh period when `redemptionPeriodIndex == 0`. This is a refactor over a gate and would change observable state — defer to Phase 299 sub-phase planning per `feedback_design_intent_before_deletion.md`.

Tactic **(b) snapshot/anchor** is REJECTED for this consumer's VIOLATION class: the offending pattern is not "value mutates between commit and re-read" (the only re-read of `rngWordByDay[claimPeriodIndex]` at sStonk:670 IS frozen, per §C-10 write-once attestation). The offending pattern is "writer-callsite mutates `redemptionPeriodIndex`'s effective meaning AFTER resolution closes the period." Snapshotting `redemptionPeriodIndex` at resolution time would still leave the `pendingRedemptionEthBase`-growth bypass open.

Tactic **(c) pre-lock reorder** is REJECTED: reordering inside `resolveRedemptionPeriod` (e.g., writing `redemptionPeriodIndex = currentPeriod + 1` or clearing it) is essentially the "advance-index protocol shape" alternative above; classified as a refactor over a gate.

Tactic **(d) immutable** is N/A — `redemptionPeriodIndex` is intentionally mutable across periods.

The line-670 cross-call SLOAD of `rngWordByDay[claimPeriodIndex]` itself is **not a VIOLATION** in §12's scope: §C-10 enumerates two write sites, both `EXEMPT-ADVANCEGAME`, and the slot is write-once-per-day. The F-41-02/03 distinct-class concern called out in the methodology note IS the VIOLATION cluster D-1/D-3/D-5/D-11 — same root pattern, different slot (sStonk-side state vs game-side `rngWordByDay`).

---

## Audit metadata

- **Trace discipline:** every reachable SLOAD inside both `resolveRedemptionPeriod` and `claimRedemption` enumerated per `feedback_rng_window_storage_read_freshness.md`; NO "by construction" / "covered by single fn" shortcuts per `feedback_verify_call_graph_against_source.md`. Two view-only external calls into game (`gameOver`, `rngWordForDay`) and one into coinflip (`getCoinflipDayResult`) are walked at the storage-slot level (see §C-8, §C-9, §C-10).
- **Commitment-window discipline:** per `feedback_rng_commitment_window.md`, the relevant commitment points are (i) `rngWordByDay[D] = finalWord` (`AdvanceModule.sol:1841`) for the rngWord that derives `roll`, and (ii) `redemptionPeriods[D] = {roll, flipDay}` (`StakedDegenerusStonk.sol:604`) for the roll already stored. Attacker reachability of writers between these commitments and the consumer re-reads at sStonk:632 / sStonk:649 / sStonk:670 was the gating analysis. The line-670 SLOAD is safe (write-once slot); the §D-VIOL cluster shows the same FRESHNESS principle violated on sStonk-side accounting slots.
- **Cross-call F-41-02/03 attestation:** the cross-call SLOAD pattern flagged in the prompt ("line 585 reads rngWord once, then line 670 re-reads rngWordForDay(claimPeriodIndex)") is the slot `rngWordByDay[claimPeriodIndex]`. Its writers are both `EXEMPT-ADVANCEGAME` (§C-10) AND the slot is write-once (`AdvanceModule.sol:1187 / :1201 / :1271` short-circuit on non-zero). The distinct-class concern materializes instead at the sStonk-side cluster (`redemptionPeriodIndex` + `pendingRedemption*Base*` + `pendingRedemptions[player]`) which are post-resolution writable from EOA paths.
- **Verdicts:** 15 SLOADs enumerated / 15 participating / 11 distinct writer-callsite tuples after de-dup / **8 VIOLATION rows (D-1, D-3, D-5, D-7, D-8, D-10, D-11, D-12)** / 9 EXEMPT-ADVANCEGAME rows (D-2, D-4, D-6, D-9, D-13, D-14, D-15, D-16, D-17). 0 discretionary-disposition rows (milestone-goal prohibition honored).
- **Scope:** zero `contracts/` + zero `test/` mutations per D-43N-AUDIT-ONLY-01. Only the §12 catalog file under `.planning/` is created.
- **Phase 299 hand-forward:** the §D-VIOL cluster collapses into a single FIX recommendation E-1 (with E-2..E-8 subsumed). Phase 299 plan-phase consumes this as one sub-phase candidate; design-intent trace per `feedback_design_intent_before_deletion.md` is deferred to that plan-phase.
