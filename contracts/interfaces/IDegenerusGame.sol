// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;


/// @notice Payment method for ticket purchases.
enum MintPaymentKind {
    DirectEth,   // Pay with fresh ETH only
    Claimable,   // Pay with claimable winnings only
    Combined,    // Pay with both ETH and claimable (combined purchase bonus)
    Internal     // Protocol-internal debit (shortfall, salvage, redemption, game-over sweep)
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

    /// @notice Whether the liveness-timeout game-over trigger is currently active.
    /// @dev True on day-timeout (365 at level 0, 120 at level 1+) with VRF healthy,
    ///      or whenever VRF has been stalled ≥ 14 days. False during sub-grace VRF stalls.
    function livenessTriggered() external view returns (bool);

    /// @notice Check if the final fund forfeiture has executed (all funds forfeited).
    function isFinalSwept() external view returns (bool);

    /// @notice Get the current mint price in wei.
    /// @return Base price unit in wei.
    function mintPrice() external view returns (uint256);

    /// @notice Check if decimator window is currently open.
    /// @return True if decimator entries are allowed.
    function decWindow() external view returns (bool);

    /// @notice Check if the current jackpot phase is compressed (3 days instead of 5).
    /// @dev Compressed mode activates when the purchase-phase target is met within the
    ///      first 2 daily advances, signaling high player interest.
    /// @return Compression tier: 0=normal, 1=compressed (3d), 2=turbo (1d).
    function jackpotCompressionTier() external view returns (uint8);

    /// @notice Get comprehensive purchase information in a single call.
    /// @dev Gas-optimized batch query: lvl is the ACTUAL game level (on-chain consumers key on
    ///      it from this one snapshot, avoiding a second level() read), while priceWei is the
    ///      buy-now price at the ROUTED ticket level. The two diverge during the purchase phase
    ///      and the final jackpot RNG window (buys route to level+1) — this is intentional.
    /// @return lvl Actual current game level.
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True if this is the last day to purchase.
    /// @return rngLocked_ True if RNG is locked (VRF pending).
    /// @return priceWei Current buy-now mint price in wei (at the routed ticket level).
    function purchaseInfo()
        external
        view
        returns (uint24 lvl, bool inJackpotPhase, bool lastPurchaseDay_, bool rngLocked_, uint256 priceWei);

    /// @notice Get the player's activity score.
    /// @dev Score based on participation and engagement, in whole points.
    /// @param player The player to query.
    /// @return Activity score in whole points.
    function playerActivityScore(address player) external view returns (uint256);

    /// @notice Check if an operator is approved to act on behalf of a player.
    /// @param owner The player who granted approval.
    /// @param operator The operator address to check.
    /// @return approved True if operator can act for owner.
    function isOperatorApproved(address owner, address operator) external view returns (bool);

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

    /// @notice Get raw deity boon state for off-chain or viewer contract computation.
    /// @param deity The deity address to query.
    function deityBoonData(
        address deity
    ) external view returns (
        uint256 dailySeed,
        uint24 day,
        uint8 usedMask,
        bool decimatorOpen,
        bool deityPassAvailable
    );

    /// @notice Issue a deity boon to a recipient.
    /// @param deity Deity issuing the boon (address(0) = msg.sender).
    /// @param recipient Recipient of the boon.
    /// @param slot Slot index (0-2).
    function issueDeityBoon(address deity, address recipient, uint8 slot) external;

    /// @notice Get the future prize pool (single pool).
    /// @return Future prize pool amount in wei.
    function futurePrizePoolView() external view returns (uint256);

    /// @notice Get the yield accumulator balance (segregated stETH yield reserve).
    /// @return The yield accumulator balance (ETH wei).
    function yieldAccumulatorView() external view returns (uint256);

    /// @notice Get the number of entries owed to a player for a specific level.
    /// @param lvl The level to query.
    /// @param player The player to query.
    /// @return Number of entries owed (fractional remainder resolves at batch time).
    function entriesOwedView(uint24 lvl, address player) external view returns (uint32);

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

