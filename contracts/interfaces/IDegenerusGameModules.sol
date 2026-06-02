// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MintPaymentKind} from "./IDegenerusGame.sol";

/// @title IDegenerusGameAdvanceModule
/// @notice Interface for the game advancement module handling VRF and game progression
interface IDegenerusGameAdvanceModule {
    /// @notice Advances the game state by processing pending operations.
    /// @return mult Day-epoch stall multiplier (new-day stall ladder 1/2/4/6; 1 mid-day;
    ///         0 on the gameover path = no bounty). The router pays 2x * mult when mult > 0.
    function advanceGame() external returns (uint8 mult);

    /// @notice Requests mid-day lootbox RNG when threshold conditions are met.
    function requestLootboxRng() external;

    /// @notice Retries a stalled mid-day lootbox RNG request after the timeout window.
    function retryLootboxRng() external;

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
    function handleGameOverDrain(uint32 day) external;

    /// @notice Performs the final sweep of remaining funds after game over
    function handleFinalSweep() external;
}

/// @title IDegenerusGameJackpotModule
/// @notice Interface for managing various jackpot distributions
interface IDegenerusGameJackpotModule {
    /// @notice Pays out the daily jackpot to winners
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl The current game level
    /// @param randWord Random word for winner selection
    function payDailyJackpot(
        bool isJackpotPhase,
        uint24 lvl,
        uint256 randWord
    ) external;

    /// @notice Pays daily jackpot rewards in coin and tickets
    /// @param randWord Random word for distribution
    function payDailyJackpotCoinAndTickets(uint256 randWord) external;

    /// @notice Pays daily coin jackpot rewards
    /// @param lvl The current game level
    /// @param randWord Random word for winner selection
    /// @param minLevel Minimum target level for near-future coin distribution (inclusive)
    /// @param maxLevel Maximum target level for near-future coin distribution (inclusive)
    function payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external;

    /// @notice Emit DailyWinningTraits without running distribution.
    /// @param lvl Current level.
    /// @param randWord VRF entropy for trait derivation.
    /// @param bonusTargetLevel Target level for the primary bonus coin distribution.
    function emitDailyWinningTraits(uint24 lvl, uint256 randWord, uint24 bonusTargetLevel) external;

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

    /// @notice Afking ticket-buy entry: the fresh-ETH portion is an explicit `ethValue` param
    ///         debited from the funder's `afkingFunding` bucket inside the Game (not msg.value),
    ///         so the afking process STAGE queues a ticket-mode sub's tickets inline (non-payable).
    function purchaseWith(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 ethValue
    ) external;

    /// @notice Processes a BURNIE purchase of tickets
    /// @param buyer Address of the buyer
    /// @param ticketQuantity Number of tickets to purchase
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity
    ) external;

    /// @notice Sells far-future ticket entries to sDGNRS for current-level tickets + cash (-EV).
    /// @param player Resolved seller / recipient
    /// @param levels Target levels to sell from
    /// @param quantities Whole far tickets to sell at each level
    /// @param queueIndices Caller-supplied ticketQueue positions (verified; for swap-pop on sell-out)
    function sellFarFutureTickets(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities,
        uint256[] calldata queueIndices
    ) external;

    /// @notice Buys a credit-gated coin-presale box (ETH + claimable shortfall)
    /// @param buyer Player receiving the box
    /// @param boxAmount Requested box ETH (>= 0.01 ETH, pre-clamp)
    function buyPresaleBox(address buyer, uint256 boxAmount) external;

    /// @notice Buys a mint leg AND a presale box in one tx sharing one RNG index
    /// @param buyer Player receiving both legs
    /// @param ticketQuantity Tickets to buy
    /// @param lootBoxAmount ETH lootbox spend
    /// @param affiliateCode Affiliate code for the mint leg
    /// @param payKind Payment method for the mint leg
    /// @param boxAmount Requested presale-box ETH (claimable-funded)
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external;

    /// @notice Processes a batch of future ticket claims
    /// @param lvl The level to process tickets for
    /// @param entropy VRF-derived entropy for rarity rolls (caller passes today's daily RNG word)
    /// @return worked Whether any processing was done
    /// @return finished Whether all pending tickets are processed
    /// @return writesUsed Number of storage writes used
    function processFutureTicketBatch(
        uint24 lvl,
        uint256 entropy
    ) external returns (bool worked, bool finished, uint32 writesUsed);

    /// @notice Processes a batch of current-level ticket entries
    /// @param lvl The level to process tickets for
    /// @return finished True if all tickets have been processed
    function processTicketBatch(uint24 lvl) external returns (bool finished);

}

/// @title IDegenerusGameLootboxModule
/// @notice Interface for opening lootboxes and managing boons
interface IDegenerusGameLootboxModule {
    /// @notice Opens a standard lootbox for a player
    /// @param player Address of the lootbox owner
    /// @param lootboxIndex Index of the lootbox to open
    function openLootBox(address player, uint48 lootboxIndex) external;

    /// @notice Opens a coin-presale box for a player
    /// @param player Address of the box owner
    /// @param index RNG index the box queued at
    function openPresaleBox(address player, uint48 index) external;

