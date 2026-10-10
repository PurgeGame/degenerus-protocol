// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

import {BitPackingLib} from "../libraries/BitPackingLib.sol";
import {ContractAddresses} from "../ContractAddresses.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {DegenerusGameMintStreakUtils} from "./DegenerusGameMintStreakUtils.sol";

import {IDegenerusGameAdvanceModule, IDegenerusGameRngModule, IDegenerusGameTicketModule,
    IDegenerusGameDegeneretteModule, IDegenerusGameDecimatorModule, IGameAfkingModule}
    from "../interfaces/IDegenerusGameModules.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";

interface IMinerCrapsWork {
    function runCrapsReadWork(uint48 index, uint256 allowance) external returns (MineFlipGas.Result memory);
    function runCrapsMaintenance(uint256 allowance) external returns (MineFlipGas.Result memory);
}

/// @notice The single permissionless state engine. Workers never choose global priority.
contract DegenerusGameMinerModule is DegenerusGameMintStreakUtils {
    error NoWork();
    error RngNotReady();

    // Covers calldata construction, call/decoding, category normalization and loop exit.
    uint256 private constant WORKER_BOUNDARY = GasBounds.ENGINE_BOUNDARY;
    uint256 private constant RETURN_RESERVE = GasBounds.ENGINE_RETURN;
    // Base-fee reimbursement excludes the caller-selected priority fee.
    uint256 private constant INITIAL_REWARD_BASEFEE_CAP = 500_000_000;

    event MinerWork(address indexed caller, uint8 firstAction, uint256 executionGas, uint256 flipReward);

    /// @notice The next action for a mineFlip by msg.sender: a donor holding credit sees a
    ///         below-threshold mid-day request that a creditless caller does not.
    function minerAction() external view returns (uint8) {
        return uint8(_nextMinerAction(msg.sender));
    }

    /// @dev Permissionless cache refresh, executed against Game storage only. Returns the
    ///      wallet ID beside the score (0 for an unregistered wallet; never allocated here).
    function playerActivityScoreCachedById(uint32 id) external returns (uint256) {
        if (address(this) != ContractAddresses.GAME) revert OnlyDelegatecall();
        return _playerActivityScoreCached(id, _effectiveQuestStreak(id));
    }

    function playerActivityScoreCached(address player) external returns (uint256 score, uint32 id) {
        if (address(this) != ContractAddresses.GAME) revert E();
        id = _walletIdOf(player);
        score = _playerActivityScoreCached(id, _effectiveQuestStreak(id));
    }

    function mineFlip(uint32 gasMultiplierBps) external {
        if (address(this) != ContractAddresses.GAME) revert E();
        gasMultiplierBps = MineFlipGas.normalize(gasMultiplierBps);
        uint256 rewardStart = gasleft();
        MinerAction first = _nextMinerAction(msg.sender);
        if (first == MinerAction.Idle) revert NoWork();
        if (first == MinerAction.Wait) revert RngNotReady();
        bool rewardEligible = first != MinerAction.Terminal;
        uint256 rewardPrice = PriceLookupLib.priceForLevel(_activeTicketLevel());
        uint256 rewardDueAt = _minerRewardDueAt();
        // Read before work, like the clock: the call that releases the lock still earns the locked rate.
        bool lockedAtStart = rngLockedFlag;
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.budget(gasleft(), gasMultiplierBps, true));
        bool moved;
        uint256 unpaidAttemptGas;

        // There are fewer than 32 category transitions. Workers own all unbounded queues.
        for (uint256 transitions; transitions < 32; ++transitions) {
            // Only reads separate the initial selection from the first dispatch.
            // Every later iteration must reselect after the preceding worker's changes.
            MinerAction action = transitions == 0 ? first : _nextMinerAction(msg.sender);
            if (action == MinerAction.Idle || action == MinerAction.Wait) break;
            if (moved) MineFlipGas.markProgress(meter);
            if (!MineFlipGas.canRun(meter, WORKER_BOUNDARY, RETURN_RESERVE)) break;

            if (action == MinerAction.CertifyRead) {
                // Selected only with the read cohort drained (stage 7) and no certificate.
                // That selector read is the certificate's evidence, so certify from it:
                // the action can never be reselected in the same state.
                _setRngComplete(true);
                moved = true;
                MineFlipGas.markProgress(meter);
                continue;
            }

            if (action == MinerAction.GrowthSettle) {
                // Selected only while the pending bit is set. Every call moves the settlement
                // cursor at least one step (pays a winner or steps past a paid sealed round), or
                // reports every sealed round paid and clears the bit, so the stage always
                // progresses. Settlement is revert-free for committed state.
                MineFlipGas.Result memory growth = parimutuel.runGrowthWork(
                    MineFlipGas.child(meter, RETURN_RESERVE + WORKER_BOUNDARY));
                if (growth.done) _setGrowthSettlePending(false);
                moved = moved || growth.progressed || growth.done;
                if (!growth.done) break;
                continue;
            }

            if (action == MinerAction.PrepareSubscriptions && _afkingResetDay <= dailyIdx) {
                // Once pinned, a preparation day survives midnight and partial batches.
                _afkingResetDay = _simulatedDayIndex();
                _subCursor = 0;
                _subOpenCursor = 0;
                subsFullyProcessed = false;
                moved = true;
                MineFlipGas.markProgress(meter);
                if (!MineFlipGas.canRun(meter, WORKER_BOUNDARY, RETURN_RESERVE)) break;
            }

            uint256 allowance = MineFlipGas.child(meter, WORKER_BOUNDARY + RETURN_RESERVE);
            address target;
            bytes memory callData;
            bool externalWorker;
            bool basicResult;
            bool request = action == MinerAction.RequestDaily || action == MinerAction.RequestMidday;

            if (action == MinerAction.Terminal) {
                basicResult = true;
                target = ContractAddresses.GAME_ADVANCE_MODULE;
                callData = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runTerminalPhase.selector, allowance);
            } else if (action == MinerAction.DailyGap) {
                if (!MineFlipGas.canRun(meter, GasBounds.DAILY_GAP, RETURN_RESERVE + WORKER_BOUNDARY)) break;
                target = ContractAddresses.GAME_ADVANCE_MODULE;
                callData = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyGap.selector);
            } else if (action == MinerAction.DailyApply) {
                if (!MineFlipGas.canRun(meter, GasBounds.DAILY_APPLY, RETURN_RESERVE + WORKER_BOUNDARY)) break;
                target = ContractAddresses.GAME_ADVANCE_MODULE;
                callData = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyWord.selector);
            } else if (action == MinerAction.DailyPhase) {
                basicResult = true;
                target = ContractAddresses.GAME_ADVANCE_MODULE;
                callData = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runDailyPhase.selector, allowance);
            } else if (action == MinerAction.Publish) {
                target = ContractAddresses.GAME_RNG_MODULE;
                callData = abi.encodeWithSelector(IDegenerusGameRngModule.publishRng.selector);
            } else if (request) {
                target = ContractAddresses.GAME_RNG_MODULE;
                if (action == MinerAction.RequestDaily) {
                    callData = abi.encodeWithSelector(IDegenerusGameRngModule.requestDailyRng.selector, _afkingResetDay);
                } else {
                    callData = abi.encodeWithSelector(IDegenerusGameRngModule.requestMinerRng.selector);
                }
                uint256 requestMax = action == MinerAction.RequestDaily
                    ? GasBounds.RNG_DAILY_REQUEST : GasBounds.RNG_MIDDAY_REQUEST;
                // Batch pricing, backing settlement and ETH/stETH funding stay atomic with
                // the commitment. Only a nonempty open batch pays their rare admission cost.
                // The first mandatory action bypasses estimates, including this sizing read.
                if (moved) {
                    (,,, uint256 escrowed) = IsDGNRS(ContractAddresses.SDGNRS).redemptionBatchState();
                    if (escrowed != 0) requestMax += GasBounds.RNG_REDEMPTION_CLOSE;
                }
                if (!MineFlipGas.canRun(meter, requestMax, RETURN_RESERVE + WORKER_BOUNDARY)) break;
            } else {
                basicResult = true;
                if (action == MinerAction.Tickets) {
                    target = ContractAddresses.GAME_TICKET_MODULE;
                    uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
                    callData = abi.encodeWithSelector(IDegenerusGameTicketModule.runTicketWork.selector, anchor, allowance);
                } else if (action == MinerAction.PrepareSubscriptions) {
                    target = ContractAddresses.GAME_AFKING_MODULE;
                    callData = abi.encodeWithSelector(IGameAfkingModule.runSubscriberWork.selector, _afkingResetDay, allowance);
                } else if (action == MinerAction.Afking) {
                    target = ContractAddresses.GAME_AFKING_MODULE;
                    callData = abi.encodeWithSelector(IGameAfkingModule.runAfkingWork.selector, allowance);
                } else if (action == MinerAction.HumanBoxes) {
                    target = ContractAddresses.GAME_AFKING_MODULE;
                    callData = abi.encodeWithSelector(IGameAfkingModule.runHumanBoxWork.selector, allowance);
                } else if (action == MinerAction.Degenerette) {
                    target = ContractAddresses.GAME_DEGENERETTE_MODULE;
                    callData = abi.encodeWithSelector(IDegenerusGameDegeneretteModule.runDegeneretteWork.selector, allowance);
                } else if (action == MinerAction.Decimator) {
                    target = ContractAddresses.GAME_DECIMATOR_MODULE;
                    callData = abi.encodeWithSelector(IDegenerusGameDecimatorModule.runDecimatorWork.selector, allowance);
                } else if (action == MinerAction.Redemption) {
                    target = ContractAddresses.SDGNRS;
                    externalWorker = true;
                    // Stage 1 runs before any later request, so the published read word is the
                    // one that answered the request that closed the settling batch.
                    callData = abi.encodeWithSelector(
                        IsDGNRS.runRedemptionWork.selector, _lootboxWord(_rngReadBuffer()), allowance
                    );
                } else {
                    target = ContractAddresses.CRAPS;
                    externalWorker = true;
                    callData = action == MinerAction.Craps
                        ? abi.encodeWithSelector(IMinerCrapsWork.runCrapsReadWork.selector, _rngReadBuffer(), allowance)
                        : abi.encodeWithSelector(IMinerCrapsWork.runCrapsMaintenance.selector, allowance);
                }
            }

            uint256 forwarded = MineFlipGas.forwardable(meter, RETURN_RESERVE);
            uint256 beforeCall = gasleft();
            bool ok;
            bytes memory result;
            if (externalWorker) (ok, result) = target.call{gas: forwarded}(callData);
            else (ok, result) = target.delegatecall{gas: forwarded}(callData);
            if (!ok) {
                // A declined next step must not undo an already committed prefix.
                // Accounting/invariant errors still bubble, including WorkGasBound.
                if (!moved || !(_checkpointRefusal(result)
                    || (action == MinerAction.RequestMidday && _middayRefusal(result)))) _revertWork(result);
                unpaidAttemptGas = MineFlipGas.consumed(beforeCall, gasleft());
                break;
            }

            if (basicResult) {
                // Preserve the full Result ABI and bool validation without allocating a struct.
                (bool progressed, bool done,) = abi.decode(result, (bool, bool, uint256));
                if (action == MinerAction.Tickets && done) {
                    // An empty queue can still advance its one-time certificate.
                    if (!ticketsFullyProcessed) { ticketsFullyProcessed = true; progressed = true; MineFlipGas.markProgress(meter); }
                    if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) {
                        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                        progressed = true;
                        MineFlipGas.markProgress(meter);
                    }
                }
                if (!progressed) {
                    // done describes eligibility/completion, not work performed.
                    // Never redispatch an unchanged worker, even if it says done.
                    unpaidAttemptGas = MineFlipGas.consumed(beforeCall, gasleft());
                    if (!moved) {
                        if (done) revert NoWork();
                        revert MineFlipGas.InsufficientExecutionGas();
                    }
                    break;
                }
                moved = true;
                MineFlipGas.markProgress(meter);
                if (!done) break;
            } else { moved = true; MineFlipGas.markProgress(meter); }
            // A request commits the next cohort; terminal stages own their continuation.
            if (action == MinerAction.Terminal || request) break;
        }

        // The only remaining zero-progress exit is a failed engine admission check.
        if (!moved) revert MineFlipGas.InsufficientExecutionGas();
        // This top-level meter starts with all available gas; worker allowance checks
        // retain the actual bounds. No successful call can overspend this initial amount.
        uint256 used = MineFlipGas.consumed(rewardStart, gasleft());
        used = used > unpaidAttemptGas ? used - unpaidAttemptGas : 0;
        uint256 reward;
        // Every call's first MIN_REWARDED_GAS is unpaid. Splitting work into small calls forfeits
        // another unpaid million per call; the only thing an extra qualifying call can gain is the
        // sub-FLIP rounding below, bounded by one FLIP per paid call.
        if (rewardEligible && !gameOver && used > MineFlipGas.MIN_REWARDED_GAS) {
            // Price only compensation, after work and its gas measurement are complete.
            uint256 elapsed = block.timestamp > rewardDueAt ? block.timestamp - rewardDueAt : 0;
            (uint256 cap, uint256 multiplierBps) = _minerRewardTerms(elapsed);
            if (_minerHoldsActivePass(msg.sender)) multiplierBps <<= 1;
            if (lockedAtStart) multiplierBps <<= 1;
            uint256 rate = block.basefee;
            if (rate > cap) rate = cap;
            uint256 numerator = (used - MineFlipGas.MIN_REWARDED_GAS) * rate * PRICE_COIN_UNIT * multiplierBps;
            uint256 denominator = rewardPrice * 10_000;
            // Legacy raw reward was floor(numerator * 1e18 / denominator). Preserve its
            // zero cutoff without multiplying, then pay whole FLIP with the existing minimum.
            if (numerator >= (denominator - 1) / 1e18 + 1) {
                // The stake ledger is keyed by wallet ID. A miner without one is registered on
                // its first bounty, after the measured work; past paid admission that bounty is
                // dropped (no registration, no credit). Registration only appends the ordinary
                // wallet and its forward lookup; it does not write mint history.
                uint32 minerId = _walletIdOf(msg.sender);
                if (minerId == 0 && wallets.length <= PAID_ADMISSION_WALLETS) {
                    (minerId, ) = _registerWallet(msg.sender, 0);
                }
                if (minerId != 0) {
                    reward = numerator / denominator;
                    if (reward == 0) reward = 1;
                    // Coinflip stakes are whole FLIP: a positive reward pays at least 1 FLIP,
                    // larger rewards floor to whole FLIP. Applied after the gas measurement, so
                    // the normalization cannot price itself. Both events report this figure;
                    // below the daily stake cap it is exactly what Coinflip credits.
                    coinflip.creditFlip(minerId, reward);
                    emit MinerBounty(MINER_BOUNTY_ADVANCE, msg.sender, reward);
                }
            }
        }
        emit MinerWork(msg.sender, uint8(first), used, reward);
    }

    /// @dev Saturate before shifting or multiplying so arbitrary elapsed time cannot overflow.
    function _minerRewardTerms(uint256 elapsed) internal pure returns (uint256 capWei, uint256 multiplierBps) {
        uint256 steps = elapsed / 30 minutes;
        if (steps > 4) steps = 4;
        capWei = INITIAL_REWARD_BASEFEE_CAP << steps;
        multiplierBps = 3_000 + 4_500 * steps;
    }

    /// @dev A deity pass, or a lazy/whale pass whose window covers the current level,
    ///      doubles the caller's bounty. Same pass test as the activity score.
    function _minerHoldsActivePass(address miner) internal view returns (bool) {
        uint256 packed = mintPacked_[_walletIdOf(miner)];
        if (packed >> BitPackingLib.HAS_DEITY_PASS_SHIFT & 1 != 0) return true;
        uint256 passType = (packed >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3;
        return (passType == 1 || passType == 3)
            && ((packed >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24) >= level;
    }

    /// @dev One clock for every action in a call: the wait since the latest VRF request (a
    ///      retry keeps its origin), or since the current day's reset when that is later, so the
    ///      reset's daily work starts at the base rate. Callers cannot move it: only requests and
    ///      the calendar do. Read before work; no worker writes it.
    function _minerRewardDueAt() internal view returns (uint256 due) {
        due = rngRequestTime;
        uint256 reset = block.timestamp - (block.timestamp - 82_620) % 1 days;
        if (reset > due) due = reset;
    }

    function _middayRefusal(bytes memory data) private pure returns (bool) {
        if (data.length != 4) return false;
        bytes4 selector;
        assembly ("memory-safe") { selector := mload(add(data, 32)) }
        return selector == IDegenerusGameRngModule.GasTooHigh.selector || selector == IDegenerusGameRngModule.PreResetWindow.selector
            || selector == IDegenerusGameRngModule.InsufficientLink.selector || selector == IDegenerusGameRngModule.NoPendingLootbox.selector
            || selector == IDegenerusGameRngModule.BelowThreshold.selector;
    }

    function _checkpointRefusal(bytes memory data) private pure returns (bool) {
        if (data.length == 0) return true;
        if (data.length != 4) return false;
        bytes4 selector = bytes4(data);
        return selector == MineFlipGas.InsufficientExecutionGas.selector
            || selector == EmptyRevert.selector || selector == NoWork.selector || selector == RngNotReady.selector;
    }

    function _revertWork(bytes memory data) private pure {
        if (data.length == 0 || (data.length == 4 && bytes4(data) == EmptyRevert.selector)) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
        assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
    }
}
