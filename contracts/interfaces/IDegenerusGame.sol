// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @notice Payment method for gamepiece purchases.
enum MintPaymentKind {
    DirectEth,   // Pay with fresh ETH only
    Claimable,   // Pay with claimable winnings only
    Combined     // Pay with both ETH and claimable (combined purchase bonus)
}

/// @title IDegenerusGame
/// @notice Core game contract interface for state machine, purchases, and prize pool management.
/// @dev Implements 3-state FSM: SETUP(1) → PURCHASE(2) → BURN(3) → SETUP(1). GAMEOVER(86) is terminal.
interface IDegenerusGame {
    /// @notice Get remaining supply for up to 4 traits in a single call.
    /// @dev Gas-optimized batch query for trait availability.
    /// @param traitIds Array of trait IDs to query (0-31).
    /// @return lastExterminated The current level's exterminated trait if set, otherwise last level's (420 if none).
    /// @return currentLevel The current game level.
    /// @return remaining Array of remaining counts for each queried trait.
    function getTraitRemainingQuad(
        uint8[4] calldata traitIds
    ) external view returns (uint16 lastExterminated, uint24 currentLevel, uint32[4] memory remaining);

    /// @notice Extended trait remaining query including current extermination window state.
    /// @param traitIds Array of trait IDs to query (0-255).
    /// @return lastExterminated The current level's exterminated trait if set, otherwise last level's (420 if none).
    /// @return currentLevel The current game level.
    /// @return remaining Array of remaining counts for each queried trait.
    /// @return exOpen True if current level has not yet been exterminated.
    function getTraitRemainingQuadExt(
        uint8[4] calldata traitIds
    )
        external
        view
        returns (
            uint16 lastExterminated,
            uint24 currentLevel,
            uint32[4] memory remaining,
            bool exOpen
        );

    /// @notice Get the current game level.
    /// @return Current level (1-based index).
    function level() external view returns (uint24);

    /// @notice Get the current game state.
    /// @return State (1=SETUP, 2=PURCHASE, 3=BURN, 86=GAMEOVER).
    function gameState() external view returns (uint8);

    /// @notice Get the current mint price in wei.
    /// @return Price per gamepiece in wei.
    function mintPrice() external view returns (uint256);

    /// @notice Get the decimator window status.
    /// @dev Decimator window opens during specific level transitions.
    /// @return on True if decimator window is currently open.
    /// @return lvl The level at which the window is open (0 if closed).
    function decWindow() external view returns (bool on, uint24 lvl);

    /// @notice Check if decimator window is currently open (flag only).
    /// @return True if decimator window is open.
    function decWindowOpenFlag() external view returns (bool);

    /// @notice Get comprehensive purchase information in a single call.
    /// @dev Gas-optimized batch query for UI display.
    /// @return lvl Current game level.
    /// @return gameState_ Current game state.
    /// @return lastPurchaseDay_ True if this is the last day to purchase.
    /// @return rngLocked_ True if RNG is locked (VRF pending).
    /// @return priceWei Current mint price in wei.
    function purchaseInfo()
        external
        view
        returns (uint24 lvl, uint8 gameState_, bool lastPurchaseDay_, bool rngLocked_, uint256 priceWei);

    /// @notice Get the VRF random word for a lootbox RNG index.
    /// @param lootboxIndex Lootbox RNG index to query.
    /// @return word VRF word (0 if not ready).
    function lootboxRngWord(uint48 lootboxIndex) external view returns (uint256 word);

    /// @notice Return last-purchase-day coinflip totals for payout tuning.
    /// @return prevTotal Previous level's lastPurchaseDay coinflip deposits.
    /// @return currentTotal Current level's lastPurchaseDay coinflip deposits.
    function lastPurchaseDayFlipTotals()
        external
        view
        returns (uint256 prevTotal, uint256 currentTotal);

    /// @notice Get the number of levels a player has minted with fresh ETH.
    /// @param player The player to query.
    /// @return Number of levels with ETH mints.
    function ethMintLevelCount(address player) external view returns (uint24);

    /// @notice Get the player's current ETH mint streak.
    /// @dev Streak breaks if player misses a level.
    /// @param player The player to query.
    /// @return Current ETH mint streak count.
    function ethMintStreakCount(address player) external view returns (uint24);

    /// @notice Get the last level where player minted with ETH.
    /// @param player The player to query.
    /// @return Last ETH mint level (0 if never minted).
    function ethMintLastLevel(address player) external view returns (uint24);

    /// @notice Get the player's activity score multiplier.
    /// @dev Multiplier based on participation and engagement (basis points).
    /// @param player The player to query.
    /// @return Multiplier in bps (10000 = 1x).
    function playerActivityScore(address player) external view returns (uint256);