    /// @notice Opens a co-queued lootbox + presale box in one tx
    /// @param player Address of the index owner
    /// @param index Shared RNG index
    function openLootboxAndPresaleBox(address player, uint48 index) external;

    /// @notice Resolves a lootbox directly with provided randomness
    /// @param player Address of the lootbox owner
    /// @param amount Amount associated with the lootbox
    /// @param rngWord Random word for lootbox resolution
    /// @param activityScore Frozen activity-score bps for the EV multiplier (caller-snapshotted)
    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
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

    /// @notice Resolve an AfKing-subscription box at the LIVE level from a caller-passed
    ///         frozen-day word.
    /// @dev The LIVE-level twin of resolveLootboxDirect — the box rolls from the LIVE level
    ///      and the EV-cap RMW is the single draw at open (EVCAP-01), with two deviations:
    ///      the word is a caller-passed param (rngWordByDay[stamp day], §1) and the seed
    ///      `day` is the FROZEN stamped process day (§1). Called by the GameAfkingModule
    ///      open-leg.
    /// @param player Box owner (resolved from the subscription)
    /// @param amount The stamped spend in wei (boons OFF ⇒ amount == spend)
    /// @param day The boundary-pinned process day stamped at process (frozen seed input)
    /// @param rngWord The frozen stamp day's word rngWordByDay[day], passed by the caller (§1)
    /// @param activityScore The stamped activity-score bps (scorePlus1 - 1, frozen EV input)
    function resolveAfkingBox(
        address player,
        uint256 amount,
        uint32 day,
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
        returns (uint8[3] memory slots, uint8 usedMask, uint32 day);

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

/// @title IDegenerusGameBingoModule
/// @notice Interface for color-completion bingo claims (v51.0) + the affiliate-DGNRS claim.
interface IDegenerusGameBingoModule {
    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @param level The level to claim on (uint24 storage-key width).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in traitBurnTicket[level][traitId] the caller occupies.
    function claimBingo(uint24 level, uint8 symbol, uint32[8] calldata slots) external;

    /// @notice Claim DGNRS affiliate rewards for the current level. The Game retains a
    ///         thin delegatecall dispatch stub that targets this selector; the body must
    ///         run in the Game's context for the onlyGame / onlyFlipCreditors external
    ///         calls, which is what that stub provides.
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external;
}

/// @title IGameAfkingModule
/// @notice Interface for the AfKing subscription logic.
/// @dev The GameAfkingModule is a delegatecall module operating on the Game's storage
///      (the subscriber set / cursors / Sub stamps live in
///      DegenerusGameStorage). This interface declares the mutating surface
///      so the Game-hosted dispatch stubs and the AdvanceModule process STAGE call
///      resolve against a real ABI. Every function runs IN the Game's storage context
///      (delegatecall), so msg.sender is preserved end-to-end (the consent gates and
///      the bounty payee read the original caller).
interface IGameAfkingModule {
    /// @notice The SINGLE subscription entrypoint: create / replace (dailyQuantity >= 1)
    ///         or cancel (dailyQuantity == 0, SUB-07 tombstone) for `player`
    ///         (self when 0/msg.sender).
    /// @dev FREEZE-01 rngLock guard (all of create / replace / cancel); CONSENT-01:
    ///      SUB-02 self-consent OR operator-approval (third-party path); OPENE-04
    ///      funding-source operator-approval gate; AFSUB validThroughLevel write.
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint8 reinvestPct,
        address fundingSource
    ) external payable;

    /// @notice Unified permissionless router: do ONE category of pending work this call
    ///         (advance → afking-box open) and pay ONE bounty (PLACE-02).
    function mintBurnie() external;

    /// @notice Standalone UNREWARDED afking-box open clear (walks _subOpenCursor).
    function autoOpen(uint256 count) external;

    /// @notice Permissionless BURNIE claim — pays each sub its accrued pendingBurnie (the
    ///         per-delivered-day slot-0 quest reward + ticket buyer-bonus) in one creditFlip
    ///         and zeroes it; always credits the sub, never the caller. Off the solvency path.
    function claimAfkingBurnie(address[] calldata subs) external;

    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued affiliateBase (the
    ///         running flat-7% affiliate balance, whole BURNIE). Read and zero happen
    ///         together so a duplicate sub drains 0 the second time; there is no separate
    ///         read accessor.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-BURNIE affiliate base (0 if already drained).
    function drainAffiliateBase(address sub) external returns (uint256 base);

    /// @notice For each funded sub it stamps the per-sub box fields (lootbox mode) or
    ///         queues whole tickets (ticket mode), debits afkingFunding, and advances
    ///         _subCursor until the accumulated gas-weight reaches weightBudget. Called by the
    ///         AdvanceModule via delegatecall; it runs pre-RNG, so the day's word is uncommitted
    ///         at stamp. A no-orphan guard skips any sub with a pending unopened box.
    /// @param processDay The boundary-pinned process day (seeds the open).
    /// @param weightBudget Per-chunk gas-weight budget (cheap buy 1, sub-ending finalize heavier).
    /// @return processed Number of set entries advanced/handled this chunk.
    function processSubscriberStage(
        uint32 processDay,
        uint256 weightBudget
    ) external returns (uint256 processed);
}
