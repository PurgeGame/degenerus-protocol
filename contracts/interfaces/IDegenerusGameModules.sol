// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MintPaymentKind} from "./IDegenerusGame.sol";

/// @title IDegenerusGameAdvanceModule
/// @notice Interface for the game advancement module handling VRF and game progression
interface IDegenerusGameAdvanceModule {
    /// @notice Advances the game state by processing pending operations
    function advanceGame() external;

    /// @notice Requests mid-day lootbox RNG when threshold conditions are met.
    function requestLootboxRng() external;

    /// @notice Configures the Chainlink VRF coordinator and subscription
    /// @param coordinator_ Address of the VRF coordinator contract
    /// @param subId Chainlink VRF subscription ID
    /// @param keyHash_ Key hash for the VRF request
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external;

    /// @notice Updates VRF coordinator, subscription, and key hash configuration
    /// @param newCoordinator New VRF coordinator address
    /// @param newSubId New subscription ID
    /// @param newKeyHash New key hash for VRF requests
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external;

    /// @notice Reverses a pending coinflip for caller
    function reverseFlip() external;

    /// @notice VRF callback function to receive random words
    /// @dev Called by the VRF coordinator to fulfill randomness requests
    /// @param requestId The ID of the VRF request being fulfilled
    /// @param randomWords Array of random words returned by VRF
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external;
}

/// @title IDegenerusGameGameOverModule
/// @notice Interface for handling game over state and final fund distribution
interface IDegenerusGameGameOverModule {
    /// @notice Handles draining funds during game over state
    /// @param day The day identifier for the drain operation
    function handleGameOverDrain(uint48 day) external;

    /// @notice Performs the final sweep of remaining funds after game over
    function handleFinalSweep() external;
}

/// @title IDegenerusGameJackpotModule
/// @notice Interface for managing various jackpot distributions
interface IDegenerusGameJackpotModule {
    /// @notice Pays out the daily jackpot to winners
    /// @param isDaily Whether this is a daily jackpot (vs other type)
    /// @param lvl The current game level
    /// @param randWord Random word for winner selection
    function payDailyJackpot(
        bool isDaily,
        uint24 lvl,
        uint256 randWord
    ) external;

    /// @notice Pays daily jackpot rewards in coin and tickets
    /// @param randWord Random word for distribution
    function payDailyJackpotCoinAndTickets(uint256 randWord) external;

    /// @notice Processes a batch of ticket entries for a specific level
    /// @param lvl The level to process tickets for
    /// @return finished True if all tickets have been processed
    function processTicketBatch(uint24 lvl) external returns (bool finished);

    /// @notice Pays daily coin jackpot rewards
    /// @param lvl The current game level
    /// @param randWord Random word for winner selection
    function payDailyCoinJackpot(uint24 lvl, uint256 randWord) external;

    /// @notice Terminal jackpot for x00 levels: Day-5-style bucket distribution.
    /// @param poolWei Total ETH to distribute.
    /// @param targetLvl Level to sample winners from.
    /// @param rngWord VRF entropy seed.
    /// @return paidWei Total ETH distributed.
    function runTerminalJackpot(
        uint256 poolWei,
        uint24 targetLvl,
        uint256 rngWord
    ) external returns (uint256 paidWei);

    /// @notice Execute BAF jackpot distribution.
    /// @param poolWei Total ETH pool for BAF.
    /// @param lvl Current level.
    /// @param rngWord VRF entropy.
    /// @return claimableDelta ETH moved to claimable.
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 claimableDelta);

    /// @notice Distribute yield surplus to stakeholders.
    /// @param rngWord VRF entropy for auto-rebuy targeting.
    function distributeYieldSurplus(uint256 rngWord) external;
}

/// @title IDegenerusGameDecimatorModule
/// @notice Interface for decimator jackpot tracking and resolution
interface IDegenerusGameDecimatorModule {
    /// @notice Record a Decimator burn for jackpot eligibility.
    /// @param player Address of the player.
    /// @param lvl Current game level.
    /// @param bucket Player's chosen denominator (2-12).
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Multiplier in basis points (10000 = 1x).
    /// @return bucketUsed The bucket actually used (may differ from requested if not an improvement).
    function recordDecBurn(
        address player,
        uint24 lvl,
        uint8 bucket,
        uint256 baseAmount,
        uint256 multBps
    ) external returns (uint8 bucketUsed);

