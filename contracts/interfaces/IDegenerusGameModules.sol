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
    function handleGameOverDrain(uint24 day) external;

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
    function payDailyFlipJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) external;

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

    /// @notice Permissionlessly resolve `player`'s Decimator jackpot claim (value credits to player).
    /// @param player Winner whose claim to resolve.
    /// @param lvl Level to claim from (must be the last decimator).
    function claimDecimatorJackpot(address player, uint24 lvl) external;

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players.
    /// @dev Non-claimable entries are skipped, not reverted.
    function claimDecimatorJackpotMany(address[] calldata players, uint24 lvl) external;

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

    /// @notice Final-day streak boost for the caller's terminal decimator entry.
    function boostTerminalDecimator() external;

    /// @notice Resolve terminal decimator at GAMEOVER.
    function runTerminalDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);

    /// @notice Claim terminal decimator jackpot for caller.
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

    /// @notice Processes a FLIP purchase of tickets
    /// @param buyer Address of the buyer
    /// @param ticketQuantity Number of tickets to purchase
    function redeemFlip(
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

    /// @notice Quote a far-future salvage swap WITHOUT executing (read-only -EV offer).
    function previewSellFarFutureTickets(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities
    )
        external
        view
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 ethCashWei,
            uint256 flipTokens
        );

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
    /// @notice Opens every box queued at an RNG index for a player — lootbox, presale, or both
    /// @param player Address of the box owner
    /// @param index Shared RNG index the box(es) queued at
    function openBox(address player, uint48 index) external;

    /// @notice Permissionless multi-index human-box auto-open sweep (the human leg of
    ///         openBoxes). Runs in the Game's storage via delegatecall.
    /// @param budget Maximum entries (opens + skips + index-headers) scanned this call
    /// @return opened Total human boxes opened this call
    function openHumanBoxes(uint256 budget) external returns (uint256 opened);

    /// @notice Resolves a lootbox directly with provided randomness
    /// @param player Address of the lootbox owner
    /// @param amount Amount associated with the lootbox
    /// @param rngWord Random word for lootbox resolution
    /// @param activityScore Frozen activity-score bps for the EV multiplier (caller-snapshotted)
    function resolveLootboxDirect(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore,
        bool emitLootboxEvent
    ) external payable;

    /// @notice Resolves an sDGNRS redemption's full lootbox leg (auth, funding-mix pull, pool
    ///         credit, 5-ETH chunked resolution) — delegatecall target of the Game's thin stub.
    /// @param player Player receiving lootbox rewards
    /// @param amount Total lootbox value (msg.value ETH + the stETH remainder pulled inside)
    /// @param rngWord RNG word for entropy
    /// @param activityScore Raw activity score (bps) snapshotted at burn submission
    function resolveRedemptionLootbox(
        address player,
        uint256 amount,
        uint256 rngWord,
        uint16 activityScore
    ) external payable;

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @param player Claimant credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(address player, uint256 amount) external payable;

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
    /// @param activityScore The stamped activity-score bps (the frozen EV input)
    function resolveAfkingBox(
        address player,
        uint256 amount,
        uint24 day,
        uint256 rngWord,
        uint16 activityScore
    ) external;

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
    function consumePurchaseBoost(address player) external payable returns (uint16 boostBps);

    /// @notice Consumes a player's decimator boost boon
    /// @param player Address of the player
    /// @return boostBps Boost value in basis points
    function consumeDecimatorBoost(address player) external returns (uint16 boostBps);

    /// @notice Clear all expired boons for a player
    /// @param player Address of the player
    /// @return hasAnyBoon True if any active boon remains
    function checkAndClearExpiredBoon(address player) external payable returns (bool hasAnyBoon);

    /// @notice Consume a pending activity boon and apply to player stats
    /// @param player Address of the player
    function consumeActivityBoon(address player) external payable;
}

/// @title IDegenerusGameDegeneretteModule
/// @notice Interface for Degenerette betting mechanics (full-ticket only)
interface IDegenerusGameDegeneretteModule {
    /// @notice Places Full Ticket bets (4 traits, match-based payouts)
    /// @param player The player address (use zero address for msg.sender)
    /// @param currency Currency type (0=ETH, 1=FLIP, 2=unsupported, 3=WWXRP)
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

    /// @notice Resolve a lootbox WWXRP roll as a single WWXRP Degenerette spin.
    /// @param player The reward recipient.
    /// @param stake The WWXRP bet amount staked for the one spin.
    /// @param activityScore Frozen activity-score bps from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    function resolveWwxrpSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) external payable;

    /// @notice Resolve a lootbox roll as three FLIP Degenerette spins under one survival flip.
    /// @param player The reward recipient.
    /// @param totalStake The total FLIP budget split across the three spins.
    /// @param activityScore Frozen activity-score bps from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    function resolveFlipSpinsFromBox(
        address player,
        uint256 totalStake,
        uint16 activityScore,
        uint256 seed
    ) external payable;

    /// @notice Resolve a lootbox roll as one ETH Degenerette spin (claimable + recirc split).
    /// @param player The reward recipient.
    /// @param stake The ETH bet amount for the one spin (the ticket budget it replaces).
    /// @param activityScore Frozen activity-score bps from the box's commitment.
    /// @param seed Domain-separated spin seed (hash2-tagged off the box seed).
    function resolveEthSpinFromBox(
        address player,
        uint256 stake,
        uint16 activityScore,
        uint256 seed
    ) external payable;
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
    function mintFlip() external;

    /// @notice Drain up to `count` ready afking boxes (walks _subOpenCursor); returns the
    ///         number opened. Unrewarded; reached via the Game's openBoxes() valve.
    function drainAfkingBoxes(uint256 count) external returns (uint256 opened);

    /// @notice Permissionless FLIP claim — pays each sub its accrued pendingFlip (the
    ///         per-delivered-day slot-0 quest reward + ticket buyer-bonus) in one creditFlip
    ///         and zeroes it; always credits the sub, never the caller. Off the solvency path.
    function claimAfkingFlip(address[] calldata subs) external;

    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued affiliateBase (the
    ///         running flat-7% affiliate balance, whole FLIP). Read and zero happen
    ///         together so a duplicate sub drains 0 the second time; there is no separate
    ///         read accessor.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained).
    function drainAffiliateBase(address sub) external returns (uint256 base);

    /// @notice Cashout-curse SET hook, delegatecalled from the Game's claimWinnings.
    function maybeCurse(address player) external;

    /// @notice Permissionless paid cure: clear `target`'s cashout/smite curse for 100 FLIP.
    function decurse(address target) external;

    /// @notice Deity-gated smite: add a saturating curse stack to `smitee` for 200 FLIP.
    function smite(uint256 deityId, address smitee) external;

    /// @notice For each funded sub it stamps the per-sub box fields (lootbox mode) or
    ///         queues whole tickets (ticket mode), debits afkingFunding, and advances
    ///         _subCursor until the accumulated gas-weight reaches weightBudget. Called by the
    ///         AdvanceModule via delegatecall; it runs pre-RNG, so the day's word is uncommitted
    ///         at stamp. A no-orphan guard skips any sub with a pending unopened box.
    /// @param processDay The boundary-pinned process day (seeds the open).
    /// @param weightBudget Per-chunk gas-weight budget (cheap buy 1, sub-ending finalize heavier).
    /// @return processed Number of set entries advanced/handled this chunk.
    function processSubscriberStage(
        uint24 processDay,
        uint256 weightBudget
    ) external returns (uint256 processed);
}
