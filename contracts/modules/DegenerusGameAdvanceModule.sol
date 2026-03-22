// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {
    IDegenerusGameEndgameModule,
    IDegenerusGameGameOverModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule
} from "../interfaces/IDegenerusGameModules.sol";
import {
    IVRFCoordinator,
    VRFRandomWordsRequest
} from "../interfaces/IVRFCoordinator.sol";
import {IStETH} from "../interfaces/IStETH.sol";
import {IStakedDegenerusStonk} from "../interfaces/IStakedDegenerusStonk.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

import {BitPackingLib} from "../libraries/BitPackingLib.sol";

/// @dev Vault interface for DGVE ownership check (advanceGame mint-gate bypass).
interface IDegenerusVaultOwner {
    function isVaultOwner(address account) external view returns (bool);
}

/// @notice Delegate-called module for advanceGame and VRF lifecycle handling.
contract DegenerusGameAdvanceModule is DegenerusGameStorage {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    // error E() — inherited from DegenerusGameStorage
    error MustMintToday();
    error NotTimeYet();
    error RngNotReady();
    error RngLocked();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    event Advance(uint8 stage, uint24 lvl);

    // Advance stage constants (sequential, matching advanceGame flow)
    uint8 private constant STAGE_GAMEOVER = 0;
    uint8 private constant STAGE_RNG_REQUESTED = 1;
    uint8 private constant STAGE_TRANSITION_WORKING = 2;
    uint8 private constant STAGE_TRANSITION_DONE = 3;
    uint8 private constant STAGE_FUTURE_TICKETS_WORKING = 4;
    uint8 private constant STAGE_TICKETS_WORKING = 5;
    uint8 private constant STAGE_PURCHASE_DAILY = 6;
    uint8 private constant STAGE_ENTERED_JACKPOT = 7;
    uint8 private constant STAGE_JACKPOT_ETH_RESUME = 8;
    uint8 private constant STAGE_JACKPOT_COIN_TICKETS = 9;
    uint8 private constant STAGE_JACKPOT_PHASE_ENDED = 10;
    uint8 private constant STAGE_JACKPOT_DAILY_STARTED = 11;
    event ReverseFlip(
        address indexed caller,
        uint256 totalQueued,
        uint256 cost
    );
    event DailyRngApplied(
        uint48 day,
        uint256 rawWord,
        uint256 nudges,
        uint256 finalWord
    );
    event LootboxRngApplied(uint48 index, uint256 word, uint256 requestId);
    event VrfCoordinatorUpdated(
        address indexed previous,
        address indexed current
    );
    event StEthStakeFailed(uint256 amount);

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+*/

    IDegenerusCoin internal constant coin =
        IDegenerusCoin(ContractAddresses.COIN);
    IBurnieCoinflip internal constant coinflip =
        IBurnieCoinflip(ContractAddresses.COINFLIP);
    IStETH internal constant steth =
        IStETH(ContractAddresses.STETH_TOKEN);
    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+*/

    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 365;
    uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 3 days;
    uint8 private constant JACKPOT_LEVEL_CAP = 5;
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 300_000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint16 private constant VRF_MIDDAY_CONFIRMATIONS = 3;
    uint256 private constant RNG_NUDGE_BASE_COST = 100 ether;
    uint256 private constant BURNIE_RNG_TRIGGER = 40_000 ether;
    uint32 private constant VAULT_PERPETUAL_TICKETS = 16;
    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 3000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 1300;
    uint16 private constant NEXT_TO_FUTURE_BPS_WEEK_STEP = 100;
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 2500;
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;
    uint16 private constant INSURANCE_SKIM_BPS = 100; // 1% of nextPool -> yieldAccumulator
    uint16 private constant OVERSHOOT_THRESHOLD_BPS = 12500;  // R > 1.25x triggers surcharge
    uint16 private constant OVERSHOOT_CAP_BPS = 3500;         // 35% max surcharge
    uint16 private constant OVERSHOOT_COEFF = 4000;           // numerator coefficient (0.40 in bps)
    uint16 private constant NEXT_TO_FUTURE_BPS_MAX = 8000;    // 80% total skim hard cap
    uint16 private constant ADDITIVE_RANDOM_BPS = 1000;      // 0–10% additive random on bps
    uint96 private constant MIN_LINK_FOR_LOOTBOX_RNG = 40 ether;

    /// @dev Presale auto-ends after this much mint-only lootbox ETH (200 ETH, unscaled).
    uint256 private constant LOOTBOX_PRESALE_ETH_CAP = 200 ether;

    /// @dev ETH-equivalent target for advanceGame bounty (~0.01 ETH worth of BURNIE).
    uint256 private constant ADVANCE_BOUNTY_ETH = 0.01 ether;

    /// @dev Vault contract for DGVE ownership check (advanceGame mint-gate bypass).
    IDegenerusVaultOwner private constant vault =
        IDegenerusVaultOwner(ContractAddresses.VAULT);

    /// @notice Advance game state. Called daily to process jackpots, mints, and phase transitions.
    ///         Caller receives ~0.01 ETH worth of BURNIE as flip credit.
    function advanceGame() external {
        address caller = msg.sender;
        uint256 advanceBounty = (ADVANCE_BOUNTY_ETH * PRICE_COIN_UNIT) / price;
        uint48 ts = uint48(block.timestamp);
        uint48 day = _simulatedDayIndexAt(ts);
        bool inJackpot = jackpotPhaseFlag;
        uint24 lvl = level;
        // Turbo: if target already met on day ≤1, flag now so _requestRng
        // does the level pre-increment (matching normal lastPurchaseDay flow).
        if (!inJackpot && !lastPurchaseDay) {
            uint48 purchaseDays = day - purchaseStartDay;
            if (purchaseDays <= 1 && _getNextPrizePool() >= levelPrizePool[lvl]) {
                lastPurchaseDay = true;
                compressedJackpotFlag = 2;
            }
        }
        bool lastPurchase = (!inJackpot) && lastPurchaseDay;
        // Level already incremented at RNG request when lastPurchase=true
        uint24 purchaseLevel = (lastPurchase && rngLockedFlag) ? lvl : lvl + 1;
        if (
            _handleGameOverPath(
                ts,
                day,
                levelStartTime,
                lvl,
                lastPurchase,
                dailyIdx
            )
        ) {
            emit Advance(STAGE_GAMEOVER, lvl);
            return;
        }

        _enforceDailyMintGate(caller, purchaseLevel, dailyIdx);

        // --- Mid-day path: same-day queue draining ---
        if (day == dailyIdx) {
            // Step 1: Finish draining the read slot if not yet fully processed
            if (!ticketsFullyProcessed) {
                // If mid-day ticket swap is pending, wait for VRF word before processing
                if (midDayTicketRngPending) {
                    uint256 word = lootboxRngWordByIndex[lootboxRngIndex - 1];
                    if (word == 0) revert NotTimeYet();
                    // VRF word arrived — update entropy source before processing tickets
                    lastLootboxRngWord = word;
                }

                uint24 rk = _tqReadKey(purchaseLevel);
                if (ticketQueue[rk].length > 0) {
                    (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
                    if (ticketWorked || !ticketsFinished) {
                        emit Advance(STAGE_TICKETS_WORKING, lvl);
                        coin.creditFlip(caller, advanceBounty);
                        return;
                    }
                }
                ticketsFullyProcessed = true;
            }

            // Clear mid-day ticket flag after drain completes
            if (midDayTicketRngPending) {
                midDayTicketRngPending = false;
            }

            // Swap write buffer during jackpot phase only (daily VRF word is active)
            if (inJackpot) {
                uint24 wk = _tqWriteKey(purchaseLevel);
                if (ticketQueue[wk].length > 0) {
                    _swapTicketSlot(purchaseLevel);
                    emit Advance(STAGE_TICKETS_WORKING, lvl);
                    coin.creditFlip(caller, advanceBounty);
                    return;
                }
            }
            revert NotTimeYet();
        }

        // Escalate bounty if daily processing is stalled (new-day path only).
        // 2x after 1 hour past jackpot reset, 3x after 2 hours, capped at 3x.
        {
            uint256 dayStart = (uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY)
                * 1 days + 82_620;
            uint256 elapsed = ts - dayStart;
            if (elapsed >= 2 hours) {
                advanceBounty *= 3;
            } else if (elapsed >= 1 hours) {
                advanceBounty *= 2;
            }
        }

        // --- Daily drain gate: ensure read slot is fully processed before RNG ---
        if (!ticketsFullyProcessed) {
            uint24 rk = _tqReadKey(purchaseLevel);
            if (ticketQueue[rk].length > 0) {
                (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(purchaseLevel);
                if (ticketWorked || !ticketsFinished) {
                    emit Advance(STAGE_TICKETS_WORKING, lvl);
                    coin.creditFlip(caller, advanceBounty);
                    return;
                }
            }
            ticketsFullyProcessed = true;
        }

        uint8 stage;
        do {
            // RNG: use existing word or request new one
            bool bonusFlip = (inJackpot && jackpotCounter == 0) || lvl == 0;
            uint256 rngWord = rngGate(ts, day, purchaseLevel, lastPurchase, bonusFlip);
            if (rngWord == 1) {
                _swapAndFreeze(purchaseLevel);
                stage = STAGE_RNG_REQUESTED;
                break;
            }

            // Phase transition housekeeping + near-future tickets
            if (phaseTransitionActive) {
                if (!_processPhaseTransition(purchaseLevel)) {
                    stage = STAGE_TRANSITION_WORKING;
                    break;
                }
                phaseTransitionActive = false;
                _unlockRng(day);
                _unfreezePool();
                purchaseStartDay = day;
                jackpotPhaseFlag = false;
                stage = STAGE_TRANSITION_DONE;
                break;
            }

            // Process near-future ticket queues (+2..+6) before daily draws
            // to include fresh lootbox-driven tickets from pass purchases.
            if (
                !dailyJackpotCoinTicketsPending &&
                dailyEthPoolBudget == 0 &&
                dailyEthPhase == 0 &&
                dailyEthBucketCursor == 0 &&
                dailyEthWinnerCursor == 0
            ) {
                if (!_prepareFutureTickets(lvl)) {
                    stage = STAGE_FUTURE_TICKETS_WORKING;
                    break;
                }
            }

            // Process current level tickets
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(
                purchaseLevel
            );
            if (ticketWorked || !ticketsFinished) {
                stage = STAGE_TICKETS_WORKING;
                break;
            }
            ticketsFullyProcessed = true;  // ADV-03: set before jackpot/phase logic

            // === PURCHASE PHASE ===
            if (!inJackpot) {
                // Pre-target: daily jackpots while building prize pool
                if (!lastPurchaseDay) {
                    payDailyJackpot(false, purchaseLevel, rngWord);
                    _payDailyCoinJackpot(purchaseLevel, rngWord);
                    if (_getNextPrizePool() >= levelPrizePool[purchaseLevel - 1]) {
                        lastPurchaseDay = true;
                        if (day - purchaseStartDay <= 3) {
                            compressedJackpotFlag = 1;
                        }
                    }
                    _unlockRng(day);
                    _unfreezePool();
                    stage = STAGE_PURCHASE_DAILY;
                    break;
                }

                // Activate next-level tickets before jackpot phase
                {
                    uint24 nextLevel = purchaseLevel + 1;
                    (
                        bool futureWorked,
                        bool futureFinished,

                    ) = _processFutureTicketBatch(nextLevel);
                    if (futureWorked || !futureFinished) {
                        stage = STAGE_FUTURE_TICKETS_WORKING;
                        break;
                    }
                }

                // Consolidate prize pools for level transition
                if (!poolConsolidationDone) {
                    levelPrizePool[purchaseLevel] = _getNextPrizePool();
                    _applyTimeBasedFutureTake(ts, purchaseLevel, rngWord);
                    _consolidatePrizePools(purchaseLevel, rngWord);
                    poolConsolidationDone = true;
                }

                if (lootboxPresaleActive && (lvl >= 3 || lootboxPresaleMintEth >= LOOTBOX_PRESALE_ETH_CAP)) lootboxPresaleActive = false;

                // Transition to jackpot phase
                jackpotPhaseFlag = true;

                // Open decimator window: levels x4 (not x94) or x99
                uint24 mod100 = lvl % 100;
                if ((lvl % 10 == 4 && mod100 != 94) || mod100 == 99) {
                    decWindowOpen = true;
                }

                poolConsolidationDone = false;
                lastPurchaseDay = false;
                levelStartTime = ts;
                _drawDownFuturePrizePool(lvl);
                // Do not unlock here: allows day-1 jackpot processing to run on
                // the same day as the transition day.
                stage = STAGE_ENTERED_JACKPOT;
                break;
            }

            // === JACKPOT PHASE ===

            // Resume split ETH distribution (Phase 0 mid-bucket OR Phase 1 carryover)
            // Must match payDailyJackpot's isResuming condition to avoid
            // emitting STAGE_JACKPOT_DAILY_STARTED on what is actually a resume.
            if (
                dailyEthBucketCursor != 0 ||
                dailyEthPhase != 0 ||
                dailyEthPoolBudget != 0 ||
                dailyEthWinnerCursor != 0
            ) {
                payDailyJackpot(true, lastDailyJackpotLevel, rngWord);
                stage = STAGE_JACKPOT_ETH_RESUME;
                break;
            }

            // Complete coin+ticket distribution
            if (dailyJackpotCoinTicketsPending) {
                payDailyJackpotCoinAndTickets(rngWord);
                if (jackpotCounter >= JACKPOT_LEVEL_CAP) {
                    _awardFinalDayDgnrsReward(lvl, rngWord);
                    _rewardTopAffiliate(lvl);
                    _runRewardJackpots(lvl, rngWord);
                    _endPhase();
                    _unfreezePool();
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

        emit Advance(stage, lvl);
        coin.creditFlip(caller, advanceBounty);
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
        if (msg.sender != ContractAddresses.ADMIN) revert E();

        address current = address(vrfCoordinator);
        vrfCoordinator = IVRFCoordinator(coordinator_);
        vrfSubscriptionId = subId;
        vrfKeyHash = keyHash_;
        lastVrfProcessedTimestamp = uint48(block.timestamp);
        emit VrfCoordinatorUpdated(current, coordinator_);
    }

    /*+======================================================================+
      |                    GAMEOVER / LIVENESS GUARDS                        |
      +======================================================================+*/

    /// @dev Handles gameover state and liveness guard checks.
    ///      Returns true if advanceGame should exit early.
    function _handleGameOverPath(
        uint48 ts,
        uint48 day,
        uint48 lst,
        uint24 lvl,
        bool lastPurchase,
        uint48 /* _dailyIdx */
    ) private returns (bool shouldReturn) {
        // Liveness guard: prevent permanent lockup if game is abandoned
        bool livenessTriggered = (lvl == 0 &&
            ts - lst > uint256(DEPLOY_IDLE_TIMEOUT_DAYS) * 1 days) ||
            (lvl != 0 && ts - 120 days > lst);

        if (!livenessTriggered) return false;

        bool ok;
        bytes memory data;

        if (gameOver) {
            // Post-gameover: check for final sweep (1 month after gameover)
            (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameGameOverModule.handleFinalSweep.selector
                )
            );
            if (!ok) _revertDelegate(data);
            return true;
        }

        // Safety: don't activate game over if nextPool requirement is already met
        if (lvl != 0 && _getNextPrizePool() >= levelPrizePool[lvl]) {
            levelStartTime = ts;
            return false;
        }

        // Pre-gameover: acquire RNG and drain to gameover state
        if (rngWordByDay[day] == 0) {
            uint256 rngWord = _gameOverEntropy(ts, day, lvl, lastPurchase);
            if (rngWord == 1 || rngWord == 0) return true;
            _unlockRng(day);
        }

        (ok, data) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeWithSelector(
                IDegenerusGameGameOverModule.handleGameOverDrain.selector,
                day
            )
        );
        if (!ok) _revertDelegate(data);
        return true;
    }

    /*+======================================================================+
      |                           LEVEL END                                 |
      +======================================================================+*/
    function _endPhase() private {
        uint24 lvl = level;
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
      |  • ContractAddresses.GAME_ENDGAME_MODULE  - Endgame settlement (payouts, wipes, ContractAddresses.JACKPOTS)    |
      |  • ContractAddresses.GAME_MINT_MODULE     - Mint data recording, airdrop multipliers                           |
      |  • ContractAddresses.GAME_WHALE_MODULE    - Whale bundle purchases                                              |
      |  • ContractAddresses.GAME_JACKPOT_MODULE  - Jackpot calculations and payouts                                   |
      |                                                                                                                |
      |  SECURITY: delegatecall executes module code in this contract's                                                |
      |  context, with access to all storage. Modules are constant.                                                    |
      +================================================================================================================+*/

    /// @dev Reward the top affiliate for a level during level transition.
    function _rewardTopAffiliate(uint24 lvl) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ENDGAME_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameEndgameModule.rewardTopAffiliate.selector,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Resolve BAF/Decimator jackpots during the level transition RNG period.
    function _runRewardJackpots(uint24 lvl, uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ENDGAME_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameEndgameModule.runRewardJackpots.selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Bubble up revert reason from delegatecall failure.
    ///      Uses assembly to preserve original error data.
    /// @param reason The error bytes from failed delegatecall.
    function _revertDelegate(bytes memory reason) private pure {
        if (reason.length == 0) revert E();
        assembly ("memory-safe") {
            revert(add(32, reason), mload(reason))
        }
    }

    /// @dev Consolidate prize pools via jackpot module delegatecall.
    ///      Merges next→current, rebalances future/current, credits coinflip, distributes yield.
    function _consolidatePrizePools(uint24 lvl, uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule
                        .consolidatePrizePools
                        .selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Award DGNRS reward to the solo bucket winner after final daily jackpot.
    function _awardFinalDayDgnrsReward(uint24 lvl, uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule
                        .awardFinalDayDgnrsReward
                        .selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay daily jackpot via jackpot module delegatecall.
    ///      Called each day during purchase phase and jackpot phase.
    /// @param isDaily True for jackpot phase, false for purchase phase (early-burn).
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    function payDailyJackpot(
        bool isDaily,
        uint24 lvl,
        uint256 randWord
    ) internal {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyJackpot.selector,
                    isDaily,
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

    /// @dev Pay daily BURNIE jackpot via jackpot module delegatecall.
    ///      Called each day during purchase phase in its own transaction.
    ///      Awards 0.5% of prize pool target in BURNIE to current and future ticket holders.
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    function _payDailyCoinJackpot(uint24 lvl, uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payDailyCoinJackpot.selector,
                    lvl,
                    randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }


    /// @dev Enforce "must mint today" gate for advanceGame callers.
    ///      Bypass tiers (only checked on revert path, zero cost for normal callers):
    ///        1. Deity pass holder — always bypasses
    ///        2. Anyone — bypasses 30+ min after day boundary
    ///        3. Any pass holder (lazy/whale freeze active) — bypasses 15+ min after day boundary
    ///        4. DGVE majority holder — always bypasses (last resort, external call)
    function _enforceDailyMintGate(
        address caller,
        uint24 lvl,
        uint48 dailyIdx_
    ) private view {
        uint32 gateIdx = uint32(dailyIdx_);
        if (gateIdx == 0) return;

        uint256 mintData = mintPacked_[caller];
        uint32 lastEthDay = uint32(
            (mintData >> BitPackingLib.DAY_SHIFT) & BitPackingLib.MASK_32
        );
        // Allow mints from current day or previous day
        if (lastEthDay + 1 < gateIdx) {
            // Deity pass — always bypasses
            if (deityPassCount[caller] != 0) return;

            // Time elapsed since today's day boundary (pure arithmetic, no SLOAD)
            // 82620 = 22:57 UTC = JACKPOT_RESET_TIME
            uint256 elapsed = (block.timestamp - 82620) % 1 days;

            // Anyone after 30 min
            if (elapsed >= 30 minutes) return;

            // Any pass holder after 15 min
            if (elapsed >= 15 minutes) {
                uint24 frozenUntilLevel = uint24(
                    (mintData >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) &
                        BitPackingLib.MASK_24
                );
                if (frozenUntilLevel > lvl) return;
            }

            // DGVE majority bypass — last resort, external call
            if (!vault.isVaultOwner(caller))
                revert MustMintToday();
        }
    }

    /// @notice Request lootbox RNG when activity threshold is met.
    /// @dev Standalone function for mid-day lootbox RNG requests.
    ///      Cannot be called while daily RNG is locked (jackpot resolution).
    ///      VRF callback handles finalization directly - no advanceGame needed.
    function requestLootboxRng() external {
        if (rngLockedFlag) revert RngLocked();

        uint48 nowTs = uint48(block.timestamp);
        uint48 currentDay = _simulatedDayIndexAt(nowTs);

        // Block in the 15-minute pre-reset window to avoid competing with daily jackpot RNG flow.
        if (_simulatedDayIndexAt(nowTs + 15 minutes) > currentDay) revert E();
        // Block until today's daily RNG has been consumed and recorded.
        if (rngWordByDay[currentDay] == 0) revert E();

        if (rngRequestTime != 0) revert E();

        // LINK balance check
        (uint96 linkBal, , , , ) = vrfCoordinator.getSubscription(vrfSubscriptionId);
        if (linkBal < MIN_LINK_FOR_LOOTBOX_RNG) revert E();

        // Threshold check
        uint256 pendingEth = lootboxRngPendingEth;
        uint256 pendingBurnie = lootboxRngPendingBurnie;
        if (pendingEth == 0 && pendingBurnie == 0) revert E();
        if (pendingBurnie < BURNIE_RNG_TRIGGER) {
            uint256 totalEthEquivalent = pendingEth;
            if (pendingBurnie != 0) {
                uint256 priceWei = price;
                if (priceWei != 0) {
                    totalEthEquivalent +=
                        (pendingBurnie * priceWei) /
                        PRICE_COIN_UNIT;
                }
            }
            uint256 threshold = lootboxRngThreshold;
            if (threshold != 0 && totalEthEquivalent < threshold) revert E();
        }

        // Freeze ticket buffer: swap write→read so tickets purchased after
        // VRF delivery can't be resolved by this word.
        {
            uint24 purchaseLevel_ = level + 1;
            uint24 wk = _tqWriteKey(purchaseLevel_);
            if (ticketQueue[wk].length > 0 && ticketsFullyProcessed) {
                _swapTicketSlot(purchaseLevel_);
                midDayTicketRngPending = true;
            }
        }

        // VRF request (reverts on failure)
        uint256 id = vrfCoordinator.requestRandomWords(
            VRFRandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: VRF_MIDDAY_CONFIRMATIONS,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: hex""
            })
        );

        _reserveLootboxRngIndex(id);
        vrfRequestId = id;
        rngWordCurrent = 0;
        rngRequestTime = uint48(block.timestamp);
    }

    // BIT ALLOCATION MAP for VRF random word (currentWord after _applyDailyRng):
    //
    // Bit(s)   Consumer                    Operation                         Location
    // ------   --------                    ---------                         --------
    // 0        Coinflip win/loss           rngWord & 1                       BurnieCoinflip.sol:809
    // 8+       Redemption roll             (currentWord >> 8) % 151 + 25     AdvanceModule.sol:795
    // full     Coinflip reward percent     keccak256(rngWord, epoch) % 20    BurnieCoinflip.sol:783-788
    // full     Jackpot winner selection    via delegatecall (full word)      JackpotModule (payDailyJackpot)
    // full     Coin jackpot                via delegatecall (full word)      JackpotModule (_payDailyCoinJackpot)
    // full     Lootbox RNG                 stored as lootboxRngWordByIndex   AdvanceModule.sol:826
    // full     Future take variance        rngWord % (variance * 2 + 1)     AdvanceModule.sol:1033
    // full     Prize pool consolidation    via delegatecall (full word)      JackpotModule (consolidatePrizePools)
    // full     Final day DGNRS reward      via delegatecall (full word)      JackpotModule (awardFinalDayDgnrsReward)
    // full     Reward jackpots             via delegatecall (full word)      JackpotModule (_runRewardJackpots)
    //
    // NOTE: Bits 0 and 8+ are the only direct bit-level consumers.
    //       All "full" consumers use modular arithmetic or keccak mixing,
    //       so bit overlap with bits 0 and 8+ is not a collision concern.

    /// @dev Daily RNG processing gate called during advanceGame. Applies VRF word,
    ///      processes coinflip payouts, resolves pending gambling burn redemptions,
    ///      stores lootbox RNG, and handles VRF timeout retries (12h).
    function rngGate(
        uint48 ts,
        uint48 day,
        uint24 lvl,
        bool isTicketJackpotDay,
        bool bonusFlip
    ) internal returns (uint256 word) {
        // Already recorded for today
        if (rngWordByDay[day] != 0) return rngWordByDay[day];

        uint256 currentWord = rngWordCurrent;

        // Have a fresh VRF word ready
        if (currentWord != 0 && rngRequestTime != 0) {
            // Compute which day the RNG request was made on
            uint48 requestDay = _simulatedDayIndexAt(rngRequestTime);

            // If request was from a previous day, it's stale for daily operations
            if (requestDay < day) {
                // Use for lootboxes only, then request fresh daily RNG
                _finalizeLootboxRng(currentWord);
                rngWordCurrent = 0;
                _requestRng(isTicketJackpotDay, lvl);
                return 1;
            }

            // Backfill gap days from VRF stall before processing current day
            uint48 idx = dailyIdx;
            if (day > idx + 1) {
                _backfillGapDays(currentWord, idx + 1, day, bonusFlip);
            }

            // Normal daily RNG processing (request from current day)
            currentWord = _applyDailyRng(day, currentWord);
            coinflip.processCoinflipPayouts(bonusFlip, currentWord, day);

            // Resolve gambling burn period if pending
            {
                IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
                if (sdgnrs.hasPendingRedemptions()) {
                    uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);
                    uint48 flipDay = day + 1;
                    uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
                    if (burnieToCredit != 0) {
                        coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
                    }
                }
            }

            _finalizeLootboxRng(currentWord);
            return currentWord;
        }

        // Waiting for VRF - check for timeout retry
        if (rngRequestTime != 0) {
            uint48 elapsed = ts - rngRequestTime;
            if (elapsed >= 12 hours) {
                _requestRng(isTicketJackpotDay, lvl);
                return 1;
            }
            revert RngNotReady();
        }

        // Need fresh RNG
        _requestRng(isTicketJackpotDay, lvl);
        return 1;
    }

    function _finalizeLootboxRng(uint256 rngWord) private {
        uint48 index = lootboxRngRequestIndexById[vrfRequestId];
        if (index == 0) return;
        lootboxRngWordByIndex[index] = rngWord;
        lastLootboxRngWord = rngWord;
        emit LootboxRngApplied(index, rngWord, vrfRequestId);
    }

    /// @dev Game-over RNG gate with fallback for stalled VRF.
    ///      After 3-day timeout, uses earliest historical VRF word as fallback (more secure
    ///      than blockhash since it's already verified on-chain and cannot be manipulated).
    ///      Also resolves any pending gambling burn redemptions (mirrors rngGate behavior, CP-06 fix).
    /// @return word RNG word, 1 if request sent, or 0 if waiting on fallback.
    function _gameOverEntropy(
        uint48 ts,
        uint48 day,
        uint24 lvl,
        bool isTicketJackpotDay
    ) private returns (uint256 word) {
        if (rngWordByDay[day] != 0) return rngWordByDay[day];

        uint256 currentWord = rngWordCurrent;
        if (currentWord != 0 && rngRequestTime != 0) {
            currentWord = _applyDailyRng(day, currentWord);
            if (lvl != 0) {
                coinflip.processCoinflipPayouts(
                    isTicketJackpotDay,
                    currentWord,
                    day
                );
            }
            // Resolve gambling burn period if pending (mirrors rngGate lines 792-802)
            {
                IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
                if (sdgnrs.hasPendingRedemptions()) {
                    uint16 redemptionRoll = uint16((currentWord >> 8) % 151 + 25);
                    uint48 flipDay = day + 1;
                    uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
                    if (burnieToCredit != 0) {
                        coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
                    }
                }
            }
            _finalizeLootboxRng(currentWord);
            return currentWord;
        }

        if (rngRequestTime != 0) {
            uint48 elapsed = ts - rngRequestTime;
            if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {
                // Use earliest historical VRF word as fallback (more secure than blockhash)
                uint256 fallbackWord = _getHistoricalRngFallback(day);
                fallbackWord = _applyDailyRng(day, fallbackWord);
                if (lvl != 0) {
                    coinflip.processCoinflipPayouts(
                        isTicketJackpotDay,
                        fallbackWord,
                        day
                    );
                }
                // Resolve gambling burn period if pending (mirrors rngGate lines 792-802)
                {
                    IStakedDegenerusStonk sdgnrs = IStakedDegenerusStonk(ContractAddresses.SDGNRS);
                    if (sdgnrs.hasPendingRedemptions()) {
                        uint16 redemptionRoll = uint16((fallbackWord >> 8) % 151 + 25);
                        uint48 flipDay = day + 1;
                        uint256 burnieToCredit = sdgnrs.resolveRedemptionPeriod(redemptionRoll, flipDay);
                        if (burnieToCredit != 0) {
                            coin.creditFlip(ContractAddresses.SDGNRS, burnieToCredit);
                        }
                    }
                }
                _finalizeLootboxRng(fallbackWord);
                return fallbackWord;
            }
            return 0;
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
        uint48 currentDay
    ) private view returns (uint256 word) {
        uint256 found;
        uint256 combined;
        uint48 searchLimit = currentDay > 30 ? 30 : currentDay;
        for (uint48 searchDay = 1; searchDay < searchLimit; ) {
            uint256 w = rngWordByDay[searchDay];
            if (w != 0) {
                combined = uint256(keccak256(abi.encodePacked(combined, w)));
                unchecked { ++found; }
                if (found == 5) break;
            }
            unchecked {
                ++searchDay;
            }
        }

        return uint256(keccak256(abi.encodePacked(combined, currentDay, block.prevrandao)));
    }

    /*+======================================================================+
      |                    FUTURE PRIZE POOL DRAW                           |
      +======================================================================+
      |  Release a portion of the future prize pool once per level.         |
      |  Normal levels draw 15%, x00 levels skip the draw.                   |
      +======================================================================+*/

    function _nextToFutureBps(
        uint48 elapsed,
        uint24 lvl
    ) internal pure returns (uint16) {
        uint256 lvlBonus = (uint256(lvl % 100) / 10) * 100; // +1% per 10 levels within cycle
        uint256 bps;
        if (elapsed <= 1 days) {
            bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus;
        } else if (elapsed <= 14 days) {
            uint256 elapsedAfterDay = elapsed - 1 days;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus -
                NEXT_TO_FUTURE_BPS_MIN;
            bps = NEXT_TO_FUTURE_BPS_FAST + lvlBonus - (delta * elapsedAfterDay) / 13 days;
        } else if (elapsed <= 28 days) {
            uint256 elapsedAfterMin = elapsed - 14 days;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus -
                NEXT_TO_FUTURE_BPS_MIN;
            bps = NEXT_TO_FUTURE_BPS_MIN + (delta * elapsedAfterMin) / 14 days;
        } else {
            bps =
                NEXT_TO_FUTURE_BPS_FAST +
                lvlBonus +
                ((elapsed - 28 days) / 1 weeks) *
                NEXT_TO_FUTURE_BPS_WEEK_STEP;
        }
        return uint16(bps > 10_000 ? 10_000 : bps);
    }

    function _applyTimeBasedFutureTake(
        uint48 reachedAt,
        uint24 lvl,
        uint256 rngWord
    ) internal {
        uint48 start = levelStartTime + 11 days;
        if (reachedAt < start) reachedAt = start;

        uint256 bps = _nextToFutureBps(reachedAt - start, lvl);
        if (lvl % 10 == 9) bps += NEXT_TO_FUTURE_BPS_X9_BONUS;

        uint256 nextPoolBefore = _getNextPrizePool();
        uint256 futurePoolBefore = _getFuturePrizePool();
        uint256 lastPool = levelPrizePool[lvl - 1];

        // Ratio adjust: ±4% based on future/next ratio (target 2:1)
        uint256 ratioPct = (futurePoolBefore * 100) / nextPoolBefore;
        if (ratioPct < 200) {
            uint256 bump = 200 - ratioPct;
            bps += (bump > 400 ? 400 : bump);
        } else {
            uint256 penalty = ratioPct - 200;
            penalty = penalty > 400 ? 400 : penalty;
            bps = penalty >= bps ? 0 : bps - penalty;
        }

        // Overshoot surcharge: hyperbolic, kicks in when nextPool > 1.25x previous level's target
        if (lastPool != 0) {
            uint256 rBps = (nextPoolBefore * 10_000) / lastPool;
            if (rBps > OVERSHOOT_THRESHOLD_BPS) {
                uint256 excess = rBps - OVERSHOOT_THRESHOLD_BPS;
                uint256 surcharge = (excess * OVERSHOOT_COEFF) / (excess + 10_000);
                if (surcharge > OVERSHOOT_CAP_BPS) surcharge = OVERSHOOT_CAP_BPS;
                bps += surcharge;
            }
        }

        // Step 2: Additive random 0–10% on bps (full 256-bit modulo; functionally uniform)
        bps += rngWord % (ADDITIVE_RANDOM_BPS + 1);

        // Step 3: Compute take from uncapped bps
        uint256 take = (nextPoolBefore * bps) / 10_000;

        // Step 4: ±25% multiplicative variance (triangular: avg of two uniform VRF rolls).
        // roll1 uses bits [64:255], roll2 uses bits [192:255] — overlap at [192:255] is
        // irrelevant because modulo by range (small) makes outputs independent.
        if (take != 0) {
            uint256 halfWidth = (take * NEXT_SKIM_VARIANCE_BPS) / 10_000;
            uint256 minWidth = (nextPoolBefore * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000;
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

        // Step 5: Cap take at 80% of nextPool
        uint256 maxTake = (nextPoolBefore * NEXT_TO_FUTURE_BPS_MAX) / 10_000;
        if (take > maxTake) take = maxTake;

        uint256 insuranceSkim = (nextPoolBefore * INSURANCE_SKIM_BPS) / 10_000;
        _setNextPrizePool(nextPoolBefore - take - insuranceSkim);
        _setFuturePrizePool(futurePoolBefore + take);
        yieldAccumulator += insuranceSkim;
    }

    function _drawDownFuturePrizePool(uint24 lvl) private {
        uint256 reserved;
        if ((lvl % 100) == 0) {
            reserved = 0; // Skip extra future->next move on x00 levels
        } else {
            reserved = (_getFuturePrizePool() * 15) / 100; // 15% on normal levels
        }

        if (reserved != 0) {
            _setFuturePrizePool(_getFuturePrizePool() - reserved);
            _setNextPrizePool(_getNextPrizePool() + reserved);
        }
    }

    /*+======================================================================+
      |                    FUTURE TICKET ACTIVATION                         |
      +======================================================================+
      |  Future ticket rewards are staged per level and activated at the     |
      |  start of the PREVIOUS level's jackpot phase (making them eligible    |
      |  for daily jackpots and early burn rewards).                         |
      +======================================================================+*/

    /// @dev Process a batch of future ticket rewards for the specified level.
    ///      Called during jackpot phase of level N-1 to activate tickets for level N.
    /// @param lvl Target level to activate (typically current level + 1).
    /// @return worked True if any queued entries were processed.
    /// @return finished True if all queued entries for this level are processed.
    /// @return writesUsed Number of SSTORE operations used in this batch.
    function _processFutureTicketBatch(
        uint24 lvl
    ) private returns (bool worked, bool finished, uint32 writesUsed) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.processFutureTicketBatch.selector,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (bool, bool, uint32));
    }

    /// @dev Before daily draws, process ticket queues for near-future levels
    ///      lvl+2..lvl+6. Runs every daily cycle (purchase and jackpot phases)
    ///      so pass-driven tickets are included promptly. Uses existing ticket
    ///      cursor state so work can resume across multiple advanceGame calls.
    /// @param lvl Current level (purchaseLevel or jackpot level).
    /// @return finished True when all target future levels are fully processed.
    function _prepareFutureTickets(
        uint24 lvl
    ) private returns (bool finished) {
        uint24 startLevel = lvl + 2;
        uint24 endLevel = lvl + 6;
        uint24 resumeLevel = ticketLevel;

        // Continue an in-flight future level first to preserve progress.
        if (resumeLevel >= startLevel && resumeLevel <= endLevel) {
            (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
                resumeLevel
            );
            if (worked || !levelFinished) return false;
        }

        // Then probe remaining target levels in order.
        for (uint24 target = startLevel; target <= endLevel; ) {
            if (target != resumeLevel) {
                (bool worked, bool levelFinished, ) = _processFutureTicketBatch(
                    target
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
      |                    TICKET / TOKEN AIRDROP BATCHING                         |
      +======================================================================+
      |  Ticket entries are processed in batches to prevent gas exhaustion.  |
      |  Large purchases are queued and processed across multiple txs.       |
      +======================================================================+*/

    /// @dev Process a batch of current level tickets via jackpot module delegatecall.
    /// @param lvl Current level.
    /// @return worked True if any tickets were processed.
    /// @return finished True if all tickets for this level have been fully processed.
    function _runProcessTicketBatch(
        uint24 lvl
    ) private returns (bool worked, bool finished) {
        uint32 prevCursor = ticketCursor;
        uint24 prevLevel = ticketLevel;
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.processTicketBatch.selector,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        finished = abi.decode(data, (bool));
        worked = (ticketCursor != prevCursor) || (ticketLevel != prevLevel);
    }

    /// @dev Process jackpot→purchase transition housekeeping (vault perpetual tickets + auto-stake).
    ///      Deity pass holders get virtual trait-targeted tickets at jackpot resolution time
    ///      (zero gas cost here). Vault addresses (DGNRS, VAULT) get generic queued tickets.
    /// @param purchaseLevel Current purchase level (level + 1).
    /// @return finished True if all transition work completed this call.
    function _processPhaseTransition(
        uint24 purchaseLevel
    ) private returns (bool finished) {
        // Vault perpetual tickets: 16 generic tickets per level for DGNRS and VAULT
        uint24 targetLevel = purchaseLevel + 99;
        _queueTickets(ContractAddresses.SDGNRS, targetLevel, VAULT_PERPETUAL_TICKETS);
        _queueTickets(ContractAddresses.VAULT, targetLevel, VAULT_PERPETUAL_TICKETS);

        // Auto-stake all non-claimable ETH into stETH for yield generation.
        // Non-blocking: if stETH contract fails, game continues normally.
        _autoStakeExcessEth();

        return true;
    }

    /// @dev Stake all ETH above claimablePool into stETH via Lido.
    ///      Uses try/catch so stETH is never a hard dependency — game
    ///      continues even if Lido is paused or the call reverts.
    function _autoStakeExcessEth() private {
        uint256 ethBal = address(this).balance;
        uint256 reserve = claimablePool;
        if (ethBal <= reserve) return;
        uint256 stakeable = ethBal - reserve;
        try steth.submit{value: stakeable}(address(0)) returns (uint256) {} catch {
            emit StEthStakeFailed(stakeable);
        }
    }

    /// @dev Request new VRF random word from Chainlink.
    ///      Sets RNG lock to prevent manipulation during pending window.
    /// @param isTicketJackpotDay True if this is the last purchase day.
    /// @param lvl Current level.
    function _requestRng(bool isTicketJackpotDay, uint24 lvl) private {
        // Hard revert if Chainlink request fails; this intentionally halts game progress until VRF funding/config is fixed.
        uint256 id = vrfCoordinator.requestRandomWords(
            VRFRandomWordsRequest({
                keyHash: vrfKeyHash,
                subId: vrfSubscriptionId,
                requestConfirmations: VRF_REQUEST_CONFIRMATIONS,
                callbackGasLimit: VRF_CALLBACK_GAS_LIMIT,
                numWords: 1,
                extraArgs: hex"" // Empty for LINK payment (default)
            })
        );
        _finalizeRngRequest(isTicketJackpotDay, lvl, id);
    }

    function _tryRequestRng(
        bool isTicketJackpotDay,
        uint24 lvl
    ) private returns (bool requested) {
        if (
            address(vrfCoordinator) == address(0) ||
            vrfKeyHash == bytes32(0) ||
            vrfSubscriptionId == 0
        ) {
            return false;
        }

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

    function _finalizeRngRequest(
        bool isTicketJackpotDay,
        uint24 lvl,
        uint256 requestId
    ) private {
        uint256 prevRequestId = vrfRequestId;
        bool isRetry = prevRequestId != 0 &&
            rngRequestTime != 0 &&
            rngWordCurrent == 0;
        if (isRetry) {
            // Retry: discard the previous VRF request and remap its reserved lootbox index.
            uint48 reservedIndex = lootboxRngRequestIndexById[prevRequestId];
            if (reservedIndex != 0) {
                delete lootboxRngRequestIndexById[prevRequestId];
                lootboxRngRequestIndexById[requestId] = reservedIndex;
            } else {
                // Do not advance or clear pending on retry.
                lootboxRngRequestIndexById[requestId] = lootboxRngIndex;
            }
        } else {
            // Fresh request: reserve the next lootbox RNG index so new purchases
            // are always assigned to the NEXT RNG.
            _reserveLootboxRngIndex(requestId);
        }

        vrfRequestId = requestId;
        rngWordCurrent = 0;
        rngRequestTime = uint48(block.timestamp);
        rngLockedFlag = true;

        // Close decimator window when RNG requested during lastPurchaseDay at resolution levels (5, 15...85, 100, 105...185, 200, etc.)
        bool decClose = decWindowOpen &&
            isTicketJackpotDay &&
            ((lvl % 10 == 5 && lvl % 100 != 95) || lvl % 100 == 0);
        if (decClose) decWindowOpen = false;

        // Increment level at RNG request time when lastPurchaseDay = true.
        // lvl is already purchaseLevel (= level + 1), so set directly.
        // Only on fresh request - retry would double-increment.
        if (isTicketJackpotDay && !isRetry) {
            level = lvl;

            // Set price for the new level based on intro tiers then 100-level cycle
            if (lvl == 5) {
                price = uint128(0.02 ether);
            } else if (lvl == 10) {
                price = uint128(0.04 ether);
            } else if (lvl == 30) {
                price = uint128(0.08 ether);
            } else if (lvl == 60) {
                price = uint128(0.12 ether);
            } else if (lvl == 90) {
                price = uint128(0.16 ether);
            } else if (lvl == 100) {
                price = uint128(0.24 ether);
            } else if (lvl > 100) {
                uint24 cycleOffset = lvl % 100;
                if (cycleOffset == 1) {
                    price = uint128(0.04 ether);
                } else if (cycleOffset == 30) {
                    price = uint128(0.08 ether);
                } else if (cycleOffset == 60) {
                    price = uint128(0.12 ether);
                } else if (cycleOffset == 90) {
                    price = uint128(0.16 ether);
                } else if (cycleOffset == 0) {
                    price = uint128(0.24 ether);
                }
            }

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
        if (msg.sender != ContractAddresses.ADMIN) revert E();

        address current = address(vrfCoordinator);
        vrfCoordinator = IVRFCoordinator(newCoordinator);
        vrfSubscriptionId = newSubId;
        vrfKeyHash = newKeyHash;

        // Reset RNG state to allow immediate advancement
        rngLockedFlag = false;
        vrfRequestId = 0;
        rngRequestTime = 0;
        rngWordCurrent = 0;
        emit VrfCoordinatorUpdated(current, newCoordinator);
    }

    /// @dev Unlock RNG after processing is complete for the day.
    ///      Resets VRF state and re-enables RNG usage.
    /// @param day Current day index to record.
    function _unlockRng(uint48 day) private {
        dailyIdx = day;
        rngLockedFlag = false;
        rngWordCurrent = 0;
        vrfRequestId = 0;
        rngRequestTime = 0;
    }

    /// @notice Pay BURNIE to nudge the next RNG word by +1.
    /// @dev Cost scales +50% per queued nudge and resets after fulfillment.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    function reverseFlip() external {
        if (rngLockedFlag) revert RngLocked();
        uint256 reversals = totalFlipReversals;
        uint256 cost = _currentNudgeCost(reversals);
        coin.burnCoin(msg.sender, cost);
        uint256 newCount = reversals + 1;
        totalFlipReversals = newCount;
        emit ReverseFlip(msg.sender, newCount, cost);
    }

    /// @dev Reserve the next lootbox RNG index for a VRF request.
    ///      Advances the index immediately so new purchases target the NEXT RNG.
    function _reserveLootboxRngIndex(uint256 requestId) private {
        uint48 index = lootboxRngIndex;
        lootboxRngRequestIndexById[requestId] = index;
        lootboxRngIndex = index + 1;
        // Reset pending counters so new purchases accrue toward the next RNG
        lootboxRngPendingEth = 0;
        lootboxRngPendingBurnie = 0;
    }

    /// @notice Chainlink VRF callback for random word fulfillment.
    /// @dev Access: VRF coordinator only.
    ///      Daily RNG: stores word for advanceGame processing (nudges applied there).
    ///      Mid-day RNG: directly finalizes lootbox RNG, no advanceGame needed.
    ///      SECURITY: Validates requestId and coordinator address.
    /// @param requestId The request ID to match.
    /// @param randomWords Array containing the random word (length 1).
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        if (msg.sender != address(vrfCoordinator)) revert E();
        if (requestId != vrfRequestId || rngWordCurrent != 0) return;

        uint256 word = randomWords[0];
        if (word == 0) word = 1;

        if (rngLockedFlag) {
            // Daily RNG: store for advanceGame processing (nudges applied there)
            rngWordCurrent = word;
        } else {
            // Mid-day RNG: directly finalize lootbox and clear state
            uint48 index = lootboxRngRequestIndexById[requestId];
            lootboxRngWordByIndex[index] = word;
            emit LootboxRngApplied(index, word, requestId);
            vrfRequestId = 0;
            rngRequestTime = 0;
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
    /// @param bonusFlip Whether presale bonus applies to coinflip resolution.
    function _backfillGapDays(
        uint256 vrfWord,
        uint48 startDay,
        uint48 endDay,
        bool bonusFlip
    ) private {
        for (uint48 gapDay = startDay; gapDay < endDay;) {
            uint256 derivedWord = uint256(keccak256(abi.encodePacked(vrfWord, gapDay)));
            if (derivedWord == 0) derivedWord = 1;
            rngWordByDay[gapDay] = derivedWord;
            coinflip.processCoinflipPayouts(bonusFlip, derivedWord, gapDay);
            emit DailyRngApplied(gapDay, derivedWord, 0, derivedWord);
            unchecked { ++gapDay; }
        }
    }

    /// @dev Apply daily RNG nudges, record the word, and emit the finalized word.
    function _applyDailyRng(
        uint48 day,
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

    /// @dev Calculate nudge cost with compounding.
    ///      Base cost is 100 BURNIE, +50% per queued nudge.
    ///      NOTE: O(n) in reversals count - could be optimized with exponentiation for large n,
    ///      but in practice reversals are bounded by game economics.
    /// @param reversals Number of nudges already queued.
    /// @return cost BURNIE cost for the next nudge.
    function _currentNudgeCost(
        uint256 reversals
    ) private pure returns (uint256 cost) {
        cost = RNG_NUDGE_BASE_COST;
        while (reversals != 0) {
            cost = (cost * 15) / 10; // Compound 50% per queued reversal
            unchecked {
                --reversals;
            }
        }
    }

}
