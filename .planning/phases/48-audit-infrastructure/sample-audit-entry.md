# Sample Audit Entry

Demonstrates the `function-audit-schema.json` applied to a real function from the Degenerus protocol audit.

**Source:** `advanceGame()` from Phase 50 AdvanceModule audit (`50-01-advance-module-audit.md`)

---

## Markdown Format (as used in Phase 50-57 reports)

### `advanceGame()` [external]

| Field | Value |
|-------|-------|
| **Signature** | `function advanceGame() external` |
| **Visibility** | external |
| **Mutability** | state-changing |
| **Parameters** | None |
| **Returns** | None |

**State Reads:**
- `msg.sender` (caller for mint-gate and bounty)
- `block.timestamp` (ts)
- `_simulatedDayIndexAt(ts)` -> `day` (inherited from GameTimeLib via Storage)
- `jackpotPhaseFlag` (inJackpot)
- `level` (lvl)
- `lastPurchaseDay` (lastPurchase)
- `rngLockedFlag` (used in purchaseLevel calculation)
- `dailyIdx` (passed to _handleGameOverPath and _enforceDailyMintGate)
- `levelStartTime` (passed to _handleGameOverPath)
- `phaseTransitionActive` (phase transition state)
- `jackpotCounter` (jackpot day counter)
- `dailyJackpotCoinTicketsPending` (split jackpot pending flag)
- `dailyEthPoolBudget`, `dailyEthPhase`, `dailyEthBucketCursor`, `dailyEthWinnerCursor` (resume state)
- `rngWordByDay[day]` (via rngGate)
- `rngWordCurrent`, `rngRequestTime` (via rngGate)
- `nextPrizePool`, `levelPrizePool[purchaseLevel - 1]` (target check)
- `poolConsolidationDone` (consolidation guard)
- `ticketCursor`, `ticketLevel` (via _runProcessTicketBatch)
- `lastDailyJackpotLevel` (resume level for split ETH)
- `lootboxPresaleActive`, `lootboxPresaleMintEth` (presale auto-end)

**State Writes:**
- `lastPurchaseDay = true` (when nextPrizePool >= target)
- `compressedJackpotFlag = (day - purchaseStartDay <= 2)` (compressed mode check)
- `levelPrizePool[purchaseLevel] = nextPrizePool` (prize pool snapshot)
- `poolConsolidationDone = true` (consolidation guard)
- `lootboxPresaleActive = false` (presale auto-end)
- `earlyBurnPercent = 0` (reset at jackpot entry)
- `jackpotPhaseFlag = true` (transition to jackpot)
- `decWindowOpen = true` (open decimator at x4/x99 levels)
- `poolConsolidationDone = false` (reset for next cycle)
- `lastPurchaseDay = false` (reset at jackpot entry)
- `levelStartTime = ts` (new level start time)
- `phaseTransitionActive = false` (transition complete)
- `purchaseStartDay = day` (new purchase start)
- `jackpotPhaseFlag = false` (back to purchase)
- Via `_unlockRng(day)`: `dailyIdx = day`, `rngLockedFlag = false`, `rngWordCurrent = 0`, `vrfRequestId = 0`, `rngRequestTime = 0`
- Via delegatecall sub-modules: various prize pool, ticket, jackpot state

**Callers:**
- External callers (any address, subject to mint-gate). Called via delegatecall from DegenerusGame.

**Callees:**
- `_simulatedDayIndexAt(ts)` (inherited helper)
- `_handleGameOverPath(ts, day, levelStartTime, lvl, lastPurchase, dailyIdx)` (private)
- `_enforceDailyMintGate(caller, purchaseLevel, dailyIdx)` (private)
- `rngGate(ts, day, purchaseLevel, lastPurchase)` (internal)
- `_processPhaseTransition(purchaseLevel)` (private)
- `_unlockRng(day)` (private)
- `_prepareFinalDayFutureTickets(lvl)` (private)
- `_runProcessTicketBatch(purchaseLevel)` (private)
- `payDailyJackpot(isDaily, lvl, rngWord)` (internal, delegatecall to JackpotModule)
- `_payDailyCoinJackpot(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_applyTimeBasedFutureTake(ts, purchaseLevel, rngWord)` (private)
- `_consolidatePrizePools(purchaseLevel, rngWord)` (private, delegatecall to JackpotModule)
- `_drawDownFuturePrizePool(lvl)` (private)
- `_processFutureTicketBatch(nextLevel)` (private, delegatecall to MintModule)
- `payDailyJackpotCoinAndTickets(rngWord)` (internal, delegatecall to JackpotModule)
- `_awardFinalDayDgnrsReward(lvl, rngWord)` (private, delegatecall to JackpotModule)
- `_rewardTopAffiliate(lvl)` (private, delegatecall to EndgameModule)
- `_runRewardJackpots(lvl, rngWord)` (private, delegatecall to EndgameModule)
- `_endPhase()` (private)
- `coin.creditFlip(caller, ADVANCE_BOUNTY)` (external call to DegenerusCoin)

