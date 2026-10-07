// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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

/**
 * @title ICoinflip
 * @notice Interface for Coinflip contract - handles all FLIP coinflip wagering logic.
 * @dev Standalone daily coinflip wagering system extracted from FLIP to reduce contract size.
 *      Integrates with FLIP for burn/mint operations and DegenerusGame for game state.
 */

/// @dev All-time record kinds. Coinflip owns the records and the ONE shared pool;
///      the game modules arm the three game-side kinds via armRecord. The flip
///      record arms internally on direct deposits and is not reachable externally,
///      and the dice-run record has its own CRAPS-only door — its claim rule is not
///      the other four's, so it never reaches armRecord.
uint8 constant RECORD_KIND_FLIP = 0;
uint8 constant RECORD_KIND_SPIN = 1;
uint8 constant RECORD_KIND_LUCKBOX = 2;
uint8 constant RECORD_KIND_BUY = 3;
uint8 constant RECORD_KIND_DICE_RUN = 4;
uint8 constant RECORD_KINDS = 5;

interface ICoinflip {
    function claimAcquiredCoinflips(uint32 id) external returns (uint256);
    /// @notice Emitted whenever a player's coinflip claim-state changes (claimable + carry + claim
    ///         cursor), so off-chain consumers can reconstruct valuation from logs without an eth_call.
    /// @param player The player whose claim-state changed.
    /// @param claimableStored Post-update claimable FLIP balance.
    /// @param autoRebuyCarry Post-update rolling auto-rebuy carry.
    /// @param lastClaim Post-update claim cursor day.
    event CoinflipClaimState(
        uint32 indexed player,
        uint128 claimableStored,
        uint128 autoRebuyCarry,
        uint24  lastClaim
    );

    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Deposit FLIP into the daily coinflip system for account `id`.
    /// @dev Processes any pending claims, funds the stake, applies quest and recycling bonuses,
    ///      then adds stake for the next day's flip.
    ///      Gift door. `id == 0` is the caller: a self deposit, with no Game resolution call. For
    ///      a nonzero `id` Coinflip calls Game `resolveAccount(id, msg.sender)` (reverts `E` for
    ///      an unallocated ID). An authorized caller (the account's key, a smurf's owner, or an
    ///      approved operator) acts as the account: the deposit is funded from the account's
    ///      settled coinflip winnings first and the remainder burns from the account's PAYEE's
    ///      wallet FLIP via FLIP.burnForCoinflip; the quest credit goes to the account. Any other
    ///      caller makes a gift: it funds the whole stake by burning its own FLIP, earns the
    ///      quest itself (registered as a paying funder), and the account's winnings stay
    ///      untouched. The recycling bonus pays on the winnings leg only.
    ///      Stakes and principal use whole FLIP. Each percentage bonus floors at its
    ///      calculation boundary before it is added to the day's stake. CoinflipStakeUpdated reports the accepted stake.
    ///      Both stake ledger and claim state are keyed by account ID. Self deposits register
    ///      the caller subject to Game admission policy. Loss-streak WWXRP rewards credit
    ///      that account's claimable balance; token withdrawals resolve its owner separately.
    /// @param id The account receiving the stake (0 = caller).
    /// @param amount Amount of FLIP to deposit (must be >= 100 FLIP minimum).
    /// @custom:reverts E (Game) If `id` is unallocated, or a new self depositor must register
    ///                 past paid admission (PAID_ADMISSION_WALLETS registered wallets; the hook
    ///                 carries no spend).
    /// @custom:reverts AmountLTMin If amount is non-zero but less than 100 FLIP.
    /// @custom:reverts StakeAboveDailyCap If the stake with its bonuses would exceed the player's
    ///                 per-day cap of type(uint32).max whole FLIP; every prior mutation rolls back.
    function depositCoinflip(uint32 id, uint256 amount) external;

