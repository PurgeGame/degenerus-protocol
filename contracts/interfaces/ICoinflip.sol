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

/**
 * @title ICoinflip
 * @notice Interface for Coinflip contract - handles all FLIP coinflip wagering logic.
 * @dev Standalone daily coinflip wagering system extracted from FLIP to reduce contract size.
 *      Integrates with FLIP for burn/mint operations and DegenerusGame for game state.
 */

/// @dev All-time record kinds. Coinflip owns the four records and the shared pool;
///      the game modules arm the three game-side kinds via armRecord. The flip
///      record arms internally on direct deposits and is not reachable externally.
uint8 constant RECORD_KIND_FLIP = 0;
uint8 constant RECORD_KIND_SPIN = 1;
uint8 constant RECORD_KIND_LUCKBOX = 2;
uint8 constant RECORD_KIND_BUY = 3;

interface ICoinflip {
    /// @notice Emitted whenever a player's coinflip claim-state changes (claimable + carry + claim
    ///         cursor), so off-chain consumers can reconstruct valuation from logs without an eth_call.
    event CoinflipClaimState(
        address indexed player,
        uint128 claimableStored,
        uint128 autoRebuyCarry,
        uint24  lastClaim
    );

    /*+======================================================================+
      |                          CORE ACTIONS                                |
      +======================================================================+*/

    /// @notice Deposit FLIP into the daily coinflip system.
    /// @dev Processes any pending claims, funds the stake, applies quest and recycling bonuses,
    ///      then adds stake for the next day's flip.
    ///      Permissionless: the player (player=address(0) or player=msg.sender) or an approved
    ///      operator funds the deposit from the player's settled coinflip winnings first and
    ///      burns the player's wallet FLIP via FLIP.burnForCoinflip for the remainder; any other
    ///      caller funds the whole stake by burning their own FLIP as a gift credited to
    ///      `player`, leaving the player's winnings untouched. The recycling bonus pays on the
    ///      winnings leg only.
    /// @param player The player making the deposit (address(0) or msg.sender for direct deposit).
    /// @param amount Amount of FLIP to deposit (must be >= 100 FLIP minimum).
    /// @custom:reverts AmountLTMin If amount is non-zero but less than 100 FLIP.
    function depositCoinflip(address player, uint256 amount) external;

