// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

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

import {MineFlipGas} from "../libraries/MineFlipGas.sol";

import {IDegenerusGame, MintPaymentKind} from "../interfaces/IDegenerusGame.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {DegenerusGameRngUtils} from "./DegenerusGameRngUtils.sol";
import {IDegenerusGameTicketModule} from "../interfaces/IDegenerusGameModules.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {
    IVRFCoordinator,
    VRFRandomWordsRequest
} from "../interfaces/IVRFCoordinator.sol";

/// @dev Minimal stETH interface (ERC20 subset)
interface IStETH {
    /// @notice stETH balance of an account.
    /// @param account Address to query balance of.
    function balanceOf(address account) external view returns (uint256);
    /// @notice Transfer stETH to a recipient.
    /// @param to Recipient address.
    /// @param amount Transfer amount in wei.
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @dev Admin interface for VRF shutdown during final sweep.
interface IDegenerusAdminShutdown {
    /// @notice Cancel the VRF subscription and sweep LINK to the vault (DegenerusAdmin,
    ///         game-over only).
    function shutdownVrf() external;
}

/// @dev GNRUS interface for gameover GNRUS cleanup.
interface IGNRUSGameOver {
    /// @notice Burn GNRUS's remaining unallocated balance at game over (GNRUS, one-shot).
    function burnAtGameOver() external;
    /// @notice Record the final-sweep timestamp on GNRUS, anchoring its post-sweep recovery gates.
    function onFinalSweep() external;
}

/// @dev FLIP interface for the gameover worthless-token tombstone flood.
interface IFlipTombstone {
    /// @notice Flood FLIP's vault mint allowance with the one-shot worthless-token
    ///         tombstone signal.
    function tombstoneAtGameOver() external;
}

/**
 * @title DegenerusGameGameOverModule
 * @notice Handles game over logic including jackpot distribution and final sweeps.
 * @dev Executed via delegatecall from DegenerusGame. Inherits storage layout.
 */
contract DegenerusGameGameOverModule is DegenerusGameRngUtils {
    uint8 private constant STAGE_GAMEOVER = 0;
    uint8 private constant STAGE_TICKETS_WORKING = 5;

    /// @notice stETH token contract for liquid staking rewards
    IStETH private constant steth = IStETH(ContractAddresses.STETH_TOKEN);

    /// @notice Admin contract for VRF shutdown
    IDegenerusAdminShutdown private constant admin =
        IDegenerusAdminShutdown(ContractAddresses.ADMIN);

    /// @notice GNRUS contract for gameover cleanup
    IGNRUSGameOver private constant charityGameOver =
        IGNRUSGameOver(ContractAddresses.GNRUS);

    /// @notice FLIP coin contract for the gameover worthless-token tombstone flood
    IFlipTombstone private constant flip =
        IFlipTombstone(ContractAddresses.COIN);

    /// @notice Refund cap per deity pass for early game over (levels 0-9)
    uint256 private constant DEITY_PASS_EARLY_GAMEOVER_REFUND =
        20 ether;

    /// @dev VRF request parameters (mirror the advance module's daily/mid-day lanes).
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;

    /// @notice Emitted when the VRF coordinator is wired or rotated.
    /// @param previous Coordinator address before this update (zero on the initial wiring).
    /// @param current Coordinator address now in effect.
    event VrfCoordinatorUpdated(
        address indexed previous,
        address indexed current
    );

    /// @dev Deity-pass early-gameover refunds, as one aggregate. `totalRefunded` bounds
    ///      the refund credits exactly, without a separate refund event per holder.
    event DeityPassRefundsSettled(uint256 totalRefunded);

    /// @notice The terminal level's leading affiliate received its one-time ETH share.
    event TerminalAffiliatePaid(address indexed affiliate, uint24 indexed level, uint256 amount);

    /// @notice The deterministic (VRF-dead) ending fixed its payout: `pot` is shared by every
    ///         ticket of `level`. Uncreated entries (queued or in an undrained foil pack, whose
    ///         traits were never rolled) take pot * weight / total each, weight in QTY_SCALE
    ///         units. Created tickets share pot * created * QTY_SCALE / total, split equally
    ///         across the `traits` non-empty trait buckets and equally within each.
    event DeadVrfPayoutFixed(
        uint24 indexed level,
        uint256 pot,
        uint256 created,
        uint256 uncreated,
        uint256 traits
    );

    /// @notice A deterministic-ending claim credited `amount` to `player`'s claimable winnings.
    event DeadVrfClaimed(address indexed player, uint256 amount);

    // error E() — inherited from DegenerusGameStorage

    /// @dev claimDeadVrf reference kinds, in the top byte of each reference.
    uint256 private constant DEAD_REF_CREATED = 0;
    uint256 private constant DEAD_REF_QUEUED = 1;

    /// @dev Handles the game-over trigger and post-game sweep. Returns (shouldReturn, stage, unlock);
    ///      unlock is true only after normal payout. shouldReturn asks Advance to emit `stage` and exit.
    ///      Stages used:
    ///         STAGE_GAMEOVER -- a step of the ending, the payout, or the final sweep
    ///         STAGE_TICKETS_WORKING -- a drain or tally batch; the caller retries
    ///
    ///      Two endings:
    ///      - Deterministic, when VRF is dead (_vrfDead: a request unanswered for
    ///        _VRF_DEAD_TIMEOUT). Latched on first entry and never undone. No entropy at all:
    ///        tallyDeadVrf counts the terminal level's tickets over as many calls as it needs,
    ///        then handleGameOverDrain fixes the pot they share (claimDeadVrf).
    ///      - Normal, for the purchase deadline or the deadman with VRF alive. The terminal word
    ///        is one this path requests itself after liveness froze purchases, and every
    ///        cohort at the terminal level draws on it. There is no retry here: if that
    ///        request goes unanswered for _VRF_DEAD_TIMEOUT the dead ending takes over.
    function handleGameOverAdvance(uint24 day, uint24 lvl) external returns (bool, uint8, bool) {
        return _runGameOverAdvance(day, lvl, MineFlipGas.available());
    }

    function runGameOverAdvance(uint24 day, uint24 lvl, uint256 allowance) external returns (bool, uint8, bool) {
        return _runGameOverAdvance(day, lvl, allowance);
    }

    function _runGameOverAdvance(uint24 day, uint24 lvl, uint256 allowance)
        private returns (bool shouldReturn, uint8 stage, bool unlock)
    {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        (shouldReturn, stage, unlock) = _handleGameOverAdvance(day, lvl, meter);
        MineFlipGas.finish(meter);
    }

    function _handleGameOverAdvance(uint24 day, uint24 lvl, MineFlipGas.Meter memory meter)
        private returns (bool shouldReturn, uint8 stage, bool unlock)
    {
        if (gameOver) {
            if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) == 0) {
                bool done = _handleGameOverDrain(day, meter);
                return (true, STAGE_GAMEOVER, done);
            }
            if (MineFlipGas.canRun(meter, GasBounds.TERMINAL_FINAL_SWEEP, GasBounds.TERMINAL_SWEEP_TAIL)) handleFinalSweep();
            return (true, STAGE_GAMEOVER, false);
        }