    /// @notice Execute BAF jackpot via JackpotModule delegatecall.
    /// @param poolWei Total ETH prize pool for BAF.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return claimableDelta ETH moved to claimable.
    function runBafJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 claimableDelta);

    // Terminal Decimator (Death Bet)

    /// @notice Record a terminal decimator burn entry for a player.
    /// @param player The player burning.
    /// @param lvl The current game level.
    /// @param baseAmount The base FLIP amount burned.
    function recordTerminalDecBurn(
        address player,
        uint24 lvl,
        uint256 baseAmount
    ) external;

    /// @notice Run the terminal decimator jackpot distribution.
    /// @param poolWei Total ETH pool to distribute.
    /// @param lvl The game level for winner sampling.
    /// @param rngWord Random word for winner selection.
    /// @return returnAmountWei ETH returned undistributed.
    function runTerminalDecimatorJackpot(
        uint256 poolWei,
        uint24 lvl,
        uint256 rngWord
    ) external returns (uint256 returnAmountWei);

    /// @notice Check if the terminal decimator window is open.
    /// @return open True if terminal decimator bets are accepted.
    /// @return lvl The current level for terminal decimator.
    function terminalDecWindow() external view returns (bool open, uint24 lvl);

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

    /// @notice Emit DailyWinningTraits without running any distribution.
    ///         Used at purchaseLevel==1 where payDailyJackpot is skipped.
    /// @param lvl Unused (preserved for signature compatibility with module).
    /// @param randWord VRF entropy for trait derivation.
    /// @param bonusTargetLevel Target level for the primary bonus coin distribution.
    function emitDailyWinningTraits(uint24 lvl, uint256 randWord, uint24 bonusTargetLevel) external;

    /// @notice Permissionlessly resolve `player`'s Decimator jackpot claim (value credits to player).
    /// @param player Winner whose claim to resolve.
    /// @param lvl Level to claim from (must be the last decimator).
    function claimDecimatorJackpot(address player, uint24 lvl) external;

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players.
    /// @dev Non-claimable entries are skipped, not reverted.
    function claimDecimatorJackpotMany(address[] calldata players, uint24 lvl) external;

    /// @notice Claim terminal Decimator jackpot for caller.
    /// @dev Only callable post-GAMEOVER. Level is read from the resolved claim round.
    function claimTerminalDecimatorJackpot() external;

    /// @notice Physically segregate sDGNRS redemption ETH out of claimable into sDGNRS balance.
    /// @dev Access: sDGNRS only. CHECKED debit of claimableWinnings[SDGNRS] + claimablePool, then
    ///      a real ETH transfer to sDGNRS. Called at gambling-burn submit (fail-closed on shortfall).
    /// @param amount ETH amount to segregate (the MAX 175% payout for the burn).
    function pullRedemptionReserve(uint256 amount) external;

    /// @notice Pay DGNRS bounty for biggest flip record holder.
    /// @dev Called by COIN contract when bounty is paid.
    /// @param player Player receiving the bounty payout.
    /// @param winningBet FLIP value of the winning flip (must meet minimum bet threshold).
    /// @param bountyPool FLIP value of the bounty pool (must meet minimum pool threshold).
    function payCoinflipBountyDgnrs(address player, uint256 winningBet, uint256 bountyPool) external;

    /// @notice Check if RNG is currently locked (VRF request pending).
    /// @return True if RNG is locked, false otherwise.
    function rngLocked() external view returns (bool);

    /// @notice Current day index.
    function currentDayView() external view returns (uint24);

    /// @notice Request lootbox RNG when activity threshold is met.
    /// @dev Standalone function for mid-day lootbox RNG requests.
    ///      Reverts if daily RNG locked, request pending, threshold not met, or VRF fails.
    function requestLootboxRng() external;

    /// @notice Get lootbox status for a player on a specific lootbox index.
    /// @param player The player to query.
    /// @param lootboxIndex Lootbox RNG index assigned at purchase time.
    /// @return amount Lootbox value in wei.
    /// @return presale True if presale mode is currently active (global flag, not per-lootbox).
    function lootboxStatus(address player, uint48 lootboxIndex) external view returns (uint256 amount, bool presale);

    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active);

    /// @notice Open every box queued at an RNG index — the ETH-lootbox leg, the coin-presale-box
    ///         leg, or both. Claims ETH, DGNRS, WWXRP, and potential boons/boosts.
    /// @param player The player address to open for (address(0) = msg.sender).
    /// @param index The RNG index the box(es) queued at.
    function openBox(address player, uint48 index) external;

    /// @notice Buy a credit-gated coin-presale box (ETH + claimable shortfall).
    /// @param buyer Player to receive the box (address(0) = msg.sender).
    /// @param boxAmount Requested box ETH (>= 0.01 ETH; excess refunded if clamped).
    function buyPresaleBox(address buyer, uint256 boxAmount) external payable;

    /// @notice Buy tickets/lootbox AND a presale box in one tx, sharing one RNG index.
    /// @param buyer Player to receive both legs (address(0) = msg.sender).
    /// @param entryQuantityScaled Tickets to buy (0 to skip).
    /// @param lootBoxAmount ETH lootbox spend (0 to skip).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (claimable-funded).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        uint256 boxAmount
    ) external payable;

    /// @notice Spendable coin-presale-box credit accrued by a player.
    /// @param player Player to query.
    /// @return credit Remaining credit (consumed 1:1 when buying a box).
    function presaleBoxCreditOf(address player) external view returns (uint256 credit);

    /// @notice Remaining coin-presale-box ETH capacity before the 50-ETH close.
    /// @return remaining ETH still buyable in boxes (0 once presaleOver / sold out).
    function presaleBoxEthRemaining() external view returns (uint256 remaining);

    /// @notice Place Full Ticket Degenerette bets (4 traits, match-based payouts).
    /// @param player The betting player (address(0) = msg.sender).
    /// @param currency Currency type (0=ETH, 1=FLIP, 2=unsupported, 3=WWXRP).
    /// @param amountPerSpin Bet amount per ticket.
    /// @param spinCount Number of spins (1-10). Each spin resolves independently.
    /// @param customTraits Custom packed traits (use 0 for random).
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost, or 0xFF for no hero.
    function placeDegeneretteBet(
        address player,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint32 customTraits,
        uint8 heroQuadrant
    ) external payable;

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

    /// @notice Sample up to 4 trait burn tickets from a specific level.
    /// @dev View function for BAF scatter selection targeting a specific level.
    /// @param targetLvl The level to sample from.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return trait The sampled trait ID.
    /// @return entries Array of player addresses holding sampled entries.
    function sampleTraitEntriesAtLevel(uint24 targetLvl, uint256 entropy) external view returns (uint8 trait, address[] memory entries);

    /// @notice Sample up to 4 far-future ticket holders from ticketQueue.
    /// @dev View function for BAF far-future selection; samples ticketQueue at levels [current+5, current+99].
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return tickets Array of player addresses (length 0-4).
    function sampleFarFutureTickets(uint256 entropy) external view returns (address[] memory tickets);


    /// @notice Purchase a deity pass for a specific symbol (0-31).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param symbolId Symbol to claim (0-31).
    function purchaseDeityPass(address buyer, uint8 symbolId) external payable;

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    function purchaseLazyPass(address buyer) external payable;

    /// @notice Whether a player holds a deity pass.
    function hasDeityPass(address player) external view returns (bool);

    /// @notice Get raw bit-packed mint data for a player.
    /// @param player Player address to query.
    /// @return Raw packed uint256 containing mint counts, streak, pass status.
    function mintPackedFor(address player) external view returns (uint256);

    /// @notice Purchase tickets and loot boxes with ETH or claimable.
    /// @dev Main entry point for all ETH/claimable purchases.
    ///      Recycling at least 3 tickets' worth of claimable winnings earns a 10% FLIP flip-credit bonus.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param entryQuantityScaled Number of tickets to purchase (0 to skip).
    /// @param lootBoxAmount ETH amount for loot boxes, minimum 0.01 ETH (0 to skip).
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param foil True to additively buy one foil pack (10x price) in the same tx; the
    ///        foil leg is one-per-cycle and adds to, never replaces, the ticket/lootbox legs.
    function purchase(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 lootBoxAmount,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        bool foil
    ) external payable;

    /// @notice Purchase tickets with FLIP.
    /// @dev Entry point for FLIP ticket purchases.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param entryQuantityScaled Number of tickets to purchase (0 to skip).
    function redeemFlip(
        address buyer,
        uint256 entryQuantityScaled
    ) external;

    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level (v51.0).
    /// @dev Tiered reward (regular / symbol-first / quadrant-first); dispatches to the bingo module.
    ///      Sender-or-approved: settles to `player` (address(0) = msg.sender, else operator-approved).
    /// @param player Bingo owner to claim for (address(0) = msg.sender).
    /// @param level The level to claim on (uint24 storage-key width).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in lvlTraitEntry[level][traitId] the owner occupies.
    function claimBingo(address player, uint24 level, uint8 symbol, uint32[8] calldata slots) external;

    // -------------------------------------------------------------------------
    // Degenerette Tracking Views
    // -------------------------------------------------------------------------

    /// @notice Get total wager units for a specific hero symbol on a given day.
    function getDailyHeroWager(uint24 day, uint8 quadrant, uint8 symbol) external view returns (uint256 wagerUnits);
    /// @notice Get the winning hero symbol and amount for a given day.
    function getDailyHeroWinner(uint24 day) external view returns (uint8 winQuadrant, uint8 winSymbol, uint256 winAmount);

    // -------------------------------------------------------------------------
    // Raw-forwarded dispatch stubs
    //
    // The Game-side implementations of these functions forward msg.data to their
    // module unchanged (signature-identical selectors), so their parameters are
    // unnamed at the implementation site. These declarations carry the canonical
    // named-parameter NatSpec for the Game's external ABI.
    // -------------------------------------------------------------------------

    /// @notice Configure the Chainlink VRF coordinator and subscription (one-shot wire).
    /// @param coordinator_ Address of the VRF coordinator contract.
    /// @param subId Chainlink VRF subscription ID.
    /// @param keyHash_ Key hash for the VRF request.
    function wireVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external;

    /// @notice Update VRF coordinator, subscription, and key hash configuration.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for VRF requests.
    function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash) external;

    /// @notice VRF callback to receive random words.
    /// @dev Coordinator-gated in the module body (delegatecall preserves msg.sender).
    /// @param requestId The ID of the VRF request being fulfilled.
    /// @param randomWords Array of random words returned by VRF.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;

    /// @notice The SINGLE AfKing subscription entrypoint: create / replace (dailyQuantity >= 1)
    ///         or cancel (dailyQuantity == 0) for `player` (self when address(0)/msg.sender).
    /// @param player Subscriber (address(0) = msg.sender).
    /// @param drainGameCreditFirst Spend game credit before fresh ETH.
    /// @param useTickets Deliver tickets (true) or lootbox deposits (false).
    /// @param dailyQuantity Daily delivery quantity; 0 cancels the subscription.
    /// @param fundingSource Account funding the subscription (operator-approval gated).
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        address fundingSource
    ) external payable;

    /// @notice Permissionless FLIP claim — pays each sub its accrued pendingFlip in one
    ///         creditFlip and zeroes it; always credits the sub, never the caller.
    /// @param subs Subscribers to pay out.
    function claimAfkingFlip(address[] calldata subs) external;

    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued affiliateBase.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained).
    function drainAffiliateBase(address sub) external returns (uint256 base);

    /// @notice QUESTS-only: bump an afking sub's streak base for a secondary/level completion.
    /// @param player The afking subscriber whose secondary completion is recorded.
    /// @param amount The streak-base increment (1 for a daily secondary, more for a level quest).
    function recordAfkingSecondary(address player, uint16 amount) external;

    /// @notice QUESTS-only: floor an afking sub's streak base to `floor`, so a foil-pack
    ///         purchase's quest-streak guarantee reaches a mid-run afker (whose reward streak
    ///         is the sub base plus funded delivered days, not the manual quest streak).
    /// @param player The afking subscriber whose streak base is floored.
    /// @param floor The minimum streak base to set (no-op if the base is already at/above it).
    function floorAfkingStreakBase(address player, uint16 floor) external;

    /// @notice Permissionless paid cure: clear `target`'s cashout/smite curse for 100 FLIP.
    /// @param target The cursed player to cure.
    function decurse(address target) external;

    /// @notice Deity-gated smite: add a saturating curse stack to `smitee` for 200 FLIP.
    /// @param deityId The smiting deity's pass ID (caller must hold it).
    /// @param smitee The player receiving the curse stack.
    function smite(uint256 deityId, address smitee) external;

    /// @notice Claim DGNRS affiliate rewards for the current level (single affiliate).
    /// @param player Affiliate address to claim for (address(0) = msg.sender).
    function claimAffiliateDgnrs(address player) external;

    /// @notice Permissionless batch affiliate-DGNRS claim; a blank array claims the caller's own.
    /// @param affiliates Affiliates to settle; empty = msg.sender only.
    function claimAffiliateDgnrs(address[] calldata affiliates) external;

    /// @notice Quote a far-future salvage swap WITHOUT executing (read-only in effect;
    ///         declared non-view because the Game dispatches it via delegatecall).
    /// @param player Ticket holder being quoted.
    /// @param levels Far-future levels to quote.
    /// @param quantities Entry quantities per level (4 entries = 1 whole ticket; parallel to `levels`).
    /// @return totalFaceWei Total face value of the quoted entries.
    /// @return totalBudget Salvage budget available against the quote.
    /// @return ticketWei Current-level ticket leg of the offer.
    /// @return ethCashWei ETH leg of the offer.
    /// @return flipTokens FLIP leg of the offer.
    function previewSellFarFutureEntries(
        address player,
        uint32[] calldata levels,
        uint256[] calldata quantities
    )
        external
        returns (
            uint256 totalFaceWei,
            uint256 totalBudget,
            uint256 ticketWei,
            uint256 ethCashWei,
            uint256 flipTokens
        );

    /// @notice Credit the direct half of an sDGNRS redemption claim to `player`'s claimable winnings.
    /// @param player Claimant credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(address player, uint256 amount) external payable;
}
