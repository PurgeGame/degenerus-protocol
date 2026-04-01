# Phase 151: Endgame Flag Implementation - Context

**Gathered:** 2026-03-31
**Status:** Ready for planning

<domain>
## Phase Boundary

Replace the 30-day BURNIE ticket purchase ban with a drip-projection-based endgame flag. The flag dynamically restricts BURNIE ticket purchases only when a level could mechanically be the last -- determined by whether remaining futurePool drip can cover the nextPool deficit. Removes all elapsed-time cutoff logic from MintModule and LootboxModule.

</domain>

<decisions>
## Implementation Decisions

### Drip Projection Math
- **D-01:** Projection rate is 0.75% (75 BPS) per day, deliberately conservative vs the actual 1% daily drip. Use exactly as specified in DRIP-01.
- **D-02:** Use the closed-form geometric series: `totalDrip = futurePool * (1 - 0.9925^n)`. Single exponentiation via repeated squaring, not iterative loop.
- **D-03:** WAD-scale (1e18) fixed-point arithmetic for the exponentiation. 0.9925 represented as 992500000000000000. Exponent n can be up to ~120 days.

### Flag Lifecycle & Storage
- **D-04:** Flag evaluation threshold is L10+ (level >= 10). ROADMAP says L11+ but REQUIREMENTS FLAG-01 is authoritative.
- **D-05:** Flag evaluation runs inside advanceGame, on purchase-phase entry and daily progression. No new entry points.
- **D-06:** Flag storage packed into an existing storage slot (near lastPurchaseDay or jackpotPhaseFlag). Zero additional cold SSTORE cost.
- **D-07:** Flag auto-clears the moment lastPurchaseDay is set (nextPool target met). BURNIE purchases reopen for the final day since the level is confirmed to not be terminal.

### BURNIE Lootbox Redirect
- **D-08:** When endgame flag is active and _rollTargetLevel produces currentLevel, redirect to far-future key space (bit 22: `currentLevel | (1 << 22)`). NOT the old +2 shift.
- **D-09:** Only current-level ticket rolls redirect. Near-future rolls (currentLevel+1..+6) land normally even when flag is active.

### Removal Scope
- **D-10:** Delete from MintModule: `COIN_PURCHASE_CUTOFF`, `COIN_PURCHASE_CUTOFF_LVL0`, `CoinPurchaseCutoff` error, and the elapsed-time revert check at line 615-617.
- **D-11:** Delete from LootboxModule: `BURNIE_LOOT_CUTOFF`, `BURNIE_LOOT_CUTOFF_LVL0`, and the elapsed-time redirect check at lines 648-657.
- **D-12:** Audit ALL other "30 days" references across contracts to confirm none are related to the BURNIE ban. GameOverModule:190 (final sweep) and similar are expected to be unrelated.
- **D-13:** Replace `CoinPurchaseCutoff` error with a new name reflecting the endgame flag mechanism (e.g., `EndgameFlagActive`).

### Claude's Discretion
- Exact storage packing slot choice (whichever existing field offers the cheapest pack)
- Internal function naming and organization
- Specific error name (must reflect endgame flag, not elapsed-time cutoff)

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Requirements
- `.planning/REQUIREMENTS.md` -- REM-01, FLAG-01 through FLAG-04, DRIP-01, DRIP-02, ENF-01 through ENF-03

### Existing Code (modification targets)
- `contracts/modules/DegenerusGameMintModule.sol` -- Lines 66-67 (error), 119-120 (constants), 614-617 (ban check), 1044-1076 (BURNIE lootbox purchase)
- `contracts/modules/DegenerusGameLootboxModule.sol` -- Lines 187-190 (constants), 640-683 (BURNIE lootbox open with redirect)
- `contracts/modules/DegenerusGameAdvanceModule.sol` -- advanceGame entry point for flag evaluation
- `contracts/modules/DegenerusGameJackpotModule.sol` -- Lines 597-607 (existing 1% daily drip for reference)
- `contracts/storage/DegenerusGameStorage.sol` -- Lines 254 (lastPurchaseDay), 228 (jackpotPhaseFlag), storage layout for packing

### Far-future ticket system (existing)
- Bit 22 key space established in v3.9 (Phase 74-80) -- reuse for endgame flag redirect

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `_getFuturePrizePool()` / `_setFuturePrizePool()` -- existing futurePool accessors in storage
- `lastPurchaseDay` bool -- existing flag that signals nextPool target met
- Far-future ticket routing (bit 22 key space) -- established pattern for redirecting tickets
- `_rollTargetLevel()` in LootboxModule -- existing level targeting logic
- WAD-scale math patterns may exist in other contracts (check during planning)

### Established Patterns
- Storage packing with bit shifts (GameStorage uses packed uint256 fields extensively)
- Flag checks in advanceGame flow (jackpotPhaseFlag, lastPurchaseDay already checked there)
- Error naming convention: PascalCase descriptive errors (E() for generic, named errors for specific conditions)

### Integration Points
- advanceGame in AdvanceModule -- flag evaluation on purchase-phase entry and daily ticks
- _purchaseBurnieFor in MintModule -- flag check replacing elapsed-time revert
- BURNIE lootbox resolution in LootboxModule -- flag check replacing elapsed-time redirect
- GameStorage -- new packed bool for endgame flag

</code_context>

<specifics>
## Specific Ideas

- Conservative 0.75% projection rate vs 1% actual drip is intentional -- accounts for drip not fully reaching nextPool
- lastPurchaseDay clears the flag immediately (not at level advance) -- BURNIE purchases should reopen since the level is confirmed non-terminal
- Far-future redirect uses bit 22, not +2 offset -- stronger guarantee that redirected tickets don't compete for terminal jackpot

</specifics>

<deferred>
## Deferred Ideas

None -- discussion stayed within phase scope

</deferred>

---

*Phase: 151-endgame-flag-implementation*
*Context gathered: 2026-03-31*