        if (!_livenessTriggered()) return (false, 0, false);

        bool dead = _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0 || _vrfDead();

        // A met pool target rescues a level from the deadline ending, but only before that
        // ending has started (the drain-level latch below makes it irreversible), and never
        // from the deadman or a dead VRF.
        if (
            !dead && lvl != 0 && _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0
                && _getNextPrizePool() > _prizePoolTarget(lvl + 1) && !_vrfDeadmanFired()
        ) {
            return (false, 0, false);
        }

        // Record which bucket the ending pays from before anything below can take the RNG
        // lock: the unlatched _gameOverTicketLevel reads the lock as "the last-purchase request
        // already promoted level", so the bucket would move between transactions. The
        // terminal affiliate is fixed with it, before any terminal word exists: a claim landing
        // between the word and the payout could otherwise turn an empty leaderboard into a
        // ranked one and move the pool the terminal draw is fed. (The dead ending pays no
        // affiliate; the latch is harmless there.)
        uint24 drainLevel = _gameOverTicketLevel(lvl);
        if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0) {
            _lrWrite(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK, drainLevel == lvl ? 1 : 2);
            _setRngTerminal();
            rngRequestDay = 0;
            // Completed quadrants already balanced their source and liabilities.
            // Retire only the unpaid normal-day continuation; its remaining funds
            // join the terminal pot. No paid award is repeated or clawed back.
            delete jackpotWork;
            dailyTicketBudgetsPacked = 0;
            dailyJackpotCoinTicketsPending = false;
            earlyBirdWhalePasses = 0;
            (address top, ) = affiliate.affiliateTop(drainLevel);
            terminalAffiliate = top;
        }

        // --- Deterministic ending ---
        if (dead) {
            if (_lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) == 0) {
                _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
                // Revoke callback authority and discard late entropy, retaining metadata.
                // The dead latch and unpublished session keep the terminal fallback reachable.
                _setRngRequestActive(false);
                _setRngSessionPublished(false);
                rngWordCurrent = RNG_WORD_WAITING;
            }
            if (!_tallyDeadVrf(drainLevel, meter)) return (true, STAGE_TICKETS_WORKING, false);
            _handleGameOverDrain(day, meter);
            return (true, STAGE_GAMEOVER, false);
        }

        // --- Normal ending ---
        // The terminal word is always this path's own request, sent after liveness froze entry;
        // LR_GO_SWAP latches when it goes out. A daily request from before that (the deadman
        // cutting off a day stuck in processing, or a backlog) never supplies it: its word, once
        // delivered, only finalizes the lootbox index its request reserved, so the cohort that
        // request committed still drains on a word requested after it; then the request is
        // dropped together with the day it was processing, whose jackpot never pays (its funds
        // stay in the terminal pot). Until delivered it is waited out like any request in flight.
        if (_rngRequestActive() && _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0) {
            uint256 preFreeze = _currentRngWord();
            if (preFreeze == 0) return (true, STAGE_GAMEOVER, false);
            _finalizeLootboxRng(preFreeze);
            if (rngLockedFlag) _clearAppliedNudges();
            _setRngRequestActive(false);
            rngLockedFlag = false;
            return (true, STAGE_GAMEOVER, false);
        }

        // Terminal scope: the payout samples only lvlTraitEntry[drainLevel], so every probe here
        // is drainLevel-only; every other windowed cohort is dead value and is never touched.
        if (!_terminalWordApplied()) {
            if (!_rngRequestActive() || rngWordCurrent == RNG_WORD_WAITING) {
                // No terminal word yet. Wait out a request in flight: a mid-day lootbox request,
                // or this path's own terminal request.
                if (_rngRequestActive()) return (true, STAGE_GAMEOVER, false);
                if (_ticketQueueLength(_tqReadKey(drainLevel)) != 0 || _foilDrainPending()) {
                    // Before the ending's own swap, the read side is a cohort an earlier request
                    // committed (a mid-day swap, or a dropped pre-freeze daily request) and its
                    // word has landed: drain it on that word first, so the write cohort can be
                    // swapped in behind it before the terminal request. After the swap the read
                    // side is the ending's own cohort, and it drains only on the terminal word:
                    // the last delivered word predates it. Without its word the cohort waits for
                    // the terminal one instead (no swap then; it keeps the read side).
                    if (
                        _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0
                            && _lootboxWord(_rngReadBuffer()) != 0
                            && _terminalDrainBatch(drainLevel, meter)
                    ) return (true, STAGE_TICKETS_WORKING, false);
                }
                if (!MineFlipGas.canRun(meter, GasBounds.RNG_REQUEST + 100_000, GasBounds.TERMINAL_TAIL)) {
                    return (true, STAGE_GAMEOVER, false);
                }
                if (
                    (_ticketQueueLength(_tqWriteKey(drainLevel)) != 0 || foilQueue[_foilWriteKey()].length != 0)
                        && _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0
                ) {
                    // ONE terminal swap, ever, and always before the terminal request: every
                    // entry at drainLevel then predates the terminal word. Without the bound a
                    // queue created after the word went public could still be drawn.
                    _swapTicketSlot();
                }
                // The swap window closes as the terminal request goes out (sent below, or
                // retried by later calls if the coordinator refuses it).
                _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
            }
            // Request the terminal word, or apply it once it has landed. Either way this
            // transaction ends here, so the word's application (which may derive up to a
            // deadman's worth of skipped days) never shares a transaction with a drain batch.
            _applyTerminalRng(uint48(block.timestamp), day, lvl, meter);
            return (true, STAGE_GAMEOVER, false);
        }

        // Terminal word recorded: drain the committed cohort and the foil tail on it, one batch
        // per transaction. A finishing batch still returns, so the payout runs in its own.
        if (
            (_ticketQueueLength(_tqReadKey(drainLevel)) != 0 || _foilDrainPending())
                && _terminalDrainBatch(drainLevel, meter)
        ) {
            return (true, STAGE_TICKETS_WORKING, false);
        }

        bool payoutDone = _handleGameOverDrain(day, meter);
        return (true, STAGE_GAMEOVER, payoutDone);
    }


    /// @notice Request the ending's entropy without consulting any read consumer.
    /// @dev Only the terminal path delegates here, after fixing its payout level and swap.
    ///      The caller arms a one-shot refusal timer; coordinator failure leaves it unchanged.
    function requestTerminalRng() public returns (bool requested) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        requested = _requestTerminalRng(_simulatedDayIndex(), meter);
        MineFlipGas.finish(meter);
    }

    function _requestTerminalRng(uint24 day, MineFlipGas.Meter memory meter) private returns (bool requested) {
        if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0 || _rngRequestActive()) revert E();
        if (!MineFlipGas.canRun(meter, GasBounds.RNG_REQUEST, GasBounds.TERMINAL_TAIL)) return false;
        if (rngRequestDay == 0) {
            rngRequestDay = day > dailyIdx ? day : dailyIdx + 1;
            rngRequestTime = uint48(block.timestamp) & ~uint48(1);
            _setRngSessionPublished(false);
            rngWordCurrent = RNG_WORD_WAITING;
        }
        // The admitted bound covers coordinator gas, EIP-150 and all request
        // bookkeeping. Gas failures are never interpreted as a semantic refusal.
        try vrfCoordinator.requestRandomWords{gas: GasBounds.RNG_REQUEST - 300_000}(VRFRandomWordsRequest({
            keyHash: vrfKeyHash, subId: vrfSubscriptionId,
            requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
            callbackGasLimit: VRF_CALLBACK_GAS_LIMIT, numWords: 1, extraArgs: hex""
        })) returns (uint256 id) {
            lootboxRngPacked &= ~((LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
                | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
            _swapRngBuffers();
            vrfRequestId = id;
            _setRngRequestActive(true);
            _setRngSessionPublished(false);
            rngWordCurrent = RNG_WORD_WAITING;
            // A refusal retry retains the first admitted attempt's identity and
            // timeout. Coordinator acceptance does not restart that deadline.
            rngLockedFlag = true;
            _setDecDayOneActive(false);
            if (jackpotPhaseFlag && _isFinalJackpotDay(jackpotCounter, jackpotFlags)) _setTicketRedemptionOpen(false);
            requested = true;
        } catch (bytes memory reason) {
            MineFlipGas.rethrowGasFailure(reason);
        }
    }

    function _terminalWordApplied() private view returns (bool) {
        return rngRequestDay != 0 && _rngRequestActive() && _rngSessionPublished()
            && _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) != 0;
    }

    /// @notice Compatibility entry; native terminal work supplies its remaining meter.
    function applyTerminalRng(uint48 ts, uint24 day, uint24 lvl) public {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        _applyTerminalRng(ts, day, lvl, meter);
        MineFlipGas.finish(meter);
    }

    function _applyTerminalRng(uint48, uint24 day, uint24 lvl, MineFlipGas.Meter memory meter) private {
        if (_terminalWordApplied()) return;
        uint256 currentWord = _currentRngWord();
        if (_rngRequestActive() && currentWord != 0) {
            if (!MineFlipGas.canRun(meter, GasBounds.DAILY_GAP + GasBounds.DAILY_APPLY, GasBounds.TERMINAL_TAIL)) return;
            day = rngRequestDay;
            uint24 first = dailyIdx + 1;
            (uint16 firstResult,) = coinflip.getCoinflipDayResult(first);
            if (firstResult != 0) ++first;
            if (day > first) _backfillGapDays(_rawDailyRngWord(currentWord), first, day);
            currentWord = _applyDailyRng(day, currentWord);
            if (lvl != 0) coinflip.processCoinflipPayouts(0, currentWord, day);
            _resolvePendingRedemption(currentWord);
            _finalizeLootboxRng(currentWord);
            return;
        }
        if (!_rngRequestActive()) _requestTerminalRng(day, meter);
    }

    /// @dev One terminal drain batch: TICKET_SLOT_BIT on the anchor asks the worker for its
    ///      single-key terminal mode, draining exactly drainLevel's read side plus the foil
    ///      tail — every queued ticket at any other level is worthless at game over.
    ///      FUND-RELEASE FALLBACK: a worker revert that carries an error of its own (an
    ///      unforeseen error in ticket processing) is swallowed and reported as no batch, so the
    ///      ending moves on: undrained tickets forfeit trait-bucket eligibility, but terminal fund
    ///      release is never blocked.
    ///      A failure that carries NO error of its own (empty return data, or EmptyRevert from a
    ///      nested module call) is re-raised instead, before the ending's swap and after it. A
    ///      batch is gas-bounded well under the per-transaction cap, so that is a caller
    ///      withholding gas. Before the swap, swallowing it would close the one swap window with
    ///      the write cohort left out. After it, the payout the call falls through to is cheap
    ///      when no winning bucket is populated yet — a starved call could afford it and forfeit
    ///      the whole undrained cohort.
    /// @return ran True if a batch ran, finished or not.
    function _terminalDrainBatch(uint24 drainLevel, MineFlipGas.Meter memory meter) private returns (bool ran) {
        uint256 allowance = MineFlipGas.forwardable(MineFlipGas.remaining(meter), 100_000);
        if (allowance == 0) return true;
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameTicketModule.runTicketWork.selector,
                drainLevel | TICKET_SLOT_BIT, allowance)
        );
        if (!ok) {
            MineFlipGas.rethrowGasFailure(data);
            if (data.length == 4 && bytes4(data) == EmptyRevert.selector) {
                assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
            }
            return false;
        }
        // A successful no-progress checkpoint still owns this transaction: low
        // supplied gas must not turn unprocessed entries into forfeited entries.
        abi.decode(data, (MineFlipGas.Result));
        return true;
    }

    /// @notice Process game over by distributing remaining funds.
    /// @dev Called when the game-over trigger fires: the purchase deadline (365 days at level
    ///      0, 30 after), the 30-day no-seal deadman, or a VRF request unanswered for 14 days.
    ///      Sets terminal gameOver flag.
    ///
    ///      Distribution logic:
    ///      - If game ended early (levels 0-9): refund of the price paid (capped at 20 ETH) per deity pass,
    ///        FIFO by purchase order, budget-capped to available funds minus claimablePool
    ///      - Normal ending: 2% to the terminal level's top affiliate, 98% to its ticket cohort by
    ///        the terminal jackpot (all of it when no affiliate is ranked)
    ///      - Deterministic (VRF-dead) ending: no affiliate share and no draw; the remainder is
    ///        fixed as the pot every terminal-level ticket claims from (claimDeadVrf)
    ///      - Any uncredited remainder later swept by handleFinalSweep three-way to vault / sDGNRS / GNRUS
    ///
    ///      The normal ending reads _recordedDailyWord(day) and reverts if funds exist but the word
    ///      is not yet available. The deterministic ending reads no word.
    /// @param day Day index for RNG word lookup from rngWordByDay mapping.
    /// @custom:reverts Invariant When distributable funds exist but the RNG word is unavailable (defense-in-depth).
    /// @custom:reverts TransferFailed When an stETH or ETH transfer fails.
    function handleGameOverDrain(uint24 day) public virtual {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        _handleGameOverDrain(day, meter);
        MineFlipGas.finish(meter);
    }

    function _handleGameOverDrain(uint24 day, MineFlipGas.Meter memory meter) private returns (bool done) {
        if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) != 0) return true;
        if (gameOver) return _resumeTerminalPayout(day, meter);
        // At most 32 deity refunds, terminal burns and accounting, with no draw
        // admitted until the remaining allowance is measured after this setup.
        if (!MineFlipGas.canRun(meter, GasBounds.TERMINAL_SETUP, GasBounds.TERMINAL_TAIL)) return false;

        bool dead = _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0;
        uint24 lvl = level;

        uint256 totalFunds = address(this).balance + steth.balanceOf(address(this));

        // Compute available funds FIRST (before any side effects)
        // Deity pass refunds have not happened yet, so claimablePool is pre-refund.
        // sDGNRS redemption reservations are backed sDGNRS-side at submit (pullRedemptionReserve's
        // ETH leg moves the ETH out of the game; its custody leg pins sDGNRS's own holdings), so
        // they are never part of totalFunds here — subtracting pendingRedemptionEthValue would
        // double-count them.
        uint256 reserved = uint256(claimablePool);
        uint256 preRefundAvailable = totalFunds > reserved ? totalFunds - reserved : 0;

        // RNG gate: when distributable funds exist, require RNG word.
        // Defense-in-depth -- caller (_handleGameOverPath) already guarantees
        // _recordedDailyWord(day) != 0 before calling, so this revert should never fire.
        uint256 rngWord;
        if (preRefundAvailable != 0 && !dead) {
            rngWord = _lootboxWord(_rngReadBuffer());
            if (rngWord == 0) revert Invariant();
        }

        // === All side effects below this line (RNG confirmed or no funds to distribute) ===

        // The deterministic ending has no word to roll a pending sDGNRS gambling-burn pool
        // with, so it resolves at the roll's expected value, 100%. The pool's ETH is
        // segregated in sDGNRS, so this moves nothing out of the game's balance.
        if (dead) {
            uint24 pendingDay = dgnrs.pendingResolveDay();
            if (pendingDay != 0) dgnrs.resolveRedemptionPeriod(100, pendingDay);
        }

        // Deity pass refunds (levels 0-9): refund each owner what they paid, capped at the flat
        // DEITY_PASS_EARLY_GAMEOVER_REFUND so a boon-discounted deity (paid < 20 ETH) never refunds
        // more than it paid, then clamped to the remaining distributable budget (FIFO).
        if (lvl < 10) {
            uint256 ownerCount = deityPassOwners.length;
            uint256 budget = preRefundAvailable;
            uint256 totalRefunded;
            for (uint256 i; i < ownerCount; ) {
                address owner = deityPassOwners[i];
                uint256 refund = deityPassPricePaid[owner];
                if (refund != 0) {
                    if (refund > DEITY_PASS_EARLY_GAMEOVER_REFUND) {
                        refund = DEITY_PASS_EARLY_GAMEOVER_REFUND;
                    }
                    if (refund > budget) {
                        refund = budget;
                    }
                    if (refund != 0) {
                        _creditClaimable(owner, refund);
                        unchecked {
                            totalRefunded += refund;
                            budget -= refund;
                        }
                    }
                    if (budget == 0) break;
                }
                unchecked {
                    ++i;
                }
            }
            if (totalRefunded != 0) {
                claimablePool += uint128(totalRefunded); // Safe: totalRefunded bounded by preRefundAvailable which fits uint128
                // The per-owner credits above carry no domain event. One aggregate marker
                // names the refund total separately from the affiliate and ticket awards.
                emit DeityPassRefundsSettled(totalRefunded);
            }
        }

        // Latch terminal state
        gameOver = true;
        earlyBirdWhalePasses = 0;

        // Burn unallocated tokens
        charityGameOver.burnAtGameOver();
        dgnrs.burnAtGameOver();
        // Flood FLIP's VAULT mint allowance as a one-shot worthless-token tombstone
        flip.tombstoneAtGameOver();

        // next|future share one slot; zero both in a single SSTORE (no read needed). currentPrizePool
        // is a separate slot, still zeroed below.
        _setPrizePools(0, 0);
        _setCurrentPrizePool(0);
        yieldAccumulator = 0;
        // Terminal state also clears the freeze: with the live pools drained, _unlockRng's
        // _unfreezePool must not resurrect the pending pool back into them, and no
        // post-gameOver box/Degenerette resolution may draw ETH from a phantom pending pool.
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
        // All three pools are drained to zero at game over. Emit the terminal snapshot here —
        // before the available==0 early return below — so every game-over path logs it once. The
        // daily snapshot in _unlockRng skips game-over (gameOver is set above) to avoid a duplicate.
        emit PrizePoolDailySnapshot(
            0,
            0,
            0,
            claimablePool,
            totalFunds, // ETH + stETH unchanged since line 82 (burns/tombstone move no ETH/stETH)
            0, // yieldAccumulator was just zeroed above
            day
        );

        // Recalculate available after refunds (claimablePool may have grown).
        // sDGNRS redemption reservations are backed sDGNRS-side at submit, so they are not part
        // of totalFunds here — only claimablePool is reserved.
        uint256 postRefundReserved = uint256(claimablePool);
        uint256 available = totalFunds > postRefundReserved ? totalFunds - postRefundReserved : 0;

        if (available == 0) { _finishTerminalPayout(); return true; }

        emit GameOverDrained(lvl, available, claimablePool);

        // remaining tracks unallocated funds.
        uint256 remaining = available;

        // The winner was latched with the terminal cohort level before the terminal word
        // existed (_handleGameOverPath); credit it here once.
        uint24 terminalLevel = _gameOverTicketLevel(lvl);

        // Deterministic ending: no affiliate share, no draw. Fix the pot and the total weight
        // it divides by (tallied by tallyDeadVrf before this ran); every terminal-level ticket
        // then claims its share through claimDeadVrf until the final sweep.
        if (dead) {
            uint256 created = deadCreated;
            uint256 uncreated = deadUncreated;
            deadPot = uint128(remaining);
            deadTotal = uint64(created * QTY_SCALE + uncreated);
            deadUncreatedLeft = uint64(uncreated);
            emit DeadVrfPayoutFixed(terminalLevel, remaining, created, uncreated, deadTraitCount);
            _finishTerminalPayout();
            return true;
        }
        address top = terminalAffiliate;
        uint256 affiliateShare = remaining / 50;
        if (top != address(0) && affiliateShare != 0) {
            _creditClaimable(top, affiliateShare);
            claimablePool += uint128(affiliateShare);
            remaining -= affiliateShare;
            emit TerminalAffiliatePaid(top, terminalLevel, affiliateShare);
        }

        // All remaining ETH goes to the final ticket cohort (Final-day distribution).
        // gameOver=true prevents auto-rebuy inside _addClaimableEth (tickets worthless post-game).
        // Pay from the SAME phase-correct level the AdvanceModule terminal drain materialized:
        // current `lvl` in jackpot phase and in the locked last-purchase transition (where level was
        // already promoted), otherwise purchase-phase `lvl + 1`. Any leftover from empty trait
        // buckets stays in the contract until handleFinalSweep (30 days later) folds it into the
        // three-way split to vault / sDGNRS / GNRUS.
        // Pin the pot before returning even if this call has too little allowance
        // left to roll a first quadrant. 255 denotes priced but not yet initialized.
        jackpotWork.kind = 3;
        jackpotWork.lvl = terminalLevel;
        jackpotWork.budget = uint128(remaining);
        jackpotWork.quadrant = 255;
        return _resumeTerminalPayout(day, meter);
    }

    function _resumeTerminalPayout(uint24 day, MineFlipGas.Meter memory meter) private returns (bool done) {
        uint256 allowance = MineFlipGas.forwardable(MineFlipGas.remaining(meter), 100_000);
        if (allowance == 0) return false;
        (MineFlipGas.Result memory result,) = IDegenerusGame(address(this)).runTerminalJackpotWork(
            jackpotWork.budget, jackpotWork.lvl, _lootboxWord(_rngReadBuffer()), allowance
        );
        if (result.done) _finishTerminalPayout();
        return result.done;
    }

    function _finishTerminalPayout() private {
        _goWrite(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK, 1);
        _goWrite(GO_TIME_SHIFT, GO_TIME_MASK, uint48(block.timestamp));
    }

    /// @notice Final sweep of all remaining funds after 30 days post-gameover.
    /// @dev Pays each sink (vault, sDGNRS, GNRUS) its whole game-side balance still
    ///      owed to it — claimable plus prepaid afking — then splits the remainder ~1/3
    ///      each (GNRUS absorbs the rounding wei). All other unclaimed player balances
    ///      are forfeited.
    ///      After GO_SWEPT=1, claimWinnings() reverts, so this is the last
    ///      chance for the three sinks to receive what they earned in-game.
    ///      Also shuts down the VRF subscription and sweeps LINK to vault.
    /// @custom:reverts TransferFailed When ETH or stETH transfer fails
    function handleFinalSweep() public {
        if (_goRead(GO_JACKPOT_PAID_SHIFT, GO_JACKPOT_PAID_MASK) == 0) return;
        uint256 goTime = _goRead(GO_TIME_SHIFT, GO_TIME_MASK);
        if (goTime == 0) return; // Game not over yet
        if (block.timestamp < goTime + 30 days) return; // Too early
        if (_goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) return; // Already swept

        _goWrite(GO_SWEPT_SHIFT, GO_SWEPT_MASK, 1);
        charityGameOver.onFinalSweep(); // stamp GNRUS with the sweep time (anchors its recovery gates)

        uint256 owedV  = _takeSinkBalance(ContractAddresses.VAULT);
        uint256 owedSD = _takeSinkBalance(ContractAddresses.SDGNRS);
        uint256 owedG  = _takeSinkBalance(ContractAddresses.GNRUS);
        claimablePool = 0;

        // Shutdown VRF subscription (fire-and-forget; failure must not block sweep)
        try admin.shutdownVrf() {} catch {}

        uint256 ethBal = address(this).balance;
        uint256 stBal = steth.balanceOf(address(this));
        uint256 totalFunds = ethBal + stBal;

        emit FinalSwept(totalFunds);

        if (totalFunds == 0) return;

        // Protocol balances are fully backed: totalFunds >= owedV + owedSD + owedG. Only an stETH
        // loss (a negative rebase) larger than the unclaimed cushion can break that, and the sweep
        // must still complete, so a shortfall splits what exists pro rata. The three legs still sum
        // to exactly totalFunds.
        uint256 owed = owedV + owedSD + owedG;
        uint256 remainder;
        if (totalFunds >= owed) {
            remainder = totalFunds - owed;
        } else {
            owedV = (owedV * totalFunds) / owed;
            owedSD = (owedSD * totalFunds) / owed;
            owedG = totalFunds - owedV - owedSD;
        }
        uint256 thirdShare = remainder / 3;
        uint256 gnrusExtra = remainder - thirdShare - thirdShare;

        stBal = _sendStethFirst(ContractAddresses.VAULT,  owedV  + thirdShare, stBal);
        stBal = _sendStethFirst(ContractAddresses.SDGNRS, owedSD + thirdShare, stBal);
        _sendStethFirst(ContractAddresses.GNRUS,          owedG  + gnrusExtra, stBal);
    }

    /// @dev Zero a sink's packed balance — claimable (low half) and prepaid afking (high half),
    ///      both inside claimablePool — and return the total the final sweep owes it.
    function _takeSinkBalance(address sink) private returns (uint256 owed) {
        uint256 claimable = _claimableOf(sink);
        uint256 afking = _afkingOf(sink);
        _debitClaimableAndAfking(sink, claimable, afking);
        if (claimable != 0) emit ClaimableSpent(sink, claimable, 0, MintPaymentKind.Internal, claimable);
        if (afking != 0) emit AfkingSpent(sink, afking);
        owed = claimable + afking;
    }

    /*+========================================================================================+
      |                    DETERMINISTIC (VRF-DEAD) ENDING                                     |
      +========================================================================================+
      |  When a VRF request goes unanswered for 14 days the game ends with no entropy at all.  |
      |  Every ticket of the terminal level shares the pot: an uncreated one (queued, or in an |
      |  undrained foil pack, its traits never rolled) takes the average; the created ones     |
      |  share the rest equally per non-empty trait bucket, then equally within each bucket.   |
      +========================================================================================+*/

    /// @notice Count the terminal level's tickets for the deterministic ending.
    /// @dev Advance-only delegate target (_handleGameOverPath, after the dead ending latched).
    ///      No ticket or foil drain runs once it is latched and every entry point that could
    ///      add a ticket is closed by the liveness trigger, so what is counted here stays
    ///      put. Actual-gas checkpoints retain exact record cursors and totals.
    ///      Three stages:
    ///        0 — uncreated queued entries: the terminal read, write and future queues, snap-adjusted as the ticket drain would have applied it, in QTY_SCALE
    ///            units (a fractional remainder counts as its fraction of an entry);
    ///        1 — undrained foil packs of `lvl`, FOIL_PACK_ENTRIES entries each;
    ///        2 — created tickets: every trait bucket's occurrence count, and how many of the
    ///            256 buckets are non-empty.
    /// @param lvl The latched terminal ticket level.
    /// @return finished True once all three stages are done.
    function tallyDeadVrf(uint24 lvl) public returns (bool finished) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        finished = _tallyDeadVrf(lvl, meter);
        MineFlipGas.finish(meter);
    }

    function _tallyDeadVrf(uint24 lvl, MineFlipGas.Meter memory meter) private returns (bool finished) {
        uint256 stage = deadTallyStage;
        if (stage == 3) return true;
        uint256 uncreated = deadUncreated;
        uint24 dd = deadTallyFoilDay;
        uint256 idx = deadTallyFoilIdx;

        if (stage == 0) {
            uint256 pos = deadTallyPos;
            uint8 shift = _snapShiftFor(lvl);
            while (dd < 3) {
                uint24 key = dd == 0 ? _tqReadKey(lvl) : (dd == 1 ? _tqWriteKey(lvl) : _tqFarFutureKey(lvl));
                uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(key)];
                uint256 len = _ticketQueueLength(key);
                while (pos < len) {
                    if (!MineFlipGas.canRun(meter, GasBounds.TERMINAL_TALLY_RECORD, GasBounds.TERMINAL_TALLY_TAIL)) {
                        deadTallyPos = uint32(pos);
                        deadTallyFoilDay = dd;
                        deadUncreated = uint64(uncreated);
                        return false;
                    }
                    uint32 id = _tqPositionAt(queue, pos);
                    uncreated += _deadWeight(_entryPacked(key, id), shift);
                    unchecked { ++pos; }
                }
                pos = 0;
                unchecked { ++dd; }
            }
            deadTallyPos = 0;
            stage = 1;
            // Both frozen read and accumulating write cohorts remain paid inventory.
            // dd uses 1/2 as progress markers for physical queue keys 0/1.
            dd = 1;
            idx = _foilReadKey() == 0 ? foilCursor : 0;
        }

        if (stage == 1) {
            while (dd != 0 && dd <= 2) {
                uint256[] storage bucket = foilQueue[dd - 1];
                uint256 n = bucket.length;
                if (idx < n) {
                    uint256 packs;
                    assembly ("memory-safe") {
                        mstore(0, bucket.slot)
                        packs := keccak256(0, 32)
                    }
                    do {
                        if (!MineFlipGas.canRun(meter, GasBounds.TERMINAL_TALLY_RECORD, GasBounds.TERMINAL_TALLY_TAIL)) {
                            _saveDeadTally(1, dd, idx, uncreated);
                            return false;
                        }
                        // idx < n proves this cached-base read is within the day's bucket.
                        uint256 pack;
                        assembly ("memory-safe") { pack := sload(add(packs, idx)) }
                        if (uint24(pack >> 160) == lvl) {
                            uncreated += FOIL_PACK_ENTRIES * QTY_SCALE;
                        }
                        unchecked {
                            ++idx;
                        }
                    } while (idx < n);
                }
                // Charge the day step too, so a long run of empty days stays metered.
                if (!MineFlipGas.canRun(meter, GasBounds.TERMINAL_TALLY_RECORD, GasBounds.TERMINAL_TALLY_TAIL)) {
                    _saveDeadTally(1, dd, idx, uncreated);
                    return false;
                }
                unchecked {
                    ++dd;
                }
                idx = dd <= 2 && dd - 1 == _foilReadKey() ? foilCursor : 0;
            }
            stage = 2;
        }

        // Stage 2: reserve the entire fixed 256-bucket scan before starting it.
        if (!MineFlipGas.canRun(meter, GasBounds.TERMINAL_TALLY_FINAL, GasBounds.TERMINAL_TALLY_TAIL)) {
            _saveDeadTally(2, dd, idx, uncreated);
            return false;
        }
        uint256 created;
        uint256 traits;
        // No calls or bucket mutations occur during this scan. Authenticate the
        // retained level once, then reuse its live bitmap and bucket base.
        _assertReadableTicketLevel(lvl);
        uint256 live = _ticketBufferLevel(lvl) == lvl ? traitBucketLive[lvl & 1] : 0;
        uint256 base = _traitBufferBase(lvl);
        for (uint256 t; t < 256; ) {
            if (live & (uint256(1) << t) != 0) {
                uint256 n;
                assembly ("memory-safe") { n := and(sload(add(base, t)), 0xffffffff) }
                if (n != 0) {
                    created += n;
                    unchecked {
                        ++traits;
                    }
                }
            }
            unchecked {
                ++t;
            }
        }
        deadCreated = uint64(created);
        deadTraitCount = uint16(traits);
        _saveDeadTally(3, dd, idx, uncreated);
        return true;
    }

    /// @dev Persist a paused (or finished) tally.
    function _saveDeadTally(uint256 stage, uint24 dd, uint256 idx, uint256 uncreated) private {
        deadTallyStage = uint8(stage);
        deadTallyFoilDay = dd;
        deadTallyFoilIdx = uint32(idx);
        deadUncreated = uint64(uncreated);
    }

    /// @dev An owed word's uncreated weight in QTY_SCALE units, snap-adjusted exactly as the
    ///      ticket drain applies it on first touch (_processOneTicketEntry).
    function _deadWeight(uint80 packed, uint8 shift) private pure returns (uint256) {
        uint256 weight = uint256(uint32(packed >> 8)) * QTY_SCALE + uint8(packed);
        // Only the scaled weight is needed here. The drain's snap helper repacks the
        // quotient and remainder for storage; unpacking those again gives weight >> shift.
        if (shift != 0 && packed & SNAP_DONE_BIT == 0) return weight >> shift;
        return weight;
    }

    /// @notice Claim deterministic-ending shares for `player`'s terminal-level tickets.
    /// @dev Delegatecall target of DegenerusGame.claimDeadVrf. Permissionless: every share
    ///      credits the holding's owner, never the caller. Open from the dead ending's payout
    ///      until the final sweep. Each reference names one holding; the top byte is its kind:
    ///        DEAD_REF_CREATED (0) — a created ticket: trait at bits 64..71, occurrence index
    ///          at bits 0..63 of the reference, selecting a holding in the level's trait bucket.
    ///          Pays the trait's equal share of
    ///          the created pot, divided equally among that trait's tickets.
    ///        DEAD_REF_QUEUED (1) — uncreated queued entries: permanent wallet ID at
    ///          bits 0..31 and absolute queue key (including its domain flags) at bits
    ///          32..55. Pays pot * weight / total for that ID's balance in that queue.
    ///        any other kind — an undrained foil pack: physical cohort (0/1) at bits 64..87, index into
    ///          foilQueue[cohort] at bits 0..63. Pays pot * FOIL_PACK_ENTRIES * QTY_SCALE / total.
    ///      Each holding pays once: a created ticket sets its claimed bit, a queued position
    ///      has its owed balance zeroed, a foil pack has its bucket word zeroed. Uncreated
    ///      weight claimed is debited from the tallied total, so claims can never exceed it.
    ///      Rounding dust stays in the contract for the final sweep.
    /// @param player Owner of every referenced holding.
    /// @param refs The holdings to claim.
    /// @custom:reverts E When no deterministic payout is open, or a reference is invalid,
    ///      not `player`'s, or already claimed.
    function claimDeadVrf(address player, uint256[] calldata refs) external {
        uint256 total = deadTotal;
        if (total == 0 || _goRead(GO_SWEPT_SHIFT, GO_SWEPT_MASK) != 0) revert E();
        uint256 pot = deadPot;
        uint24 lvl = _gameOverTicketLevel(level);
        uint256 traits = deadTraitCount;
        uint256 perTrait = traits == 0 ? 0 : (pot * uint256(deadCreated) * QTY_SCALE) / total / traits;
        uint8 shift = _snapShiftFor(lvl);
        uint256 amount;
        uint256 weight;
        for (uint256 i; i < refs.length; ) {
            uint256 ref = refs[i];
            uint256 kind = ref >> 248;
            if (kind == DEAD_REF_CREATED) {
                uint8 trait = uint8(ref >> 64);
                uint256 k = uint64(ref);
                uint256 n = _bucketLength(lvl, trait);
                if (k >= n || _bucketOwnerAtUnchecked(lvl, trait, k) != player) revert E();
                uint256 key = (uint256(trait) << 64) | (k >> 8);
                uint256 bits = deadClaimed[key];
                uint256 bit = uint256(1) << (k & 255);
                if (bits & bit != 0) revert E();
                deadClaimed[key] = bits | bit;
                amount += perTrait / n;
            } else if (kind == DEAD_REF_QUEUED) {
                uint32 pos = uint32(ref);
                // Queue-domain key is carried above the stable ID in bits 32..55.
                uint24 key = uint24(ref >> 32);
                if (key != _tqReadKey(lvl) && key != _tqWriteKey(lvl) && key != _tqFarFutureKey(lvl)) revert E();
                uint256 record = _entryRecord(key, pos);
                if (address(uint160(record)) != player) revert E();
                uint256 w = _deadWeight(uint80(record >> 160), shift);
                if (w == 0) revert E();
                _setEntryOwed(key, pos, 0);
                weight += w;
                amount += (pot * w) / total;
            } else {
                uint24 cohort = uint24(ref >> 64);
                uint256 idx = uint64(ref);
                if (cohort > 1 || (cohort == _foilReadKey() && idx < foilCursor)) revert E();
                uint256[] storage bucket = foilQueue[cohort];
                if (idx >= bucket.length) revert E();
                uint256 pack = bucket[idx];
                if (address(uint160(pack)) != player || uint24(pack >> 160) != lvl) revert E();
                bucket[idx] = 0;
                uint256 w = FOIL_PACK_ENTRIES * QTY_SCALE;
                weight += w;
                amount += (pot * w) / total;
            }
            unchecked {
                ++i;
            }
        }
        uint256 left = deadUncreatedLeft;
        if (weight > left) revert E();
        deadUncreatedLeft = uint64(left - weight);
        if (amount != 0) {
            _creditClaimable(player, amount);
            claimablePool += uint128(amount);
            emit DeadVrfClaimed(player, amount);
        }
    }

    /// @dev Send stETH first to a recipient, then ETH for the remainder. Returns updated stETH balance.
    ///      IMPORTANT: Hard-reverts on stETH/ETH transfer failure. handleFinalSweep latches
    ///      GO_SWEPT before transferring, so a stuck stETH transfer reverts the whole sweep
    ///      (GO_SWEPT rolls back), blocking the final sweep until the transfer succeeds.
    /// @param to Recipient address.
    /// @param amount Total amount to send (stETH preferred, ETH as fallback).
    /// @param stethBal Remaining stETH balance available for transfers.
    /// @return Updated stETH balance after transfer.
    function _sendStethFirst(address to, uint256 amount, uint256 stethBal) private returns (uint256) {
        if (amount == 0) return stethBal;
        if (amount <= stethBal) {
            if (!steth.transfer(to, amount)) revert TransferFailed();
            return stethBal - amount;
        }
        if (stethBal != 0) {
            if (!steth.transfer(to, stethBal)) revert TransferFailed();
        }
        uint256 ethAmount = amount - stethBal;
        if (ethAmount != 0) {
            (bool ok, ) = payable(to).call{value: ethAmount}("");
            if (!ok) revert TransferFailed();
        }
        return 0;
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  Deploy-only VRF setup called from the ContractAddresses.ADMIN constructor, and the    |
      |  governance-gated emergency coordinator rotation. Cold administrative paths hosted     |
      |  here for the advance module's EIP-170 headroom; both operate on the shared VRF        |
      |  storage the daily request path reads.                                                 |
      +========================================================================================+*/

    /// @notice Wire VRF config, called once from the ADMIN constructor during deployment.
    /// @dev Access: ContractAddresses.ADMIN only. No post-deploy caller exists on ADMIN;
    ///      emergency VRF rotation uses updateVrfCoordinatorAndSub instead.
    /// @param coordinator_ Chainlink VRF V2.5 coordinator address.
    /// @param subId VRF subscription ID for LINK billing.
    /// @param keyHash_ VRF key hash for gas lane selection.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();

        address current = address(vrfCoordinator);
        _setVrfConfig(coordinator_, subId, keyHash_);
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit VrfCoordinatorUpdated(current, coordinator_);
    }

    /// @notice Emergency VRF coordinator rotation (governance-gated).
    /// @dev Access: ContractAddresses.ADMIN only. The Admin contract enforces
    ///      stall duration via sDGNRS-holder governance (propose/vote/execute).
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the gas lane.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();

        address current = address(vrfCoordinator);
        _setVrfConfig(newCoordinator, newSubId, newKeyHash);

        // Once the game has ended, or the deterministic ending has latched, no word can count
        // for anything: repoint the config only, never re-issue.
        if (gameOver || _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0) {
            emit VrfCoordinatorUpdated(current, newCoordinator);
            return;
        }

        // Detect what is in flight and re-issue on the new coordinator. A re-issue is the same
        // request sent again: rngRequestTime is left as it was, so the request keeps the day it
        // was first issued for and the VRF-dead window keeps running from the original send.
        // The request is accepted before the new subscription is LINK-funded; DegenerusAdmin
        // funds it in the same _executeSwap transaction (transferAndCall), and the VRF node
        // fulfills once funded. If the new coordinator also stalls, the vault owner's one retry is
        // the remaining recourse, and a request unanswered _VRF_DEAD_TIMEOUT from its original
        // send reaches the VRF-dead ending.
        if (!rngLockedFlag) {
            // Reissue only an active unanswered mid-day request. Delivery does not clear
            // its ID; a delivered word awaiting keeper publication must remain unchanged.
            if (_rngRequestActive() && rngWordCurrent == RNG_WORD_WAITING) vrfRequestId = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);
        } else {
            // Daily in flight: KEEP rngLockedFlag=true.
            if (rngWordCurrent == RNG_WORD_WAITING) {
                // Daily word not yet delivered: re-request on the new coordinator. The swap spends
                // the vault owner's single retry (the low bit; the stamp itself does not move): the
                // retry is the last resort before a swap, and re-armed here it could discard the
                // new coordinator's first answer. A replacement that stalls too is recovered by
                // another swap or reaches the VRF-dead ending.
                vrfRequestId = _requestVrfWord(VRF_REQUEST_CONFIRMATIONS);
                rngRequestTime |= 1;
            }
            // else: daily word already delivered and valid -> preserve it; no re-issue
            // (a fresh callback would be rejected by the advance module's
            // rngWordCurrent != RNG_WORD_WAITING fulfillment guard).
        }

        // Intentional: totalFlipReversals is NOT reset here. Nudges were purchased
        // with irreversible FLIP burns before or during the stall. They carry over
        // and apply to the first post-swap VRF word via _applyDailyRng. Resetting
        // would steal user value (burned FLIP for zero effect).

        emit VrfCoordinatorUpdated(current, newCoordinator);
    }

    /// @dev Write the VRF coordinator, subscription, and key hash together.
    /// @param coord VRF coordinator address.
    /// @param sub VRF subscription ID for LINK billing.
    /// @param key VRF key hash for gas lane selection.
    function _setVrfConfig(address coord, uint256 sub, bytes32 key) private {
        vrfCoordinator = IVRFCoordinator(coord);
        vrfSubscriptionId = sub;
        vrfKeyHash = key;
    }

    /// @dev Submit a single-word VRF request on the current coordinator.
    /// @param confirmations Block confirmations for this request's gas lane.
    /// @return id The Chainlink request ID.
    function _requestVrfWord(uint16 confirmations) private returns (uint256 id) {
        id = vrfCoordinator.requestRandomWords(
            VRFRandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: confirmations,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: hex""
            })
        );
    }
}