**ETH Flow:**
- No direct ETH transfers in `advanceGame` itself.
- ETH is moved indirectly through delegatecall sub-modules:
  - `payDailyJackpot` -> currentPrizePool/futurePrizePool -> claimableWinnings (player credits)
  - `_consolidatePrizePools` -> nextPrizePool -> currentPrizePool, futurePrizePool adjustments
  - `_applyTimeBasedFutureTake` -> nextPrizePool -> futurePrizePool (time-based skim)
  - `_drawDownFuturePrizePool` -> futurePrizePool -> nextPrizePool (15% release)
  - `_autoStakeExcessEth` (via _processPhaseTransition) -> excess ETH -> stETH via Lido

**Invariants:**
- `advanceGame` cannot be called twice within the same day (reverts `NotTimeYet` if `day == dailyIdx`)
- Mint-gate: caller must have minted today (with time-based and pass-based bypasses)
- Game-over path takes priority and returns early
- Phase transitions are mutually exclusive: purchase phase XOR jackpot phase
- `poolConsolidationDone` prevents double consolidation
- Level increment happens at RNG request time (not at advance time) to prevent manipulation
- `jackpotCounter` caps at `JACKPOT_LEVEL_CAP = 5` before triggering phase end
- ADVANCE_BOUNTY (500 BURNIE flip credit) always awarded to caller after processing

**NatSpec Accuracy:**
- Line 118-119: NatSpec says "Called daily to process jackpots, mints, and phase transitions" -- ACCURATE.
- NatSpec says "Caller receives ADVANCE_BOUNTY (500 BURNIE) as flip credit" -- ACCURATE.

**Gas Flags:**
- The `do { ... } while(false)` pattern is a clean single-pass state machine with `break` for early exits. No wasted iteration.
- `purchaseLevel` computation reads `rngLockedFlag` even when `lastPurchase` is false (minor: the branch is only taken when both are true, so no wasted SLOAD in practice due to short-circuit).

**Verdict:** CORRECT

---

## JSON Format (conforming to function-audit-schema.json)

The same `advanceGame()` entry expressed as a `FunctionAudit` object:

