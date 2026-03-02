// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;


/// @notice Payment method for ticket purchases.
enum MintPaymentKind {
    DirectEth,   // Pay with fresh ETH only
    Claimable,   // Pay with claimable winnings only
    Combined     // Pay with both ETH and claimable (combined purchase bonus)
}

/// @title IDegenerusGame
/// @notice Core game contract interface for state machine, purchases, and prize pool management.
/// @dev Implements 2-state FSM: PURCHASE(false) → JACKPOT(true) → PURCHASE(false). gameOver() is terminal.
interface IDegenerusGame {
    /// @notice Get the current jackpot level.
    /// @return Current jackpot level (starts at 0).
    function level() external view returns (uint24);

    /// @notice Get the current game phase using jackpot semantics.
    /// @return True if jackpot phase is active, false if purchase phase.
    function jackpotPhase() external view returns (bool);

    /// @notice Check if the game has ended (terminal state).
    function gameOver() external view returns (bool);

    /// @notice Get the current mint price in wei.
    /// @return Base price unit in wei.
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
    /// @return lvl Active direct-ticket level (lootbox purchases still route to next level during jackpot phase).
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True if this is the last day to purchase.
    /// @return rngLocked_ True if RNG is locked (VRF pending).
    /// @return priceWei Current mint price in wei.
    function purchaseInfo()
        external
        view
        returns (uint24 lvl, bool inJackpotPhase, bool lastPurchaseDay_, bool rngLocked_, uint256 priceWei);

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

    /// @notice Get normalized activity score for lootbox EV calculation (0-10000 bps).
    /// @dev Converts playerActivityScore to 0-10000 scale for lootbox EV multiplier.
    /// @param player The player to query.
    /// @return scoreBps Normalized activity score (0-10000 bps).
    function activityScoreFor(address player) external view returns (uint16 scoreBps);

    /// @notice Check if an operator is approved to act on behalf of a player.
    /// @param owner The player who granted approval.
    /// @param operator The operator address to check.
    /// @return approved True if operator can act for owner.
    function isOperatorApproved(address owner, address operator) external view returns (bool);

    /// @notice Record a ticket purchase and calculate rewards.
    /// @dev Access restricted to authorized contracts (COIN or GAME self-call).
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

    /// @notice Consume purchase boost for purchase bonus.
    /// @dev Grants bonus to next ticket purchase.
    /// @param player The player consuming the boost.
    /// @return boostBps Boost amount in basis points.
    function consumePurchaseBoost(address player) external returns (uint16 boostBps);

    /// @notice Get raw deity boon state for off-chain or viewer contract computation.
    /// @param deity The deity address to query.
    function deityBoonData(
        address deity
    ) external view returns (
        uint256 dailySeed,
        uint48 day,
        uint8 usedMask,
        bool decimatorOpen,
        bool deityPassAvailable
    );

    /// @notice Issue a deity boon to a recipient.
    /// @param deity Deity issuing the boon (address(0) = msg.sender).
    /// @param recipient Recipient of the boon.
    /// @param slot Slot index (0-4).
    function issueDeityBoon(address deity, address recipient, uint8 slot) external;

    /// @notice Get the future prize pool (single pool).
    /// @param lvl Unused; retained for interface compatibility.
    /// @return Future prize pool amount in wei.
    function futurePrizePoolView(uint24 lvl) external view returns (uint256);

    /// @notice Get the aggregate future prize pool.
    /// @return Total future prize pool amount in wei.
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

    /// @notice Credit a single decimator jackpot claim into the game's claimable balance.
    /// @dev Splits claim 50/50: half ETH, half lootbox tickets (derived using rngWord entropy).
    ///      During GAMEOVER, credits 100% ETH (no lootbox split).
    /// @param account Player address to credit.
    /// @param amount Wei amount to credit (total before split).
    /// @param rngWord VRF random word from jackpot resolution (used for lootbox ticket randomness).
    function creditDecJackpotClaim(address account, uint256 amount, uint256 rngWord) external;

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

    /// @notice Record a coinflip deposit for tracking.
    /// @dev Called by COIN contract when players deposit into coinflip pool.
    /// @param amount Amount deposited in wei.
    function recordCoinflipDeposit(uint256 amount) external;

    /// @notice Record mint streak completion after a 1x price ETH quest completes.
    /// @dev Called by COIN contract.
    /// @param player The player who completed the quest.
    function recordMintQuestStreak(address player) external;

    /// @notice Pay DGNRS bounty for biggest flip record holder.
    /// @dev Called by COIN contract when bounty is paid.
    /// @param player Player receiving the bounty payout.
    function payCoinflipBountyDgnrs(address player) external;

    /// @notice Check if RNG is currently locked (VRF request pending).
    /// @return True if RNG is locked, false otherwise.
    function rngLocked() external view returns (bool);

    /// @notice Current day index.
    function currentDayView() external view returns (uint48);

    /// @notice Request lootbox RNG when activity threshold is met.
    /// @dev Standalone function for mid-day lootbox RNG requests.
    ///      Reverts if daily RNG locked, request pending, threshold not met, or VRF fails.
    function requestLootboxRng() external;

    /// @notice Check if afKing mode is active for a player.
    /// @param player The player to query.
    /// @return active True if afKing mode is active.
    function afKingModeFor(address player) external view returns (bool active);

    /// @notice Get the level when afKing mode was activated for a player.
    /// @param player The player to query.
    /// @return activationLevel Level at which afKing mode was enabled (0 if inactive).
    function afKingActivatedLevelFor(address player) external view returns (uint24 activationLevel);

    /// @notice Deactivate afKing mode for a player (coin-only hook).
    /// @param player Player to deactivate.
    function deactivateAfKingFromCoin(address player) external;

