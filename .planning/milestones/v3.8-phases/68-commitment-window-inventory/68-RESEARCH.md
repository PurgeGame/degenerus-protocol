# Phase 68: Commitment Window Inventory - Research

**Researched:** 2026-03-22
**Domain:** Solidity smart contract audit -- VRF commitment window state inventory
**Confidence:** HIGH

## Summary

Phase 68 is a pure audit/documentation phase requiring no code changes. The goal is to produce a complete catalog of every storage variable that VRF fulfillment touches (reads, writes, or feeds into outcome computation), along with every external function that could mutate those variables. This is the foundation for Phase 69's SAFE/VULNERABLE verdicts.

The codebase has two distinct VRF paths: (1) daily RNG via `advanceGame -> rngGate -> rawFulfillRandomWords`, and (2) mid-day lootbox RNG via `requestLootboxRng -> rawFulfillRandomWords`. Both converge in `rawFulfillRandomWords` (AdvanceModule line 1436). The daily path feeds into jackpot selection, coinflip resolution, redemption rolls, lootbox RNG finalization, and prize pool operations. The mid-day path only writes `lootboxRngWordByIndex` and `lastLootboxRngWord`.

**Primary recommendation:** Structure the inventory as three catalogs: (A) forward-trace from `rawFulfillRandomWords` through all downstream consumers, (B) backward-trace from each outcome computation to the committed inputs it depends on, and (C) mutation surface per variable listing every external/public function that can write it.

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| CW-01 | Every storage variable written or read by VRF fulfillment (rawFulfillRandomWords -> all downstream consumers) is cataloged with slot, contract, and purpose | Forward-trace catalog structure documented below. `forge inspect` provides slot numbers. Two VRF paths (daily + mid-day) identified with complete call graphs. |
| CW-02 | Every storage variable that feeds into VRF-dependent outcome computations is cataloged (backward trace from outcome to committed inputs) | Backward-trace catalog structure documented below. Six outcome computation categories identified (coinflip, jackpot ETH, jackpot coin, lootbox, redemption, prize pool operations). |
| CW-03 | For each cataloged variable, every external/public function that can mutate it is identified with call-graph depth (direct + indirect via internal calls) | Mutation surface analysis methodology documented. All external functions on DegenerusGame, BurnieCoinflip, StakedDegenerusStonk identified. Call-graph depth tracking approach defined. |
</phase_requirements>

## Standard Stack

### Core Tools

| Tool | Version | Purpose | Why Standard |
|------|---------|---------|--------------|
| Foundry (forge) | Latest | `forge inspect` for storage layout, `forge test` for validation | Already in project -- provides authoritative slot numbers |
| Solidity 0.8.34 | 0.8.34 | Contract source language | Project standard |

### Supporting

| Tool | Purpose | When to Use |
|------|---------|-------------|
| `forge inspect <Contract> storage-layout` | Extract authoritative EVM slot assignments | CW-01, CW-02: getting slot numbers for every variable |
| `grep -rn` / project search | Trace variable reads/writes across contracts | CW-03: finding mutation surfaces |

### No External Libraries Needed

This is a pure audit/analysis phase. No npm packages, no new dependencies. All work is reading contracts, tracing call graphs, and producing documentation.

## Architecture Patterns

### Recommended Catalog Structure

The output should be structured markdown documents (findings files), not code. The catalog should follow this organization:

```
audit/
  v3.8-commitment-window-inventory.md    # The deliverable
```

### Pattern 1: Forward-Trace Catalog

**What:** Start from `rawFulfillRandomWords` entry point and trace every storage read/write through all downstream functions.

**When to use:** CW-01 requirement.

**Structure per variable entry:**

```markdown
| Variable | Contract | Slot | Type | Purpose | Read/Write | Accessed By (function chain) |
```

**Entry point:** `DegenerusGameAdvanceModule.rawFulfillRandomWords()` (line 1436)

**Two branches in rawFulfillRandomWords:**
1. `rngLockedFlag == true` (daily RNG): stores `rngWordCurrent = word`
2. `rngLockedFlag == false` (mid-day RNG): stores `lootboxRngWordByIndex[index] = word`, clears `vrfRequestId`, `rngRequestTime`