```json
{
  "name": "advanceGame",
  "signature": "function advanceGame() external",
  "visibility": "external",
  "mutability": "state-changing",
  "parameters": [],
  "returns": [],
  "stateReads": [
    "msg.sender (caller for mint-gate and bounty)",
    "block.timestamp (ts)",
    "_simulatedDayIndexAt(ts) -> day (inherited from GameTimeLib via Storage)",
    "jackpotPhaseFlag (inJackpot)",
    "level (lvl)",
    "lastPurchaseDay (lastPurchase)",
    "rngLockedFlag (used in purchaseLevel calculation)",
    "dailyIdx (passed to _handleGameOverPath and _enforceDailyMintGate)",
    "levelStartTime (passed to _handleGameOverPath)",
    "phaseTransitionActive (phase transition state)",
    "jackpotCounter (jackpot day counter)",
    "dailyJackpotCoinTicketsPending (split jackpot pending flag)",
    "dailyEthPoolBudget, dailyEthPhase, dailyEthBucketCursor, dailyEthWinnerCursor (resume state)",
    "rngWordByDay[day] (via rngGate)",
    "rngWordCurrent, rngRequestTime (via rngGate)",
    "nextPrizePool, levelPrizePool[purchaseLevel - 1] (target check)",
    "poolConsolidationDone (consolidation guard)",
    "ticketCursor, ticketLevel (via _runProcessTicketBatch)",
    "lastDailyJackpotLevel (resume level for split ETH)",
    "lootboxPresaleActive, lootboxPresaleMintEth (presale auto-end)"
  ],
  "stateWrites": [
    "lastPurchaseDay = true (when nextPrizePool >= target)",
    "compressedJackpotFlag = (day - purchaseStartDay <= 2)",
    "levelPrizePool[purchaseLevel] = nextPrizePool (prize pool snapshot)",
    "poolConsolidationDone = true (consolidation guard)",
    "lootboxPresaleActive = false (presale auto-end)",
    "earlyBurnPercent = 0 (reset at jackpot entry)",
    "jackpotPhaseFlag = true (transition to jackpot)",
    "decWindowOpen = true (open decimator at x4/x99 levels)",
    "poolConsolidationDone = false (reset for next cycle)",
    "lastPurchaseDay = false (reset at jackpot entry)",
    "levelStartTime = ts (new level start time)",
    "phaseTransitionActive = false (transition complete)",
    "purchaseStartDay = day (new purchase start)",
    "jackpotPhaseFlag = false (back to purchase)",
    "Via _unlockRng(day): dailyIdx, rngLockedFlag, rngWordCurrent, vrfRequestId, rngRequestTime",
    "Via delegatecall sub-modules: various prize pool, ticket, jackpot state"
  ],
  "callers": [
    {
      "function": "external callers (any address, subject to mint-gate)",
      "contract": "DegenerusGame",
      "callType": "delegatecall"
    }
  ],
  "callees": [
    { "function": "_simulatedDayIndexAt", "callType": "internal" },
    { "function": "_handleGameOverPath", "callType": "internal" },
    { "function": "_enforceDailyMintGate", "callType": "internal" },
    { "function": "rngGate", "callType": "internal" },
    { "function": "_processPhaseTransition", "callType": "internal" },
    { "function": "_unlockRng", "callType": "internal" },
    { "function": "_prepareFinalDayFutureTickets", "callType": "internal" },
    { "function": "_runProcessTicketBatch", "callType": "internal" },
    { "function": "payDailyJackpot", "contract": "JackpotModule", "callType": "delegatecall" },
    { "function": "_payDailyCoinJackpot", "contract": "JackpotModule", "callType": "delegatecall" },
    { "function": "_applyTimeBasedFutureTake", "callType": "internal" },
    { "function": "_consolidatePrizePools", "contract": "JackpotModule", "callType": "delegatecall" },
    { "function": "_drawDownFuturePrizePool", "callType": "internal" },
    { "function": "_processFutureTicketBatch", "contract": "MintModule", "callType": "delegatecall" },
    { "function": "payDailyJackpotCoinAndTickets", "contract": "JackpotModule", "callType": "delegatecall" },
    { "function": "_awardFinalDayDgnrsReward", "contract": "JackpotModule", "callType": "delegatecall" },
    { "function": "_rewardTopAffiliate", "contract": "EndgameModule", "callType": "delegatecall" },
    { "function": "_runRewardJackpots", "contract": "EndgameModule", "callType": "delegatecall" },
    { "function": "_endPhase", "callType": "internal" },
    { "function": "creditFlip", "contract": "DegenerusCoin", "callType": "external" }
  ],
  "ethFlow": {
    "hasEthFlow": true,
    "details": "No direct ETH transfers in advanceGame itself. ETH is moved indirectly through delegatecall sub-modules.",
    "paths": [
      {
        "source": "currentPrizePool/futurePrizePool",
        "destination": "claimableWinnings (player credits)",
        "description": "payDailyJackpot distributes prize pool to winners"
      },
      {
        "source": "nextPrizePool",
        "destination": "currentPrizePool + futurePrizePool",
        "description": "_consolidatePrizePools merges and rebalances pools"
      },
      {
        "source": "nextPrizePool",
        "destination": "futurePrizePool",
        "description": "_applyTimeBasedFutureTake skims based on time curve BPS"
      },
      {
        "source": "futurePrizePool",
        "destination": "nextPrizePool",
        "description": "_drawDownFuturePrizePool releases 15% on normal levels"
      },
      {
        "source": "address(this).balance - claimablePool",
        "destination": "stETH (Lido)",
        "description": "_autoStakeExcessEth via _processPhaseTransition"
      }
    ]
  },
  "invariants": [
    "advanceGame cannot be called twice within the same day (reverts NotTimeYet if day == dailyIdx)",
    "Mint-gate: caller must have minted today (with time-based and pass-based bypasses)",
    "Game-over path takes priority and returns early",
    "Phase transitions are mutually exclusive: purchase phase XOR jackpot phase",
    "poolConsolidationDone prevents double consolidation",
    "Level increment happens at RNG request time (not at advance time) to prevent manipulation",
    "jackpotCounter caps at JACKPOT_LEVEL_CAP = 5 before triggering phase end",
    "ADVANCE_BOUNTY (500 BURNIE flip credit) always awarded to caller after processing"
  ],
  "natspecAccuracy": {
    "accurate": true,
    "notes": "NatSpec says 'Called daily to process jackpots, mints, and phase transitions' -- accurate. 'Caller receives ADVANCE_BOUNTY (500 BURNIE) as flip credit' -- accurate."
  },
  "gasFlags": [
    {
      "type": "other",
      "description": "do { ... } while(false) pattern is a clean single-pass state machine with break for early exits. No wasted iteration.",
      "severity": "info"
    },
    {
      "type": "redundant-read",
      "description": "purchaseLevel computation reads rngLockedFlag even when lastPurchase is false (minor: branch only taken when both true, no wasted SLOAD due to short-circuit)",
      "severity": "info"
    }
  ],
  "verdict": "CORRECT"
}
```

