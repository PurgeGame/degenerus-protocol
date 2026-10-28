// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {RngTags} from "./libraries/RngTags.sol";

import {MineFlipGasBounds as GasBounds} from "./libraries/MineFlipGasBounds.sol";

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

import {ContractAddresses} from "./ContractAddresses.sol";
import {IStETH} from "./interfaces/IStETH.sol";
import {EntropyLib} from "./libraries/EntropyLib.sol";
import {FlipRoundLib} from "./libraries/FlipRoundLib.sol";
import {MineFlipGas} from "./libraries/MineFlipGas.sol";
import {BoundedCall} from "./libraries/BoundedCall.sol";

/// @notice Interface for game contract player-facing functions used by sDGNRS.
interface IDegenerusGamePlayer {
    /// @notice Crank the unified miner router (advance + box opens), paying any earned bounty.
    function mineRun(uint32 gasMultiplierBps) external;
    /// @notice Start or extend a daily afking subscription for account `id` (0 = caller).
    /// @dev The afking subscription surface is GAME-resident. sDGNRS self-subscribes with
    ///      `id == 0`. SDGNRS's subscription is exempt from the seat burn, so `seatId` is
    ///      ignored (pass 0).
    function subscribe(
        uint32 id,
        bool useTickets,
        uint8 dailyQuantity,
        uint256 seatId
    ) external payable;
    /// @notice Claim account `id`'s accumulated ETH winnings (0 = caller); pays the payee.
    function claimClaimable(uint32 id) external;
    /// @notice View claimable ETH winnings for a player.
    function claimableWinningsOf(address player) external view returns (uint256);

    function redemptionReserve() external view returns (uint256);

    /// @notice Current ordered RNG consumer stage (1 = redemption settlement).
    function rngConsumerStage_g379() external view returns (uint8);
    /// @notice Check if game is over.
    function gameOver() external view returns (bool);

    /// @notice Resolve account `id` for `caller`: key, payee and whether `caller` may act for it
    ///         (its key, a smurf's owner, or an approved operator). Reverts for an unallocated
    ///         or zero `id`; never reverts on authorization.
    function resolveAccount_g7029(uint32 id, address caller)
        external view returns (address key, address payee, bool authorized);
    /// @notice Check if the liveness-timeout game-over trigger is active (fires before gameOver latches).
    function livenessTriggered() external view returns (bool);
    /// @notice Get player's activity score and permanent Game wallet ID (0 = none).
    function playerActivityScore(address player) external view returns (uint256 scorePoints, uint32 walletId);

    /// @notice `player`'s current default Game account (0 = none; never allocates).
    function walletIdOf_g3120(address player) external view returns (uint32);
    function acquiredBuyer(uint32 id) external view returns (uint32 buyer);
    /// @notice Resolve a redemption lootbox, drawn from the Game's redemption reserve.
    function resolveRedemptionLootbox(
        uint32 playerId, uint256 amount, uint256 rngWord, uint16 activityScore, uint32 batchId
    ) external;
    /// @notice Credit a redemption's direct half to wallet `playerId`'s game claimable, drawn from
    ///         the Game's redemption reserve.
    function creditRedemptionDirect(uint32 playerId, uint256 amount) external;
}

/// @notice Interface for Coinflip contract methods used by sDGNRS.
interface ICoinflipPlayer {
    /// @notice Preview claimable coinflip winnings for a player.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (seed claimable + carry, disjoint).
    function redeemableFlipBacking() external returns (uint256 backing);
    /// @notice Remove up to `base` whole FLIP of sDGNRS's backing at batch close (claimable → carry).
    function withdrawRedeemedFlip(uint256 base) external returns (uint256 removed);
    /// @notice Read a player's auto-rebuy config; `carry` is the rolling FLIP bankroll.
    function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint24 startDay);

    /// @notice Credit a FLIP flip stake to wallet `id` (sDGNRS is an authorized flip creditor;
    ///         0 is a no-op).
    function creditFlip_g317(uint32 id, uint256 amount) external;
}

/// @notice Interface for DGNRS wrapper contract used by sDGNRS.
interface IDGNRS {
    /// @notice Burn DGNRS from a player on behalf of sDGNRS.
    function burnForSdgnrs(address player, uint256 amount) external;
}

/**
 * @title sDGNRS (sDGNRS)
 * @notice Soulbound token backed by ETH, stETH, and FLIP reserves
 * @dev Receives ETH/stETH from game distributions; reward pools recycle 25-75% of live burns each century.
 *      The vault allocation is minted to the DGNRS wrapper contract; all other holders receive
 *      sDGNRS directly from reward pools (soulbound — no transfer function).
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Accrues FLIP backing on Coinflip (FLIP sent or minted to sDGNRS is staked); a batch close escrows its share
 * - Pre-minted supply split into DGNRS wrapper allocation + reward pools
 * - Game distributes sDGNRS to players by drawing down pools
 * - Completed centuries recycle a random 25-75% of their supply burns into the four ongoing pools
 * - Live burns join a redemption batch (ETH, lootbox and contingent FLIP); after game over a
 *   burn pays proportional ETH + stETH
 */