    /// @notice Check if an operator is approved to act on behalf of a player.
    /// @param owner The player who granted approval.
    /// @param operator The operator address to check.
    /// @return approved True if operator can act for owner.
    function isOperatorApproved(address owner, address operator) external view returns (bool);

    /// @notice Enqueue future tickets for a player.
    /// @dev Used for whale bundles and presale purchases.
    /// @param buyer The player receiving the tickets.
    /// @param quantityScaled Number of tickets to enqueue (2 decimals, scaled by 100).
    /// @param lvlOffset Level offset from current level.
    function enqueueTickets(address buyer, uint32 quantityScaled, uint24 lvlOffset) external;

    /// @notice Record a gamepiece mint and calculate rewards.
    /// @dev Access restricted to authorized contracts (COIN, GAMEPIECES).
    /// @param player The player making the purchase.
    /// @param lvl The current game level.
    /// @param costWei Total cost in wei.
    /// @param mintUnits Number of units purchased.
    /// @param payKind Payment method used.
    /// @return coinReward BURNIE reward amount.
    /// @return newClaimableBalance Updated claimable balance if using claimable payment.
    function recordMint(
        address player,
        uint24 lvl,
        uint256 costWei,
        uint32 mintUnits,
        MintPaymentKind payKind
    ) external payable returns (uint256 coinReward, uint256 newClaimableBalance);

    /// @notice Consume coinflip boon for next coinflip stake bonus.
    /// @dev Grants bonus to the next coinflip deposit.
    /// @param player The player consuming the boon.
    /// @return boostBps Boost amount in basis points.
    function consumeCoinflipBoon(address player) external returns (uint16 boostBps);

    /// @notice Consume decimator boon for burn boost.
    /// @dev Grants bonus to next decimator burn.
    /// @param player The player consuming the boon.
    /// @return boostBps Boost amount in basis points.
    function consumeDecimatorBoon(address player) external returns (uint16 boostBps);

    /// @notice Consume ticket boost for purchase bonus.
    /// @dev Grants bonus to next ticket purchase.
    /// @param player The player consuming the boost.
    /// @return boostBps Boost amount in basis points.
    function consumeTicketBoost(address player) external returns (uint16 boostBps);

    /// @notice Consume gamepiece boost for purchase bonus.
    /// @dev Grants bonus to next gamepiece purchase.
    /// @param player The player consuming the boost.
    /// @return boostBps Boost amount in basis points.
    function consumeGamepieceBoost(address player) external returns (uint16 boostBps);

    /// @notice Get the future prize pool (single pool).
    /// @param lvl Unused; retained for interface compatibility.
    function futurePrizePoolView(uint24 lvl) external view returns (uint256);

    /// @notice Get the aggregate future prize pool.
    function futurePrizePoolTotalView() external view returns (uint256);

    /// @notice Get the number of tickets owed to a player for a specific level.
    /// @param lvl The level to query.
    /// @param player The player to query.
    /// @return Number of whole tickets owed (fractional remainder resolves at batch time).
    function ticketsOwedView(uint24 lvl, address player) external view returns (uint32);

    /// @notice Credit decimator jackpot claims into the game's claimable balance.
    /// @dev Splits claim 50/50: half ETH, half lootbox tickets (derived using rngWord entropy).
    ///      Supports both single and batch claims. During GAMEOVER, credits 100% ETH (no lootbox split).
    /// @param accounts Player addresses to credit.
    /// @param amounts  Wei amounts to credit per player (total before split).
    /// @param rngWord VRF random word from jackpot resolution (used for lootbox ticket randomness).
    function creditDecJackpotClaimBatch(address[] calldata accounts, uint256[] calldata amounts, uint256 rngWord) external;

    /// @notice Record a coinflip deposit for tracking.
    /// @dev Called by COIN contract when players deposit into coinflip pool.
    /// @param amount Amount deposited in wei.
    function recordCoinflipDeposit(uint256 amount) external;

    /// @notice Pay DGNRS bounty for biggest flip record holder.
    /// @dev Called by COIN contract when bounty is paid.
    /// @param player Player receiving the bounty payout.
    function payCoinflipBountyDgnrs(address player) external;


    /// @notice Check if RNG is currently locked (VRF request pending).
    /// @return True if RNG is locked, false otherwise.
    function rngLocked() external view returns (bool);

    /// @notice Check if afKing mode is active for a player.
    /// @param player The player to query.
    /// @return active True if afKing mode is active.
    function afKingModeFor(address player) external view returns (bool active);

    /// @notice Deactivate afKing mode for a player (coin-only hook).
    /// @param player Player to deactivate.
    function deactivateAfKingFromCoin(address player) external;