    /// @notice Claim an exact amount of account `id`'s coinflip winnings as FLIP tokens.
    /// @dev Processes pending daily claims, then mints up to the requested amount.
    ///      Authorized: `id == 0` is the caller; a nonzero `id` needs Game
    ///      `resolveAccount(id, msg.sender).authorized` (the key, a smurf's owner or an approved
    ///      operator). The FLIP and any loss-streak WWXRP mint to the account's PAYEE (the
    ///      caller for `id == 0`, a smurf's owner, or an ordinary account's own key).
    ///      A self caller with no wallet ID has no stake and claims 0.
    /// @param id The account claiming (0 = caller).
    /// @param amount Amount to claim (will be capped at available balance).
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    function claimCoinflips(uint32 id, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim up to `amount` of account `id`'s auto-rebuy carry as minted FLIP while
    ///         staying on auto-rebuy.
    /// @dev Runs the bounded claim walk first (wins roll into the carry, a loss zeroes it),
    ///      then withdraws from the settled carry; the remainder keeps rolling. Blocked while
    ///      today's flip is unapplied (`flipResolvedToday()` false), whether or not the game's
    ///      RNG lock is up. Take-profit chunks surfaced by the settle bank into the claimable side.
    ///      Authorized as `claimCoinflips`; the FLIP mints to the account's payee.
    /// @param id The account claiming (0 = caller).
    /// @param amount Maximum carry to claim.
    /// @return claimed The actual amount minted from the carry.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    /// @custom:reverts RngLocked If today's flip has not been applied yet.
    /// @custom:reverts AutoRebuyNotEnabled If the account is not on auto-rebuy.
    function claimCoinflipCarry(uint32 id, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim coinflip winnings via FLIP contract to cover token transfers/burns.
    /// @dev Access restricted to FLIP contract only. Processes pending claims and mints tokens.
    ///      Keeps its address parameter: a holder with no wallet ID has no stake and claims 0,
    ///      exactly as an empty ledger does (plain FLIP holders never newly revert here).
    /// @param player The player claiming.
    /// @param amount Amount to claim.
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function claimCoinflipsFromFlip(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Consume coinflip winnings via FLIP for burns without minting new tokens.
    /// @dev Access restricted to FLIP contract only. Reduces claimable balance without minting.
    ///      Keeps its address parameter: a holder with no wallet ID consumes 0, exactly as an
    ///      empty ledger does (FLIP burns by plain holders never newly revert here).
    /// @param player The player whose balance to consume.
    /// @param amount Amount to consume.
    /// @return consumed The actual amount consumed.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);

    /// @notice Configure auto-rebuy mode for account `id`'s coinflips.
    /// @dev Auto-rebuy automatically rolls over winnings as stake for future flips.
    ///      When enabled, winnings accumulate as carry until claimed. When disabled,
    ///      processes a larger window of pending claims and mints all accumulated tokens to the
    ///      account's payee. Authorized as `claimCoinflips`.
    /// @param id The account configuring auto-rebuy (0 = caller).
    /// @param enabled Whether auto-rebuy should be enabled.
    /// @param takeProfit Threshold up to uint128 max; whole multiples are banked. Zero rolls all; ignored when disabling.
    /// @custom:reverts RngLocked If the player is already on auto-rebuy and today's flip has not
    ///                 been applied yet; enabling from off is never blocked.
    /// @custom:reverts AutoRebuyAlreadyEnabled If enabling when already enabled.
    /// @custom:reverts TakeProfitTooLarge If enabling with a threshold above uint128 max.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    function setCoinflipAutoRebuy(
        uint32 id,
        bool enabled,
        uint256 takeProfit
    ) external;

    /// @notice Update the take profit threshold for account `id`'s auto-rebuy mode.
    /// @dev Only callable when auto-rebuy is already enabled. Processes pending claims before
    ///      updating; any settled winnings it mints go to the account's payee. Authorized as
    ///      `claimCoinflips`.
    /// @param id The account configuring (0 = caller).
    /// @param takeProfit New threshold up to uint128 max for banking whole multiples (zero rolls all).
    /// @custom:reverts RngLocked If today's flip has not been applied yet.
    /// @custom:reverts AutoRebuyNotEnabled If the account does not have auto-rebuy enabled.
    /// @custom:reverts TakeProfitTooLarge If the threshold exceeds uint128 max.
    /// @custom:reverts NotApproved If the caller may not act for `id`.
    /// @custom:reverts E (Game) If `id` is unallocated.
    function setCoinflipAutoRebuyTakeProfit(
        uint32 id,
        uint256 takeProfit
    ) external;

    /*+======================================================================+
      |                       RNG PROCESSING                                 |
      +======================================================================+*/

    /// @notice Process coinflip payout for a completed epoch (called by game contract after VRF fulfillment).
    /// @dev Determines win/loss and reward percent from RNG, drips the record pool, advances claimable day.
    ///      Reward percent ranges: 5% chance of 50% (unlucky), 5% chance of 150% (lucky),
    ///      90% chance of 78-115% (normal). The caller adds a precomputed bonus on top.
    /// @param bonus Reward-percent bonus precomputed by the caller from frozen state: 0 = normal day,
    ///        2 = bonus day (a level-0 day, the second day of a level's jackpot phase, or the first
    ///        purchase day after a turbo collapse), 6 = the same on an x0 BAF level (10, 20, 30, …).
    /// @param rngWord The VRF random word for determining outcome.
    /// @param epoch The epoch (day) index being resolved.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function processCoinflipPayouts(
        uint8 bonus,
        uint256 rngWord,
        uint24 epoch
    ) external;

    /// @notice Backfill compact coinflip results over [start, end), at most 31 days.
    /// @dev At most 31 days; wins take raw root bits 1..31 relative to the original start.
    ///      Already-settled prefixes retain that anchor; wins pay double the stake, losses zero.
    function processCoinflipGap(uint256 root, uint24 start, uint24 end) external;

    /*+======================================================================+
      |                       CREDIT SYSTEM                                  |
      +======================================================================+*/

    /// @notice Credit flip stake to wallet `id` without burning tokens.
    /// @dev Called by authorized creditors (GAME, QUESTS, AFFILIATE, ADMIN, SDGNRS, WWXRP,
    ///      PARIMUTUEL, CRAPS) for rewards. Keyed by wallet ID only: writes the ID-keyed stake
    ///      lane and never reads or fills the ID-keyed PlayerCoinflipState, so a creditor
    ///      needs nothing but the ID. `id == 0` or `amount == 0` is a silent no-op, never a
    ///      revert: credits reached from a mineFlip stage cannot fail on a missing wallet.
    ///      Never touches the biggest-flip record (credits carry recordAmount 0).
    ///      Each credit floors to whole FLIP on its own (two sub-FLIP credits add nothing) and
    ///      saturates at the wallet's per-day cap of type(uint32).max whole FLIP rather than
    ///      reverting; CoinflipStakeUpdated reports the amount the lane accepted.
    /// @param id Wallet ID receiving the credit (0 = no wallet: no-op).
    /// @param amount Amount of flip credit to add to next day's stake, whole FLIP.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlip(uint32 id, uint256 amount) external;

    /// @notice Credit flips to multiple wallets in a single call.
    /// @dev Batch version of creditFlip for gas efficiency. Legs with a zero ID or a zero
    ///      amount are skipped. Each leg floors and saturates on its own, as creditFlip does.
    ///      Callers pass equal-length arrays (a shorter `amounts` reverts on the index).
    /// @param ids Wallet IDs to credit (0 entries are skipped).
    /// @param amounts Credit amounts corresponding to each ID, whole FLIP (0 entries are skipped).
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipBatch(
        uint32[] calldata ids,
        uint256[] calldata amounts
    ) external;

    /// @notice Credit flips to exactly two wallets in a single call.
    /// @dev Fixed-arity variant of creditFlipBatch — spares the caller the two array
    ///      allocations and the dynamic ABI encode. Legs with a zero ID or a zero amount
    ///      are skipped; each leg floors and saturates on its own.
    /// @param id1 First recipient wallet ID (0 = skipped).
    /// @param amount1 First credit amount, whole FLIP.
    /// @param id2 Second recipient wallet ID (0 = skipped).
    /// @param amount2 Second credit amount, whole FLIP.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipPair(
        uint32 id1,
        uint256 amount1,
        uint32 id2,
        uint256 amount2
    ) external;