---

## Field Mapping

How the markdown audit format maps to `FunctionAudit` JSON schema fields:

| Markdown Field | JSON Path | Notes |
|---|---|---|
| **Signature** | `signature` | Full Solidity function signature string |
| **Visibility** | `visibility` | Enum: `external` / `public` / `internal` / `private` |
| **Mutability** | `mutability` | Enum: `state-changing` / `view` / `pure` |
| **Parameters** | `parameters[]` | Array of `{name, type, description}` objects. Empty array when "None" |
| **Returns** | `returns[]` | Array of `{type, name?, description}` objects. Empty array when "None" |
| **State Reads** | `stateReads[]` | Bullet list becomes string array. Each item includes variable name and context |
| **State Writes** | `stateWrites[]` | Bullet list becomes string array. Each item includes assignment and context |
| **Callers** | `callers[]` | Array of `{function, contract?, callType}`. Markdown prose parsed into structured entries |
| **Callees** | `callees[]` | Array of `{function, contract?, callType}`. Each bullet becomes an entry with call type classification |
| **ETH Flow** | `ethFlow` | Object with `hasEthFlow` boolean, `details` string, and `paths[]` array. Set to `null` when "None" |
| **Invariants** | `invariants[]` | Bullet list becomes string array |
| **NatSpec Accuracy** | `natspecAccuracy` | Object with `accurate` boolean and `notes` string. Markdown prose condensed |
| **Gas Flags** | `gasFlags[]` | Array of `{type, description, severity}`. Each gas observation becomes a typed entry |
| **Verdict** | `verdict` | Enum: `CORRECT` / `CONCERN` / `BUG`. Verdict notes in separate `verdictNotes` field |

### Key Differences Between Formats

1. **Structured vs. prose**: The markdown format uses free-form bullets and paragraphs. The JSON format requires structured objects with typed fields, making it machine-parseable.

2. **Callers/Callees**: In markdown, these are prose descriptions ("External callers via delegatecall from DegenerusGame"). In JSON, each caller/callee is a discrete object with `function`, `contract`, and `callType` fields.

3. **ETH Flow**: The markdown format is a paragraph with nested bullets. The JSON format separates the boolean flag (`hasEthFlow`), the summary (`details`), and individual flow paths into a structured object.

4. **Gas Flags**: In markdown, these are descriptive paragraphs. In JSON, each is classified by `type` (impossible-condition, redundant-read, unnecessary-computation, other) and `severity` (high, medium, low, info).

5. **NatSpec**: The markdown format includes inline quotes and accuracy assessment. The JSON format distills this to a boolean (`accurate`) and a notes string.

---

*Schema: `function-audit-schema.json` (JSON Schema draft 2020-12)*
*Source: Phase 50 AdvanceModule audit (`50-01-advance-module-audit.md`)*
