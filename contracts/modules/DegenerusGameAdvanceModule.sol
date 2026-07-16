// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {
    IDegenerusGameGameOverModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule,
    IGameAfkingModule
} from "../interfaces/IDegenerusGameModules.sol";
import {
    IVRFCoordinator,
    VRFRandomWordsRequest
} from "../interfaces/IVRFCoordinator.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev GNRUS interface for level-transition governance resolution.
interface IGNRUSResolve {
    function pickCharity(uint24 level) external;
}

/// @dev Vault interface for the >50.1%-DGVE owner check (daily VRF retry head start).
interface IVaultOwnerCheck {
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Delegate-called module for advanceGame and VRF lifecycle handling.
contract DegenerusGameAdvanceModule is DegenerusGameStorage {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage
    error MidDayActive(); // A mid-day ticket-swap VRF request is already in flight; cannot start another lootbox RNG request.
    error PreResetWindow(); // Request blocked: within the 15-minute pre-reset window before the daily boundary to avoid competing with daily jackpot RNG.
    error InsufficientLink(); // VRF subscription LINK balance is below the minimum required for a lootbox RNG request.
    error NoPendingLootbox(); // No pending lootbox ETH or FLIP value; nothing to trigger a mid-day RNG request for.
    error BelowThreshold(); // Pending lootbox ETH-equivalent value is below the configured threshold required to trigger mid-day RNG.
    error RngInFlight(); // A VRF request is already in flight (rngRequestTime != 0); cannot start another.
    error NotTimeYet();
    error RngNotReady();
    // error RngLocked() — inherited from DegenerusGameStorage

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    event Advance(uint8 stage, uint24 lvl);
    event RewardJackpotsSettled(
        uint24 indexed lvl,
        uint256 futurePool,
        uint256 claimableDelta
    );

    // Advance stage constants (sequential, matching advanceGame flow)
    uint8 private constant STAGE_GAMEOVER = 0;
    uint8 private constant STAGE_RNG_REQUESTED = 1;
    uint8 private constant STAGE_TRANSITION_WORKING = 2;
    uint8 private constant STAGE_TRANSITION_DONE = 3;
    uint8 private constant STAGE_FUTURE_TICKETS_WORKING = 4;
    uint8 private constant STAGE_TICKETS_WORKING = 5;
    uint8 private constant STAGE_PURCHASE_DAILY = 6;
    uint8 private constant STAGE_ENTERED_JACKPOT = 7;
    uint8 private constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 private constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 private constant STAGE_JACKPOT_DAILY_STARTED = 10;
    /// @dev Partial-drain status for the afking process STAGE (mirrors
    ///      STAGE_TICKETS_WORKING): the subscriber set has not yet fully stamped
    ///      this cycle, so advance broke before rngGate and returns mult.
    uint8 private constant STAGE_SUBS_WORKING = 11;
    /// @dev A multi-day VRF-stall gap backfill ran this advance; the day's jackpot
    ///      distribution is deferred to the next advance so the backfill + jackpot never
    ///      share one tx (each stays under the per-tx gas ceiling). rngGate is idempotent on
    ///      re-entry (gapDays == 0 next call), dailyIdx is not yet advanced, so advanceDue()
    ///      stays true and the next advance pays the jackpot with the same frozen word.
    uint8 private constant STAGE_GAP_BACKFILLED = 12;
    /// @dev The funded subscriber set drained to its end this advance AND a multi-day VRF-stall
    ///      gap backfill is pending. rngGate (and its backfill) is deferred to the next advance so
    ///      the heavy completing subscriber chunk and the up-to-120-day backfill never share one tx
    ///      (the upstream mirror of STAGE_GAP_BACKFILLED). subsFullyProcessed is already set and
    ///      dailyIdx is not advanced, so advanceDue() stays true: the next advance runs the backfill
    ///      alone, then defers the jackpot via STAGE_GAP_BACKFILLED.
    uint8 private constant STAGE_SUBS_BACKFILL_DEFERRED = 13;
    event DailyRngApplied(
        uint24 day,
        uint256 rawWord,
        uint256 nudges,
        uint256 finalWord
    );
    event VrfCoordinatorUpdated(
        address indexed previous,
        address indexed current
    );
    event StEthStakeFailed(uint256 amount);

    /// @notice Emitted when DGNRS is rewarded to the top affiliate.
    /// @param affiliate Address of the top affiliate.
    /// @param level Level for which they were top affiliate.
    /// @param dgnrsAmount Amount of DGNRS paid from the affiliate pool.
    event AffiliateDgnrsReward(
        address indexed affiliate,
        uint24 indexed level,
        uint256 dgnrsAmount
    );

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+*/

    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    /// @notice GNRUS contract for governance resolution at level transitions
    IGNRUSResolve private constant charityResolve =
        IGNRUSResolve(ContractAddresses.GNRUS);
    /// @notice Jackpots contract — direct handle for skip-marker on losing flip days.
    IDegenerusJackpots private constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);
    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+*/

    uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 14 days;
    uint8 private constant JACKPOT_LEVEL_CAP = 5;
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;

    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;

    uint48 private constant DAILY_RNG_RETRY_TIMEOUT = 12 hours;
    uint48 private constant DAILY_RNG_RETRY_HEAD_START = 1 hours;

    uint32 private constant VAULT_PERPETUAL_ENTRIES = 16;
    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 3000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 1300;
    uint16 private constant NEXT_TO_FUTURE_BPS_DAY_STEP = 14;
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 2500;
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;
    uint16 private constant INSURANCE_SKIM_BPS = 100; // 1% of nextPool -> yieldAccumulator
    uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12500; // R > 1.25x triggers surcharge
    uint16 private constant OVERSHOOT_CAP_BPS = 3500; // 35% max surcharge
    uint16 private constant OVERSHOOT_COEFF = 4000; // numerator coefficient (0.40 in bps)
    uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000; // 80% total skim hard cap
    uint16 private constant ADDITIVE_RANDOM_BPS = 1000; // 0–10% additive random on bps
    bytes32 private constant FUTURE_KEEP_TAG = keccak256("future-keep");
    bytes32 private constant BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS");
    uint96 private constant MIN_LINK_FOR_LOOTBOX_RNG = 40 ether;
    uint48 private constant MIDDAY_RNG_STALL_TIMEOUT = 4 hours;

    /// @dev Per-call afking process-STAGE gas-weight budget. Every day is uniform: the streak is
    ///      computed on read from the Sub slot (no per-buy `playerQuestStates` STATICCALL, no
    ///      settle day), so there is a SINGLE budget. The STAGE consumes a gas-weight per
    ///      iteration — buys and finalizes are weighted by true marginal cost (a lootbox buy
    ///      ≈34k = `SUB_STAGE_LOOTBOX_WEIGHT` (10), a ticket buy ≈73k = `SUB_STAGE_TICKET_WEIGHT`
    ///      (21), a cross-contract sub-ending finalize / pass-evict / funding-kill ≈29k =
    ///      `SUB_STAGE_EVICT_WEIGHT` (8)) — and ends the chunk on accumulated weight, not raw
    ///      count, so EVERY composition (including a saturated all-evict swap-pop chunk) stays on
    ///      the <10M target with deep headroom to the 16.7M advance-chain ceiling. The lootbox and
    ///      ticket per-chunk counts are unchanged from the prior calibration; only the evict chunk
    ///      shrinks (≈500 → ≈312 finalizes) so a saturated all-evict crank stays below 10M.
    ///      A large set drains across several advanceGame calls.
    uint256 private constant SUB_STAGE_WEIGHT_BUDGET = 2500;

    /// @notice DGNRS reward for top affiliate: 1% of remaining affiliate pool.
    uint16 private constant AFFILIATE_POOL_REWARD_BPS = 100;

    /// @notice Max share of affiliate DGNRS pool segregated per level for claims (5%).
    uint16 private constant AFFILIATE_DGNRS_LEVEL_BPS = 500;

    /// @notice Advance game state. Called daily to process jackpots, mints, and phase transitions.
    ///         Returns mult: the day-epoch stall multiplier (1 base / 2 / 4 / 6 by stall; 0 on
    ///         the gameover path = no bounty). Standalone callers earn nothing — the unified
    ///         afking router pays the re-homed bounty (2x * mult) only when mult > 0.
    function advanceGame() external returns (uint8 mult) {
        mult = 1;
        uint48 ts = uint48(block.timestamp);
        uint24 wallDay = _simulatedDayIndexAt(ts);
        uint24 day = wallDay;
        // dailyIdx and rngLockedFlag are stable across every read below: their
        // only writers (_unlockRng, _finalizeRngRequest) execute after the last
        // use of these locals, or on paths that return before reaching it.
        uint24 dIdx = dailyIdx;
        bool locked = rngLockedFlag;
        // RNGREUSE guard: never resolve a NEW wall-day with a prior day's still-unsealed
        // VRF word. Two arms, both clamping this advance to the in-progress day so its
        // OWN word resolves it, with the next advance picking up the wall-day on a fresh
        // VRF request:
        // - Recorded: the in-progress day (dailyIdx+1) already recorded its word but was
        //   not yet sealed (_unlockRng deferred behind chunked drains / a pending daily
        //   jackpot / a phase transition) and the wall-clock has moved past it. rngGate
        //   returns the cached word, the deferred jackpot half stays on its Phase-1 word,
        //   and the afking box keeps a real word.
        // - Buffered: a delivered daily word (rngWordCurrent) is public from its
        //   fulfillment tx, and flip deposits stay open during the lock targeting
        //   wallDay+1 — so a word requested on day R may only resolve days <= R, whose
        //   deposit windows closed before the request fired. The clamp (dailyIdx+1 <= R)
        //   points the word at a day whose flips were committed before it existed.
        // A stall whose word was requested on the current wall-day stays unclamped:
        // rngGate's backfill handles it, and every backfilled day's deposits closed
        // before that word became public.
        if (day > dIdx + 1) {
            if (rngWordByDay[dIdx + 1] != 0) {
                day = dIdx + 1;
            } else if (
                locked &&
                rngWordCurrent != 0 &&
                rngRequestTime != 0 &&
                _simulatedDayIndexAt(rngRequestTime) < day
            ) {
                day = dIdx + 1;
            }
        }
        bool inJackpot = jackpotPhaseFlag;
        uint24 lvl = level;
        uint24 psd = purchaseStartDay;
        // Turbo: if target already met on day ≤1, flag now so the upcoming
        // _requestRng does the level pre-increment (matching normal
        // lastPurchaseDay flow). Skipped when rngLockedFlag is set because
        // rngGate will take the fresh-word path instead of _requestRng, so
        // the level pre-increment would be missed and the (lastPurchase &&
        // rngLockedFlag) ternary below would compute purchaseLevel = 0.
        // A VRF-stall backfill credits the gap to purchaseStartDay while the RNGREUSE clamp
        // re-walks already-recorded historical days. Such a replay may have `day < psd` (making
        // the subtraction unsafe) and, even after it reaches psd, must not arm turbo: its word is
        // already cached, so rngGate would skip the request that performs the level promotion.
        // Turbo is therefore restricted to the real wall day with an unrequested word.
        if (
            !inJackpot &&
            !lastPurchaseDay &&
            !locked &&
            day == wallDay &&
            day >= psd &&
            rngWordByDay[day] == 0
        ) {
            uint32 purchaseDays = day - psd;
            if (
                purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]
            ) {
                lastPurchaseDay = true;
                compressedJackpotFlag = 2;
            }
        }
        bool lastPurchase = (!inJackpot) && lastPurchaseDay;
        // Level already incremented at RNG request when lastPurchase=true
        uint24 purchaseLevel = (lastPurchase && locked) ? lvl : lvl + 1;
        // The VRF-death deadman also enters here during jackpot / last-purchase, where the
        // normal !inJackpot && !lastPurchase gate would otherwise skip the game-over path.
        if ((!inJackpot && !lastPurchase) || _vrfDeadmanFired()) {
            (bool goReturn, uint8 goStage) = _handleGameOverPath(day, lvl);
            if (goReturn) {
                // Gameover path: advance ran but earns NO router bounty (the flip-credit
                // coin is worthless at gameover) — return mult = 0 so mintFlip pays nothing.
                emit Advance(goStage, lvl);
                return 0;
            }
        }