**Daily path downstream (via advanceGame -> rngGate):**
- `_applyDailyRng` -> writes `rngWordCurrent`, `rngWordByDay[day]`, `totalFlipReversals`, `lastVrfProcessedTimestamp`
- `coinflip.processCoinflipPayouts` -> writes `coinflipDayResult[epoch]`, `flipsClaimableDay`, `currentBounty`, `bountyOwedTo`
- `_finalizeLootboxRng` -> writes `lootboxRngWordByIndex[index]`, `lastLootboxRngWord`
- `sdgnrs.resolveRedemptionPeriod` -> reads `rngWordCurrent`, writes redemption state
- `payDailyJackpot` -> reads `currentPrizePool`, `traitBurnTicket`, `ticketQueue`; writes `claimableWinnings`, `claimablePool`, etc.
- `_payDailyCoinJackpot` -> reads prize pools, writes coin balances
- `_consolidatePrizePools` -> reads/writes `currentPrizePool`, `prizePoolsPacked`
- `_applyTimeBasedFutureTake` -> reads/writes `prizePoolsPacked`
- `_runRewardJackpots` -> reads `traitBurnTicket`, writes `claimableWinnings`, `claimablePool`
- `processTicketBatch` -> reads `lastLootboxRngWord`, `ticketQueue`, `ticketsOwedPacked`; writes `traitBurnTicket`

### Pattern 2: Backward-Trace Catalog

**What:** Start from each outcome that a player cares about (who wins, how much they win) and trace backward to every input that influenced that outcome.

**When to use:** CW-02 requirement. This is the critical audit methodology -- see project memory `feedback_rng_backward_trace.md`.

**Six outcome categories to trace backward from:**

1. **Coinflip win/loss** -- `(rngWord & 1) == 1` at BurnieCoinflip.sol:810
   - Backward: `rngWord` <- `_applyDailyRng(day, rawWord)` <- `rngWordCurrent` <- `rawFulfillRandomWords`
   - Inputs: `totalFlipReversals` (nudges), `coinflipBalance[epoch][player]` (bet amount)

2. **Jackpot ETH winner selection** -- trait-based winner in JackpotModule
   - Backward: winner <- `traitBurnTicket[level][traitId]` array index via `randWord`
   - Inputs: `traitBurnTicket` array contents, `currentPrizePool`, `randWord`

3. **Jackpot coin winner** -- via `_payDailyCoinJackpot`
   - Backward: similar trait-based selection

4. **Lootbox outcome** -- resolved at open time using `lootboxRngWordByIndex[index]`
   - Backward: `lootboxRngWordByIndex` <- `rawFulfillRandomWords` (mid-day) or `_finalizeLootboxRng` (daily)
   - Inputs: `lootboxEth[index][player]`, `lootboxBaseLevelPacked`, `lootboxEvScorePacked`

5. **Redemption roll** -- `((currentWord >> 8) % 151) + 25` at AdvanceModule line 804-805
   - Backward: `currentWord` <- `_applyDailyRng`

6. **Prize pool consolidation** -- `_consolidatePrizePools(lvl, rngWord)` and `_applyTimeBasedFutureTake`
   - Backward: `rngWord`, `currentPrizePool`, `prizePoolsPacked`

### Pattern 3: Mutation Surface Catalog

**What:** For each variable in the forward/backward catalogs, list every external/public function that can write to it, directly or indirectly.

**When to use:** CW-03 requirement.

**Structure per variable entry:**

```markdown
| Variable | External Function | Call Path | Depth | Access Control |
```

**Depth levels:**
- **D0 (direct):** External function directly writes the variable
- **D1 (one hop):** External -> internal function writes the variable
- **D2 (two hops):** External -> internal -> internal writes the variable
- **D3+ (deep):** Three or more hops

### Anti-Patterns to Avoid