    /// @notice Get lootbox status for a player on a specific lootbox index.
    /// @param player The player to query.
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    /// @return amount Lootbox value in wei.
    /// @return presale True if this was a presale lootbox.
    function lootboxStatus(address player, uint48 lootboxIndex) external view returns (uint256 amount, bool presale);

    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active);

    /// @notice Open a lootbox for a specific lootbox index and claim rewards.
    /// @dev Claims ETH, DGNRS, WWXRP, and potential boons/boosts.
    /// @param player The player address to open for (address(0) = msg.sender).
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    function openLootBox(address player, uint48 lootboxIndex) external;

    /// @notice Force a lootbox RNG request for the current index by burning BURNIE.
    /// @param player The player address paying the BURNIE cost (address(0) = msg.sender).
    function rollLootboxRng(address player) external;

    /// @notice Get the current lootbox RNG index for new purchases.
    function lootboxRngIndexView() external view returns (uint48 index);

    /// @notice Get the lootbox RNG request threshold (wei).
    function lootboxRngThresholdView() external view returns (uint256 threshold);

    /// @notice Get minimum LINK balance required for manual lootbox RNG rolls.
    function lootboxRngMinLinkBalanceView() external view returns (uint256 minBalance);

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Admin-only.
    function setLootboxRngThreshold(uint256 newThreshold) external;

    /// @notice Update minimum LINK balance required for manual lootbox RNG rolls.
    /// @dev Admin-only.
    function setLootboxRngMinLinkBalance(uint256 newMinBalance) external;

    /// @notice End the lootbox presale period (admin function).
    /// @dev One-way transition; cannot be re-enabled after calling.
    function endLootboxPresale() external;

    /// @notice Sample up to 4 trait burn tickets from a random trait and recent level (last 20).
    /// @dev View function for BAF scatter selection; uses provided entropy.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return lvl The sampled level.
    /// @return trait The sampled trait ID.
    /// @return tickets Array of player addresses holding sampled tickets.
    function sampleTraitTickets(uint256 entropy) external view returns (uint24 lvl, uint8 trait, address[] memory tickets);

    /// @notice Return the exterminator address for a given level (level index is 1-based).
    /// @dev Returns the player who eliminated the final trait and triggered level advancement.
    /// @param lvl The level to query (1-based).
    /// @return The exterminator's address (address(0) if not yet set).
    function levelExterminator(uint24 lvl) external view returns (address);

    /// @notice Purchase a deity pass (perma whale pass).
    /// @dev Grants auto-refreshing whale tickets and bundled perks.
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param quantity Number of passes to purchase.
    function purchaseDeityPass(address buyer, uint256 quantity) external payable;

    /// @notice Redeem giftable 10-level whale bundle credits.
    /// @param player Player address to redeem for (address(0) = msg.sender).
    /// @param quantity Number of 10-level passes to redeem.
    function redeemWhaleBundle10Pass(address player, uint256 quantity) external;

    /// @notice Transfer giftable 10-level whale bundle credits to another player.
    /// @param from Pass owner (address(0) = msg.sender).
    /// @param to Recipient address.
    /// @param quantity Number of passes to transfer.
    function transferWhaleBundle10Pass(address from, address to, uint256 quantity) external;

    /// @notice Activate a lazy pass token (lazy pass contract only).
    /// @param player Player receiving the lazy pass tickets.
    /// @return passLevel Start level for the 10-level window.
    function activateLazyPass(address player) external returns (uint24 passLevel);

    /// @notice Activate a lazy pass for a specific level window (lazy pass contract only).
    /// @param player Player receiving the lazy pass tickets.
    /// @param passLevel Start level for the 10-level window.
    function activateLazyPassAtLevel(address player, uint24 passLevel) external;

    /// @notice Get deity pass count for a player.
    /// @param player Player address to query.
    /// @return Count of deity passes owned.
    function deityPassCountFor(address player) external view returns (uint16);

    /// @notice Get giftable 10-level whale pass credits for a player.
    /// @param player Player address to query.
    /// @return Credits available for redemption (inactive lazy pass tokens).
    function whaleBundle10PassCreditsFor(address player) external view returns (uint16);

    /// @notice Purchase any combination of gamepieces, tickets, and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases. For BURNIE purchases, use DegenerusGamepieces.purchase().
    ///      Spending all claimable winnings earns a 10% bonus across the combined purchase.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param gamepieceQuantity Number of gamepieces to purchase (0 to skip).
    /// @param ticketQuantity Number of tickets to purchase (0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    function purchase(
        address buyer,
        uint256 gamepieceQuantity,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;
}