        // --- Mid-day path: same-day queue draining ---
        if (day == dIdx) {
            // Step 1: Finish draining the read slot if not yet fully processed
            if (!ticketsFullyProcessed) {
                // If mid-day ticket swap is pending, wait for VRF word before
                // processing. One packed read covers both the flag and the index.
                uint256 lrPacked = lootboxRngPacked;
                if (((lrPacked >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK) != 0) {
                    uint256 word = lootboxRngWordByIndex[
                        uint48((lrPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK) - 1
                    ];
                    if (word == 0) revert RngNotReady();
                }

                uint24 rk = _tqReadKey(purchaseLevel);
                // The draw is gated on BOTH the normal queue AND the foil drain: keep
                // draining while the normal queue OR a sealed-but-un-drained foil bucket
                // (resolved on leftover budget) remains, else foil's boosted entries
                // silently under-resolve into the jackpot.
                if (
                    ticketQueue[rk].length > 0 ||
                    _foilDrainPending()
                ) {
                    (
                        bool ticketWorked,
                        bool ticketsFinished
                    ) = _runProcessTicketBatch(purchaseLevel);
                    if (ticketWorked || !ticketsFinished) {
                        if (ticketsFinished) {
                            ticketsFullyProcessed = true;
                            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                        }
                        emit Advance(STAGE_TICKETS_WORKING, lvl);
                        // Mid-day partial-drain: mult = 1 (no escalation).
                        return mult;
                    }
                }
            }

            revert NotTimeYet();
        }

        // Day-epoch stall multiplier (new-day path only), written straight into the `mult`
        // return so the router scales the re-homed advance bounty: 2x after 20 min, 4x after
        // 1 hour, 6x after 2 hours. `mult` defaults to 1 (set at function entry).
        {
            uint256 dayStart = (uint256(day - 1) +
                ContractAddresses.DEPLOY_DAY_BOUNDARY) *
                1 days +
                82_620;
            uint256 elapsed = ts - dayStart;
            if (elapsed >= 2 hours) {
                mult = 6;
            } else if (elapsed >= 1 hours) {
                mult = 4;
            } else if (elapsed >= 20 minutes) {
                mult = 2;
            }
        }

        uint8 stage;
        do {
            // --- Daily drain gate: ensure read slot is fully processed before RNG ---
            if (!ticketsFullyProcessed) {
                uint24 preRk = _tqReadKey(purchaseLevel);
                // The draw is gated on BOTH the normal queue AND the foil drain: keep
                // draining while the normal queue OR a sealed-but-un-drained foil bucket
                // remains.
                if (
                    ticketQueue[preRk].length > 0 ||
                    _foilDrainPending()
                ) {
                    uint48 preIdx = uint48(
                        _lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)
                    ) - 1;
                    if (lootboxRngWordByIndex[preIdx] == 0) {
                        uint256 cw = rngWordCurrent;
                        if (cw == 0) {
                            // A mid-day lootbox request (rngLockedFlag == false) whose own VRF
                            // word never arrived has bled past the day boundary. If it has stalled
                            // past MIDDAY_RNG_STALL_TIMEOUT, abandon it and promote it to this
                            // day's daily request: _requestRng re-fires VRF under the daily lock,
                            // and its isRetry path preserves the reserved index so the fresh daily
                            // word seals the day AND finalizes this bucket (preIdx) — just as the
                            // mid-day word would have. The stale mid-day requestId stops matching
                            // in rawFulfillRandomWords. Then handle the ticket buffer like a normal
                            // daily request: if the read slot is drained, swap the write slot in so
                            // its tickets also resolve against this word; otherwise the read slot
                            // still holds the undrained mid-day batch, so freeze only and let it
                            // drain against the new word next advance.
                            if (
                                !rngLockedFlag &&
                                rngRequestTime != 0 &&
                                ts - rngRequestTime >= MIDDAY_RNG_STALL_TIMEOUT
                            ) {
                                _requestRng(lastPurchase, purchaseLevel);
                                if (ticketQueue[preRk].length == 0) {
                                    _swapAndFreeze();
                                } else {
                                    _freezePool();
                                }
                                stage = STAGE_RNG_REQUESTED;
                                break;
                            }
                            revert RngNotReady();
                        }
                        unchecked {
                            cw += totalFlipReversals;
                        }
                        // preIdx is the current lootbox index and its word slot
                        // is known-empty here, so store and emit directly.
                        lootboxRngWordByIndex[preIdx] = cw;
                        emit LootboxRngApplied(preIdx, cw, vrfRequestId);
                    }
                    (bool preWorked, bool preFinished) = _runProcessTicketBatch(
                        purchaseLevel
                    );
                    if (preWorked || !preFinished) {
                        stage = STAGE_TICKETS_WORKING;
                        break;
                    }
                }
                ticketsFullyProcessed = true;
                // Release the mid-day latch when a swapped ticket batch finishes draining
                // on the new-day path: the same-day release runs only while day == dIdx, so a
                // batch whose drain crosses the day boundary completes here instead. Guarded so
                // the daily-swapped drain (latch already clear) skips the write.
                if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) {
                    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                }
            }

            // --- Afking process STAGE: stamp the funded subscriber set BEFORE the day
            // requests its RNG. Inserted on the new-day path only, after the daily
            // ticket-drain gate and strictly before rngGate. The mid-day same-day path
            // returns earlier, so the STAGE never runs mid-day. Chunked by SUB_STAGE_BATCH across advance calls
            // (BUY_BATCH-style) so a large set stays under the 16.7M advance-chain
            // ceiling — mirrors the ticketsFullyProcessed partial-drain discipline:
            // break + return mult while !subsFullyProcessed; set true only at cursor
            // end; then fall through to rngGate.
            //
            // The STAGE runs strictly pre-RNG (before rngGate writes the day's word), so
            // rngWordByDay[processDay] is uncommitted when a sub is stamped — the
            // load-bearing freeze property. The box reads the LIVE level +
            // rngWordByDay[lastAutoBoughtDay] at open.
            //
            // Forward-looking per-day reset: the first time the advance enters a new `day`,
            // flip the drain gate + cursor BEFORE that day's STAGE runs. subsFullyProcessed
            // stays true after a day's STAGE completes (it means "afking done for that day")
            // until the next day flips it here. Stamped to `day` at the reset, so it fires
            // exactly once per day and never re-fires within the day (independent of when
            // dailyIdx catches up in _unlockRng).
            if (_afkingResetDay != day) {
                _afkingResetDay = day;
                subsFullyProcessed = false;
                _subCursor = 0;
            }
            if (!subsFullyProcessed) {
                if (_subscribers.length != 0) {
                    _runSubscriberStage(day);
                    if (_subCursor < _subscribers.length) {
                        // Partial drain: more subs remain this cycle — break before
                        // rngGate and return mult (no RNG request yet). subsFullyProcessed
                        // stays false; the next advance call resumes the cursor.
                        stage = STAGE_SUBS_WORKING;
                        break;
                    }
                    // The set drained to its end THIS tx — a heavy completing chunk (up to the
                    // weight budget, or a saturated all-evict swap-pop chunk that empties the set
                    // in one pass). If a multi-day VRF-stall gap backfill is ALSO pending, defer
                    // rngGate to the next advance so the completing subscriber chunk and the
                    // up-to-120-day backfill never share one tx and blow the per-tx gas ceiling.
                    // Upstream mirror of the STAGE_GAP_BACKFILLED decouple: same gate rngGate uses
                    // to enter _backfillGapDays. dailyIdx is unadvanced and rngWordByDay[day] is
                    // unset, so advanceDue() stays true and the next advance runs the (idempotent)
                    // rngGate — it backfills, then defers the jackpot via STAGE_GAP_BACKFILLED.
                    subsFullyProcessed = true;
                    if (
                        rngWordCurrent != 0 &&
                        rngRequestTime != 0 &&
                        day > dIdx + 1 &&
                        rngWordByDay[dIdx + 1] == 0
                    ) {
                        stage = STAGE_SUBS_BACKFILL_DEFERRED;
                        break;
                    }
                } else {
                    // Empty set — nothing was stamped, no heavy chunk to segregate. Fall through
                    // to rngGate (a lone backfill stays under the per-tx ceiling).
                    subsFullyProcessed = true;
                }
            }

            // RNG: use existing word or request new one. Precompute the day's coinflip reward
            // bonus from the frozen level: +2 on a bonus day (level 0 or a level's first jackpot
            // day), +6 on a post-BAF x0-level first-jackpot-day (levels 10, 20, 30, …; level 0
            // is excluded — no BAF precedes it), 0 otherwise. Sized so a recycling (auto-rebuy)
            // player nets ~99.9% / ~101.9% RTP once the 0.75% recycle bonus compounds in.
            bool bonusDay = (inJackpot && jackpotCounter == 0) || lvl == 0;
            uint8 coinflipBonus = bonusDay
                ? (lvl != 0 && lvl % 10 == 0 ? 6 : 2)
                : 0;
            (uint256 rngWord, uint32 gapDays) = rngGate(
                ts,
                day,
                purchaseLevel,
                lastPurchase,
                coinflipBonus
            );
            psd += uint24(gapDays);
            if (rngWord == 1) {
                _swapAndFreeze();
                stage = STAGE_RNG_REQUESTED;
                break;
            }

            // Decouple a multi-day VRF-stall gap backfill from the day's jackpot distribution:
            // if rngGate just backfilled a gap (gapDays != 0), defer everything downstream (the
            // phase transition + the up-to-305-winner daily jackpot) to the next advance so the
            // backfill and the jackpot never execute in one tx (each stays under the per-tx gas
            // ceiling). rngGate is idempotent (rngWordByDay[day] is now set -> gapDays == 0 next
            // call) and dailyIdx is not yet advanced (no _unlockRng reached), so advanceDue() stays
            // true and the next advance pays the jackpot with the same frozen word. The break
            // returns mult so the keeper is paid for the backfill work (mirrors the partial drains).
            if (gapDays != 0) {
                stage = STAGE_GAP_BACKFILLED;
                break;
            }

            // Phase transition housekeeping + FF promotion
            if (phaseTransitionActive) {
                // Drain the one FF level that entered near-future at this level transition.
                // At new level L, the boundary moved from >L+4 to >L+5, making L+5 near-future.
                // No new FF entries can arrive at L+5 (tickets targeting it now route to write key).
                // purchaseLevel = level + 1, so the FF level is purchaseLevel + 4 = level + 5.
                uint24 ffLevel = purchaseLevel + 4;
                bool resumingFF = (ticketLevel ==
                    (ffLevel | TICKET_FAR_FUTURE_BIT));
                if (!resumingFF) {
                    _processPhaseTransition(purchaseLevel);
                    // Set up FF drain — ticketLevel signals we've completed transition housekeeping
                    ticketLevel = ffLevel | TICKET_FAR_FUTURE_BIT;
                    ticketCursor = 0;
                }
                (bool ffWorked, bool ffFinished, ) = _processFutureTicketBatch(
                    ffLevel,
                    rngWord
                );
                if (ffWorked || !ffFinished) {
                    // A batch that both WORKED and FINISHED clears ticketLevel (the resume marker)
                    // inside processFutureTicketBatch, yet we still break here for the per-tx
                    // one-batch gas discipline. Re-assert the marker so the next advance's
                    // resumingFF check skips the (already-completed) transition housekeeping —
                    // otherwise _processPhaseTransition re-runs and double-credits the SDGNRS/VAULT
                    // perpetual jackpot entries. On that next advance the FF queue is empty, so the
                    // batch returns finished with no work and the transition completes cleanly.
                    if (ffFinished) {
                        ticketLevel = ffLevel | TICKET_FAR_FUTURE_BIT;
                    }
                    stage = STAGE_TRANSITION_WORKING;
                    break;
                }
                phaseTransitionActive = false;
                _unlockRng(day);
                purchaseStartDay = day;
                jackpotPhaseFlag = false;
                stage = STAGE_TRANSITION_DONE;
                break;
            }

            // Process near-future ticket queues before daily draws
            // to include fresh lootbox-driven tickets
            if (!dailyJackpotCoinTicketsPending) {
                if (
                    !_prepareFutureTickets(
                        inJackpot ? lvl : purchaseLevel,
                        rngWord
                    )
                ) {
                    stage = STAGE_FUTURE_TICKETS_WORKING;
                    break;
                }
            }

            // Process current level tickets:
            // Purchase phase processes purchaseLevel (= level+1) where new tickets route.
            // Jackpot phase processes level where jackpot-phase tickets route.
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(
                inJackpot ? lvl : purchaseLevel
            );
            if (ticketWorked || !ticketsFinished) {
                stage = STAGE_TICKETS_WORKING;
                break;
            }
            ticketsFullyProcessed = true; // set before jackpot/phase logic

            // === PURCHASE PHASE ===
            if (!inJackpot) {
                // Pre-target: daily jackpots while building prize pool.
                // lastPurchase equals lastPurchaseDay here (read after the turbo
                // write, inside !inJackpot, with no writer on the path between).
                if (!lastPurchase) {
                    if (purchaseLevel == 1) {
                        // Self-call into GAME (which delegatecalls the jackpot
                        // module) so msg.sender == address(this) passes the
                        // module's OnlyGame check.
                        IDegenerusGame(address(this)).emitDailyWinningTraits(
                            1,
                            rngWord,
                            1
                        );
                        _payDailyCoinJackpot(1, rngWord, 1, 1);
                        uint256 saltedRng = uint256(
                            keccak256(
                                abi.encodePacked(rngWord, BONUS_TRAITS_TAG)
                            )
                        );
                        _payDailyCoinJackpot(1, saltedRng, 2, 5);
                    } else {
                        payDailyJackpot(false, purchaseLevel, rngWord);
                        _payDailyCoinJackpot(
                            purchaseLevel,
                            rngWord,
                            purchaseLevel + 1,
                            purchaseLevel + 4
                        );
                    }
                    bool targetMet = _getNextPrizePool() >=
                        levelPrizePool[purchaseLevel - 1];
                    // Do not latch on an RNGREUSE replay day. Its NEXT day may also have a cached
                    // backfill word, which would let rngGate bypass the sole `level = lvl` writer in
                    // _finalizeRngRequest and enter jackpot one level behind. Latch only after the
                    // walk reaches the real wall day; the following calendar day then necessarily
                    // takes the normal request path and promotes the level. `day >= psd` also makes
                    // the compressed-phase subtraction safe after the death-clock adjustment.
                    if (targetMet && day == wallDay && day >= psd) {
                        lastPurchaseDay = true;
                        if (day - psd <= 3) {
                            compressedJackpotFlag = 1;
                        }
                    }
                    _unlockRng(day);
                    stage = STAGE_PURCHASE_DAILY;
                    break;
                }

                // Activate next-level tickets before jackpot phase
                {
                    uint24 nextLevel = purchaseLevel + 1;
                    (
                        bool futureWorked,
                        bool futureFinished,

                    ) = _processFutureTicketBatch(nextLevel, rngWord);
                    if (futureWorked || !futureFinished) {
                        stage = STAGE_FUTURE_TICKETS_WORKING;
                        break;
                    }
                }

                // Consolidate prize pools for level transition
                levelPrizePool[purchaseLevel] = _getNextPrizePool();
                _distributeYieldSurplus(rngWord);
                _consolidatePoolsAndRewardJackpots(
                    lvl,
                    purchaseLevel,
                    day,
                    rngWord,
                    psd
                );

                // Transition to jackpot phase
                jackpotPhaseFlag = true;

                lastPurchaseDay = false;

                // Roll level quest at level transition so it's active during jackpot phase
                quests.rollLevelQuest(rngWord);

                // Do not unlock here: allows day-1 jackpot processing to run on
                // the same day as the transition day.
                stage = STAGE_ENTERED_JACKPOT;
                break;
            }

            // === JACKPOT PHASE ===

            // Complete coin+ticket distribution
            if (dailyJackpotCoinTicketsPending) {
                payDailyJackpotCoinAndTickets(rngWord);
                if (jackpotCounter >= JACKPOT_LEVEL_CAP) {
                    _endPhase(lvl);
                    stage = STAGE_JACKPOT_PHASE_ENDED;
                    break;
                }
                _unlockRng(day);
                stage = STAGE_JACKPOT_COIN_TICKETS;
                break;
            }

            // Fresh daily jackpot
            payDailyJackpot(true, lvl, rngWord);
            stage = STAGE_JACKPOT_DAILY_STARTED;
        } while (false);

