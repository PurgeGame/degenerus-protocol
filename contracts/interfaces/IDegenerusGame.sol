// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {LiquidationQuote} from "./ILiquidation.sol";

import {MineFlipGas} from "../libraries/MineFlipGas.sol";

/*
 * TERMS OF INTERACTION — submitting a transaction to this contract accepts them.
 *
 * THIS IS GAMBLING. Outcomes are decided by chance. You can lose everything you put in
 * simply by being unlucky. That is the software working exactly as intended. Do not
 * commit funds you are not prepared to lose entirely.
 *
 * The deployed bytecode is the entire agreement and the exclusive source of truth; any
 * comment, name, document or statement that disagrees with it is in error. It has been
 * audited but is not proven correct: it may contain defects the author did not find, and
 * by interacting with it you accept that risk in full.
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
    Internal     // Protocol-internal debit (shortfall, liquidation, redemption, game-over sweep)
}

/// @title IDegenerusGame
/// @notice Core game contract interface for state machine, purchases, and prize pool management.
/// @dev Per level: a purchase phase (jackpotPhase()==false) transitions to a multi-day jackpot
///      payout phase (jackpotPhase()==true) once the prize target is met, then the level advances.
///      Ticket purchases stay open in both phases. gameOver() is terminal.
///
///      ACCOUNTS. Every player entry point names the account it acts for by wallet ID, never by
///      address. An account is an ordinary wallet or a smurf (an extra account a wallet created
///      with `createSmurf`; it stores an owner ID and has no address). The account rule:
///      - `id == 0` is the caller. The forward wallet registry supplies the caller's ID.
///      - Any other `id` must be allocated (`0 < id < wallets.length`), else `E`.
///      - Authorized entry points require the caller to be the account's key, the owner of a
///        smurf account, or an operator approved for that ID (`setOperatorApproval`), else
///        `NotApproved`. Permissionless doors (claims that only credit the account) skip the
///        check. Gift doors (Degenerette bets) treat an unauthorized caller as a gift funder.
///      - Game state (ledgers, quests, mint history, pricing, events) follows the account.
///      - Value paid out (ETH, stETH, FLIP, WWXRP, DGNRS, sDGNRS, seat and deity NFTs) goes to the
///        account's PAYEE: the caller for `id == 0`, the key of an ordinary wallet, or the owner's
///        key for a smurf. Tokens pulled or burned from a player's wallet come from the payee.
///      - Third-party recipients (deity-boon recipient, AFKing deposit beneficiary, AFKing
///        funding source) are IDs that must already exist: 0 or an unallocated ID reverts `E`.
interface IDegenerusGame {
    function liquidateAccount(uint32 id, uint256 minEthOut) external;
    function previewLiquidateAccount(uint32 id) external returns (LiquidationQuote memory);
    function harvestAcquiredAccounts(uint32 buyer, uint32[] calldata ids) external returns (uint256);

    /// @notice Wallet-ID hook for trusted protocol contracts: existing ID, or with `allocate` a new
    ///         one subject to paid admission. Non-allocating calls return zero for unregistered wallets.
    function registerWallet(address owner, bool allocate) external returns (uint32 id);
    function registerWalletIdentity(address owner) external returns (uint32 id);
    function walletIdentityOf(address owner) external view returns (uint32);
    function acquiredBuyer(uint32 id) external view returns (uint32 buyerId);
    /// @notice A wallet's current gameplay ID, or zero before registration/after liquidation.
    function walletIdOf(address player) external view returns (uint32);

    /// @notice Resolve an allocated account's payee and caller authorization.
    /// @dev Ordinary accounts return their address as `key`; subaccounts return zero.
    ///      Subaccounts store an owner ID, resolved to an ordinary wallet for payouts.
    ///      Authorization is the current payee, or an operator approval on an unsold account.
    ///      Authorization failure returns false; zero or unallocated IDs revert E.
    function resolveAccount(uint32 id, address caller)
        external view returns (address key, address payee, bool authorized);

    /// @notice Approve or revoke `operator` for account `id` (game-wide delegated control).
    /// @dev `id == 0` is the caller's own account, which must already hold an ID (approving pays
    ///      nothing, so it never registers). A nonzero `id` must be allocated and the caller must be
    ///      its key or, for a smurf, its owner: operators cannot approve operators. Approvals are
    ///      keyed `operatorApprovals[id][operator]`; the operator stays an address because it is a
    ///      real caller. Emits `OperatorApproval(uint32 indexed id, address indexed operator, bool)`.
    /// @param id Account to manage (0 = caller).
    /// @param operator Address to approve or revoke.
    /// @param approved True to approve, false to revoke.
    /// @custom:reverts ZeroAddress If `operator` is the zero address.
    /// @custom:reverts E If `id == 0` and the caller has no ID, or `id` is unallocated.
    /// @custom:reverts NotApproved If the caller is neither the key nor the smurf's owner.
    function setOperatorApproval(uint32 id, address operator, bool approved) external;

    /// @notice Create a smurf account owned by the caller, give it the caller's referrer and buy it
    ///         one ticket, all in one call.
    /// @dev Owner = `msg.sender`, which must already hold an ordinary wallet ID. Steps, atomically:
    ///      1. Resolve the owner's referral exactly as a purchase does: an unset referral is set
    ///         from `affiliateCode`, or locked to no referrer for a blank or invalid code; a set
    ///         referral ignores the code.
    ///      2. Allocate the next ID, storing only `ownerId << 160` in its wallet-table element.
    ///         Set the account's mint-word smurf flag and emit `SmurfCreated(ownerId, smurfId)`.
    ///      3. Copy the owner's resolved referral word to the smurf, locked (Affiliate
    ///         `copyReferral`). An owner with no referrer gives a smurf with none.
    ///      4. Buy exactly one whole ticket (400 scaled units, no boxes) for the smurf at the
    ///         current price. The owner pays: fresh `msg.value` first, then the owner's claimable
    ///         and AFKing balances as `payKind` allows, exactly as `purchase` spends a buyer's.
    ///         Fresh ETH above the price credits the owner's AFKing balance. The ticket, mint
    ///         history and quest progress belong to the smurf.
    ///      Past PAID_ADMISSION_WALLETS the allocation is admitted only when the ticket price is
    ///      at least PAID_ADMISSION_MIN_SPEND (`quotedSpend` = the ticket price).
    /// @param affiliateCode Referral code applied to the owner if its referral is unset.
    /// @param payKind How the owner funds the ticket (DirectEth, Claimable or Combined).
    /// @return smurfId The new account's wallet ID.
    /// @custom:reverts E If the caller has no wallet ID or paid admission refuses the allocation.
    /// @custom:reverts (purchase) Every revert of a one-ticket `purchase` by the owner (RNG lock,
    ///                 liveness/game over, insufficient payment).
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        external payable returns (uint32 smurfId);
    /// @notice Read a raw storage slot; used for permanent identity lookups with pinned roots.
    function extsload(bytes32 slot) external view returns (bytes32 value);
    /// @notice Allowed read consumer: 0 blocked, 1 redemption, 2 AFK, 3 boxes/bets, 4 Decimator, 5 Craps, 6 complete.
    function rngConsumerStage() external view returns (uint8);

    /// @notice Get the current jackpot level.
    /// @return Current jackpot level (starts at 0).
    function level() external view returns (uint24);

    /// @notice Get the current game phase using jackpot semantics.
    /// @return True if jackpot phase is active, false if purchase phase.
    function jackpotPhase() external view returns (bool);

    /// @notice Check if the game has ended (terminal state).
    function gameOver() external view returns (bool);

    /// @notice Whether the liveness-timeout game-over trigger is currently active.
    /// @dev Purchase phase: true past the purchase deadline (250 days at level 0, 30
    ///      after) unless a pre-deadline VRF request is still inside its 14-day grace.
    ///      Jackpot / last-purchase: true only once no day has sealed for 30 days.
    function livenessTriggered() external view returns (bool);

    /// @notice Check if the final fund forfeiture has executed (all funds forfeited).
    function isFinalSwept() external view returns (bool);

    /// @notice Get the current mint price in wei.
    /// @return Base price unit in wei.
    function mintPrice() external view returns (uint256);

    /// @notice Check if decimator window is currently open.
    /// @return True if decimator entries are allowed.
    function decWindow() external view returns (bool);

    /// @notice Selected jackpot duration: one day for turbo, otherwise three days.
    function jackpotDuration() external view returns (uint8);

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
    /// @return scorePoints Activity score in whole points.
    /// @return walletId The player's wallet ID (zero if unregistered).
    function playerActivityScore(address player) external view returns (uint256 scorePoints, uint32 walletId);

    /// @notice Address convenience form; never allocates identity.
    function playerActivityScoreCached(address player) external returns (uint256 score, uint32 id);
    /// @notice Account activity score, including effective quest streak.
    function playerActivityScoreById(uint32 id) external view returns (uint256);
    /// @notice Account activity score; refreshes its current-level affiliate cache.
    function playerActivityScoreCachedById(uint32 id) external returns (uint256);

    /// @notice Everything the growth-bet parimutuel reads out of the game.
    /// @param round The round to report pool terms for; 0 skips the pool reads.
    /// @return prevPool The ratchet entry for round - 1.
    /// @return currPool The ratchet entry for round.
    /// @return nextPool The ratchet entry for round + 1 (0 until the successor banks).
    /// @return currentLevel The current game level — the round a bet placed now joins.
    /// @return bettingOpen True while the jackpot phase is live, its draws have not ended
    ///         (phaseTransitionActive clear) and the level is not turbo
    ///         ((jackpotFlags & JACKPOT_TURBO) == 0). The RNG lock is not consulted: the market
    ///         consumes no randomness and its terms are write-once. `bettingOpen` has no
    ///         gameOver leg: a deadman-triggered game over inside a jackpot phase leaves
    ///         jackpotPhaseFlag set, so the market can still read open after game over.
    /// @return phaseDay Physical jackpot draws completed: 0 before the first draw,
    ///         then 1 or 2 while a standard phase remains open. The third draw closes
    ///         betting; turbo's only draw closes its phase without opening a market.
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
    /// @dev Access: COINFLIP, COIN or WWXRP. The caller selects its own lane: coinflip,
    ///      craps or WWXRP respectively. WWXRP exposes a separate consumption hook to
    ///      its trusted-minter applications; those applications cannot call this directly.
    ///      Boon state is keyed by wallet ID; `id == 0` returns 0 (no boon), never reverts.
    /// @param id Wallet ID of the player consuming the boon.
    /// @return boostBps Boost amount in basis points.
    /// @custom:reverts Unauthorized If caller is not COINFLIP, COIN or WWXRP.
    function consumeCoinflipBoon(uint32 id) external returns (uint16 boostBps);

    /// @notice Consume decimator boon for burn boost.
    /// @dev Access: COIN only. Grants bonus to next decimator burn. Boon state is keyed by
    ///      wallet ID; `id == 0` returns 0 (no boon), never reverts.
    /// @param id Wallet ID of the player consuming the boon.
    /// @return boostBps Boost amount in basis points.
    /// @custom:reverts Unauthorized If caller is not COIN.
    function consumeDecimatorBoon(uint32 id) external returns (uint16 boostBps);

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

    /// @notice Deity boon menu for an account, including a subaccount.
    function deityBoonDataById(uint32 deityId) external view returns (
        uint256 dailySeed, uint24 day, uint8 usedMask, bool decimatorOpen, bool deityPassAvailable
    );

    /// @notice Issue a deity boon from deity account `deityId` to account `recipientId`.
    /// @dev Authorized (account rule): `deityId == 0` is the caller; otherwise the caller must be the
    ///      deity account's key, its owner (smurf deity) or an approved operator. The deity account
    ///      must hold HAS_DEITY_PASS. The recipient is a third party: an existing ID, never 0. Self
    ///      boons are compared by ID; a deity may boon its owner or its owner's other smurfs (no
    ///      smurf-specific limit). Boon state is written for the recipient ID; no value moves.
    /// @param deityId Deity account issuing the boon (0 = caller).
    /// @param recipientId Recipient account (nonzero, allocated).
    /// @param slot Slot index (0-2).
    /// @custom:reverts NotApproved If the caller may not act for `deityId`.
    /// @custom:reverts E If `deityId` or `recipientId` is unallocated, or `recipientId == 0`.
    /// @custom:reverts SelfBoon If the resolved deity ID equals `recipientId`.
    function issueDeityBoon(uint32 deityId, uint32 recipientId, uint8 slot) external;

    /// @notice Initialize both protocol deities in one post-deployment batch (creator only, once).
    function initProtocolDeity() external;



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
    /// @param lvl Resolution level (current game level + 1).
    /// @param baseAmount Burn amount before multiplier.
    /// @param multBps Multiplier in basis points (10000 = 1x).
    /// @param chips The entry's board: zero to seven named chips, as a normal battle takes them.
    /// @return entryId The wallet's accumulated battle entry.
    function recordDecBurn(
        uint32 player,
        uint24 lvl,
        uint256 baseAmount,
        uint256 multBps,
        uint32 chips
    ) external returns (uint64 entryId);

    /// @notice Seal a Decimator battle for bounded run and payout settlement.
    /// @param poolWei Total ETH prize pool for this level.
    /// @param lvl Level number being resolved.
    /// @param rngWord VRF-derived randomness seed.
    /// @return returnAmountWei Amount to return (no entries or this round was already sealed).
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

    /// @notice Game-over terminal jackpot: final-day bucket distribution to the final ticket
    ///         cohort, continued through the shared gas allowance.
    function runTerminalJackpotWork(uint256 poolWei, uint24 targetLvl, uint256 rngWord, uint256 allowance)
        external returns (MineFlipGas.Result memory result, uint256 paidDelta);

    /// @notice Roll, record and emit level 1's purchase-day board without running any
    ///         distribution. Used at purchaseLevel==1 where runDailyJackpot is skipped.
    /// @param randWord VRF entropy for the board.
    function emitDailyWinningTraits(uint256 randWord) external;

    /// @notice Pay the sDGNRS leg of an all-time record claim and name the record's payee.
    /// @dev COINFLIP only. Pays the claim's accrued record-pool share at 1/500 scale
    ///      from the sDGNRS reward pool to the payee Game resolves for `id` (the wallet's own
    ///      address, or the owner's for a smurf). `payee` is returned on
    ///      every call, including `shareBps == 0`, an empty pool and a zero payout: Coinflip
    ///      calls this on every record ratchet and mints the record trophy to `payee`.
    ///      Coinflip passes only nonzero IDs (its callers hold them).
    /// @param id Wallet ID of the record holder.
    /// @param shareBps The claim's accrued record-pool share in bps (0 for a ratchet that
    ///        claims nothing).
    /// @return paid The sDGNRS actually transferred.
    /// @return payee The address that received (or would receive) the sDGNRS and the trophy.
    /// @custom:reverts Unauthorized If caller is not COINFLIP.
    function payRecordSdgnrs(uint32 id, uint256 shareBps) external returns (uint256 paid, address payee);

    /// @notice Check if the daily RNG processing lock is set (request through day seal; not set for mid-day requests).
    /// @return True if RNG is locked, false otherwise.
    function rngLocked() external view returns (bool);

    /// @notice Whether every consumer of the previous RNG cycle has completed.
    function rngComplete() external view returns (bool);

    /// @notice Current day index.
    function currentDayView() external view returns (uint24);

    /// @notice Admin-only transport retry of an unanswered request after its 20-hour timeout.
    function retryRng() external;

    /// @notice Mint mid-day RNG credit to a LINK donor.
    /// @dev Access: ADMIN only. A donor's mineFlip spends credit on the mid-day request when
    ///      pending work sits below the threshold; the subscription LINK floor still applies.
    ///      A donation is a paying action: the donor is registered (existing ID or a new one)
    ///      and the ID is returned so Admin credits the donation's FLIP reward by ID.
    /// @param to Donor to credit.
    /// @param linkAmount LINK donated, in juels.
    /// @return id The donor's wallet ID (never 0).
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
    /// @custom:reverts E If the donor is new past paid admission (PAID_ADMISSION_WALLETS
    ///                 registered wallets; a donation quotes no Game spend).
    function creditMiddayRng(address to, uint256 linkAmount) external returns (uint32 id);


    /// @notice Check whether lootbox presale mode is currently active.
    /// @return active True if presale is active.
    function lootboxPresaleActiveFlag() external view returns (bool active);

    /// @notice Buy a credit-gated coin-presale box (ETH + claimable shortfall) for account `id`.
    /// @dev Authorized (account rule). The box, its credit gate and the claimable/AFKing legs are
    ///      the account's; fresh ETH comes from the caller. Overpay and clamp-to-50 excess credit
    ///      the payer's AFKing balance: the account's own ID when the caller is the account, else
    ///      the caller's existing ID. Box payouts go to the account's payee.
    /// @param id Account receiving the box (0 = caller).
    /// @param boxAmount Requested box ETH (>= 0.01 ETH; overpay and clamp-to-50 excess credit to AFKing).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function buyPresaleBox(uint32 id, uint256 boxAmount) external payable;

    /// @notice Buy tickets/lootbox AND a presale box in one tx for account `id`, sharing one RNG index.
    /// @dev Authorized (account rule); funding and refunds as `purchase`.
    /// @param id Account receiving both legs (0 = caller).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @param boxOrder Packed box order (0 to skip; see purchase()).
    /// @param affiliateCode Affiliate/referral code for the mint leg.
    /// @param payKind Payment method for the mint leg.
    /// @param boxAmount Requested presale-box ETH (funded by the mint leg's leftover fresh ETH,
    ///        then claimable, then afking).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function buyLootboxAndPresaleBox(
        uint32 id,
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

    /// @notice Place single-symbol Degenerette bets for account `id`.
    /// @dev Gift door. `id == 0` is the caller. When the caller is authorized for `id` (key, smurf
    ///      owner or approved operator) the account funds the bet: fresh ETH from the caller, the
    ///      claimable shortfall from the account's ledger, FLIP burned from the account's payee,
    ///      and the quest credit goes to the account. Any other caller makes a permissionless
    ///      gift: the caller funds the whole bet itself (its own ETH, claimable or FLIP; the
    ///      caller is registered as a paying funder) and earns the quest; the bet belongs to
    ///      `id`, which must already exist. Winnings follow the account and pay its payee.
    /// @param id The betting account (0 = caller).
    /// @param currency Currency type (0=ETH, 1=FLIP; all other values unsupported).
    /// @param amountPerSpin Bet amount per ticket.
    /// @param spinCount Number of spins (1..25 ETH, 1..15 FLIP). Each spin resolves independently.
    /// @param symbol Chosen hero symbol (0..23: Crypto, Zodiac, Cards); quadrant = symbol >> 3.
    /// @custom:reverts E If `id` is unallocated (gift or not).
    function placeDegeneretteBet(
        uint32 id,
        uint8 currency,
        uint128 amountPerSpin,
        uint8 spinCount,
        uint8 symbol
    ) external payable;

    /// @notice View a queued Degenerette bet word (zero once resolved or unknown).
    /// @param index Lootbox RNG index the bet was placed at.
    /// @param betId Bet id within `index` (queue position + 1).
    /// @return packed Compact lane: owner32, symbol5, spins5, currency1, record1, activity16, stake64.
    function degeneretteBetInfo(
        uint48 index,
        uint64 betId
    )
        external
        view
        returns (uint256 packed);

    /// @notice Sample up to 4 trait burn tickets from a specific level.
    /// @dev View function for BAF scatter selection targeting a specific level. Returns the
    ///      wallet IDs the trait bucket already stores (no wallet-table decode).
    /// @param nextLevel Select the next level instead of the current level.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @return trait The sampled trait ID.
    /// @return entries Wallet IDs holding the sampled entries (IDs may repeat).
    function sampleTraitEntries(bool nextLevel, uint256 entropy) external view returns (uint8 trait, uint32[] memory entries);

    /// @notice Sample two BAF rounds' worth of unminted future-level candidates.
    /// @dev Four packs (independent level in [fromLevel, toLevel] + one random eight-lane queue
    ///      word), two distinct lanes each: slots 0..3 feed one round and 4..7 the next, so
    ///      each round's candidates come from four different packs. Unfilled slots are
    ///      0. Call during BAF with unminted levels only (above current+1). Returns the
    ///      wallet IDs the queue lanes already store (no wallet-table decode).
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @param fromLevel Lowest candidate level (inclusive).
    /// @param toLevel Highest candidate level (inclusive).
    /// @return tickets Eight candidate slots as wallet IDs (may repeat; 0 = unfilled).
    function sampleFarFutureTickets(uint256 entropy, uint24 fromLevel, uint24 toLevel)
        external view returns (uint32[] memory tickets);


    /// @notice Purchase a deity pass for a specific symbol (0-31) for account `id`.
    /// @dev Authorized (account rule). One deity per main wallet: the main of an account is its
    ///      payee (the owner for a smurf, itself otherwise), and the purchase reverts when any
    ///      existing deity's main equals the buyer's main (a scan of at most 32 deity IDs). The
    ///      buying account keeps HAS_DEITY_PASS and every deity behaviour (perpetual tickets, boons
    ///      issued as that deity, refunds by its ID); the soulbound pass NFT, the buyer's DGNRS
    ///      reward and the free-tranche seat go to the payee. Funding and refunds as `purchase`.
    /// @param id Account buying the pass (0 = caller).
    /// @param symbolId Symbol to claim (0-31).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    /// @custom:reverts AlreadyOwnsDeityPass If the account, or any account with the same main
    ///                 wallet, already holds a deity pass.
    function purchaseDeityPass(
        uint32 id,
        uint8 symbolId,
        bytes32 affiliateCode
    ) external payable;

    /// @notice Purchase a 10-level lazy pass (direct in-game activation) for account `id`.
    /// @dev Authorized (account rule). The pass is the account's; the free-tranche seat (one per
    ///      account for life) mints to the payee. Funding and refunds as `purchase`.
    /// @param id Account receiving the pass (0 = caller).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function purchaseLazyPass(uint32 id, bytes32 affiliateCode) external payable;

    /// @notice Purchase whale passes for account `id`.
    /// @dev Authorized (account rule). Passes, entries and lootboxes are the account's; the buyer
    ///      DGNRS reward and the free-tranche seat go to the payee. Funding and refunds as `purchase`.
    /// @param id Account receiving the passes (0 = caller).
    /// @param quantity Number of passes to purchase (1-100).
    /// @param affiliateCode Affiliate/referral code for the purchase (bytes32(0) = stored code).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function purchaseWhalePass(uint32 id, uint256 quantity, bytes32 affiliateCode) external payable;

    /// @notice Whether a player holds a deity pass.
    function hasDeityPass(address player) external view returns (bool);

    /// @notice Get raw bit-packed mint data for a player.
    /// @dev Address convenience view of ID-keyed mint history. Bits 224..255 are unused;
    ///      bit 147 is the smurf flag (set once by `createSmurf`).
    /// @param player Player address to query.
    /// @return Raw packed uint256 containing mint counts, streak, pass status.
    function mintPackedFor(address player) external view returns (uint256);

    /// @notice Mint word keyed directly by account ID; missing IDs return zero.
    /// @param id Account ID.
    /// @return Raw packed mint word for the account.
    function mintPackedOfId(uint32 id) external view returns (uint256);

    /// @notice Purchase tickets and loot boxes with ETH or claimable for account `id`.
    /// @dev Main entry point for all ETH/claimable purchases.
    ///      Recycling at least 3 tickets' worth of claimable winnings earns a 10% FLIP flip-credit bonus.
    ///      Authorized (account rule). Tickets, boxes, mint history, quests and pricing are the
    ///      account's. Fresh ETH comes from the caller; the claimable and AFKing legs spend the
    ///      account's own balances. Fresh ETH above the cost credits the payer's AFKing balance:
    ///      the account's ID when the caller is the account, else the caller's existing ID (a
    ///      smurf's owner gets its own refund). Box and pass payouts go to the account's payee.
    /// @param id Account receiving the purchases (0 = caller).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @param boxOrder Packed box order (0 to skip):
    ///        [small:8][med:8][large:8][customCount:8][customSize:56 in gwei]; at most 100 boxes,
    ///        every bit at or above 88 zero.
    /// @param affiliateCode Affiliate/referral code for all purchases.
    /// @param payKind Payment method (DirectEth, Claimable, or Combined).
    /// @param foil True to additively buy one foil pack (10x price) in the same tx; the
    ///        foil leg is one-per-cycle and adds to, never replaces, the ticket/lootbox legs.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function purchase(
        uint32 id,
        uint256 entryQuantityScaled,
        uint256 boxOrder,
        bytes32 affiliateCode,
        MintPaymentKind payKind,
        bool foil
    ) external payable;

    /// @notice Purchase tickets with FLIP for account `id`.
    /// @dev Entry point for FLIP ticket purchases. Authorized (account rule). The tickets are the
    ///      account's; the FLIP is burned from the account's payee (wallet balance, then the
    ///      payee's settled coinflip winnings for a shortfall).
    /// @param id Account receiving the tickets (0 = caller).
    /// @param entryQuantityScaled Scaled entry quantity (400 units = 1 whole ticket; 0 to skip).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    function redeemFlip(
        uint32 id,
        uint256 entryQuantityScaled
    ) external;



    /// @notice Claim color-completion bingo: all 8 colors of one symbol on a level.
    /// @dev One reward per player per level, claimable until the next level starts; dispatches
    ///      to the bingo module. Permissionless: any caller may settle any account's claim. The
    ///      FLIP leg credits the account by ID; the DGNRS leg goes to the account's payee.
    /// @param id Bingo owner to claim for (0 = caller; otherwise allocated).
    /// @param level The level to claim on (uint24 storage-key width).
    /// @param symbol Symbol 0-31 (quadrant = symbol >> 3, symInQ = symbol & 7).
    /// @param slots Per-color positions in lvlTraitEntry[level][traitId] the owner occupies.
    /// @custom:reverts E If `id` is unallocated (or 0 for a caller with no ID).
    function claimBingo(uint32 id, uint24 level, uint8 symbol, uint32[8] calldata slots) external;

    /// @notice Claim deterministic-ending shares for account `id`'s terminal-level tickets after a
    ///         game over caused by a dead VRF (open until the final sweep).
    /// @dev Permissionless; each share credits the account's claimable by ID, never the caller.
    /// @param id Owner of every referenced holding (0 = caller; otherwise allocated).
    /// @param refs Holdings to claim; the top byte of each is its kind: 0 a created ticket
    ///        (trait at bits 64..71, occurrence index at bits 0..63), 1 queued entries (stable owner ID
    ///        at bits 0..31, uint24 queue-domain key at bits 32..55), any other an undrained foil pack (resolve day at
    ///        bits 64..87, index into that day's bucket at bits 0..63).
    /// @custom:reverts E If `id` is unallocated (or 0 for a caller with no ID).
    function claimDeadVrf(uint32 id, uint256[] calldata refs) external;

    /// @notice Claim account `id`'s deferred whale-pass half passes as tickets.
    /// @dev Permissionless: it only awards the account its own deferred tickets and moves no value.
    /// @param id Account to claim for (0 = caller; otherwise allocated).
    /// @custom:reverts E If `id` is unallocated.
    function claimWhalePass(uint32 id) external;

    /// @notice Permissionlessly resolve account `id`'s foil match claim for (`day`, `ticketIndex`).
    /// @dev Credits the account by ID; a WWXRP box-spin prize mints to the account's payee. A tuple
    ///      pays at most once.
    /// @param id Pack owner (0 = caller; otherwise allocated).
    /// @param day Draw day of the claim.
    /// @param ticketIndex Ticket index 0..3 of the day's board.
    /// @custom:reverts E If `id` is unallocated.
    function claimFoilMatch(uint32 id, uint256 day, uint256 ticketIndex) external;

    /// @notice Permissionlessly resolve a batch of foil match claims (parallel arrays).
    /// @dev Each settled win credits its own account as `claimFoilMatch` does; `ids[i] == 0` is the
    ///      caller. Non-claimable tuples past index 0 are skipped; a non-claimable tuple at index 0
    ///      reverts the whole call (StaleBatch).
    /// @param ids Pack owners.
    /// @param drawDays Draw days.
    /// @param ticketIndexes Ticket indexes 0..3.
    function claimFoilMatchMany(uint32[] calldata ids, uint24[] calldata drawDays, uint8[] calldata ticketIndexes) external;

    /// @notice Claim a foil pack's gold for account `id`: a FLIP ladder from three golds up, or the
    ///         golden-ticket grand when two whole tickets came out all gold.
    /// @dev Permissionless; credits the account by ID, payouts to the account's payee. A pack pays
    ///      at most once.
    /// @param id Pack owner (0 = caller; otherwise allocated).
    /// @param lvl The pack's level.
    /// @custom:reverts E If `id` is unallocated.
    function claimGoldenTicket(uint32 id, uint24 lvl) external;

    /// @notice Claim account `id`'s accrued ETH winnings in full.
    /// @dev Authorized (account rule). Debits the account's claimable (and after game over its
    ///      whole AFKing balance) and pays the account's payee, ETH first with a stETH fallback,
    ///      then applies the cashout curse to the account. Leaves the 1-wei sentinel.
    /// @param id Account to claim for (0 = caller).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    /// @custom:reverts NothingToClaim If nothing is claimable.
    /// @custom:reverts AlreadySwept After the final sweep.
    function claimWinnings(uint32 id) external;

    /// @notice Claim up to `amount` of account `id`'s accrued ETH winnings (partial cashout).
    /// @dev As `claimWinnings(uint32)`, capped at `amount` of claimable.
    /// @param id Account to claim for (0 = caller).
    /// @param amount Maximum wei of claimable winnings to take.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    /// @custom:reverts NothingToClaim If nothing is claimable.
    /// @custom:reverts AlreadySwept After the final sweep.
    function claimWinnings(uint32 id, uint256 amount) external;

    /// @notice Fund account `id`'s prepaid AFKing ETH bucket with `msg.value`.
    /// @dev Permissionless (fund anyone). `id` is a third-party recipient: it must already exist
    ///      and 0 is not the caller. Credits the ledger by ID (claimablePool in tandem).
    /// @param id Beneficiary account (nonzero, allocated).
    /// @custom:reverts E If `id == 0` or `id` is unallocated.
    function depositAfkingFunding(uint32 id) external payable;

    /// @notice Withdraw `amount` of account `id`'s prepaid AFKing ETH.
    /// @dev Authorized (account rule). Debits the account's bucket and pays the account's payee
    ///      (the caller for `id == 0` or a smurf's owner; an operator's withdrawal for an ordinary
    ///      wallet pays that wallet), ETH first with a stETH fallback. `amount == 0` is a no-op.
    /// @param id Account whose bucket is debited (0 = caller).
    /// @param amount ETH amount (wei) to withdraw.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated.
    /// @custom:reverts Insolvent If `amount` exceeds the bucket.
    /// @custom:reverts AlreadySwept After the final sweep.
    function withdrawAfkingFunding(uint32 id, uint256 amount) external;

    // -------------------------------------------------------------------------
    // Degenerette Tracking Views
    // -------------------------------------------------------------------------

    /// @notice Get hero wager units in a retained day. Recycled days return zero; use logs for history.
    function getDailyHeroWager(uint24 day, uint8 quadrant, uint8 symbol) external view returns (uint256 wagerUnits);
    /// @notice Get the most-wagered hero in a retained day. Recycled days return zeros.
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
    ///         or cancel (dailyQuantity == 0) for account `id`.
    /// @dev Authorized (account rule), checked once here and never at process time.
    ///      Seats: a NEW run (no live run: never subscribed, cancelled or evicted) burns seat
    ///      `seatId`, which must be held by the subscriber's payee (the owner for a smurf): Game
    ///      calls `AFKING_SUB_TOKEN.consumeSeat(payee, seatId)` before it writes the run. Changing
    ///      a live run, a cancel, and the exempt VAULT/SDGNRS subscriptions burn nothing and
    ///      ignore `seatId`. There is no seat lock and no eviction forfeit.
    ///      Funding: `fundingSourceId == 0` (or the subscriber's own ID) self-funds from the
    ///      subscriber's own AFKing ledger; a stETH top-up pulls from the subscriber's payee.
    ///      Any other `fundingSourceId` is an ID that must exist and must consent: it shares the
    ///      subscriber's main wallet (equal payees: an owner and its smurfs) or approved the
    ///      subscriber's key as an operator. Prepaid draws keep that consent, and each stETH
    ///      pull from the source's payee re-checks it live.
    ///      `msg.value` credits the funding bucket the draws debit (the source's when external,
    ///      else the subscriber's).
    /// @param id Subscriber account (0 = caller).
    /// @param drainGameCreditFirst Spend game credit before fresh ETH.
    /// @param useTickets Deliver tickets (true) or lootbox deposits (false).
    /// @param dailyQuantity Daily delivery quantity; 0 cancels the subscription.
    /// @param fundingSourceId Account funding the subscription (0 = self-funded).
    /// @param seatId Seat serial to burn when this call starts a new run (ignored otherwise).
    /// @custom:reverts RngLocked During the RNG freeze window.
    /// @custom:reverts GameOver Once the liveness trigger fires.
    /// @custom:reverts NotApproved If the caller may not act for `id`, or the funding source does
    ///                 not authorize the subscriber.
    /// @custom:reverts E If `id` or `fundingSourceId` is unallocated.
    /// @custom:reverts NotSubscribed On a cancel with no subscription.
    /// @custom:reverts InvalidToken (seat token) If a new run's `seatId` is not held by the payee.
    function subscribe(
        uint32 id,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        uint32 fundingSourceId,
        uint256 seatId
    ) external payable;

    /// @notice Length of the AFKing subscriber set: live subscriptions, the two exempt protocol
    ///         subscriptions (VAULT, SDGNRS) and cancel/eviction tombstones awaiting the in-pass
    ///         reclaim.
    /// @dev The seat token's capped vault mint reads it: `liveSeats + n + subscriberSetLength()`
    ///      may not exceed 2,000. Every non-exempt entry burned a seat, so the set never exceeds
    ///      2,000 and needs no runtime cap.
    function subscriberSetLength() external view returns (uint256);

    /// @notice GAME-only atomic stETH pull; caller catches any failed funding attempt.
    /// @dev Game self-call (caller and callee both live in the Game image). `subWord` is the
    ///      sub's set element (key bits 0..159, wallet ID 160..191) and `source` the address the
    ///      stETH comes from: the funding account's payee. The live consent re-check runs by ID.
    function setAfkingFundingApproval(uint32 funderId, uint32 subscriberId, bool approved) external;
    function pullAfkingSteth(uint32 subWord, address source, uint256 shortfall) external returns (uint256);

    /// @notice Permissionless FLIP claim — pays each listed account its accrued pendingFlip in one
    ///         creditFlip and zeroes it; always credits the account, never the caller.
    /// @dev `ids[i] == 0` is the caller. An ID with nothing accrued, including an unallocated ID,
    ///      settles nothing and does not revert.
    /// @param ids Subscriber accounts to pay out.
    function claimAfkingFlip(uint32[] calldata ids) external;

    /// @notice Affiliate-only atomic read-and-zero of a sub's accrued affiliateBase.
    /// @param sub The subscriber whose affiliate base is drained.
    /// @return base The drained whole-FLIP affiliate base (0 if already drained).
    function drainAffiliateBase(uint32 sub) external returns (uint256 base);

    /// @notice QUESTS-only: bump an afking sub's streak base for a secondary/level completion.
    /// @dev Keyed by wallet ID (Quests holds only IDs). A no-op unless `id` has a live afking
    ///      sub; `id == 0` is a no-op. Never reverts for the authorized caller.
    /// @param id Wallet ID of the afking subscriber whose secondary completion is recorded.
    /// @param amount The streak-base increment (1 for a daily secondary, more for a level quest).
    function recordAfkingSecondary(uint32 id, uint16 amount) external;

    /// @notice QUESTS-only: floor an afking sub's streak base to `floor`, so a foil-pack
    ///         purchase's quest-streak guarantee reaches a mid-run afker (whose reward streak
    ///         is the sub base plus funded delivered days, not the manual quest streak).
    /// @dev Keyed by wallet ID. A no-op unless `id` has a live afking sub; `id == 0` is a no-op.
    /// @param id Wallet ID of the afking subscriber whose streak base is floored.
    /// @param floor The minimum streak base to set (no-op if the base is already at/above it).
    function floorAfkingStreakBase(uint32 id, uint16 floor) external;

    /// @notice Permissionless paid cure: clear account `id`'s cashout/smite curse for 100 FLIP.
    /// @dev The caller pays: 100 FLIP is burned from `msg.sender`'s own wallet (a gift), never
    ///      from the account. Clears the curse on the account's mint word.
    /// @param id The cursed account to cure (0 = caller; otherwise allocated).
    /// @custom:reverts E If `id` is unallocated.
    /// @custom:reverts NothingToClaim If the account has no curse.
    function decurse(uint32 id) external;

    /// @notice Deity-gated smite: add a saturating curse stack to account `smiteeId` for 200 FLIP.
    /// @dev The caller must own deity pass `deityId` (the NFT sits at the deity account's main
    ///      wallet, so the main wallet smites) and pays 200 FLIP from its own wallet. Self-smite
    ///      is allowed. Active afkers and the protocol accounts (VAULT, SDGNRS, GNRUS) are immune.
    /// @param deityId The smiting deity's pass ID (caller must hold it).
    /// @param smiteeId The account receiving the curse stack (0 = caller; otherwise allocated).
    /// @custom:reverts Unauthorized If the caller does not own the pass, or the smitee is a
    ///                 protocol account.
    /// @custom:reverts E If `smiteeId` is unallocated.
    function smite(uint256 deityId, uint32 smiteeId) external;

    /// @notice Claim DGNRS affiliate rewards for the current level for affiliate account `id`.
    /// @dev Permissionless: the reward is deterministic. The DGNRS leg goes to the account's
    ///      payee; the FLIP bonus credits the account by ID.
    /// @param id Affiliate account to claim for (0 = caller; otherwise allocated).
    /// @custom:reverts E If `id` is unallocated.
    function claimAffiliateDgnrs(uint32 id) external;

    /// @notice Permissionless batch affiliate-DGNRS claim; a blank array claims the caller's own.
    /// @dev Each element runs as `claimAffiliateDgnrs(uint32)` in isolation (an ineligible or
    ///      already-claimed account is skipped). `ids[i] == 0` is the caller: the Game resolves it
    ///      to the caller's ID before its isolating self-call, whose `msg.sender` is the Game.
    /// @param ids Affiliate accounts to settle; empty = the caller only.
    function claimAffiliateDgnrs(uint32[] calldata ids) external;



    /// @notice Credit the direct half of an sDGNRS redemption claim to the claimant's claimable winnings.
    /// @param id Claimant wallet ID credited.
    /// @param amount Total direct-half value (msg.value ETH + the stETH remainder pulled here).
    function creditRedemptionDirect(uint32 id, uint256 amount) external payable;
}
