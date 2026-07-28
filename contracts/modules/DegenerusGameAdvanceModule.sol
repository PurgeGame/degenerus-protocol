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

/// @dev Admin surface for the guarded LINK/ETH valuation. Passing one whole LINK yields
///      wei-per-LINK, capped and staleness-checked, or zero when it cannot be priced.
interface IAdminLinkValue {
    function linkAmountToEth(uint256 amount) external view returns (uint256);
}

/// @dev Vault interface for the >50.1%-DGVE owner check (daily VRF retry head start).
interface IVaultOwnerCheck {
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev WWXRP surface for the century BAF-incinerator draw: level-x99 burn
///      entries resolve to one winner when the x00 BAF skips.
interface IWwxrpIncinerator {
    function resolveIncinerator(
        uint24 bracket,
        uint256 rngWord,
        uint256 poolWei
    ) external returns (address winner);
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
    error GasTooHigh(); // Block basefee is above the mid-day ceiling; the request would bill the subscription at a bad price.
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
    // 12 is the last stage: the subscriber STAGE is entry-gated on !rngLockedFlag, so it can
    // never complete in a tx that also has a buffered word / pending backfill — there is no
    // deferred-composition case left to stage.
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

    /// @notice Daily seat-tenure drawing paid out: one uniform draw over the afking
    ///         ring (the VAULT's pinned slot 0 excluded) at each day-seal, prize
    ///         proportional to the winner's funded tenure. A drawn tombstone or
    ///         span-0 sub is a dud day (no event).
    /// @param winner Drawn subscriber credited the FLIP prize
    /// @param day Sealed day whose committed word drove the draw
    /// @param spanDays Winner's funded tenure span (afkCoveredThroughDay - afkingStartDay)
    /// @param flipAmount Whole-FLIP prize (SEAT_DRAW_FLIP_PER_DAY x span, capped)
    event SubDrawWon(
        address indexed winner,
        uint24 day,
        uint24 spanDays,
        uint256 flipAmount
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
    /// @notice WWXRP token — century BAF-incinerator draw resolution.
    IWwxrpIncinerator private constant wwxrpIncinerator =
        IWwxrpIncinerator(ContractAddresses.WWXRP);
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
    ///      (21), a cross-contract sub-ending finalize (cancel-reclaim / funding-kill) ≈29k =
    ///      `SUB_STAGE_EVICT_WEIGHT` (8)) — and ends the chunk on accumulated weight, not raw
    ///      count, so EVERY composition (including a saturated all-evict swap-pop chunk) stays on
    ///      the <10M target with deep headroom to the 16.7M advance-chain ceiling. The budget
    ///      sizes the evict chunk at ≈312 finalizes so a saturated all-evict crank stays below 10M.
    ///      A large set drains across several advanceGame calls.
    uint256 private constant SUB_STAGE_WEIGHT_BUDGET = 2500;

    /// @dev Seat-tenure drawing prize rate: whole FLIP per funded tenure day of the
    ///      drawn winner (pure days — dailyQuantity does not scale the prize).
    uint256 private constant SEAT_DRAW_FLIP_PER_DAY = 10;

    /// @dev Seat-tenure drawing prize ceiling, whole FLIP (binds from a 400-day span).
    uint256 private constant SEAT_DRAW_MAX_FLIP = 4000;

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
        // dailyIdx is stable across every read below: its only writer (_unlockRng)
        // executes after the last use, or on paths that return before reaching it.
        // locked is deliberately the ENTRY snapshot: rngGate's retry re-fires the
        // request mid-flow (_finalizeRngRequest), and the sentinel branch below keys
        // its swap decision off the pre-request lock state.
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
        // Latched mid-day stall: the pre-gate promotion cannot swap while the
        // committed cohort occupies the read slot, and a collapsed turbo phase issues
        // no sentinel swap — so buys queued after the stalled request would drain (the
        // sweep's trailing window guarantees that) but only after the level retired:
        // safe yet drawless. Defer the arm; the evening target-met latch takes the
        // compressed path instead, whose next-day request commits them in time to
        // draw.
        if (
            !inJackpot &&
            !lastPurchaseDay &&
            !locked &&
            day == wallDay &&
            day >= psd &&
            rngWordByDay[day] == 0 &&
            !(rngRequestTime != 0 &&
                _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0)
        ) {
            uint32 purchaseDays = day - psd;
            if (
                purchaseDays <= 1 &&
                _getNextPrizePool() > _prizePoolTarget(lvl + 1)
            ) {
                lastPurchaseDay = true;
                // A surviving flag 2 here is the previous turbo's unpaid bonus latch
                // (_endPhase preserved it): escalate to 3 = armed turbo whose
                // predecessor's bonus is still owed today. A plain arm writes 2.
                compressedJackpotFlag = compressedJackpotFlag == 2 ? 3 : 2;
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
                // coin is worthless at gameover) — return mult = 0 so mineFlip pays nothing.
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

                // Unified sweep: the swapped read slot may span several windowed keys
                // (the routed cohort, the award queue, future-level cohorts, or a
                // self-healing leftover). The pick is stable across partial batches —
                // a queue's length is only released when its drain completes — and the
                // latch clears only once the whole window is empty.
                (, bool midFound) = _sweepReadLevel(purchaseLevel);
                // The draw is gated on BOTH the normal queue AND the foil drain: keep
                // draining while the normal queue OR a sealed-but-un-drained foil bucket
                // (resolved on leftover budget) remains, else foil's boosted entries
                // silently under-resolve into the jackpot.
                if (midFound || _foilDrainPending()) {
                    (, bool ticketsFinished) = _runProcessTicketBatch(
                        purchaseLevel
                    );
                    // Commit unconditionally: the outer gate already proved there was
                    // work to attempt, and every outcome the worker can return carries
                    // progress worth keeping. A finished walk that resolved no buyers
                    // still advanced foilDrainDay past a drained-empty bucket — reverting
                    // that write would roll the cursor back onto the same bucket, leaving
                    // _foilDrainPending (and so _advanceDue) true and re-entering this
                    // branch on every call until the day boundary resets the latch.
                    // The sweep worker's finished means the WHOLE window and the foil
                    // drain are caught up, so the latch releases directly.
                    if (ticketsFinished) {
                        ticketsFullyProcessed = true;
                        _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                    }
                    emit Advance(STAGE_TICKETS_WORKING, lvl);
                    // Mid-day partial-drain: mult = 1 (no escalation).
                    return mult;
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
                // One packed read of lootboxRngPacked covers LR_INDEX (preIdx) and the post-drain
                // LR_MID_DAY check below: the _runProcessTicketBatch delegatecall (a CSE barrier)
                // never writes this slot, and the only writer on a path reaching the mid-day check
                // (_requestRng) breaks out before it.
                uint256 lrCached = lootboxRngPacked;
                // Unified sweep: any windowed read-side key may hold committed work — a
                // mid-day batch that crossed the day boundary, the award queue, a
                // future-level cohort, or a self-healing leftover a later swap
                // re-committed. Everything must drain before rngGate's swap re-points
                // the read slot.
                (, bool preFound) = _sweepReadLevel(purchaseLevel);
                // The draw is gated on BOTH the normal queue AND the foil drain: keep
                // draining while the normal queue OR a sealed-but-un-drained foil bucket
                // remains.
                if (preFound || _foilDrainPending()) {
                    uint48 preIdx = uint48(
                        (lrCached >> LR_INDEX_SHIFT) & LR_INDEX_MASK
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
                                if (!preFound) {
                                    _swapTicketSlot();
                                }
                                _freezePool(day);
                                stage = STAGE_RNG_REQUESTED;
                                break;
                            }
                            // A stalled DAILY request dead-ends here — the cohort needs
                            // the word this gate is waiting for, and rngGate's retry sits
                            // behind the gate. Offer the same single retry on the same
                            // terms (LSB latch, 12h, vault-owner head start): the cohort
                            // is staged and the pool frozen, so the re-request IS the
                            // recovery; _finalizeRngRequest recognizes the daily lock and
                            // finalizes it as a retry.
                            if (
                                rngLockedFlag &&
                                rngRequestTime != 0 &&
                                (rngRequestTime & 1) == 0 &&
                                (ts - rngRequestTime >= DAILY_RNG_RETRY_TIMEOUT ||
                                    (ts - rngRequestTime >=
                                        DAILY_RNG_RETRY_TIMEOUT -
                                            DAILY_RNG_RETRY_HEAD_START &&
                                        IVaultOwnerCheck(ContractAddresses.VAULT)
                                            .isVaultOwner(msg.sender)))
                            ) {
                                _requestRng(lastPurchase, purchaseLevel);
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
                if (((lrCached >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK) != 0) {
                    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
                }
            }

            // --- Afking process STAGE: stamp the funded subscriber set BEFORE the day
            // requests its RNG. Runs on the new-day path only, after the daily
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
            // Forward-looking per-day reset: the first UNLOCKED advance entry of a new
            // `day` flips the drain gate + cursor BEFORE that day's STAGE runs (locked
            // entries skip the whole block below, so a stall never spends resets or
            // walks). subsFullyProcessed stays true after a day's STAGE completes (it
            // means "afking done for that day") until the next unlocked new-day entry
            // flips it here. Stamped to `day` at the reset, so it fires exactly once
            // per day and never re-fires within the day (independent of when dailyIdx
            // catches up in _unlockRng).
            // VRF-outstanding gate: the STAGE never runs while rngLockedFlag is set
            // [request -> unlock]. In that window the walk can do nothing — every live
            // sub is stamped ahead (the AlreadyAutoBoughtToday skip), pending boxes are
            // no-orphan-protected, and subscribe/cancel revert under the freeze, so
            // no tombstones can appear mid-window. Gating entry here also
            // makes the one heavy composition structurally impossible: a completing
            // subscriber chunk can never share a tx with a buffered-word apply or a
            // gap backfill (both run under the lock, released only at _unlockRng), so
            // the chunk and the ~10M jackpot/backfill legs never fuse against the
            // per-tx gas ceiling — at ANY subscriber cap. The stamp-before-request
            // ordering is untouched: an unlocked advance walks the stage to completion
            // and only then reaches rngGate to fire the day's request.
            if (!locked) {
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
                    }
                    subsFullyProcessed = true;
                }
            }

            // RNG: use existing word or request new one. Precompute the day's coinflip reward
            // bonus from the frozen level: +2 on a bonus day, +6 when the bonus level is an x0
            // BAF level (10, 20, 30, …), 0 otherwise. The bonus day is the SECOND day of a
            // level's jackpot phase — phase entry and jackpot #1 land on the prior (last
            // purchase) day, whose flips settle before the jackpotPhaseFlag write below, so the
            // second day's settlement is the one that observes jackpotCounter == 1. Level-0 days
            // all carry +2. A turbo level's collapsed phase never spans a settlement, so its
            // bonus shifts to the next level's first purchase day, marked by the surviving
            // flag-2 latch _endPhase preserves; rngGate consumes it at that settlement. When
            // that same day arms the next turbo (back-to-back chain), the arm escalates the
            // latch to 3 — armed + bonus owed — so every post-payout day of a chain still
            // carries its own bonus; the settlement drops 3 back to 2 for tonight's
            // collapse. A plain fresh arm's flag 2 on a last-purchase day is excluded, as a
            // non-post-turbo day. The bonus keys the COLLAPSED level: lvl names it directly
            // except on a flag-3 day once the arm request has pre-incremented (locked),
            // where it is lvl - 1. Sized so a recycling (auto-rebuy) player nets ~99.9% /
            // ~101.9% RTP once the 0.75% recycle bonus compounds in.
            bool bonusDay = (inJackpot && jackpotCounter == 1) ||
                lvl == 0 ||
                (!inJackpot &&
                    (compressedJackpotFlag == 3 ||
                        (!lastPurchase && compressedJackpotFlag == 2)));
            uint24 bonusLvl = (compressedJackpotFlag == 3 && locked)
                ? lvl - 1
                : lvl;
            uint8 coinflipBonus = bonusDay
                ? (bonusLvl != 0 && bonusLvl % 10 == 0 ? 6 : 2)
                : 0;
            (uint256 rngWord, uint32 gapDays) = rngGate(
                ts,
                day,
                purchaseLevel,
                lastPurchase,
                coinflipBonus,
                dIdx
            );
            psd += uint24(gapDays);
            if (rngWord == 1) {
                // Sentinel from an already-locked entry = the daily retry re-firing the
                // outstanding request. The original request's swap already committed the
                // read cohort; swapping again would flip it back to the write slot
                // mid-drain. Only an unlocked entry (fresh request or promoted mid-day
                // stall) commits the buffer here.
                if (!locked) {
                    _swapTicketSlot();
                }
                _freezePool(day);
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
                // At new level L the near-future boundary is >L+5, so L+5 is near-future.
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

            // Unified sweep over the windowed read keys (routed cohort first); an
            // empty-window call is the foil drain's continuation vehicle.
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(
                purchaseLevel
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
                    bool targetMet = _getNextPrizePool() >
                        _prizePoolTarget(purchaseLevel);
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

                // Consolidate prize pools for level transition. A century level's
                // achieved pool is also appended to the century history, which is the
                // only place it survives: _endPhase later overwrites levelPrizePool[x00]
                // with the reachable x01 ratchet base.
                {
                    uint256 achievedPool = _getNextPrizePool();
                    levelPrizePool[purchaseLevel] = achievedPool;
                    if (purchaseLevel % 100 == 0) {
                        centuryPrizePools.push(uint128(achievedPool));
                    }
                    // Banking this entry finalizes growth round purchaseLevel - 1; settle
                    // it after the century append so a century term reads its pushed pool.
                    // Level 1 has no round to settle (round 0 never opens), which also
                    // keeps purchaseLevel - 2 from underflowing.
                    if (purchaseLevel >= 2) {
                        parimutuel.recordGrowth(
                            purchaseLevel - 1,
                            _growthOver(
                                _growthRatchet(purchaseLevel - 2),
                                _growthRatchet(purchaseLevel - 1),
                                achievedPool
                            )
                        );
                    }
                }
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
            _getNextPrizePool() > _prizePoolTarget(lvl + 1) &&
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
        // Terminal entropy is two-case by design: a real word if VRF works, the
        // fallback if it does not — and BOTH buffers clear against whichever one
        // applies. A DELIVERED word blocks the write swap permanently (entries may
        // postdate it), but a dead request does not: once the fallback regime is
        // due, the terminal word will be derived AFTER the liveness gate froze
        // purchases, so every write-side entry predates it and the abandonment
        // cohort commits and drains like any other. The read cohort always drains
        // first (branch priority below), so the swap can never displace it.
        // The regime is LATCHED at derivation (LR_GO_FALLBACK): the committed
        // fallback replays through rngWordCurrent for entropy idempotence, which
        // would otherwise read as a delivered word here and re-block the write
        // swap on the entry after the read cohort releases.
        bool deliveredWord = dayWord != 0 || rngWordCurrent != 0;
        bool fallbackDue = _lrRead(LR_GO_FALLBACK_SHIFT, LR_GO_FALLBACK_MASK) !=
            0 ||
            (!deliveredWord &&
                (((jackpotPhaseFlag || lastPurchaseDay) && _vrfDeadmanFired()) ||
                    (rngRequestTime != 0 &&
                        uint48(block.timestamp) - rngRequestTime >=
                        GAMEOVER_RNG_FALLBACK_DELAY)));
        bool entropyCommitted = !fallbackDue &&
            (deliveredWord ||
                vrfRequestId != 0 ||
                rngLockedFlag ||
                prizePoolFrozen ||
                _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 0);
        // Terminal scope: the payout samples only lvlTraitEntry[drainLevel], so the
        // probes and the swap decision are drainLevel-only; every other windowed
        // cohort is dead value whether materialized or not (its level never draws)
        // and is discarded at the drain step below, after the terminal entropy
        // commitment makes termination irreversible.
        bool readPending = ticketQueue[_tqReadKey(drainLevel)].length != 0;
        bool writePending = ticketQueue[_tqWriteKey(drainLevel)].length != 0;
        if (readPending) {
            // The selected read queue is already the oldest committed snapshot. Trust the queue
            // itself over a stale-true completion flag and resume it without touching write state.
            ticketsFullyProcessed = false;
        } else if (
            writePending &&
            !entropyCommitted &&
            _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0
        ) {
            // No selected read cohort and no entropy boundary: freeze the abandonment
            // cohort now. ONE terminal swap, ever. Two parities means a single handoff,
            // and every path needs at most that: when no request was in flight the read
            // side is provably empty (rngRequestTime == 0 only after _unlockRng, which
            // follows a completed drain), so this fires once before any word exists;
            // when a request WAS in flight its cohort holds the read side and this is
            // the one handoff behind it. Without the bound the sticky fallback regime
            // would re-promote every later write queue in turn, so a queue created after
            // the terminal word went public could still be drawn.
            _swapTicketSlot();
            _lrWrite(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK, 1);
        } else if (_foilDrainPending()) {
            ticketsFullyProcessed = false;
        }

        // Record which bucket the terminal sequence pays from, while rngLockedFlag still
        // carries its normal meaning. The VRF-dead and failed-request branches below take
        // the lock themselves (the successful-request path already gets it from
        // _finalizeRngRequest), and _gameOverTicketLevel would otherwise read that lock as
        // "the last-purchase request already promoted level" and move the bucket between
        // transactions. Latched once, before any of those branches run.
        if (_lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0) {
            _lrWrite(
                LR_GO_LVL_SHIFT,
                LR_GO_LVL_MASK,
                drainLevel == lvl ? 1 : 2
            );
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

        // Re-ask now that a word exists. The probe above ran before the entropy step, so
        // on the transaction that commits the fallback it could not yet see the regime
        // that makes an unworded foil bucket drainable — the latch and rngWordCurrent are
        // both written inside the call above. Without this second look a game whose only
        // outstanding work is such a bucket keeps ticketsFullyProcessed true, skips the
        // worker, and pays the terminal jackpot with those paid packs missing from the
        // trait buckets while their ETH is still in the distributed pool.
        if (ticketsFullyProcessed && _foilDrainPending()) {
            ticketsFullyProcessed = false;
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
            // TICKET_SLOT_BIT on the anchor asks the worker for its single-key
            // terminal mode: drain exactly drainLevel plus the foil tail — every
            // queued ticket at any other level is worthless at game over and is
            // never touched.
            (bool dOk, bytes memory dData) = ContractAddresses
                .GAME_MINT_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameMintModule.processTicketBatch.selector,
                        drainLevel | TICKET_SLOT_BIT
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
        // Turbo (2) survives phase end as the coinflip bonus-day latch: a
        // collapsed phase never spans a flip settlement, so the level's bonus
        // day shifts to the next level's first purchase day, where rngGate
        // consumes the latch. Compressed (1) keeps a real second jackpot day
        // and clears here like a normal level.
        if (compressedJackpotFlag < 2) compressedJackpotFlag = 0;
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
        // stays in futurePool (less the century incinerator payout at x00), and
        // pre-skip winning-flip credit is filtered out of future claims via the
        // lastBafResolvedDay bump.
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

                // Century BAF incinerator: level-x99 WWXRP burners bet on this
                // exact skip. 25% of the would-be BAF pool pays one
                // burn-weighted winner; the rest rolls forward in futurePool
                // as on any skip. An empty bracket leaves the full pool.
                if (prevMod100 == 0) {
                    uint256 incinPoolWei = ((baseMemFuture * 20) / 100) / 4;
                    if (incinPoolWei != 0) {
                        address incinWinner = wwxrpIncinerator.resolveIncinerator(
                            lvl,
                            rngWord,
                            incinPoolWei
                        );
                        if (incinWinner != address(0)) {
                            _creditClaimable(incinWinner, incinPoolWei);
                            memFuture -= incinPoolWei;
                            claimableDelta += incinPoolWei;
                        }
                    }
                }
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
        // Decline to issue while the block is expensive: the fulfillment is billed at the
        // node's gas price a block or so later, so holding the request back while the
        // basefee is high bounds what a mid-day word can cost the subscription. Gates only
        // this path — the daily advance must run at any price — so a refused request just
        // leaves the pending boxes to the next daily word. Zero disables the gate.
        {
            uint256 maxBasefee = _lrRead(
                LR_MAX_BASEFEE_SHIFT,
                LR_MAX_BASEFEE_MASK
            );
            if (maxBasefee != 0 && block.basefee > maxBasefee * 1 gwei) {
                revert GasTooHigh();
            }
        }
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

        // Threshold check: pending ETH must clear the owner-tunable threshold. This gates
        // only the mid-day fast path — the daily advance assigns the day's word to
        // the current index regardless, so pending boxes never wait past one cycle.
        uint256 pendingEth = _unpackMilliEthToWei(
            uint64(_lrRead(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK))
        );
        // Pending FLIP counts as work outstanding but adds nothing to the threshold: only ETH
        // pays for a mid-day word, so only ETH justifies buying one. A FLIP-denominated queue
        // resolves on the daily word instead, and anyone wanting it sooner can donate LINK for
        // the credit that waives this gate, or have an ETH buyer trigger it.
        bool noPending = pendingEth == 0 &&
            _lrRead(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK) == 0;
        uint256 totalEthEquivalent = pendingEth;
        uint256 threshold = _unpackMilliEthToWei(
            uint64(_lrRead(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK))
        );
        // Donation credit waives both pending-value gates — an empty queue and a
        // below-threshold one alike. Charged only where one actually binds, so a request
        // that already clears them costs a holder nothing, and a caller holding no credit
        // still gets the specific gate as the revert. Ordered after the LINK floor above
        // so credit is never charged for a request the subscription cannot pay for.
        if (noPending || (threshold != 0 && totalEthEquivalent < threshold)) {
            if (!_tryChargeMiddayCredit()) {
                if (noPending) revert NoPendingLootbox();
                revert BelowThreshold();
            }
        }

        // Freeze ticket buffer: swap write→read so tickets purchased after
        // VRF delivery can't be resolved by this word. Any write-side key in the
        // trailing window may hold pending work (this path reverts while
        // rngLockedFlag is set, so the building level here is always level + 1
        // and the window is [level .. level + 5]). Stranding is impossible either
        // way — the unified sweep keeps naming a retired level until both its
        // parities are empty — but the guard below protects DRAW ELIGIBILITY:
        // when the NEXT daily request caps the jackpot counter, a freeze window
        // opened now can cross into that final day via a stalled-word promotion,
        // which cannot swap (the committed cohort occupies the read slot). The
        // stall-window buys would then materialize only after the level retires —
        // safe but drawless. Skipping the swap keeps the whole evening cohort
        // together on the write side for the final request's own commit, which
        // its chain drains BEFORE the final draw. The word still serves the
        // pending lootboxes.
        {
            bool lastSwapAhead;
            if (jackpotPhaseFlag) {
                uint8 cnt = jackpotCounter;
                uint8 comp = compressedJackpotFlag;
                uint8 step = comp == 2
                    ? JACKPOT_LEVEL_CAP
                    : (comp == 1 && cnt > 0 && cnt < JACKPOT_LEVEL_CAP - 1 ? 2 : 1);
                lastSwapAhead = cnt + step >= JACKPOT_LEVEL_CAP;
            }
            if (!lastSwapAhead) {
                bool queuedWork;
                uint24 t = level;
                uint24 end = level + 5;
                for (; t <= end; ) {
                    if (ticketQueue[_tqWriteKey(t)].length > 0) {
                        queuedWork = true;
                        break;
                    }
                    unchecked {
                        ++t;
                    }
                }
                if (queuedWork && ticketsFullyProcessed) {
                    _swapTicketSlot();
                    _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
                }
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
    // 0        Coinflip win/loss           rngWord & 1                       Coinflip.processCoinflipPayouts
    // 0        BAF fire gate               rngWord & 1                       AdvanceModule._consolidatePoolsAndRewardJackpots
    // 8+       Redemption roll             (currentWord >> 8) % 151 + 25     AdvanceModule.rngGate
    // full     Coinflip reward percent     keccak256(rngWord, epoch) % 20    Coinflip.processCoinflipPayouts
    // full     Jackpot winner selection    via delegatecall (full word)      JackpotModule (payDailyJackpot)
    // full     Coin jackpot                via delegatecall (full word)      AdvanceModule._payDailyCoinJackpot -> payDailyFlipJackpot
    // 64+/192+ Future take variance        (rngWord>>64/>>192) % range       _consolidatePoolsAndRewardJackpots
    // low      Additive skim random        rngWord % (ADDITIVE_RANDOM_BPS+1) _consolidatePoolsAndRewardJackpots
    // full     Prize pool consolidation    in-module memory batch            _consolidatePoolsAndRewardJackpots
    // full     Reward jackpots (BAF/Dec)   self-call (BAF/Decimator)         _consolidatePoolsAndRewardJackpots
    // full     Incinerator winner           domain-hashed in WWXRP            _consolidatePoolsAndRewardJackpots -> WWXRP.resolveIncinerator
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
        uint8 coinflipBonus,
        uint24 dIdx
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
            // dIdx == dailyIdx here (caller cached it; _unlockRng, the sole writer, runs after
            // rngGate returns), so reuse it instead of re-SLOADing the slot-0 field.
            uint24 idx = dIdx;
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
            // Consume the turbo coinflip-bonus latch once the settlement it
            // marks (the next level's first purchase day) has been paid. A
            // chained day's flag 3 drops to 2 — the freshly-armed turbo for
            // tonight's collapse; a plain fresh arm's 2 stays for the same
            // reason; a spent latch (2 on a non-arm day) clears.
            if (compressedJackpotFlag == 3) {
                compressedJackpotFlag = 2;
            } else if (
                compressedJackpotFlag == 2 &&
                !jackpotPhaseFlag &&
                !isTicketJackpotDay
            ) {
                compressedJackpotFlag = 0;
            }
            // Force the MINT_FLIP daily on the first jackpot day (lastPurchaseDay still set here,
            // jackpot not yet entered) so the FLIP-mint quest only lands when the redeem window is
            // live. Turbo (compressedJackpotFlag == 2) is skipped — its jackpot collapses at this
            // request, leaving no full open day for that quest.
            // Force the buy-a-foil-pack daily on the day the purchase phase opens — the day
            // whose jackpot run is the level's last, since the transition drains and reopens
            // purchasing later in that same day. Whether this pass carries the final run is
            // already decidable here, by the step arithmetic the redemption-close mirrors:
            // turbo collapses all five logical days at the transition request (jackpotPhaseFlag
            // is not yet set, so isTicketJackpotDay stands in for it), compressed advances two
            // at a time mid-phase, everything else one. (phaseTransitionActive cannot serve
            // here: it is raised after the day's word is recorded and dropped before
            // _unlockRng, so every roll while it is set takes the recorded-word early return
            // above.) Never collides with the MINT_FLIP force below: that fires on a level's
            // first jackpot day, which is final only for turbo — where its own flag-2 exclusion
            // already stands it down. Gated on gapDays == 0 so a VRF-stall backfill (which
            // defers the whole transition to the next advance, line 412) does not roll the
            // foil quest early.
            //
            // Force the decimator daily on the day a burn window arms. decDayOneActive is
            // exactly that day: the arming request raises it a few lines after opening the
            // window, and only the NEXT day's fresh request clears it, so it still reads true
            // when this roll consumes the arming day's word. It outranks the other two forces
            // (see rollDailyQuest), which costs the MINT_FLIP force on x4/x99 levels — the
            // arming day is also those levels' first jackpot day.
            //
            // All three forces are skipped entirely on a late-consumed word (buffered RNGREUSE
            // clamp: day < wall day): that day's quest never rolled while the day was live, so
            // a roll now would create a retroactive quest that immediately counts as a rolled
            // miss against every streak. The day stays unrolled — forgiven, matching
            // gap-backfill days.
            uint8 foilJpStep = 1;
            if (compressedJackpotFlag == 2 && jackpotCounter == 0) {
                foilJpStep = JACKPOT_LEVEL_CAP;
            } else if (
                compressedJackpotFlag == 1 &&
                jackpotCounter > 0 &&
                jackpotCounter < JACKPOT_LEVEL_CAP - 1
            ) {
                foilJpStep = 2;
            }
            bool finalJackpotRun = (jackpotPhaseFlag || isTicketJackpotDay) &&
                jackpotCounter + foilJpStep >= JACKPOT_LEVEL_CAP;
            if (day == _simulatedDayIndexAt(ts)) {
                quests.rollDailyQuest(
                    day,
                    currentWord,
                    lastPurchaseDay && compressedJackpotFlag < 2,
                    finalJackpotRun && gapDays == 0,
                    decDayOneActive && gapDays == 0
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

    /// @dev Charge the caller's donation credit for one mid-day request, in the LINK the
    ///      subscription is billed in: the gas a fulfillment bills at this block's
    ///      basefee, times MIDDAY_RNG_CHARGE_MULT, converted at the same capped and
    ///      staleness-checked feed the donation reward values with. Pricing from what the
    ///      request actually costs, rather than a stored rate, keeps the charge tracking
    ///      gas as it moves. The markup is not a surplus at every price: a fulfillment
    ///      landing above 5x the request block's basefee, or a feed reading above the
    ///      coordinator's own LINK valuation, bills more than the redemption charged. The
    ///      LINK floor gating this request is what bounds the drain that opens up.
    ///      Priced off block.basefee, not tx.gasprice: the requester sets the latter and
    ///      could otherwise submit at a trivial price to be charged almost nothing while
    ///      the node fulfills at market. Basefee omits the node's tip; the multiple covers
    ///      it. A feed that cannot price right now returns zero and the waiver is refused
    ///      rather than granted free — the free path is unaffected either way.
    /// @return charged True if the caller's balance covered the charge.
    function _tryChargeMiddayCredit() private returns (bool charged) {
        uint256 balance = middayRngCredit[msg.sender];
        // A zero balance never qualifies, even where basefee (and so the charge) is zero.
        if (balance == 0) return false;

        uint256 weiPerLink = IAdminLinkValue(ContractAddresses.ADMIN)
            .linkAmountToEth(1 ether);
        if (weiPerLink == 0) return false;

        uint256 charge = (MIDDAY_RNG_BILLED_GAS *
            block.basefee *
            MIDDAY_RNG_CHARGE_MULT *
            1 ether) / weiPerLink;
        if (balance < charge) return false;
        unchecked {
            balance -= charge;
        }
        middayRngCredit[msg.sender] = balance;
        emit MiddayRngCreditSpent(msg.sender, charge, balance);
        return true;
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
    ///      Also resolves any pending gambling burn redemptions (mirrors rngGate behavior).
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
            // The terminal cohorts must compose against fresh-or-fallback entropy,
            // never the last delivered (public) word: when no empty reserved slot
            // exists (VRF died with no request in flight, or the terminal request
            // attempt reverted without advancing the index), reserve a fresh slot
            // so the fallback word becomes the drain's entropy.
            if (
                lootboxRngWordByIndex[
                    uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1
                ] != 0
            ) {
                _lrAdvanceIndexClearPending();
            }
            _finalizeLootboxRng(fallbackWord);
            // A deadman entry with no request ever armed must still latch the timer:
            // rngWordCurrent now holds the committed fallback, and an armed timer makes
            // a terminal drain that crosses a wall-day boundary take the delivered-word
            // replay branch above — the SAME word instead of a second fallback that
            // would drift the cohort's entropy mid-drain.
            if (rngRequestTime == 0) {
                rngRequestTime = ts;
            }
            // Latch the fallback regime for the multi-tx drain: the replayed word
            // reads as delivered on later entries, and without the latch the
            // write-buffer swap _handleGameOverPath owes the abandonment cohort
            // would stay blocked.
            _lrWrite(LR_GO_FALLBACK_SHIFT, LR_GO_FALLBACK_MASK, 1);
            // Take the RNG lock the successful-request path gets from
            // _finalizeRngRequest. A word is committed right here and consumed by later
            // calls, so this is an RNG window like any other — but it is the one the
            // normal path never reaches, which is why every lock-keyed guard
            // (reverseFlip, requestLootboxRng, far-future queueing, subscribe) has been
            // reading an unlocked state through the whole terminal drain. The swap
            // decision upstream has already been made this call, and later calls stay
            // swap-eligible through fallbackDue, so the lock cannot suppress it.
            //
            // Coupling worth knowing: holding the lock also arms the "buffered" arm of
            // the RNGREUSE day clamp, so from here on `day` resolves to dailyIdx + 1
            // rather than the wall day. That is entropy-neutral — the replay branch
            // writes this same word to whichever day key it lands on, and _unlockRng
            // leaves dailyIdx stale at game over — but it does decide which day key the
            // terminal coinflip settlement, handleGameOverDrain, and the terminal events
            // record against.
            rngLockedFlag = true;
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
        // The timer alone suffices here: no word exists yet, so nothing is predictable,
        // and this state feeds the fallback branch above — which takes the real lock at
        // the moment it commits a word.
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


    /*+======================================================================+
      |                    TICKET / TOKEN AIRDROP BATCHING                   |
      +======================================================================+
      |  Ticket entries are processed in batches to prevent gas exhaustion.  |
      |  Large purchases are queued and processed across multiple txs.       |
      +======================================================================+*/

    /// @dev Run the windowed ticket sweep via mint module delegatecall: one writes
    ///      budget drains the read window [anchor-1 .. anchor+4] plus foil.
    /// @param lvl The window anchor (purchaseLevel).
    /// @return worked True if the batch materialized at least one ticket or foil entry.
    ///         Reported directly by the mint module rather than inferred from a cursor
    ///         delta, so a batch that both starts and finishes in one call (cursor returns
    ///         to 0) still reports its work and the chain breaks before BAF/jackpot.
    /// @return finished True when the whole window and the foil drain are caught up.
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

    /// @dev The unified sweep's key picker: the first non-empty READ-side plain queue in
    ///      the six-level window [purchaseLevel-1 .. purchaseLevel+4] — one key per level
    ///      the distance routing can currently target (plain iff target <= level + 5)
    ///      plus the trailing key. Ascending order is routed-priority in both phases: in
    ///      the jackpot phase purchaseLevel-1 IS the routed level, and in the purchase
    ///      phase purchaseLevel-1 is the just-finished level, whose self-healing
    ///      leftovers must drain first anyway. The trailing key keeps a retired level
    ///      named until both its parities are provably empty — a leftover re-committed
    ///      by any later swap drains instead of stranding. Far-future keys are never
    ///      probed: each is emptied once per level by the transition's crossing drain
    ///      and is write-dead afterward.
    function _sweepReadLevel(
        uint24 purchaseLevel
    ) private view returns (uint24 pick, bool found) {
        unchecked {
            uint24 t = purchaseLevel == 0 ? 0 : purchaseLevel - 1;
            uint24 end = purchaseLevel + 4;
            for (; t <= end; ++t) {
                if (ticketQueue[_tqReadKey(t)].length > 0) {
                    return (t, true);
                }
            }
        }
        return (purchaseLevel, false);
    }

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
    ///
    ///      The freeze is the volume round's crossover: buys route to pending from here,
    ///      so the live counter is final and is pushed to the market before the unfreeze
    ///      overwrites it. A re-entered freeze closes no round and pushes nothing.
    /// @param round The round closing at this crossover.
    function _freezePool(uint24 round) internal {
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            parimutuel.recordVolume(round, _getLiveTicketVolume());
            uint256 futureBal = _getFuturePrizePool();
            uint256 seed = futureBal / 100;
            _setFuturePrizePool(futureBal - seed);
            // Full reset: the seed lands in the pending future half and the volume counter
            // starts the new round at zero.
            _resetPendingPools(0, uint128(seed));
        }
    }

    /// @dev Whether a growth round resolves OVER: the successor's growth RATE strictly
    ///      exceeds the round's own — cross-multiplied (nextR * prevR > currR * currR) so
    ///      the comparison is exact, unsigned, division-free. Ties are UNDER.
    function _growthOver(
        uint256 prevR,
        uint256 currR,
        uint256 nextR
    ) internal pure returns (bool) {
        return nextR * prevR > currR * currR;
    }

    /// @dev Fold pending into live and clear freeze; no-op if not frozen. One read and
    ///      one write per slot: the halves ADD (saturating), the volume counter ROLLS —
    ///      its outgoing value was already scored at the freeze.
    function _unfreezePool() internal {
        if (!prizePoolFrozen) return;
        uint256 pending = prizePoolPendingPacked;
        uint256 live = prizePoolsPacked;
        uint256 next = (live & POOL_HALF_MAX) + (pending & POOL_HALF_MAX);
        uint256 future = ((live >> POOL_FUTURE_SHIFT) & POOL_HALF_MAX) +
            ((pending >> POOL_FUTURE_SHIFT) & POOL_HALF_MAX);
        if (next > POOL_HALF_MAX) next = POOL_HALF_MAX;
        if (future > POOL_HALF_MAX) future = POOL_HALF_MAX;
        prizePoolsPacked =
            (pending & ~POOL_HALVES_MASK) |
            (future << POOL_FUTURE_SHIFT) |
            next;
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

        // Decimator day-one bonus window closes at the next fresh daily request.
        // A retry re-requests the SAME day's word, so it must not clear the latch.
        // Runs before the window-open branch below, so the arming request itself
        // (clear-then-set) leaves the latch armed.
        if (!isDailyRetry && decDayOneActive) {
            decDayOneActive = false;
        }

        // Close the FLIP purchase window at the final jackpot day's RNG request — the boundary where
        // new tickets begin routing to the next level (mirrors the route-to-level+1 step in the mint
        // module). jackpotCounter + step catches the final daily jackpot; the isTicketJackpotDay
        // (level-transition) request catches the single-day turbo jackpot, where jackpotPhaseFlag is
        // not yet set here.
        if (ticketRedemptionOpen && (jackpotPhaseFlag || isTicketJackpotDay)) {
            uint8 jpStep = 1;
            // >= 2 covers the chained-arm request, whose flag is 3 (turbo + owed latch).
            if (compressedJackpotFlag >= 2 && jackpotCounter == 0) {
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

            // Fold a reached thanos declaration into the active shift: from this
            // level onward every drain target resolves to the declared exponent via
            // snapShift, and the pending pair frees for the next declaration.
            {
                uint24 pl = snapLevel;
                if (pl != 0 && lvl >= pl) {
                    snapShift = snapPendingShift;
                    snapLevel = 0;
                }
            }

            // Decimator window: open at x4/x99, close at x5/x00
            uint24 mod100 = lvl % 100;
            uint24 mod10 = lvl % 10;
            if ((mod10 == 4 && mod100 != 94) || mod100 == 99) {
                decWindowOpen = true;
                // Arm the day-one burn bonus: recordDecBurn grants the boosted
                // weight until the next fresh daily request clears the latch.
                decDayOneActive = true;
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
        // Game-over keeps its stale dailyIdx: the deadman reads currentDay - dailyIdx, so
        // advancing it here would retire the very staleness that declared the game dead and
        // let _livenessTriggered read false again while gameOver stays true — reopening every
        // liveness-gated paid entrypoint. A dead game seals no day, so nothing else wants it.
        if (!gameOver) dailyIdx = day;
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
            // One packed SLOAD for next|future (via-IR does not coalesce the two tuple getters).
            (uint128 nextP, uint128 futureP) = _getPrizePools();
            emit PrizePoolDailySnapshot(
                nextP,
                futureP,
                _getCurrentPrizePool(),
                claimablePool,
                address(this).balance + steth.balanceOf(address(this)),
                yieldAccumulator
            );
            _afKingSubDraw(day);
        }
    }

    /// @dev Daily seat-tenure drawing, run once per day-seal: one uniform draw over
    ///      the afking ring, FLIP prize proportional to the winner's funded tenure
    ///      (10/day, capped 4,000 — EV-identical to a tenure-weighted draw with a
    ///      fixed prize, but selection is O(1)). Index 0 is the VAULT's pinned
    ///      construction slot (never relocated: the vault is never killed or
    ///      cancelled, and a swap-pop only moves the tail into a freed slot) and is
    ///      excluded; index 1 (sDGNRS) and every player sub are eligible. A drawn
    ///      tombstone or span-0 sub (no live run, or day-0) is a dud day — no
    ///      payout, no re-probe, keeping the draw O(1); the ring is post-STAGE at
    ///      the seal so duds are rare.
    ///      RNG-freeze: every input is frozen across [request -> unlock] — the ring
    ///      and Sub span fields mutate only in the pre-request STAGE and the
    ///      lock-gated subscribe/cancel path — and the word is domain-separated
    ///      ("SEATDRAW") from every other consumer. Gap days backfilled after a
    ///      stall never seal through _unlockRng, so they hold no drawing.
    function _afKingSubDraw(uint24 day) private {
        uint256 len = _subscribers.length;
        uint256 word = rngWordByDay[day];
        if (len < 2 || word == 0) return;
        uint256 idx = 1 +
            (uint256(keccak256(abi.encodePacked("SEATDRAW", word))) % (len - 1));
        address winner = _subscribers[idx];
        Sub storage s = _subOf[winner];
        uint24 startDay = s.afkingStartDay;
        uint24 covered = s.afkCoveredThroughDay;
        if (s.dailyQuantity == 0 || startDay == 0 || covered <= startDay) return;
        uint256 spanDays;
        unchecked {
            spanDays = covered - startDay;
        }
        uint256 prize = spanDays * SEAT_DRAW_FLIP_PER_DAY;
        if (prize > SEAT_DRAW_MAX_FLIP) prize = SEAT_DRAW_MAX_FLIP;
        coinflip.creditFlip(winner, prize * 1 ether);
        emit SubDrawWon(winner, day, uint24(spanDays), prize);
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