- **Forward-only tracing:** The ticket queue swap vulnerability survived 10+ VRF audit passes because audits only traced forward from VRF delivery. Always trace backward from each outcome.
- **Ignoring cross-contract calls:** `coinflip.processCoinflipPayouts` and `sdgnrs.resolveRedemptionPeriod` are cross-contract calls from the game contract. Their storage is separate but their inputs come from game state.
- **Conflating "read during fulfillment" with "read during outcome computation":** `rawFulfillRandomWords` itself reads very little (just `vrfCoordinator`, `vrfRequestId`, `rngWordCurrent`, `rngLockedFlag`). The real surface is in the downstream processing during the next `advanceGame` call.
- **Missing the double-buffer:** The ticket queue uses a double-buffer (`ticketWriteSlot`, `TICKET_SLOT_BIT`). New ticket purchases write to the write slot; processing reads from the read slot. `_swapAndFreeze` swaps them at RNG request time, which is a critical commitment boundary.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Storage slot numbers | Manual counting | `forge inspect DegenerusGameStorage storage-layout` | Authoritative, accounts for packing, mapping slot derivation |
| BurnieCoinflip slots | Manual counting | `forge inspect BurnieCoinflip storage-layout` | Separate contract, separate storage |
| StakedDegenerusStonk slots | Manual counting | `forge inspect StakedDegenerusStonk storage-layout` | Separate contract, separate storage |
| Call graph depth | Mental tracing | Systematic grep + follow through delegatecall boundaries | delegatecall modules share DegenerusGame storage but have separate code |

## Common Pitfalls

### Pitfall 1: Missing the delegatecall boundary

**What goes wrong:** Treating module functions as separate-contract calls and missing that they share DegenerusGame's storage.
**Why it happens:** DegenerusGameAdvanceModule, JackpotModule, MintModule, EndgameModule, etc. are all deployed separately but execute via `delegatecall` -- their code runs against DegenerusGame's storage slots.
**How to avoid:** All modules inherit `DegenerusGameStorage`. Any variable in that storage layout is accessible by any module. When tracing writes, check ALL modules, not just the one containing the function.
**Warning signs:** Finding a variable "only written by JackpotModule" -- it may be writable by MintModule too via a different function.

### Pitfall 2: Missing the two VRF fulfillment paths

**What goes wrong:** Only cataloging the daily RNG path and missing the mid-day lootbox RNG path.
**Why it happens:** The mid-day path is less obvious -- it writes directly in `rawFulfillRandomWords` rather than going through `rngGate`.
**How to avoid:** `rawFulfillRandomWords` has an `if (rngLockedFlag)` branch. The `else` branch is the mid-day path that directly writes `lootboxRngWordByIndex[index]`. Both paths must be cataloged.
**Warning signs:** Only seeing `rngWordCurrent` writes and missing `lootboxRngWordByIndex` writes in the fulfillment function.

### Pitfall 3: Confusing "VRF fulfillment reads" with "outcome computation reads"

**What goes wrong:** Listing only variables read inside `rawFulfillRandomWords` itself (which is very few) and missing the much larger set read during downstream processing.
**Why it happens:** `rawFulfillRandomWords` is a thin callback that mostly just stores the word. The real outcome computation happens in the next `advanceGame` call.
**How to avoid:** The forward trace MUST follow from `rawFulfillRandomWords` through `advanceGame -> rngGate` and ALL downstream consumers. The backward trace catches anything the forward trace misses.
**Warning signs:** A catalog with only 5-10 variables is almost certainly incomplete.

### Pitfall 4: Missing BurnieCoinflip as a separate storage domain

**What goes wrong:** Only cataloging DegenerusGameStorage variables and missing BurnieCoinflip's own storage (separate contract, not delegatecall).
**Why it happens:** `coinflip.processCoinflipPayouts` is a regular external call, not delegatecall. BurnieCoinflip has its own storage at its own address.
**How to avoid:** Catalog BurnieCoinflip storage variables that `processCoinflipPayouts` reads/writes. Use `forge inspect BurnieCoinflip storage-layout` for slots.
**Warning signs:** The coinflip outcome variables (`coinflipDayResult`, `coinflipBalance`, `flipsClaimableDay`) are in BurnieCoinflip's storage, not DegenerusGameStorage.

### Pitfall 5: Ignoring the backfill paths

**What goes wrong:** Missing the gap-day backfill (`_backfillGapDays`) and orphaned lootbox backfill (`_backfillOrphanedLootboxIndices`) paths.
**Why it happens:** These are edge-case paths for VRF stall recovery.
**How to avoid:** Include these in the forward trace. They write `rngWordByDay`, `lootboxRngWordByIndex`, `lastLootboxRngWord`, and call `coinflip.processCoinflipPayouts`.