    /// @notice Snapshot Decimator jackpot winners for deferred claims.
    /// @param poolWei Total ETH prize pool for this level.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return returnAmountWei Amount to return (non-zero if no winners or already snapshotted).
    function runDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);

    /// @notice Consume Decimator claim on behalf of player.
    /// @param player Address to claim for.
    /// @param lvl Level to claim from.
    /// @return amountWei Pro-rata payout amount.
    function consumeDecClaim(address player, uint24 lvl) external returns (uint256 amountWei);

    /// @notice Claim Decimator jackpot for caller.
    /// @param lvl Level to claim from (must be the last decimator).
    function claimDecimatorJackpot(uint24 lvl) external;

    /// @notice Check if player can claim Decimator jackpot for a level.
    /// @param player Address to check.
    /// @param lvl Level to check (must be the last decimator).
    /// @return amountWei Claimable amount (0 if not winner, already claimed, or expired).
    /// @return winner True if player is a winner for this level.
    function decClaimable(address player, uint24 lvl) external view returns (uint256 amountWei, bool winner);

    // Terminal Decimator (Death Bet)

    /// @notice Record a terminal decimator burn.
    function recordTerminalDecBurn(
        address player,
        uint24 lvl,
        uint256 baseAmount
    ) external;

    /// @notice Resolve terminal decimator at GAMEOVER.
    function runTerminalDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);

    /// @notice Claim terminal decimator jackpot.
    function claimTerminalDecimatorJackpot() external;

    /// @notice Check terminal decimator claimable amount.
    function terminalDecClaimable(address player) external view returns (uint256 amountWei, bool winner);
}

/// @title IDegenerusGameWhaleModule
/// @notice Interface for whale-tier purchases and premium passes
interface IDegenerusGameWhaleModule {
    /// @notice Purchases a whale bundle for the buyer
    /// @param buyer Address receiving the bundle
    /// @param quantity Number of bundles to purchase
    function purchaseWhaleBundle(address buyer, uint256 quantity) external payable;

    /// @notice Purchases a 10-level lazy pass for the buyer
    /// @param buyer Address receiving the pass
    function purchaseLazyPass(address buyer) external payable;

    /// @notice Purchases a deity pass for a specific symbol
    /// @param buyer Address receiving the deity pass
    /// @param symbolId Symbol index (0-31) to bind the pass to
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

    /// @notice Claim deferred whale pass rewards for a player.
    /// @param player Player address to claim for.
    function claimWhalePass(address player) external;
}

/// @title IDegenerusGameMintModule
/// @notice Interface for minting operations and purchase processing
interface IDegenerusGameMintModule {
    /// @notice Records mint data and updates Activity Score metrics
    /// @param player Address of the minting player
    /// @param lvl Current game level
    /// @param mintUnits Number of units being minted
    function recordMintData(
        address player,
        uint24 lvl,
        uint32 mintUnits
    ) external payable;

    /// @notice Processes a ticket and lootbox purchase
    /// @param buyer Address of the buyer
    /// @param ticketQuantity Number of tickets to purchase
    /// @param lootBoxAmount Amount of lootboxes to purchase
    /// @param affiliateCode Affiliate code for referral tracking
    /// @param payKind Payment method used for the purchase
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    /// @notice Processes a BURNIE purchase of tickets and optional lootboxes
    /// @param buyer Address of the buyer
    /// @param ticketQuantity Number of tickets to purchase
    /// @param lootBoxBurnieAmount Amount of BURNIE to burn for lootboxes
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external;

    /// @notice Purchases Burnie-specific lootboxes
    /// @param buyer Address of the buyer
    /// @param burnieAmount Amount of Burnie lootboxes to purchase
    function purchaseBurnieLootbox(address buyer, uint256 burnieAmount) external;

    /// @notice Opens a lootbox for a player
    /// @param player Address of the lootbox owner
    /// @param lootboxIndex Index of the lootbox to open
    function openLootBox(address player, uint48 lootboxIndex) external;

