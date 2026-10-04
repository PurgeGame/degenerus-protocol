// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusGameAdvanceModule} from "../interfaces/IDegenerusGameModules.sol";
import {VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
import {DegenerusGameRngUtils} from "./DegenerusGameRngUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

interface IAdminLinkValue {
    function linkAmountToEth(uint256 amount) external view returns (uint256);
}
/// @notice Commitment boundary, publication and transport-only recovery.
/// @dev The miner engine selects when these actions run. A fresh request is last.
contract DegenerusGameRngModule is DegenerusGameRngUtils {
    error PreResetWindow();
    error InsufficientLink();
    error NoPendingLootbox();
    error BelowThreshold();
    error GasTooHigh();
    error RngNotReady();

    event Advance(uint8 stage, uint24 lvl);
    uint8 private constant STAGE_RNG_REQUESTED = 1;
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;
    uint48 private constant RNG_RETRY_TIMEOUT = 20 hours;

    /// @notice Publish accepted entropy before any read consumer, including tickets.
    function publishRng() external {
        if (address(this) != ContractAddresses.GAME || !_rngRequestActive() || _rngSessionPublished()
            || _currentRngWord() == 0 || _livenessTriggered()) revert RngNotReady();
        _finalizeLootboxRng(_currentRngWord());
        if (!rngLockedFlag) _setRngRequestActive(false);
    }

    /// @notice Final normal action: prepare, seal and request a fresh daily commitment.
    function requestDailyRng(uint24 day) external {
        if (address(this) != ContractAddresses.GAME || !_lootboxReadComplete() || _minerMaintenancePending()
            || _livenessTriggered() || day != _afkingResetDay || day <= dailyIdx || !subsFullyProcessed) revert RngNotReady();
        (bool ok, bytes memory result) = ContractAddresses.GAME_ADVANCE_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameAdvanceModule.prepareRequestBoundary.selector, day)
        );
        if (!ok) _revertDelegate(result);
        _swapTicketSlot();
        _swapFoilSlot();
        _freezePool();
        _sealRngWriteBuffer();
        rngRequestDay = day;
        rngGapApplied = false;
        rngRequestTime = uint48(block.timestamp);
        _rearmRngRetry();
        rngWordCurrent = RNG_WORD_WAITING;
        _setRngRequestActive(false);
        uint256 id = _requestVrfWord(VRF_REQUEST_CONFIRMATIONS);
        vrfRequestId = id;
        _setRngRequestActive(true);
        emit Advance(STAGE_RNG_REQUESTED, level);
    }

    /// @notice Admin transport-only retry: preserve kind, logical day, cohort and timeout origin.
    function retryRng() external {
        if (address(this) != ContractAddresses.GAME || msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();
        if (gameOver || _livenessTriggered() || !_rngRetryDue(uint48(block.timestamp))) revert RngNotReady();
        _setRngRequestActive(false);
        _spendRngRetry();
        uint256 id = _requestVrfWord(rngLockedFlag ? VRF_REQUEST_CONFIRMATIONS : VRF_MIDDAY_CONFIRMATIONS);
        vrfRequestId = id;
        _setRngRequestActive(true);
        emit Advance(STAGE_RNG_REQUESTED, level);
    }

    /// @notice Automatic request uses public pending work and never spends a miner's donation credit.
    function requestMinerRng() external {
        _requestLootboxRng(address(0));
    }

    /// @notice Explicit donor requests may spend the caller's LINK credit to waive value gates.
    function requestLootboxRng() external {
        _requestLootboxRng(msg.sender);
    }

    function _requestLootboxRng(address creditOwner) private {
        if (address(this) != ContractAddresses.GAME || _simulatedDayIndex() != dailyIdx
            || _minerMaintenancePending() || _livenessTriggered()) revert RngNotReady();
        // Completion already requires no daily lock, active request or mid-day ticket latch.
        if (!_lootboxReadComplete()) revert RngNotReady();
        // Decline to issue while the block is expensive: the fulfillment is billed at the
        // node's gas price a block or so later, so holding the request back while the
        // basefee is high bounds what a mid-day word can cost the subscription. Gates only
        // this path — the daily advance must run at any price — so a refused request just
        // leaves the pending boxes to the next daily word. Zero disables the gate.
        {
            uint256 maxBasefee = _lrRead(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK);
            if (maxBasefee != 0 && block.basefee > maxBasefee * 1 gwei) {
                revert GasTooHigh();
            }
        }
        uint48 nowTs = uint48(block.timestamp);
        uint24 currentDay = _simulatedDayIndexAt(nowTs);

        // Block only in the final minute before reset to avoid competing with daily jackpot RNG flow.
        if ((nowTs - 82_620) % 1 days >= 1 days - 1 minutes) revert PreResetWindow();
        // Block until today's daily RNG has been consumed and recorded.
        if (_recordedDailyWord(currentDay) == 0) revert RngNotReady();

        // A closed craps window registered on the write buffer is pending work for this
        // request. Read once: it picks the LINK reserve here and waives the pending-value
        // gates below, and both want the same answer.
        bool crapsWork = (lootboxRngPacked >> (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer())) & 1 != 0;

        // LINK balance check
        (uint96 linkBal,,,,) = vrfCoordinator.getSubscription(vrfSubscriptionId);
        if (linkBal < (crapsWork ? MIN_LINK_FOR_CRAPS_RNG : MIN_LINK_FOR_LOOTBOX_RNG)) {
            revert InsufficientLink();
        }

        // Threshold check: pending ETH must clear the owner-tunable threshold. This gates
        // only the mid-day fast path — the daily advance assigns the day's word to
        // the current index regardless, so pending boxes never wait past one cycle.
        uint256 pendingEth = _unpackMilliEthToWei(uint64(_lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK)));
        // Pending FLIP counts as work outstanding but adds nothing to the threshold: only ETH
        // pays for a mid-day word, so only ETH justifies buying one. A FLIP-denominated queue
        // resolves on the daily word instead, and anyone wanting it sooner can donate LINK for
        // the credit that waives this gate, or have an ETH buyer trigger it.
        bool noPending = pendingEth == 0 && _lrRead(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK) == 0;
        uint256 totalEthEquivalent = pendingEth;
        uint256 threshold = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
        // Donation credit waives both pending-value gates — an empty queue and a
        // below-threshold one alike. Charged only where one actually binds, so a request
        // that already clears them costs a holder nothing, and a caller holding no credit
        // still gets the specific gate as the revert. Ordered after the LINK floor above
        // so credit is never charged for a request the subscription cannot pay for.
        if (noPending || (threshold != 0 && totalEthEquivalent < threshold)) {
            // A pending craps window waives both: its word settles a table already holding
            // staked FLIP, which a lootbox queue it has no stake in cannot price. Checked before
            // the credit charge, so the caller pays no credit for it. Every other gate above
            // still binds, and the LINK floor binds at its own level rather than not at all.
            if (!crapsWork && (creditOwner == address(0) || !_tryChargeMiddayCredit(creditOwner))) {
                if (noPending) revert NoPendingLootbox();
                revert BelowThreshold();
            }
        }

        // Freeze ticket buffer: swap write→read so tickets purchased after
        // VRF delivery can't be resolved by this word. Any write-side key in the
        // trailing window may hold pending work (this path reverts while
        // rngLockedFlag is set, so the building level here is always level + 1
        // and the window is [level .. _mintCeiling()], level + 2 after a seal). Stranding is impossible either
        // way — the unified sweep keeps naming a retired level until both its
        // parities are empty — but the guard below protects DRAW ELIGIBILITY:
        // when the NEXT daily request caps the jackpot counter, a freeze window
        // opened now can cross into that final day via a stalled-word retry,
        // which cannot swap (the committed cohort occupies the read slot). The
        // stall-window buys would then materialize only after the level retires —
        // safe but drawless. Skipping the swap keeps the whole evening cohort
        // together on the write side for the final request's own commit, which
        // its chain drains BEFORE the final draw. The word still serves the
        // pending lootboxes.
        bool activated = _activateNextTickets();
        if (activated && _ticketQueueLength(_tqFarFutureKey(earlyTicketLevel)) != 0) {
            ticketsFullyProcessed = false;
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, MID_DAY_FUTURE_POOL);
        } else {
            // A latched one-day collapse (lastPurchaseDay with JACKPOT_TURBO set — an x0
            // evening latch, or an armed turbo whose advance chain broke on
            // ticket work before its request) is the same final-day shape: the
            // next daily request is the transition that collapses every draw
            // under its lock, so a swap here, crossed by a stall, would hold the
            // post-request cohort write-side until the level retires — safe but
            // drawless. Refused, the whole day's cohort stays together on the
            // write side for that request's own commit.
            bool lastSwapAhead = (lastPurchaseDay && (jackpotFlags & JACKPOT_TURBO) != 0)
                || (jackpotPhaseFlag && _isFinalJackpotDay(jackpotCounter, jackpotFlags));
            if (!lastSwapAhead) {
                // Foil packs ride the daily request only: a pending pack is not mid-day work
                // and the foil cohort does not move here.
                bool queuedWork;
                {
                    uint24 t = level;
                    uint24 end = _mintCeiling();
                    for (; t <= end;) {
                        if (_ticketQueueLength(_tqWriteKey(t)) > 0) {
                            queuedWork = true;
                            break;
                        }
                        unchecked {
                            ++t;
                        }
                    }
                }
                if (queuedWork && ticketsFullyProcessed) {
                    _swapTicketSlot();
                    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
                }
            }
        }

        // Seal before the coordinator call so completion is invalid throughout it.
        // A failed request rolls back this swap, queue resets and any credit charge.
        _sealRngWriteBuffer();
        rngRequestDay = 0;
        rngGapApplied = false;
        _setRngRequestActive(false);
        _setRngSessionPublished(false);
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = uint48(block.timestamp);
        _rearmRngRetry();
        uint256 id = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);
        vrfRequestId = id;
        _setRngRequestActive(true);
    }

    function _tryChargeMiddayCredit(address caller) private returns (bool charged) {
        uint256 balance = middayRngCredit[caller];
        // A zero balance never qualifies, even where basefee (and so the charge) is zero.
        if (balance == 0) return false;

        uint256 weiPerLink = IAdminLinkValue(ContractAddresses.ADMIN).linkAmountToEth(1 ether);
        if (weiPerLink == 0) return false;

        uint256 charge = (MIDDAY_RNG_BILLED_GAS * block.basefee * MIDDAY_RNG_CHARGE_MULT * 1 ether) / weiPerLink;
        if (balance < charge) return false;
        unchecked {
            balance -= charge;
        }
        middayRngCredit[caller] = balance;
        emit MiddayRngCreditSpent(caller, charge, balance);
        return true;
    }

    function _markTicketGenerationStart(uint24 lvl) private {
        if (ticketGenerationStartBlock[lvl] == 0) ticketGenerationStartBlock[lvl] = block.number;
    }

    function _activateNextTickets() private returns (bool activated) {
        // The sole caller checked liveness before any relevant state could change.
        uint24 nextLvl = level + 2;
        if (
            !jackpotPhaseFlag && ticketsFullyProcessed && earlyTicketLevel < nextLvl
                && _getNextPrizePool() > _prizePoolTarget(level + 1)
        ) {
            earlyTicketLevel = nextLvl;
            _markTicketGenerationStart(nextLvl);
            return true;
        }
    }

    function _rngRetryDue(uint48 ts) private view returns (bool) {
        return _rngRequestActive() && rngWordCurrent == RNG_WORD_WAITING && !_rngRetrySpent()
            && uint256(ts) >= uint256(rngRequestTime) + RNG_RETRY_TIMEOUT;
    }

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

    function _sealRngWriteBuffer() private {
        lootboxRngPacked &= ~((LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
            | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
    }

    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }
}
