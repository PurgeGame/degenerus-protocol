// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
import {GameTimeLib} from "./libraries/GameTimeLib.sol";
import {MineFlipGas} from "./libraries/MineFlipGas.sol";


/// @notice Interface for game contract player-facing functions used by sDGNRS.
interface IDegenerusGamePlayer {
    /// @notice Crank the unified miner router (advance + box opens), paying any earned bounty.
    function mineFlip() external;
    /// @notice Start or extend a daily afking subscription for `player` (self when 0/msg.sender).
    /// @dev The afking subscription surface is GAME-resident. sDGNRS self-subscribes
    ///      (player == address(this) == msg.sender) so the GAME's self-consent path passes
    ///      with no operator approval.
    function subscribe(
        address player,
        bool drainGameCreditFirst,
        bool useTickets,
        uint8 dailyQuantity,
        address fundingSource
    ) external payable;
    /// @notice Claim accumulated ETH winnings for a player.
    function claimWinnings(address player) external;
    /// @notice View claimable ETH winnings for a player.
    function claimableWinningsOf(address player) external view returns (uint256);
    /// @notice Current ordered RNG consumer stage (1 = redemption settlement).
    function rngConsumerStage() external view returns (uint8);
    /// @notice Check if game is over.
    function gameOver() external view returns (bool);
    /// @notice Check if `operator` is approved to act for `owner` (game operator approval).
    function isOperatorApproved(address owner, address operator) external view returns (bool);
    /// @notice Check if the liveness-timeout game-over trigger is active (fires before gameOver latches).
    function livenessTriggered() external view returns (bool);
    /// @notice Get player's activity score.
    function playerActivityScore(address player) external view returns (uint256);
    /// @notice Resolve a redemption lootbox (sDGNRS forwards ETH as msg.value; GAME pulls any stETH remainder).
    function resolveRedemptionLootbox(
        address player, uint256 amount, uint256 rngWord, uint16 activityScore, uint32 batchId
    ) external payable;
    /// @notice Credit a redemption's direct half to `player`'s game claimable (same ETH + stETH-remainder funding).
    function creditRedemptionDirect(address player, uint256 amount) external payable;
}

/// @notice Interface for Coinflip contract methods used by sDGNRS.
interface ICoinflipPlayer {
    /// @notice Claim coinflip winnings for a player.
    function claimCoinflips(address player, uint256 amount) external returns (uint256 claimed);
    /// @notice Preview claimable coinflip winnings for a player.
    function previewClaimCoinflips(address player) external view returns (uint256 mintable);
    /// @notice Settle-then-read sDGNRS's redeemable coinflip backing (seed claimable + carry, disjoint).
    function redeemableFlipBacking() external returns (uint256 backing);
    /// @notice Remove up to `base` whole FLIP of sDGNRS's backing at batch close (claimable → carry).
    function withdrawRedeemedFlip(uint256 base) external returns (uint256 removed);
    /// @notice Read a player's auto-rebuy config; `carry` is the rolling FLIP bankroll.
    function coinflipAutoRebuyInfo(address player) external view returns (bool enabled, uint256 stop, uint256 carry, uint24 startDay);
    /// @notice Credit a FLIP flip stake to a player (sDGNRS is an authorized flip creditor).
    function creditFlip(address player, uint256 amount) external;
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
 *      Creator allocation is minted to the DGNRS wrapper contract; all other holders receive
 *      sDGNRS directly from reward pools (soulbound — no transfer function).
 *
 * ARCHITECTURE:
 * - Receives ETH deposits from game distributions
 * - Receives stETH deposits from game distributions
 * - Accrues FLIP backing via manual transfers and coinflip claimables (withdrawn on burn)
 * - Pre-minted supply split into DGNRS wrapper allocation + reward pools
 * - Game distributes sDGNRS to players by drawing down pools
 * - Completed centuries recycle a random 25-75% of their supply burns into the four ongoing pools
 * - Users burn sDGNRS to claim proportional ETH + stETH + FLIP
 */
contract sDGNRS {
    // =====================================================================
    //                              ERRORS
    // =====================================================================

    /// @notice Thrown when caller is not authorized for the operation
    error Unauthorized();
    /// @notice The game-over trigger reads true but the game is not over yet: retry once it is.
    error EndingPending();

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

    /// @notice Thrown when a wallet's gambling burns on one wall day would exceed 160 ETH, valued
    ///         at the live price when each burn is made
    error ExceedsDailyRedemptionCap();

    /// @notice Thrown when a gambling burn amount is below the 1-whole-sDGNRS minimum (1e18 raw).
    error BurnTooSmall();


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
    /// @param flipAmount FLIP amount (always 0; FLIP arrives via manual transfers or coinflip claims)
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
    /// @param player The beneficiary of the redemption.
    /// @param sdgnrsAmount sDGNRS burned into the batch (left supply at the burn; priced at close).
    /// @param batchId The open batch the burn joined.
    event RedemptionSubmitted(address indexed player, uint256 sdgnrsAmount, uint32 indexed batchId);

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
    /// @param player The claimant.
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
        address indexed player, uint32 indexed batchId, uint16 roll, uint256 ethPayout, uint256 lootboxEth, uint256 flipPaid
    );

    /// @notice A live settlement refused by a dependency (e.g. stETH) left the batch with its word kept.
    event RedemptionParked(address indexed player, uint32 indexed batchId, bytes reason);

    // =====================================================================
    //                          ERC20 METADATA
    // =====================================================================

    /// @notice Token name
    string public constant name = "Degenerus Protocol Revenue and Governance Token";

    /// @notice Token symbol
    string public constant symbol = "sDGNRS";

    /// @notice Token decimals
    uint8 public constant decimals = 18;

