// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

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
import {MineFlipGasBounds as GasBounds} from "../libraries/MineFlipGasBounds.sol";
import {IJackpotBattle} from "../interfaces/IJackpotBattle.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusGameJackpotModule, IDegenerusGameFoilPackModule, IDegenerusGameBoonModule, IDegenerusGameGameOverModule}
    from "../interfaces/IDegenerusGameModules.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IsDGNRS} from "../interfaces/IsDGNRS.sol";
import {EntropyLib} from "../libraries/EntropyLib.sol";
import {PriceLookupLib} from "../libraries/PriceLookupLib.sol";
import {DegenerusGameRngUtils} from "./DegenerusGameRngUtils.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

interface ICrapsBonusDay { function openBonusDay() external; }
interface ICrapsPassCredit { function creditPasses(address player, uint32 normal, uint32 high) external; }
interface IGNRUSResolve { function pickCharity(uint24 level) external; }
interface IWwxrpIncinerator { function resolveIncinerator(uint24 bracket, uint256 rngWord) external; }

/// @notice Daily economics and lifecycle transitions, selected by the miner engine.
/// @dev Publication and ticket materialization precede these actions. Read consumers
///      follow day sealing. Fresh RNG commitment belongs to the RNG module.
contract DegenerusGameAdvanceModule is DegenerusGameRngUtils {
    error RngNotReady();

    IStETH internal constant steth = IStETH(ContractAddresses.STETH_TOKEN);
    IGNRUSResolve private constant charityResolve = IGNRUSResolve(ContractAddresses.GNRUS);
    IDegenerusJackpots private constant jackpots = IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IWwxrpIncinerator private constant wwxrpIncinerator = IWwxrpIncinerator(ContractAddresses.WWXRP);

    event Advance(uint8 stage, uint24 lvl);
    event PoolSkimApplied(uint24 indexed lvl, uint256 take, uint256 insuranceSkim);
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
    event StEthStakeFailed(uint256 amount);
    event AffiliateDgnrsReward(address indexed affiliate, uint24 indexed level, uint256 dgnrsAmount);
    event LevelDgnrsAllocated(uint24 indexed level, uint256 allocation);
    event SubDrawWon(address indexed winner, uint24 day, uint24 spanDays, uint256 flipAmount);

    uint8 private constant STAGE_TRANSITION_DONE = 3;
    uint8 private constant STAGE_PURCHASE_DAILY = 6;
    uint8 private constant STAGE_ENTERED_JACKPOT = 7;
    uint8 private constant STAGE_JACKPOT_COIN_TICKETS = 8;
    uint8 private constant STAGE_JACKPOT_PHASE_ENDED = 9;
    uint8 private constant STAGE_JACKPOT_DAILY_STARTED = 10;
    uint8 private constant STAGE_GAP_BACKFILLED = 12;
    uint8 private constant STAGE_JACKPOT_EARLY_BIRD_TICKETS = 14;
    uint8 private constant STAGE_PURCHASE_DAILY_TICKETS = 15;
    uint8 private constant STAGE_JACKPOT_BATTLE = 16;
    uint8 private constant STAGE_PURCHASE_BATTLE = 17;
    uint8 private constant STAGE_DAILY_WORD_APPLIED = 18;
    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 3000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 1500;
    uint16 private constant NEXT_TO_FUTURE_BPS_DEADLINE = 4500;
    uint16 private constant GENESIS_SKIM_BPS_MIN = 1300;
    uint16 private constant GENESIS_SKIM_BPS_DAY_STEP = 14;
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 2500;
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;
    uint16 private constant INSURANCE_SKIM_BPS = 100;
    uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12_500;
    uint16 private constant OVERSHOOT_CAP_BPS = 3500;
    uint16 private constant OVERSHOOT_COEFF = 4000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000;
    uint16 private constant ADDITIVE_RANDOM_BPS = 1000;
    bytes32 private constant FUTURE_KEEP_TAG = keccak256("future-keep");
    bytes32 private constant SKIM_BPS_TAG = keccak256("degenerus.skim.bps");
    bytes32 private constant SKIM_VARIANCE_TAG = keccak256("degenerus.skim.variance");
    uint256 private constant SEAT_DRAW_FLIP_PER_DAY = 10;
    uint256 private constant SEAT_DRAW_MAX_FLIP = 4000;
    uint16 private constant AFFILIATE_POOL_REWARD_BPS = 100;
    uint16 private constant AFFILIATE_DGNRS_LEVEL_BPS = 500;

    /// @notice Compact skipped-day funding is a separate indivisible daily action.
    function applyDailyGap() external {
        uint24 day = rngRequestDay;
        if (address(this) != ContractAddresses.GAME || !rngLockedFlag || !_rngSessionPublished()
            || !ticketsFullyProcessed || !_rngRequestActive() || day <= dailyIdx + 1
            || _recordedDailyWord(day) != 0 || _livenessTriggered()) revert E();
        uint24 count = day - dailyIdx - 1;
        _backfillGapDays(_rawDailyRngWord(_currentRngWord()), dailyIdx + 1, day);
        purchaseStartDay += count;
        dailyIdx = day - 1;
        rngGapApplied = true;
        emit Advance(STAGE_GAP_BACKFILLED, level);
    }

    /// @notice Game-only daily setup, after publication and complete ticket materialization.
    function applyDailyWord() external {
        if (address(this) != ContractAddresses.GAME || !rngLockedFlag || !_rngSessionPublished()
            || !ticketsFullyProcessed || !_rngRequestActive() || _livenessTriggered()) revert E();
        uint24 day = rngRequestDay;
        if (day == 0 || _recordedDailyWord(day) != 0) revert E();
        uint48 ts = uint48(block.timestamp);
        uint24 lvl = level;
        bool inJackpot = jackpotPhaseFlag;
        bool isTicketJackpotDay = !inJackpot && lastPurchaseDay;
        bool bonusDay = (inJackpot && jackpotCounter == 1) || lvl == 0
            || (!inJackpot && (jackpotFlags & TURBO_BONUS_PENDING) != 0);
        uint24 bonusLvl = jackpotFlags == (JACKPOT_TURBO | TURBO_BONUS_PENDING) ? lvl - 1 : lvl;
        uint8 coinflipBonus = bonusDay ? (bonusLvl != 0 && bonusLvl % 10 == 0 ? 6 : 2) : 0;
        uint256 currentWord = _currentRngWord();
        if (currentWord == 0) revert RngNotReady();
        uint32 gapDays = rngGapApplied ? 1 : 0;
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
        // routing boundary (prepareRequestBoundary), so on those days this force is an
        // idempotent no-op backstop.
        //
        // Force the decimator daily on the day a burn window arms. _decDayOneActive() is
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
            bool decDayOne = _decDayOneActive();
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
            // request clears _decDayOneActive(). FLIP only sizes and records the entry.
            // On this opening-day path, lvl is the request-promoted level.
            if (decDayOne) coin.autoDecimatorBurn(lvl + 1);

            // The craps bonus day opens on the same crank that applied its word — the
            // terms and the house's available backing have both settled. The WALL-day
            // gate skips buffered historical days; the recorded-word guard makes
            // this once per day. The opener's revert-freedom is pinned by the craps tests.
            ICrapsBonusDay(ContractAddresses.CRAPS).openBonusDay();

            // The word is now finalized and yesterday's pools are closed.
            // Six bounded draws share this existing daily RNG call; no player
            // claim or additional advance step. Recorded-word retries skip it.
            // Pools live in two-day rings (protocolBoonPools); the draw itself skips a slot
            // tagged with another day, so an older day's weight here costs one no-op call.
            if (day > 1 && (
                protocolBoonPools[ContractAddresses.VAULT][(day - 1) & 1].totalWeight != 0 ||
                protocolBoonPools[ContractAddresses.SDGNRS][(day - 1) & 1].totalWeight != 0
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


        emit Advance(gapDays == 0 ? STAGE_DAILY_WORD_APPLIED : STAGE_GAP_BACKFILLED, lvl);
    }

    /// @notice One ordered daily phase. Every partial payout retains the daily lock.
    function runDailyPhase(uint256 allowance) external returns (MineFlipGas.Result memory result) {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (address(this) != ContractAddresses.GAME || !rngLockedFlag || !ticketsFullyProcessed
            || !_rngSessionPublished() || _livenessTriggered()) revert E();
        uint24 day = rngRequestDay;
        uint256 word = _recordedDailyWord(day);
        if (day == 0 || word == 0) revert RngNotReady();
        if (!MineFlipGas.canRun(meter, 100_000, 150_000)) return result;
        uint24 lvl = level;
        bool inJackpot = jackpotPhaseFlag;
        bool lastPurchase = !inJackpot && lastPurchaseDay;
        uint24 purchaseLevel = lastPurchase ? lvl : lvl + 1;
        uint8 stage;

        if (_jackpotBattlePending()) {
            result = _runJackpotWork(abi.encodeWithSelector(
                IDegenerusGameJackpotModule.runPurchaseJackpotBattle.selector, _mintCeiling(), word, _phaseAllowance(meter)
            ));
            stage = inJackpot ? STAGE_JACKPOT_BATTLE : STAGE_PURCHASE_BATTLE;
        } else if (phaseTransitionActive) {
            if (!MineFlipGas.canRun(meter, GasBounds.TRANSITION_CLOSE, GasBounds.DAILY_PHASE_TAIL)) return result;
            _processPhaseTransition(purchaseLevel);
            phaseTransitionActive = false;
            _unlockRng(day);
            purchaseStartDay = day;
            jackpotPhaseFlag = false;
            if (lvl % 100 == 0) {
                dgnrs.recycleCentury(lvl, word);
                coinflip.armCenturySeed(lvl);
            }
            result.progressed = true;
            result.done = true;
            stage = STAGE_TRANSITION_DONE;
        } else if (jackpotWork.kind == 1 || jackpotWork.kind == 2) {
            // Pricing can set ticket-leg flags before the ETH quadrants have finished.
            result = _runJackpotWork(abi.encodeWithSelector(
                IDegenerusGameJackpotModule.runDailyJackpot.selector,
                inJackpot, inJackpot ? lvl : purchaseLevel, word, _phaseAllowance(meter)
            ));
            if (result.done && !inJackpot && !_purchaseTicketLegPending()) {
                _sealPurchaseDay(purchaseLevel, day, _simulatedDayIndex(), purchaseStartDay);
            }
            stage = inJackpot ? STAGE_JACKPOT_DAILY_STARTED : STAGE_PURCHASE_DAILY;
        } else if (!inJackpot) {
            if (_purchaseTicketLegPending()) {
                result = _runJackpotWork(abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.runPurchaseDailyTickets.selector, word, _phaseAllowance(meter)
                ));
                if (result.done) _sealPurchaseDay(purchaseLevel, day, _simulatedDayIndex(), purchaseStartDay);
                stage = STAGE_PURCHASE_DAILY_TICKETS;
            } else if (!lastPurchase) {
                if (purchaseLevel == 1) {
                    if (!MineFlipGas.canRun(meter, GasBounds.LEVEL_ONE_DRAW, GasBounds.DAILY_PHASE_TAIL)) return result;
                    IDegenerusGame(address(this)).emitDailyWinningTraits(word);
                    _payDailyCoinJackpot(1, word, 1, 1);
                    result.progressed = true;
                    result.done = true;
                } else {
                    result = _runJackpotWork(abi.encodeWithSelector(
                        IDegenerusGameJackpotModule.runDailyJackpot.selector,
                        false, purchaseLevel, word, _phaseAllowance(meter)
                    ));
                }
                if (result.done && !_purchaseTicketLegPending()) {
                    _sealPurchaseDay(purchaseLevel, day, _simulatedDayIndex(), purchaseStartDay);
                }
                stage = STAGE_PURCHASE_DAILY;
            } else {
                // The consolidated-pool transition is a single atomic accounting action.
                if (!MineFlipGas.canRun(meter, GasBounds.POOL_CONSOLIDATION, GasBounds.DAILY_PHASE_TAIL)) return result;
                uint256 achieved = _getNextPrizePool();
                levelPrizePool[purchaseLevel] = achieved;
                if (purchaseLevel % 100 == 0) centuryPrizePools.push(uint128(achieved));
                if (purchaseLevel >= 2) {
                    parimutuel.recordGrowth(purchaseLevel - 1,
                        _growthOver(_growthRatchet(purchaseLevel - 2), _growthRatchet(purchaseLevel - 1), achieved));
                }
                _distributeYieldSurplus(word);
                _consolidatePoolsAndRewardJackpots(lvl, purchaseLevel, day, word, purchaseStartDay);
                jackpotPhaseFlag = true;
                lastPurchaseDay = false;
                quests.rollLevelQuest(word);
                result.progressed = true;
                result.done = true;
                stage = STAGE_ENTERED_JACKPOT;
            }
        } else if (_earlyBirdLegPending()) {
            result = _runJackpotWork(abi.encodeWithSelector(
                IDegenerusGameJackpotModule.runEarlyBirdTickets.selector, word, _phaseAllowance(meter)
            ));
            stage = STAGE_JACKPOT_EARLY_BIRD_TICKETS;
        } else if (dailyJackpotCoinTicketsPending) {
            result = _runJackpotWork(abi.encodeWithSelector(
                IDegenerusGameJackpotModule.runDailyJackpotTickets.selector, word, _phaseAllowance(meter)
            ));
            if (result.done) {
                if (jackpotCounter >= _jackpotDays()) {
                    _endPhase(lvl);
                    stage = STAGE_JACKPOT_PHASE_ENDED;
                } else {
                    _unlockRng(day);
                    stage = STAGE_JACKPOT_COIN_TICKETS;
                }
            } else stage = STAGE_JACKPOT_COIN_TICKETS;
        } else {
            result = _runJackpotWork(abi.encodeWithSelector(
                IDegenerusGameJackpotModule.runDailyJackpot.selector, true, lvl, word, _phaseAllowance(meter)
            ));
            stage = STAGE_JACKPOT_DAILY_STARTED;
        }
        MineFlipGas.finish(meter);
        if (result.progressed) emit Advance(stage, lvl);
    }

    function _phaseAllowance(MineFlipGas.Meter memory meter) private view returns (uint256) {
        return MineFlipGas.remaining(meter) - GasBounds.DAILY_PHASE_TAIL;
    }

    function _runJackpotWork(bytes memory callData) private returns (MineFlipGas.Result memory) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE.delegatecall{
            gas: MineFlipGas.forwardable(gasleft(), 150_000)
        }(callData);
        if (!ok) _revertDelegate(data);
        return abi.decode(data, (MineFlipGas.Result));
    }

    /// @notice Terminal handling always precedes live-game mutations.
    function runTerminalPhase(uint256 allowance) external {
        MineFlipGas.Meter memory meter = MineFlipGas.start(allowance);
        if (!MineFlipGas.canRun(meter, 100_000, 150_000)) return;
        if (address(this) != ContractAddresses.GAME || (!gameOver && !_livenessTriggered())) revert E();
        (bool handled, uint8 stage) = _handleGameOverPath(_simulatedDayIndex(), level, MineFlipGas.remaining(meter) - GasBounds.DAILY_PHASE_TAIL);
        MineFlipGas.finish(meter);
        if (!handled) revert E();
        emit Advance(stage, level);
    }

    /// @notice Fresh daily boundary only; the caller seals and sends in this same transaction.
    function prepareRequestBoundary(uint24 day) external {
        if (address(this) != ContractAddresses.GAME || !_lootboxReadComplete() || _livenessTriggered()
            || day != _afkingResetDay || day <= dailyIdx || !subsFullyProcessed) revert E();
        uint24 wallDay = _simulatedDayIndex();
        uint24 psd = purchaseStartDay;
        if (!jackpotPhaseFlag && !lastPurchaseDay && day == wallDay && day >= psd
            && _lrRead(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK) != 1) {
            if (day - psd <= 1 && level % 10 != 9 && _getNextPrizePool() > _prizePoolTarget(level + 1)) {
                lastPurchaseDay = true;
                jackpotFlags |= JACKPOT_TURBO;
                _markTicketGenerationStart(level + 2);
            }
        }
        bool isTicketJackpotDay = !jackpotPhaseFlag && lastPurchaseDay;
        if (isTicketJackpotDay && (jackpotFlags & JACKPOT_TURBO) != 0) _activateNextTickets();
        uint24 lvl = level + 1;
        uint48 lvlAndQuestDay = (uint48(day) << 24) | uint48(lvl);
        rngLockedFlag = true;
        uint24 battleDay = uint24(lvlAndQuestDay >> 24);
        if (battleDay != 0) {
            uint24 poolLevel = jackpotPhaseFlag && level != 0 ? level - 1 : level;
            IJackpotBattle(ContractAddresses.CRAPS).lockJackpotBattle(battleDay, levelPrizePool[poolLevel], level);
            dailyTicketBudgetsPacked |= _JACKPOT_BATTLE_PENDING;
        }

        // Decimator opening-day quest / auto-entry latch closes at the next fresh daily request.
        // A retry re-requests the SAME day's word, so it must not clear the latch.
        // Runs before the window-open branch below, so the arming request itself
        // (clear-then-set) leaves the latch armed.
        if (_decDayOneActive()) {
            _setDecDayOneActive(false);
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
        if (finalJackpotRequest && _ticketRedemptionOpen()) _setTicketRedemptionOpen(false);

        // Increment level at RNG request time when lastPurchaseDay = true.
        // lvl is already purchaseLevel (= level + 1), so set directly.
        // Only on a fresh daily request - a daily retry would double-increment, and an
        // in-flight mid-day lootbox request must not suppress this increment.
        if (isTicketJackpotDay) {
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
                _setDecWindowOpen(true);
                decBattleRounds[lvl + 1].openedDay = _simulatedDayIndex();
                // Arm the opening-day quest and protocol auto-entry.
                _setDecDayOneActive(true);
            } else if (_decWindowOpen() && ((mod10 == 5 && mod100 != 95) || mod100 == 0)) {
                _setDecWindowOpen(false);
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
        // of the two forces always wins here. _decDayOneActive() is read AFTER the arming block
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
        // (no RNGREUSE clamp applies while a request is pending — rngWordCurrent is RNG_WORD_WAITING), so
        // an ungated roll would force a SECOND foil daily on a day whose one-per-cycle slot
        // the first day's quest may already have spent: a quest that can only miss.
        uint24 questDay = uint24(lvlAndQuestDay >> 24);
        if (finalJackpotRequest && questDay == _simulatedDayIndex()) {
            quests.rollDailyQuest(questDay, 0, false, true, _decDayOneActive());
        }

    }
    function _handleGameOverPath(uint24 day, uint24 lvl, uint256 allowance) private returns (bool shouldReturn, uint8 stage) {
        // The sole caller, runTerminalPhase, already authenticated terminal liveness.
        (bool ok, bytes memory data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameGameOverModule.runGameOverAdvance.selector, day, lvl, allowance)
        );
        if (!ok) _revertDelegate(data);
        bool unlock;
        (shouldReturn, stage, unlock) = abi.decode(data, (bool, uint8, bool));
        if (unlock) _unlockRng(day);
    }

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

    function _distributeYieldSurplus(uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(abi.encodeWithSelector(IDegenerusGameJackpotModule.distributeYieldSurplus.selector, rngWord));
        if (!ok) _revertDelegate(data);
    }

    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert EmptyRevert();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    struct PoolSettlement {
        uint256 next;
        uint256 future;
        uint256 current;
        uint256 yield;
        uint256 claimable;
    }

    function _consolidatePoolsAndRewardJackpots(
        uint24 lvl,
        uint24 purchaseLevel,
        uint24 day,
        uint256 rngWord,
        uint24 psd
    ) private {
        (uint128 packedNext, uint128 packedFuture) = _getPrizePools();
        PoolSettlement memory p;
        p.future = packedFuture;
        p.current = _getCurrentPrizePool();
        p.next = packedNext;
        p.yield = yieldAccumulator;

        // --- Time-based future take (batched) ---
        {
            uint32 purchaseAge = day > psd ? day - psd : 0;
            uint256 bps = _nextToFutureBps(purchaseAge, purchaseLevel);
            if (purchaseLevel % 10 == 9) bps += NEXT_TO_FUTURE_BPS_X9_BONUS;

            uint256 lastPool = levelPrizePool[purchaseLevel - 1];

            // Ratio adjust: ±4% based on future/next ratio (target 2:1)
            uint256 ratioPct = (p.future * 100) / p.next;
            if (ratioPct < 200) {
                bps += (200 - ratioPct) * 2;
            } else {
                uint256 penalty = ratioPct - 200;
                penalty = penalty > 400 ? 400 : penalty;
                bps = penalty >= bps ? 0 : bps - penalty;
            }

            // Overshoot surcharge
            if (lastPool != 0) {
                uint256 rBps = (p.next * 10_000) / lastPool;
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
            uint256 take = (p.next * bps) / 10_000;

            // Triangular variance (avg of two uniform VRF rolls) with half-width
            // max(25% of take, 10% of nextPool), capped at take; the final take is
            // capped at 80% of nextPool below.
            if (take != 0) {
                uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
                uint256 minWidth = (p.next * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000;
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
            uint256 maxTake = (p.next * NEXT_TO_FUTURE_BPS_MAX) / 10_000;
            if (take > maxTake) take = maxTake;

            uint256 insuranceSkim = (p.next * INSURANCE_SKIM_BPS) / 10_000;
            p.next -= take + insuranceSkim;
            p.future += take;
            p.yield += insuranceSkim;
            // Emitted here, inside the block, so the two amounts are read where they are
            // still live — the pools they move keep mutating through the reward jackpots
            // below, so a later emit would have to carry them out by hand.
            emit PoolSkimApplied(lvl, take, insuranceSkim);
        }

        // --- x00 yield accumulator dump: 40% into futurePool (memory) ---
        if ((lvl % 100) == 0) {
            uint256 dump = (p.yield * 40) / 100;
            p.future += dump;
            p.yield -= dump;
        }

        // --- BAF + Decimator x00: draw from futurePool BEFORE keep roll ---
        uint256 baseMemFuture = p.future;
        uint24 prevMod10 = lvl % 10;
        uint24 prevMod100 = lvl % 100;


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
                p.future -= claimed;
                p.claimable += claimed;
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
            decPoolWei = (p.future * 10) / 100;
        }

        // Seal even a zero-pool event so every entered battle reaches a final result.
        if (decPoolWei != 0 || decBattleRounds[lvl].count != 0) {
            uint256 returnWei = IDegenerusGame(address(this)).runDecimatorJackpot(decPoolWei, lvl, rngWord);
            uint256 spend = decPoolWei - returnWei;
            p.future -= spend;
            p.claimable += spend;
        }

        // --- x00 keep roll (5d4 dice: 50-80% keep, avg 65%) ---
        // Operates on post-jackpot p.future — all reward jackpots drew first.
        if ((lvl % 100) == 0) {
            uint256 seed = EntropyLib.hash2(rngWord, uint256(FUTURE_KEEP_TAG));
            uint256 total;
            unchecked {
                total = (seed % 4) + ((seed >> 16) % 4) + ((seed >> 32) % 4) + ((seed >> 48) % 4) + ((seed >> 64) % 4);
            }
            uint256 keepBps = 5000 + (total * 3000) / 15;
            if (keepBps < 10_000) {
                uint256 moveWei = p.future - (p.future * keepBps) / 10_000;
                p.future -= moveWei;
                p.current += moveWei;
            }
        }

        // --- Merge next → current ---
        p.current += p.next;
        p.next = 0;

        // --- The house's level cut: high-roller craps passes ---
        // A twentieth of the consolidated pool, priced in FLIP at this level, banks to sDGNRS as
        // high-roller day passes rather than as a coinflip stake — one pass per
        // HIGH_ROLLER_DAY_PASS_VALUE, rounded down, the fraction under a whole pass dropped.
        // sDGNRS has no door of its own, so the table spends them: its daily seat reaches for a
        // banked high pass before FLIP and sits the house at the day's high multiple.
        // purchaseLevel == storage level here: consolidation runs only on the
        // lastPurchase leg with rngLockedFlag held, after the request-time
        // level pre-increment.
        uint256 highPasses = (p.current * PRICE_COIN_UNIT)
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
            uint256 reserved = (p.future * 15) / 100;
            p.future -= reserved;
            p.next = reserved;
        }

        // --- Single SSTORE batch: all pool values ---
        _setPrizePools(uint128(p.next), uint128(p.future));
        currentPrizePool = uint128(p.current);
        yieldAccumulator = p.yield;
        if (p.claimable != 0) {
            claimablePool += uint128(p.claimable); // Safe: p.claimable bounded by futurePool which fits uint128
        }
        emit PoolsSettled(lvl, day, psd, p.next, p.future, p.current, p.yield, claimablePool, p.claimable);
    }

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

    function _payDailyCoinJackpot(uint24 lvl, uint256 randWord, uint24 minLevel, uint24 maxLevel) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyFlipJackpot.selector, lvl, randWord, minLevel, maxLevel
                )
            );
        if (!ok) _revertDelegate(data);
    }

    function _markTicketGenerationStart(uint24 lvl) private {
        if (ticketGenerationStartBlock[lvl] == 0) ticketGenerationStartBlock[lvl] = block.number;
    }

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

    function _processPhaseTransition(uint24 purchaseLevel) private {
        (bool ok, bytes memory data) = ContractAddresses.GAME_FOILPACK_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameFoilPackModule.queuePerpetualTickets.selector, purchaseLevel + 99)
        );
        if (!ok) _revertDelegate(data);

        // Auto-stake all non-claimable ETH into stETH for yield generation.
        // Non-blocking: if stETH contract fails, game continues normally.
        _autoStakeExcessEth();
    }

    function _autoStakeExcessEth() private {
        uint256 ethBal = address(this).balance;
        uint256 reserve = claimablePool;
        if (ethBal <= reserve) return;
        uint256 stakeable = ethBal - reserve;
        try steth.submit{value: stakeable, gas: 500_000}(address(0)) returns (uint256) {}
        catch (bytes memory reason) {
            MineFlipGas.rethrowGasFailure(reason);
            emit StEthStakeFailed(stakeable);
        }
    }

    function _growthOver(uint256 prevR, uint256 currR, uint256 nextR) internal pure returns (bool) {
        return nextR * prevR > currR * currR;
    }

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

    function _unlockRng(uint24 day) private {
        // Game-over keeps its stale dailyIdx: the deadman reads currentDay - dailyIdx, so
        // advancing it here would retire the very staleness that declared the game dead and
        // let _livenessTriggered read false again while gameOver stays true — reopening every
        // liveness-gated paid entrypoint. A dead game seals no day, so nothing else wants it.
        if (!gameOver) dailyIdx = day;
        bool wasLocked = rngLockedFlag;
        rngLockedFlag = false;
        // Retain the session word until every remaining read consumer completes.
        _setRngRequestActive(false);
        _unfreezePool();
        // The day-seal is the one chokepoint every completed game-day passes through (purchase
        // daily, jackpot coin+tickets, phase transition). Emit the daily pool
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
        _tryCompleteRng();
    }

    function _afKingSubDraw(uint24 day) private {
        uint256 len = _subscribers.length;
        uint256 word = _recordedDailyWord(day);
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
}