## Code Examples

### Key Entry Points for Tracing

**rawFulfillRandomWords (AdvanceModule lines 1436-1457):**
```solidity
function rawFulfillRandomWords(
    uint256 requestId,
    uint256[] calldata randomWords
) external {
    if (msg.sender != address(vrfCoordinator)) revert E();
    if (requestId != vrfRequestId || rngWordCurrent != 0) return;

    uint256 word = randomWords[0];
    if (word == 0) word = 1;

    if (rngLockedFlag) {
        // Daily RNG: store for advanceGame processing
        rngWordCurrent = word;
    } else {
        // Mid-day RNG: directly finalize lootbox
        uint48 index = lootboxRngIndex - 1;
        lootboxRngWordByIndex[index] = word;
        emit LootboxRngApplied(index, word, requestId);
        vrfRequestId = 0;
        rngRequestTime = 0;
    }
}
```

**VRF Word Bit Allocation (AdvanceModule lines 743-760):**
```
Bit(s)   Consumer                    Operation
0        Coinflip win/loss           rngWord & 1
8+       Redemption roll             (currentWord >> 8) % 151 + 25
full     Coinflip reward percent     keccak256(rngWord, epoch) % 20
full     Jackpot winner selection    via delegatecall (full word)
full     Coin jackpot                via delegatecall (full word)
full     Lootbox RNG                 stored as lootboxRngWordByIndex
full     Future take variance        rngWord % (variance * 2 + 1)
full     Prize pool consolidation    via delegatecall (full word)
full     Final day DGNRS reward      via delegatecall (full word)
full     Reward jackpots             via delegatecall (full word)
```

### forge inspect Usage

```bash
# DegenerusGameStorage (shared by DegenerusGame + all delegatecall modules)
forge inspect DegenerusGameStorage storage-layout

# BurnieCoinflip (separate contract, separate storage)
forge inspect BurnieCoinflip storage-layout

# StakedDegenerusStonk (separate contract, called by resolveRedemptionPeriod)
forge inspect StakedDegenerusStonk storage-layout
```

### Key Storage Slot Reference (from forge inspect)

**DegenerusGameStorage (107 slots):**

| Slot | Variables | Relevance to VRF |
|------|-----------|-------------------|
| 0 | levelStartTime, dailyIdx, rngRequestTime, level, jackpotPhaseFlag, jackpotCounter, poolConsolidationDone, lastPurchaseDay, decWindowOpen, **rngLockedFlag**, phaseTransitionActive, gameOver, dailyJackpotCoinTicketsPending, dailyEthBucketCursor, dailyEthPhase | Core FSM -- rngLockedFlag is the commitment window latch |
| 1 | compressedJackpotFlag, purchaseStartDay, price, **ticketWriteSlot**, **ticketsFullyProcessed**, **prizePoolFrozen** | Double-buffer and freeze controls |
| 2 | currentPrizePool | Jackpot source pool |
| 3 | prizePoolsPacked (next + future) | Pool management |
| 4 | **rngWordCurrent** | VRF word staging |
| 5 | **vrfRequestId** | Request matching |
| 6 | **totalFlipReversals** | Nudge accumulator |
| 7 | dailyTicketBudgetsPacked | Jackpot ticket budgets |
| 8 | dailyEthPoolBudget | Jackpot ETH budget |
| 9 | claimableWinnings (mapping) | Winner payouts |
| 10 | claimablePool | Aggregate liability |
| 11 | traitBurnTicket (mapping) | Jackpot winner selection pool |
| 12 | mintPacked_ (mapping) | Player mint state |
| 13 | **rngWordByDay** (mapping) | Historical RNG words |
| 14 | prizePoolPendingPacked | Freeze accumulators |
| 15 | **ticketQueue** (mapping) | Ticket double-buffer |
| 16 | ticketsOwedPacked (mapping) | Per-player ticket counts |
| 17 | ticketCursor, ticketLevel, dailyEthWinnerCursor | Processing cursors |
| 42 | lastDailyJackpotWinningTraits, lastDailyJackpotLevel, lastDailyJackpotDay | Jackpot resume state |
| 60 | **lootboxRngIndex** | Lootbox RNG cursor |
| 64 | **lootboxRngWordByIndex** (mapping) | Lootbox entropy storage |
| 70 | **lastLootboxRngWord** | Ticket processing entropy |
| 71 | **midDayTicketRngPending** | Mid-day ticket swap flag |
| 103 | **lastVrfProcessedTimestamp** | VRF processing timestamp |