contract sDGNRS {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();

    /// @notice Thrown when amount exceeds available balance or allowance
    error Insufficient();

    /// @notice Thrown when zero address is provided where not allowed
    error ZeroAddress();

    /// @notice Thrown when ETH or token transfer fails
    error TransferFailed();

    /// @notice Thrown when burns are attempted after liveness fires but before gameOver latches.
    ///         No request closes a batch once liveness fires: the open batch is unwound at the
    ///         game-over price, which a burn can take directly once gameOver latches.
    error BurnsBlockedDuringLiveness();

    /// @notice Thrown when a player tries to claim with no pending redemption
    error NoClaim();

    /// @notice Thrown when a player tries to claim before the batch is resolved
    error NotResolved();

    /// @notice Earlier RNG consumers must finish before live redemptions can settle.
    error RedemptionStageBlocked();

    /// @notice Live redemptions settle only through mineFlip, in order; a self-claim opens once the
    ///         game is over.
    error NotGameOver();

    /// @notice Thrown when a gambling burn's live value is below MIN_REDEMPTION_VALUE.
    error BurnTooSmall();

    /// @notice Thrown when a gambling burn's beneficiary has no Game wallet ID (a burn never
    ///         registers one).
    error NoWalletId();

    // =====================================================================
    //                              EVENTS
    // =====================================================================

    /// @notice Emitted when tokens are transferred between addresses
    /// @param from Source address (address(0) for mints)
    /// @param to Destination address (address(0) for burns)
    /// @param amount Amount of tokens transferred
    event Transfer(address indexed from, address indexed to, uint256 amount);

    /// @notice Emitted when sDGNRS is burned to claim backing assets
    /// @param from Address that burned tokens
    /// @param amount Amount of sDGNRS burned
    /// @param ethOut ETH received
    /// @param stethOut stETH received
    /// @param flipOut FLIP received
    event Burn(address indexed from, uint256 amount, uint256 ethOut, uint256 stethOut, uint256 flipOut);

    /// @notice Emitted when backing assets are deposited into reserves
    /// @param from Address that deposited
    /// @param ethAmount ETH deposited
    /// @param stethAmount stETH deposited
    /// @param flipAmount FLIP amount (always 0; FLIP backing accrues on Coinflip)
    event Deposit(address indexed from, uint256 ethAmount, uint256 stethAmount, uint256 flipAmount);

    /// @notice Emitted when sDGNRS is transferred from a reward pool
    /// @param pool Pool from which tokens were transferred
    /// @param to Recipient address
    /// @param amount Amount transferred
    event PoolTransfer(Pool indexed pool, address indexed to, uint256 amount);

    /// @notice A random 25-75% of the completed century's live burns returned to ongoing pools.
    /// @dev refillPercent is a whole percentage; amounts are raw units. Lootbox receives allocation dust.
    event CenturyRecycled(
        uint24 indexed completedLevel,
        uint256 refillPercent,
        uint256 burned,
        uint256 minted,
        uint256 whale,
        uint256 affiliate,
        uint256 lootbox,
        uint256 reward
    );

    /// @notice Emitted when a gambling burn joins the open redemption batch.
    /// @param player The beneficiary wallet ID.
    /// @param sdgnrsAmount sDGNRS burned into the batch (left supply at the burn; priced at close).
    /// @param batchId The open batch the burn joined.
    event RedemptionSubmitted(uint32 indexed player, uint256 sdgnrsAmount, uint32 indexed batchId);

    /// @notice Emitted when a redemption batch closes with the request that commits its word.
    /// @param batchId The closed batch.
    /// @param tokens sDGNRS the batch's burns removed from supply.
    /// @param ethBase Base (100%) ETH value of the whole batch at the close price, gwei-floored.
    /// @param flipEscrow Whole FLIP removed from sDGNRS's backing for the batch, paid only on its
    ///        synthetic flip win.
    event RedemptionBatchClosed(uint32 indexed batchId, uint256 tokens, uint256 ethBase, uint256 flipEscrow);

    /// @notice Emitted when a redemption batch is resolved.
    /// @param batchId The resolved batch.
    /// @param roll The resolved roll (21-175 live; a flat 100 when the ending resolves the batch).
    /// @param flipReward The synthetic flip's reward percent; 0 on a loss or at the ending.
    event RedemptionResolved(uint32 indexed batchId, uint16 roll, uint16 flipReward);

    /// @notice Emitted when a beneficiary's share of a batch is paid.
    /// @param player The claimant wallet ID.
    /// @param batchId The batch the claim belonged to.
    /// @param roll The resolved roll the claim paid against; 0 for a claim in the batch still
    ///        open at game over, which is unwound at the game-over price.
    /// @param ethPayout The direct leg's ETH value: credited to `player`'s Game claimable while
    ///        the game is live; pushed as ETH (stETH covering any shortfall) in terminal mode.
    /// @param lootboxEth ETH staked into the lootbox leg for the claimant (0 if terminal or
    ///        below the dust floor), resolved as one box order of up to 20 equal boxes.
    /// @param flipPaid Escrowed FLIP (whole tokens) credited to the redeemer as a flip stake —
    ///        nonzero only on the batch's synthetic flip win; 0 on a loss or in terminal mode.
    event RedemptionClaimed(
        uint32 indexed player, uint32 indexed batchId, uint16 roll, uint256 ethPayout, uint256 lootboxEth, uint256 flipPaid
    );

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Degenerus Protocol Revenue and Governance Token";

    /// @notice Token symbol
    string public constant symbol = "sDGNRS";

    /// @notice Token decimals
    uint8 public constant decimals = 12;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of sDGNRS tokens. A gambling burn leaves supply at the burn; until its
    ///         batch closes, prices and shares use supply plus economic escrow as the holder base.
    /// @dev uint128 (<= INITIAL_SUPPLY 1e24 << uint128 max 3.4e38; century refills never exceed
    ///      the previous post-refill supply), packed with the redemption reserve and the open batch
    ///      id into slot 0 (128+96+32 = 256 bits). Each access is an independent masked
    ///      SLOAD/SSTORE.
    uint128 private _totalSupply;

    /// @dev Total reserved redemption ETH value across closed batches and their unpaid claims: a
    ///      close adds min(the batch's 175% share, free backing), resolution lowers it to the rolled total,
    ///      each paid claim releases its rolled share and a finished batch releases its rounding
    ///      dust. Backed live by the Game's redemption reserve, which the close moves out of the
    ///      Game claimable; after game over by custody and the claimable. uint96 holds 7.9e28 wei (~658x the total ETH supply) —
    ///      real-ETH-bounded, safe. Packed into slot 0.
    uint96 private _pendingRedemptionEthValue;

    /// @dev The batch live gambling burns join. Ids start at 1 and only advance when a non-empty
    ///      batch closes. Packed into slot 0.
    uint32 private _openBatch = 1;

    /// @notice Token balance for each address
    mapping(address => uint256) public balanceOf;

    // =====================================================================
    //                          POOL STATE
    // =====================================================================

    /// @notice Enumeration of reward pools
    enum Pool {
        Whale,
        Affiliate,
        Lootbox,
        Reward,
        Degenesis
    }

    /// @notice Balances for each reward pool.
    /// @dev uint128 elements: the compiler packs the 5 lanes into 3 slots in index order
    ///      (Whale|Affiliate, Lootbox|Reward, Degenesis), co-locating the warm whale/affiliate pair
    ///      debited together in a pass purchase. Each balance is <= INITIAL_SUPPLY (1e24) << uint128 max.
    uint128[5] private poolBalances;

    // =====================================================================
    //                   GAMBLING BURN STATE
    // =====================================================================

    // Live gambling burns join the open batch. The next live VRF request (daily or mid-day)
    // closes it at one price for every token in it; the miner settles it on the word that
    // request returns. The ending's request closes nothing: a batch still open at game over is
    // unwound at the game-over price. At most one batch is open and at most one is settling, so
    // the two player lists alternate by batch-id parity. Claims are keyed by the beneficiary's
    // Game wallet ID; the address is needed only to authenticate and to pay.

    /// @dev Two storage words. `ethPayout` is the maximum reserved at close, then the capped
    ///      payout fixed at resolution. Claims share this total pro rata, independent of order.
    ///      Raw tokens never exceed INITIAL_SUPPLY (1e24 < 2**80), including century refills.
    struct RedemptionBatch {
        uint80 tokens;
        uint96 ethPayout;
        uint96 ethBase;
        uint96 flipEscrow;
        uint16 roll;
        uint16 flipReward;
        uint32 id;
    }

    /// @dev Two locators per account in one word, selected by batch parity. Each lane holds
    ///      batchId (low 32) and queue index (high 32). Tags prevent aliasing on buffer reuse.
    mapping(uint32 => uint128) private _claimLocations;

    function redemptionBatches(uint32 id) external view returns (
        uint80 tokens, uint96 ethPayout, uint96 ethBase, uint96 flipEscrow, uint16 roll, uint16 flipReward
    ) {
        RedemptionBatch memory batch = _batchValue(id);
        return (batch.tokens, batch.ethPayout, batch.ethBase, batch.flipEscrow, batch.roll, batch.flipReward);
    }

    function _batchValue(uint32 id) private view returns (RedemptionBatch memory batch) {
        if (_redemptionBatches[id & 1].id == id) batch = _redemptionBatches[id & 1];
    }

    /// @notice Pending raw token amount and first activity score + 1 from the active queue,
    ///         in raw 12-decimal token units.
    function pendingRedemptions(uint32 walletId, uint32 batchId)
        external view returns (uint80 tokens, uint16 activityScore)
    {
        (uint256 index, bool live) = _liveClaimIndex(walletId, batchId);
        uint128 entry;
        if (live) entry = _batchPlayer(batchId & 1, index);
        tokens = uint80(entry);
        activityScore = uint16(entry >> BATCH_PLAYER_SCORE_SHIFT);
    }

    /// @dev The settling batch's prefix below the miner's cursor is paid:
    ///      the miner leaves those entries in place, so they are not live.
    function _liveClaimIndex(uint32 walletId, uint32 batchId) private view returns (uint256 index, bool live) {
        uint32 settling = _settlingBatch;
        if (batchId == 0 || (batchId != _openBatch && batchId != settling)) return (0, false);
        uint64 locator = uint64(_claimLocations[walletId] >> ((batchId & 1) * 64));
        index = uint32(locator >> 32);
        live = uint32(locator) == batchId && (batchId != settling || index >= _redemptionCursor);
    }

    /// @dev Remove before paying, including terminal ETH callbacks.
    function _takeClaim(uint32 walletId, uint32 batchId) private returns (uint128 entry) {
        (uint256 index, bool live) = _liveClaimIndex(walletId, batchId);
        if (live) {
            entry = _batchPlayer(batchId & 1, index);
            if (entry != 0) _setBatchPlayer(batchId & 1, index, 0);
        }
    }

    /// @dev Raw sDGNRS burned into the open batch and not yet priced: already out of every balance
    ///      and `_totalSupply`. Every price or share uses supply plus economic escrow as the
    ///      holder base, so these tokens keep their share until their batch closes.
    ///      Stored as the economic amount plus one to keep the escrow word initialized.
    uint128 private _escrowedSupply = 1;
    /// @dev The closed batch the miner is settling (0 = none).
    uint32 private _settlingBatch;
    /// @dev Next index into the settling batch's player list.
    uint32 private _redemptionCursor;
    /// @dev Two uint32 queue counts, even then odd, fill the remaining eight bytes of the escrow word.
    uint64 private _batchPlayerCounts;

    /// @dev A closed batch has unsettled claims: RNG consumer stage 1, which every later request
    ///      waits for. A batch only closes non-empty, so a settling id always has claims left.
    function redemptionSettlementPending_g153837() external view returns (bool) {
        return _settlingBatch != 0;
    }

    /// @notice Redemption batch pointers: the open batch, the settling batch (0 = none), the
    ///         settlement cursor into its player list, and the raw sDGNRS burned into the open
    ///         batch and not yet priced.
    function redemptionBatchState()
        external view returns (uint32 openBatch, uint32 settlingBatch, uint32 cursor, uint256 escrowedSupply)
    {
        return (_openBatch, _settlingBatch, _redemptionCursor, _escrowedSupply - 1);
    }

    /// @notice Close the open batch inside the transaction that sends the next live VRF request.
    /// @dev Game only, daily and mid-day requests only (the ending's request closes nothing).
    ///      One price for the whole batch: (Game claimable − every outstanding reserve) × batch tokens ÷
    ///      the holder base (supply plus the batch's escrow). Earlier batches are settled before a
    ///      live close (every request waits for stage 1), so earlier claims reserve nothing.
    ///      The batch's tokens left
    ///      supply at their burns; here they only leave the escrow count. The batch's MAX (175%)
    ///      payout, capped at free backing, is reserved, and all of it moves into the Game's
    ///      redemption reserve. A close while another batch still settles keeps the
    ///      batch open (unreachable: requests wait for settlement).
    /// @param gameClaimable sDGNRS's claimable balance on the Game (1 wei of it is dust).
    /// @return pull The batch's reserve, isolated from ordinary Game claimable (at most
    ///         `gameClaimable` − 1).
    function closeRedemptionBatch_g165517(uint256 gameClaimable) external onlyGame returns (uint256 pull) {
        uint32 id = _openBatch;
        RedemptionBatch storage batch = _redemptionBatches[id & 1];
        uint256 tokens = batch.tokens;
        if (batch.id != id || tokens == 0 || _settlingBatch != 0) return 0;

        uint256 escrowed = _escrowedSupply - 1;
        uint256 holderBase = _totalSupply + escrowed;
        uint256 claimable = gameClaimable > 1 ? gameClaimable - 1 : 0;
        // Live legs pay only from the Game reserve, so token custody waits for the ending.
        uint256 gross = claimable > type(uint96).max ? type(uint96).max : claimable;
        uint256 reserved = _pendingRedemptionEthValue;
        uint256 money = gross > reserved ? gross - reserved : 0;
        uint256 ethBase = ((money * tokens) / holderBase / 1e9) * 1e9;

        // FLIP: the batch's share of the settled backing leaves it now and pays only on the
        // batch's synthetic flip win. Sized from the same settled read, so the clamp never binds.
        uint256 flipEscrow = (coinflip.redeemableFlipBacking() * tokens) / holderBase;
        if (flipEscrow != 0) flipEscrow = coinflip.withdrawRedeemedFlip(flipEscrow);

        // The escrow is exactly the open batch's tokens, so this cannot underflow.
        unchecked {
            _escrowedSupply = uint128(escrowed - tokens + 1);
        }

        uint256 maxPayout = (ethBase * MAX_ROLL) / 100;
        if (maxPayout > money) maxPayout = money;
        reserved += maxPayout;
        _pendingRedemptionEthValue = uint96(reserved);
        batch.ethPayout = uint96(maxPayout);
        batch.ethBase = uint96(ethBase);
        batch.flipEscrow = uint96(flipEscrow);
        _settlingBatch = id;
        unchecked {
            _openBatch = id + 1;
        }

        // maxPayout <= money <= gross = claimable.
        pull = maxPayout;
        emit RedemptionBatchClosed(id, tokens, ethBase, flipEscrow);
    }

    /// @notice Resolve the settling batch at a flat ENDING_ROLL (100) if its live settlement never
    ///         started (Game only). It is the only closed batch that can lack a roll: the ending's
    ///         request closes nothing, and every earlier batch settled before the next live close.
    /// @dev Every ending — the terminal word's and the deterministic one — pays the batch at 100,
    ///      never from a word. The FLIP escrow is forfeited (FLIP is worthless at the ending). A
    ///      batch already resolved live keeps its roll.
    function resolveTerminalRedemptions() external onlyGame {
        uint32 id = _settlingBatch;
        if (id == 0) return;
        RedemptionBatch storage batch = _redemptionBatches[id & 1];
        if (batch.roll == 0) _resolveBatch(id, batch, ENDING_ROLL, 0);
    }

    /// @dev Store a batch's roll and synthetic flip and lower its reserve from the MAX added at
    ///      close to the rolled total, which bounds the sum of its claims' rolled shares.
    /// @return rolledTotal The batch's reserve after resolution.
    function _resolveBatch(uint32 id, RedemptionBatch storage batch, uint16 roll, uint16 flipReward)
        private returns (uint256 rolledTotal)
    {
        uint256 ethBase = batch.ethBase;
        rolledTotal = (ethBase * roll) / 100;
        uint256 maxReserve = batch.ethPayout;
        if (rolledTotal > maxReserve) rolledTotal = maxReserve;
        uint256 reserved = _pendingRedemptionEthValue;
        reserved = reserved > maxReserve ? reserved - maxReserve : 0;
        _pendingRedemptionEthValue = uint96(reserved + rolledTotal);
        batch.ethPayout = uint96(rolledTotal);
        batch.roll = roll;
        batch.flipReward = flipReward;
        emit RedemptionResolved(id, roll, flipReward);
    }

    /// @dev Roll in [MIN_ROLL, MAX_ROLL] = [21, 175], 155 values with mean exactly 98, from the
    ///      word hashed under REDEMPTION_AMOUNT (independent of raw bit 0, the daily coinflip).
    function _rollFromWord(uint256 word) private pure returns (uint16) {
        return uint16((EntropyLib.hash2(RngTags.REDEMPTION_AMOUNT, word) % (MAX_ROLL - MIN_ROLL + 1)) + MIN_ROLL);
    }

    // Admission bounds cover the complete beneficiary: the claim and its ETH/ledger funding,
    // plus its lootbox leg as one box order of at most REDEMPTION_BOXES_MAX boxes, bounded like
    // a human entry. These are safety floors, never work charges.
    uint256 private constant REDEMPTION_BASE_GAS = GasBounds.REDEMPTION_BASE_GAS;
    uint256 private constant REDEMPTION_TAIL_GAS = GasBounds.REDEMPTION_TAIL_GAS;
    /// @dev Resolution writes (reserve, roll, flip, batch reserve) before the first claim.
    uint256 private constant REDEMPTION_RESOLVE_GAS = GasBounds.REDEMPTION_RESOLVE_GAS;

    /// @notice Settle the settling batch on `word` (Game only, RNG consumer stage 1).
    /// @dev Stage 1 is part of the essential chain and no request can go out before it finishes,
    ///      so the published read word is always the one that answered the request that closed
    ///      the batch. No word is stored.
    function runRedemptionWork(uint256 word, uint256 allowance) external onlyGame returns (MineFlipGas.Result memory result) {
        return _runRedemptionWork(word, allowance);
    }

    function _runRedemptionWork(uint256 word, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint32 id = _settlingBatch;
        if (id == 0) { result.done = true; return result; }
        // Stage 1 is never selected under liveness or game over, so this also excludes both.
        if (game.rngConsumerStage_g379() != 1) revert RedemptionStageBlocked();
        if (word <= 1) revert NotResolved();
        if (!MineFlipGas.canRun(meter, REDEMPTION_TAIL_GAS, 0)) return result;

        RedemptionBatch storage batch = _redemptionBatches[id & 1];
        uint256 reserveLeft;
        if (batch.roll == 0) {
            if (!MineFlipGas.canRun(meter, REDEMPTION_RESOLVE_GAS, REDEMPTION_TAIL_GAS)) return result;
            // One synthetic flip per batch, hashed under its own tag so it is independent of the
            // word's raw bit 0 (on a daily word that bit is the real coinflip day). Odds match a
            // coinflip day with no bonus; a win pays through creditFlip, whose stake then rides
            // the real flip.
            uint256 synth = uint256(EntropyLib.hash2(RngTags.REDEMPTION_FLIP, word));
            uint16 flipReward = (synth & 1) == 1 ? FlipRoundLib.coinflipRewardPercent(0, synth) : 0;
            reserveLeft = _resolveBatch(id, batch, _rollFromWord(word), flipReward);
            result.progressed = true;
            MineFlipGas.markProgress(meter);
        } else {
            reserveLeft = _settlingReserveLeft;
        }

        uint256 batchTokens = batch.tokens;
        uint256 payout = batch.ethPayout;
        uint256 total = _batchPlayerCount(id & 1);
        uint256 cursor = _redemptionCursor;
        uint256 initialCursor = cursor;
        while (cursor < total) {
            uint128 entry = _batchPlayer(id & 1, cursor);
            uint256 claimTokens = uint80(entry);
            if (claimTokens == 0) {
                if (!MineFlipGas.canRun(meter, GasBounds.REDEMPTION_SKIP_GAS, REDEMPTION_TAIL_GAS)) break;
                _redemptionCursor = uint32(++cursor);
                MineFlipGas.markProgress(meter);
                continue;
            }
            (uint256 rolled, , uint256 lootbox,) =
                _redemptionAmounts((payout * claimTokens) / batchTokens, false);
            uint256 nextMax = REDEMPTION_BASE_GAS;
            if (lootbox != 0) {
                // The lootbox leg's box count, exactly as the Game builds the order.
                uint256 boxes = (lootbox - 1) / GasBounds.REDEMPTION_BOX_UNIT + 1;
                if (boxes > GasBounds.REDEMPTION_BOXES_MAX) boxes = GasBounds.REDEMPTION_BOXES_MAX;
                nextMax += GasBounds.HUMAN_ENTRY_GAS + boxes * GasBounds.HUMAN_BOX_GAS;
            }
            if (!MineFlipGas.canRun(meter, nextMax, REDEMPTION_TAIL_GAS)) break;
            // The entry stays in place: the frontier retires it for every claim lookup.
            // Commit the frontier before any nested calls.
            _redemptionCursor = uint32(++cursor);
            MineFlipGas.markProgress(meter);
            reserveLeft -= rolled;
            // A live claim calls only protocol contracts and has no failure branch.
            _claimRedemptionFor(entry, address(0), id, false, word);
        }
        if (cursor != initialCursor) result.progressed = true;
        result.done = cursor == total;
        if (result.done) {
            _finishRedemptionSettlement(id, reserveLeft);
        } else {
            _settlingReserveLeft = uint96(reserveLeft);
        }
        MineFlipGas.finish(meter);
    }

    /// @dev Release the batch's rounding dust (its rolled total less every claim's rolled share)
    ///      and clear the settlement pointers and the batch's player list.
    function _finishRedemptionSettlement(uint32 id, uint256 reserveLeft) private {
        if (reserveLeft != 0) {
            uint256 reserved = _pendingRedemptionEthValue;
            _pendingRedemptionEthValue = uint96(reserved > reserveLeft ? reserved - reserveLeft : 0);
        }
        _settlingBatch = 0;
        _redemptionCursor = 0;
        _setBatchPlayerCount(id & 1, 0);
    }

    /// @notice Holder base (supply plus the open batch's escrow) immediately after the last century
    ///         refill (initial supply before the first).
    /// @dev All intervening reductions of the holder base are burns; a live gambling burn counts
    ///      once its batch closes. Packed with the century/closure markers in one slot; no per-burn
    ///      writes.
    uint128 public centurySupplyCheckpoint;

    /// @notice Last completed century recycled, starting at 1 for the level-100 transition close.
    uint24 public lastRecycledCentury;

    /// @notice Permanently disables recycling once terminal pool destruction begins.
    bool public recyclingClosed;

    /// @dev The settling batch's rolled total not yet assigned to a paid claim; between
    ///      settlement calls only. Packed beside the century markers.
    uint96 private _settlingReserveLeft;

    /// @dev Two claims per slot, by batch parity: raw token amount (80 bits),
    ///      wallet ID (32 bits), first activity score + 1 (16 bits). No address in settlement.
    mapping(uint256 => uint256)[2] private _batchPlayers;

    function _batchPlayerCount(uint256 parity) private view returns (uint256) {
        return uint32(_batchPlayerCounts >> (parity << 5));
    }

    function _setBatchPlayerCount(uint256 parity, uint256 count) private {
        uint256 shift = parity << 5;
        _batchPlayerCounts = uint64((uint256(_batchPlayerCounts) & ~(uint256(type(uint32).max) << shift))
            | (count << shift));
    }

    function _batchPlayer(uint256 parity, uint256 index) private view returns (uint128) {
        return uint128(_batchPlayers[parity][index >> 1] >> ((index & 1) << 7));
    }

    /// @dev Whole lanes are replaced on reuse. Only terminal manual claims clear a lane;
    ///      live settlement retires entries with the cursor and retains every data word.
    function _setBatchPlayer(uint256 parity, uint256 index, uint128 entry) private {
        uint256 shift = (index & 1) << 7;
        uint256 word = _batchPlayers[parity][index >> 1];
        _batchPlayers[parity][index >> 1] = (word & ~(uint256(type(uint128).max) << shift))
            | (uint256(entry) << shift);
    }

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @notice Initial supply (1 trillion tokens)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e12;

    /// @dev Basis points denominator (100%)
    uint16 private constant BPS_DENOM = 10_000;

    /// @dev Vault allocation (20%), minted to the DGNRS wrapper
    uint16 private constant VAULT_BPS = 2000;

    /// @dev Pool distribution other than the vault allocation (BPS of total supply).
    uint16 private constant WHALE_POOL_BPS = 1000;
    uint16 private constant AFFILIATE_POOL_BPS = 3000;
    uint16 private constant LOOTBOX_POOL_BPS = 2000;
    uint16 private constant REWARD_POOL_BPS = 1000;
    uint16 private constant DEGENESIS_POOL_BPS = 1000;

    /// @dev Maximum redemption roll (percent). The resolve roll is in [21, 175]; at batch close the
    ///      MAX possible payout min(base × MAX_ROLL / 100, free backing) is reserved and held in the
    ///      Game's redemption reserve, moved out of claimableWinnings[SDGNRS], so no concurrent claimable drain
    ///      can under-fund a later claim. Resolution lowers the reserve from MAX to the rolled total
    ///      (accounting only — any over-pull stays as free backing).
    uint256 private constant MAX_ROLL = 175;

    /// @dev Minimum redemption roll (percent). [21, 175] has mean 98: the roll's low end carries a
    ///      2% redemption cost that stays as backing for remaining holders.
    uint256 private constant MIN_ROLL = 21;

    /// @dev Flat roll for a settling batch the ending resolves (terminal word or deterministic).
    uint16 private constant ENDING_ROLL = 100;

    /// @dev Minimum live redemption value at admission; no fixed token-count floor.
    uint256 public constant MIN_REDEMPTION_VALUE = 0.01 ether;

    uint256 private constant BATCH_PLAYER_ID_SHIFT = 80;
    uint256 private constant BATCH_PLAYER_SCORE_SHIFT = 112;

    /// @dev This contract's own Game wallet ID; the Game constructor registers it.
    uint32 private constant SDGNRS_WALLET_ID = 2;

    /// @dev Minimum ETH size for a redemption lootbox (0.01 ETH). At claim the rolled value splits
    ///      50/50 into a direct-ETH leg and a lootbox leg; if the lootbox half lands below this floor
    ///      (i.e. total rolled value under ~0.02 ETH), the lootbox leg is dropped entirely. The player
    ///      keeps only the direct half plus whatever the escrowed FLIP pays on the batch's synthetic
    ///      flip; the dropped lootbox
    ///      value is NOT paid out to the player — it is forfeited back to sDGNRS's own claimable on the
    ///      Game as free backing, raising backing for remaining holders. Live-game only; terminal
    ///      claims are already 100% direct.
    uint256 private constant MIN_REDEMPTION_LOOTBOX_ETH = 0.01 ether;

    /// @dev Game contract reference for player actions and claimable queries
    IDegenerusGamePlayer private constant game = IDegenerusGamePlayer(ContractAddresses.GAME);

    /// @dev Coinflip contract for claimable FLIP withdrawals during burns
    ICoinflipPlayer private constant coinflip =
        ICoinflipPlayer(ContractAddresses.COINFLIP);

    /// @dev DGNRS wrapper contract for burning wrapped DGNRS to receive sDGNRS backing
    IDGNRS private constant dgnrsWrapper = IDGNRS(ContractAddresses.DGNRS);

    /// @dev stETH token reference
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    // =====================================================================
    //                          MODIFIERS
    // =====================================================================

    /// @dev Restricts function to game contract only
    modifier onlyGame() {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        _;
    }
    // =====================================================================
    //                          CONSTRUCTOR
    // =====================================================================

    /// @notice Initializes token supply and distributes to pools
    /// @dev Mints the vault allocation to the DGNRS wrapper address and pool allocations to this contract
    constructor() {
        uint256 vaultAmount = (INITIAL_SUPPLY * VAULT_BPS) / BPS_DENOM;
        uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
        uint256 degenesisAmount = (INITIAL_SUPPLY * DEGENESIS_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 totalAllocated = vaultAmount + whaleAmount + degenesisAmount + affiliateAmount + lootboxAmount + rewardAmount;
        if (totalAllocated < INITIAL_SUPPLY) {
            uint256 dust;
            unchecked {
                dust = INITIAL_SUPPLY - totalAllocated;
            }
            lootboxAmount += dust;
        }
        uint256 poolTotal =
            whaleAmount + degenesisAmount + affiliateAmount + lootboxAmount + rewardAmount;

        _mint(ContractAddresses.DGNRS, vaultAmount);
        _mint(address(this), poolTotal);
        centurySupplyCheckpoint = _totalSupply;

        // Pool amounts are BPS slices of INITIAL_SUPPLY (1e24) << uint128 max — narrowing is safe.
        poolBalances[uint8(Pool.Whale)] = uint128(whaleAmount);
        poolBalances[uint8(Pool.Affiliate)] = uint128(affiliateAmount);
        poolBalances[uint8(Pool.Lootbox)] = uint128(lootboxAmount);
        poolBalances[uint8(Pool.Reward)] = uint128(rewardAmount);
        poolBalances[uint8(Pool.Degenesis)] = uint128(degenesisAmount);

        // Protocol-owned self-subscription: daily lootbox buy of flat quantity 1 for the
        // caller's own account (`id == 0`), claimable first, then prepaid AFKing ETH.
        // The afking module exempts the pinned SDGNRS wallet from its seat burn and the
        // completed-day signup gate, so this subscribe lands before the seat token is deployed
        // and `seatId` is ignored; the token's constructor then mints sDGNRS its construction
        // seat. An unfunded day pauses the seat until it can pay again.
        // Coinflip auto-rebuy is NOT enabled here: during the 20-day seed window
        // sDGNRS's daily flip wins accumulate as unminted coinflip claimable backing
        // (sDGNRS never holds a FLIP wallet balance); Coinflip arms perpetual
        // auto-rebuy (0 take-profit) once the final seeded day settles, after which
        // wins roll into the carry.
        game.subscribe(0, false, 1, 0);

        // Register this contract's ENS reverse name (best-effort; skipped when the
        // registrar is unset — local/test/testnet builds). The setName(string)
        // selector is shared by the L1 ReverseRegistrar and Base's L2ReverseRegistrar.
        address ensReg = ContractAddresses.ENS_REVERSE_REGISTRAR;
        if (ensReg != address(0)) {
            (bool ok, ) = ensReg.call(
                // raw-selectors: justified — best-effort ENS reverse-name; setName(string) has no deploy-wide bound interface and must not revert deployment
                abi.encodeWithSignature("setName(string)", "sdgnrs.degenerus.eth")
            );
            ok;
        }
    }

    // =====================================================================
    //                          WRAPPER FUNCTIONS
    // =====================================================================

    /// @notice Transfer sDGNRS from the wrapper to a recipient (wrapper only)
    /// @dev Called by DGNRS contract when the vault unwraps DGNRS to soulbound sDGNRS.
    ///      Direct balance manipulation avoids modifying _transfer authorization.
    /// @param to Recipient address
    /// @param amount Amount to transfer
    /// @custom:reverts Unauthorized If caller is not DGNRS contract
    /// @custom:reverts ZeroAddress If to is zero address
    /// @custom:reverts Insufficient If wrapper balance is insufficient
    function wrapperTransferTo(address to, uint256 amount) external {
        if (msg.sender != ContractAddresses.DGNRS) revert Unauthorized();
        if (to == address(0)) revert ZeroAddress();
        uint256 bal = balanceOf[ContractAddresses.DGNRS];
        if (amount > bal) revert Insufficient();
        unchecked {
            balanceOf[ContractAddresses.DGNRS] = bal - amount;
            balanceOf[to] += amount;
        }
        emit Transfer(ContractAddresses.DGNRS, to, amount);
    }

    // =====================================================================
    //                          PLAYER ACTIONS
    // =====================================================================

    /// @notice Crank the game miner router on behalf of sDGNRS (advance + box opens)
    /// @dev Routes through mineFlip so sDGNRS earns the miner bounty for the work;
    ///      reverts NoWork() when nothing is due.
    /// @param gasMultiplierBps Forwarded to mineFlip unchanged; 0 selects the 1x default.
    function gameAdvance(uint32 gasMultiplierBps) external {
        game.mineRun(gasMultiplierBps);
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit from the game contract.
    /// @dev The Game pays sDGNRS ETH only from game over on (its claimable and the final sweep).
    ///      Custody counts as backing only then, read live via address(this).balance, so no running
    ///      counter is kept here.
    /// @custom:reverts Unauthorized If caller is not the game contract.
    receive() external payable {
        if (msg.sender != ContractAddresses.GAME) revert Unauthorized();
        emit Deposit(msg.sender, msg.value, 0, 0);
    }

    /// @notice Receive stETH deposit from game contract
    /// @dev Only callable by game contract. Transfers stETH from caller and adds to reserve.
    /// @param amount Amount of stETH to deposit
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts TransferFailed If stETH transfer fails
    function depositSteth(uint256 amount) external onlyGame {
        if (!steth.transferFrom(msg.sender, address(this), amount)) revert TransferFailed();
        emit Deposit(msg.sender, 0, amount, 0);
    }

    // =====================================================================
    //                          POOL SPENDING (Game Only)
    // =====================================================================

    /// @notice Get remaining balance for a reward pool
    /// @param pool Pool identifier
    /// @return Remaining pool balance
    function poolBalance(Pool pool) external view returns (uint256) {
        return poolBalances[_poolIndex(pool)];
    }

    /// @notice Total supply of sDGNRS tokens (ERC20).
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Total redemption value reserved for closed batches and their unpaid claims (wei):
    ///         paid from the Game's redemption reserve live, from custody after game over.
    function pendingRedemptionEthValue() external view returns (uint256) {
        return _pendingRedemptionEthValue;
    }

    /// @notice sDGNRS supply held by governance-eligible addresses.
    /// @dev Excludes undistributed pools (held by this contract), DGNRS wrapper, and vault.
    ///      Gambling burns already left `_totalSupply` at the burn, so they never vote.
    function votingSupply() external view returns (uint256) {
        return _totalSupply
            - balanceOf[address(this)]
            - balanceOf[ContractAddresses.DGNRS]
            - balanceOf[ContractAddresses.VAULT];
    }

    /// @notice Transfer sDGNRS from a reward pool to a recipient
    /// @dev Only callable by game contract. Transfers up to available balance if requested amount exceeds pool.
    /// @param pool Pool identifier
    /// @param to Recipient address
    /// @param amount Requested amount of sDGNRS to transfer
    /// @return transferred Actual amount transferred (may be less than requested if pool depleted)
    /// @custom:reverts Unauthorized If caller is not game contract
    /// @custom:reverts ZeroAddress If to is zero address
    function transferFromPool_g106128(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
        if (amount == 0) return 0;
        if (to == address(0)) revert ZeroAddress();
        uint8 idx = _poolIndex(pool);
        uint256 available = poolBalances[idx];
        if (available == 0) return 0;
        if (amount > available) {
            amount = available;
        }
        unchecked {
            poolBalances[idx] = uint128(available - amount);
            balanceOf[address(this)] -= amount;
        }
        if (to == address(this)) {
            // Self-win: burn instead of no-op transfer, increasing value per remaining token
            _totalSupply = uint128(_totalSupply - amount);
            emit Transfer(address(this), address(0), amount);
        } else {
            balanceOf[to] += amount;
            emit Transfer(address(this), to, amount);
        }
        emit PoolTransfer(pool, to, amount);
        return amount;
    }

    /// @notice Recycle a random 25-75% of burns since the previous completed century into ongoing pools.
    /// @dev GAME calls once as an x00 transition closes. No external calls or backing movements.
    ///      The post-mint checkpoint counts each holder-base reduction once, including self-awards
    ///      and wrapped redemptions. The committed transition word selects one of 51 whole
    ///      percentages; caller, timing and burn amount cannot change the roll, and a live burn made
    ///      while the word is public leaves the holder base, and so the refill, unchanged.
    ///      Fractional raw-unit dust expires.
    ///      Stale/non-boundary calls are no-ops. A later boundary consumes the checkpoint delta
    ///      once; it never loops over or fabricates separate missed-century budgets.
    function recycleCentury(uint24 completedLevel, uint256 rngWord) external onlyGame {
        if (recyclingClosed || completedLevel == 0 || completedLevel % 100 != 0) return;
        uint24 century = completedLevel / 100;
        if (century <= lastRecycledCentury) return;

        // Holder base, not raw supply: a live burn moves tokens from supply into the open batch's
        // escrow without changing the base, so a burn landing while this word is public cannot
        // move the refill. Escrowed tokens count as burned once their batch closes, and a close
        // happens inside a request, before its word exists.
        uint256 burned = uint256(centurySupplyCheckpoint) - (uint256(_totalSupply) + _escrowedSupply - 1);
        uint256 refillPercent = 25 + EntropyLib.hash2(RngTags.CENTURY_REFILL, rngWord) % 51;
        uint256 minted = burned * refillPercent / 100;
        uint256 whale = minted / 7;
        uint256 affiliate = (minted * 3) / 7;
        uint256 reward = whale;
        uint256 lootbox = minted - whale - affiliate - reward;

        if (minted != 0) {
            _mint(address(this), minted);
            // Every pool plus its credit is <= the new total supply, so each share
            // fits uint128. Checked additions preserve pool inventory; Degenesis receives zero.
            poolBalances[uint8(Pool.Whale)] += uint128(whale);
            poolBalances[uint8(Pool.Affiliate)] += uint128(affiliate);
            poolBalances[uint8(Pool.Lootbox)] += uint128(lootbox);
            poolBalances[uint8(Pool.Reward)] += uint128(reward);
        }
        // Stamp even a zero mint. Post-mint holder base stays <= checkpoint: at least 25% stays burned.
        centurySupplyCheckpoint = uint128(uint256(_totalSupply) + _escrowedSupply - 1);
        lastRecycledCentury = century;
        emit CenturyRecycled(completedLevel, refillPercent, burned, minted, whale, affiliate, lootbox, reward);
    }

    /// @notice Burn all undistributed pool tokens at game over and permanently close recycling.
    /// @dev Only callable by game contract. Burns this contract's own balance.
    function burnAtGameOver() external onlyGame {
        recyclingClosed = true;
        uint256 bal = balanceOf[address(this)];
        if (bal == 0) return;
        unchecked {
            balanceOf[address(this)] = 0;
            _totalSupply = uint128(_totalSupply - bal);
        }
        delete poolBalances;
        emit Transfer(address(this), address(0), bal);
    }

    // =====================================================================
    //                          BURN (Public)
    // =====================================================================

    /// @notice Forfeit the seller's entire native sDGNRS balance when its main account is liquidated.
    /// @dev Game authenticates the seller. No payout, reserve, queue entry or ID link is created.
    ///      Already submitted redemptions are unaffected; wrapped DGNRS is not burned.
    function burnForLiquidation(address seller) external onlyGame {
        uint256 amount = balanceOf[seller];
        if (amount == 0) return;
        balanceOf[seller] = 0;
        _totalSupply = uint128(uint256(_totalSupply) - amount);
        emit Transfer(seller, address(0), amount);
        emit Burn(seller, amount, 0, 0, 0);
    }

    /// @notice Burn sDGNRS to claim proportional share of backing assets
    /// @dev Post-gameOver: deterministic payout. During game: the tokens burn now and join the open
    ///      redemption batch. The next live VRF request closes and prices it; the miner settles
    ///      it on that request's word. Returns (0,0,0) during game.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return flipOut Always 0
    /// @custom:reverts BurnsBlockedDuringLiveness If liveness fired but gameOver has not yet latched.
    function burn(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 flipOut) {
        if (game.gameOver()) {
            (ethOut, stethOut) = _deterministicBurn(msg.sender, amount);
            return (ethOut, stethOut, 0);
        }
        if (game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
        _submitGamblingClaim(msg.sender, amount);
        return (0, 0, 0);
    }

    /// @notice Burn wrapped DGNRS (held by the caller) to claim proportional backing assets
    /// @dev Burns the caller's DGNRS wrapper tokens, then burns the corresponding sDGNRS backing
    ///      held by the DGNRS contract.
    ///      Post-gameOver: deterministic payout. During game: joins the open redemption batch.
    /// @param amount Amount of sDGNRS-equivalent to burn (from DGNRS wrapper balance)
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return flipOut Always 0
    /// @custom:reverts BurnsBlockedDuringLiveness If liveness fired but gameOver has not yet latched.
    function burnWrapped(uint256 amount) external returns (uint256 ethOut, uint256 stethOut, uint256 flipOut) {
        // burnForSdgnrs makes no external calls, so gameOver cannot change
        // between the gate and the branch — one read serves both.
        bool isOver = game.gameOver();
        if (!isOver && game.livenessTriggered()) revert BurnsBlockedDuringLiveness();
        dgnrsWrapper.burnForSdgnrs(msg.sender, amount);
        if (isOver) {
            (ethOut, stethOut) = _deterministicBurnFrom(msg.sender, ContractAddresses.DGNRS, amount);
            return (ethOut, stethOut, 0);
        }
        _submitGamblingClaimFrom(msg.sender, ContractAddresses.DGNRS, amount);
        return (0, 0, 0);
    }

    /// @dev Deterministic burn: player burns their own sDGNRS and receives backing assets directly.
    function _deterministicBurn(address player, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {
        return _deterministicBurnFrom(player, player, amount);
    }

    /// @dev Deterministic burn parameterized by beneficiary and burnFrom.
    ///      Used for the wrapped case where sDGNRS is burned from DGNRS contract's balance
    ///      but ETH/stETH goes to beneficiary. No FLIP payout (gameOver burns are pure ETH/stETH).
    ///      Priced by `_gameOverValue`: reserves excluded, holder base including the escrow of a
    ///      batch still open at game over (its claims keep their share and unwind at this price).
    function _deterministicBurnFrom(address beneficiary, address burnFrom, uint256 amount) private returns (uint256 ethOut, uint256 stethOut) {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        uint256 value = _gameOverValue(amount);

        unchecked {
            balanceOf[burnFrom] = bal - amount;
            _totalSupply = uint128(_totalSupply - amount);
        }
        emit Transfer(burnFrom, address(0), amount);

        (ethOut, stethOut) = _payGameOverValue(beneficiary, value);

        // No FLIP payout for gameOver burns — pure ETH/stETH only
        emit Burn(beneficiary, amount, ethOut, stethOut, 0);
    }

    /// @dev Game-over value of `amount` of the holder base: ETH + stETH + Game claimable net of
    ///      every redemption reserve, over supply plus the open batch's escrow. Floored at zero: an
    ///      stETH loss that leaves custody below the reserve prices at nothing instead of
    ///      panicking every burn after game over.
    function _gameOverValue(uint256 amount) private view returns (uint256) {
        return _holderValue(amount, true);
    }

    /// @dev `amount`'s share of backing net of reserves over the holder base; token custody
    ///      counts only when claims can pay in it.
    function _holderValue(uint256 amount, bool withCustody) private view returns (uint256) {
        return (_liveMoney(withCustody) * amount) / (uint256(_totalSupply) + _escrowedSupply - 1);
    }

    /// @dev Pay `value` of game-over backing to `to`: ETH first, stETH for the rest. sDGNRS's game
    ///      claimable is pulled first when the ETH leg alone is short or paying from custody would
    ///      drop ETH + stETH below the redemption reserve, so custody keeps covering every later
    ///      claim. stETH goes first and the untrusted ETH call last; callers write state before.
    function _payGameOverValue(address to, uint256 value) private returns (uint256 ethOut, uint256 stethOut) {
        // An acquired account's claim becomes free backing when its escrow is released.
        // Keep it in place; this contract's ETH receiver accepts only Game deposits.
        if (to == address(this)) return (0, 0);
        uint256 ethBal = address(this).balance;
        (uint256 custody,) = _redemptionBacking(0, true);
        if ((value > ethBal || value + _pendingRedemptionEthValue > custody) && _claimableWinnings() != 0) {
            game.claimClaimable(0);
            ethBal = address(this).balance;
            (custody,) = _redemptionBacking(0, true);
        }
        uint256 stethBal = custody - ethBal;

        if (value <= ethBal) {
            ethOut = value;
        } else {
            ethOut = ethBal;
            stethOut = value - ethOut;
            if (stethOut > stethBal) revert Insufficient();
        }

        if (stethOut > 0) {
            if (!steth.transfer(to, stethOut)) revert TransferFailed();
        }

        if (ethOut > 0) {
            (bool success, ) = to.call{value: ethOut}("");
            if (!success) revert TransferFailed();
        }
    }

    // =====================================================================
    //                       GAMBLING BURN FUNCTIONS
    // =====================================================================

    /// @notice Claim account `id`'s gambling-burn redemption in batch `batchId` once the game is over.
    /// @dev In a live game mineFlip settles every redemption in batch order, so this is the
    ///      post-gameover door only, and it deletes the claim under the account's wallet ID. Only
    ///      the account's key, a smurf's owner or an operator approved for the account on the GAME
    ///      may call (`id == 0` is the caller); acquired-account claims are permissionless.
    ///      The payout is pushed straight to the
    ///      account's payee (ETH, with stETH covering any ETH shortfall) rather than credited to
    ///      the Game — a game-claimable credit would forfeit in the post-gameover sweep.
    ///      - A closed batch must carry a roll (resolved live, or at a flat 100 by the ending): the rolled amount pays 100% direct, with no lootbox leg
    ///        and no FLIP.
    ///      - The batch still open at game over never closed and has no price or roll: each claim
    ///        unwinds at the plain game-over value of its tokens — exactly what a game-over burn of
    ///        that many tokens pays, through the same payout path. No roll, lootbox or FLIP.
    /// @param id Claimant account (0 = caller).
    /// @param batchId Batch whose claim to settle.
    function claimRedemption(uint32 id, uint32 batchId) external {
        bool open = batchId == _openBatch;
        if (!open && _batchValue(batchId).roll == 0) revert NotResolved();
        // Only once the game is over, which is irreversible: while the game-over trigger reads true
        // before that, it can still read false again, and a terminal settlement taken then would stick.
        if (!game.gameOver()) revert NotGameOver();
        (address payee, uint32 walletId) = _claimant(id);
        uint128 entry = _takeClaim(walletId, batchId);
        if (entry == 0) revert NoClaim();
        if (open) {
            _unwindOpenClaim(entry, payee, walletId, batchId);
            return;
        }
        _claimRedemptionFor(entry, payee, batchId, true, 0);
    }

    /// @dev Pay a claim in the batch still open at game over its tokens' game-over value, to the
    ///      account's payee. The tokens left supply at the burn but stayed in the holder base
    ///      through the escrow, so the value matches a game-over burn of the same count; the
    ///      escrow then drops by them.
    function _unwindOpenClaim(uint128 entry, address payee, uint32 walletId, uint32 batchId) private {
        uint256 tokens = uint80(entry);
        uint256 value = _gameOverValue(tokens);
        // The escrow and the batch hold every open claim's tokens, so neither can underflow.
        unchecked {
            _escrowedSupply -= uint128(tokens);
            _redemptionBatches[batchId & 1].tokens -= uint80(tokens);
        }
        emit RedemptionClaimed(walletId, batchId, 0, value, 0, 0);
        _payGameOverValue(payee, value);
    }

    /// @dev The estimator and execution use identical rounding and dust treatment.
    function _redemptionAmounts(uint256 payout, bool terminal)
        private pure returns (uint256 rolled, uint256 direct, uint256 lootbox, uint256 forfeited)
    {
        rolled = payout;
        if (terminal) return (rolled, rolled, 0, 0);
        direct = rolled / 2;
        lootbox = rolled - direct;
        if (lootbox < MIN_REDEMPTION_LOOTBOX_ETH) {
            forfeited = lootbox;
            lootbox = 0;
        }
    }

    /// @dev Shared settle core for the miner's batch settlement and the post-game-over
    ///      claim. Callers authenticate and remove the entry before any external call. The miner
    ///      passes no address; `payee` is used only for a terminal transfer. Claims share the
    ///      capped batch payout pro rata, with identical rounding for admission and execution.
    function _claimRedemptionFor(
        uint128 entry,
        address payee,
        uint32 batchId,
        bool isTerminal,
        uint256 word
    ) private {
        uint256 tokens = uint80(entry);
        uint32 walletId = uint32(entry >> BATCH_PLAYER_ID_SHIFT);
        RedemptionBatch memory batch = _batchValue(batchId);

        (uint256 totalRolledEth, uint256 ethDirect, uint256 lootboxEth, uint256 forfeitEth) =
            _redemptionAmounts((uint256(batch.ethPayout) * tokens) / batch.tokens, isTerminal);

        // Release the rolled share from the reserve (both direct and lootbox portions leave
        // sDGNRS). The MAX − rolled over-pull stays in the Game reserve as free backing. Checked:
        // resolution left at least the batch's rolled total, which bounds every claim's share.
        _pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue - totalRolledEth);

        // Contingent FLIP escrow: the claim's share of the whole-FLIP slice removed from sDGNRS's
        // backing at close. The batch's synthetic flip is the first of two flips: a win pays the
        // principal PLUS that flip's multiplier as a flip credit, which then rides the real
        // coinflip (the second flip). A loss pays nothing (symmetric with the auto-rebuy carry
        // zeroing for every holder on a losing flip). In terminal mode FLIP is worthless and
        // skipped entirely. The slot is already cleared (CEI) and creditFlip makes no callback
        // into this contract.
        uint256 flipPaid;
        if (!isTerminal && batch.flipReward != 0) {
            uint256 principal = (uint256(batch.flipEscrow) * tokens) / batch.tokens;
            if (principal != 0) {
                flipPaid = principal + (principal * uint256(batch.flipReward)) / 100;
                coinflip.creditFlip_g317(walletId, flipPaid);
            }
        }

        emit RedemptionClaimed(walletId, batchId, batch.roll, ethDirect, lootboxEth, flipPaid);

        if (isTerminal) {
            // 100% direct push to the payee (account authorization enforced by callers; the
            // untrusted .call comes after the slot delete above — CEI).
            _payGameOverValue(payee, ethDirect);
            return;
        }

        // Live legs spend the protected Game reserve. Ordinary loans and purchases cannot
        // consume this backing.
        if (lootboxEth != 0) {
            uint16 actScore = uint16(entry >> BATCH_PLAYER_SCORE_SHIFT) - 1;
            // Burns commit before the word that settles their batch exists: the batch closes
            // with the request that word answers. Live callers pass that word (the miner's
            // session word).
            // The claim's beneficiary ID, committed at the burn, is the owner input.
            uint256 entropy = EntropyLib.hash3(RngTags.REDEMPTION_BOX, word, uint256(walletId));
            game.resolveRedemptionLootbox(walletId, lootboxEth, entropy, actScore, batchId);
        }

        // Direct half: credit into the player's game claimable (a permissionless trigger must
        // not push ETH at the player); the player withdraws via the access-gated claimClaimable.
        if (ethDirect != 0) game.creditRedemptionDirect(walletId, ethDirect);

        // Forfeited dust-lootbox half → sDGNRS's OWN claimable on the Game (SDGNRS_WALLET_ID),
        // from the same reserve. With this leg the full rolled amount leaves the reserve (direct
        // half to the player, forfeited half to sDGNRS), so it reconciles exactly with the
        // pendingRedemptionEthValue release.
        if (forfeitEth != 0) game.creditRedemptionDirect(SDGNRS_WALLET_ID, forfeitEth);
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview the value and FLIP output for burning sDGNRS
    /// @dev The live price: the proportional share of Game backing (sDGNRS's Game claimable plus
    ///      the Game's redemption reserve), net of pendingRedemptionEthValue (owed to closed
    ///      batches), over the holder base (supply plus the open batch's escrow); token custody
    ///      (ETH and stETH) counts only after game over. A live burn is
    ///      priced when its batch closes, so this is an estimate before the batch-wide upside cap. After game over
    ///      it is exactly the deterministic burn's value. The value is paid as ETH, stETH, or a mix
    ///      chosen at pay time — the two are at par protocol-wide, so it is reported as one
    ///      wei-denominated figure. GameOver burns pay no FLIP.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut Total value that would be received, in wei (paid as ETH and/or stETH)
    /// @return flipOut FLIP that would be received (0 during gameOver)
    function previewBurnValue(uint256 amount) external view returns (uint256 ethOut, uint256 flipOut) {
        uint256 supply = uint256(_totalSupply) + _escrowedSupply - 1;
        if (amount == 0 || amount > supply) return (0, 0);

        bool over = game.gameOver();
        ethOut = _holderValue(amount, over);

        // GameOver burns pay no FLIP. sDGNRS's full FLIP backing is its seed-reserve claimable +
        // the auto-rebuy carry (incoming FLIP rides tomorrow's stake and settles into these);
        // it holds no wallet balance.
        // No reserve term: a batch close removes its escrowed slice from this backing, so these
        // live reads are already net of closed batches. Best-effort (the carry/claimable can
        // momentarily lag a stalled advance or an in-flight stake).
        if (!over) {
            uint256 claimableFlip = coinflip.previewClaimCoinflips(address(this));
            (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(address(this));
            uint256 totalFlip = claimableFlip + carry;
            flipOut = (totalFlip * amount) / supply;
        }
    }

    /// @notice Get FLIP backing available for new burns (seed claimable + auto-rebuy carry).
    /// @dev No reserve subtraction: a batch close removes its escrowed slice from this backing,
    ///      so these live reads are already net of closed batches. sDGNRS holds no wallet
    ///      balance; its FLIP lives in the seed-reserve claimable and the auto-rebuy carry
    ///      (incoming FLIP rides tomorrow's stake and settles into these).
    /// @return FLIP backing value (seed claimable + auto-rebuy carry).
    function flipReserve() external view returns (uint256) {
        uint256 claimableFlip = coinflip.previewClaimCoinflips(address(this));
        (, , uint256 carry, ) = coinflip.coinflipAutoRebuyInfo(address(this));
        return claimableFlip + carry;
    }

    // =====================================================================
    //                          INTERNAL HELPERS
    // =====================================================================

    /// @dev Submit a gambling burn claim on behalf of player burning their own sDGNRS.
    function _submitGamblingClaim(address player, uint256 amount) private {
        _submitGamblingClaimFrom(player, player, amount);
    }

    /// @dev Core gambling burn logic. Burns `amount` from burnFrom now (balance and supply, with
    ///      the Transfer to address(0)), counts it in the open batch's escrow so it keeps its share
    ///      of the holder base until the batch closes, and records it on the beneficiary's claim in
    ///      that batch. No price, reserve or FLIP is fixed here: the batch close prices every token
    ///      in the batch at once. The beneficiary must already hold a Game wallet ID.
    function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        // Measured at the live price the batch close will use.
        if (_holderValue(amount, false) < MIN_REDEMPTION_VALUE) revert BurnTooSmall();

        uint32 id = _openBatch;
        RedemptionBatch storage batch = _redemptionBatches[id & 1];
        uint256 supply = _totalSupply;
        uint256 escrowed = _escrowedSupply - 1;
        uint256 tokens = batch.id == id ? batch.tokens : 0;
        (uint256 score, uint32 walletId) = game.playerActivityScore(beneficiary);
        if (walletId == 0) revert NoWalletId();

        // Burned now; the escrow count keeps the tokens in the holder base until the close.
        unchecked {
            balanceOf[burnFrom] = bal - amount;
            _totalSupply = uint128(supply - amount);
        }
        _escrowedSupply = uint128(escrowed + amount + 1);
        if (batch.id != id) {
            assembly ("memory-safe") {
                sstore(batch.slot, amount)
                sstore(add(batch.slot, 1), shl(224, id))
            }
        } else {
            batch.tokens = uint80(tokens + amount);
        }
        emit Transfer(burnFrom, address(0), amount);

        uint256 parity = id & 1;
        uint256 locations = _claimLocations[walletId];
        uint64 lane = uint64(locations >> (parity * 64));
        uint80 units = uint80(amount);
        if (uint32(lane) != id) {
            uint256 index = _batchPlayerCount(parity);
            _setBatchPlayer(parity, index, uint128(units) | (uint128(walletId) << BATCH_PLAYER_ID_SHIFT)
                | (uint128(uint16(score) + 1) << BATCH_PLAYER_SCORE_SHIFT));
            // One entry per nonzero uint32 wallet ID: the count cannot exceed uint32.max.
            _setBatchPlayerCount(parity, index + 1);
            uint256 locator = uint256(id) | (index << 32);
            _claimLocations[walletId] = uint128(
                (locations & ~(uint256(type(uint64).max) << (parity * 64))) | (locator << (parity * 64))
            );
        } else {
            // Only the amount changes: position and first activity snapshot stay fixed.
            // The entire supply in units fits in 80 bits, so this addition cannot carry into ID.
            uint256 index = uint32(lane >> 32);
            _setBatchPlayer(parity, index, _batchPlayer(parity, index) + uint128(units));
        }

        emit RedemptionSubmitted(walletId, amount, id);
    }

    /// @dev Authentication and terminal recipient resolution are outside the miner's ID-only path.
    function _claimant(uint32 id) private view returns (address payee, uint32 walletId) {
        if (id == 0) {
            return (msg.sender, game.walletIdOf_g3120(msg.sender));
        }
        bool authorized;
        (, payee, authorized) = game.resolveAccount_g7029(id, msg.sender);
        if (!authorized) {
            uint32 buyer = game.acquiredBuyer(id);
            if (buyer == 0) revert Unauthorized();
        }
        walletId = id;
    }

    /// @dev Game backing plus, when `withCustody` (after game over), token custody: ETH and
    ///      admitted stETH. Capped to the packed batch value range.
    function _redemptionBacking(uint256 gameBacking, bool withCustody)
        private view returns (uint256 custody, uint256 gross)
    {
        gross = gameBacking;
        if (withCustody) {
            custody = address(this).balance;
            gross += custody;
            uint256 stethBalance = BoundedCall.stethBalanceOrZero(ContractAddresses.STETH_TOKEN, address(this));
            if (gross > type(uint96).max || stethBalance > type(uint96).max - gross) stethBalance = 0;
            custody += stethBalance;
            gross += stethBalance;
        }
        if (gross > type(uint96).max) gross = type(uint96).max;
    }

    /// @dev Admitted backing net of every outstanding redemption reserve, floored at 0. Token
    ///      custody counts only once claims can pay in it (after game over).
    function _liveMoney(bool withCustody) private view returns (uint256) {
        (, uint256 gross) = _redemptionBacking(_claimableWinnings(), withCustody);
        uint256 reserved = _pendingRedemptionEthValue;
        return gross > reserved ? gross - reserved : 0;
    }

    /// @dev Game backing is ordinary claimable minus its sentinel plus the protected reserve.
    /// @return claimable Total Game-held backing available to holders and reserved claims
    function _claimableWinnings() private view returns (uint256 claimable) {
        uint256 stored = game.claimableWinningsOf(address(this));
        return (stored > 1 ? stored - 1 : 0) + game.redemptionReserve();
    }

    /// @dev Convert Pool enum to array index
    /// @param pool Pool enum value
    /// @return Index into poolBalances array
    function _poolIndex(Pool pool) private pure returns (uint8) {
        return uint8(pool);
    }

    /// @dev Internal mint implementation
    /// @param to Recipient address
    /// @param amount Amount to mint
    function _mint(address to, uint256 amount) private {
        uint256 supplyAfter = uint256(_totalSupply) + amount;
        // Only genesis allocations and century refills mint. Genesis totals INITIAL_SUPPLY;
        // a refill adds at most 75% of (checkpoint - holder base), so supply stays <= checkpoint <= 1e24.
        // This inductive bound makes narrowing safe without an extra crank-halting cap check.
        _totalSupply = uint128(supplyAfter);
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
    /// @dev Open and settling batches occupy opposite parities; completed terms are reused.
    RedemptionBatch[2] private _redemptionBatches;

}
