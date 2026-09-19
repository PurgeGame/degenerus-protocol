// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement, and controls over every comment, name,
 * document and statement made about it. It has been audited but is not proven correct:
 * it may contain defects the author did not find, and by interacting with it you accept
 * that risk in full.
 *
 * Any state transition the code permits is authorised — including one that exploits a
 * defect, and including sequences the author did not intend or foresee. A bug is not a
 * breach of these terms. There is no unwritten rule behind the code for a permitted
 * transaction to violate, and no unauthorised access to this contract.
 *
 * You bear all resulting loss, whether it follows from chance or from a defect. There is
 * no refund, no rollback and no privileged party able to restore a position.
 *
 * Provided AS IS, without warranty of any kind. Full text: TERMS.md
 */

/// @notice Payment method for ticket purchases.
enum MintPaymentKind {
    DirectEth,   // Fresh ETH first; prepaid afking covers a shortfall; claimable never drawn
    Claimable,   // No fresh ETH; claimable (to its 1-wei sentinel), then prepaid afking
    Combined,    // Fresh ETH first, then claimable, then prepaid afking
    Internal     // Protocol-internal debit (shortfall, salvage, redemption, game-over sweep)
}

/// @title IDegenerusGame
/// @notice Core game contract interface for state machine, purchases, and prize pool management.
/// @dev Per level: a purchase phase (jackpotPhase()==false) transitions to a multi-day jackpot
///      payout phase (jackpotPhase()==true) once the prize target is met, then the level advances.
///      Ticket purchases stay open in both phases. gameOver() is terminal.
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
    /// @dev Purchase phase: true past the purchase deadline (365 days at level 0, 120
    ///      after) unless a pre-deadline VRF request is still inside its 14-day grace.
    ///      Jackpot / last-purchase: true only once no day has sealed for 120 days.
    function livenessTriggered() external view returns (bool);

    /// @notice Check if the final fund forfeiture has executed (all funds forfeited).
    function isFinalSwept() external view returns (bool);

    /// @notice Get the current mint price in wei.
    /// @return Base price unit in wei.
    function mintPrice() external view returns (uint256);

    /// @notice Check if decimator window is currently open.
    /// @return True if decimator entries are allowed.
    function decWindow() external view returns (bool);

    /// @notice Raw jackpot compression flag.
    /// @dev Latched at target-met: 1 (compressed: the five logical jackpot days settle over three
    ///      physical days, the day counter stepping 0, 1, 3, end) when the target is met
    ///      within 3 days of the purchase start; 2 (turbo, 1 day) when the target is met within
    ///      1 day of the purchase start on any level (a BAF level latches it at the sealed day's
    ///      settlement, every other level at the morning arm). A turbo's 2 lingers through the
    ///      next level's first purchase-day settlement as the coinflip bonus latch; 3 marks a
    ///      back-to-back turbo armed on that day.
    /// @return Raw flag: 0=normal, 1=compressed, 2=turbo or lingering bonus latch, 3=chained turbo.
    function jackpotCompressionTier() external view returns (uint8);

    /// @notice Get comprehensive purchase information in a single call.
    /// @dev Gas-optimized batch query: lvl is the ACTUAL game level (on-chain consumers key on
    ///      it from this one snapshot, avoiding a second level() read), while priceWei is the
    ///      buy-now price at the ROUTED ticket level. The two diverge during the purchase phase
    ///      and the final jackpot RNG window (buys route to level+1) — this is intentional.
    /// @return lvl Actual current game level.
    /// @return inJackpotPhase True if jackpot phase is active.
    /// @return lastPurchaseDay_ True once the level's prize target is met (jackpot transition pending); purchases stay open.
    /// @return rngLocked_ True during daily RNG processing, from request through the day seal.
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

    /// @notice Everything the growth-bet parimutuel reads out of the game.
    /// @param round The round to report pool terms for; 0 skips the pool reads.
    /// @return prevPool The ratchet entry for round - 1.
    /// @return currPool The ratchet entry for round.
    /// @return nextPool The ratchet entry for round + 1 (0 until the successor banks).
    /// @return currentLevel The current game level — the round a bet placed now joins.
    /// @return bettingOpen True while the jackpot phase is live, its draws have not ended
    ///         (phaseTransitionActive clear) and the level is not turbo
    ///         (compressedJackpotFlag < 2). The RNG lock is not consulted: the market
    ///         consumes no randomness and its terms are write-once. `bettingOpen` has no
    ///         gameOver leg: a deadman-triggered game over inside a jackpot phase leaves
    ///         jackpotPhaseFlag set, so the market can still read open after game over.
    /// @return phaseDay Jackpot-phase day counter, which decays the quest reward. The
    ///         phase runs five logical jackpot days; the counter reads k once logical day k's
    ///         processing completes, and completing day 5 ends the phase in the same advance,
    ///         so an open market reads 0-4. A compressed phase settles them over three
    ///         physical days (counter 0, 1, 3, then end); turbo settles all five in one. 0 is
    ///         only the sliver between the transition and the same day's first processing.
    function growthState(uint24 round)
        external
        view
        returns (
            uint256 prevPool,
            uint256 currPool,
            uint256 nextPool,
            uint24 currentLevel,
            bool bettingOpen,
            uint8 phaseDay
        );

    /// @notice Consume the caller's boon lane for the next stake bonus.
    /// @dev Access: COIN or COINFLIP. The caller names the lane — COINFLIP grants the bonus to the
    ///      next coinflip deposit, COIN (FLIP) grants it to the paid craps burn in flight. The two
    ///      lanes are disjoint and neither caller can reach the other's.
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
    /// @return dailySeed Yesterday's finalized RNG word for today's boons (0 if unavailable).
    /// @return day Current day index.
    /// @return usedMask Bitmask of slots already used (bit i = slot i used).
    /// @return decimatorOpen Whether decimator boons are available.
    /// @return deityPassAvailable Whether deity pass boons can be generated.
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

    /// @notice Initialize both protocol deities in one post-deployment batch (creator only, once).
    function initProtocolDeity() external;

    /// @notice Enter the caller's protocol boon draw, staking donor FLIP for tomorrow.
    function enterProtocolBoonDraw(address donor, uint256 amount) external;


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

    /// @notice Game-over terminal jackpot: Day-5-style bucket distribution to the final ticket cohort.
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
    /// @param lvl Resolved level whose unclaimed winning position is being settled (any snapshotted round).
    function claimDecimatorJackpot(address player, uint24 lvl) external;

    /// @notice Permissionlessly resolve Decimator jackpot claims for a batch of players.
    /// @dev Non-claimable entries are skipped, not reverted.
    function claimDecimatorJackpotMany(address[] calldata players, uint24 lvl) external;

    /// @notice Back an sDGNRS redemption reservation: segregate game-side ETH, or verify custody.
    /// @dev Access: sDGNRS only. Called at gambling-burn submit, fail-closed. Two legs: when
    ///      claimableWinnings[SDGNRS] AND the game's liquid ETH both cover `amount`, a CHECKED
    ///      debit of claimableWinnings[SDGNRS] + claimablePool moves that ETH out to sDGNRS (ETH
    ///      leg); otherwise sDGNRS's own ETH + stETH custody must cover every outstanding
    ///      reservation plus this one, with no game-side move or ledger debit (custody leg). Either
    ///      way the reservation is backed sDGNRS-side, so it is never part of the game's balance.
    /// @param amount ETH value to reserve (the MAX 175% payout for the burn).
    function pullRedemptionReserve(uint256 amount) external;

    /// @notice Pay the sDGNRS leg of an all-time record claim.
    /// @dev COINFLIP only. Pays the claim's accrued record-pool share at 1/500 scale
    ///      from the sDGNRS reward pool.
    /// @param player Recipient of the sDGNRS.
    /// @param shareBps The claim's accrued record-pool share in bps.
    /// @return paid The sDGNRS actually transferred.
    function payRecordSdgnrs(address player, uint256 shareBps) external returns (uint256 paid);

    /// @notice Check if the daily RNG processing lock is set (request through day seal; not set for mid-day requests).
    /// @return True if RNG is locked, false otherwise.
    function rngLocked() external view returns (bool);

    /// @notice Current day index.
    function currentDayView() external view returns (uint24);

    /// @notice Request lootbox RNG when activity threshold is met.
    /// @dev Standalone function for mid-day lootbox RNG requests.
    ///      Reverts if daily RNG locked, request pending, threshold not met, or VRF fails.
    ///      The craps table clears the pending-value gates unconditionally and answers to a
    ///      lower LINK floor — it requests to settle a bound window, not to drain the lootbox
    ///      queue. Every timing gate still binds on it.
    function requestLootboxRng() external;

    /// @notice Mint mid-day RNG credit to a LINK donor.
    /// @dev Access: ADMIN only. Credits waive the pending-value gates on
    ///      requestLootboxRng; the subscription LINK floor there still applies.
    /// @param to Donor to credit.
    /// @param linkAmount LINK donated, in juels.
    function creditMiddayRng(address to, uint256 linkAmount) external;


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
    /// @param boxAmount Requested box ETH (>= 0.01 ETH; overpay and clamp-to-50 excess credit to AFKing).
    function buyPresaleBox(address buyer, uint256 boxAmount) external payable;

    /// @notice Buy tickets/lootbox AND a presale box in one tx, sharing one RNG index.
    /// @param buyer Player to receive both legs (address(0) = msg.sender).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @param boxOrder Packed box order (0 to skip; see purchase()).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (funded by the mint leg's leftover fresh ETH,
    ///        then claimable, then afking).
    function buyLootboxAndPresaleBox(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
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
    /// @param spinCount Number of spins (1..25 ETH, 1..15 FLIP, 1..5 WWXRP). Each spin resolves independently.
    /// @param customTraits Four packed quadrant bytes; all-zero is a valid fixed selection, not random.
    /// @param heroQuadrant Hero quadrant (0-3) for payout boost; values >= 4 revert.
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

    /// @notice Sample four far-future candidate slots for BAF.
    /// @dev Sample one populated level in [current+5, current+99], then additional levels
    ///      only as needed to fill four slots; duplicate owners across levels are allowed.
    ///      Call during BAF, before the current level's far-future promotion.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return tickets Four live queue owners (addresses may repeat).
    function sampleFarFutureTickets(uint256 entropy) external view returns (address[] memory tickets);


    /// @notice Purchase a deity pass for a specific symbol (0-31).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param symbolId Symbol to claim (0-31).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    function purchaseDeityPass(
        address buyer,
        uint8 symbolId,
        bytes32 affiliateCode
    ) external payable;

    /// @notice Purchase a 10-level lazy pass (direct in-game activation).
    /// @param buyer Player address to receive pass (address(0) = msg.sender).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    function purchaseLazyPass(address buyer, bytes32 affiliateCode) external payable;

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
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @param boxOrder Packed box order (0 to skip):
    ///        [small:8][med:8][large:8][customCount:8][customSize:48 in 1e12-wei units].
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param foil True to additively buy one foil pack (10x price) in the same tx; the
    ///        foil leg is one-per-cycle and adds to, never replaces, the ticket/lootbox legs.
    function purchase(
        address buyer,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        bool foil
    ) external payable;

    /// @notice Purchase tickets with FLIP.
    /// @dev Entry point for FLIP ticket purchases.
    /// @param buyer Player address to receive purchases (address(0) = msg.sender).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    function redeemFlip(
        address buyer,
        uint256 entryQuantityScaled
    ) external;

    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @dev One reward per player per level; dispatches to the bingo module. Permissionless:
    ///      settles to `player`, the slot owner, never the caller (address(0) = msg.sender).
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