    /// @notice Claim an exact amount of coinflip winnings as FLIP tokens.
    /// @dev Processes pending daily claims, then mints up to the requested amount.
    ///      Caller can claim for themselves or as an approved operator for another player.
    /// @param player The player claiming (address(0) for msg.sender).
    /// @param amount Amount to claim (will be capped at available balance).
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim up to `amount` of the auto-rebuy carry as minted FLIP while staying on auto-rebuy.
    /// @dev Settles all resolved days first (wins roll into the carry, a pending loss zeroes it),
    ///      then withdraws from the settled carry; the remainder keeps rolling. Blocked during
    ///      the RNG lock. Take-profit chunks surfaced by the settle bank into the claimable side.
    /// @param player The player claiming (address(0) for msg.sender).
    /// @param amount Maximum carry to claim.
    /// @return claimed The actual amount minted from the carry.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    /// @custom:reverts RngLocked If a VRF request is pending.
    /// @custom:reverts AutoRebuyNotEnabled If the player is not on auto-rebuy.
    function claimCoinflipCarry(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Claim coinflip winnings via FLIP contract to cover token transfers/burns.
    /// @dev Access restricted to FLIP contract only. Processes pending claims and mints tokens.
    /// @param player The player claiming.
    /// @param amount Amount to claim.
    /// @return claimed The actual amount claimed and minted.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function claimCoinflipsFromFlip(address player, uint256 amount) external returns (uint256 claimed);

    /// @notice Consume coinflip winnings via FLIP for burns without minting new tokens.
    /// @dev Access restricted to FLIP contract only. Reduces claimable balance without minting.
    /// @param player The player whose balance to consume.
    /// @param amount Amount to consume.
    /// @return consumed The actual amount consumed.
    /// @custom:reverts OnlyFLIP If caller is not the FLIP contract.
    function consumeCoinflipsForBurn(address player, uint256 amount) external returns (uint256 consumed);

    /// @notice Configure auto-rebuy mode for coinflips.
    /// @dev Auto-rebuy automatically rolls over winnings as stake for future flips.
    ///      When enabled, winnings accumulate as carry until claimed. When disabled,
    ///      processes a larger window of pending claims and mints all accumulated tokens.
    /// @param player The player configuring auto-rebuy (address(0) for msg.sender).
    /// @param enabled Whether auto-rebuy should be enabled.
    /// @param takeProfit The threshold amount; winnings above this are auto-claimed in multiples.
    /// @custom:reverts RngLocked If VRF randomness is currently being resolved.
    /// @custom:reverts AutoRebuyAlreadyEnabled If enabling when already enabled (in strict mode).
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function setCoinflipAutoRebuy(
        address player,
        bool enabled,
        uint256 takeProfit
    ) external;

    /// @notice Update the take profit threshold for auto-rebuy mode.
    /// @dev Only callable when auto-rebuy is already enabled. Processes pending claims before updating.
    /// @param player The player configuring (address(0) for msg.sender).
    /// @param takeProfit The new threshold amount for auto-claiming multiples.
    /// @custom:reverts RngLocked If VRF randomness is currently being resolved.
    /// @custom:reverts AutoRebuyNotEnabled If player does not have auto-rebuy enabled.
    /// @custom:reverts NotApproved If caller is not the player and not an approved operator.
    function setCoinflipAutoRebuyTakeProfit(
        address player,
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
    ///        2 = bonus day (level 0 or a level's first jackpot day), 6 = x0-level (post-BAF) bonus day.
    /// @param rngWord The VRF random word for determining outcome.
    /// @param epoch The epoch (day) index being resolved.
    /// @custom:reverts OnlyDegenerusGame If caller is not the DegenerusGame contract.
    function processCoinflipPayouts(
        uint8 bonus,
        uint256 rngWord,
        uint24 epoch
    ) external;

    /*+======================================================================+
      |                       CREDIT SYSTEM                                  |
      +======================================================================+*/

    /// @notice Credit flip stake to a player without burning tokens.
    /// @dev Called by authorized creditors (GAME, QUESTS, AFFILIATE, ADMIN, SDGNRS, WWXRP) for rewards.
    ///      Never touches the biggest-flip record (credits carry recordAmount 0).
    /// @param player The player receiving the flip credit.
    /// @param amount Amount of flip credit to add to next day's stake.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlip(address player, uint256 amount) external;

    /// @notice Credit flips to multiple players in a single call.
    /// @dev Batch version of creditFlip for gas efficiency. Skips zero addresses and amounts.
    /// @param players Player addresses.
    /// @param amounts Credit amounts corresponding to each player.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipBatch(
        address[] calldata players,
        uint256[] calldata amounts
    ) external;

    /// @notice Credit flips to exactly two players in a single call.
    /// @dev Fixed-arity variant of creditFlipBatch — spares the caller the two array
    ///      allocations and the dynamic ABI encode. Skips zero addresses and amounts.
    /// @param player1 First recipient.
    /// @param amount1 First credit amount.
    /// @param player2 Second recipient.
    /// @param amount2 Second credit amount.
    /// @custom:reverts OnlyFlipCreditors If caller is not an authorized creditor.
    function creditFlipPair(
        address player1,
        uint256 amount1,
        address player2,
        uint256 amount2
    ) external;

    /// @notice Arm a game-side all-time record for `player` with `candidate` in the
    ///         record's own unit (spin and lootbox deposit: ETH wei; buy: whole tickets).
    /// @dev GAME only (delegatecall modules). Larger-than-mark candidates ratchet the
    ///      record; clearing the mark by a fifth also claims the category's accrued
    ///      share of the record pool, plus the sDGNRS leg at 1/500 scale. Callers gate
    ///      each record's entry floor before paying for the call. The flip record arms
    ///      internally on direct deposits, never here.
    /// @return The FLIP claimed from the record pool (0 when the candidate only ratcheted
    ///         the mark). Coinflip does NOT credit it — the caller folds it into the FLIP
    ///         its own path already pays, so a claim costs no second stake write.
    function armRecord(
        uint8 kind,
        address player,
        uint256 candidate
    ) external returns (uint256);

    /// @notice Add FLIP to the shared all-time record pool.
    /// @dev GAME only. Level transitions push 0.2% of the completed level's prize pool,
    ///      converted notionally at that level's ticket price — no ETH moves.
    function fundRecordPool(uint256 amount) external;

    /// @notice Arm the x00 seed window if one is due (GAME only, silent when not due).
    /// @param lvl The level whose jackpot phase just ended.
    function armCenturySeed(uint24 lvl) external;

    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (claimableStored + carry).
    /// @dev sDGNRS-only. Settles all resolved days first so the two summed components are disjoint
    ///      and current; sDGNRS holds no wallet balance — its entire FLIP backing lives in these two.
    /// @return backing claimableStored + autoRebuyCarry for sDGNRS.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function redeemableFlipBacking() external returns (uint256 backing);

    /// @notice Remove `base` (wei) of sDGNRS's FLIP backing at redemption submit.
    /// @dev sDGNRS-only. Waterfall: settled claimable (consumed) → auto-rebuy carry (decremented) —
    ///      sDGNRS holds no wallet balance, so backing lives entirely in these two. Credits nothing;
    ///      the redeemer's escrowed slice is paid later on the resolving day's coinflip win via
    ///      creditFlip. Fail-closed if backing < base.
    /// @param base Whole-token-aligned FLIP backing (wei) to remove from sDGNRS.
    /// @custom:reverts OnlysDGNRS If caller is not the sDGNRS contract.
    function withdrawRedeemedFlip(uint256 base) external;

    /*+======================================================================+
      |                          VIEW FUNCTIONS                              |
      +======================================================================+*/

    /// @notice Preview total claimable FLIP for a player including pending daily claims.
    /// @dev Calculates claimable from stored balance plus unprocessed winning days within claim window.
    /// @param player The player to check.
    /// @return mintable Total amount that would be claimable if claimed now.
    function previewClaimCoinflips(
        address player
    ) external view returns (uint256 mintable);

    /// @notice Get player's current coinflip stake for the next day's flip.
    /// @dev Returns the stake amount deposited for the upcoming flip day.
    /// @param player The player to check.
    /// @return The stake amount in FLIP for the next flip.
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