    /// @notice Sync afKing lazy pass status and revoke if inactive (coin-only hook).
    /// @param player Player to sync.
    /// @return active True if afKing remains active after sync.
    function syncAfKingLazyPassFromCoin(address player) external returns (bool active);

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

    /// @notice Place Full Ticket Degenerette bets (4 traits, match-based payouts).
    /// @param player The betting player (address(0) = msg.sender).
    /// @param currency Currency type (0=ETH, 1=BURNIE, 2=unsupported, 3=WWXRP).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1-10). Each spin resolves independently.
    /// @param customTicket Custom packed traits (use 0 for random).
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeFullTicketBets(
        address player,
        uint8 currency,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external payable;

    /// @notice Place Full Ticket Degenerette bets using pending affiliate Degenerette credit.
    /// @param player The betting player (address(0) = msg.sender).
    /// @param amountPerTicket Bet amount per ticket.
    /// @param ticketCount Number of spins (1-10). Each spin resolves independently.
    /// @param customTicket Custom packed traits (use 0 for random).
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeFullTicketBetsFromAffiliateCredit(
        address player,
        uint128 amountPerTicket,
        uint8 ticketCount,
        uint32 customTicket,
        uint8 heroQuadrant
    ) external;

    /// @notice Resolve Degenerette bets once RNG is available.
    /// @param player The betting player (address(0) = msg.sender).
    /// @param betIds Bet identifiers for the player.
    function resolveDegeneretteBets(
        address player,
        uint64[] calldata betIds
    ) external;

    /// @notice View Degenerette packed bet info for a player/betId.
    /// @param player Player address to query.
    /// @param betId Bet identifier for the player.
    /// @return packed Packed bet data (amount/currency/betSpec/rngIndex/resolved).
    function degeneretteBetInfo(
        address player,
        uint64 betId
    )
        external
        view
        returns (uint256 packed);

    /// @notice Get the current lootbox RNG index for new purchases.
    /// @return index Current lootbox RNG index.
    function lootboxRngIndexView() external view returns (uint48 index);

    /// @notice Get the lootbox RNG request threshold (wei).
    /// @return threshold Minimum wei accumulation before VRF request triggers.
    function lootboxRngThresholdView() external view returns (uint256 threshold);

    /// @notice Get minimum LINK balance required for manual lootbox RNG rolls.
    /// @return minBalance Minimum LINK balance in wei.
    function lootboxRngMinLinkBalanceView() external view returns (uint256 minBalance);

    /// @notice Update lootbox RNG request threshold (wei).
    /// @dev Admin-only.
    /// @param newThreshold New threshold value in wei.
    function setLootboxRngThreshold(uint256 newThreshold) external;

    /// @notice Sample up to 4 trait burn tickets from a random trait and recent level (last 20).
    /// @dev View function for BAF scatter selection; uses provided entropy.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return lvl The sampled level.
    /// @return trait The sampled trait ID.
    /// @return tickets Array of player addresses holding sampled tickets.
    function sampleTraitTickets(uint256 entropy) external view returns (uint24 lvl, uint8 trait, address[] memory tickets);

    /// @dev View function for BAF far-future selection; samples ticketQueue at levels [current+5, current+99].
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return tickets Array of player addresses (length 0-4).
    function sampleFarFutureTickets(uint256 entropy) external view returns (address[] memory tickets);

    /// @notice Purchase a deity pass (presale or with boon).
    /// @dev Two modes:
    ///      - Presale (useBoon=false): During presale only, level 1, fixed 25 ETH price.
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param symbolId Symbol to claim (0-31).
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

    /// @notice Callback from deity pass ERC721 on transfer.
    /// @param from Current holder.
    /// @param to New holder.
    /// @param symbolId The symbol/tokenId being transferred.
    function onDeityPassTransfer(address from, address to, uint8 symbolId) external;

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    function purchaseLazyPass(address buyer) external payable;

    /// @notice Get deity pass count for a player.
    /// @param player Player address to query.
    /// @return Count of deity passes owned.
    function deityPassCountFor(address player) external view returns (uint16);

    /// @notice Get deity pass count purchased via presale bundle for a player.
    /// @param player Player address to query.
    /// @return Count of presale-purchased deity passes.
    function deityPassPurchasedCountFor(address player) external view returns (uint16);

    /// @notice Get total deity passes issued across all sources.
    /// @return count Total count (capped at 50).
    function deityPassTotalIssuedCount() external view returns (uint32 count);

    /// @notice Purchase tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases.
    ///      Spending all claimable winnings earns a 10% bonus across the combined purchase.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    function purchase(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind
    ) external payable;

    /// @notice Purchase tickets and loot boxes with BURNIE.
    /// @dev Entry point for all BURNIE purchases (tickets and loot boxes).
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param ticketQuantity Number of tickets to purchase (0 to skip).
    /// @param lootBoxBurnieAmount BURNIE amount for loot boxes (0 to skip).
    function purchaseCoin(
        address buyer,
        uint256 ticketQuantity,
        uint256 lootBoxBurnieAmount
    ) external;

    // -------------------------------------------------------------------------
    // Degenerette Tracking Views
    // -------------------------------------------------------------------------

    function getDailyHeroWager(uint48 day, uint8 quadrant, uint8 symbol) external view returns (uint256 wagerUnits);
    function getDailyHeroWinner(uint48 day) external view returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount);
    function getPlayerDegeneretteWager(address player, uint24 lvl) external view returns (uint256 weiAmount);
    function getTopDegenerette(uint24 lvl) external view returns (address topPlayer, uint256 amountUnits);
}