        // New-day advance leg: `mult` already holds the day-epoch stall ladder (1/2/4/6)
        // the router scales the re-homed bounty by.
        emit Advance(stage, lvl);
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  Deploy-only VRF setup called from the ContractAddresses.ADMIN constructor.            |
      |  Post-deploy VRF changes use updateVrfCoordinatorAndSub (emergency rotation).          |
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

    /*+======================================================================+
      |                    GAMEOVER / LIVENESS GUARDS                        |
      +======================================================================+*/

    /// @dev Handles gameover state and liveness guard checks.
    ///      Returns (shouldReturn, stage). shouldReturn=true means advanceGame
    ///      should emit `stage` and exit. Stages used:
    ///         STAGE_GAMEOVER -- normal game-over completion or final sweep
    ///         STAGE_TICKETS_WORKING -- partial best-effort drain; caller retries
    function _handleGameOverPath(
        uint24 day,
        uint24 lvl
    ) private returns (bool shouldReturn, uint8 stage) {
        // Liveness guard: prevent permanent lockup if game is abandoned.
        // Uses the shared _livenessTriggered() helper so purchase paths (in
        // DegenerusGameMintModule) can reuse the same predicate to block new
        // purchases during the multi-tx game-over drain sequence.
        bool ok;
        bytes memory data;

        // gameOver check precedes liveness so the post-gameover final-sweep path
        // stays reachable after the VRF-dead path latches gameOver with day-math
        // still below the 120/365 threshold (e.g., VRF breaks on day 14).
        if (gameOver) {
            // Post-gameover: check for final sweep (1 month after gameover)
            (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameGameOverModule.handleFinalSweep.selector
                )
            );
            if (!ok) _revertDelegate(data);
            return (true, STAGE_GAMEOVER);
        }

        // _livenessTriggered now folds in the VRF-death deadman, so it returns true here even
        // during jackpot / last-purchase when the game has been stalled past the deadman.
        if (!_livenessTriggered()) return (false, 0);

        // Safety: don't activate game over if nextPool requirement is already met — but the
        // VRF-death deadman overrides it: a permanently-stalled game must drain even if its pool
        // target reads as met.
        if (
            lvl != 0 &&
            _getNextPrizePool() >= levelPrizePool[lvl] &&
            !_vrfDeadmanFired()
        ) {
            return (false, 0);
        }

        // Drain and payout must use the same phase-correct level. Snapshot it before entropy
        // acquisition: _gameOverEntropy leaves the phase flags intact, and a terminal fallback
        // must never choose a bucket dynamically from attacker-populated queue state.
        uint24 drainLevel = _gameOverTicketLevel(lvl);

        // Freeze an otherwise-unsnapped terminal cohort BEFORE its entropy is requested/chosen.
        // When an RNG boundary already exists, the read buffer is the committed cohort and the
        // write buffer contains later tickets; never promote that write buffer into this terminal
        // draw. The liveness gate is already active, so after a safe initial swap no player buy can
        // enter the new write buffer during the multi-tx drain. Foil buckets carry their own sealed
        // resolve-day entropy and may be drained without promoting the normal-ticket write buffer.
        uint256 dayWord = rngWordByDay[day];
        bool entropyCommitted = dayWord != 0 ||
            rngWordCurrent != 0 ||
            vrfRequestId != 0 ||
            rngLockedFlag ||
            prizePoolFrozen ||
            _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0;
        bool readPending = ticketQueue[_tqReadKey(drainLevel)].length != 0;
        bool writePending = ticketQueue[_tqWriteKey(drainLevel)].length != 0;
        if (readPending) {
            // The selected read queue is already the oldest committed snapshot. Trust the queue
            // itself over a stale-true completion flag and resume it without touching write state.
            ticketsFullyProcessed = false;
        } else if (writePending && !entropyCommitted) {
            // No selected read cohort and no entropy boundary: freeze the abandonment cohort now.
            _swapTicketSlot();
        } else if (_foilDrainPending()) {
            ticketsFullyProcessed = false;
        }

