// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";

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
    function minerMaintenanceDueAt() external view returns (uint256);
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

    function minerAction() external view returns (uint8) {
        return uint8(_nextMinerAction());
    }

    function mineFlip() external {
        if (address(this) != ContractAddresses.GAME) revert E();
        uint256 rewardStart = gasleft();
        MinerAction first = _nextMinerAction();
        if (first == MinerAction.Idle) revert NoWork();
        if (first == MinerAction.Wait) revert RngNotReady();
        if (gasleft() < WORKER_BOUNDARY + RETURN_RESERVE + MineFlipGas.CHECK_RESERVE) {
            revert MineFlipGas.InsufficientExecutionGas();
        }
        bool rewardEligible = first != MinerAction.Terminal;
        uint256 rewardPrice = PriceLookupLib.priceForLevel(_activeTicketLevel());
        uint256 rewardDueAt = _minerRewardDueAt(first);
        MineFlipGas.Meter memory meter = MineFlipGas.start(MineFlipGas.available());
        bool moved;
        uint256 unpaidAttemptGas;

        // There are fewer than 32 category transitions. Workers own all unbounded queues.
        for (uint256 transitions; transitions < 32; ++transitions) {
            // Only reads separate the initial selection from the first dispatch.
            // Every later iteration must reselect after the preceding worker's changes.
            MinerAction action = transitions == 0 ? first : _nextMinerAction();
            if (action == MinerAction.Idle || action == MinerAction.Wait) break;
            if (!MineFlipGas.canRun(meter, WORKER_BOUNDARY, RETURN_RESERVE)) break;

            if (action == MinerAction.CertifyRead) {
                bool wasComplete = _rngComplete();
                _tryCompleteRng();
                if (!_rngComplete()) revert E();
                if (wasComplete) break;
                moved = true;
                continue;
            }

            if (action == MinerAction.PrepareSubscriptions && _afkingResetDay <= dailyIdx) {
                // Once pinned, a preparation day survives midnight and partial batches.
                _afkingResetDay = _simulatedDayIndex();
                _subCursor = 0;
                subsFullyProcessed = false;
                moved = true;
            }

            uint256 left = MineFlipGas.remaining(meter);
            if (left <= WORKER_BOUNDARY + RETURN_RESERVE) break;
            uint256 allowance = left - WORKER_BOUNDARY - RETURN_RESERVE;
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
                // Request/boundary work is indivisible; leave it for the next call if needed.
                if (!MineFlipGas.canRun(meter, GasBounds.RNG_REQUEST, RETURN_RESERVE + WORKER_BOUNDARY)) break;
                allowance = GasBounds.RNG_REQUEST;
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
                    callData = abi.encodeWithSelector(IsDGNRS.runRedemptionWork.selector, allowance);
                } else {
                    target = ContractAddresses.CRAPS;
                    externalWorker = true;
                    callData = action == MinerAction.Craps
                        ? abi.encodeWithSelector(IMinerCrapsWork.runCrapsReadWork.selector, _rngReadBuffer(), allowance)
                        : abi.encodeWithSelector(IMinerCrapsWork.runCrapsMaintenance.selector, allowance);
                }
            }

            uint256 forwarded = MineFlipGas.forwardable(MineFlipGas.remaining(meter), RETURN_RESERVE);
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
                unpaidAttemptGas = beforeCall - gasleft();
                break;
            }

            if (basicResult) {
                // Preserve the full Result ABI and bool validation without allocating a struct.
                (bool progressed, bool done,) = abi.decode(result, (bool, bool, uint256));
                if (action == MinerAction.Tickets && done) {
                    // An empty queue can still advance its one-time certificate.
                    if (!ticketsFullyProcessed) { ticketsFullyProcessed = true; progressed = true; }
                    if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) {
                        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                        progressed = true;
                    }
                }
                if (!progressed) {
                    // done describes eligibility/completion, not work performed.
                    // Never redispatch an unchanged worker, even if it says done.
                    unpaidAttemptGas = beforeCall - gasleft();
                    if (!moved) {
                        if (done) revert NoWork();
                        revert MineFlipGas.InsufficientExecutionGas();
                    }
                    break;
                }
                moved = true;
                if (!done) break;
            } else moved = true;
            // A request commits the next cohort; terminal stages own their continuation.
            if (action == MinerAction.Terminal || request) break;
        }

        // The only remaining zero-progress exit is a failed engine admission check.
        if (!moved) revert MineFlipGas.InsufficientExecutionGas();
        // This top-level meter starts with all available gas; worker allowance checks
        // retain the actual bounds. No successful call can overspend this initial amount.
        uint256 used = rewardStart - gasleft() - unpaidAttemptGas;
        uint256 reward;
        if (rewardEligible && !gameOver && used >= MineFlipGas.MIN_REWARDED_GAS) {
            // Price only compensation, after work and its gas measurement are complete.
            uint256 elapsed = rewardDueAt != 0 && block.timestamp > rewardDueAt ? block.timestamp - rewardDueAt : 0;
            (uint256 cap, uint256 multiplierBps) = _minerRewardTerms(elapsed);
            uint256 rate = block.basefee;
            if (rate > cap) rate = cap;
            reward = used * rate * PRICE_COIN_UNIT * multiplierBps / (rewardPrice * 10_000);
            if (reward != 0) {
                coinflip.creditFlip(msg.sender, reward);
                emit MinerBounty(MINER_BOUNTY_ADVANCE, msg.sender, reward);
            }
        }
        emit MinerWork(msg.sender, uint8(first), used, reward);
    }

    /// @dev Saturate before shifting or multiplying so arbitrary elapsed time cannot overflow.
    function _minerRewardTerms(uint256 elapsed) internal pure returns (uint256 capWei, uint256 multiplierBps) {
        uint256 steps = elapsed / 30 minutes;
        if (steps > 4) steps = 4;
        capWei = INITIAL_REWARD_BASEFEE_CAP << steps;
        multiplierBps = 7_500 + 5_000 * steps;
    }

    /// @dev Snapshot the oldest current obligation's anchor before workers mutate its state.
    ///      No-op/partial calls never write these clocks. Optional midday requests have no
    ///      authenticated first-pending timestamp and therefore use the initial reward rate.
    function _minerRewardDueAt(MinerAction action) internal view returns (uint256) {
        if (action >= MinerAction.Publish && action <= MinerAction.CertifyRead) {
            return _lrRead(LR_WORK_READY_SHIFT, LR_WORK_READY_MASK);
        }
        if (action == MinerAction.PrepareSubscriptions || action == MinerAction.RequestDaily) {
            // dailyIdx + 1 first becomes due at this reset, even if the first miner arrives late.
            return (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + dailyIdx) * 1 days + 82_620;
        }
        if (action == MinerAction.Maintenance) return IMinerCrapsWork(ContractAddresses.CRAPS).minerMaintenanceDueAt();
        return 0;
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
