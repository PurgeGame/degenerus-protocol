// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

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
    /// @notice Execute ordered game work. Zero selects the 10,000-bps default estimate factor.
    function mineFlip(uint32 gasMultiplierBps) external;

    /// @notice Borrow up to `amount` against far-future tickets, due when the game enters `dueLevel`.
    function borrow(uint32 id, uint24 dueLevel, uint256 amount, uint256 minEthOut) external;
    /// @notice Repay an open loan before its due level; excess ETH funds the account's AFKing.
    function repay(uint32 id) external payable;
    /// @notice Sweep up to 32 owned subaccounts into their current main accounts.
    /// @dev Permissionless only for sDGNRS-owned accounts; otherwise each source requires its
    ///      payee or approved operator. Moves claimable ETH internally (retaining 1 wei), and
    ///      settled FLIP to the payee. Acquired accounts also surrender prepaid AFKing and,
    ///      once caught up and unfrozen, coinflip carry. Ordinary smurfs keep live AFKing
    ///      funding and auto-rebuy; moving their ETH applies their normal cashout curse.
    ///      Repeat for later awards or a coinflip backlog. Does not resolve unclaimed prizes.
    function sweepAccounts(uint32[] calldata ids) external returns (uint256 ethCollected, uint256 flipCollected);

    /// @notice Wallet-ID hook for trusted protocol contracts: existing ID, or with `allocate` a new
    ///         one subject to paid admission. Non-allocating calls return zero for unregistered wallets.
    function registerWallet_g9539(address owner, bool allocate) external returns (uint32 id);
    function registerWalletIdentity(address owner) external returns (uint32 id);
    function walletIdentityOf_g8516(address owner) external view returns (uint32);
    function acquiredBuyer(uint32 id) external view returns (uint32 buyerId);

    /// @notice A wallet's current gameplay ID, or zero before registration/after liquidation.
    function walletIdOf_g3120(address player) external view returns (uint32);

    /// @notice Resolve an allocated account's payee and caller authorization.
    /// @dev Ordinary accounts return their address as `key`; subaccounts return zero.
    ///      Subaccounts store an owner ID, resolved to an ordinary wallet for payouts.
    ///      Authorization is the current payee, or an operator approval on an unsold account.
    ///      Authorization failure returns false; zero or unallocated IDs revert E.
    function resolveAccount_g7029(uint32 id, address caller)
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

    /// @notice Create a smurf account owned and referred by the caller and buy it
    ///         one ticket, all in one call.
    /// @dev Owner = `msg.sender`, which must already hold an ordinary wallet ID. Steps, atomically:
    ///      Lifetime creations must be below the main ID's admin base + floor(current main score / 120).
    ///      Only ordinary mains create children. The packed count/base remain on that ID after liquidation; new IDs start at zero.
    ///      1. Resolve the owner's referral exactly as a purchase does: an unset referral is set
    ///         from `affiliateCode`, or locked to no referrer for a blank or invalid code; a set
    ///         referral ignores the code.
    ///      2. Allocate the next ID, storing only `ownerId << 160` in its wallet-table element.
    ///         Set the account's mint-word smurf flag and emit `SmurfCreated(ownerId, smurfId)`.
    ///      3. Permanently refer the smurf through the current main ID with zero kickback.
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
    /// @custom:reverts E If the caller has no ordinary main or paid admission refuses allocation.
    /// @custom:reverts SmurfCreationLimitReached If all base-plus-score creation slots are consumed.
    /// @custom:reverts (purchase) Every applicable revert of a one-ticket `purchase` by the owner (
    ///                 liveness/game over, insufficient payment).
    function createSmurf(bytes32 affiliateCode, MintPaymentKind payKind)
        external payable returns (uint32 smurfId);
    /// @notice Vault-owner-only permanent increase to a registered main ID's base (0..65535).
    /// @dev Strictly increasing absolute value; preserves lifetime count and all other mint fields.
    function raiseSmurfBaseAllowance(uint32 mainId, uint16 newBase) external;

    /// @notice Read a raw storage slot; used for permanent identity lookups with pinned roots.
    function extsload_g2807007(bytes32 slot) external view returns (bytes32 value);

    /// @notice Allowed read consumer: 0 blocked, 1 redemption, 2 AFK, 3 boxes/bets, 4 Decimator, 5 Craps, 6 complete.
    function rngConsumerStage_g379() external view returns (uint8);

    /// @notice Get the current jackpot level.
    /// @return Current jackpot level (starts at 0).
    function level() external view returns (uint24);

    /// @notice Get the current game phase using jackpot semantics.
    /// @return True if jackpot phase is active, false if purchase phase.
    function jackpotPhase() external view returns (bool);

    /// @notice Check if the game has ended (terminal state).
    function gameOver() external view returns (bool);

    /// @notice Whether the liveness-timeout game-over trigger is currently active.
    /// @dev Purchase phase: true after 30 completed purchase rounds (level-0 baseline is day 9; 30
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
    function purchaseInfo_g1027()
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
    function playerActivityScoreCachedById_g975(uint32 id) external returns (uint256);

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
    function consumeCoinflipBoon_g2902(uint32 id) external returns (uint16 boostBps);

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
    function recordDecBurn_g1271(
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
    function currentDayView_g542950() external view returns (uint24);
    function currentWallDayView() external view returns (uint24);
    function dailySessionState() external view returns (bool complete, uint24 requestWallDay, uint48 completedAt);
    function latestDailyResultDay() external view returns (uint24);
    function dailyScheduleOpen_g214() external view returns (bool);

    /// @notice Admin-only transport retry of an unanswered request after its 20-hour timeout.
    function retryRng() external;

    /// @notice Mint mid-day RNG credit to a native ETH donor.
    /// @dev Access: ADMIN only. A donor's mineFlip spends credit on the mid-day request when
    ///      pending work sits below the threshold; the subscription native ETH floor still applies.
    ///      A donation is a paying action: the donor is registered (existing ID or a new one)
    ///      and the ID is returned to Admin.
    /// @param to Donor to credit.
    /// @param amount Request credit in wei.
    /// @return id The donor's wallet ID (never 0).
    /// @custom:reverts OnlyAdmin If caller is not ADMIN.
    /// @custom:reverts E If the donor is new past paid admission (PAID_ADMISSION_WALLETS
    ///                 registered wallets; a donation quotes no Game spend).
    function creditMiddayRng(address to, uint256 amount) external returns (uint32 id);

    /// @notice Buy a credit-gated Degenesis box (ETH + claimable shortfall) for account `id`.
    /// @dev Authorized (account rule). The order, its credit gate and the claimable/AFKing legs are
    ///      the account's; fresh ETH comes from the caller. Overpay credits the payer's AFKing
    ///      balance: the account's own ID when the caller is the account, else the caller's
    ///      existing ID. Rewards go to the account's payee. Degenesis days 1-7 only; the Vault
    ///      account cannot buy. Primary token payees remain account-derived; additional boon,
    ///      quest and activity state belongs to the stored wallet ID. Boons use 20% of raw ETH
    ///      capped at 1 ETH, level-1 normalization and up to three guaranteed-plus-fractional
    ///      draws. Normal settlement-day expiry and upgrade/discard rules apply; repeated types
    ///      are allowed and splitting orders can avoid the per-order ceiling. The purchase
    ///      itself earns no quest/streak/activity credit; drawn activity/shields can grant it.
    ///      Neither the purchase nor the boon grant earns Degenesis credit.
    /// @param id Account receiving the order (0 = caller).
    /// @param amount Degenesis ETH: at least 0.01 ETH, a whole multiple of 0.0001 ETH, below
    ///        2^38 units of 0.0001 ETH (about 27.5M ETH).
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated, outside the sale, over credit, or out of bounds.
    function buyDegenesisBox(uint32 id, uint256 amount) external payable;

    /// @notice Vault-only: spend the Vault's Degenesis budget on an ordinary purchase for an
    ///         allocated recipient at its normal price. The unspent part of `maxCost` returns to the budget.
    /// @param recipientId Allocated recipient account; 0 selects the Vault.
    /// @param whalePass True for whale passes, false for tickets and lootboxes.
    /// @param quantity Whale passes, or ticket purchase units (400 = one whole ticket).
    /// @param boxOrder Packed lootbox order (ignored with whale passes).
    /// @param maxCost Budget made available to the purchase.
    /// @custom:reverts E If the caller is not the Vault, the budget is short, or the purchase
    ///         costs more than `maxCost`.
    function spendDegenesis(uint32 recipientId, bool whalePass, uint256 quantity, uint256 boxOrder, uint256 maxCost) external;

    /// @notice Spendable Degenesis credit accrued by a player.
    /// @param player Player to query.
    /// @return credit Remaining credit (consumed 1:1 by Degenesis purchases).
    function degenesisCreditOf(address player) external view returns (uint256 credit);

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

    /// @notice Sample up to 4 entries from a prepared BAF trait buffer.
    /// @dev Returns the wallet IDs the trait bucket already stores (no wallet-table decode).
    ///      BAF prepares its even/current and odd/next buffers when armed. This reads the
    ///      chosen physical buffer directly, without looking up the current game level.
    /// @param nextLevel False selects the even/current BAF buffer; true selects the odd/next buffer.
    /// @param entropy Random entropy for sampling (typically from VRF).
    /// @param trait The explicit trait bucket (one of the main board's non-solo traits for BAF).
    /// @return entries Wallet IDs holding the sampled entries (IDs may repeat).
    function sampleTraitEntries(bool nextLevel, uint8 trait, uint256 entropy)
        external view returns (uint32[] memory entries);

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
    /// @dev Address convenience view of ID-keyed mint history. Bits 224..239 count lifetime smurfs; 240..255 hold the admin base;
    ///      bit 147 is the smurf flag (set once by `createSmurf`).
    /// @param player Player address to query.
    /// @return Raw packed uint256 containing mint counts, streak, pass status.
    function mintPackedFor(address player) external view returns (uint256);

    /// @notice Mint word keyed directly by account ID; missing IDs return zero.
    /// @param id Account ID.
    /// @return Raw packed mint word for the account.
    function mintPackedOfId_g5372(uint32 id) external view returns (uint256);

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
    /// @param boxOrder Packed box order (0 to skip): [quantity:7][kind:2][customUnits:21];
    ///        kind 0/1/2 small/medium/large preset, 3 custom of customUnits x 0.001 ETH per box
    ///        (10..2,000,000 units); quantity 1-100; every bit at or above 30 zero.
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
    /// @param slots Per-color positions in lvlTraitEntry[(level) & 1][traitId] the owner occupies.
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
    /// @custom:reverts RngLocked While the daily RNG lock is held.
    function claimFoilMatch(uint32 id, uint256 day, uint256 ticketIndex) external;

    /// @notice Permissionlessly resolve a batch of foil match claims (parallel arrays).
    /// @dev Each settled win credits its own account as `claimFoilMatch` does; `ids[i] == 0` is the
    ///      caller. Non-claimable tuples past index 0 are skipped; a non-claimable tuple at index 0
    ///      reverts the whole call (StaleBatch).
    /// @param ids Pack owners.
    /// @param drawDays Draw days.
    /// @param ticketIndexes Ticket indexes 0..3.
    /// @custom:reverts RngLocked While the daily RNG lock is held, before any tuple.
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

    /// @notice Get hero weights for the sealed request day - 1, or the accumulating pool for today.
    function getDailyHeroWager(uint24 day, uint8 quadrant, uint8 symbol) external view returns (uint256 wagerUnits);
    /// @notice Get the leading hero in the sealed or accumulating pool; other days return zeros.
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
    function initVrf(address coordinator_, uint256 subId, bytes32 keyHash_) external;

    /// @notice Update VRF coordinator, subscription, key hash and callback gas limit.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for VRF requests.
    /// @param newCallbackGasLimit Callback gas limit for VRF requests.
    function updateVrfCoordinatorAndSub(address newCoordinator, uint256 newSubId, bytes32 newKeyHash,
        uint32 newCallbackGasLimit) external;

    /// @notice VRF callback to receive random words.
    /// @dev Coordinator-gated in the module body (delegatecall preserves msg.sender).
    /// @param requestId The ID of the VRF request being fulfilled.
    /// @param randomWords Array of random words returned by VRF.
    function rawFulfillRandomWords(uint256 requestId, uint256[] calldata randomWords) external;

    /// @notice The SINGLE AfKing subscription entrypoint: create / change (dailyQuantity 1..8)
    ///         or cancel (dailyQuantity == 0) for account `id`.
    /// @dev Authorized (account rule), checked once here and never at process time.
    ///      Seats: a NEW run (no live run: never subscribed, cancelled or expired) burns seat
    ///      `seatId`, which must be held by the subscriber's payee (the owner for a smurf): Game
    ///      calls `AFKING_SUB_TOKEN.consumeSeat(payee, seatId)` before it writes the run. A new
    ///      run starts only after today's subscriber pass completed; its first purchase and first
    ///      credited day are tomorrow. Changing a live run, a cancel, and the exempt VAULT/SDGNRS
    ///      subscriptions burn nothing and ignore `seatId`.
    ///      Funding: each day's purchase spends the subscriber's claimable first (keeping 1 wei),
    ///      then its prepaid AFKing ETH, then a stETH top-up pulled from its payee. `msg.value`
    ///      credits the subscriber's prepaid AFKing ETH.
    ///      Every change settles the run first; a cancel settles both sides and removes the run.
    ///      The Vault's quantity 0 pauses it instead: it keeps its seat and earns nothing until a
    ///      quantity is set again.
    /// @param id Subscriber account (0 = caller).
    /// @param useTickets Deliver tickets (true) or lootboxes (false).
    /// @param dailyQuantity Daily delivery quantity, 1..8; 0 cancels the subscription.
    /// @param seatId Seat serial to burn when this call starts a new run (ignored otherwise).
    /// @custom:reverts RngLocked During the RNG freeze window, or for a new run before today's
    ///                 subscriber pass completed.
    /// @custom:reverts GameOver Once the liveness trigger fires.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E If `id` is unallocated, `dailyQuantity` exceeds 8, or a protocol seat
    ///                 asks for tickets.
    /// @custom:reverts NotSubscribed On a cancel with no subscription.
    /// @custom:reverts InvalidToken (seat token) If a new run's `seatId` is not held by the payee.
    function subscribe(
        uint32 id,
        bool useTickets,
        uint8 dailyQuantity,
        uint256 seatId
    ) external payable;

    /// @notice Length of the AFKing subscriber set: live subscriptions, the two exempt protocol
    ///         subscriptions (VAULT, SDGNRS) and seized runs awaiting the in-pass removal.
    /// @dev The seat token's capped vault mint reads it: `liveSeats + n + subscriberSetLength()`
    ///      may not exceed 2,000. Every non-exempt entry burned a seat, so the set never exceeds
    ///      2,000 and needs no runtime cap.
    function subscriberSetLength() external view returns (uint256);

    /// @notice GAME-only atomic stETH pull; caller catches any failed funding attempt.
    /// @dev Game self-call (caller and callee both live in the Game image). `subId` is the
    ///      subscriber's wallet ID and `source` the address the stETH comes from: its payee.
    function pullAfkingSteth(uint32 subId, address source, uint256 shortfall) external returns (uint256);

    /// @notice Permissionless AFKing claim — settles each listed account on both sides (its own
    ///         reward and its affiliate base to the upline) for every day since its last
    ///         settlement; always credits the accounts and uplines, never the caller.
    /// @dev `ids[i] == 0` is the caller. A non-member settles nothing and does not revert.
    ///      Reverts GameOver from the liveness trigger onward.
    /// @param ids Subscriber accounts to settle.
    function claimAfkingFlip(uint32[] calldata ids) external;

    /// @notice Affiliate-only settlement of up to eight subs sharing one direct affiliate: pays
    ///         each sub its own reward and returns their summed affiliate base (whole FLIP). Each
    ///         settlement moves its checkpoint first, so a duplicate sub settles nothing the second time.
    /// @param ids Up to eight subscriber IDs, 32 bits each from the low end (zero lanes skipped).
    /// @param uplines The run's two upline IDs packed low/high 32 bits (zero for no referrer).
    /// @return sumB The settled affiliate base.
    /// @return skipU1 The part of `sumB` from subs that are themselves the first upline.
    /// @return skipU2 The part of `sumB` from subs that are themselves the second upline.
    function drainAffiliateBases(uint256 ids, uint256 uplines)
        external returns (uint256 sumB, uint256 skipU1, uint256 skipU2);

    /// @notice QUESTS-only: bump a live afking run's streak for a secondary/level completion.
    /// @dev Keyed by wallet ID (Quests holds only IDs). A no-op unless `id` has a live afking
    ///      sub; `id == 0` is a no-op. Never reverts for the authorized caller.
    /// @param id Wallet ID of the afking subscriber whose secondary completion is recorded.
    /// @param amount The streak increment (1 for a daily secondary, more for a level quest).
    function recordAfkingSecondary_g3316(uint32 id, uint16 amount) external;

    /// @notice QUESTS-only: raise a live afking run's streak to at least `floor`, the same
    ///         foil-pack quest-streak guarantee a manual player's streak receives.
    /// @dev Keyed by wallet ID. A no-op unless `id` has a live afking sub; `id == 0` is a no-op.
    /// @param id Wallet ID of the afking subscriber whose streak is floored.
    /// @param floor The minimum live streak (no-op if the streak is already at/above it).
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
    /// @param amount Total direct-half value, drawn from the redemption reserve.
    function creditRedemptionDirect(uint32 id, uint256 amount) external;

    /// @notice Claim the caller's winnings, preferring stETH over native ETH.
    function claimWinningsStethFirst() external;

    /// @notice Spend FLIP to influence the next daily result, at the expected cost.
    function reverseFlip(uint256 expectedCost) external;

    /// @notice Raw claimable balance, including its 1-wei sentinel.
    function claimableWinningsOf(address player) external view returns (uint256);

    /// @notice Prepaid AFKing ETH belonging to a wallet.
    function afkingFundingOf(address player) external view returns (uint256);
}