        // Pre-gameover: acquire RNG, drain the committed cohort, then unlock.
        if (dayWord == 0) {
            uint256 rngWord = _gameOverEntropy(
                uint48(block.timestamp),
                day,
                lvl,
                lastPurchaseDay
            );
            if (rngWord == 1 || rngWord == 0) return (true, STAGE_GAMEOVER);
        }

        // Best-effort drain of the single RNG-committed ticket snapshot. One batch runs per tx
        // (mirroring the normal daily drain), and a finishing batch still breaks so the terminal
        // jackpot executes in its OWN transaction below the EIP-7825 per-tx gas ceiling.
        //
        // FUND-RELEASE FALLBACK: a catastrophic delegatecall revert (e.g., an
        // unforeseen error in ticket processing) is swallowed so game-over
        // continues straight to handleGameOverDrain -- undrained tickets forfeit
        // trait-bucket eligibility, but terminal fund release is never blocked.
        //
        if (!ticketsFullyProcessed) {
            (bool dOk, bytes memory dData) = ContractAddresses
                .GAME_MINT_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameMintModule.processTicketBatch.selector,
                        drainLevel
                    )
                );
            if (dOk && dData.length >= 64) {
                (bool finished, ) = abi.decode(dData, (bool, bool));
                if (!finished) {
                    // Read slot has more entries -- retry next tx.
                    return (true, STAGE_TICKETS_WORKING);
                }
                // The committed read snapshot is complete. Do NOT swap in the later write buffer:
                // those tickets may have been purchased after the terminal word was committed.
                ticketsFullyProcessed = true;
                return (true, STAGE_TICKETS_WORKING);
            }
            // dOk=false -> swallow, fall through to handleGameOverDrain.
        }

        (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameGameOverModule.handleGameOverDrain.selector,
                day
            )
        );
        if (!ok) _revertDelegate(data);
        _unlockRng(day);
        return (true, STAGE_GAMEOVER);
    }

    /*+======================================================================+
      |                           LEVEL END                                  |
      +======================================================================+*/
    function _endPhase(uint24 lvl) private {
        phaseTransitionActive = true;
        if (lvl % 100 == 0) {
            levelPrizePool[lvl] = _getFuturePrizePool() / 3;
        }
        jackpotCounter = 0;
        compressedJackpotFlag = 0;
    }

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • ContractAddresses.GAME_DECIMATOR_MODULE - Decimator claim credits and lootbox payouts                       |
      |  • ContractAddresses.GAME_MINT_MODULE     - Mint data recording, airdrop multipliers                           |
      |  • ContractAddresses.GAME_WHALE_MODULE    - Whale pass purchases and whale pass claims                         |
      |  • ContractAddresses.GAME_JACKPOT_MODULE  - Jackpot calculations and payouts                                   |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant.                                                    |
      +================================================================================================================+*/

    /// @dev Reward the top affiliate for a level and segregate per-level DGNRS allocation.
    ///      After the 1% top-affiliate draw, snapshots 5% of the remaining affiliate
    ///      pool into the allocation half of levelDgnrsPacked[lvl]. Affiliate scores
    ///      always route to level + 1 during gameplay, so at transition time (when level
    ///      becomes lvl), all scores at index lvl are frozen — new scores go to lvl + 1.
    ///      Claims read the allocation half of levelDgnrsPacked[currLevel] directly.
    ///      Unclaimed tokens are never physically moved — they remain in the pool
    ///      and naturally roll into the next level's snapshot.
    function _rewardTopAffiliate(uint24 lvl) private {
        (address top, ) = affiliate.affiliateTop(lvl);

        uint256 poolBalance = dgnrs.poolBalance(
            IsDGNRS.Pool.Affiliate
        );
        if (top != address(0)) {
            uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) /
                10_000;
            uint256 paid = dgnrs.transferFromPool(
                IsDGNRS.Pool.Affiliate,
                top,
                dgnrsReward
            );
            emit AffiliateDgnrsReward(top, lvl, paid);
            // transferFromPool returns the exact pool decrement (clamped to the
            // available balance, zero on the empty-pool path), so the remaining
            // pool is derivable without a second external read.
            poolBalance -= paid;
        }

        // Segregate 5% of remaining affiliate pool for per-affiliate claims.
        // Scores at index lvl are frozen (new scores go to lvl + 1).
        _setLevelDgnrsAllocation(
            lvl,
            (poolBalance * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000
        );
    }

    /// @dev Distribute yield surplus via JackpotModule delegatecall.
    ///      Runs while frozen, before pool consolidation. The obligations sum
    ///      includes both live pools and the pending buffer, so freeze-window
    ///      revenue (which routes to pending) is never misread as yield surplus.
    function _distributeYieldSurplus(uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.distributeYieldSurplus.selector,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Drive one chunk of the afking process STAGE via GAME_AFKING_MODULE
    ///      delegatecall (the module operates on this contract's storage in-context —
    ///      the subscriber set / cursors / Sub stamps all live in
    ///      DegenerusGameStorage). For each funded sub the callee STAMPS the per-sub box
    ///      fields (lootbox mode) or QUEUES whole tickets directly via _queueEntriesScaled (ticket mode),
    ///      sets the lastAutoBoughtDay marker, debits afkingFunding (claimablePool in
    ///      tandem, fail loud — no error-swallowing valve), and advances _subCursor until the
    ///      accumulated gas-weight reaches SUB_STAGE_WEIGHT_BUDGET; it persists _subCursor
    ///      itself. The STAGE caller decides drained-vs-partial by re-reading _subCursor against
    ///      _subscribers.length. No per-day epoch is written — the box reads the LIVE level +
    ///      rngWordByDay[day] at open.
    /// @param processDay The boundary-pinned process day (seeds the open).
    function _runSubscriberStage(uint24 processDay) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_AFKING_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IGameAfkingModule.processSubscriberStage.selector,
                    processDay,
                    SUB_STAGE_WEIGHT_BUDGET
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev All pool transition logic: time-based future take, pool consolidation,
    ///      coinflip credit, reward jackpots (BAF/Decimator), and future→next drawdown.
    ///      All intermediate pool values computed in memory; storage written in batches.
    function _consolidatePoolsAndRewardJackpots(
        uint24 lvl,
        uint24 purchaseLevel,
        uint24 day,
        uint256 rngWord,
        uint24 psd
    ) private {
        (uint128 packedNext, uint128 packedFuture) = _getPrizePools();
        uint256 memFuture = packedFuture;
        uint256 memCurrent = _getCurrentPrizePool();
        uint256 memNext = packedNext;
        uint256 memYieldAcc = yieldAccumulator;

        // --- Time-based future take (batched) ---
        {
            uint32 start = psd + 7;
            uint32 elapsed = day > start ? day - start : 0;

            uint256 bps = _nextToFutureBps(elapsed, purchaseLevel);
            if (purchaseLevel % 10 == 9) bps += NEXT_TO_FUTURE_BPS_X9_BONUS;

            uint256 lastPool = levelPrizePool[purchaseLevel - 1];

            // Ratio adjust: ±4% based on future/next ratio (target 2:1)
            uint256 ratioPct = (memFuture * 100) / memNext;
            if (ratioPct < 200) {
                bps += (200 - ratioPct) * 2;
            } else {
                uint256 penalty = ratioPct - 200;
                penalty = penalty > 400 ? 400 : penalty;
                bps = penalty >= bps ? 0 : bps - penalty;
            }

            // Overshoot surcharge
            if (lastPool != 0) {
                uint256 rBps = (memNext * 10_000) / lastPool;
                if (rBps > OVERSHOOT_THRESHOLD_BPS) {
                    uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;
                    uint256 surcharge = (excess * OVERSHOOT_COEFF) /
                        (excess + 10_000);
                    if (surcharge > OVERSHOOT_CAP_BPS)
                        surcharge = OVERSHOOT_CAP_BPS;
                    bps += surcharge;
                }
            }

            // Additive random 0–10%
            bps += rngWord % (ADDITIVE_RANDOM_BPS + 1);

            // Compute take
            uint256 take = (memNext * bps) / 10_000;

            // ±25% multiplicative variance (triangular: avg of two uniform VRF rolls)
            if (take != 0) {
                uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
                uint256 minWidth = (memNext * NEXT_SKIM_VARIANCE_MIN_BPS) /
                    10_000;
                if (halfWidth < minWidth) halfWidth = minWidth;
                if (halfWidth > take) halfWidth = take;

                uint256 range = halfWidth * 2 + 1;
                uint256 roll1 = (rngWord >> 64) % range;
                uint256 roll2 = (rngWord >> 192) % range;
                uint256 combined = (roll1 + roll2) / 2;

                if (combined >= halfWidth) {
                    take += combined - halfWidth;
                } else {
                    take -= halfWidth - combined;
                }
            }

            // Cap at 80%
            uint256 maxTake = (memNext * NEXT_TO_FUTURE_BPS_MAX) / 10_000;
            if (take > maxTake) take = maxTake;

            uint256 insuranceSkim = (memNext * INSURANCE_SKIM_BPS) / 10_000;
            memNext -= take + insuranceSkim;
            memFuture += take;
            memYieldAcc += insuranceSkim;
        }

        // --- x00 yield accumulator dump: 50% into futurePool (memory) ---
        if ((lvl % 100) == 0) {
            uint256 half = memYieldAcc >> 1;
            memFuture += half;
            memYieldAcc -= half;
        }

        // --- BAF + Decimator x00: draw from futurePool BEFORE keep roll ---
        uint256 baseMemFuture = memFuture;
        uint24 prevMod10 = lvl % 10;
        uint24 prevMod100 = lvl % 100;
        uint256 claimableDelta;

        // BAF Jackpot (every 10 levels) — only if the daily flip won (bit 0 of
        // rngWord = 1). On a losing flip the bracket is marked skipped, the pool
        // stays in futurePool, and pre-skip winning-flip credit is filtered out
        // of future claims via the lastBafResolvedDay bump.
        if (prevMod10 == 0) {
            if ((rngWord & 1) == 1) {
                uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 20 : 10);
                uint256 bafPoolWei = (baseMemFuture * bafPct) / 100;

                uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(
                    bafPoolWei,
                    lvl,
                    rngWord
                );
                memFuture -= claimed;
                claimableDelta += claimed;
            } else {
                jackpots.markBafSkipped(lvl);
            }
        }

        // Decimator jackpot fires at the window-close bump.
        // x00 draws 30% from the pre-jackpot future snapshot; x5 (non-x95) draws 10% from future.
        uint256 decPoolWei;
        if (prevMod100 == 0) {
            decPoolWei = (baseMemFuture * 30) / 100;
        } else if (prevMod10 == 5 && prevMod100 != 95) {
            decPoolWei = (memFuture * 10) / 100;
        }

        if (decPoolWei != 0) {
            uint256 returnWei = IDegenerusGame(address(this))
                .runDecimatorJackpot(decPoolWei, lvl, rngWord);
            uint256 spend = decPoolWei - returnWei;
            memFuture -= spend;
            claimableDelta += spend;
        }

        // --- x00 keep roll (5d4 dice: 30-65% keep, avg ~47.5%) ---
        // Operates on post-jackpot memFuture — all reward jackpots drew first.
        if ((lvl % 100) == 0) {
            uint256 seed = EntropyLib.hash2(rngWord, uint256(FUTURE_KEEP_TAG));
            uint256 total;
            unchecked {
                total =
                    (seed % 4) +
                    ((seed >> 16) % 4) +
                    ((seed >> 32) % 4) +
                    ((seed >> 48) % 4) +
                    ((seed >> 64) % 4);
            }
            uint256 keepBps = 3000 + (total * 3500) / 15;
            if (keepBps < 10_000) {
                uint256 moveWei = memFuture - (memFuture * keepBps) / 10_000;
                memFuture -= moveWei;
                memCurrent += moveWei;
            }
        }

        // --- Merge next → current ---
        memCurrent += memNext;
        memNext = 0;

        // --- Coinflip credit ---
        // purchaseLevel == storage level here: consolidation runs only on the
        // lastPurchase leg with rngLockedFlag held, after the request-time
        // level pre-increment.
        coinflip.creditFlip(
            ContractAddresses.SDGNRS,
            (memCurrent * PRICE_COIN_UNIT) /
                (PriceLookupLib.priceForLevel(purchaseLevel) * 20)
        );

        // --- Future→next drawdown (15% on non-x00 levels) ---
        if ((lvl % 100) != 0) {
            uint256 reserved = (memFuture * 15) / 100;
            memFuture -= reserved;
            memNext = reserved;
        }

        // --- Single SSTORE batch: all pool values ---
        _setPrizePools(uint128(memNext), uint128(memFuture));
        currentPrizePool = uint128(memCurrent);
        yieldAccumulator = memYieldAcc;
        if (claimableDelta != 0) {
            claimablePool += uint128(claimableDelta); // Safe: claimableDelta bounded by futurePool which fits uint128
        }
        emit RewardJackpotsSettled(lvl, memFuture, claimableDelta);
    }

    /// @dev Pay daily jackpot via jackpot module delegatecall.
    ///      Called each day during purchase phase and jackpot phase.
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    function payDailyJackpot(
        bool isJackpotPhase,
        uint24 lvl,
        uint256 randWord
    ) internal {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyJackpot.selector,
                    isJackpotPhase,
                    lvl,
                    randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay coin+ticket portion of daily jackpot via jackpot module delegatecall.
    ///      Called when dailyJackpotCoinTicketsPending is true to complete the split
    ///      daily jackpot (gas optimization to stay under 15M block limit).
    /// @param randWord VRF random word for winner selection.
    function payDailyJackpotCoinAndTickets(uint256 randWord) internal {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule
                        .payDailyJackpotCoinAndTickets
                        .selector,
                    randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay daily FLIP jackpot via jackpot module delegatecall.
    ///      Called each day during purchase phase in its own transaction.
    ///      Awards 0.5% of prize pool target in FLIP to trait-matched winners in [minLevel, maxLevel].
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    /// @param minLevel Minimum target level for near-future coin distribution (inclusive).
    /// @param maxLevel Maximum target level for near-future coin distribution (inclusive).
    function _payDailyCoinJackpot(
        uint24 lvl,
        uint256 randWord,
        uint24 minLevel,
        uint24 maxLevel
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyFlipJackpot.selector,
                    lvl,
                    randWord,
                    minLevel,
                    maxLevel
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @notice Request lootbox RNG when activity threshold is met.
    /// @dev Standalone function for mid-day lootbox RNG requests.
    ///      Cannot be called while daily RNG is locked (jackpot resolution).
    ///      VRF callback handles finalization directly - no advanceGame needed.
    function requestLootboxRng() external {
        if (rngLockedFlag) revert RngLocked();
        // Block while mid-day ticket processing is active — prevents entropy reroll
        // by requesting a new VRF word after inspecting the current one.
        if (_lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0) revert MidDayActive();
        uint48 nowTs = uint48(block.timestamp);
        uint24 currentDay = _simulatedDayIndexAt(nowTs);

        // Block in the 15-minute pre-reset window to avoid competing with daily jackpot RNG flow.
        if ((nowTs - 82620) % 1 days >= 1 days - 15 minutes) revert PreResetWindow();
        // Block until today's daily RNG has been consumed and recorded.
        if (rngWordByDay[currentDay] == 0) revert RngNotReady();

        if (rngRequestTime != 0) revert RngInFlight();

        // LINK balance check
        (uint96 linkBal, , , , ) = vrfCoordinator.getSubscription(
            vrfSubscriptionId
        );
        if (linkBal < MIN_LINK_FOR_LOOTBOX_RNG) revert InsufficientLink();

        // Threshold check: pending ETH plus the FLIP ETH-equivalent (valued at the
        // current ticket price) must clear the owner-tunable threshold. This gates
        // only the mid-day fast path — the daily advance assigns the day's word to
        // the current index regardless, so pending boxes never wait past one cycle.
        uint256 pendingEth = _unpackMilliEthToWei(
            uint64(_lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK))
        );
        uint256 pendingFlip = _unpackWholeFlipToWei(
            uint40(_lrRead(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK))
        );
        if (pendingEth == 0 && pendingFlip == 0) revert NoPendingLootbox();
        uint256 totalEthEquivalent = pendingEth;
        if (pendingFlip != 0) {
            uint256 priceWei = PriceLookupLib.priceForLevel(level);
            if (priceWei != 0) {
                totalEthEquivalent +=
                    (pendingFlip * priceWei) /
                    PRICE_COIN_UNIT;
            }
        }
        uint256 threshold = _unpackMilliEthToWei(
            uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK))
        );
        if (threshold != 0 && totalEthEquivalent < threshold) revert BelowThreshold();

        // Freeze ticket buffer: swap write→read so tickets purchased after
        // VRF delivery can't be resolved by this word.
        {
            uint24 purchaseLevel_ = level + 1;
            uint24 wk = _tqWriteKey(purchaseLevel_);
            if (ticketQueue[wk].length > 0 && ticketsFullyProcessed) {
                _swapTicketSlot();
                _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
            }
        }

        // VRF request (reverts on failure)
        uint256 id = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);

        // Advance lootbox index so new purchases target the NEXT RNG
        _lrAdvanceIndexClearPending();
        vrfRequestId = id;
        rngWordCurrent = 0;
        rngRequestTime = uint48(block.timestamp);
    }

    // BIT ALLOCATION MAP for VRF random word (currentWord after _applyDailyRng):
    //
    // Bit(s)   Consumer                    Operation                         Location
    // ------   --------                    ---------                         --------
    // 0        Coinflip win/loss           rngWord & 1                       Coinflip._resolveDay
    // 0        BAF fire gate               rngWord & 1                       AdvanceModule._consolidatePoolsAndRewardJackpots
    // 8+       Redemption roll             (currentWord >> 8) % 151 + 25     AdvanceModule.rngGate
    // full     Coinflip reward percent     keccak256(rngWord, epoch) % 20    Coinflip._resolveDay
    // full     Jackpot winner selection    via delegatecall (full word)      JackpotModule (payDailyJackpot)
    // full     Coin jackpot                via delegatecall (full word)      JackpotModule (_payDailyCoinJackpot)
    // 64+/192+ Future take variance        (rngWord>>64/>>192) % range       _consolidatePoolsAndRewardJackpots
    // low      Additive skim random        rngWord % (ADDITIVE_RANDOM_BPS+1) _consolidatePoolsAndRewardJackpots
    // full     Prize pool consolidation    in-module memory batch            _consolidatePoolsAndRewardJackpots
    // full     Reward jackpots (BAF/Dec)   self-call (BAF/Decimator)         _consolidatePoolsAndRewardJackpots
    // full     Lootbox RNG                 stored as lootboxRngWordByIndex   _finalizeLootboxRng
    //
    // NOTE: Direct bit-level consumers are bit 0, bits 8+, and the future-take
    //       variance rolls (rngWord>>64, rngWord>>192). All other 'full' consumers
    //       use modular arithmetic or keccak mixing, so bit overlap is not a
    //       collision concern.

    /// @dev Daily RNG processing gate called during advanceGame. Applies VRF word,
    ///      processes coinflip payouts, rolls daily quest, resolves pending gambling
    ///      burn redemptions, stores lootbox RNG, and handles VRF timeout retries (12h).
    function rngGate(
        uint48 ts,
        uint24 day,
        uint24 lvl,
        bool isTicketJackpotDay,
        uint8 coinflipBonus
    ) internal returns (uint256 word, uint32 gapDays) {
        // Already recorded for today
        uint256 recordedWord = rngWordByDay[day];
        if (recordedWord != 0) return (recordedWord, 0);

        uint256 currentWord = rngWordCurrent;

        // Have a fresh VRF word ready
        if (currentWord != 0 && rngRequestTime != 0) {
            // Backfill gap days from VRF stall before processing current day.
            // Gated on rngWordByDay[idx + 1] == 0 so the backfill runs at
            // most once per lock window: dailyIdx is only updated by
            // _unlockRng, so a multi-day drain would otherwise re-enter
            // this branch on each new wall-clock day and re-process the
            // same gap range, doubling purchaseStartDay and re-running
            // coinflip payouts for already-resolved days.
            uint24 idx = dailyIdx;
            if (day > idx + 1 && rngWordByDay[idx + 1] == 0) {
                uint24 gapCount = day - idx - 1;
                _backfillGapDays(currentWord, idx + 1, day);

                // Backfill any lootbox indices that never got a VRF word (orphaned by stall).
                // Uses fresh VRF entropy, not predictable on-chain state.
                _backfillOrphanedLootboxIndices(currentWord);

                // Extend death clock by the stall duration -- gap days don't count toward
                // the 120-day inactivity timeout since the game was stalled, not abandoned.
                purchaseStartDay += gapCount;
                gapDays = gapCount;
            }

            // Normal daily RNG processing (request from current day)
            currentWord = _applyDailyRng(day, currentWord);
            coinflip.processCoinflipPayouts(coinflipBonus, currentWord, day);
            // Force the MINT_FLIP daily on the first jackpot day (lastPurchaseDay still set here,
            // jackpot not yet entered) so the FLIP-mint quest only lands when the redeem window is
            // live. Turbo (compressedJackpotFlag == 2) is skipped — its jackpot collapses at this
            // request, leaving no full open day for that quest.
            // Force the buy-a-foil-pack daily on the first purchase day of a level:
            // phaseTransitionActive is set at level end (_endPhase) and cleared only once
            // the transition completes (line 440), and this roll runs before that completion
            // in the same advance — so it is true exactly on the day the new purchase phase
            // opens. Gated on gapDays == 0 so a VRF-stall backfill (which defers the whole
            // transition to the next advance, line 412) does not roll the foil quest early.
            // Mutually exclusive with the first-jackpot-day MINT_FLIP force (opposite cycle ends).
            // Skipped entirely on a late-consumed word (buffered RNGREUSE clamp: day < wall day):
            // that day's quest never rolled while the day was live, so a roll now would create a
            // retroactive quest that immediately counts as a rolled miss against every streak.
            // The day stays unrolled — forgiven, matching gap-backfill days.
            if (day == _simulatedDayIndexAt(ts)) {
                quests.rollDailyQuest(
                    day,
                    currentWord,
                    lastPurchaseDay && compressedJackpotFlag != 2,
                    phaseTransitionActive && gapDays == 0
                );
            }

            // Resolve the sentinel-stamped gambling-burn pool if any. Reading the
            // sentinel rather than deriving `day - 1` makes multi-day RNG stalls correct by
            // construction: the sentinel always names the (at most one) unresolved day, so a
            // single resolve call after the stall recovers covers the stuck pool exactly.
            {
                IsDGNRS sdgnrs = IsDGNRS(
                    ContractAddresses.SDGNRS
                );
                uint24 toResolve = sdgnrs.pendingResolveDay();
                if (toResolve != 0) {
                    uint16 redemptionRoll = uint16(
                        ((currentWord >> 8) % 151) + 25
                    );
                    sdgnrs.resolveRedemptionPeriod(redemptionRoll, toResolve);
                }
            }

            _finalizeLootboxRng(currentWord);
            return (currentWord, gapDays);
        }

        // Waiting for VRF - check for timeout retry. A daily request (rngLockedFlag) gets ONE
        // 12h VRF retry, with a 1h head start for the >50.1%-DGVE vault owner. The retry
        // overwrites the outstanding request ID, so whoever fires it discards a late-arriving
        // word — a once-per-stall reroll, offered first to the party already trusted with the
        // (functionally identical) coordinator-swap reroll. The retry-spent state rides in the
        // LSB of rngRequestTime (set by _finalizeRngRequest); once spent, recovery is the
        // retried request's fulfillment or a governance coordinator swap, which re-arms the
        // retry. A lootbox-only mid-day request (rngLockedFlag == false) that bled past the day
        // boundary is instead abandoned after MIDDAY_RNG_STALL_TIMEOUT and promoted to this
        // day's daily request — _requestRng's isRetry path keeps the reserved index, so the
        // fresh daily word finalizes that bucket just as the mid-day word would have. The
        // promotion is that day's FIRST daily request (isDailyRetry false), so it keeps a retry.
        if (rngRequestTime != 0) {
            uint48 elapsed = ts - rngRequestTime;
            if (rngLockedFlag) {
                if (
                    (rngRequestTime & 1) == 0 &&
                    (elapsed >= DAILY_RNG_RETRY_TIMEOUT ||
                        (elapsed >=
                            DAILY_RNG_RETRY_TIMEOUT -
                                DAILY_RNG_RETRY_HEAD_START &&
                            IVaultOwnerCheck(ContractAddresses.VAULT)
                                .isVaultOwner(msg.sender)))
                ) {
                    _requestRng(isTicketJackpotDay, lvl);
                    return (1, 0);
                }
            } else if (elapsed >= MIDDAY_RNG_STALL_TIMEOUT) {
                _requestRng(isTicketJackpotDay, lvl);
                return (1, 0);
            }
            revert RngNotReady();
        }

        // Need fresh RNG
        _requestRng(isTicketJackpotDay, lvl);
        return (1, 0);
    }

    function _finalizeLootboxRng(uint256 rngWord) private {
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
        if (lootboxRngWordByIndex[index] != 0) return;
        lootboxRngWordByIndex[index] = rngWord;
        emit LootboxRngApplied(index, rngWord, vrfRequestId);
    }

    /// @dev Game-over RNG gate with fallback for stalled VRF.
    ///      After the 14-day GAMEOVER_RNG_FALLBACK_DELAY, uses earliest historical VRF word as
    ///      fallback (more secure than blockhash since it's already verified on-chain and
    ///      cannot be manipulated).
    ///      Also resolves any pending gambling burn redemptions (mirrors rngGate behavior, CP-06 fix).
    /// @return word RNG word, 1 if request sent, or 0 if waiting on fallback.
    function _gameOverEntropy(
        uint48 ts,
        uint24 day,
        uint24 lvl,
        bool isTicketJackpotDay
    ) private returns (uint256 word) {
        if (rngWordByDay[day] != 0) return rngWordByDay[day];

        uint256 currentWord = rngWordCurrent;
        if (currentWord != 0 && rngRequestTime != 0) {
            currentWord = _applyDailyRng(day, currentWord);
            if (lvl != 0) {
                // Gameover settles the final day's flips but never grants a bonus (0).
                coinflip.processCoinflipPayouts(0, currentWord, day);
            }
            // Resolve the sentinel-stamped gambling-burn pool if any. Same shape as the
            // rngGate redemption resolution path — sentinel-keyed so multi-day stalls resolve
            // by construction.
            {
                IsDGNRS sdgnrs = IsDGNRS(
                    ContractAddresses.SDGNRS
                );
                uint24 toResolve = sdgnrs.pendingResolveDay();
                if (toResolve != 0) {
                    uint16 redemptionRoll = uint16(
                        ((currentWord >> 8) % 151) + 25
                    );
                    sdgnrs.resolveRedemptionPeriod(redemptionRoll, toResolve);
                }
            }
            _finalizeLootboxRng(currentWord);
            return currentWord;
        }

        // VRF-death deadman: in a suppressed phase (jackpot / last-purchase) where no day has
        // sealed for _VRF_DEADMAN_DAYS, commit the historical fallback immediately — regardless
        // of whether a request is outstanding or how long it has been pending — so a
        // permanently-dead VRF there reaches terminal fund release without the
        // GAMEOVER_RNG_FALLBACK_DELAY wait. Gated to the suppressed phases so the normal
        // purchase-phase / genesis game-over keeps its two-step real-VRF request path. Outside
        // the deadman, honor the normal grace: an outstanding request waits the fallback delay,
        // otherwise a fresh request is issued.
        bool deadman = (jackpotPhaseFlag || lastPurchaseDay) && _vrfDeadmanFired();
        if (rngRequestTime != 0 || deadman) {
            if (!deadman && ts - rngRequestTime < GAMEOVER_RNG_FALLBACK_DELAY) {
                revert RngNotReady();
            }
            // Use earliest historical VRF word as fallback (more secure than blockhash)
            uint256 fallbackWord = _getHistoricalRngFallback(day);
            // Cancel any reverseFlip nudge from the fallback word: the VRF-dead fallback
            // never set rngLockedFlag, so reverseFlip stayed open and a committer could
            // otherwise steer the terminal distribution. Pre-subtracting cancels the +=
            // inside _applyDailyRng (and consumes the nudges), leaving the pure
            // historical+prevrandao word.
            unchecked { fallbackWord -= totalFlipReversals; }
            fallbackWord = _applyDailyRng(day, fallbackWord);
            if (lvl != 0) {
                // Gameover settles the final day's flips but never grants a bonus (0).
                coinflip.processCoinflipPayouts(0, fallbackWord, day);
            }
            // Resolve the sentinel-stamped gambling-burn pool if any. Fallback path
            // uses fallbackWord for the roll; sentinel still names the stuck day so resolves
            // are correct even after a GAMEOVER_RNG_FALLBACK_DELAY (14-day) stall.
            {
                IsDGNRS sdgnrs = IsDGNRS(
                    ContractAddresses.SDGNRS
                );
                uint24 toResolve = sdgnrs.pendingResolveDay();
                if (toResolve != 0) {
                    uint16 redemptionRoll = uint16(
                        ((fallbackWord >> 8) % 151) + 25
                    );
                    sdgnrs.resolveRedemptionPeriod(redemptionRoll, toResolve);
                }
            }
            _finalizeLootboxRng(fallbackWord);
            // Keep the already-expired timer as a terminal-intent latch until _unlockRng. Ticket
            // processing and handleGameOverDrain intentionally run in separate transactions; if
            // this grace timer were cleared here before day-based liveness had independently fired,
            // the next advance would leave _handleGameOverPath and the terminal payout would never
            // run. The final terminal transaction clears the timer together with the RNG lock.
            return fallbackWord;
        }

        if (_tryRequestRng(isTicketJackpotDay, lvl)) {
            return 1;
        }

        // VRF request failed; start fallback timer (rngRequestTime != 0 acts as lock).
        rngWordCurrent = 0;
        rngRequestTime = ts;
        return 0;
    }

    /// @dev Get historical VRF fallback entropy for gameover RNG.
    ///      Collects up to 5 early historical VRF words and hashes them together
    ///      with currentDay and block.prevrandao. Historical words are committed VRF
    ///      (non-manipulable), prevrandao adds unpredictability at the cost of 1-bit
    ///      validator manipulation (propose or skip). Acceptable trade-off for a
    ///      gameover-only fallback path when VRF is dead.
    ///      If no historical words exist, falls through to prevrandao-only
    ///      entropy. This can only happen at level 0 (zero VRF history means
    ///      zero completed advances), so the 1-bit validator bias is irrelevant.
    /// @param currentDay Current day index.
    /// @return word Combined historical entropy.
    function _getHistoricalRngFallback(
        uint24 currentDay
    ) private view returns (uint256 word) {
        uint256 found;
        uint256 combined;
        uint24 searchLimit = currentDay > 30 ? 30 : currentDay;
        for (uint24 searchDay = 1; searchDay < searchLimit; ) {
            uint256 w = rngWordByDay[searchDay];
            if (w != 0) {
                combined = EntropyLib.hash2(combined, w);
                unchecked {
                    ++found;
                }
                if (found == 5) break;
            }
            unchecked {
                ++searchDay;
            }
        }

        word = uint256(
            keccak256(abi.encodePacked(combined, currentDay, block.prevrandao))
        );
        if (word == 0) word = 1;
    }

    /*+======================================================================+
      |                       NEXT-TO-FUTURE SKIM RATE                       |
      +======================================================================+
      |  Compute the bps skimmed from the next pool into the future pool,    |
      |  ramping by days elapsed and by level within the 100-level cycle.    |
      +======================================================================+*/

    function _nextToFutureBps(
        uint32 elapsed,
        uint24 lvl
    ) internal pure returns (uint16) {
        uint256 lvlBonus = (uint256(lvl % 100) / 10) * 100; // +1% per 10 levels within cycle
        uint256 bps;
        if (elapsed <= 1) {
            bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus;
        } else if (elapsed <= 14) {
            uint256 elapsedAfterDay = elapsed - 1;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus -
                NEXT_TO_FUTURE_BPS_MIN;
            bps =
                NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus -
                (delta * elapsedAfterDay) /
                13;
        } else if (elapsed <= 28) {
            uint256 elapsedAfterMin = elapsed - 14;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus -
                NEXT_TO_FUTURE_BPS_MIN;
            bps = NEXT_TO_FUTURE_BPS_MIN + (delta * elapsedAfterMin) / 14;
        } else {
            bps =
                NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus +
                (elapsed - 28) *
                NEXT_TO_FUTURE_BPS_DAY_STEP;
        }
        return uint16(bps > 10_000 ? 10_000 : bps);
    }

    /*+======================================================================+
      |                    FUTURE TICKET ACTIVATION                          |
      +======================================================================+
      |  Future ticket rewards are staged per level and drained on every     |
      |  advance over a rolling near-future range (lvl+1..lvl+4 in jackpot   |
      |  phase, purchaseLevel+1..+4 in purchase), before the day's draws.    |
      |  Far-future entries promote at each level transition.                |
      +======================================================================+*/

    /// @dev Process a batch of future ticket rewards for the specified level.
    ///      Drained on every advance over the rolling near-future range (not only at the prior level's jackpot).
    /// @param lvl Target level to activate (typically current level + 1).
    /// @param entropy Today's daily RNG word (from rngGate) used for rarity rolls.
    /// @return worked True if any queued entries were processed.
    /// @return finished True if all queued entries for this level are processed.
    /// @return writesUsed Write-budget units consumed (each storage write or skip costs one unit), not a raw SSTORE count.
    function _processFutureTicketBatch(
        uint24 lvl,
        uint256 entropy
    ) private returns (bool worked, bool finished, uint32 writesUsed) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.processFutureTicketBatch.selector,
                    lvl,
                    entropy
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert EmptyReturn();
        return abi.decode(data, (bool, bool, uint32));
    }

    /// @dev Before daily draws, process near-future ticket read queues.
    ///      Caller passes level during jackpot phase (range lvl+1..lvl+4) or
    ///      purchaseLevel during purchase phase (range lvl+2..lvl+5).
    ///      FF promotion is handled separately at phase transition time.
    /// @param lvl Base level (level during jackpot, purchaseLevel during purchase).
    /// @param entropy Today's daily RNG word (from rngGate) threaded to ticket rarity rolls.
    /// @return finished True when all target future levels are fully processed.
    function _prepareFutureTickets(
        uint24 lvl,
        uint256 entropy
    ) private returns (bool finished) {
        uint24 startLevel = lvl + 1;
        uint24 endLevel = lvl + 4;
        uint24 resumeLevel = ticketLevel;

        // The current-level ticket drain shares this resume cursor and runs after prepare on
        // every advance call. While that drain is mid-flight across transactions (marker == lvl),
        // defer: probing future levels here lets an empty-queue probe reset the shared cursor,
        // restarting the current drain from index 0 on each call and wedging a large queue
        // permanently. Future levels are processed once the current drain clears the marker.
        if (resumeLevel == lvl) return true;

        // Continue an in-flight future level first to preserve progress.
        if (resumeLevel >= startLevel && resumeLevel <= endLevel) {
            (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
                resumeLevel,
                entropy
            );
            if (worked || !levelFinished) return false;
        }

        // Then probe remaining target levels in order.
        for (uint24 target = startLevel; target <= endLevel; ) {
            if (target != resumeLevel) {
                (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
                    target,
                    entropy
                );
                if (worked || !levelFinished) return false;
            }
            unchecked {
                ++target;
            }
        }
        return true;
    }

    /*+======================================================================+
      |                    TICKET / TOKEN AIRDROP BATCHING                   |
      +======================================================================+
      |  Ticket entries are processed in batches to prevent gas exhaustion.  |
      |  Large purchases are queued and processed across multiple txs.       |
      +======================================================================+*/

    /// @dev Process a batch of current level tickets via mint module delegatecall.
    /// @param lvl Current level.
    /// @return worked True if the batch materialized at least one ticket or foil entry.
    ///         Reported directly by the mint module rather than inferred from a cursor
    ///         delta, so a batch that both starts and finishes in one call (cursor returns
    ///         to 0) still reports its work and the chain breaks before BAF/jackpot.
    /// @return finished True if all tickets for this level have been fully processed.
    function _runProcessTicketBatch(
        uint24 lvl
    ) private returns (bool worked, bool finished) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.processTicketBatch.selector,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length < 64) revert EmptyReturn();
        (finished, worked) = abi.decode(data, (bool, bool));
    }

    /// @dev Process jackpot→purchase transition housekeeping (vault perpetual tickets + auto-stake).
    ///      Vault addresses (SDGNRS, VAULT) get generic queued tickets.
    /// @param purchaseLevel Current purchase level (level + 1).
    function _processPhaseTransition(uint24 purchaseLevel) private {
        // Vault perpetual entries: 16 entries (= 4 whole tickets) per level for DGNRS and VAULT
        uint24 targetLevel = purchaseLevel + 99;
        _queueEntries(
            ContractAddresses.SDGNRS,
            targetLevel,
            VAULT_PERPETUAL_ENTRIES,
            true
        );
        _queueEntries(
            ContractAddresses.VAULT,
            targetLevel,
            VAULT_PERPETUAL_ENTRIES,
            true
        );

        // Auto-stake all non-claimable ETH into stETH for yield generation.
        // Non-blocking: if stETH contract fails, game continues normally.
        _autoStakeExcessEth();
    }

    /// @dev Stake all ETH above claimablePool into stETH via Lido.
    ///      Uses try/catch so stETH is never a hard dependency — game
    ///      continues even if Lido is paused or the call reverts.
    function _autoStakeExcessEth() private {
        uint256 ethBal = address(this).balance;
        uint256 reserve = claimablePool;
        if (ethBal <= reserve) return;
        uint256 stakeable = ethBal - reserve;
        try steth.submit{value: stakeable}(address(0)) returns (
            uint256
        ) {} catch {
            emit StEthStakeFailed(stakeable);
        }
    }

    /// @dev Request new VRF random word from Chainlink.
    ///      Sets RNG lock to prevent manipulation during pending window.
    /// @param isTicketJackpotDay True if this is the last purchase day.
    /// @param lvl Current level.
    function _requestRng(bool isTicketJackpotDay, uint24 lvl) private {
        // Hard revert if Chainlink request fails; this intentionally halts game progress until VRF funding/config is fixed.
        _finalizeRngRequest(
            isTicketJackpotDay,
            lvl,
            _requestVrfWord(VRF_REQUEST_CONFIRMATIONS)
        );
    }

    function _tryRequestRng(
        bool isTicketJackpotDay,
        uint24 lvl
    ) private returns (bool requested) {
        try
            vrfCoordinator.requestRandomWords(
                VRFRandomWordsRequest({
                    keyHash: vrfKeyHash,
                    subId: vrfSubscriptionId,
                    requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
                    callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                    numWords: 1,
                    extraArgs: hex"" // Empty for LINK payment (default)
                })
            )
        returns (uint256 id) {
            _finalizeRngRequest(isTicketJackpotDay, lvl, id);
            requested = true;
        } catch {}
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

    /// @dev Write the VRF coordinator, subscription, and key hash together.
    /// @param coord VRF coordinator address.
    /// @param sub VRF subscription ID for LINK billing.
    /// @param key VRF key hash for gas lane selection.
    function _setVrfConfig(address coord, uint256 sub, bytes32 key) internal {
        vrfCoordinator = IVRFCoordinator(coord);
        vrfSubscriptionId = sub;
        vrfKeyHash = key;
    }

    /// @dev Advance the lootbox RNG index and zero both pending accumulators in a
    ///      single read-modify-write of the packed slot: new purchases target the
    ///      NEXT RNG index and the pending ETH/FLIP totals restart at zero.
    function _lrAdvanceIndexClearPending() private {
        uint256 packed = lootboxRngPacked;
        uint256 nextIndex = ((packed >> LR_INDEX_SHIFT) & LR_INDEX_MASK) + 1;
        packed &= ~((LR_INDEX_MASK << LR_INDEX_SHIFT) |
            (LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT) |
            (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
        lootboxRngPacked =
            packed |
            ((nextIndex & LR_INDEX_MASK) << LR_INDEX_SHIFT);
    }

    // =========================================================================
    // Queue Swap and Prize Pool Freeze
    // =========================================================================

    /// @dev Toggle the active ticket queue buffer and reset the read-slot drained flag.
    ///      Normal-cycle callers swap only after the read slot is drained. The terminal caller may
    ///      instead snapshot the selected abandonment cohort while unrelated levels still have
    ///      queued entries; the global toggle only defers those irrelevant post-game queues, never
    ///      loses them. This runs inside the advance heartbeat, where reverting would brick release.
    function _swapTicketSlot() internal {
        ticketWriteSlot = !ticketWriteSlot;
        ticketsFullyProcessed = false;
    }

    /// @dev Activate the prize pool freeze. If not already frozen, pre-seeds the pending
    ///      future-pool buffer with 1% of futurePrizePool so Degenerette ETH wins can resolve
    ///      during freeze without waiting for bet inflow. Unconsumed remainder rolls back to
    ///      futurePool via _unfreezePool. If already frozen (jackpot phase), accumulators keep
    ///      growing.
    function _freezePool() internal {
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            uint256 futureBal = _getFuturePrizePool();
            uint256 seed = futureBal / 100;
            if (seed != 0) {
                _setFuturePrizePool(futureBal - seed);
                _setPendingPools(0, uint128(seed));
            } else {
                prizePoolPendingPacked = 0;
            }
        }
    }

    /// @dev Swap queue buffer AND activate the prize pool freeze (daily RNG path only).
    function _swapAndFreeze() internal {
        _swapTicketSlot();
        _freezePool();
    }

    /// @dev Apply pending accumulators to live pools and clear freeze.
    ///      No-op if not currently frozen.
    function _unfreezePool() internal {
        if (!prizePoolFrozen) return;
        (uint128 pNext, uint128 pFuture) = _getPendingPools();
        (uint128 next, uint128 future) = _getPrizePools();
        _setPrizePools(next + pNext, future + pFuture);
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
    }

    function _finalizeRngRequest(
        bool isTicketJackpotDay,
        uint24 lvl,
        uint256 requestId
    ) private {
        // isRetry: some VRF request already reserved the lootbox index (a daily retry OR an
        // in-flight mid-day lootbox request) — so the index must not be advanced again.
        bool isRetry = vrfRequestId != 0 &&
            rngRequestTime != 0 &&
            rngWordCurrent == 0;
        // isDailyRetry: a genuine retry of the *daily* request. A daily request holds the lock
        // (rngLockedFlag set true by the first daily request); a mid-day lootbox request leaves
        // rngLockedFlag false. Distinguishing them stops an in-flight lootbox request from
        // making this fresh daily request look like a retry and skip the level increment below.
        bool isDailyRetry = isRetry && rngLockedFlag;
        if (!isRetry) {
            // Fresh request: advance lootbox index so new purchases target the NEXT RNG.
            _lrAdvanceIndexClearPending();
        }
        // Retry: index already advanced from the original request. No action needed —
        // lootboxRngIndex - 1 still points to the pending index regardless of request ID.

        vrfRequestId = requestId;
        rngWordCurrent = 0;
        // The LSB of rngRequestTime doubles as the daily retry-spent flag: 0 on a fresh daily
        // request (mid-day promotion included), 1 once the single daily retry has fired. Both
        // forms round DOWN (<=1s into the past) so same-second `ts - rngRequestTime` reads
        // never underflow; the skew is harmless to every elapsed-time and day-index reader.
        rngRequestTime = isDailyRetry
            ? (uint48(block.timestamp) - 1) | 1
            : uint48(block.timestamp) & ~uint48(1);
        rngLockedFlag = true;

        // Close the FLIP purchase window at the final jackpot day's RNG request — the boundary where
        // new tickets begin routing to the next level (mirrors the route-to-level+1 step in the mint
        // module). jackpotCounter + step catches the final daily jackpot; the isTicketJackpotDay
        // (level-transition) request catches the single-day turbo jackpot, where jackpotPhaseFlag is
        // not yet set here.
        if (ticketRedemptionOpen && (jackpotPhaseFlag || isTicketJackpotDay)) {
            uint8 jpStep = 1;
            if (compressedJackpotFlag == 2 && jackpotCounter == 0) {
                jpStep = JACKPOT_LEVEL_CAP;
            } else if (
                compressedJackpotFlag == 1 &&
                jackpotCounter > 0 &&
                jackpotCounter < JACKPOT_LEVEL_CAP - 1
            ) {
                jpStep = 2;
            }
            if (jackpotCounter + jpStep >= JACKPOT_LEVEL_CAP) {
                ticketRedemptionOpen = false;
            }
        }

        // Increment level at RNG request time when lastPurchaseDay = true.
        // lvl is already purchaseLevel (= level + 1), so set directly.
        // Only on a fresh daily request - a daily retry would double-increment, and an
        // in-flight mid-day lootbox request must not suppress this increment.
        if (isTicketJackpotDay && !isDailyRetry) {
            // Snapshot affiliate reward before level increment.
            // Scores routed to lvl (= level + 1) during the purchase phase just ended.
            _rewardTopAffiliate(lvl);
            level = lvl;

            // Decimator window: open at x4/x99, close at x5/x00
            uint24 mod100 = lvl % 100;
            uint24 mod10 = lvl % 10;
            if ((mod10 == 4 && mod100 != 94) || mod100 == 99) {
                decWindowOpen = true;
            } else if (
                decWindowOpen && ((mod10 == 5 && mod100 != 95) || mod100 == 0)
            ) {
                decWindowOpen = false;
            }

            // Resolve charity governance for the completed level.
            // lvl is the NEW level (old level + 1). CHARITY.currentLevel tracks
            // the CURRENT governance level (starts at 0, incremented by pickCharity).
            // The game's level 0->1 transition means level 0 gameplay is complete,
            // so we resolve governance for level 0 = lvl - 1.
            charityResolve.pickCharity(lvl - 1);
        }
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

        // Detect what is in flight and re-issue on the new coordinator.
        // The request is accepted before the new subscription is LINK-funded; DegenerusAdmin
        // funds it in the same _executeSwap transaction (transferAndCall), and the VRF node
        // fulfills once funded. If the new coordinator also stalls, the daily advance abandons a
        // mid-day request and promotes it to the daily word after MIDDAY_RNG_STALL_TIMEOUT.
        if (
            _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0 &&
            vrfRequestId != 0 &&
            !rngLockedFlag
        ) {
            // Mid-day request actually in flight: KEEP LR_MID_DAY=1; LR_INDEX preserved so the
            // new word lands in the same reserved slot [N] via the mid-day fulfillment branch.
            // `vrfRequestId != 0` is the mid-day counterpart of the daily branch's
            // `rngWordCurrent == 0` guard: an outstanding request is cleared to 0 only on
            // fulfillment (rawFulfillRandomWords mid-day branch), whereas LR_MID_DAY stays set
            // after the word lands until the ticket batch drains. Keying on rngRequestTime alone
            // is unsafe -- _gameOverEntropy's failed-request fallback re-sets rngRequestTime with
            // no request in flight (vrfRequestId already 0), so a rotation in that window would
            // re-issue a spurious request whose fulfillment overwrites the already-delivered
            // write-once lootbox word. `!rngLockedFlag` routes a promoted mid-day->daily request
            // (LR_MID_DAY set alongside the daily lock) to the daily branch for correct
            // confirmation depth. When no genuine mid-day request is pending, fall through.
            vrfRequestId = _requestVrfWord(VRF_MIDDAY_CONFIRMATIONS);
            rngRequestTime = uint48(block.timestamp);
        } else if (rngLockedFlag) {
            // Daily in flight: KEEP rngLockedFlag=true.
            if (rngWordCurrent == 0) {
                // Daily word not yet delivered: re-request on the new coordinator. The cleared
                // LSB re-arms the single daily retry — a new coordinator gets its own retry.
                vrfRequestId = _requestVrfWord(VRF_REQUEST_CONFIRMATIONS);
                rngRequestTime = uint48(block.timestamp) & ~uint48(1);
            }
            // else: daily word already delivered and valid -> preserve it; no re-issue
            // (a fresh callback would be rejected by the :1761 rngWordCurrent!=0 guard).
        }
        // else: nothing in flight -> config repoint only; no re-issue, no flag change.

        // Intentional: totalFlipReversals is NOT reset here. Nudges were purchased
        // with irreversible FLIP burns before or during the stall. They carry over
        // and apply to the first post-swap VRF word via _applyDailyRng. Resetting
        // would steal user value (burned FLIP for zero effect).

        emit VrfCoordinatorUpdated(current, newCoordinator);
    }

    /// @dev Unlock RNG after processing is complete for the day.
    ///      Resets VRF state and re-enables RNG usage.
    /// @param day Current day index to record.
    function _unlockRng(uint24 day) private {
        dailyIdx = day;
        rngLockedFlag = false;
        rngWordCurrent = 0;
        vrfRequestId = 0;
        rngRequestTime = 0;
        _unfreezePool();
        // The day-seal is the one chokepoint every completed game-day passes through (purchase
        // daily, jackpot coin+tickets, phase transition). Emit the daily pool snapshot here, after
        // _unfreezePool folds the pending accumulators back into the live pools, so the indexer
        // mirrors the settled end-of-day pools and a solvency total (ETH + stETH) from logs alone.
        // Game-over also seals here but emits its own terminal snapshot in the drain, so skip it.
        if (!gameOver) {
            emit PrizePoolDailySnapshot(
                _getNextPrizePool(),
                _getFuturePrizePool(),
                _getCurrentPrizePool(),
                claimablePool,
                address(this).balance + steth.balanceOf(address(this)),
                yieldAccumulator
            );
        }
    }


    /// @dev Backfill rngWordByDay and process coinflip payouts for gap days
    ///      caused by VRF stall. Derives deterministic words from the first
    ///      post-gap VRF word via keccak256(vrfWord, gapDay).
    ///      NOTE: Gap days get zero nudges (totalFlipReversals not consumed).
    ///      NOTE: resolveRedemptionPeriod is NOT called for backfilled gap days —
    ///      the redemption timer continued ticking in real time during the stall;
    ///      it resolves only on the current day via the normal rngGate path.
    /// @param vrfWord The first post-gap VRF random word.
    /// @param startDay First gap day (dailyIdx + 1).
    /// @param endDay Current day (exclusive — not backfilled, handled by normal path).
    function _backfillGapDays(
        uint256 vrfWord,
        uint24 startDay,
        uint24 endDay
    ) private {
        // Cap at 120 gap days to stay within block gas limit (~9M gas).
        // Backfills oldest days first (most likely to have active coinflips).
        if (endDay - startDay > 120) endDay = startDay + 120;
        for (uint24 gapDay = startDay; gapDay < endDay; ) {
            uint256 derivedWord = uint256(
                keccak256(abi.encodePacked(vrfWord, gapDay))
            );
            if (derivedWord == 0) derivedWord = 1;
            rngWordByDay[gapDay] = derivedWord;
            // Gap days are calendar days that elapsed during the stall (no advance ran on
            // them), so none is a level-0 or first-jackpot day — always non-bonus (0).
            coinflip.processCoinflipPayouts(0, derivedWord, gapDay);
            emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
            unchecked {
                ++gapDay;
            }
        }
    }

    /// @dev Backfill any lootbox RNG indices that never received a VRF word.
    ///      Scans backwards from lootboxRngIndex - 1 until hitting a filled index.
    ///      Uses VRF-derived entropy so lootbox outcomes cannot be front-run.
    /// @param vrfWord Fresh VRF word from the post-gap callback.
    function _backfillOrphanedLootboxIndices(uint256 vrfWord) private {
        uint48 idx = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
        if (idx <= 1) return; // nothing reserved yet

        // Scan backwards from the most recent reserved index
        for (uint48 i = idx - 1; i >= 1; ) {
            if (lootboxRngWordByIndex[i] != 0) break; // hit a filled index, done

            uint256 fallbackWord = uint256(
                keccak256(abi.encodePacked(vrfWord, i))
            );
            if (fallbackWord == 0) fallbackWord = 1;
            lootboxRngWordByIndex[i] = fallbackWord;
            emit LootboxRngApplied(i, fallbackWord, 0);

            unchecked {
                --i;
            }
        }
    }

    /// @dev Apply daily RNG nudges, record the word, and emit the finalized word.
    function _applyDailyRng(
        uint24 day,
        uint256 rawWord
    ) private returns (uint256 finalWord) {
        uint256 nudges = totalFlipReversals;
        finalWord = rawWord;
        if (nudges != 0) {
            unchecked {
                finalWord += nudges;
            }
            totalFlipReversals = 0;
        }
        rngWordCurrent = finalWord;
        rngWordByDay[day] = finalWord;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit DailyRngApplied(day, rawWord, nudges, finalWord);
    }
}