    /// @notice Arm a game-side all-time record for wallet `id` with `candidate` in the
    ///         record's own unit (spin and lootbox deposit: ETH wei; buy: whole tickets).
    /// @dev GAME only (delegatecall modules). Larger-than-mark candidates ratchet the
    ///      record; clearing the mark by a fifth also claims the category's accrued
    ///      share of the record pool, plus the sDGNRS leg at 1/500 scale. Callers gate
    ///      each record's entry floor before paying for the call. The flip record arms
    ///      internally on direct deposits, never here.
    ///      Every ratchet calls Game `payRecordSdgnrs(id, shareBps)` (shareBps 0 when the
    ///      candidate does not clear the claim bar) and hands the record trophy to the
    ///      `payee` it returns, so the trophy always has a recipient without an address
    ///      parameter. Game callers pass the nonzero ID they already hold.
    /// @param kind Which record (RECORD_KIND_*), excluding flip and dice run.
    /// @param id Wallet ID whose candidate is being armed.
    /// @param candidate The candidate mark to ratchet the record with.
    /// @return The FLIP claimed from the record pool (0 when the candidate only ratcheted
    ///         the mark). Coinflip does NOT credit it — the caller folds it into the FLIP
    ///         its own path already pays, so a claim costs no second stake write.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function armRecord(
        uint8 kind,
        uint32 id,
        uint256 candidate
    ) external returns (uint256);

    /// @notice Add FLIP to the shared all-time record pool.
    /// @dev GAME only. Level transitions push 0.2% of the completed level's prize pool,
    ///      converted notionally at that level's ticket price — no ETH moves.
    function fundRecordPool(uint256 amount) external;

    /// @notice Arm the x00 seed window if one is due (GAME only, silent when not due).
    /// @dev Stores the window's first day and writes no stake lane: VAULT and sDGNRS each hold the
    ///      seed on every window day on top of that day's stored stake. SeedWindowArmed is the only
    ///      event; no per-day CoinflipStakeUpdated is emitted for the seed.
    /// @param lvl The level whose jackpot phase just ended.
    function armCenturySeed(uint24 lvl) external;

    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (claimableStored + carry).
    /// @dev sDGNRS-only. Settles all resolved days first so the two summed components are disjoint
    ///      and current; sDGNRS holds no wallet balance — its entire FLIP backing lives in these two.
    /// @return backing claimableStored + autoRebuyCarry for sDGNRS.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function redeemableFlipBacking() external returns (uint256 backing);

    /// @notice Remove up to `base` whole FLIP of sDGNRS's FLIP backing as a redemption batch closes.
    /// @dev sDGNRS-only. Waterfall: settled claimable (consumed) → auto-rebuy carry (decremented) —
    ///      sDGNRS holds no wallet balance, so backing lives entirely in these two. Credits nothing;
    ///      the batch escrow is paid later on its synthetic flip win via creditFlip. Clamps to the
    ///      backing instead of reverting, so a batch close cannot fail here.
    /// @param base Whole-FLIP backing to remove from sDGNRS.
    /// @return removed Whole FLIP actually removed.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function withdrawRedeemedFlip(uint256 base) external returns (uint256 removed);

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    function previewClaimCoinflipsById(uint32 id) external view returns (uint256);
    function previewFlipBackingById(uint32 id) external view returns (uint256);
    function coinflipAmountById(uint32 id) external view returns (uint256);
    function coinflipAutoRebuyInfoById(uint32 id) external view returns (bool, uint256, uint256, uint24);

    /// @notice Preview total claimable FLIP for a player including pending daily claims.
    /// @dev Calculates claimable from stored balance plus unprocessed winning days within claim window.
    /// @param player The player to check.
    /// @return mintable Total amount that would be claimable if claimed now.
    function previewClaimCoinflips(
        address player
    ) external view returns (uint256 mintable);

    /// @notice Get player's current coinflip stake for the next day's flip.
    /// @dev Returns the stake amount deposited for the upcoming flip day. Stakes are whole FLIP
    ///      (stored as uint32 units), returned without scaling. For VAULT and sDGNRS it includes
    ///      the seed when that day lies in the active seed window.
    /// @param player The player to check.
    /// @return The stake amount in whole FLIP for the next flip.
    function coinflipAmount(address player) external view returns (uint256);

    /// @notice Get player's auto-rebuy configuration.
    /// @param player The player to check.
    /// @return enabled Whether auto-rebuy mode is currently active.
    /// @return stop The threshold amount for auto-claiming multiples.
    /// @return carry The current accumulated carry amount (winnings below threshold).
    /// @return startDay The day auto-rebuy was enabled (used for claim window calculation).
    function coinflipAutoRebuyInfo(
        address player
    )
        external
        view
        returns (
            bool enabled,
            uint256 stop,
            uint256 carry,
            uint24 startDay
        );

    /// @notice Arm flip day `day` for the BAF weighted draw (GAME only).
    /// @dev The advance path arms the flip day an x0 level's last-purchase-day
    ///      deposits stake (day + 1); direct self-funded deposits staking that day
    ///      record amount-weighted draw intervals.
    function armBafDraw(uint24 day) external;

    /// @notice The armed BAF draw day and its book totals: the whole-FLIP sum of every direct
    ///         self-funded deposit that staked the armed day, and the entry count.
    function bafDrawInfo() external view returns (uint24 day, uint96 totalWeight, uint32 entryCount);

    /// @notice Get the result of a coinflip day.
    /// @param day The day to query.
    /// @return rewardPercent The reward percentage for that day.
    /// @return win Whether the flip was a win.
    function getCoinflipDayResult(uint24 day) external view returns (uint16 rewardPercent, bool win);

    /// @notice True once today's flip has been applied — its VRF word recorded and paid out.
    /// @dev Settlement marker for the carry freeze: past it the carry has resolved through
    ///      today's word and rides tomorrow, whose word is not yet requested. Reopens the FLIP
    ///      claim paths ahead of the game's RNG lock, which advanceGame holds through the
    ///      chunked drains that follow settlement.
    function flipResolvedToday() external view returns (bool);
}