**BurnieCoinflip (6 slots):**

| Slot | Variable | Relevance |
|------|----------|-----------|
| 0 | coinflipBalance (mapping) | Player bet amounts per day |
| 1 | **coinflipDayResult** (mapping) | Win/loss + reward percent (written by processCoinflipPayouts) |
| 2 | playerState (mapping) | Player coinflip mode state |
| 3 | **currentBounty**, biggestFlipEver | Bounty pool (written by processCoinflipPayouts) |
| 4 | **bountyOwedTo**, **flipsClaimableDay** | Bounty recipient, claimable window (written by processCoinflipPayouts) |
| 5 | coinflipTopByDay (mapping) | Leaderboard (not written by processCoinflipPayouts) |

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Forward-only VRF tracing | Forward + backward tracing | v3.7 (feedback) | The ticket queue swap bug survived 10+ forward-only audit passes. Backward tracing from outcomes is mandatory. |
| Single VRF path | Two VRF paths (daily + mid-day) | v3.4 (lootbox redesign) | Mid-day `requestLootboxRng` path must be included in inventory |
| No double-buffer | Ticket queue double-buffer | Code architecture | `_swapAndFreeze` at RNG request time is a commitment boundary |

## External Function Inventory (Mutation Surface Candidates)

These are ALL external/public state-mutating functions callable by non-admin actors during the commitment window. The plan must trace which variables each function writes.

### DegenerusGame (via delegatecall to modules)

| Function | Module | Key Variables Written |
|----------|--------|----------------------|
| `advanceGame()` | AdvanceModule | Many (this IS the processing path) |
| `purchase()` | MintModule | `ticketQueue`, `ticketsOwedPacked`, `mintPacked_`, prize pools, `lootboxEth`, `lootboxRngPendingEth` |
| `purchaseCoin()` | MintModule | `ticketsOwedPacked`, coin balances |
| `purchaseBurnieLootbox()` | MintModule | `lootboxBurnie`, `lootboxRngPendingBurnie` |
| `openLootBox()` | LootboxModule | `lootboxEth`, `claimableWinnings`, `claimablePool`, boon state |
| `openBurnieLootBox()` | LootboxModule | `lootboxBurnie`, boon state |
| `purchaseLazyPass()` | MintModule | `mintPacked_`, `ticketQueue`, `ticketsOwedPacked` |
| `purchaseDeityPass()` | Game directly | `deityPassCount`, `deityPassOwners`, tickets |
| `claimWinnings()` | Game directly | `claimableWinnings`, `claimablePool` |
| `claimDecimatorJackpot()` | DecimatorModule | `claimableWinnings`, `claimablePool`, decimator state |
| `claimWhalePass()` | Game directly | `whalePassClaims`, `ticketQueue`, `ticketsOwedPacked` |
| `reverseFlip()` | AdvanceModule | `totalFlipReversals` |
| `requestLootboxRng()` | AdvanceModule | `lootboxRngIndex`, VRF state, ticket buffer swap |
| `setAutoRebuy()` | Game directly | `autoRebuyState` |
| `setOperatorApproval()` | Game directly | `operatorApprovals` |
| `placeFullTicketBets()` | DegeneretteModule | `degeneretteBets`, `degeneretteBetNonce` |

### BurnieCoinflip (separate contract, separate storage)

| Function | Key Variables Written |
|----------|----------------------|
| `depositCoinflip()` | `coinflipBalance[day][player]`, `playerState[player]` |

### StakedDegenerusStonk (separate contract)

| Function | Key Variables Written |
|----------|----------------------|
| `burn()` / `burnWrapped()` | Token balances, possibly triggers redemption |
| `claimRedemption()` | Redemption state |

### DegenerusStonk (DGNRS token)