    // =====================================================================
    //                          ERC20 STATE
    // =====================================================================

    /// @notice Total supply of sDGNRS tokens. A gambling burn leaves supply at the burn; until its
    ///         batch closes, prices and shares use `_totalSupply + _escrowedSupply` as the holder base.
    /// @dev Narrowed to uint128 (<= INITIAL_SUPPLY 1e30 << uint128 max 3.4e38; century refills
    ///      never exceed the previous post-refill supply) and co-located with the redemption reserve
    ///      and the open batch id so the compiler packs all three into slot 0 (128+96+32 = 256
    ///      bits). Each access is an independent masked SLOAD/SSTORE. The public `totalSupply()` /
    ///      `pendingRedemptionEthValue()` getters preserve the original ABI.
    uint128 private _totalSupply;

    /// @dev Total reserved redemption ETH value across closed batches and their unpaid claims: a
    ///      close adds the batch's MAX (175%) share, resolution lowers it to the rolled total,
    ///      each paid claim releases its rolled share and a finished batch releases its rounding
    ///      dust. Held in this contract's own ETH + stETH custody (the close tops custody up from
    ///      the Game claimable). uint96 holds 7.9e28 wei (~658x the total ETH supply) —
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
        PresaleBox
    }

    /// @notice Balances for each reward pool.
    /// @dev uint128 elements: the compiler packs the 5 lanes into 3 slots in index order
    ///      (Whale|Affiliate, Lootbox|Reward, PresaleBox), co-locating the warm whale/affiliate pair
    ///      debited together in a pass purchase. Each balance is <= INITIAL_SUPPLY (1e30) << uint128 max.
    uint128[5] private poolBalances;

    // =====================================================================
    //                   GAMBLING BURN STATE
    // =====================================================================

    // Live gambling burns join the open batch. The next live VRF request (daily or mid-day)
    // closes it at one price for every token in it; the miner settles it on the word that
    // request returns. The ending's request closes nothing: a batch still open at game over is
    // unwound at the game-over price. At most one batch is open and at most one is settling, so
    // the two player lists alternate by batch-id parity.

    /// @dev A beneficiary's stake in one batch: raw sDGNRS burned into it and the activity score
    ///      at the beneficiary's first burn in it, plus one (0 = no claim).
    struct PendingRedemption {
        uint128 tokens;
        uint16 activityScore;
    }

    /// @dev One redemption batch. Burns add `tokens` while it is open; `supplySnapshot` is the
    ///      holder base at its first burn (the 50% cap). The close fixes `ethBase` (the batch's base
    ///      ETH value at the close price, gwei-floored) and `flipEscrow` (whole FLIP removed from
    ///      backing). Resolution writes `roll` (21-175; 0 = unresolved) and `flipReward` (the
    ///      synthetic flip's reward percent; 0 = loss or none).
    struct RedemptionBatch {
        uint128 tokens;
        uint128 supplySnapshot;
        uint96 ethBase;
        uint96 flipEscrow;
        uint16 roll;
        uint16 flipReward;
    }

    /// @notice Per-beneficiary-per-batch redemption record, held from burn until its claim clears it.
    mapping(address => mapping(uint32 => PendingRedemption)) public pendingRedemptions;
    /// @notice Redemption batches by id.
    mapping(uint32 => RedemptionBatch) public redemptionBatches;

    /// @dev Raw sDGNRS burned into the open batch and not yet priced: already out of every balance
    ///      and `_totalSupply`. Every price or share uses `_totalSupply + _escrowedSupply` as the
    ///      holder base, so these tokens keep their share until their batch closes.
    uint128 private _escrowedSupply;
    /// @dev The closed batch the miner is settling (0 = none).
    uint32 private _settlingBatch;
    /// @dev Next index into the settling batch's player list.
    uint32 private _redemptionCursor;

    /// @dev A closed batch has unsettled claims: RNG consumer stage 1, which every later request
    ///      waits for. A batch only closes non-empty, so a settling id always has claims left.
    function redemptionSettlementPending() external view returns (bool) {
        return _settlingBatch != 0;
    }

    /// @notice Redemption batch pointers: the open batch, the settling batch (0 = none), the
    ///         settlement cursor into its player list, and the raw sDGNRS burned into the open
    ///         batch and not yet priced.
    function redemptionBatchState()
        external view returns (uint32 openBatch, uint32 settlingBatch, uint32 cursor, uint256 escrowedSupply)
    {
        return (_openBatch, _settlingBatch, _redemptionCursor, _escrowedSupply);
    }

    /// @notice Close the open batch inside the transaction that sends the next live VRF request.
    /// @dev Game only, daily and mid-day requests only (the ending's request closes nothing).
    ///      Never reverts: every bound is a min(), and the FLIP withdrawal clamps. One price for the
    ///      whole batch: (ETH + stETH + Game claimable − every outstanding reserve) × batch tokens ÷
    ///      the holder base (supply plus the batch's escrow). Earlier batches are settled before a
    ///      live close (every request waits for stage 1), so the reserves netted here are exact
    ///      rolled amounts of parked claims, never another batch's 175%. The batch's tokens left
    ///      supply at their burns; here they only leave the escrow count. The batch's MAX (175%)
    ///      payout is reserved, and `pull` is the part of the reserve that custody does not already
    ///      hold, capped at the Game claimable. A close while another batch still settles keeps the
    ///      batch open (unreachable: requests wait for settlement).
    /// @param gameClaimable sDGNRS's claimable balance on the Game (1 wei of it is dust).
    /// @return pull ETH value the Game moves from sDGNRS's claimable into this contract.
    function closeRedemptionBatch(uint256 gameClaimable) external onlyGame returns (uint256 pull) {
        uint32 id = _openBatch;
        RedemptionBatch storage batch = redemptionBatches[id];
        uint256 tokens = batch.tokens;
        if (tokens == 0 || _settlingBatch != 0) return 0;

        uint256 escrowed = _escrowedSupply;
        uint256 holderBase = _totalSupply + escrowed;
        uint256 claimable = gameClaimable > 1 ? gameClaimable - 1 : 0;
        uint256 custody = address(this).balance + steth.balanceOf(address(this));
        uint256 reserved = _pendingRedemptionEthValue;
        uint256 gross = custody + claimable;
        uint256 money = gross > reserved ? gross - reserved : 0;
        uint256 ethBase = ((money * tokens) / holderBase / 1e9) * 1e9;

        // FLIP: the batch's share of the settled backing leaves it now and pays only on the
        // batch's synthetic flip win. Sized from the same settled read, so the clamp never binds.
        uint256 flipEscrow = (coinflip.redeemableFlipBacking() * tokens) / holderBase;
        if (flipEscrow != 0) flipEscrow = coinflip.withdrawRedeemedFlip(flipEscrow);

        // The escrow is exactly the open batch's tokens, so this cannot underflow.
        unchecked {
            _escrowedSupply = uint128(escrowed - tokens);
        }

        reserved += (ethBase * MAX_ROLL) / 100;
        _pendingRedemptionEthValue = uint96(reserved);
        batch.ethBase = uint96(ethBase);
        batch.flipEscrow = uint96(flipEscrow);
        _settlingBatch = id;
        unchecked {
            _openBatch = id + 1;
        }

        // At most half the snapshot supply burns per batch, so 175% of the batch base stays
        // inside the backing; the cap at the claimable is a backstop, never a revert.
        if (reserved > custody) {
            pull = reserved - custody;
            if (pull > claimable) pull = claimable;
        }
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
        RedemptionBatch storage batch = redemptionBatches[id];
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
        uint256 maxReserve = (ethBase * MAX_ROLL) / 100;
        uint256 reserved = _pendingRedemptionEthValue;
        reserved = reserved > maxReserve ? reserved - maxReserve : 0;
        _pendingRedemptionEthValue = uint96(reserved + rolledTotal);
        batch.roll = roll;
        batch.flipReward = flipReward;
        emit RedemptionResolved(id, roll, flipReward);
    }

    /// @dev Roll in [MIN_ROLL, MAX_ROLL] = [21, 175], 155 values with mean exactly 98, from bits
    ///      above the word's lowest byte (bit 0 is the daily coinflip).
    function _rollFromWord(uint256 word) private pure returns (uint16) {
        return uint16(((word >> 8) % (MAX_ROLL - MIN_ROLL + 1)) + MIN_ROLL);
    }

    // Admission bounds cover the complete beneficiary: the claim and its direct/stETH funding,
    // plus its lootbox leg as one box order of at most REDEMPTION_BOXES_MAX boxes, bounded like
    // a human entry. These are safety floors, never work charges.
    uint256 private constant REDEMPTION_BASE_GAS = GasBounds.REDEMPTION_BASE_GAS;
    uint256 private constant REDEMPTION_TAIL_GAS = GasBounds.REDEMPTION_TAIL_GAS;
    /// @dev Resolution writes (reserve, roll, flip, batch reserve) before the first claim.
    uint256 private constant REDEMPTION_RESOLVE_GAS = 60_000;

    /// @notice Settle the settling batch on `word` (Game only, RNG consumer stage 1).
    /// @dev Stage 1 is part of the essential chain and no request can go out before it finishes,
    ///      so the published read word is always the one that answered the request that closed
    ///      the batch. No word is stored.
    function runRedemptionWork(uint256 word, uint256 allowance) external onlyGame returns (MineFlipGas.Result memory result) {
        return _runRedemptionWork(word, allowance);
    }

    function _runRedemptionWork(uint256 word, uint256 allowance) private returns (MineFlipGas.Result memory result) {
        if (allowance == 0) return result;
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        uint32 id = _settlingBatch;
        if (id == 0) { result.done = true; return result; }
        // Stage 1 is never selected under liveness or game over, so this also excludes both.
        if (game.rngConsumerStage() != 1) revert RedemptionStageBlocked();
        if (word <= 1) revert NotResolved();
        if (!MineFlipGas.canRun(meter, REDEMPTION_TAIL_GAS, 0)) return result;

        RedemptionBatch storage batch = redemptionBatches[id];
        uint256 reserveLeft;
        if (batch.roll == 0) {
            if (!MineFlipGas.canRun(meter, REDEMPTION_RESOLVE_GAS, REDEMPTION_TAIL_GAS)) return result;
            // One synthetic flip per batch, hashed under its own tag so it is independent of the
            // word's raw bit 0 (on a daily word that bit is the real coinflip day). Odds match a
            // coinflip day with no bonus; a win pays through creditFlip, whose stake then rides
            // the real flip.
            uint256 synth = uint256(keccak256(abi.encodePacked(SYNTH_FLIP_TAG, word, id)));
            uint16 flipReward = (synth & 1) == 1 ? FlipRoundLib.coinflipRewardPercent(0, synth, uint24(id)) : 0;
            reserveLeft = _resolveBatch(id, batch, _rollFromWord(word), flipReward);
            result.progressed = true;
        } else {
            reserveLeft = _settlingReserveLeft;
        }

        uint256 batchTokens = batch.tokens;
        uint256 ethBase = batch.ethBase;
        uint16 roll = batch.roll;
        address[] storage players = _batchPlayers[id & 1];
        uint256 total = players.length;
        uint256 cursor = _redemptionCursor;
        uint256 initialCursor = cursor;
        while (cursor < total) {
            address player = players[cursor];
            uint256 claimTokens = pendingRedemptions[player][id].tokens;
            if (claimTokens == 0) {
                if (!MineFlipGas.canRun(meter, 15_000, REDEMPTION_TAIL_GAS)) break;
                _redemptionCursor = uint32(++cursor);
                continue;
            }
            (uint256 rolled, , uint256 lootbox,) =
                _redemptionAmounts((ethBase * claimTokens) / batchTokens, roll, false);
            uint256 nextMax = REDEMPTION_BASE_GAS;
            if (lootbox != 0) {
                // The lootbox leg's box count, exactly as the Game builds the order.
                uint256 boxes = (lootbox - 1) / GasBounds.REDEMPTION_BOX_UNIT + 1;
                if (boxes > GasBounds.REDEMPTION_BOXES_MAX) boxes = GasBounds.REDEMPTION_BOXES_MAX;
                nextMax += GasBounds.HUMAN_ENTRY_GAS + boxes * GasBounds.HUMAN_BOX_GAS;
            }
            // The self-call keeps its whole bound after EIP-150 retention.
            if (!MineFlipGas.canRun(meter, nextMax + nextMax / 63 + MineFlipGas.CALL_RESERVE,
                REDEMPTION_TAIL_GAS)) break;
            ++cursor;
            // Commit the frontier before any nested calls.
            _redemptionCursor = uint32(cursor);
            // Paid or parked, the claim's rolled share leaves the batch's remaining reserve; a
            // parked claim keeps it in the global reserve until claimParkedRedemption pays it.
            reserveLeft -= rolled;
            // A refusing dependency must not hold every later RNG request: park the claim with
            // its session word and move on. Gas failures still revert the whole transaction.
            try this.settleRedemptionHead(player, id, word) {
            } catch (bytes memory reason) {
                MineFlipGas.rethrowGasFailure(reason);
                _parkedRedemptionWord[player][id] = word;
                emit RedemptionParked(player, id, reason);
            }
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
        address[] storage players = _batchPlayers[id & 1];
        assembly ("memory-safe") { sstore(players.slot, 0) }
    }

    /// @dev Self-call target of the miner drain, so a refused claim rolls back alone.
    function settleRedemptionHead(address player, uint32 batchId, uint256 word) external returns (bool) {
        if (msg.sender != address(this)) revert Unauthorized();
        return _claimRedemptionFor(player, batchId, false, word);
    }

    /// @notice Settle a parked claim on its batch's word. Player or approved operator only.
    /// @dev The word, roll and synthetic flip are fixed, but the lootbox half resolves at the
    ///      level live at claim time. Terminal claims take the usual direct terminal shape; the
    ///      word is then unused.
    function claimParkedRedemption(address player, uint32 batchId) external {
        uint256 word = _parkedRedemptionWord[player][batchId];
        if (word == 0) revert NoClaim();
        if (player != msg.sender && !game.isOperatorApproved(player, msg.sender)) revert Unauthorized();
        bool isTerminal = game.gameOver();
        if (!isTerminal && game.livenessTriggered()) revert EndingPending();
        delete _parkedRedemptionWord[player][batchId];
        if (!_claimRedemptionFor(player, batchId, isTerminal, word)) revert NoClaim();
    }

    /// @notice Holder base (supply plus the open batch's escrow) immediately after the last century
    ///         refill (initial supply before the first).
    /// @dev All intervening reductions of the holder base are burns; a live gambling burn counts
    ///      once its batch closes. Appended with the century/closure markers
    ///      in one slot, preserving the existing redemption layout and adding no per-burn writes.
    uint128 public centurySupplyCheckpoint;

    /// @notice Last completed century recycled, starting at 1 for the level-100 transition close.
    uint24 public lastRecycledCentury;

    /// @notice Permanently disables recycling once terminal pool destruction begins.
    bool public recyclingClosed;

    /// @dev The settling batch's rolled total not yet assigned to a paid or parked claim; between
    ///      settlement calls only. Packed beside the century markers.
    uint96 private _settlingReserveLeft;

    /// @dev Beneficiary lists of the open and the settling batch, by batch-id parity.
    address[][2] private _batchPlayers;

    /// @dev Per-wallet live-burn value on one wall day: (day << 128) | value (wei, live price).
    mapping(address => uint256) private _redemptionDayValue;

    /// @dev Session word of a parked live claim, nonzero until it settles.
    mapping(address => mapping(uint32 => uint256)) private _parkedRedemptionWord;

    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @dev Domain for the per-century refill percentage; the completed level keys each draw.
    bytes32 private constant CENTURY_REFILL_TAG = keccak256("sdgnrs.century.refill");

    /// @notice Initial supply (1 trillion tokens)
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev Basis points denominator (100%)
    uint16 private constant BPS_DENOM = 10_000;

    /// @dev Creator allocation (20%)
    uint16 private constant CREATOR_BPS = 2000;

    /// @dev Non-creator pool distribution (BPS of total supply).
    uint16 private constant WHALE_POOL_BPS = 1000;
    uint16 private constant AFFILIATE_POOL_BPS = 3000;
    uint16 private constant LOOTBOX_POOL_BPS = 2000;
    uint16 private constant REWARD_POOL_BPS = 1000;
    uint16 private constant PRESALE_BOX_POOL_BPS = 1000;

    /// @dev Maximum value a single wallet can burn into live redemptions per wall day, each burn
    ///      valued at the live price when it is made.
    uint256 private constant MAX_DAILY_REDEMPTION_EV = 160 ether;

    /// @dev Maximum redemption roll (percent). The resolve roll is in [21, 175]; at batch close the
    ///      MAX possible payout (base × MAX_ROLL / 100) is reserved and held in this contract's ETH +
    ///      stETH custody, topped up from claimableWinnings[SDGNRS], so no concurrent claimable drain
    ///      can under-fund a later claim. Resolution lowers the reserve from MAX to the rolled total
    ///      (accounting only — any over-pull stays as free backing).
    uint256 private constant MAX_ROLL = 175;

    /// @dev Minimum redemption roll (percent). [21, 175] has mean 98: the roll's low end carries a
    ///      2% redemption cost that stays as backing for remaining holders.
    uint256 private constant MIN_ROLL = 21;

    /// @dev Flat roll for a settling batch the ending resolves (terminal word or deterministic).
    uint16 private constant ENDING_ROLL = 100;

    /// @dev Minimum gambling-burn amount (1 whole sDGNRS = 1e18 raw).
    uint256 private constant MIN_BURN_AMOUNT = 1e18;

    /// @dev Domain for a batch's synthetic flip; batch id and word key each draw.
    bytes32 private constant SYNTH_FLIP_TAG = keccak256("sdgnrs.redemption.synthetic-flip");

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
    /// @dev Mints creator allocation to DGNRS wrapper address and pool allocations to this contract
    constructor() {
        uint256 creatorAmount = (INITIAL_SUPPLY * CREATOR_BPS) / BPS_DENOM;
        uint256 whaleAmount = (INITIAL_SUPPLY * WHALE_POOL_BPS) / BPS_DENOM;
        uint256 presaleBoxAmount = (INITIAL_SUPPLY * PRESALE_BOX_POOL_BPS) / BPS_DENOM;
        uint256 affiliateAmount = (INITIAL_SUPPLY * AFFILIATE_POOL_BPS) / BPS_DENOM;
        uint256 lootboxAmount = (INITIAL_SUPPLY * LOOTBOX_POOL_BPS) / BPS_DENOM;
        uint256 rewardAmount = (INITIAL_SUPPLY * REWARD_POOL_BPS) / BPS_DENOM;
        uint256 totalAllocated = creatorAmount + whaleAmount + presaleBoxAmount + affiliateAmount + lootboxAmount + rewardAmount;
        if (totalAllocated < INITIAL_SUPPLY) {
            uint256 dust;
            unchecked {
                dust = INITIAL_SUPPLY - totalAllocated;
            }
            lootboxAmount += dust;
        }
        uint256 poolTotal =
            whaleAmount + presaleBoxAmount + affiliateAmount + lootboxAmount + rewardAmount;

        _mint(ContractAddresses.DGNRS, creatorAmount);
        _mint(address(this), poolTotal);
        centurySupplyCheckpoint = _totalSupply;

        // Pool amounts are BPS slices of INITIAL_SUPPLY (1e30) << uint128 max — narrowing is safe.
        poolBalances[uint8(Pool.Whale)] = uint128(whaleAmount);
        poolBalances[uint8(Pool.Affiliate)] = uint128(affiliateAmount);
        poolBalances[uint8(Pool.Lootbox)] = uint128(lootboxAmount);
        poolBalances[uint8(Pool.Reward)] = uint128(rewardAmount);
        poolBalances[uint8(Pool.PresaleBox)] = uint128(presaleBoxAmount);

        // Protocol-owned self-subscription: claimable-first daily lootbox
        // buy of flat quantity 1. Self-consent —
        // sDGNRS IS the player (player == msg.sender). The afking module exempts the
        // pinned SDGNRS address from its seat-token and purchase gates, so this subscribe
        // lands before the seat token is deployed; the token's constructor then mints
        // sDGNRS its construction seat.
        // The afking surface is GAME-resident; self-subscribe directly against the
        // GAME (subscriber == msg.sender ⇒ the GAME's self-consent path, no operator
        // approval needed).
        // Coinflip auto-rebuy is NOT enabled here: during the 20-day seed window
        // sDGNRS's daily flip wins accumulate as unminted coinflip claimable backing
        // (sDGNRS never holds a FLIP wallet balance); Coinflip arms perpetual
        // auto-rebuy (0 take-profit) once the final seeded day settles, after which
        // wins roll into the carry.
        game.subscribe(address(this), true, false, 1, address(0));

        // Pre-approve GAME to pull stETH for both redemption claim legs. Live settlement funds
        // each leg (resolveRedemptionLootbox / creditRedemptionDirect) with msg.value ETH and the
        // GAME pulls any remainder via transferFrom whenever liquid ETH is short, so the claim
        // can't strand mid-game on an ETH-only forward.
        steth.approve(ContractAddresses.GAME, type(uint256).max);

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
    /// @dev Called by DGNRS contract when creator unwraps DGNRS to soulbound sDGNRS.
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
    function gameAdvance() external {
        game.mineFlip();
    }

    // =====================================================================
    //                          DEPOSITS (Game Only)
    // =====================================================================

    /// @notice Receive ETH deposit from the game contract.
    /// @dev GAME deposits reserve ETH and the afking-funding claim/withdraw send-back (the Game's
    ///      `.call` has msg.sender == GAME). Accounting-safe: reserves are read live via
    ///      address(this).balance everywhere, so no running counter is kept here.
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

    /// @notice Total supply of sDGNRS tokens (ERC20). ABI-preserving view over the packed slot-0 field.
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    /// @notice Total redemption ETH reserved in this contract's custody for closed batches and their
    ///         unpaid claims (wei).
    /// @dev ABI-preserving view over the packed slot-0 field (cross-contract + harness readers).
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
    function transferFromPool(Pool pool, address to, uint256 amount) external onlyGame returns (uint256 transferred) {
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
        uint256 burned = uint256(centurySupplyCheckpoint) - (uint256(_totalSupply) + _escrowedSupply);
        uint256 refillPercent = 25 + EntropyLib.hash2(rngWord, uint256(CENTURY_REFILL_TAG) ^ completedLevel) % 51;
        uint256 minted = burned * refillPercent / 100;
        uint256 whale = minted / 7;
        uint256 affiliate = (minted * 3) / 7;
        uint256 reward = whale;
        uint256 lootbox = minted - whale - affiliate - reward;

        if (minted != 0) {
            _mint(address(this), minted);
            // Every pool plus its credit is <= the new total supply, so each share
            // fits uint128. Checked additions preserve pool inventory; PresaleBox receives zero.
            poolBalances[uint8(Pool.Whale)] += uint128(whale);
            poolBalances[uint8(Pool.Affiliate)] += uint128(affiliate);
            poolBalances[uint8(Pool.Lootbox)] += uint128(lootbox);
            poolBalances[uint8(Pool.Reward)] += uint128(reward);
        }
        // Stamp even a zero mint. Post-mint holder base stays <= checkpoint: at least 25% stays burned.
        centurySupplyCheckpoint = uint128(uint256(_totalSupply) + _escrowedSupply);
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

    /// @notice Burn sDGNRS to claim proportional share of backing assets
    /// @dev Post-gameOver: deterministic payout. During game: the tokens burn now and join the open
    ///      redemption batch, which the next live VRF request closes and prices; the miner settles
    ///      it on that request's word. Returns (0,0,0) during game.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return flipOut FLIP received (deterministic path only)
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

    /// @notice Burn wrapped DGNRS (held in the DGNRS contract) to claim proportional backing assets
    /// @dev Burns the DGNRS wrapper tokens, then burns the corresponding sDGNRS backing held by the DGNRS contract.
    ///      Post-gameOver: deterministic payout. During game: joins the open redemption batch.
    /// @param amount Amount of sDGNRS-equivalent to burn (from DGNRS wrapper balance)
    /// @return ethOut ETH received (deterministic path only)
    /// @return stethOut stETH received (deterministic path only)
    /// @return flipOut FLIP received (deterministic path only)
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
        return (_liveMoney() * amount) / (uint256(_totalSupply) + _escrowedSupply);
    }

    /// @dev Pay `value` of game-over backing to `to`: ETH first, stETH for the rest. sDGNRS's game
    ///      claimable is pulled first when the ETH leg alone is short or paying from custody would
    ///      drop ETH + stETH below the redemption reserve, so custody keeps covering every later
    ///      claim. stETH goes first and the untrusted ETH call last; callers write state before.
    function _payGameOverValue(address to, uint256 value) private returns (uint256 ethOut, uint256 stethOut) {
        uint256 ethBal = address(this).balance;
        uint256 stethBal = steth.balanceOf(address(this));
        if ((value > ethBal || value + _pendingRedemptionEthValue > ethBal + stethBal) && _claimableWinnings() != 0) {
            game.claimWinnings(address(0));
            ethBal = address(this).balance;
            stethBal = steth.balanceOf(address(this));
        }

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

    /// @notice Claim a gambling-burn redemption for `player` in batch `batchId` once the game is over.
    /// @dev In a live game mineFlip settles every redemption in batch order, so this is the
    ///      post-gameover door only, and it deletes `pendingRedemptions[player][batchId]`. Only
    ///      `player` or an operator `player` approved on the GAME may call, since the payout is
    ///      pushed straight to `player` (ETH, with stETH covering any ETH shortfall) rather than
    ///      credited to the Game — a game-claimable credit would forfeit in the post-gameover sweep.
    ///      - A closed batch must carry a roll (resolved live, or at a flat 100 by the ending): the rolled amount pays 100% direct, with no lootbox leg
    ///        and no FLIP.
    ///      - The batch still open at game over never closed and has no price or roll: each claim
    ///        unwinds at the plain game-over value of its tokens — exactly what a game-over burn of
    ///        that many tokens pays, through the same payout path. No roll, lootbox or FLIP.
    /// @param player Claimant whose redemption to settle.
    /// @param batchId Batch whose claim to settle.
    function claimRedemption(address player, uint32 batchId) external {
        bool open = batchId == _openBatch;
        if (!open && redemptionBatches[batchId].roll == 0) revert NotResolved();
        // Only once the game is over, which is irreversible: while the game-over trigger reads true
        // before that, it can still read false again, and a terminal settlement taken then would stick.
        if (!game.gameOver()) revert NotGameOver();
        if (player != msg.sender && !game.isOperatorApproved(player, msg.sender)) revert Unauthorized();
        if (open) {
            _unwindOpenClaim(player, batchId);
            return;
        }
        if (!_claimRedemptionFor(player, batchId, true, 0)) revert NoClaim();
    }

    /// @dev Pay a claim in the batch still open at game over its tokens' game-over value. The
    ///      tokens left supply at the burn but stayed in the holder base through the escrow, so
    ///      the value matches a game-over burn of the same count; the escrow then drops by them.
    function _unwindOpenClaim(address player, uint32 batchId) private {
        uint256 tokens = pendingRedemptions[player][batchId].tokens;
        if (tokens == 0) revert NoClaim();
        uint256 value = _gameOverValue(tokens);
        // The escrow and the batch hold every open claim's tokens, so neither can underflow.
        unchecked {
            _escrowedSupply -= uint128(tokens);
            redemptionBatches[batchId].tokens -= uint128(tokens);
        }
        delete pendingRedemptions[player][batchId];
        emit RedemptionClaimed(player, batchId, 0, value, 0, 0);
        _payGameOverValue(player, value);
    }

    /// @dev The estimator and execution use identical rounding and dust treatment.
    function _redemptionAmounts(uint256 base, uint16 roll, bool terminal)
        private pure returns (uint256 rolled, uint256 direct, uint256 lootbox, uint256 forfeited)
    {
        rolled = base * roll / 100;
        if (terminal) return (rolled, rolled, 0, 0);
        direct = rolled / 2;
        lootbox = rolled - direct;
        if (lootbox < MIN_REDEMPTION_LOOTBOX_ETH) {
            forfeited = lootbox;
            lootbox = 0;
        }
    }

    /// @dev Shared settle core for the miner's batch settlement, parked claims and the post-game-over
    ///      claim. Callers must have verified the batch is resolved and (in terminal mode) that the
    ///      caller is `player` or an operator `player` approved on the Game; the pending-claim
    ///      existence check lives here, returning false on an empty (player, batch) slot.
    ///      The claim's share of the batch is pro rata by tokens: one close price for every token.
    function _claimRedemptionFor(address player, uint32 batchId, bool isTerminal, uint256 word)
        private returns (bool)
    {
        PendingRedemption memory claim = pendingRedemptions[player][batchId];
        if (claim.tokens == 0) return false;
        RedemptionBatch memory batch = redemptionBatches[batchId];

        (uint256 totalRolledEth, uint256 ethDirect, uint256 lootboxEth, uint256 forfeitEth) =
            _redemptionAmounts((uint256(batch.ethBase) * claim.tokens) / batch.tokens, batch.roll, isTerminal);

        // Release the rolled share from the reserve (both direct and lootbox portions leave
        // sDGNRS). The MAX − rolled over-pull stays in this contract as free backing. Checked:
        // resolution left at least the batch's rolled total, which bounds every claim's share.
        _pendingRedemptionEthValue = uint96(_pendingRedemptionEthValue - totalRolledEth);

        // Full claim: clear the (player, batch) slot entirely.
        delete pendingRedemptions[player][batchId];

        // Contingent FLIP escrow: the claim's share of the whole-FLIP slice removed from sDGNRS's
        // backing at close. The batch's synthetic flip is the first of two flips: a win pays the
        // principal PLUS that flip's multiplier as a flip credit, which then rides the real
        // coinflip (the second flip). A loss pays nothing (symmetric with the auto-rebuy carry
        // zeroing for every holder on a losing flip). In terminal mode FLIP is worthless and
        // skipped entirely. The slot is already cleared (CEI) and creditFlip makes no callback
        // into this contract.
        uint256 flipPaid;
        if (!isTerminal && batch.flipReward != 0) {
            uint256 principal = (uint256(batch.flipEscrow) * claim.tokens) / batch.tokens;
            if (principal != 0) {
                flipPaid = principal + (principal * uint256(batch.flipReward)) / 100;
                coinflip.creditFlip(player, flipPaid);
            }
        }

        emit RedemptionClaimed(player, batchId, batch.roll, ethDirect, lootboxEth, flipPaid);

        if (isTerminal) {
            // 100% direct push (player/operator restriction enforced by callers; the untrusted .call comes after
            // the slot delete above — CEI).
            _payEth(player, ethDirect);
            return true;
        }

        // Live game: both legs move to the Game. Each leg mixes ETH and stETH like _payEth —
        // msg.value carries the ETH on hand, the GAME pulls any remainder as stETH — so a
        // mid-game ETH-depleted contract can't strand the claim on an ETH-only forward. The MAX
        // reservation guarantees ETH + stETH >= rolled, so the stETH remainder is always coverable.
        if (lootboxEth != 0) {
            uint16 actScore = claim.activityScore > 0 ? claim.activityScore - 1 : 0;
            // Burns commit before the word that settles their batch exists: the batch closes
            // with the request that word answers. Live callers pass that word (the miner's
            // session word, or the word kept with a parked claim).
            if (word <= 1) revert NotResolved();
            uint256 entropy = EntropyLib.hash2(word, uint256(uint160(player)));
            uint256 bal = address(this).balance;
            uint256 ethForLootbox = bal < lootboxEth ? bal : lootboxEth;
            game.resolveRedemptionLootbox{value: ethForLootbox}(player, lootboxEth, entropy, actScore, batchId);
        }

        // Direct half: credit into the player's game claimable (a permissionless trigger must
        // not push ETH at the player); the player withdraws via the access-gated claimWinnings.
        if (ethDirect != 0) {
            uint256 bal = address(this).balance;
            uint256 ethForDirect = bal < ethDirect ? bal : ethDirect;
            game.creditRedemptionDirect{value: ethForDirect}(player, ethDirect);
        }

        // Forfeited dust-lootbox half → sDGNRS's OWN claimable on the Game (player == address(this)),
        // using the same ETH/stETH funding mix as the direct leg. With this leg the full rolled amount
        // leaves the contract (direct half to the player, forfeited half to sDGNRS), so it reconciles
        // exactly with the pendingRedemptionEthValue release — no ETH is stranded in the contract.
        if (forfeitEth != 0) {
            uint256 bal = address(this).balance;
            uint256 ethForForfeit = bal < forfeitEth ? bal : forfeitEth;
            game.creditRedemptionDirect{value: ethForForfeit}(address(this), forfeitEth);
        }
        return true;
    }

    // =====================================================================
    //                          VIEW FUNCTIONS
    // =====================================================================

    /// @notice Preview the value and FLIP output for burning sDGNRS
    /// @dev The live price: the proportional share of ETH + stETH + claimable, net of
    ///      pendingRedemptionEthValue (owed to closed batches), over the holder base (supply plus
    ///      the open batch's escrow). A live burn is priced when its batch closes, so this is an
    ///      estimate of that price; the per-wallet daily cap uses the same figure. After game over
    ///      it is exactly the deterministic burn's value. The value is paid as ETH, stETH, or a mix
    ///      chosen at pay time — the two are at par protocol-wide, so it is reported as one
    ///      wei-denominated figure. GameOver burns pay no FLIP.
    /// @param amount Amount of sDGNRS to burn
    /// @return ethOut Total value that would be received, in wei (paid as ETH and/or stETH)
    /// @return flipOut FLIP that would be received (0 during gameOver)
    function previewBurnValue(uint256 amount) external view returns (uint256 ethOut, uint256 flipOut) {
        uint256 supply = uint256(_totalSupply) + _escrowedSupply;
        if (amount == 0 || amount > supply) return (0, 0);

        ethOut = (_liveMoney() * amount) / supply;

        // GameOver burns pay no FLIP. sDGNRS's full FLIP backing is its seed-reserve claimable +
        // the auto-rebuy carry (incoming FLIP rides tomorrow's stake and settles into these);
        // it holds no wallet balance.
        // No reserve term: a batch close removes its escrowed slice from this backing, so these
        // live reads are already net of closed batches. Best-effort (the carry/claimable can
        // momentarily lag a stalled advance or an in-flight stake).
        if (!game.gameOver()) {
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
    ///      in the batch at once. Caps: the batch holds at most half the holder base at its first
    ///      burn; a wallet burns at most 160 ETH per wall day at the live price.
    function _submitGamblingClaimFrom(address beneficiary, address burnFrom, uint256 amount) private {
        uint256 bal = balanceOf[burnFrom];
        if (amount == 0 || amount > bal) revert Insufficient();
        if (amount < MIN_BURN_AMOUNT) revert BurnTooSmall();

        uint32 id = _openBatch;
        RedemptionBatch storage batch = redemptionBatches[id];
        uint256 supply = _totalSupply;
        uint256 escrowed = _escrowedSupply;
        uint256 holderBase = supply + escrowed;
        uint256 tokens = batch.tokens;
        uint256 snapshot = tokens == 0 ? holderBase : batch.supplySnapshot;
        if (tokens + amount > snapshot / 2) revert Insufficient();

        // Valued at the live price; the close never re-checks (it cannot revert).
        uint256 day = GameTimeLib.currentDayIndex();
        uint256 dayValue = _redemptionDayValue[beneficiary];
        uint256 spent = ((dayValue >> 128) == day ? uint128(dayValue) : 0) + (_liveMoney() * amount) / holderBase;
        if (spent > MAX_DAILY_REDEMPTION_EV) revert ExceedsDailyRedemptionCap();
        _redemptionDayValue[beneficiary] = (day << 128) | spent;

        // Burned now; the escrow count keeps the tokens in the holder base until the close.
        unchecked {
            balanceOf[burnFrom] = bal - amount;
            _totalSupply = uint128(supply - amount);
        }
        _escrowedSupply = uint128(escrowed + amount);
        if (tokens == 0) batch.supplySnapshot = uint128(holderBase);
        batch.tokens = uint128(tokens + amount);
        emit Transfer(burnFrom, address(0), amount);

        PendingRedemption storage claim = pendingRedemptions[beneficiary][id];
        if (claim.activityScore == 0) {
            _batchPlayers[id & 1].push(beneficiary);
            // Snapshot on the first burn in the batch (stored as score + 1; 0 = no claim).
            claim.activityScore = uint16(game.playerActivityScore(beneficiary)) + 1;
        }
        claim.tokens += uint128(amount);

        emit RedemptionSubmitted(beneficiary, amount, id);
    }

    /// @dev ETH + stETH + Game claimable net of every outstanding redemption reserve, floored at 0.
    function _liveMoney() private view returns (uint256) {
        uint256 gross = address(this).balance + steth.balanceOf(address(this)) + _claimableWinnings();
        uint256 reserved = _pendingRedemptionEthValue;
        return gross > reserved ? gross - reserved : 0;
    }

    /// @dev Pay the redemption from this contract's balance: ETH first, falling back to stETH if the
    ///      ETH balance is insufficient. No game.claimWinnings pull — the batch close topped this
    ///      contract's ETH + stETH custody up to every outstanding reserve, so the backing is
    ///      already in this contract's balance.
    function _payEth(address player, uint256 amount) private {
        if (amount == 0) return;
        uint256 ethBal = address(this).balance;

        if (amount <= ethBal) {
            (bool success, ) = player.call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            uint256 ethOut = ethBal;
            uint256 stethOut = amount - ethOut;
            // stETH first, untrusted ETH .call LAST (CEI): otherwise a reentrant burn()/claim in the
            // player's ETH hook sees the in-flight stETH (no longer reserved — claimRedemption already
            // decremented pendingRedemptionEthValue) as free backing and over-reserves, breaking solvency.
            if (!steth.transfer(player, stethOut)) revert TransferFailed();
            if (ethOut > 0) {
                (bool success, ) = player.call{value: ethOut}("");
                if (!success) revert TransferFailed();
            }
        }
    }

    /// @dev Get claimable game winnings, accounting for dust (returns 0 if stored <= 1)
    /// @return claimable Claimable winnings minus 1 wei dust
    function _claimableWinnings() private view returns (uint256 claimable) {
        uint256 stored = game.claimableWinningsOf(address(this));
        if (stored <= 1) return 0;
        return stored - 1;
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
        if (to == address(0)) revert ZeroAddress();
        uint256 supplyAfter = uint256(_totalSupply) + amount;
        // Only genesis allocations and century refills mint. Genesis totals INITIAL_SUPPLY;
        // a refill adds at most 75% of (checkpoint - holder base), so supply stays <= checkpoint <= 1e30.
        // This inductive bound makes narrowing safe without an extra crank-halting cap check.
        _totalSupply = uint128(supplyAfter);
        balanceOf[to] += amount;
        emit Transfer(address(0), to, amount);
    }
}
