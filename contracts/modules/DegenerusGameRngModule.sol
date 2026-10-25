// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {GameDailyInternals} from "./GameDailyInternals.sol";

import {DegenerusGameRngUtils} from "./DegenerusGameRngUtils.sol";
import {MineFlipGas} from "../libraries/MineFlipGas.sol";
import {BoundedCall} from "../libraries/BoundedCall.sol";
import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";
import {GameTimeLib} from "../libraries/GameTimeLib.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @notice Commitment boundary, publication and transport-only recovery.
/// @dev The miner engine selects when these actions run. A fresh request is last.
abstract contract DegenerusGameRngModule is GameDailyInternals, DegenerusGameRngUtils {
    error PreResetWindow();
    error InsufficientNativeBalance();
    error NoPendingLootbox();
    error BelowThreshold();
    error GasTooHigh();

    uint8 private constant STAGE_RNG_REQUESTED = 1;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 6;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;
    uint48 private constant RNG_RETRY_TIMEOUT = 20 hours;



    /// @notice Publish accepted entropy before any read consumer, including tickets.
    function publishRng_g4514() external {
        if (address(this) != ContractAddresses.GAME || !_rngRequestActive() || _rngSessionPublished()
            || _currentRngWord() == 0 || _livenessTriggered()) revert RngNotReady();
        _finalizeLootboxRng(_currentRngWord());
        if (!rngLockedFlag) _endRngSession();
    }



    /// @notice Final normal action: prepare, seal and request a fresh daily commitment.
    function requestDailyRng_g8190(uint24 day) external {
        MineFlipGas.Meter memory meter = MineFlipGas.fromCall(36);
        if (address(this) != ContractAddresses.GAME || !_lootboxReadComplete() || _minerMaintenancePending()
            || _livenessTriggered() || day != _afkingResetDay || day != dailyIdx + 1 || !dailyComplete || !_dailyRequestDue() || !subsFullyProcessed) revert RngNotReady();
        _refillVrfNative(meter, GasBounds.VRF_DAILY_REFILL_TAIL);
        _rngPrepareRequestBoundary(day);
        _swapTicketSlot();
        _swapFoilSlot();
        _sealHeroWagers(day);
        _freezePool();
        _sealRngWriteBuffer();
        rngRequestDay = day;
        dailyIdx = day;
        dailyComplete = false;
        lastDailyRequestWallDay = _wallDay();
        if (day < GameTimeLib.MAIN_LAUNCH_DAY) degenesisOpenedAt = uint48(block.timestamp);
        // No external call can observe different Game/Coinflip request indices:
        // the hook writes its mirror before it can call any other contract.
        coinflip.onDailyRequest(day);
        rngRequestTime = uint48(block.timestamp);
        _rearmRngRetry();
        rngWordCurrent = RNG_WORD_WAITING;
        // Daily completion already required the previous session closed.
        _setRngRequest(_requestVrfWord(VRF_REQUEST_CONFIRMATIONS, meter));
        emit Advance(STAGE_RNG_REQUESTED, level);
    }

    /// @notice Admin transport-only retry: preserve kind, logical day, cohort and timeout origin.
    function retryRng() external {
        if (address(this) != ContractAddresses.GAME || msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();
        if (gameOver || _livenessTriggered() || !_rngRetryDue(uint48(block.timestamp))) revert RngNotReady();
        // The replacement's ID supersedes the old request; a refused request reverts this call.
        _spendRngRetry();
        _setRngRequest(_requestVrfWord(rngLockedFlag ? VRF_REQUEST_CONFIRMATIONS : VRF_MIDDAY_CONFIRMATIONS, MineFlipGas.fromCall(4)));
        emit Advance(STAGE_RNG_REQUESTED, level);
    }



    /// @notice The mid-day request, reached only through mineRun (msg.sender is the miner).
    ///         The caller's donated credit pays the threshold gate when pending work sits
    ///         below it.
    function requestMinerRng_g4954() external {
        _requestLootboxRng(msg.sender, MineFlipGas.fromCall(4));
    }

    function _requestLootboxRng(address caller, MineFlipGas.Meter memory meter) private {
        if (address(this) != ContractAddresses.GAME || !dailyComplete || _dailyRequestDue()
            || _minerMaintenancePending() || _livenessTriggered()) revert RngNotReady();
        // Completion already requires no daily lock, active request or mid-day ticket latch.
        if (!_lootboxReadComplete()) revert RngNotReady();
        bool crapsWork = (lootboxRngPacked >> (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer())) & 1 != 0;
        // Decline to issue while the block is expensive: the fulfillment is billed at the
        // node's gas price a block or so later, so holding the request back while the
        // basefee is high bounds what a mid-day word can cost the subscription. Gates only
        // this path — the daily advance must run at any price — so a refused request just
        // leaves the pending boxes to the next daily word. Zero disables the gate.
        {
            uint256 maxBasefee = _lrRead(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK);
            if (maxBasefee != 0 && block.basefee > maxBasefee * (crapsWork ? 4 gwei : 1 gwei)) {
                revert GasTooHigh();
            }
        }
        uint48 nowTs = uint48(block.timestamp);
        uint24 currentDay = dailyIdx;

        // Block only in the final minute before reset to avoid competing with daily jackpot RNG flow.
        if ((nowTs - 82_620) % 1 days >= 1 days - 1 minutes) revert PreResetWindow();
        // Block until today's daily RNG has been consumed and recorded.
        if (_recordedDailyWord(currentDay) == 0) revert RngNotReady();

        // Pending-value gates. They gate only the mid-day fast path — the daily advance
        // assigns the day's word to the current index regardless, so pending boxes never wait
        // past one cycle. A pending craps window waives both with no charge: its word settles a
        // table already holding staked FLIP, which a lootbox queue cannot price. Every other
        // timing gate still binds.
        if (!crapsWork) {
            uint256 pendingEth = _unpackMilliEthToWei(uint64(_lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK)));
            // An empty queue has nothing for a word to settle, credit or not.
            if (pendingEth == 0 && _lrRead(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK) == 0) {
                revert NoPendingLootbox();
            }
            // The request that follows admits at its own floor and reserve.
            BoundedCall.admitFirst(meter, VRF_REQUEST_MIN_GAS, VRF_REQUEST_RESERVE);
            (bool readable, uint256 nativeBal) = _vrfNativeBalance(meter, VRF_REQUEST_MIN_GAS + VRF_REQUEST_RESERVE);
            if (!readable) revert ExternalRequestRefused();
            if (nativeBal < _vrfMinFulfillBalance() * 3 / 2) revert InsufficientNativeBalance();
            // Pending FLIP counts as work but adds nothing to the threshold: only ETH pays for a
            // mid-day word. Below the threshold the caller's donated credit pays the gate,
            // charged after the native floor so credit is never spent on a request the
            // subscription cannot pay for.
            uint256 threshold = _unpackMilliEthToWei(uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK)));
            if (threshold != 0 && pendingEth < threshold && !_tryChargeMiddayCredit(caller)) {
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
        bool activated = _rngActivateNextTickets();
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
        rngWordCurrent = RNG_WORD_WAITING;
        rngRequestTime = uint48(block.timestamp);
        _rearmRngRetry();
        // Read completion already required the previous session closed.
        _setRngRequest(_requestVrfWord(VRF_MIDDAY_CONFIRMATIONS, meter));
    }

    /// @notice Bank the donor's native request credit (Admin only).
    /// @dev A donation is a paying action and registers its donor under normal admission rules.
    function creditMiddayRng(address to, uint256 amount) external returns (uint32 id) {
        if (msg.sender != ContractAddresses.ADMIN) revert OnlyAdmin();
        (id, ) = _registerWallet(to, 0);
        uint256 balance = middayRngCredit[id] + amount;
        middayRngCredit[id] = balance;
        emit MiddayRngCredited(to, amount, balance);
    }

    function _tryChargeMiddayCredit(address caller) private returns (bool charged) {
        (bool covered, uint256 charge, uint256 balance, uint32 id) = _middayCreditCharge(caller);
        if (!covered) return false;
        unchecked {
            balance -= charge;
        }
        middayRngCredit[id] = balance;
        emit MiddayRngCreditSpent(caller, charge, balance);
        return true;
    }

    function _rngActivateNextTickets() private returns (bool activated) {
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

    function _requestVrfWord(uint16 confirmations, MineFlipGas.Meter memory meter) private returns (uint256 id) {
        bool ok;
        (ok, id) = _boundedVrfRequest(confirmations, meter);
        // Roll back the request's own swaps, credit charge and redemption close.
        // The miner catches this trusted worker refusal without discarding its prefix.
        if (!ok) revert ExternalRequestRefused();
    }

    /// @dev Daily and mid-day fresh requests only, never a retry: the sealed cohort and the
    ///      sDGNRS redemption batch closed here both settle on the word this request returns.
    function _sealRngWriteBuffer() private {
        _swapRngBuffers();
        _closeRedemptionBatch();
    }

}
