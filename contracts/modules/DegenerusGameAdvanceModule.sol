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

import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {
    IDegenerusGameGameOverModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule,
    IDegenerusGameFoilPackModule,
    IDegenerusGameBoonModule,
    IGameAfkingModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";

/// @dev The craps table's daily opener. Only the game may call it, and it never reverts — see
///      `CrapsBattle.openBonusDay`.
interface ICrapsBonusDay {
    /// @notice CrapsBattle's daily bonus-window opener.
    function openBonusDay() external;
}

/// @dev The table's pass-credit door, for the house's level cut. Called BARE from the level
///      close — no stipend, no try/catch — because `creditPasses` is revert-free for the game by
///      contract: a full lane saturates and reports rather than throws.
interface ICrapsPassCredit {
    /// @notice CrapsBattle's revert-free bank of `normal`/`high` pass credits to `player`.
    function creditPasses(address player, uint32 normal, uint32 high) external;
}

/// @dev GNRUS interface for level-transition governance resolution.
interface IGNRUSResolve {
    /// @notice GNRUS's charity-pick resolution for `level`.
    function pickCharity(uint24 level) external;
}

/// @dev Admin surface for the guarded LINK/ETH valuation. Passing one whole LINK yields
///      wei-per-LINK, capped and staleness-checked, or zero when it cannot be priced.
interface IAdminLinkValue {
    /// @notice DegenerusAdmin's guarded LINK-to-ETH valuation for `amount`.
    function linkAmountToEth(uint256 amount) external view returns (uint256);
}

/// @dev Vault interface for the >50.1%-DGVE owner check (the vault-owner-only daily VRF retry).
interface IVaultOwnerCheck {
    /// @notice DegenerusVault's majority-DGVE-holder check for `account`.
    function isVaultOwner(address account) external view returns (bool);
}

/// @dev WWXRP surface for the century BAF-incinerator draw: level-x99 burn
///      entries resolve to one winner when the x00 BAF skips.
interface IWwxrpIncinerator {
    /// @notice WWXRP's incinerator draw: resolves `bracket` to one winner and credits its FLIP award.
    ///         WWXRP returns the winner; the crank has no use for it, so the surface omits the
    ///         decode (the selector is unchanged).
    function resolveIncinerator(uint24 bracket, uint256 rngWord) external;
}

/// @notice Delegate-called module for advanceGame and VRF lifecycle handling.
contract DegenerusGameAdvanceModule is DegenerusGameStorage {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage
    /// @notice Thrown when a mid-day ticket-swap VRF request is already in flight, blocking
    ///         another lootbox RNG request.
    error MidDayActive();
    /// @notice Thrown within the 1-minute pre-reset window before the daily boundary, where a
    ///         request would compete with daily jackpot RNG.
    error PreResetWindow();
    /// @notice Thrown when the VRF subscription's LINK balance is below the minimum required
    ///         for a lootbox RNG request.
    error InsufficientLink();
    /// @notice Thrown when there is no pending lootbox ETH or FLIP value to trigger a mid-day
    ///         RNG request for.
    error NoPendingLootbox();
    /// @notice Thrown when the pending lootbox ETH-equivalent value is below the configured
    ///         threshold required to trigger mid-day RNG.
    error BelowThreshold();
    /// @notice Thrown when a VRF request is already in flight (`rngRequestTime != 0`).
    error RngInFlight();
    /// @notice Thrown when the block basefee is above the mid-day ceiling, where the request
    ///         would bill the subscription at a bad price.
    error GasTooHigh();
    /// @notice Thrown when advance is called before its daily boundary time has arrived.
    error NotTimeYet();
    /// @notice Thrown when a required RNG word has not been fulfilled yet.
    error RngNotReady();
    // error RngLocked() — inherited from DegenerusGameStorage

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    /// @notice Emitted at the end of an advanceGame call, reporting the stage it stopped at.
    /// @param stage The STAGE_* constant the advance reached.
    /// @param lvl The level live when the advance stopped.
    event Advance(uint8 stage, uint24 lvl);
    /// @dev The level-transition skim, reported as the two amounts it moves: `take` from
    ///      next into future, `insuranceSkim` from next into the yield accumulator. The
    ///      curve that sized them is deliberately not carried — the take is already
    ///      post-variance and post-cap, so no ratio of these fields reproduces the bps,
    ///      and publishing one invites reconstructing the curve off-chain instead of
    ///      reading the outcome.
    event PoolSkimApplied(uint24 indexed lvl, uint256 take, uint256 insuranceSkim);

    /// @dev Every pool balance as the level transition leaves it, emitted after the pool
    ///      SSTOREs and the claimablePool credit. This is the pool truth and never the
    ///      phase truth: jackpotPhaseFlag, lastPurchaseDay and the level quest roll all
    ///      happen after this function returns, so a reader that treats this as "the
    ///      transition completed" is one state write ahead of the chain.
    event PoolsSettled(
        uint24 indexed lvl,
        uint24 day,
        uint24 purchaseStartDay,
        uint256 nextPool,
        uint256 futurePool,
        uint256 currentPool,
        uint256 yieldAccumulator,
        uint256 claimablePool,
        uint256 claimableDelta
    );

    // Advance stage constants (sequential, matching advanceGame flow)
    uint8 private constant STAGE_GAMEOVER = 0;
    uint8 private constant STAGE_RNG_REQUESTED = 1;
    // Stage 2 (a multi-advance transition drain) is retired: the transition closes in one advance.
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
    ///      re-entry (gapDays == 0 next call) and dailyIdx sits at the wall day minus one, so
    ///      advanceDue() stays true and the next advance pays the jackpot with the same frozen word.
    uint8 private constant STAGE_GAP_BACKFILLED = 12;
    /// @dev Gas bound on the gap backfill (~9M): the deadman's window plus one day. A live
    ///      gap is always shorter, since the deadman ends the game first. The normal ending's
    ///      terminal word can meet a longer one (nobody advanced for a while after the deadman
    ///      fired): every ticket and foil day up to the trigger lies inside the bound; only
    ///      coinflip stakes placed during that long a wait, on days past it, never settle.
    uint24 private constant GAP_BACKFILL_MAX_DAYS = _VRF_DEADMAN_DAYS + 1;
    /// @dev The carryover ticket leg of a jackpot-phase daily, paid on the advance after
    ///      STAGE_JACKPOT_COIN_TICKETS / STAGE_JACKPOT_PHASE_ENDED priced it, so the two
    ///      96-winner ticket legs never share a tx. Seals the day on a non-final daily.
    uint8 private constant STAGE_JACKPOT_CARRYOVER_TICKETS = 13;
    /// @dev The early-bird ticket leg of the day-1 jackpot-phase daily, paid on the advance
    ///      after STAGE_JACKPOT_DAILY_STARTED priced it and ahead of the coin+tickets stage,
    ///      so the 305-winner ETH leg and the 128-winner early-bird leg never share a tx.
    uint8 private constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    /// @dev The ticket leg of a purchase-phase daily, paid from the advance after the one
    ///      that priced it (STAGE_PURCHASE_DAILY) on the same recorded word; seals the day.
    uint8 private constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    // No deferred-composition stage is left: the subscriber STAGE is entry-gated on
    // !rngLockedFlag, so it can never complete in a tx that also has a buffered word /
    // pending backfill.
    /// @notice Emitted when a day's RNG word is finalized: the raw VRF (or VRF-derived) word plus
    ///         any reverseFlip nudges applied on top of it.
    /// @param day The day the word is recorded for.
    /// @param rawWord The word before nudges.
    /// @param nudges The reversal count added to `rawWord`.
    /// @param finalWord The recorded word: `rawWord + nudges`.
    event DailyRngApplied(uint24 day, uint256 rawWord, uint256 nudges, uint256 finalWord);
    /// @notice Emitted when staking excess ETH into stETH via Lido reverts or Lido is paused.
    /// @param amount The ETH that failed to stake.
    event StEthStakeFailed(uint256 amount);

    /// @notice Emitted when DGNRS is rewarded to the top affiliate.
    /// @param affiliate Address of the top affiliate.
    /// @param level Level for which they were top affiliate.
    /// @param dgnrsAmount Amount of DGNRS paid from the affiliate pool.
    event AffiliateDgnrsReward(address indexed affiliate, uint24 indexed level, uint256 dgnrsAmount);

    /// @notice Emitted when the level's per-affiliate DGNRS claim pool is segregated
    ///         at the level transition — the allocation half of levelDgnrsPacked[lvl],
    ///         which per-affiliate claims draw down against frozen lvl-index scores.
    /// @param level Level the allocation is keyed to.
    /// @param allocation DGNRS amount segregated for per-affiliate claims.
    event LevelDgnrsAllocated(uint24 indexed level, uint256 allocation);

    /// @notice Daily seat-tenure drawing paid out: one uniform draw over the afking
    ///         ring (the VAULT's pinned slot 0 excluded) at each day-seal, prize
    ///         proportional to the winner's funded tenure. A drawn tombstone or
    ///         span-0 sub is a dud day (no event).
    /// @param winner Drawn subscriber credited the FLIP prize
    /// @param day Sealed day whose committed word drove the draw
    /// @param spanDays Winner's funded tenure span (afkCoveredThroughDay - afkingStartDay)
    /// @param flipAmount Whole-FLIP prize (SEAT_DRAW_FLIP_PER_DAY x span, capped)
    event SubDrawWon(address indexed winner, uint24 day, uint24 spanDays, uint256 flipAmount);

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+*/

    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    /// @notice GNRUS contract for governance resolution at level transitions
    IGNRUSResolve private constant charityResolve = IGNRUSResolve(ContractAddresses.GNRUS);
    /// @notice Jackpots contract — direct handle for skip-marker on losing flip days.
    IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    /// @notice WWXRP token — century BAF-incinerator draw resolution.
    IWwxrpIncinerator private constant wwxrpIncinerator = IWwxrpIncinerator(ContractAddresses.WWXRP);
    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+*/

    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;

    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 4;

    /// @dev Age at which an outstanding request — daily, or a mid-day one that bled past the day
    ///      boundary — may be re-sent, by the vault owner only: the one retry, and the last resort
    ///      before a governance coordinator swap. The same 20h genuine-stall grace the admin swap
    ///      proposal waits out.
    uint48 private constant RNG_RETRY_TIMEOUT = 20 hours;

    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 3000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 1500;
    uint16 private constant NEXT_TO_FUTURE_BPS_DEADLINE = 4500;
    uint16 private constant GENESIS_SKIM_BPS_MIN = 1300;
    uint16 private constant GENESIS_SKIM_BPS_DAY_STEP = 14;
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 2500;
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;
    uint16 private constant INSURANCE_SKIM_BPS = 100; // 1% of nextPool -> yieldAccumulator
    uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12_500; // R > 1.25x triggers surcharge
    uint16 private constant OVERSHOOT_CAP_BPS = 3500; // 35% max surcharge
    uint16 private constant OVERSHOOT_COEFF = 4000; // numerator coefficient (0.40 in bps)
    uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000; // 80% total skim hard cap
    uint16 private constant ADDITIVE_RANDOM_BPS = 1000; // 0–10% additive random on bps
    bytes32 private constant FUTURE_KEEP_TAG = keccak256("future-keep");
    bytes32 private constant SKIM_BPS_TAG = keccak256("degenerus.skim.bps");
    bytes32 private constant SKIM_VARIANCE_TAG = keccak256("degenerus.skim.variance");
    bytes32 private constant BONUS_TRAITS_TAG = keccak256("BONUS_TRAITS");
    uint96 private constant MIN_LINK_FOR_LOOTBOX_RNG = 40 ether;
    /// @dev The same floor for the craps table, set to the reserve the never-gated daily word
    ///      actually needs rather than a comfortable multiple of it. At MIDDAY_RNG_BILLED_GAS,
    ///      the coordinator's 20% premium and LINK near 0.004 ETH, one word runs about 0.3 LINK
    ///      at 5 gwei and 6 at 100, so this reserve keeps a daily request funded to roughly 165
    ///      gwei and the lootbox floor above it to roughly 660. Craps reaches deeper because its
    ///      request settles a table already holding staked FLIP, where a lootbox queue can simply
    ///      wait for the daily word it would have shared anyway.
    uint96 private constant MIN_LINK_FOR_CRAPS_RNG = 10 ether;

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
    ///      A large set drains across several advanceGame calls. On the one chunk per level that
    ///      delivers sDGNRS's automatic whale purchase, the STAGE first charges
    ///      `SUB_STAGE_SDGNRS_WHALE_WEIGHT` against this same budget, so that chunk's subscriber
    ///      allowance shrinks by the purchase's weight and the composition stays on target.
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
        // dailyIdx is stable across every read below: its writers (_unlockRng, and the
        // gap skip inside rngGate) execute after the last use, or on paths that return
        // before reaching it.
        // locked is deliberately the ENTRY snapshot: rngGate's retry re-fires the
        // request mid-flow (_finalizeRngRequest), and the sentinel branch below keys
        // its swap decision off the pre-request lock state.
        uint24 dIdx = dailyIdx;
        bool locked = rngLockedFlag;
        // RNGREUSE guard: a delivered word resolves exactly the day its request was issued
        // for, never a later wall day. A request's day is fixed at its fresh send
        // (_finalizeRngRequest stamps rngRequestTime; the vault owner's retry and a
        // coordinator swap re-send it without re-stamping), so while the lock holds a
        // delivered word this advance works on that day. That covers a stalled word landing
        // days late, a day whose processing outruns midnight (chunked drains, split jackpot
        // legs, a phase transition), and a word requested after a gap, which resolves the
        // wall day it was requested on while rngGate derives the skipped days before it. A
        // delivered word is public from its fulfillment tx and flip deposits stay open under
        // the lock targeting wallDay + 1, so a later day's deposits may postdate it — the
        // next day always takes a fresh request. Unlocked, no recorded word sits ahead of
        // dailyIdx (skipped days are never re-walked), so there is nothing to clamp.
        if (day > dIdx + 1 && locked && rngWordCurrent != 0) {
            day = _simulatedDayIndexAt(rngRequestTime);
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
        // An x0 (BAF) purchase level never arms same-day: deposits on day D feed
        // board[D+1], so a same-day collapse would leave the BAF top-flipper board
        // empty. Its turbo-speed latch lives on the evening path instead, keeping a real last-purchase
        // window ahead of the one-day collapse.
        // An ordinary mid-day latch defers the arm, delivered word or not: a turbo latch freezes the
        // next level's pool, which must mint on a word requested after the freeze, and an
        // undrained mid-day cohort's word was requested before it.
        // Latched mid-day stall: the pre-gate retry cannot swap while the
        // committed cohort occupies the read slot, and a collapsed turbo phase issues
        // no sentinel swap — so buys queued after the stalled request would drain (the
        // sweep's trailing window guarantees that) but only after the level retired:
        // safe yet drawless. Defer the arm; the evening target-met latch takes the
        // standard three-day path instead, whose next-day request commits them in time to
        // draw. An isolated early pool (latch 2) was frozen before its own request and
        // leaves the ordinary read buffer free, so it can retain turbo and swap on retry.
        if (
            !inJackpot && !lastPurchaseDay && !locked && day == wallDay && day >= psd && rngWordByDay[day] == 0
                && _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 1
        ) {
            uint32 purchaseDays = day - psd;
            if (purchaseDays <= 1 && lvl % 10 != 9 && _getNextPrizePool() > _prizePoolTarget(lvl + 1)) {
                lastPurchaseDay = true;
                // Arm turbo without discarding an unpaid bonus from the previous level.
                jackpotFlags |= JACKPOT_TURBO;
                // Level L+1's first generation window opens with this latch (see the seal).
                _markTicketGenerationStart(lvl + 2);
            }
        }
        bool lastPurchase = (!inJackpot) && lastPurchaseDay;
        // Level already incremented at RNG request when lastPurchase=true
        uint24 purchaseLevel = (lastPurchase && locked) ? lvl : lvl + 1;
        // During jackpot / last-purchase the trigger can only be the deadman or a dead VRF
        // (the purchase deadline is suppressed there), so those phases enter only when it
        // fires. After a game over, liveness stays true (the drain-level latch, the frozen
        // dailyIdx, or the never-cleared dead request), so the final sweep stays reachable.
        if ((!inJackpot && !lastPurchase) || _livenessTriggered()) {
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
                    uint256 word = lootboxRngWordByIndex[uint48((lrPacked >> LR_INDEX_SHIFT) & LR_INDEX_MASK) - 1];
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
                    (, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
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
            uint256 dayStart = (uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_620;
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
                // LR_MID_DAY check below. A completed isolated pool may change latch 2 to 1;
                // its index and the nonzero test used by the release below stay unchanged.
                // A new request changes the index but breaks before that release.
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
                    uint48 preIdx = uint48((lrCached >> LR_INDEX_SHIFT) & LR_INDEX_MASK) - 1;
                    if (lootboxRngWordByIndex[preIdx] == 0) {
                        uint256 cw = rngWordCurrent;
                        if (cw == 0) {
                            // The outstanding request's word never arrived. The ONE retry is the
                            // vault owner's, RNG_RETRY_TIMEOUT after the send (_rngRetryDue) — the
                            // last resort before a governance coordinator swap.
                            //
                            // A mid-day lootbox request (rngLockedFlag == false) that bled past the
                            // day boundary is re-fired as this day's daily request: _requestRng
                            // takes the daily lock, and its isRetry path preserves the reserved
                            // index so the fresh daily word seals the day AND finalizes this bucket
                            // (preIdx) — just as the mid-day word would have. The stale mid-day
                            // requestId stops matching in rawFulfillRandomWords. Then the ticket
                            // buffer is handled like a normal daily request: if the read slot is
                            // drained, swap the write slot in so its tickets also resolve against
                            // this word; otherwise the read slot still holds the undrained mid-day
                            // batch, so freeze only and let it drain against the new word next
                            // advance.
                            if (!rngLockedFlag && _rngRetryDue(ts)) {
                                _requestRng(lastPurchase, (uint48(day) << 24) | uint48(purchaseLevel));
                                // An isolated future pool never occupied the ordinary read
                                // buffer. Commit all intervening current-level buys on this
                                // fresh daily request, including a turbo's final cohort.
                                if (!preFound || ((lrCached >> LR_MID_DAY_SHIFT) & LR_MID_DAY_MASK) == MID_DAY_FUTURE_POOL) {
                                    _swapTicketSlot();
                                }
                                _freezePool();
                                stage = STAGE_RNG_REQUESTED;
                                break;
                            }
                            // A stalled DAILY request dead-ends here too — the cohort needs
                            // the word this gate is waiting for, and rngGate's retry sits
                            // behind the gate. The cohort is staged and the pool frozen, so
                            // the re-request IS the recovery; _finalizeRngRequest recognizes
                            // the daily lock and finalizes it as a retry.
                            if (rngLockedFlag && _rngRetryDue(ts)) {
                                _requestRng(lastPurchase, (uint48(day) << 24) | uint48(purchaseLevel));
                                stage = STAGE_RNG_REQUESTED;
                                break;
                            }
                            revert RngNotReady();
                        }
                        unchecked {
                            cw += totalFlipReversals;
                        }
                        // preIdx is the reserved pending index (one below the live
                        // reserve index) and its word slot is known-empty here, so
                        // store and emit directly.
                        lootboxRngWordByIndex[preIdx] = cw;
                        emit LootboxRngApplied(preIdx, cw, vrfRequestId);
                    }
                    (bool preWorked, bool preFinished) = _runProcessTicketBatch(purchaseLevel);
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
            // returns earlier, so the STAGE never runs mid-day. Chunked by
            // SUB_STAGE_WEIGHT_BUDGET across advance calls (BUY_BATCH-style) so a
            // large set stays under the 16.7M advance-chain
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
            // Committed-word gate: the STAGE also never runs once rngWordByDay[day] holds
            // a word. After a VRF stall the fulfil crank backfills every gap day's word and
            // records the wall day's, and the RNGREUSE re-walk then enters those days with
            // the lock already down — unlocked, yet holding a public word. The stamp must
            // precede the word, so the block keys on both: lock down AND word uncommitted.
            // A normal day is untouched (its word is written by rngGate, after this block).
            if (!locked && rngWordByDay[day] == 0) {
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
            // TURBO_BONUS_PENDING bit set by _endPhase; rngGate clears it after payment.
            // If this settlement also arms a new turbo, both bits are set. Its request
            // has already promoted the level, so the owed bonus belongs to lvl - 1.
            bool bonusDay = (inJackpot && jackpotCounter == 1) || lvl == 0
                || (!inJackpot && (jackpotFlags & TURBO_BONUS_PENDING) != 0);
            uint24 bonusLvl = (jackpotFlags == (JACKPOT_TURBO | TURBO_BONUS_PENDING) && locked) ? lvl - 1 : lvl;
            uint8 coinflipBonus = bonusDay ? (bonusLvl != 0 && bonusLvl % 10 == 0 ? 6 : 2) : 0;
            (uint256 rngWord, uint32 gapDays) = rngGate(ts, day, purchaseLevel, lastPurchase, coinflipBonus, dIdx);
            psd += uint24(gapDays);
            if (rngWord == 1) {
                // Sentinel from an already-locked entry = the daily retry re-firing the
                // outstanding request. The original request's swap already committed the
                // read cohort; swapping again would flip it back to the write slot
                // mid-drain. Only an unlocked entry (fresh request or a re-fired mid-day
                // stall) commits the buffer here.
                if (!locked) {
                    _swapTicketSlot();
                }
                _freezePool();
                stage = STAGE_RNG_REQUESTED;
                break;
            }

            // Decouple a multi-day VRF-stall gap backfill from the day's jackpot distribution:
            // if rngGate just backfilled a gap (gapDays != 0), defer everything downstream (the
            // phase transition + the up-to-305-winner daily jackpot) to the next advance so the
            // backfill and the jackpot never execute in one tx (each stays under the per-tx gas
            // ceiling). rngGate is idempotent (rngWordByDay[day] is now set -> gapDays == 0 next
            // call) and dailyIdx sits at the wall day minus one (no _unlockRng reached), so
            // advanceDue() stays true and the next advance pays the jackpot with the same frozen
            // word. The break
            // returns mult so the keeper is paid for the backfill work (mirrors the partial drains).
            if (gapDays != 0) {
                stage = STAGE_GAP_BACKFILLED;
                break;
            }

            // Carryover ticket leg of the jackpot-phase daily: the stage after the one that
            // priced it, on the same recorded word, ahead of the transition it may precede.
            // The read slot drained before that daily ran and the lock has held since, so no
            // drain or request can sit between the two halves.
            if (_carryoverLegPending()) {
                _payCarryoverTickets(rngWord);
                if (!phaseTransitionActive) _unlockRng(day);
                stage = STAGE_JACKPOT_CARRYOVER_TICKETS;
                break;
            }

            // Phase transition housekeeping. Nothing crosses a far-future boundary here any more:
            // level L+1 minted on L's last-purchase word, and L+2 mints on L+1's.
            if (phaseTransitionActive) {
                _processPhaseTransition(purchaseLevel);
                phaseTransitionActive = false;
                _unlockRng(day);
                purchaseStartDay = day;
                jackpotPhaseFlag = false;
                // Century recycling and seed ride the transition close. `lvl` still names the x00 level —
                // only a last-purchase request bumps `level`, and the next one is a whole
                // purchase phase away. This branch is reached exactly once per boundary.
                // Silent when nothing is due.
                if (lvl % 100 == 0) {
                    dgnrs.recycleCentury(lvl, rngWord);
                    coinflip.armCenturySeed(lvl);
                }
                stage = STAGE_TRANSITION_DONE;
                break;
            }

            // Unified sweep over the windowed read keys (routed cohort first); an
            // empty-window call is the foil drain's continuation vehicle.
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
            if (ticketWorked || !ticketsFinished) {
                stage = STAGE_TICKETS_WORKING;
                break;
            }
            ticketsFullyProcessed = true; // set before jackpot/phase logic

            // === PURCHASE PHASE ===
            if (!inJackpot) {
                // Ticket leg of the purchase-phase daily: the stage after the one that
                // priced it, on the same recorded word. The lock has held since the request,
                // so the purchase level is still un-promoted and nothing sits between the
                // halves. This stage seals the day, so the last-purchase latch it may set
                // never coexists with a held lock across transactions.
                if (_purchaseTicketLegPending()) {
                    _payPurchaseDailyTickets(rngWord);
                    _sealPurchaseDay(purchaseLevel, day, wallDay, psd);
                    stage = STAGE_PURCHASE_DAILY_TICKETS;
                    break;
                }

                // Pre-target: daily jackpots while building prize pool.
                // lastPurchase equals lastPurchaseDay here (read after the turbo
                // write, inside !inJackpot, with no writer on the path between).
                if (!lastPurchase) {
                    if (purchaseLevel == 1) {
                        // Self-call into GAME (which delegatecalls the jackpot
                        // module) so msg.sender == address(this) passes the
                        // module's OnlyGame check.
                        IDegenerusGame(address(this)).emitDailyWinningTraits(1, rngWord, 1);
                        _payDailyCoinJackpot(1, rngWord, 1, 1);
                        uint256 saltedRng = uint256(keccak256(abi.encodePacked(rngWord, BONUS_TRAITS_TAG)));
                        _payDailyFutureCoinJackpot(1, saltedRng);
                    } else {
                        payDailyJackpot(false, purchaseLevel, rngWord);
                        _payDailyFutureCoinJackpot(purchaseLevel, rngWord);
                    }
                    // A priced ticket leg seals the day from its own stage instead.
                    if (!_purchaseTicketLegPending()) _sealPurchaseDay(purchaseLevel, day, wallDay, psd);
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
                                _growthRatchet(purchaseLevel - 2), _growthRatchet(purchaseLevel - 1), achievedPool
                            )
                        );
                    }
                }
                _distributeYieldSurplus(rngWord);
                _consolidatePoolsAndRewardJackpots(lvl, purchaseLevel, day, rngWord, psd);

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

            // Early-bird ticket leg of the day-1 daily: the stage after the one that priced
            // it, on the same recorded word, ahead of the coin+tickets stage that seals the
            // day. The lock has held since the request, so nothing sits between the halves.
            if (_earlyBirdLegPending()) {
                _payEarlyBirdTickets(rngWord);
                stage = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
                break;
            }

            // Complete coin+ticket distribution
            if (dailyJackpotCoinTicketsPending) {
                bool carryover = payDailyJackpotCoinAndTickets(rngWord);
                if (jackpotCounter >= _jackpotDays()) {
                    _endPhase(lvl);
                    stage = STAGE_JACKPOT_PHASE_ENDED;
                    break;
                }
                // A priced carryover leg seals the day from its own stage instead.
                if (!carryover) _unlockRng(day);
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

    /*+======================================================================+
      |                    GAMEOVER / LIVENESS GUARDS                        |
      +======================================================================+*/

    /// @dev Handles the game-over trigger and the post-game sweep. Returns (shouldReturn, stage);
    ///      shouldReturn = true means advanceGame should emit `stage` and exit. Stages used:
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
    function _handleGameOverPath(uint24 day, uint24 lvl) private returns (bool shouldReturn, uint8 stage) {
        bool ok;
        bytes memory data;

        if (gameOver) {
            // Post-gameover: check for final sweep (1 month after gameover)
            (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE
                .delegatecall(abi.encodeWithSelector(IDegenerusGameGameOverModule.handleFinalSweep.selector));
            if (!ok) _revertDelegate(data);
            return (true, STAGE_GAMEOVER);
        }

        if (!_livenessTriggered()) return (false, 0);

        bool dead = _lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) != 0 || _vrfDead();

        // A met pool target rescues a level from the deadline ending, but only before that
        // ending has started (the drain-level latch below makes it irreversible), and never
        // from the deadman or a dead VRF.
        if (
            !dead && lvl != 0 && _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0
                && _getNextPrizePool() > _prizePoolTarget(lvl + 1) && !_vrfDeadmanFired()
        ) {
            return (false, 0);
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
            (address top, ) = affiliate.affiliateTop(drainLevel);
            terminalAffiliate = top;
        }

        // --- Deterministic ending ---
        if (dead) {
            if (_lrRead(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK) == 0) {
                _lrWrite(LR_GO_DEAD_SHIFT, LR_GO_DEAD_MASK, 1);
                // Drop the request: a word still in flight is ignored by the callback, and one
                // that arrived too late to be applied is discarded. rngRequestTime is never
                // cleared. The dead latch keeps _vrfDead and the trigger on even when this
                // was a mid-day request whose day already has a sealed daily word.
                vrfRequestId = 0;
                rngWordCurrent = 0;
            }
            (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE
                .delegatecall(abi.encodeWithSelector(IDegenerusGameGameOverModule.tallyDeadVrf.selector, drainLevel));
            if (!ok) _revertDelegate(data);
            if (!abi.decode(data, (bool))) return (true, STAGE_TICKETS_WORKING);
            (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE
                .delegatecall(abi.encodeWithSelector(IDegenerusGameGameOverModule.handleGameOverDrain.selector, day));
            if (!ok) _revertDelegate(data);
            return (true, STAGE_GAMEOVER);
        }

        // --- Normal ending ---
        // The terminal word is always this path's own request, sent after liveness froze entry;
        // LR_GO_SWAP latches when it goes out. A daily request from before that (the deadman
        // cutting off a day stuck in processing, or a backlog) never supplies it: its word, once
        // delivered, only finalizes the lootbox index its request reserved, so the cohort that
        // request committed still drains on a word requested after it; then the request is
        // dropped together with the day it was processing, whose jackpot never pays (its funds
        // stay in the terminal pot). Until delivered it is waited out like any request in flight.
        if (rngLockedFlag && _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0) {
            uint256 preFreeze = rngWordCurrent;
            if (preFreeze == 0) return (true, STAGE_GAMEOVER);
            _finalizeLootboxRng(preFreeze);
            rngWordCurrent = 0;
            vrfRequestId = 0;
            rngRequestTime = 0;
            rngLockedFlag = false;
            return (true, STAGE_GAMEOVER);
        }

        // Terminal scope: the payout samples only lvlTraitEntry[drainLevel], so every probe here
        // is drainLevel-only; every other windowed cohort is dead value and is never touched.
        if (rngWordByDay[day] == 0) {
            if (rngWordCurrent == 0) {
                // No terminal word yet. Wait out a request in flight: a mid-day lootbox request,
                // or this path's own terminal request.
                if (vrfRequestId != 0) return (true, STAGE_GAMEOVER);
                if (ticketQueue[_tqReadKey(drainLevel)].length != 0) {
                    // Before the ending's own swap, the read side is a cohort an earlier request
                    // committed (a mid-day swap, or a dropped pre-freeze daily request) and its
                    // word has landed: drain it on that word first, so the write cohort can be
                    // swapped in behind it before the terminal request. After the swap the read
                    // side is the ending's own cohort, and it drains only on the terminal word:
                    // the last delivered word predates it. Without its word the cohort waits for
                    // the terminal one instead (no swap then; it keeps the read side).
                    if (
                        _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0
                            && lootboxRngWordByIndex[uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1] != 0
                            && _terminalDrainBatch(drainLevel, true)
                    ) return (true, STAGE_TICKETS_WORKING);
                } else if (
                    ticketQueue[_tqWriteKey(drainLevel)].length != 0 && _lrRead(LR_GO_SWAP_SHIFT, LR_GO_SWAP_MASK) == 0
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
            _gameOverEntropy(uint48(block.timestamp), day, lvl);
            return (true, STAGE_GAMEOVER);
        }

        // Terminal word recorded: drain the committed cohort and the foil tail on it, one batch
        // per transaction. A finishing batch still returns, so the payout runs in its own.
        if (
            (ticketQueue[_tqReadKey(drainLevel)].length != 0 || _foilDrainPending())
                && _terminalDrainBatch(drainLevel, false)
        ) {
            return (true, STAGE_TICKETS_WORKING);
        }

        (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameGameOverModule.handleGameOverDrain.selector, day));
        if (!ok) _revertDelegate(data);
        _unlockRng(day);
        return (true, STAGE_GAMEOVER);
    }

    /// @dev One terminal drain batch: TICKET_SLOT_BIT on the anchor asks the worker for its
    ///      single-key terminal mode, draining exactly drainLevel's read side plus the foil
    ///      tail — every queued ticket at any other level is worthless at game over.
    ///      FUND-RELEASE FALLBACK: a worker revert (an unforeseen error in ticket processing)
    ///      is swallowed and reported as no batch, so the ending moves on: undrained tickets
    ///      forfeit trait-bucket eligibility, but terminal fund release is never blocked.
    ///      Before the ending's swap (`beforeSwap`) a failure that carries no error of its own
    ///      (empty return data, or EmptyRevert from a nested module call) is re-raised instead:
    ///      a batch is gas-bounded well under the per-transaction cap, so that is a caller
    ///      withholding gas, and swallowing it would close the one swap window with the write
    ///      cohort left out. After the swap a swallowed failure falls through to the payout in
    ///      the same transaction, which a starved call cannot afford.
    /// @return ran True if a batch ran, finished or not.
    function _terminalDrainBatch(uint24 drainLevel, bool beforeSwap) private returns (bool ran) {
        (bool dOk, bytes memory dData) = ContractAddresses.GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(IDegenerusGameMintModule.processTicketBatch.selector, drainLevel | TICKET_SLOT_BIT)
            );
        if (
            !dOk && beforeSwap
                && (dData.length == 0 || (dData.length == 4 && bytes4(dData) == EmptyRevert.selector))
        ) _revertDelegate(dData);
        return dOk && dData.length >= 64;
    }

    /*+======================================================================+
      |                           LEVEL END                                  |
      +======================================================================+*/
    function _endPhase(uint24 lvl) private {
        phaseTransitionActive = true;
        // Fund the all-time record pool with 0.2% of the completed level's achieved
        // prize pool, converted notionally at that level's ticket price — pure FLIP
        // supply, no ETH moves. Read before the x00 overwrite below, so a century
        // level funds off its achieved pool rather than the reset artifact.
        uint256 recordFundFlip = (levelPrizePool[lvl] * PRICE_COIN_UNIT) / (PriceLookupLib.priceForLevel(lvl) * 500);
        if (recordFundFlip != 0) coinflip.fundRecordPool(recordFundFlip);
        if (lvl % 100 == 0) {
            levelPrizePool[lvl] = (_getFuturePrizePool() * 40) / 100;
        }
        jackpotCounter = 0;
        // A turbo has no second jackpot settlement. Its bonus is owed on the next
        // purchase settlement; clearing the active bit keeps the two states distinct.
        jackpotFlags = (jackpotFlags & JACKPOT_TURBO) != 0 ? TURBO_BONUS_PENDING : 0;
    }

    /*+================================================================================================================+
      |                    DELEGATE MODULE HELPERS                                                                     |
      +================================================================================================================+
      |  Internal functions that delegatecall into specialized modules.                                                |
      |  All modules MUST inherit DegenerusGameStorage for slot alignment.                                             |
      |                                                                                                                |
      |  Modules:                                                                                                      |
      |  • ContractAddresses.GAME_GAMEOVER_MODULE - Game-over path and final sweeps                                    |
      |  • ContractAddresses.GAME_MINT_MODULE     - Ticket drains and mint-side daily work                             |
      |  • ContractAddresses.GAME_JACKPOT_MODULE  - Jackpot calculations and payouts                                   |
      |  • ContractAddresses.GAME_AFKING_MODULE   - The afking process stage                                           |
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
        (address top,) = affiliate.affiliateTop(lvl);

        uint256 poolBalance = dgnrs.poolBalance(IsDGNRS.Pool.Affiliate);
        if (top != address(0)) {
            uint256 dgnrsReward = (poolBalance * AFFILIATE_POOL_REWARD_BPS) / 10_000;
            uint256 paid = dgnrs.transferFromPool(IsDGNRS.Pool.Affiliate, top, dgnrsReward);
            emit AffiliateDgnrsReward(top, lvl, paid);
            // transferFromPool returns the exact pool decrement (clamped to the
            // available balance, zero on the empty-pool path), so the remaining
            // pool is derivable without a second external read.
            poolBalance -= paid;
        }

        // Segregate 5% of remaining affiliate pool for per-affiliate claims.
        // Scores at index lvl are frozen (new scores go to lvl + 1).
        uint256 levelAllocation = (poolBalance * AFFILIATE_DGNRS_LEVEL_BPS) / 10_000;
        _setLevelDgnrsAllocation(lvl, levelAllocation);
        emit LevelDgnrsAllocated(lvl, levelAllocation);
    }

    /// @dev Distribute yield surplus via JackpotModule delegatecall.
    ///      Runs while frozen, before pool consolidation. The obligations sum
    ///      includes both live pools and the pending buffer, so freeze-window
    ///      revenue (which routes to pending) is never misread as yield surplus.
    function _distributeYieldSurplus(uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.distributeYieldSurplus.selector, rngWord));
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
        (bool ok, bytes memory data) = ContractAddresses.GAME_AFKING_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IGameAfkingModule.processSubscriberStage.selector, processDay, SUB_STAGE_WEIGHT_BUDGET
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
            uint32 purchaseAge = day > psd ? day - psd : 0;
            uint256 bps = _nextToFutureBps(purchaseAge, purchaseLevel);
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
                    uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000);
                    if (surcharge > OVERSHOOT_CAP_BPS) {
                        surcharge = OVERSHOOT_CAP_BPS;
                    }
                    bps += surcharge;
                }
            }

            // Additive random 0–10%
            bps += EntropyLib.hash2(rngWord, uint256(SKIM_BPS_TAG)) % (ADDITIVE_RANDOM_BPS + 1);

            // Compute take
            uint256 take = (memNext * bps) / 10_000;

            // Triangular variance (avg of two uniform VRF rolls) with half-width
            // max(25% of take, 10% of nextPool), capped at take; the final take is
            // capped at 80% of nextPool below.
            if (take != 0) {
                uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
                uint256 minWidth = (memNext * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000;
                if (halfWidth < minWidth) halfWidth = minWidth;
                if (halfWidth > take) halfWidth = take;

                uint256 range = halfWidth * 2 + 1;
                uint256 varianceWord = EntropyLib.hash2(rngWord, uint256(SKIM_VARIANCE_TAG));
                uint256 roll1 = varianceWord % range;
                uint256 roll2 = EntropyLib.hash1(varianceWord) % range;
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
            // Emitted here, inside the block, so the two amounts are read where they are
            // still live — the pools they move keep mutating through the reward jackpots
            // below, so a later emit would have to carry them out by hand.
            emit PoolSkimApplied(lvl, take, insuranceSkim);
        }

        // --- x00 yield accumulator dump: 40% into futurePool (memory) ---
        if ((lvl % 100) == 0) {
            uint256 dump = (memYieldAcc * 40) / 100;
            memFuture += dump;
            memYieldAcc -= dump;
        }

        // --- BAF + Decimator x00: draw from futurePool BEFORE keep roll ---
        uint256 baseMemFuture = memFuture;
        uint24 prevMod10 = lvl % 10;
        uint24 prevMod100 = lvl % 100;
        uint256 claimableDelta;

        // BAF Jackpot (every 10 levels) — only if the daily flip won (bit 0 of
        // rngWord = 1). On a losing flip the bracket is marked skipped, the pool
        // stays whole in futurePool (the x00 incinerator pays FLIP, not ETH), and
        // pre-skip winning-flip credit is filtered out of future claims via the
        // lastBafResolvedDay bump.
        if (prevMod10 == 0) {
            if ((rngWord & 1) == 1) {
                uint256 bafPct = prevMod100 == 0 ? 20 : (lvl == 50 ? 20 : 10);
                uint256 bafPoolWei = (baseMemFuture * bafPct) / 100;

                uint256 claimed = IDegenerusGame(address(this)).runBafJackpot(bafPoolWei, lvl, rngWord);
                memFuture -= claimed;
                claimableDelta += claimed;
            } else {
                jackpots.markBafSkipped(lvl);

                // Century BAF incinerator: level-x99 WWXRP burners bet on this
                // exact skip. WWXRP draws one burn-weighted winner and credits
                // it a share of the FLIP the armed BAF day's direct depositors
                // burned and just lost on tails (flip credit, from the
                // coinflip's draw book). The would-be BAF pool rolls forward
                // whole in futurePool, as on any skip.
                if (prevMod100 == 0) wwxrpIncinerator.resolveIncinerator(lvl, rngWord);
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
            uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
            uint256 spend = decPoolWei - returnWei;
            memFuture -= spend;
            claimableDelta += spend;
        }

        // --- x00 keep roll (5d4 dice: 50-80% keep, avg 65%) ---
        // Operates on post-jackpot memFuture — all reward jackpots drew first.
        if ((lvl % 100) == 0) {
            uint256 seed = EntropyLib.hash2(rngWord, uint256(FUTURE_KEEP_TAG));
            uint256 total;
            unchecked {
                total = (seed % 4) + ((seed >> 16) % 4) + ((seed >> 32) % 4) + ((seed >> 48) % 4) + ((seed >> 64) % 4);
            }
            uint256 keepBps = 5000 + (total * 3000) / 15;
            if (keepBps < 10_000) {
                uint256 moveWei = memFuture - (memFuture * keepBps) / 10_000;
                memFuture -= moveWei;
                memCurrent += moveWei;
            }
        }

        // --- Merge next → current ---
        memCurrent += memNext;
        memNext = 0;

        // --- The house's level cut: high-roller craps passes ---
        // A twentieth of the consolidated pool, priced in FLIP at this level, banks to sDGNRS as
        // high-roller day passes rather than as a coinflip stake — one pass per
        // HIGH_ROLLER_DAY_PASS_VALUE, rounded down, the fraction under a whole pass dropped.
        // sDGNRS has no door of its own, so the table spends them: its daily seat reaches for a
        // banked high pass before FLIP and sits the house at the day's high multiple.
        // purchaseLevel == storage level here: consolidation runs only on the
        // lastPurchase leg with rngLockedFlag held, after the request-time
        // level pre-increment.
        uint256 highPasses = (memCurrent * PRICE_COIN_UNIT)
            / (PriceLookupLib.priceForLevel(purchaseLevel) * 20 * HIGH_ROLLER_DAY_PASS_VALUE);
        if (highPasses != 0) {
            // Unreachable at any real pool — the cap merely makes the cast provable.
            if (highPasses > type(uint32).max) highPasses = type(uint32).max;
            ICrapsPassCredit(ContractAddresses.CRAPS).creditPasses(
                ContractAddresses.SDGNRS, 0, uint32(highPasses)
            );
        }

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
        emit PoolsSettled(lvl, day, psd, memNext, memFuture, memCurrent, memYieldAcc, claimablePool, claimableDelta);
    }

    /// @dev Pay daily jackpot via jackpot module delegatecall.
    ///      Called each day during purchase phase and jackpot phase.
    /// @param isJackpotPhase True for jackpot phase dailies, false for purchase phase jackpot.
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    function payDailyJackpot(bool isJackpotPhase, uint24 lvl, uint256 randWord) internal {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyJackpot.selector, isJackpotPhase, lvl, randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay the coin jackpot and the day's own ticket leg via jackpot module delegatecall.
    ///      Called when dailyJackpotCoinTicketsPending is true; the carryover ticket leg it
    ///      prices runs from the next advance so the two ticket legs never share a tx.
    /// @param randWord VRF random word for winner selection.
    /// @return carryoverPending True when a carryover leg waits for the next advance.
    function payDailyJackpotCoinAndTickets(uint256 randWord) internal returns (bool carryoverPending) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(IDegenerusGameJackpotModule.payDailyJackpotCoinAndTickets.selector, randWord)
            );
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (bool));
    }

    /// @dev Pay the pending carryover ticket leg via jackpot module delegatecall.
    /// @param randWord The day's recorded VRF word.
    function _payCarryoverTickets(uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.payCarryoverTickets.selector, randWord));
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay the pending purchase-phase ticket leg via jackpot module delegatecall.
    /// @param randWord The day's recorded VRF word.
    function _payPurchaseDailyTickets(uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.payPurchaseDailyTickets.selector, randWord));
        if (!ok) _revertDelegate(data);
    }

    /// @dev Seal a purchase-phase day: latch the level's last purchase day when the next-pool
    ///      target is met, arm the x0 BAF draw and select turbo when eligible, then unlock.
    ///      Do not latch on an RNGREUSE replay day. Its NEXT day may also have a cached
    ///      backfill word, which would let rngGate bypass the sole `level = lvl` writer in
    ///      _finalizeRngRequest and enter jackpot one level behind. Latch only after the
    ///      walk reaches the real wall day; the following calendar day then necessarily
    ///      takes the normal request path and promotes the level. `day >= psd` also makes
    ///      the purchase-day subtraction safe after the death-clock adjustment.
    function _sealPurchaseDay(uint24 purchaseLevel, uint24 day, uint24 wallDay, uint24 psd) private {
        bool targetMet = _getNextPrizePool() > _prizePoolTarget(purchaseLevel);
        if (targetMet && day == wallDay && day >= psd) {
            lastPurchaseDay = true;
            // Level L+1's first generation window opens with this latch: its frozen pool mints
            // on the first word requested after it (a post-seal mid-day word or the
            // last-purchase word), never on a word already public. One metadata write per
            // level, never a charged drain step.
            _markTicketGenerationStart(purchaseLevel + 1);
            // x0 (BAF) level: arm tomorrow's flip day for the
            // weighted depositor draw — the sealed day's direct
            // deposits stake day + 1, the day the transition word
            // resolves. Turbo-speed x0: the one-day collapse
            // latches here rather than at the morning arm, leaving
            // the rest of the sealed day as a real last-purchase
            // window ahead of the collapse; that transition request
            // pays the entire jackpot exactly as an
            // armed turbo does.
            bool bafLevel_ = purchaseLevel % 10 == 0;
            if (bafLevel_) {
                coinflip.armBafDraw(day + 1);
            }
            if (bafLevel_ && day - psd <= 1) {
                jackpotFlags = JACKPOT_TURBO;
            }
        }
        _unlockRng(day);
    }

    /// @dev Pay the pending early-bird ticket leg via jackpot module delegatecall.
    /// @param randWord The day's recorded VRF word.
    function _payEarlyBirdTickets(uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.payEarlyBirdTickets.selector, randWord));
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay daily FLIP jackpot via jackpot module delegatecall.
    ///      Called for level 1's main coin draw during purchase-phase daily processing.
    ///      Awards 0.25% of the previous level's recorded pool (levelPrizePool[lvl-1]) in
    ///      FLIP to trait-matched winners in [minLevel, maxLevel] (minted levels only).
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    /// @param minLevel Minimum target level for the coin distribution (inclusive).
    /// @param maxLevel Maximum target level for the coin distribution (inclusive).
    function _payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyFlipJackpot.selector, lvl, randWord, minLevel, maxLevel
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay the purchase-day FLIP fill draw over unminted future levels via jackpot module
    ///      delegatecall: the same daily coin budget, played as one craps battle among wallets
    ///      drawn from the far-future queues of [lvl + 1, lvl + 99].
    /// @param lvl Purchase level.
    /// @param randWord VRF random word for level picks and walks.
    function _payDailyFutureCoinJackpot(uint24 lvl, uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(IDegenerusGameJackpotModule.payDailyFutureFlipJackpot.selector, lvl, randWord)
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
        if (rngWordByDay[currentDay] == 0) revert RngNotReady();

        if (rngRequestTime != 0) revert RngInFlight();

        // Which floors this caller answers to. Read once: it picks the LINK reserve here and
        // waives the pending-value gates below, and both want the same answer.
        bool crapsCall = msg.sender == ContractAddresses.CRAPS;

        // LINK balance check
        (uint96 linkBal,,,,) = vrfCoordinator.getSubscription(vrfSubscriptionId);
        if (linkBal < (crapsCall ? MIN_LINK_FOR_CRAPS_RNG : MIN_LINK_FOR_LOOTBOX_RNG)) {
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
            // The craps table is exempt from both. It shuts a bonus window by binding it to the
            // index this request fills, so it is not buying a word for the lootbox queue — it is buying
            // the word that settles a table already holding staked FLIP, and a queue it has no
            // stake in cannot price it. Checked before the credit charge so craps never pays for
            // the ADMIN price call it would fail anyway, holding no credit. Every other gate above
            // — the daily lock, mid-day processing, the basefee ceiling, the pre-reset minute, one
            // request in flight — still binds on it exactly as on anyone else, and the LINK floor
            // binds at its own level rather than not at all.
            if (!crapsCall && !_tryChargeMiddayCredit()) {
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
        if (activated && ticketQueue[_tqFarFutureKey(earlyTicketLevel)].length != 0) {
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
                bool queuedWork;
                uint24 t = level;
                uint24 end = _mintCeiling();
                for (; t <= end;) {
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
        // Even, like every request stamp: the LSB is the retry-spent flag the vault owner's
        // retry checks, so an odd stamp would read as a retry already used.
        rngRequestTime = uint48(block.timestamp) & ~uint48(1);
    }

    /// @dev Early generation may precede the last-purchase latch. Keep its original bound.
    function _markTicketGenerationStart(uint24 lvl) private {
        if (ticketGenerationStartBlock[lvl] == 0) ticketGenerationStartBlock[lvl] = block.number;
    }

    /// @dev A fresh mid-day request or turbo transition after the goal is met freezes
    ///      the next level's future queue. Called at a request boundary with the prior read batch
    ///      drained; retries never reopen or add a cohort to their reserved word.
    function _activateNextTickets() private returns (bool activated) {
        uint24 nextLvl = level + 2;
        if (
            !jackpotPhaseFlag && ticketsFullyProcessed && earlyTicketLevel < nextLvl
                && _getNextPrizePool() > _prizePoolTarget(level + 1) && !_livenessTriggered()
        ) {
            earlyTicketLevel = nextLvl;
            _markTicketGenerationStart(nextLvl);
            return true;
        }
    }

    // Daily VRF consumers: only Coinflip win/loss and the BAF fire gate intentionally
    // share bit 0. Redemption uses bits 8+; other games derive tagged substreams.
    // Coinflip reward %, trait boards, daily/level quests, skim bps and skim
    // variance have separate named domains. The two variance draws hash-chain
    // within their domain. Lootbox storage carries the root, not an outcome.
    // See docs/audit/RNG-DOMAINS.md for shared-board rules and retained exceptions.

    /// @dev Daily RNG processing gate called during advanceGame. Applies VRF word,
    ///      processes coinflip payouts, rolls daily quest, resolves pending gambling
    ///      burn redemptions, stores lootbox RNG, and handles VRF timeout retries (12h).
    function rngGate(uint48 ts, uint24 day, uint24 lvl, bool isTicketJackpotDay, uint8 coinflipBonus, uint24 dIdx)
        internal
        returns (uint256 word, uint32 gapDays)
    {
        // Already recorded for today
        uint256 recordedWord = rngWordByDay[day];
        if (recordedWord != 0) return (recordedWord, 0);

        uint256 currentWord = rngWordCurrent;

        // Have a fresh VRF word ready
        if (currentWord != 0 && rngRequestTime != 0) {
            // Backfill gap days from VRF stall before processing current day.
            // Gated on rngWordByDay[idx + 1] == 0 so the backfill runs at most once per
            // lock window; the branch also moves dailyIdx past the gap, so a later
            // wall-clock day cannot re-enter it and re-process the same range.
            // dIdx == dailyIdx here (caller cached it; nothing writes it before this
            // branch), so reuse it instead of re-SLOADing the slot-0 field.
            uint24 idx = dIdx;
            if (day > idx + 1 && rngWordByDay[idx + 1] == 0) {
                uint24 gapCount = day - idx - 1;
                _backfillGapDays(currentWord, idx + 1, day);

                // Extend death clock by the stall duration -- gap days don't count toward
                // the purchase deadline since the game was stalled, not abandoned.
                purchaseStartDay += gapCount;
                gapDays = gapCount;
                // The stalled days are over. Their coinflips settled above and anything
                // bought for them resolves against the derived words; they get no daily
                // draw and no seal. Processing resumes at the wall day, under the lock
                // this request still holds.
                dailyIdx = day - 1;
            }

            // Normal daily RNG processing (request from current day)
            currentWord = _applyDailyRng(day, currentWord);
            coinflip.processCoinflipPayouts(coinflipBonus, currentWord, day);
            // Settlement paid any owed bonus. Preserve a newly armed turbo.
            if ((jackpotFlags & TURBO_BONUS_PENDING) != 0) jackpotFlags &= JACKPOT_TURBO;
            // Force the MINT_FLIP daily on the first jackpot day (lastPurchaseDay still set here,
            // jackpot not yet entered) so the FLIP-mint quest only lands when the redeem window is
            // live. Turbo is skipped — its jackpot collapses at this
            // request, leaving no full open day for that quest.
            // Force the buy-a-foil-pack daily on the day the purchase phase opens — the day
            // whose jackpot run is the level's last, since the transition drains and reopens
            // purchasing later in that same day. Whether this pass carries the final run is
            // already decidable from the physical day counter and turbo bit. At a turbo
            // transition, isTicketJackpotDay stands in for jackpotPhaseFlag, which has not
            // yet been set. phaseTransitionActive is too late: it is raised after the word
            // is recorded, so later rolls take the recorded-word early return
            // above. Never collides with the MINT_FLIP force below: that fires on a level's
            // first jackpot day, which is final only for turbo — where its own turbo exclusion
            // already stands it down. Gated on gapDays == 0 so a VRF-stall backfill (which
            // defers the whole transition to the next advance, line 412) does not roll the
            // foil quest early. The final-jackpot REQUEST already rolls this quest at the
            // routing boundary (_finalizeRngRequest), so on those days this force is an
            // idempotent no-op backstop.
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
            bool finalJackpotRun =
                (jackpotPhaseFlag || isTicketJackpotDay) && _isFinalJackpotDay(jackpotCounter, jackpotFlags);
            if (day == _simulatedDayIndexAt(ts)) {
                bool decDayOne = decDayOneActive;
                quests.rollDailyQuest(
                    day,
                    currentWord,
                    lastPurchaseDay && (jackpotFlags & JACKPOT_TURBO) == 0,
                    finalJackpotRun && gapDays == 0,
                    decDayOne && gapDays == 0
                );

                // Spend sDGNRS's settled backing on the opening-day decimator before the
                // craps seat. Roll today's quests first so both actions credit the right day.
                // The recorded-word return makes this once per day, and the next fresh
                // request clears decDayOneActive. FLIP only sizes and records the entry.
                // On this opening-day path, lvl is the request-promoted level.
                if (decDayOne) coin.autoDecimatorBurn(lvl + 1);

                // The craps bonus day opens on the same crank that applied its word — the
                // terms and the house's available backing have both settled. The WALL-day
                // gate skips buffered historical days; rngGate's recorded-word return makes
                // this once per day. The opener's revert-freedom is pinned by the craps tests.
                ICrapsBonusDay(ContractAddresses.CRAPS).openBonusDay();

                // The word is now finalized and yesterday's pools are closed.
                // Six bounded draws share this existing daily RNG call; no player
                // claim or additional advance step. Recorded-word retries skip it.
                if (day > 1 && (
                    protocolBoonPools[ContractAddresses.VAULT][day - 1].totalWeight != 0 ||
                    protocolBoonPools[ContractAddresses.SDGNRS][day - 1].totalWeight != 0
                )) {
                    (bool ok, bytes memory data) = ContractAddresses.GAME_BOON_MODULE.delegatecall(
                        abi.encodeWithSelector(IDegenerusGameBoonModule.resolveProtocolBoonDraws.selector, day)
                    );
                    if (!ok) _revertDelegate(data);
                }
            }

            // Resolve the sentinel-stamped gambling-burn pool if any. Reading the
            // sentinel rather than deriving `day - 1` makes multi-day RNG stalls correct by
            // construction: the sentinel always names the (at most one) unresolved day, so a
            // single resolve call after the stall recovers covers the stuck pool exactly.
            _resolvePendingRedemption(currentWord);

            _finalizeLootboxRng(currentWord);
            return (currentWord, gapDays);
        }

        // Waiting for VRF. An outstanding request — the daily one (rngLockedFlag), or a
        // lootbox-only mid-day request that bled past the day boundary — gets ONE retry, fired
        // by the vault owner only, RNG_RETRY_TIMEOUT after the send (_rngRetryDue): the last
        // resort before a governance coordinator swap, and the only retry there is. The retry
        // overwrites the outstanding request ID, so it discards a word that might still land
        // late; keeping it with the party already trusted with the swap leaves no public way to
        // time that. A daily retry keeps the stamp and sets its LSB, the retry-spent flag (a
        // coordinator swap spends it too). A mid-day request re-fires as this day's FIRST daily
        // request — _requestRng's isRetry path keeps the reserved index, so the fresh daily word
        // finalizes that bucket just as the mid-day word would have — with a fresh stamp, so the
        // daily request keeps its own retry.
        if (rngRequestTime != 0) {
            if (_rngRetryDue(ts)) {
                _requestRng(isTicketJackpotDay, (uint48(day) << 24) | uint48(lvl));
                return (1, 0);
            }
            revert RngNotReady();
        }

        // Need fresh RNG
        _requestRng(isTicketJackpotDay, (uint48(day) << 24) | uint48(lvl));
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

        uint256 weiPerLink = IAdminLinkValue(ContractAddresses.ADMIN).linkAmountToEth(1 ether);
        if (weiPerLink == 0) return false;

        uint256 charge = (MIDDAY_RNG_BILLED_GAS * block.basefee * MIDDAY_RNG_CHARGE_MULT * 1 ether) / weiPerLink;
        if (balance < charge) return false;
        unchecked {
            balance -= charge;
        }
        middayRngCredit[msg.sender] = balance;
        emit MiddayRngCreditSpent(msg.sender, charge, balance);
        return true;
    }

    /// @dev Resolve the sentinel-stamped gambling-burn pool off `word`. Three call sites in this
    ///      module ran this identically; folded into one so the encoding is emitted once.
    function _resolvePendingRedemption(uint256 word) private {
        IsDGNRS sdgnrs = IsDGNRS(ContractAddresses.SDGNRS);
        uint24 toResolve = sdgnrs.pendingResolveDay();
        if (toResolve != 0) {
            sdgnrs.resolveRedemptionPeriod(uint16(((word >> 8) % 151) + 25), toResolve);
        }
    }

    function _finalizeLootboxRng(uint256 rngWord) private {
        uint48 index = uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK)) - 1;
        if (lootboxRngWordByIndex[index] != 0) return;
        lootboxRngWordByIndex[index] = rngWord;
        emit LootboxRngApplied(index, rngWord, vrfRequestId);
    }

    /// @dev Terminal entropy for the normal (VRF-alive) ending. _handleGameOverPath calls it
    ///      only with no request in flight, any pre-freeze daily request dropped and the read
    ///      side drained, so the request it sends postdates the liveness freeze and the one
    ///      terminal swap: every cohort at the terminal level predates the word. Once that word
    ///      lands it is applied to the day the request was issued for, and the days between the
    ///      last sealed day and that one are derived from it exactly as rngGate derives a gap
    ///      (a dropped day that had already applied its own word keeps it, its flips settled),
    ///      so every coinflip day and foil bucket up to the terminal day holds a word. Also settles the terminal day's
    ///      flips and any pending gambling-burn redemption, and fills the reserved lootbox
    ///      index. A request call that fails outright still starts the VRF-dead window, so a
    ///      coordinator that refuses requests ends deterministically once it passes.
    /// @param ts Current block timestamp.
    /// @param day Day the terminal word is applied to (the terminal request's own day).
    /// @param lvl Level live at game-over; zero skips the terminal day's coinflip settlement
    ///        (the bonus is always 0 here).
    function _gameOverEntropy(uint48 ts, uint24 day, uint24 lvl) private {
        uint256 currentWord = rngWordCurrent;
        if (currentWord != 0) {
            uint24 first = dailyIdx + 1;
            if (rngWordByDay[first] != 0) ++first;
            if (day > first) _backfillGapDays(currentWord, first, day);
            currentWord = _applyDailyRng(day, currentWord);
            if (lvl != 0) {
                // Gameover settles the final day's flips but never grants a bonus (0).
                coinflip.processCoinflipPayouts(0, currentWord, day);
            }
            _resolvePendingRedemption(currentWord);
            _finalizeLootboxRng(currentWord);
            return;
        }
        if (vrfRequestId == 0 && !_tryRequestRng(lvl) && rngRequestTime == 0) {
            rngRequestTime = ts;
        }
    }

    /*+======================================================================+
      |                       NEXT-TO-FUTURE SKIM RATE                       |
      +======================================================================+
      |  Compute the bps skimmed from the next pool into the future pool,    |
      |  based on purchase age, with the original level-0 curve preserved.  |
      +======================================================================+*/

    /// @dev Age is measured from purchaseStartDay, before any offset. The transition has
    ///      already incremented level, so purchaseLevel == 1 identifies the level-0 curve.
    ///      Later levels: 30% + level bonus through day 3, 15% at day 8, 45% + bonus
    ///      at day 30. As before, the trough excludes the century-level bonus. Interpolate
    ///      the full numerator before flooring so the rising leg lands exactly on 45%.
    function _nextToFutureBps(uint32 purchaseAge, uint24 purchaseLevel) internal pure returns (uint16) {
        uint256 bps;
        if (purchaseLevel != 1) {
            uint256 lvlBonus = (uint256(purchaseLevel % 100) / 10) * 100;
            uint256 fast = NEXT_TO_FUTURE_BPS_FAST + lvlBonus;
            if (purchaseAge <= 3) return uint16(fast);
            if (purchaseAge <= 8) {
                return uint16(fast - ((fast - NEXT_TO_FUTURE_BPS_MIN) * (purchaseAge - 3)) / 5);
            }
            bps = NEXT_TO_FUTURE_BPS_MIN +
                ((NEXT_TO_FUTURE_BPS_DEADLINE + lvlBonus - NEXT_TO_FUTURE_BPS_MIN) * (purchaseAge - 8)) /
                (_PURCHASE_TIMEOUT_DAYS - 8);
            return uint16(bps > 10_000 ? 10_000 : bps);
        }

        // Level 0 retains the seven-day offset and its original 30% / 13% / 30% curve.
        uint32 elapsed = purchaseAge > 7 ? purchaseAge - 7 : 0;
        if (elapsed <= 1) {
            bps = NEXT_TO_FUTURE_BPS_FAST;
        } else if (elapsed <= 14) {
            uint256 elapsedAfterDay = elapsed - 1;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST - GENESIS_SKIM_BPS_MIN;
            bps = NEXT_TO_FUTURE_BPS_FAST - (delta * elapsedAfterDay) / 13;
        } else if (elapsed <= 28) {
            uint256 elapsedAfterMin = elapsed - 14;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST - GENESIS_SKIM_BPS_MIN;
            bps = GENESIS_SKIM_BPS_MIN + (delta * elapsedAfterMin) / 14;
        } else {
            bps = NEXT_TO_FUTURE_BPS_FAST + uint256(elapsed - 28) * GENESIS_SKIM_BPS_DAY_STEP;
        }
        return uint16(bps > 10_000 ? 10_000 : bps);
    }

    /*+======================================================================+
      |                    FUTURE TICKET ACTIVATION                          |
      +======================================================================+
      |  Unminted entries (above the mint ceiling) live in the far-future key |
      |  space. Level L+1's pool, frozen when L's last purchase day latches, |
      |  mints inside the unified sweep with the first cohort committed     |
      |  after that latch (_runProcessTicketBatch / processTicketBatch).    |
      +======================================================================+*/

    /*+======================================================================+
      |                    TICKET / TOKEN AIRDROP BATCHING                   |
      +======================================================================+
      |  Ticket entries are processed in batches to prevent gas exhaustion.  |
      |  Large purchases are queued and processed across multiple txs.       |
      +======================================================================+*/

    /// @dev Run the windowed ticket sweep via mint module delegatecall: one writes
    ///      budget drains the read window [anchor-1 .. _mintCeiling()], a committed
    ///      next-level pool, and foil. An isolated mid-day pool gets its own batch.
    /// @param lvl The window anchor (purchaseLevel).
    /// @return worked True if the batch materialized at least one ticket or foil entry.
    ///         Reported directly by the mint module rather than inferred from a cursor
    ///         delta, so a batch that both starts and finishes in one call (cursor returns
    ///         to 0) still reports its work and the chain breaks before BAF/jackpot.
    /// @return finished True when the whole window and the foil drain are caught up.
    function _runProcessTicketBatch(uint24 lvl) private returns (bool worked, bool finished) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_MINT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameMintModule.processTicketBatch.selector, lvl));
        if (!ok) _revertDelegate(data);
        if (data.length < 64) revert EmptyReturn();
        (finished, worked) = abi.decode(data, (bool, bool));
        if (finished && _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) == MID_DAY_FUTURE_POOL) {
            // A daily retry may have committed current-level buys while the next-level
            // snapshot was waiting. Finish the ordinary sweep before paying its jackpot.
            _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 1);
            finished = !rngLockedFlag && !_foilDrainPending();
        }
    }

    /// @dev Process jackpot→purchase transition housekeeping (deity perpetual tickets + auto-stake).
    ///      All deity owners, including VAULT/SDGNRS, get one ordinary queued ticket.
    /// @param purchaseLevel Current purchase level (level + 1).
    function _processPhaseTransition(uint24 purchaseLevel) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameFoilPackModule.queuePerpetualTickets.selector, purchaseLevel + 99)
        );
        if (!ok) _revertDelegate(data);

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
        try steth.submit{value: stakeable}(address(0)) returns (uint256) {}
        catch {
            emit StEthStakeFailed(stakeable);
        }
    }

    /// @dev Whether the caller may fire the single RNG retry now: a request is outstanding (no
    ///      word has been applied — every caller reaches this only while waiting), its retry is
    ///      unspent, it is RNG_RETRY_TIMEOUT old, and the caller is the vault owner. The
    ///      ownership read runs last, only once the rest holds.
    function _rngRetryDue(uint48 ts) private view returns (bool) {
        uint48 t = rngRequestTime;
        return t != 0 && (t & 1) == 0 && ts - t >= RNG_RETRY_TIMEOUT
            && IVaultOwnerCheck(ContractAddresses.VAULT).isVaultOwner(msg.sender);
    }

    /// @dev Request new VRF random word from Chainlink.
    ///      Sets RNG lock to prevent manipulation during pending window.
    /// @param isTicketJackpotDay True if this is the last purchase day.
    /// @param lvlAndQuestDay Low 24 bits: current level. High 24 bits: the day this request
    ///        seals — the caller's `day`, which the RNGREUSE clamp may hold below the wall
    ///        day. Only the foil-quest roll reads the day, and only when it IS the wall day;
    ///        0 suppresses that roll.
    function _requestRng(bool isTicketJackpotDay, uint48 lvlAndQuestDay) private {
        // Ordinary purchase dailies leave the next-level future pool unminted for
        // their jackpots. A turbo transition needs it ready for the early-bird draw.
        // The standard last-purchase transition retains its existing frozen-pool drain.
        if (rngRequestTime == 0 && isTicketJackpotDay && (jackpotFlags & JACKPOT_TURBO) != 0) {
            _activateNextTickets();
        }
        // Hard revert if Chainlink request fails; this intentionally halts game progress until VRF funding/config is fixed.
        _finalizeRngRequest(isTicketJackpotDay, lvlAndQuestDay, _requestVrfWord(VRF_REQUEST_CONFIRMATIONS));
    }

    /// @dev The ending's terminal request. Never a level transition: the ending latched its
    ///      level (LR_GO_LVL) on entry, so the request runs none of the last-purchase steps
    ///      (level bump, affiliate reward, charity resolution, decimator window), whatever phase
    ///      it ended in. The flag is passed as that rule, not as a literal false, which would
    ///      have the optimizer compile a second copy of _finalizeRngRequest.
    function _tryRequestRng(uint24 lvl) private returns (bool requested) {
        try vrfCoordinator.requestRandomWords(
            VRFRandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: hex"" // Empty for LINK payment (default)
            })
        ) returns (
            uint256 id
        ) {
            // questDay 0: the game-over entropy path never rolls the foil daily. A foil buy
            // reverts GameOver from here on, so the quest could only bill an unmeetable miss.
            _finalizeRngRequest(lastPurchaseDay && _lrRead(LR_GO_LVL_SHIFT, LR_GO_LVL_MASK) == 0, uint48(lvl), id);
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

    /// @dev Advance the lootbox RNG index and zero both pending accumulators in a
    ///      single read-modify-write of the packed slot: new purchases target the
    ///      NEXT RNG index and the pending ETH/FLIP totals restart at zero.
    function _lrAdvanceIndexClearPending() private {
        uint256 packed = lootboxRngPacked;
        uint256 nextIndex = ((packed >> LR_INDEX_SHIFT) & LR_INDEX_MASK) + 1;
        packed &= ~((LR_INDEX_MASK << LR_INDEX_SHIFT)
                | (LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
                | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
        lootboxRngPacked = packed | ((nextIndex & LR_INDEX_MASK) << LR_INDEX_SHIFT);
    }

    // =========================================================================
    // Queue Swap and Prize Pool Freeze
    // =========================================================================

    /// @dev The unified sweep's key picker: the first non-empty READ-side plain queue in
    ///      the window [purchaseLevel-1 .. _mintCeiling()] — every level the distance
    ///      routing can currently target plainly (plain iff target <= _mintCeiling())
    ///      plus the trailing key. Ascending order is routed-priority in both phases: in
    ///      the jackpot phase purchaseLevel-1 IS the routed level, and in the purchase
    ///      phase purchaseLevel-1 is the just-finished level, whose self-healing
    ///      leftovers must drain first anyway. The trailing key keeps a retired level
    ///      named until both its parities are provably empty — a leftover re-committed
    ///      by any later swap drains instead of stranding. The only far-future key probed is a
    ///      latched last purchase day's frozen next-level pool, which the sweep itself mints;
    ///      every far-future key is emptied once, that way, and is write-dead afterward.
    function _sweepReadLevel(uint24 purchaseLevel) private view returns (uint24 pick, bool found) {
        unchecked {
            uint24 t = purchaseLevel == 0 ? 0 : purchaseLevel - 1;
            uint24 end = _mintCeiling();
            for (; t <= end; ++t) {
                if (ticketQueue[_tqReadKey(t)].length > 0) {
                    return (t, true);
                }
            }
            // A latched last purchase day's frozen next-level pool drains inside the sweep.
            if (_frozenPoolDue() && ticketQueue[_tqFarFutureKey(end)].length > 0) {
                return (end, true);
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
    ///      futurePool via _unfreezePool. If already frozen (a re-request inside the same
    ///      locked daily/transition chain), accumulators keep growing.
    function _freezePool() internal {
        if (!prizePoolFrozen) {
            prizePoolFrozen = true;
            uint256 futureBal = _getFuturePrizePool();
            uint256 seed = futureBal / 100;
            _setFuturePrizePool(futureBal - seed);
            // The seed opens the pending buffer; buys route here until the unfreeze.
            _setPendingPools(0, uint128(seed));
        }
    }

    /// @dev Whether a growth round resolves OVER: the successor's growth RATE strictly
    ///      exceeds the round's own — cross-multiplied (nextR * prevR > currR * currR) so
    ///      the comparison is exact, unsigned, division-free. Ties are UNDER.
    function _growthOver(uint256 prevR, uint256 currR, uint256 nextR) internal pure returns (bool) {
        return nextR * prevR > currR * currR;
    }

    /// @dev Fold pending into live and clear freeze; no-op if not frozen. One read and
    ///      one write per slot: each half ADDS into its own, saturating independently on
    ///      the same never-revert grounds as the purchase path.
    function _unfreezePool() internal {
        if (!prizePoolFrozen) return;
        uint256 pending = prizePoolPendingPacked;
        uint256 live = prizePoolsPacked;
        // Masked operands: both sums must evaluate in uint256, or the saturating fold
        // would revert exactly where it is meant to clamp.
        uint256 next = (live & POOL_HALF_MAX) + (pending & POOL_HALF_MAX);
        uint256 future = (live >> POOL_FUTURE_SHIFT) + (pending >> POOL_FUTURE_SHIFT);
        if (next > POOL_HALF_MAX) next = POOL_HALF_MAX;
        if (future > POOL_HALF_MAX) future = POOL_HALF_MAX;
        prizePoolsPacked = (future << POOL_FUTURE_SHIFT) | next;
        prizePoolPendingPacked = 0;
        prizePoolFrozen = false;
    }

    function _finalizeRngRequest(bool isTicketJackpotDay, uint48 lvlAndQuestDay, uint256 requestId) private {
        uint24 lvl = uint24(lvlAndQuestDay);
        // isRetry: some VRF request already reserved the lootbox index (a daily retry OR an
        // in-flight mid-day lootbox request) — so the index must not be advanced again.
        bool isRetry = vrfRequestId != 0 && rngRequestTime != 0 && rngWordCurrent == 0;
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
        // rngRequestTime fixes the request's identity: the day it resolves (the advance works
        // on dayOf(rngRequestTime) while the lock holds a delivered word) and the start of the
        // VRF-dead window. Only a fresh request (a re-fired mid-day request included) stamps it; the
        // retry re-sends the same request and just sets the LSB, the retry-spent flag. A fresh
        // stamp rounds DOWN to an even second (<=1s into the past, so same-second
        // `ts - rngRequestTime` reads never underflow). Day boundaries fall on even seconds
        // (82,620 and 86,400 are both even), so neither the round-down nor the LSB can move
        // the stamp into another day.
        rngRequestTime = isDailyRetry ? rngRequestTime | 1 : uint48(block.timestamp) & ~uint48(1);
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
        // The redemption latch is opened lazily by the first FLIP redeem of a phase, so it
        // cannot gate the test itself: finalJackpotRequest must be decided on a cycle where
        // nobody redeemed. Only the clearing write stays behind the latch.
        bool finalJackpotRequest =
            (jackpotPhaseFlag || isTicketJackpotDay) && _isFinalJackpotDay(jackpotCounter, jackpotFlags);
        if (finalJackpotRequest && ticketRedemptionOpen) ticketRedemptionOpen = false;

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
            } else if (decWindowOpen && ((mod10 == 5 && mod100 != 95) || mod100 == 0)) {
                decWindowOpen = false;
            }

            // Resolve charity governance for the completed level.
            // lvl is the NEW level (old level + 1). CHARITY.currentLevel tracks
            // the CURRENT governance level (starts at 0, incremented by pickCharity).
            // The game's level 0->1 transition means level 0 gameplay is complete,
            // so we resolve governance for level 0 = lvl - 1.
            charityResolve.pickCharity(lvl - 1);
        }

        // Buy-a-foil-pack daily: rolled at the REQUEST, not at the word's fulfilment.
        // This request is the boundary where _activeTicketLevel starts routing to level + 1,
        // so from here a foil pack spends the one-per-cycle slot for the very cycle whose
        // opening day carries this quest. The fulfilment roll rides the next advanceGame
        // (rawFulfillRandomWords only records the word), so leaving it there strands that
        // gap and hands the buyer a quest that can only revert FoilAlreadyBought.
        //
        // No entropy is read: a forced slot-1 type never reaches the weighted roll, and one
        // of the two forces always wins here. decDayOneActive is read AFTER the arming block
        // above so DECIMATOR-over-FOIL precedence matches the fulfilment roll on a turbo
        // x4/x99 level, where the final run is also the arming day. rollDailyQuest is
        // idempotent per day, so the fulfilment call no-ops on this day.
        //
        // questDay == wall day mirrors the fulfilment roll's own guard: a day the RNGREUSE
        // clamp held in the past must stay unrolled, since a retroactive quest lands already
        // missed and bills every streak. That case rolls nothing.
        //
        // !isDailyRetry pins the roll to the request that MOVED the boundary. The level
        // increment above carries the same gate, so a retry re-requests a word for a
        // transition already made. A retry that crosses midnight carries the NEW wall day
        // (no RNGREUSE clamp applies while a request is pending — rngWordCurrent is 0), so
        // an ungated roll would force a SECOND foil daily on a day whose one-per-cycle slot
        // the first day's quest may already have spent: a quest that can only miss.
        uint24 questDay = uint24(lvlAndQuestDay >> 24);
        if (finalJackpotRequest && !isDailyRetry && questDay == _simulatedDayIndex()) {
            quests.rollDailyQuest(questDay, 0, false, true, decDayOneActive);
        }
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
        bool wasLocked = rngLockedFlag;
        rngLockedFlag = false;
        rngWordCurrent = 0;
        vrfRequestId = 0;
        rngRequestTime = 0;
        _unfreezePool();
        // The day-seal is the one chokepoint every completed game-day passes through (purchase
        // daily, jackpot coin+tickets or its carryover leg, phase transition). Emit the daily pool
        // snapshot here, after
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
                yieldAccumulator,
                day
            );
            if (wasLocked) _afKingSubDraw(day);
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
    ///      ("SEATDRAW") from every other consumer. Runs only at a seal that
    ///      releases the lock (the caller's `wasLocked`): the wall day recorded in the
    ///      same fulfil crank seals with the lock already down and a word public since
    ///      that crank, so it holds no drawing (stalled gap days are skipped, never
    ///      re-walked).
    function _afKingSubDraw(uint24 day) private {
        uint256 len = _subscribers.length;
        uint256 word = rngWordByDay[day];
        if (len < 2 || word == 0) return;
        uint256 idx = 1 + (uint256(keccak256(abi.encodePacked("SEATDRAW", word))) % (len - 1));
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
    function _backfillGapDays(uint256 vrfWord, uint24 startDay, uint24 endDay) private {
        // Bounded for gas (~9M). A live gap never reaches the bound (the deadman ends the game
        // first); on the normal ending the days past it hold no ticket or foil entry.
        if (endDay - startDay > GAP_BACKFILL_MAX_DAYS) endDay = startDay + GAP_BACKFILL_MAX_DAYS;
        for (uint24 gapDay = startDay; gapDay < endDay;) {
            uint256 derivedWord = uint256(keccak256(abi.encodePacked(vrfWord, gapDay)));
            if (derivedWord == 0) derivedWord = 1;
            rngWordByDay[gapDay] = derivedWord;
            // Gap days are calendar days that elapsed during the stall (no advance ran on
            // them); every backfilled day is paid with bonus 0 regardless of phase or level.
            coinflip.processCoinflipPayouts(0, derivedWord, gapDay);
            emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
            unchecked {
                ++gapDay;
            }
        }
    }

    /// @dev Apply daily RNG nudges, record the word, and emit the finalized word. A recorded
    ///      day word is never 0 (reads as "no word") or 1 (rngGate's "request sent" return,
    ///      which would hold the day behind its own recorded word): those two values, from a
    ///      raw word of 1 or a nudge sum that wraps, are recorded as 2 and 3.
    function _applyDailyRng(uint24 day, uint256 rawWord) private returns (uint256 finalWord) {
        uint256 nudges = totalFlipReversals;
        finalWord = rawWord;
        if (nudges != 0) {
            unchecked {
                finalWord += nudges;
            }
            totalFlipReversals = 0;
        }
        if (finalWord < 2) finalWord += 2;
        rngWordCurrent = finalWord;
        rngWordByDay[day] = finalWord;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit DailyRngApplied(day, rawWord, nudges, finalWord);
    }
}