| Function | Key Variables Written |
|----------|----------------------|
| `burn()` | Token balances, ETH/stETH distribution |

## Validation Architecture

### Test Framework

| Property | Value |
|----------|-------|
| Framework | Foundry (forge test) |
| Config file | `foundry.toml` |
| Quick run command | `forge test --match-path test/fuzz/*.sol -vv` |
| Full suite command | `forge test -vv` |

### Phase Requirements to Test Map

| Req ID | Behavior | Test Type | Automated Command | File Exists? |
|--------|----------|-----------|-------------------|-------------|
| CW-01 | Forward-trace catalog completeness | manual-only | N/A | N/A |
| CW-02 | Backward-trace catalog completeness | manual-only | N/A | N/A |
| CW-03 | Mutation surface completeness | manual-only | N/A | N/A |

**Justification for manual-only:** This phase produces a documentation artifact (catalog), not code. The catalog's correctness is verified by manual review against the source code. Automated tests cannot verify "is this list complete?" -- only human review of the source can confirm no variables were missed. The validation is inherent in the systematic methodology (forward + backward trace + grep for mutation surfaces).

### Wave 0 Gaps

None -- existing test infrastructure covers all phase requirements. No new test files needed for this documentation-only phase.

## Open Questions

1. **StakedDegenerusStonk internal storage**
   - What we know: `resolveRedemptionPeriod` is called from rngGate with the RNG word. It writes internal redemption state.
   - What's unclear: The exact storage variables written inside sDGNRS need to be cataloged for completeness.
   - Recommendation: Run `forge inspect StakedDegenerusStonk storage-layout` and trace `resolveRedemptionPeriod` internally.

2. **DegenerusJackpots contract**
   - What we know: `DegenerusJackpots.sol` exists as a separate contract, not a delegatecall module.
   - What's unclear: Whether any VRF-dependent computation paths route through it.
   - Recommendation: Check if any jackpot functions in JackpotModule make external calls to DegenerusJackpots. If so, catalog its storage too.

3. **Degenerette (roulette) RNG dependency**
   - What we know: `degeneretteBets` storage exists with an RNG index field (bits 172-219).
   - What's unclear: Whether Degenerette resolution reads VRF words and which ones.
   - Recommendation: Trace the Degenerette resolution path to determine if it reads `lootboxRngWordByIndex` or `rngWordByDay`.

## Sources

### Primary (HIGH confidence)

- `forge inspect DegenerusGameStorage storage-layout` -- Authoritative slot assignments for all 107 storage variables
- `forge inspect BurnieCoinflip storage-layout` -- Authoritative slot assignments for BurnieCoinflip's 6 storage variables
- Direct source code analysis of:
  - `contracts/modules/DegenerusGameAdvanceModule.sol` (1552 lines) -- VRF lifecycle, rngGate, rawFulfillRandomWords
  - `contracts/storage/DegenerusGameStorage.sol` -- Complete storage layout with inline documentation
  - `contracts/BurnieCoinflip.sol` -- processCoinflipPayouts, depositCoinflip
  - `contracts/modules/DegenerusGameJackpotModule.sol` -- payDailyJackpot, processTicketBatch
  - `contracts/DegenerusGame.sol` -- External function surface (proxy to modules)

### Secondary (MEDIUM confidence)

- Prior audit findings from v3.7 (`audit/v3.7-vrf-core-findings.md`, `audit/v3.7-vrf-stall-findings.md`) -- STALL-04 state reset analysis, STALL-05 zero-seed analysis
- Prior audit findings from v3.6 (`audit/v3.6-findings-consolidated.md`) -- midDayTicketRngPending context

### Tertiary (LOW confidence)

- Project memory notes on backward-trace methodology and commitment window methodology -- methodology is verified by prior bug discovery, but specific variable lists need fresh verification against current code

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH -- `forge inspect` is authoritative for slot numbers, no external tools needed
- Architecture: HIGH -- Complete call graph traced through source code, two VRF paths identified
- Pitfalls: HIGH -- Drawn from real bugs found in prior audit phases (ticket queue swap survived 10+ passes)

**Research date:** 2026-03-22
**Valid until:** 2026-04-22 (stable -- Solidity contracts don't change between audits)
