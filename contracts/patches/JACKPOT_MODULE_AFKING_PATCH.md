# Jackpot Module afKing Auto-Rebuy Patch

## Location
`contracts/modules/DegenerusGameJackpotModule.sol` - `_processAutoRebuy()` function (lines 1037-1102)

## Current Behavior
Auto-rebuy converts ALL claimable winnings to tickets (with dust remainder).

## Required Behavior with afKing
- If afKing active: Only convert complete 2 ETH multiples
- Leave fractional remainder in claimable balance
- Fractional part is player's "safe money" that won't be rebought

## Updated Function

```solidity
/// @dev Converts winnings to tickets for next level.
///      Processes ALL accumulated claimableWinnings plus the new amount.
///      Applies fixed 30% bonus (130% EV) for gas efficiency.
///
///      afKing Mode:
///      - If active: Only converts complete 2 ETH multiples
///      - Leaves fractional remainder in claimable
///      - Example: 12.5 ETH → converts 12 ETH, keeps 0.5 ETH claimable
///
/// @param player Player receiving winnings.
/// @param newAmount New winnings amount in wei.
function _processAutoRebuy(address player, uint256 newAmount) private {
    // Get existing claimable balance and combine with new amount
    uint256 existingClaimable = claimableWinnings[player];
    if (existingClaimable == 1) existingClaimable = 0; // Sentinel handling
    uint256 totalAmount = existingClaimable + newAmount;

    // Determine how much to rebuy based on afKing mode
    uint256 rebuyAmount;
    uint256 remainingClaimable;

    if (afKingMode[player]) {
        // afKing mode: Only rebuy complete 2 ETH multiples
        uint256 AFKING_MIN_ETH = 2 ether / ContractAddresses.COST_DIVISOR;
        uint256 completeThresholds = totalAmount / AFKING_MIN_ETH;
        rebuyAmount = completeThresholds * AFKING_MIN_ETH;
        remainingClaimable = totalAmount - rebuyAmount;

        // If rebuy amount is below minimum, keep all in claimable
        if (rebuyAmount < AUTO_REBUY_MIN) {
            unchecked {
                claimableWinnings[player] += newAmount;
            }
            emit PlayerCredited(player, player, newAmount);
            return;
        }
    } else {
        // Normal mode: Rebuy all (with dust remainder)
        if (totalAmount < AUTO_REBUY_MIN) {
            // Combined amount still too small, credit normally
            unchecked {
                claimableWinnings[player] += newAmount;
            }
            emit PlayerCredited(player, player, newAmount);
            return;
        }
        rebuyAmount = totalAmount;
        remainingClaimable = 0; // Will be set to dust below
    }

    // Award tickets for current level unless in BURN phase (then next level)
    uint24 currLvl = level;
    uint24 targetLevel = (gameState == GAME_STATE_BURN) ? currLvl + 1 : currLvl;

    // Get ticket price for target level
    uint256 ticketPrice = _priceForLevel(targetLevel) / 4;
    if (ticketPrice == 0) ticketPrice = 0.00625 ether;

    // Calculate base tickets from rebuy amount
    uint256 baseTickets = rebuyAmount / ticketPrice;
    if (baseTickets == 0) {
        // Shouldn't happen but be safe
        unchecked {
            claimableWinnings[player] += newAmount;
        }
        emit PlayerCredited(player, player, newAmount);
        return;
    }

    // Apply fixed 30% bonus (evScale = 13000 = 130% EV)
    uint256 bonusTickets = (baseTickets * 13000) / 10000;
    uint32 ticketCount = bonusTickets > type(uint32).max ? type(uint32).max : uint32(bonusTickets);

    uint256 ethSpent = baseTickets * ticketPrice;
    uint256 dustRemainder = rebuyAmount - ethSpent;

    // Clear existing claimable (we're consuming it)
    if (existingClaimable > 0) {
        claimableWinnings[player] = 0;
        claimablePool -= existingClaimable;
    }

    // Add tickets to player's ticketsOwed
    uint32 owed = ticketsOwed[targetLevel][player];
    if (owed == 0) owed = 1; // Sentinel for tracking
    ticketsOwed[targetLevel][player] = owed + ticketCount;

    // Credit ETH to next prize pool (backs next level tickets)
    nextPrizePool += ethSpent;

    // Handle remainders - add to claimableWinnings and claimablePool
    uint256 totalRemainder = remainingClaimable + dustRemainder;
    if (totalRemainder > 0) {
        unchecked {
            claimableWinnings[player] += totalRemainder;
            claimablePool += totalRemainder;
        }
    }

    emit AutoRebuyProcessed(player, targetLevel, ticketCount, ethSpent, totalRemainder);
}
```

## Key Changes

1. **afKing Mode Check**: Determines rebuy amount differently based on afKing status
2. **Complete Multiples**: Only converts floor(amount / 2 ETH) × 2 ETH when afKing active
3. **Fractional Remainder**: Stays in claimable balance for afKing users
4. **Dust Handling**: Combines afKing remainder + dust remainder for final claimable

## Examples

### Normal Mode (afKing inactive)
- Total: 12.5 ETH
- Rebuy: 12.5 ETH
- Dust: ~0.001 ETH (from ticket calculation)
- Final claimable: ~0.001 ETH

### afKing Mode
- Total: 12.5 ETH
- Complete thresholds: 6 (12 ETH)
- Rebuy: 12 ETH
- Fractional remainder: 0.5 ETH
- Dust: ~0.001 ETH
- Final claimable: 2.501 ETH

### afKing Mode with Low Balance
- Total: 2.9 ETH
- Complete thresholds: 0
- Rebuy: 0 ETH (below threshold)
- Final claimable: 2.9 ETH (no rebuy triggered)

## Testing Scenarios

1. afKing active, 12.5 ETH → rebuy 12 ETH, keep 0.5 ETH
2. afKing active, 7 ETH → rebuy 6 ETH, keep 1 ETH
3. afKing active, 1.9 ETH → rebuy 0 ETH, keep 1.9 ETH
4. afKing inactive, 12.5 ETH → rebuy all, keep dust
5. afKing active, 0.9 ETH → rebuy 0 ETH, keep 0.9 ETH (below min)