    /// @notice Resolves a lootbox directly with provided randomness
    /// @param player Address of the lootbox owner
    /// @param amount Amount associated with the lootbox
    /// @param rngWord Random word for lootbox resolution
    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) external;

    /// @notice Processes a batch of future ticket claims
    /// @param lvl The level to process tickets for
    /// @return worked Whether any processing was done
    /// @return finished Whether all pending tickets are processed
    /// @return writesUsed Number of storage writes used
    function processFutureTicketBatch(
        uint24 lvl
    ) external returns (bool worked, bool finished, uint32 writesUsed);

}

/// @title IDegenerusGameLootboxModule
/// @notice Interface for opening lootboxes and managing boons
interface IDegenerusGameLootboxModule {
    /// @notice Opens a standard lootbox for a player
    /// @param player Address of the lootbox owner
    /// @param lootboxIndex Index of the lootbox to open
    function openLootBox(address player, uint48 lootboxIndex) external;

    /// @notice Opens a Burnie lootbox for a player
    /// @param player Address of the lootbox owner
    /// @param lootboxIndex Index of the Burnie lootbox to open
    function openBurnieLootBox(address player, uint48 lootboxIndex) external;

    /// @notice Resolves a lootbox directly with provided randomness
    /// @param player Address of the lootbox owner
    /// @param amount Amount associated with the lootbox
    /// @param rngWord Random word for lootbox resolution
    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord
    ) external;

    /// @notice Resolves a redemption lootbox with a snapshotted activity score
    /// @param player Player receiving lootbox rewards
    /// @param amount ETH amount for lootbox resolution
    /// @param rngWord RNG word for entropy
    /// @param activityScore Raw activity score (bps) snapshotted at burn submission
    function resolveRedemptionLootbox(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external;

    /// @notice Returns deity boon slot information
    /// @param deity Address of the deity
    /// @return slots Array of 3 boon slot types
    /// @return usedMask Bitmask of which slots have been used
    /// @return day The day these slots were generated for
    function deityBoonSlots(address deity)
        external
        view
        returns (uint8[3] memory slots, uint8 usedMask, uint48 day);

    /// @notice Issues a deity boon from a deity to a recipient
    /// @param deity Address of the deity issuing the boon
    /// @param recipient Address receiving the boon
    /// @param slot Slot index of the boon to issue
    function issueDeityBoon(address deity, address recipient, uint8 slot) external;
}

/// @title IDegenerusGameBoonModule
/// @notice Interface for boon consumption
interface IDegenerusGameBoonModule {
    /// @notice Consumes a player's coinflip boon and returns its value
    /// @param player Address of the player
    /// @return boonBps Boon value in basis points
    function consumeCoinflipBoon(address player) external returns (uint16 boonBps);

    /// @notice Consumes a player's purchase boost boon
    /// @param player Address of the player
    /// @return boostBps Boost value in basis points
    function consumePurchaseBoost(address player) external returns (uint16 boostBps);

    /// @notice Consumes a player's decimator boost boon
    /// @param player Address of the player
    /// @return boostBps Boost value in basis points
    function consumeDecimatorBoost(address player) external returns (uint16 boostBps);

    /// @notice Clear all expired boons for a player
    /// @param player Address of the player
    /// @return hasAnyBoon True if any active boon remains
    function checkAndClearExpiredBoon(address player) external returns (bool hasAnyBoon);

    /// @notice Consume a pending activity boon and apply to player stats
    /// @param player Address of the player
    function consumeActivityBoon(address player) external;
}

/// @title IDegenerusGameDegeneretteModule
/// @notice Interface for Degenerette betting mechanics (full-ticket only)
interface IDegenerusGameDegeneretteModule {
    /// @notice Places Full Ticket bets (4 traits, match-based payouts)
    /// @param player The player address (use zero address for msg.sender)
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP)
    /// @param amountPerTicket Bet amount per ticket
    /// @param ticketCount Number of spins (1..10). Each spin resolves independently.
    /// @param customTicket Custom packed traits
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable;

    /// @notice Resolves one or more pending bets for a player
    /// @param player The player address (use zero address for msg.sender)
    /// @param betIds Array of bet IDs to resolve
    function resolveBets(
        address player,
        uint64[] calldata betIds
    ) external;
}
