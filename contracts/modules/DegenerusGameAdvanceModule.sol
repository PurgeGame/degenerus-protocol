// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IDegenerusGamepieces} from "../interfaces/IDegenerusGamepieces.sol";
import {IDegenerusCoin} from "../interfaces/IDegenerusCoin.sol";
import {IBurnieCoinflip} from "../interfaces/IBurnieCoinflip.sol";
import {IBurnieLootbox} from "../interfaces/IBurnieLootbox.sol";
import {IDegenerusJackpots} from "../interfaces/IDegenerusJackpots.sol";
import {IDegenerusLazyPass} from "../interfaces/IDegenerusLazyPass.sol";
import {
    IDegenerusGameEndgameModule,
    IDegenerusGameGameOverModule,
    IDegenerusGameJackpotModule,
    IDegenerusGameMintModule
} from "../interfaces/IDegenerusGameModules.sol";
import {IVRFCoordinator, VRFRandomWordsRequest} from "../interfaces/IVRFCoordinator.sol";
import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../ContractAddresses.sol";

/// @notice Delegate-called module for advanceGame and VRF lifecycle handling.
contract DegenerusGameAdvanceModule is DegenerusGameStorage {
    /*+======================================================================+
      |                              ERRORS                                  |
      +======================================================================+*/

    error E();
    error MustMintToday();
    error NotTimeYet();
    error RngNotReady();
    error RngLocked();
    error VrfUpdateNotReady();

    /*+======================================================================+
      |                              EVENTS                                  |
      +======================================================================+*/

    error NotApproved();

    event Advance(uint8 gameState);
    event ReverseFlip(address indexed caller, uint256 totalQueued, uint256 cost);
    event VrfCoordinatorUpdated(address indexed previous, address indexed current);
    event LootBoxPresaleStatus(bool active);

    /*+=======================================================================+
      |                   PRECOMPUTED ADDRESSES (CONSTANT)                    |
      +=======================================================================+*/

    IDegenerusCoin internal constant coin = IDegenerusCoin(ContractAddresses.COIN);
    IBurnieCoinflip internal constant coinflip = IBurnieCoinflip(ContractAddresses.COINFLIP);
    IBurnieLootbox internal constant lootbox = IBurnieLootbox(ContractAddresses.LOOTBOX);
    IDegenerusGamepieces internal constant gamepieces =
        IDegenerusGamepieces(ContractAddresses.GAMEPIECES);
    IDegenerusJackpots internal constant jackpots =
        IDegenerusJackpots(ContractAddresses.JACKPOTS);
    IDegenerusLazyPass internal constant lazyPass =
        IDegenerusLazyPass(ContractAddresses.LAZY_PASS);

    /*+======================================================================+
      |                           CONSTANTS                                  |
      +======================================================================+*/

    uint256 private constant DEPLOY_IDLE_TIMEOUT = (365 days * 5) / 2;
    uint48 private constant DEPLOY_IDLE_TIMEOUT_DAYS = 912;
    uint48 private constant LEVEL_START_SENTINEL = type(uint48).max;
    uint48 private constant JACKPOT_RESET_TIME = 82620;
    uint48 private constant GAMEOVER_RNG_FALLBACK_DELAY = 3 days;
    uint8 private constant JACKPOT_LEVEL_CAP = 10;
    uint8 private constant TICKET_JACKPOT_NONE = 0;
    uint16 private constant TRAIT_ID_TIMEOUT = 420;
    uint32 private constant VRF_CALLBACK_GAS_LIMIT = 200_000;
    uint16 private constant VRF_REQUEST_CONFIRMATIONS = 10;
    uint256 private constant RNG_NUDGE_BASE_COST = 100 ether;
    uint24 private constant DEITY_PASS_TICKET_LEVELS = 100;
    uint32 private constant DEITY_PASS_TICKETS_PER_LEVEL = 4;
    uint8 private constant ETH_PERK_ODDS = 100;
    uint16 private constant NEXT_TO_FUTURE_BPS_FAST = 2000;
    uint16 private constant NEXT_TO_FUTURE_BPS_MIN = 300;
    uint16 private constant NEXT_TO_FUTURE_BPS_WEEK_STEP = 100;
    uint16 private constant NEXT_TO_FUTURE_BPS_X9_BONUS = 200;
    bytes32 private constant NEXT_SKIM_VARIANCE_TAG =
        keccak256("next-skim-variance");
    uint16 private constant NEXT_SKIM_VARIANCE_BPS = 1000;
    uint16 private constant NEXT_SKIM_VARIANCE_MIN_BPS = 1000;

    /// @dev Minimum lootbox pending ETH to allow manual RNG roll (ETH lootboxes)
    uint256 private constant MANUAL_RNG_MIN_LOOTBOX_ETH = 1 ether / ContractAddresses.COST_DIVISOR;
    /// @dev Minimum combined pending BURNIE to allow manual RNG roll (BURNIE lootboxes + turboflips)
    uint256 private constant MANUAL_RNG_MIN_BURNIE_PENDING = 100_000 ether;
    /// @dev Work bounty for ticket processing (500 BURNIE flip credit)
    uint256 private constant TICKET_WORK_BOUNTY = PRICE_COIN_UNIT >> 1;

    /*+======================================================================+
      |                    MINT PACKED BIT LAYOUT                            |
      +======================================================================+*/

    uint256 private constant MINT_MASK_24 = (uint256(1) << 24) - 1;
    uint256 private constant MINT_MASK_32 = (uint256(1) << 32) - 1;
    uint256 private constant ETH_DAY_SHIFT = 72;
    uint256 private constant ETH_FROZEN_UNTIL_LEVEL_SHIFT = 128;

    ///      3. Process dormant cleanup if in setup state
    ///      4. Gate on RNG readiness (request new VRF if needed)
    ///      5. Process ticket batches
    ///      6. Execute state-specific logic:
    ///         - SETUP: Run endgame settlement and queue prep before advancing to PURCHASE
    ///         - PURCHASE/BURN: Process phase-specific logic
    ///      7. Credit caller with BURNIE reward (if cap == 0)
    ///
    ///      SECURITY:
    ///      - Liveness guards prevent abandoned game lockup
    ///      - Daily gate prevents non-participants from advancing
    ///      - RNG gating ensures fairness (no manipulation during VRF window)
    ///      - Batched processing prevents DoS from large queues
    ///
    /// @param cap Gas budget override for batched operations.
    ///            0 = standard flow with BURNIE reward.
    ///            >0 = emergency unstuck mode (no BURNIE reward).
    function advanceGame(uint32 cap) external {
        address caller = msg.sender;
        uint48 ts = uint48(block.timestamp);
        // Day index is relative to deploy time (day 1 = deploy day).
        uint48 day = _currentDayIndex();
        IDegenerusCoin coinContract = coin;
        uint48 lst = levelStartTime;
        bool gameOver;
        uint8 _gameState = gameState;
        uint24 lvl = level;

        // === GAMEOVER CHECK ===
        if (_gameState == GAME_STATE_GAMEOVER) {
            // Check for final sweep (1 month after gameover)
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_GAMEOVER_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameGameOverModule.handleFinalSweep.selector
                    )
                );
            if (!ok) _revertDelegate(data);
            return;
        }

        // === LIVENESS GUARDS ===
        // Prevent permanent lockup if game is abandoned
        if (
            lvl == 1 &&
            lst == LEVEL_START_SENTINEL &&
            day > DEPLOY_IDLE_TIMEOUT_DAYS
        ) {
            // Deployed but never started for 2.5 years - game abandoned
            gameOver = true;
        } else if (
            lst != LEVEL_START_SENTINEL &&
            ts - 365 days > lst &&
            _gameState != GAME_STATE_GAMEOVER
        ) {
            // Game inactive for 365 days - trigger game over
            gameOver = true;
        }
        if (gameOver) {
            if (rngWordByDay[dailyIdx] == 0) {
                bool lastPurchaseFlag = (_gameState == GAME_STATE_PURCHASE) &&
                    lastPurchaseDay;
                uint256 rngWord = _gameOverEntropy(day, lvl, lastPurchaseFlag);
                if (rngWord == 1 || rngWord == 0) return;
                _unlockRng(day);
            }
            // Sweep all funds to the vault for final distribution
            (bool ok, bytes memory data) = ContractAddresses
                .GAME_GAMEOVER_MODULE
                .delegatecall(
                    abi.encodeWithSelector(
                        IDegenerusGameGameOverModule
                            .handleGameOverDrain
                            .selector,
                        dailyIdx
                    )
                );
            if (!ok) _revertDelegate(data);
            return;
        }

        bool lastPurchase = (_gameState == GAME_STATE_PURCHASE) &&
            lastPurchaseDay;

        // === MANUAL LOOTBOX RNG ===
        // Allow manual RNG roll if there's >1 ETH of pending lootbox OR >100k BURNIE pending
        // (BURNIE = lootboxes + turboflips combined)
        // Bypasses daily gate when threshold met - the reward is getting RNG to gamble on
        uint256 burniePending = lootbox.lootboxRngPendingBurnieAmount() + coin.turboFlipPendingBurnieAmount();
        bool ethThresholdMet = lootboxRngPendingEth >= MANUAL_RNG_MIN_LOOTBOX_ETH;
        bool burnieThresholdMet = burniePending >= MANUAL_RNG_MIN_BURNIE_PENDING;

        if (ethThresholdMet || burnieThresholdMet) {
            // Check if we can skip daily gate for this manual roll
            if (day == dailyIdx) {
                // Same day - request manual lootbox RNG without crossing daily boundary
                // Tickets will be processed AFTER RNG arrives (for RNG integrity)
                bool requested = _tryRequestLootboxRng();
                if (requested) {
                    return; // Exit early - manual RNG requested (reward is getting RNG)
                }
            }
        }

        // Single-iteration do-while pattern allows structured breaks for early exit
        do {
            // === DAILY GATE ===
            // Standard flow requires caller to have minted today (prevents gaming by non-participants)
            // Skip for CREATOR address to allow maintenance advances
            if (cap == 0 && caller != ContractAddresses.CREATOR) {
                uint32 gateIdx = uint32(dailyIdx);
                if (gateIdx != 0) {
                    uint256 mintData = mintPacked_[caller];
                    uint32 lastEthDay = uint32(
                        (mintData >> ETH_DAY_SHIFT) & MINT_MASK_32
                    );
                    // Allow mints from current day or previous day
                    if (lastEthDay + 1 < gateIdx) {
                        uint24 frozenUntilLevel = uint24(
                            (mintData >> ETH_FROZEN_UNTIL_LEVEL_SHIFT) &
                                MINT_MASK_24
                        );
                        bool hasLazyPass = frozenUntilLevel > lvl ||
                            deityPassCount[caller] != 0;
                        if (!hasLazyPass) revert MustMintToday();
                    }
                }
            }

            // Release a portion of the future prize pool once per level.
            _drawDownFuturePrizePool(lvl);

            // === RNG GATING ===
            // Either use existing VRF word or request new one. Returns 1 if request just made.
            uint256 rngWord = rngAndTimeGate(day, lvl, lastPurchase, caller, cap);
            if (rngWord == 1) {
                break; // VRF requested - must wait for fulfillment
            }

            // === DEITY PASS REFRESH ===
            // Queue perma-pass tickets in batches before any ticket processing.
            (bool refreshWorked, bool refreshFinished) = _runDeityPassRefreshBatch(
                cap
            );
            if (refreshWorked || !refreshFinished) break;

            // === LAZY PASS AUTO-ACTIVATION ===
            // Activate lazy passes at the first ticket level before processing current tickets.
            if (
                _gameState == GAME_STATE_PURCHASE &&
                lastPurchaseDay &&
                !levelJackpotPaid &&
                (lvl % 10 == 1)
            ) {
                (bool lazyWorked, bool lazyFinished) = lazyPass
                    .processAutoActivation(cap, lvl);
                if (lazyWorked || !lazyFinished) break;
            }

            // === CURRENT LEVEL TICKET PROCESSING ===
            // Process tickets for current level in batches (prevents gas exhaustion).
            // Future level tickets are processed at burn phase start.
            (bool ticketWorked, bool ticketsFinished) = _runProcessTicketBatch(
                cap,
                lvl
            );
            if (ticketWorked || !ticketsFinished) break;

            // +================================================================+
            // |                    STATE 1: SETUP                              |
            // |  Endgame settlement phase after level completion.              |
            // |  • Open decimator window at specific level positions           |
            // |  • Run endgame module for reward jackpots (BAF/Decimator)     |
            // |  • Exterminator payout handled during burn phase, not here    |
            // |  • Transitions to PURCHASE after settlement and queue prep    |
            // +================================================================+
            if (_gameState == GAME_STATE_SETUP) {
                // Decimator window opens at levels ending in 5 (except 95)
                // Note: Level 99 window opens during State 2 for the level 100 special
                if (lvl % 10 == 5 && lvl % 100 != 95) {
                    decWindowOpen = true;
                }

                // Run endgame settlement (reward jackpots/affiliate trophy).
                // Exterminator payouts are handled during the burn phase.
                _runEndgameModule(lvl, rngWord);

                // Process near-future ticket queues (next 4 levels) before starting new level
                // Uses same gas-conscious batch processing as normal ticket activation
                // Processes multiple levels in one call if each completes quickly
                // Start cursor at 1 if not yet started
                if (nearFutureLevelCursor == 0) {
                    nearFutureLevelCursor = 1;
                }

                // Process levels until we hit one that's not finished or complete all 4
                // This allows multiple small queues to be processed in one call
                while (nearFutureLevelCursor <= 4) {
                    uint24 targetLevel = lvl + nearFutureLevelCursor;
                    (, bool finished) = _processFutureTicketBatch(cap, targetLevel);

                    // If this level isn't finished, stay in State 1 for next advanceGame call
                    // (we're in the middle of processing this level's queue)
                    if (!finished) {
                        break;
                    }

                    // This level is complete - move to next level
                    // (continue processing, allowing multiple levels per call if queues are small)
                    unchecked {
                        ++nearFutureLevelCursor;
                    }
                }

                // If not all 4 levels processed, stay in State 1
                if (nearFutureLevelCursor <= 4) {
                    break;
                }

                // All 4 near-future levels processed - reset cursor and transition to State 2
                nearFutureLevelCursor = 0;
                bool firstLevelStart = (levelStartTime == LEVEL_START_SENTINEL);
                gameState = GAME_STATE_PURCHASE;
                levelStartTime = uint48(block.timestamp);
                purchaseTargetReachedTime = 0;
                lastPurchaseDay = false;
                levelJackpotPaid = false;
                levelJackpotLootboxPaid = false;
                if (firstLevelStart) {
                    _releaseDeityPassEscrow();
                }
                break;
            }

            // +================================================================+
            // |                    STATE 2: PURCHASE / AIRDROP                 |
            // |  Mint phase where players purchase gamepieces and receive airdrops.  |
            // |  • Pay daily jackpot until prize pool target is met            |
            // |  • Pay level jackpot once target is met                        |
            // |  • Process pending mint batches                                |
            // |  • Rebuild trait counts for new level                          |
            // |  • Transition to State 3 when all processing complete          |
            // +================================================================+
            if (_gameState == GAME_STATE_PURCHASE) {
                if (ticketJackpotType != TICKET_JACKPOT_NONE) {
                    payTicketJackpot(lvl, rngWord);
                    _unlockRng(day);
                    break;
                }
                // --- Pre-target: daily ContractAddresses.JACKPOTS while building up prize pool ---
                if (!lastPurchaseDay) {
                    payDailyJackpot(false, lvl, rngWord);
                    _payDailyCoinJackpot(lvl, rngWord); // Award BURNIE to ticket holders
                    // Check if prize pool target is now met
                    if (nextPrizePool >= lastPrizePool) {
                        lastPurchaseDay = true;
                        lastPurchaseDayFlipTotal = 0;
                        purchaseTargetReachedTime = uint48(block.timestamp);
                        // Time-based split: route a portion of nextPrizePool into future reserve.
                        _applyTimeBasedFutureTake(purchaseTargetReachedTime, lvl, rngWord);
                    }
                    if (ticketJackpotType != TICKET_JACKPOT_NONE) {
                        break; // ticket jackpot queued, will process next tick
                    }
                    _unlockRng(day);
                    break;
                }

                // --- Target met: pay level jackpot ---
                if (!levelJackpotPaid) {
                    // Level 100 multiples get special decimator/BAF jackpot
                    if (lvl % 100 == 0) {
                        if (!_runDecimatorHundredJackpot(lvl, rngWord)) {
                            break; // Keep working this jackpot slice before moving on
                        }
                    }

                    // === PROCESS NEXT LEVEL TICKETS (from lootboxes) ===
                    // Activate lootbox tickets for next level before level jackpot.
                    // This makes them eligible for early-bird jackpots and ensures
                    // they're ready at burn phase start.
                    uint24 nextLevel = lvl + 1;
                    (
                        bool futureWorked,
                        bool futureFinished
                    ) = _processFutureTicketBatch(cap, nextLevel);
                    if (futureWorked || !futureFinished) break;

                    // === PHASE 1: EARLY BIRD + LEVEL LOOTBOX JACKPOT ===
                    // Combined into one transaction to stay under 15M gas (11-14M total).
                    if (!levelJackpotLootboxPaid) {
                        // Reward lootbox ticket holders with loot boxes from 3% reward + 3% future pool.
                        _payEarlyBirdLootboxJackpot(nextLevel, rngWord);

                        // Calculate and pay level jackpot lootbox distribution
                        uint256 levelJackpotWei = _calcPrizePoolForLevelJackpot(
                            lvl,
                            rngWord
                        );
                        _payLevelJackpotLootbox(lvl, rngWord, levelJackpotWei);
                        levelJackpotLootboxPaid = true;
                        break;
                    }

                    // === PHASE 2: LEVEL ETH JACKPOT ===
                    // Separate transaction for ETH distribution (6-10M gas).
                    _payLevelJackpotEth(lvl, rngWord);
                    _rewardTopAffiliate(lvl);
                    {
                        (
                            uint32 purchaseCountPreJackpot,
                            uint32 purchaseCountPhaseJackpot
                        ) = gamepieces.purchaseCounts();
                        uint256 purchaseCountTotalJackpot =
                            uint256(purchaseCountPreJackpot) +
                            uint256(purchaseCountPhaseJackpot);
                        if (purchaseCountTotalJackpot > type(uint32).max)
                            revert E();
                        uint32 purchaseCountRawJackpot = uint32(
                            purchaseCountTotalJackpot
                        );
                        if (purchaseCountRawJackpot == 0) {
                            perkExpectedCount = 0;
                        } else {
                            uint32 expected = purchaseCountRawJackpot /
                                ETH_PERK_ODDS;
                            if (expected == 0) expected = 1;
                            if (expected > type(uint16).max) {
                                perkExpectedCount = type(uint16).max;
                            } else {
                                perkExpectedCount = uint16(expected);
                            }
                        }
                    }
                    levelJackpotPaid = true;
                    break;
                }

                // --- Process pending gamepiece mints ---
                (uint32 purchaseCountPre, uint32 purchaseCountPhase) = gamepieces
                    .purchaseCounts();
                uint256 purchaseCountTotal = uint256(purchaseCountPre) +
                    uint256(purchaseCountPhase);
                if (purchaseCountTotal > type(uint32).max) revert E();
                uint32 purchaseCountRaw = uint32(purchaseCountTotal);
                if (airdropMultiplier == 0) {
                    airdropMultiplier = _calculateAirdropMultiplierModule(
                        purchaseCountPre,
                        purchaseCountPhase,
                        lvl
                    );
                }
                if (!traitCountsSeedQueued) {
                    uint32 multiplier_ = airdropMultiplier;
                    if (!gamepieces.processPendingMints(cap, multiplier_, rngWord)) {
                        break; // More mints to process
                    }
                    if (purchaseCountRaw != 0) {
                        traitCountsSeedQueued = true;
                        traitRebuildCursor = 0;
                        break; // Defer trait rebuild to next advanceGame call.
                    }
                }

                // --- Rebuild trait counts for new level ---
                if (traitCountsSeedQueued) {
                    uint32 targetCount = _purchaseTargetCountFromRawModule(
                        purchaseCountPre,
                        purchaseCountPhase
                    );
                    if (traitRebuildCursor < targetCount) {
                        uint256 baseTokenId = gamepieces.currentBaseTokenId();
                        _rebuildTraitCountsModule(
                            cap,
                            targetCount,
                            baseTokenId
                        );
                        break; // More trait counts to rebuild
                    }
                    _seedTraitCounts(); // Copy traitRemaining to traitStartRemaining
                    traitCountsSeedQueued = false;
                }

                // --- Auto-end presale when purchase phase ends ---
                if (lootboxPresaleActive) {
                    lootboxPresaleActive = false;
                    emit LootBoxPresaleStatus(false);
                }

                // --- Transition to State 3 (DEGENERUS) ---
                traitRebuildCursor = 0;
                airdropMultiplier = 0;
                earlyBurnPercent = 0;
                gameState = GAME_STATE_BURN;
                levelJackpotPaid = false;
                levelJackpotLootboxPaid = false;
                lastPurchaseDay = false;
                if (lvl % 100 == 99) decWindowOpen = true;
                _unlockRng(day); // Open RNG after level jackpot is finalized
                break;
            }

            // +================================================================+
            // |                    STATE 3: DEGENERUS (BURN)                   |
            // |  Active burn phase where players burn gamepieces for jackpot tickets.|
            // |  • Next level tickets already activated at end of purchase phase|
            // |  • Pay daily jackpot each day                                  |
            // |  • Level ends after jackpot cap (10 days)                      |
            // |  • Extermination marks a winner but does not end the level     |
            // |  • Transition to State 1 on level end                          |
            // +================================================================+
            if (_gameState == GAME_STATE_BURN) {
                // === FUTURE MINT ACTIVATION (if needed) ===
                // Future mints for next level are already processed at end of purchase phase.
                // This is a safety check in case there are any remaining tickets.
                // Normally this will be a no-op (queue already empty).
                uint24 nextLevel = lvl + 1;
                (
                    bool futureWorked,
                    bool futureFinished
                ) = _processFutureTicketBatch(cap, nextLevel);
                if (futureWorked || !futureFinished) break;

                _payExterminatorOnJackpot(lvl, rngWord);

                if (ticketJackpotType != TICKET_JACKPOT_NONE) {
                    payTicketJackpot(lvl, rngWord);
                    // Check timeout on-the-fly (jackpotCounter was incremented before pending was set)
                    if (jackpotCounter >= JACKPOT_LEVEL_CAP) {
                        _endLevel();
                        break;
                    }
                    _unlockRng(day);
                    break;
                }

                payDailyJackpot(true, lvl, rngWord);
                _payDailyCoinJackpot(lvl, rngWord); // Award BURNIE to ticket holders
                if (ticketJackpotType != TICKET_JACKPOT_NONE) {
                    break; // ticket jackpot queued, will process next tick
                }
                // Check for timeout end (10 ContractAddresses.JACKPOTS paid)
                if (jackpotCounter >= JACKPOT_LEVEL_CAP) {
                    _endLevel(); // Force level end
                    break;
                }
                _unlockRng(day);
                break;
            }
        } while (false);

        // Emit state change event for indexers
        emit Advance(gameState);

        // Credit caller with BURNIE reward for advancing (skip emergency cap mode)
        if (cap == 0) {
            coinContract.creditFlip(caller, PRICE_COIN_UNIT >> 1);
        }
    }

    /*+========================================================================================+
      |                    ADMIN VRF FUNCTIONS                                                 |
      +========================================================================================+
      |  One-time VRF setup function called by ContractAddresses.ADMIN during deployment phase.|
      +========================================================================================+*/

    /// @notice One-time wiring of VRF config from the VRF ContractAddresses.ADMIN contract.
    /// @dev Access: ContractAddresses.ADMIN only. Idempotent after first wire (repeats must match).
    ///      SECURITY: Once wired, config cannot be changed except via emergency rotation.
    /// @param coordinator_ Chainlink VRF V2.5 coordinator address.
    /// @param subId VRF subscription ID for LINK billing.
    function wireVrf(
        address coordinator_,
        uint256 subId,
        bytes32 keyHash_
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();

        // Idempotent once wired: allow only no-op repeats with identical config.
        if (vrfSubscriptionId != 0) {
            if (subId != vrfSubscriptionId) revert E();
            if (coordinator_ != address(vrfCoordinator)) revert E();
            if (keyHash_ != vrfKeyHash) revert E();
            return;
        }

        if (coordinator_ == address(0) || keyHash_ == bytes32(0) || subId == 0)
            revert E();

        address current = address(vrfCoordinator);
        vrfCoordinator = IVRFCoordinator(coordinator_);
        vrfSubscriptionId = subId;
        vrfKeyHash = keyHash_;
        emit VrfCoordinatorUpdated(current, coordinator_);
    }

    function _requireApproved(address player) private view {
        if (msg.sender != player && !operatorApprovals[player][msg.sender]) {
            revert NotApproved();
        }
    }

    /*+======================================================================+
      |                           LEVEL END                                 |
      +======================================================================+*/
    function _endLevel() private {
        uint24 levelSnapshot = level;
        uint24 completedLevel = levelSnapshot;
        uint256 prizePoolSnapshot = lastPrizePool;
        gameState = GAME_STATE_SETUP;
        lastPurchaseDayFlipTotalPrev = lastPurchaseDayFlipTotal;
        lastPurchaseDayFlipTotal = 0;

        uint16 exTrait = currentExterminatedTrait;
        if (exTrait < 256) {
            lastExterminatedTrait = exTrait;
        } else {
            lastExterminatedTrait = TRAIT_ID_TIMEOUT;
            _setExterminatorForLevel(levelSnapshot, address(0));
        }

        currentExterminatedTrait = TRAIT_ID_TIMEOUT;
        exterminationPaidThisLevel = false;
        exterminationInvertFlag = false;

        uint256 leftover = currentPrizePool;
        if (leftover != 0) {
            nextPrizePool += leftover;
            currentPrizePool = 0;
        }

        affiliateDgnrsPrizePool[levelSnapshot] = prizePoolSnapshot;

        if (levelSnapshot % 100 == 0) {
            lastPrizePool = futurePrizePool;
            price = 0.05 ether;
        }

        unchecked {
            levelSnapshot++;
            level++;
        }

        _scheduleDeityPassRefresh(completedLevel);

        if (levelSnapshot % 100 == 0) {
            whalePassClaims[ContractAddresses.DGNRS] += 1;
        }

        perkExpectedCount = 0;

        traitRebuildCursor = 0;
        uint8 jackpotCounterSnapshot = jackpotCounter;
        lastLevelJackpotCount = jackpotCounterSnapshot;
        jackpotCounter = 0;
        // Reset daily burn counters so the next level's ContractAddresses.JACKPOTS start fresh.
        if (jackpotCounterSnapshot < JACKPOT_LEVEL_CAP) {
            _clearDailyBurnCount();
        }

        uint256 cycleOffset = levelSnapshot % 100; // position within the 100-level schedule (0 == 100)

        if (cycleOffset == 10) {
            price = 0.05 ether;
        } else if (cycleOffset == 40) {
            price = 0.1 ether;
        } else if (cycleOffset == 80) {
            price = 0.125 ether;
        } else if (cycleOffset == 0) {
            price = 0.25 ether;
        }

        gamepieces.advanceBase(); // prepare dormant cleanup; base advances during batches
    }

    function _scheduleDeityPassRefresh(uint24 completedLevel) private {
        if (deityPassOwners.length == 0) {
            return;
        }

        if (deityPassRefreshStartLevel != 0) {
            return;
        }

        unchecked {
            deityPassRefreshStartLevel = completedLevel + DEITY_PASS_TICKET_LEVELS;
        }
        deityPassRefreshOwnerCursor = 0;
    }

    function _releaseDeityPassEscrow() private {
        uint256 escrow = deityPassEscrow;
        if (escrow == 0) return;

        deityPassEscrow = 0;
        // Level 1 distribution: 50% next, 25% reward, 25% future (reward tracked in futurePrizePool).
        uint256 nextShare = (escrow * 5000) / 10_000;
        uint256 rewardShare = (escrow * 2500) / 10_000;
        uint256 futureShare;
        unchecked {
            futureShare = escrow - nextShare - rewardShare;
        }

        nextPrizePool += nextShare;
        futurePrizePool += rewardShare;
        futurePrizePool += futureShare;
    }

    function _runDeityPassRefreshBatch(
        uint32 ownerCap
    ) private returns (bool worked, bool finished) {
        uint24 targetLevel = deityPassRefreshStartLevel;
        if (targetLevel == 0) {
            return (false, true);
        }

        uint256 ownerCount = deityPassOwners.length;
        if (ownerCount == 0) {
            deityPassRefreshStartLevel = 0;
            deityPassRefreshOwnerCursor = 0;
            return (false, true);
        }

        uint32 cursor = deityPassRefreshOwnerCursor;
        if (cursor >= ownerCount) {
            deityPassRefreshStartLevel = 0;
            deityPassRefreshOwnerCursor = 0;
            return (false, true);
        }

        uint32 batch;
        if (ownerCap == 0) {
            uint256 remaining = ownerCount - cursor;
            batch = remaining > type(uint32).max
                ? type(uint32).max
                : uint32(remaining);
        } else {
            batch = ownerCap;
        }
        if (batch == 0) {
            batch = 1;
        }

        uint256 end = uint256(cursor) + uint256(batch);
        if (end > ownerCount) {
            end = ownerCount;
        }

        for (uint256 i = cursor; i < end; ) {
            address owner = deityPassOwners[i];
            uint16 passCount = deityPassCount[owner];
            if (passCount != 0) {
                uint32 ticketsPerLevel = uint32(passCount) *
                    DEITY_PASS_TICKETS_PER_LEVEL;
                _queueTickets(owner, targetLevel, ticketsPerLevel);
            }
            unchecked {
                ++i;
            }
        }

        worked = end > cursor;
        if (end >= ownerCount) {
            deityPassRefreshStartLevel = 0;
            deityPassRefreshOwnerCursor = 0;
            finished = true;
        } else {
            deityPassRefreshOwnerCursor = uint32(end);
            finished = false;
        }
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

    /// @dev Delegatecall into the endgame module to resolve settlement paths.
    ///      Handles: payouts, wipes, endgame distribution, and ContractAddresses.JACKPOTS.
    /// @param lvl Current level snapshot.
    /// @param rngWord VRF random word for RNG-dependent operations.
    function _runEndgameModule(uint24 lvl, uint256 rngWord) internal {
        // Endgame settlement logic lives in DegenerusGameEndgameModule (delegatecall keeps state on this contract).
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ENDGAME_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameEndgameModule.finalizeEndgame.selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Reward the top affiliate for a level during the level jackpot.
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

    /// @dev Pay exterminator on the first jackpot after extermination.
    ///      Delegates to endgame module for payout/trophy logic.
    function _payExterminatorOnJackpot(uint24 lvl, uint256 rngWord) private {
        if (
            currentExterminatedTrait == TRAIT_ID_TIMEOUT ||
            exterminationPaidThisLevel
        ) {
            return;
        }
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_ENDGAME_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameEndgameModule.payExterminatorOnJackpot.selector,
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

    /// @dev Calculate airdrop multiplier via mint module delegatecall.
    ///      Multiplier determines bonus gamepieces in airdrops.
    /// @param prePurchaseCount Raw count before purchase phase (eligible for multiplier).
    /// @param purchasePhaseCount Raw count during purchase phase (not multiplied).
    /// @param lvl Current level.
    /// @return Multiplier value for airdrop calculations.
    function _calculateAirdropMultiplierModule(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount,
        uint24 lvl
    ) private returns (uint32) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule
                        .calculateAirdropMultiplier
                        .selector,
                    prePurchaseCount,
                    purchasePhaseCount,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint32));
    }

    /// @dev Convert raw purchase count to target count via mint module.
    /// @param prePurchaseCount Raw count before purchase phase (eligible for multiplier).
    /// @param purchasePhaseCount Raw count during purchase phase (not multiplied).
    /// @return Target count for trait rebuild operations.
    function _purchaseTargetCountFromRawModule(
        uint32 prePurchaseCount,
        uint32 purchasePhaseCount
    ) private returns (uint32) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule
                        .purchaseTargetCountFromRaw
                        .selector,
                    prePurchaseCount,
                    purchasePhaseCount
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint32));
    }

    /// @dev Rebuild trait counts via mint module delegatecall.
    ///      Processes tokens in batches to avoid gas exhaustion.
    /// @param tokenBudget Maximum tokens to process this call.
    /// @param target Total tokens to process.
    /// @param baseTokenId Starting token ID for this level.
    function _rebuildTraitCountsModule(
        uint32 tokenBudget,
        uint32 target,
        uint256 baseTokenId
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.rebuildTraitCounts.selector,
                    tokenBudget,
                    target,
                    baseTokenId
                )
            );
        if (!ok) _revertDelegate(data);
    }

    function _runDecimatorHundredJackpot(
        uint24 lvl,
        uint256 rngWord
    ) internal returns (bool finished) {
        // Decimator/BAF ContractAddresses.JACKPOTS are promotional side-games; odds/payouts live in the ContractAddresses.JACKPOTS module.
        if (!decimatorHundredReady) {
            uint256 basePool = futurePrizePool;
            uint256 decPool = (basePool * 30) / 100;
            uint256 bafPool = (basePool * 10) / 100;
            decimatorHundredPool = decPool;
            bafHundredPool = bafPool;
            futurePrizePool -= decPool + bafPool;
            decimatorHundredReady = true;
        }

        uint256 pool = decimatorHundredPool;

        uint256 returnWei = jackpots.runDecimatorJackpot(pool, lvl, rngWord);
        uint256 netSpend = pool - returnWei;
        if (netSpend != 0) {
            // Reserve the full decimator pool in `claimablePool` immediately; player credits occur on claim.
            claimablePool += netSpend;
        }

        if (returnWei != 0) {
            futurePrizePool += returnWei;
        }
        decimatorHundredPool = 0;
        decimatorHundredReady = false;
        return true;
    }

    /// @dev Pay level jackpot lootbox distribution (phase 1) via jackpot module delegatecall.
    ///      Combined with early bird jackpot to stay under 15M gas.
    /// @param lvl Current level.
    /// @param rngWord VRF random word.
    /// @param effectiveWei Total prize pool amount.
    function _payLevelJackpotLootbox(
        uint24 lvl,
        uint256 rngWord,
        uint256 effectiveWei
    ) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payLevelJackpotLootbox.selector,
                    lvl,
                    rngWord,
                    effectiveWei
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay level jackpot ETH distribution (phase 2) via jackpot module delegatecall.
    /// @param lvl Current level.
    /// @param rngWord VRF random word.
    function _payLevelJackpotEth(uint24 lvl, uint256 rngWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payLevelJackpotEth.selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Calculate prize pool for level jackpot via jackpot module delegatecall.
    ///      Factors in stETH balance and other pool considerations.
    /// @param lvl Current level.
    /// @param rngWord VRF random word.
    /// @return effectiveWei The prize pool amount available for jackpot.
    function _calcPrizePoolForLevelJackpot(
        uint24 lvl,
        uint256 rngWord
    ) internal returns (uint256 effectiveWei) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule
                        .calcPrizePoolForLevelJackpot
                        .selector,
                    lvl,
                    rngWord
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (uint256));
    }

    /// @dev Pay daily jackpot via jackpot module delegatecall.
    ///      Called each day during States 2 and 3.
    /// @param isDaily True if degenerus phase (State 3), false if purchase phase (State 2).
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

    /// @dev Pay daily BURNIE jackpot via jackpot module delegatecall.
    ///      Called each day during States 2 and 3 in its own transaction.
    ///      Awards 0.5% of lastPrizePool in BURNIE to current and future ticket holders.
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

    /// @dev Pay the queued ticket jackpot (daily or purchase) via jackpot module delegatecall.
    /// @param lvl Current level.
    /// @param randWord VRF random word for winner selection.
    function payTicketJackpot(uint24 lvl, uint256 randWord) internal {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.payTicketJackpot.selector,
                    lvl,
                    randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    /// @dev Pay early bird lootbox jackpot to next-level ticket holders (from lootboxes).
    ///      Takes a slice from the unified future pool, awards loot boxes.
    ///      Called after next-level tickets are activated at end of purchase phase.
    /// @param lvl The level whose tickets were just activated.
    /// @param randWord VRF random word for winner selection.
    function _payEarlyBirdLootboxJackpot(uint24 lvl, uint256 randWord) private {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule
                        .payEarlyBirdLootboxJackpot
                        .selector,
                    lvl,
                    randWord
                )
            );
        if (!ok) _revertDelegate(data);
    }

    function rngAndTimeGate(
        uint48 day,
        uint24 lvl,
        bool isTicketJackpotDay,
        address caller,
        uint32 cap
    ) internal returns (uint256 word) {
        if (day == dailyIdx) revert NotTimeYet();

        uint256 currentWord = rngFulfilled ? rngWordCurrent : 0;

        if (currentWord == 0 && rngLockedFlag && rngRequestTime != 0) {
            uint48 elapsed = uint48(block.timestamp) - rngRequestTime;
            if (elapsed >= 18 hours) {
                _requestRng(gameState, isTicketJackpotDay, lvl);
                return 1;
            }
        }

        if (currentWord == 0) {
            if (rngLockedFlag) revert RngNotReady();
            // Request RNG; tickets will be processed AFTER RNG arrives (for RNG integrity)
            _requestRng(gameState, isTicketJackpotDay, lvl);
            return 1;
        }

        if (!rngLockedFlag) {
            // Stale entropy from previous cycle; request a fresh word.
            // Tickets will be processed AFTER RNG arrives (for RNG integrity)
            _requestRng(gameState, isTicketJackpotDay, lvl);
            return 1;
        }

        // Record the word once per day; using a zero sentinel since VRF returning 0 is effectively impossible.
        if (rngWordByDay[day] == 0) {
            rngWordByDay[day] = currentWord;

            // === PROCESS COINFLIPS FIRST (cheap, can happen immediately) ===
            bool bonusFlip = isTicketJackpotDay || lootboxPresaleActive;
            coinflip.processCoinflipPayouts(bonusFlip, currentWord, day);
            coinflip.recordAfKingRng(currentWord, bonusFlip); // afKing gets bonus on special days
            _finalizeLootboxRngFromDaily(currentWord);

            // === PROCESS ALL TICKETS BEFORE JACKPOTS ===
            // Tickets need RNG word, so process them after coinflips (before jackpots)
            // This awards 500 BURNIE work bounty to caller
            bool allFinished = _processAllTicketsBeforeUnlock(caller, lvl, cap);
            if (!allFinished) {
                // Not all tickets processed yet - must continue next call
                // Note: RNG word is already recorded, so next call will skip this block
                return currentWord;
            }
        }
        return currentWord;
    }

    function _finalizeLootboxRngFromDaily(uint256 rngWord) private {
        if (lootboxRngPendingEth == 0) return;
        uint48 index = lootboxRngIndex;
        if (lootboxRngWordByIndex[index] == 0) {
            lootboxRngWordByIndex[index] = rngWord;
            // Resolve lootbox RNG via standalone contract
            lootbox.resolveLootboxRng(rngWord, index);
            // Note: recordAfKingRng already called for this RNG word in rngAndTimeGate
        }
        lootboxRngIndex = index + 1;
        lootboxRngPendingEth = 0;
    }

    /// @dev Game-over RNG gate with fallback for stalled VRF.
    ///      After 3-day timeout, uses earliest historical VRF word as fallback (more secure
    ///      than blockhash since it's already verified on-chain and cannot be manipulated).
    /// @return word RNG word, 1 if request sent, or 0 if waiting on fallback.
    function _gameOverEntropy(
        uint48 day,
        uint24 lvl,
        bool isTicketJackpotDay
    ) private returns (uint256 word) {
        if (rngWordByDay[day] != 0) return rngWordByDay[day];

        uint256 currentWord = rngFulfilled ? rngWordCurrent : 0;
        if (currentWord != 0 && rngLockedFlag) {
            rngWordByDay[day] = currentWord;
            if (lvl != 0) {
                coinflip.processCoinflipPayouts(isTicketJackpotDay, currentWord, day);
            }
            coinflip.recordAfKingRng(currentWord, isTicketJackpotDay); // afKing gets bonus on special days
            _finalizeLootboxRngFromDaily(currentWord);
            return currentWord;
        }

        if (rngLockedFlag) {
            if (rngRequestTime != 0) {
                uint48 elapsed = uint48(block.timestamp) - rngRequestTime;
                if (elapsed >= GAMEOVER_RNG_FALLBACK_DELAY) {
                    // Use earliest historical VRF word as fallback (more secure than blockhash)
                    uint256 fallbackWord = _getHistoricalRngFallback(day);
                    rngWordByDay[day] = fallbackWord;
                    if (lvl != 0) {
                        coinflip.processCoinflipPayouts(isTicketJackpotDay, fallbackWord, day);
                    }
                    coinflip.recordAfKingRng(fallbackWord, isTicketJackpotDay); // afKing gets bonus on special days
                    _finalizeLootboxRngFromDaily(fallbackWord);
                    return fallbackWord;
                }
            }
            return 0;
        }

        if (_tryRequestRng(gameState, isTicketJackpotDay, lvl)) {
            return 1;
        }

        // VRF request failed; lock RNG and start fallback timer.
        rngLockedFlag = true;
        rngFulfilled = false;
        rngWordCurrent = 0;
        rngRequestTime = uint48(block.timestamp);
        return 0;
    }

    /// @dev Get historical VRF word as fallback for gameover RNG.
    ///      Searches backwards from current day to find earliest available RNG word (max 30 tries).
    ///      If no historical words exist, uses firstEverRngWord as ultimate fallback.
    ///      Reverts if VRF never worked at all (game would be unplayable anyway).
    /// @param currentDay Current day index.
    /// @return word Historical RNG word or VRF-derived fallback.
    function _getHistoricalRngFallback(
        uint48 currentDay
    ) private view returns (uint256 word) {
        // Search for earliest available historical RNG word (capped at 30 tries for gas)
        // Start from day 1 (day 0 might not exist if game started at different time)
        uint48 searchLimit = currentDay > 30 ? 30 : currentDay;
        for (uint48 searchDay = 1; searchDay < searchLimit; ) {
            word = rngWordByDay[searchDay];
            if (word != 0) {
                // Found a historical VRF word - use it (XOR with current day for uniqueness)
                return uint256(keccak256(abi.encodePacked(word, currentDay)));
            }
            unchecked {
                ++searchDay;
            }
        }

        // No historical words found - use first VRF word ever received as ultimate fallback
        if (firstEverRngWord == 0) revert E(); // VRF must work at some point
        return
            uint256(keccak256(abi.encodePacked(firstEverRngWord, currentDay)));
    }

    /*+======================================================================+
      |                    FUTURE PRIZE POOL DRAW                           |
      +======================================================================+
      |  Release a portion of the future prize pool once per level.         |
      |  Normal levels draw 20%, x00 levels skip the draw.                   |
      +======================================================================+*/

    function _nextToFutureBps(uint48 elapsed) private pure returns (uint16) {
        if (elapsed <= 1 days) {
            return NEXT_TO_FUTURE_BPS_FAST;
        }
        if (elapsed <= 14 days) {
            uint256 span = 13 days;
            uint256 elapsedAfterDay = elapsed - 1 days;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST - NEXT_TO_FUTURE_BPS_MIN; // 20% -> 3%
            return uint16(
                NEXT_TO_FUTURE_BPS_FAST - (delta * elapsedAfterDay) / span
            );
        }
        if (elapsed <= 28 days) {
            uint256 span = 14 days;
            uint256 elapsedAfterMin = elapsed - 14 days;
            uint256 delta = NEXT_TO_FUTURE_BPS_FAST - NEXT_TO_FUTURE_BPS_MIN; // 3% -> 20%
            return uint16(
                NEXT_TO_FUTURE_BPS_MIN + (delta * elapsedAfterMin) / span
            );
        }
        uint256 weeksAfter = (elapsed - 28 days) / 1 weeks;
        uint256 bps = uint256(NEXT_TO_FUTURE_BPS_FAST) +
            (weeksAfter * NEXT_TO_FUTURE_BPS_WEEK_STEP);
        if (bps > 10_000) bps = 10_000;
        return uint16(bps);
    }

    function _nextSkimVarianceDelta(
        uint256 baseTakeAbs,
        uint256 nextPoolBefore,
        uint256 rngWord,
        uint256 maxDelta
    ) private pure returns (int256) {
        if (baseTakeAbs == 0 || maxDelta == 0) return 0;
        uint256 variance = (baseTakeAbs * NEXT_SKIM_VARIANCE_BPS) / 10_000;
        uint256 minVariance = (nextPoolBefore * NEXT_SKIM_VARIANCE_MIN_BPS) / 10_000;
        if (variance < minVariance) variance = minVariance;
        if (variance == 0) return 0;
        if (variance > maxDelta) variance = maxDelta;

        uint256 seed = uint256(keccak256(abi.encodePacked(rngWord, NEXT_SKIM_VARIANCE_TAG)));
        uint256 span = variance * 2 + 1;
        return int256(seed % span) - int256(variance);
    }

    function _nextRatioAdjustBps(uint256 futurePool, uint256 nextPool) private pure returns (int256) {
        if (nextPool == 0) return 0;
        uint256 ratioBps = (futurePool * 10_000) / nextPool; // 1.0x = 10000 bps
        int256 adjust = (int256(ratioBps) * 100) / 10_000 - 200; // 1% per 1x, offset -2%
        if (adjust > 200) return 200;
        if (adjust < -200) return -200;
        return adjust;
    }

    function _nextGrowthAdjustBps(uint256 nextPool, uint256 lastPool) private pure returns (int256) {
        if (lastPool == 0) return 0;
        if (nextPool <= lastPool) return -200; // Equal or down: favor future
        uint256 excess = nextPool - lastPool;
        uint256 excessBps = (excess * 10_000) / lastPool;
        if (excessBps >= 2000) return 200; // >=20% increase
        return -200 + int256(excessBps / 5); // linear to +2% at 20%
    }

    function _applyTimeBasedFutureTake(uint48 reachedAt, uint24 lvl, uint256 rngWord) private {
        uint48 start = levelStartTime;
        if (start == LEVEL_START_SENTINEL || reachedAt <= start) return;
        uint48 elapsed = reachedAt - start;
        uint16 bps = _nextToFutureBps(elapsed);
        if (lvl % 10 == 9) {
            uint256 bumped = uint256(bps) + NEXT_TO_FUTURE_BPS_X9_BONUS;
            bps = uint16(bumped > 10_000 ? 10_000 : bumped);
        }
        uint256 nextPoolBefore = nextPrizePool;
        if (nextPoolBefore == 0) return;

        uint256 futurePoolBefore = futurePrizePool;
        int256 ratioAdjustBps = _nextRatioAdjustBps(futurePoolBefore, nextPoolBefore);
        int256 growthAdjustBps = _nextGrowthAdjustBps(nextPoolBefore, lastPrizePool);
        int256 adjustedBps = int256(uint256(bps)) - ratioAdjustBps - growthAdjustBps;
        int256 baseTake = (int256(uint256(nextPoolBefore)) * adjustedBps) / 10_000;

        if (baseTake > 0) {
            uint256 take = uint256(baseTake);
            if (take > nextPoolBefore) take = nextPoolBefore;
            if (take != 0) {
                nextPrizePool -= take;
                futurePrizePool += take;
            }
            baseTake = int256(take);
        } else if (baseTake < 0) {
            uint256 take = uint256(-baseTake);
            if (take > futurePoolBefore) take = futurePoolBefore;
            if (take != 0) {
                futurePrizePool -= take;
                nextPrizePool += take;
            }
            baseTake = -int256(take);
        }

        uint256 baseTakeAbs = baseTake >= 0 ? uint256(baseTake) : uint256(-baseTake);
        uint256 maxDelta = nextPrizePool < futurePrizePool ? nextPrizePool : futurePrizePool;
        int256 delta = _nextSkimVarianceDelta(baseTakeAbs, nextPoolBefore, rngWord, maxDelta);
        if (delta > 0) {
            uint256 extra = uint256(delta);
            if (extra != 0) {
                nextPrizePool -= extra;
                futurePrizePool += extra;
            }
        } else if (delta < 0) {
            uint256 extra = uint256(-delta);
            if (extra != 0) {
                futurePrizePool -= extra;
                nextPrizePool += extra;
            }
        }
    }

    function _drawDownFuturePrizePool(uint24 lvl) private {
        if (futurePoolLastLevel == lvl) return;
        futurePoolLastLevel = lvl;

        uint256 reserved;
        if ((lvl % 100) == 0) {
            reserved = 0; // Skip extra future->next move on x00 levels
        } else {
            reserved = futurePrizePool / 5; // 20% on normal levels
        }

        if (reserved != 0) {
            futurePrizePool -= reserved;
            nextPrizePool += reserved;
        }
    }

    /*+======================================================================+
      |                    FUTURE TICKET ACTIVATION                         |
      +======================================================================+
      |  Future ticket rewards are staged per level and activated at the     |
      |  start of the PREVIOUS level's burn phase (making them eligible      |
      |  for daily jackpots and early burn rewards).                         |
      +======================================================================+*/

    /// @dev Process a batch of future ticket rewards for the specified level.
    ///      Called during burn phase of level N-1 to activate tickets for level N.
    /// @param playersToProcess Max players to process this call (0 = default batch size).
    /// @param lvl Target level to activate (typically current level + 1).
    /// @return worked True if any queued entries were processed.
    /// @return finished True if all queued entries for this level are processed.
    function _processFutureTicketBatch(
        uint32 playersToProcess,
        uint24 lvl
    ) private returns (bool worked, bool finished) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_MINT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameMintModule.processFutureTicketBatch.selector,
                    playersToProcess,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (bool, bool));
    }

    /*+======================================================================+
      |                    TICKET / gamepiece AIRDROP BATCHING                     |
      +======================================================================+
      |  Ticket entries are processed in batches to prevent gas exhaustion.  |
      |  Large purchases are queued and processed across multiple txs.       |
      +======================================================================+*/

    /// @dev Process a batch of current level tickets via jackpot module delegatecall.
    /// @param writesBudget Count of SSTORE writes allowed (0 = use default).
    /// @param lvl Current level whose tickets should be processed.
    /// @return finished True if all tickets for this level have been processed.
    function _processTicketBatch(
        uint32 writesBudget,
        uint24 lvl
    ) internal returns (bool finished) {
        (bool ok, bytes memory data) = ContractAddresses
            .GAME_JACKPOT_MODULE
            .delegatecall(
                abi.encodeWithSelector(
                    IDegenerusGameJackpotModule.processTicketBatch.selector,
                    writesBudget,
                    lvl
                )
            );
        if (!ok) _revertDelegate(data);
        if (data.length == 0) revert E();
        return abi.decode(data, (bool));
    }

    /// @dev Helper to run one ticket batch and detect whether any progress was made.
    /// @param writesBudget Gas budget for this batch.
    /// @param lvl Current level.
    /// @return worked True if any tickets were processed.
    /// @return finished True if all tickets for this level have been fully processed.
    function _runProcessTicketBatch(
        uint32 writesBudget,
        uint24 lvl
    ) private returns (bool worked, bool finished) {
        uint32 prevCursor = ticketCursor;
        uint24 prevLevel = ticketLevel;
        finished = _processTicketBatch(writesBudget, lvl);
        worked = (ticketCursor != prevCursor) || (ticketLevel != prevLevel);
    }

    /// @dev Request new VRF random word from Chainlink.
    ///      Sets RNG lock to prevent manipulation during pending window.
    /// @param gameState_ Current game state.
    /// @param isTicketJackpotDay True if this is the last purchase day.
    /// @param lvl Current level.
    function _requestRng(
        uint8 gameState_,
        bool isTicketJackpotDay,
        uint24 lvl
    ) private {
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
        _finalizeRngRequest(gameState_, isTicketJackpotDay, lvl, id);
    }

    function _tryRequestRng(
        uint8 gameState_,
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
            _finalizeRngRequest(gameState_, isTicketJackpotDay, lvl, id);
            requested = true;
        } catch {}
    }

    function _finalizeRngRequest(
        uint8 gameState_,
        bool isTicketJackpotDay,
        uint24 lvl,
        uint256 requestId
    ) private {
        vrfRequestId = requestId;
        rngFulfilled = false;
        rngWordCurrent = 0;
        rngLockedFlag = true;
        rngRequestTime = uint48(block.timestamp);

        bool decClose = (((lvl % 100 != 0 &&
            (lvl % 100 != 99) &&
            gameState_ == GAME_STATE_SETUP) ||
            (lvl % 100 == 0 && isTicketJackpotDay)) && decWindowOpen);
        if (decClose) decWindowOpen = false;
    }

    /// @notice Emergency VRF coordinator rotation after 3-day stall.
    /// @dev Access: ContractAddresses.ADMIN only. Only available when VRF has stalled for 3+ days.
    ///      This is a recovery mechanism for Chainlink outages.
    ///      SECURITY: Requires 3-day gap to prevent abuse.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash for the gas lane.
    function updateVrfCoordinatorAndSub(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash
    ) external {
        if (msg.sender != ContractAddresses.ADMIN) revert E();
        if (!_threeDayRngGap(_currentDayIndex())) revert VrfUpdateNotReady();
        _setVrfConfig(
            newCoordinator,
            newSubId,
            newKeyHash,
            address(vrfCoordinator)
        );
    }

    /// @dev Set new VRF configuration and reset RNG state.
    ///      Clears any pending request and unlocks RNG usage.
    /// @param newCoordinator New VRF coordinator address.
    /// @param newSubId New subscription ID.
    /// @param newKeyHash New key hash.
    /// @param current Previous coordinator address (for event).
    function _setVrfConfig(
        address newCoordinator,
        uint256 newSubId,
        bytes32 newKeyHash,
        address current
    ) private {
        if (
            newCoordinator == address(0) ||
            newKeyHash == bytes32(0) ||
            newSubId == 0
        ) revert E();

        vrfCoordinator = IVRFCoordinator(newCoordinator);
        vrfSubscriptionId = newSubId;
        vrfKeyHash = newKeyHash;

        // Reset RNG state to allow immediate advancement
        rngLockedFlag = false;
        rngFulfilled = true;
        vrfRequestId = 0;
        rngRequestTime = 0;
        rngWordCurrent = 0;
        emit VrfCoordinatorUpdated(current, newCoordinator);
    }

    /// @dev Process all pending tickets (current level + near-future) before unlocking RNG.
    ///      Must complete ALL ticket processing for RNG integrity (tickets use RNG word).
    ///      Credits caller with 500 BURNIE work bounty if work was done.
    /// @param caller Address to credit with work bounty.
    /// @param lvl Current level.
    /// @param cap Emergency cap override (0 = normal mode, >0 = skip bounty).
    /// @return allFinished True if all tickets are fully processed and RNG can be unlocked.
    function _processAllTicketsBeforeUnlock(
        address caller,
        uint24 lvl,
        uint32 cap
    ) private returns (bool allFinished) {
        bool anyWorkDone = false;

        // Process current level tickets (batch size: 0 = use default work counter)
        (bool currentWorked, bool currentFinished) = _runProcessTicketBatch(0, lvl);
        if (currentWorked) anyWorkDone = true;
        if (!currentFinished) return false; // Must finish current level tickets

        // Process near-future tickets (next level) - batch size 0 uses default
        uint24 nextLevel = lvl + 1;
        (bool futureWorked, bool futureFinished) = _processFutureTicketBatch(0, nextLevel);
        if (futureWorked) anyWorkDone = true;
        if (!futureFinished) return false; // Must finish future tickets

        // All tickets processed - credit work bounty to caller (skip in emergency cap mode)
        if (anyWorkDone && cap == 0) {
            coin.creditFlip(caller, TICKET_WORK_BOUNTY);
        }

        return true; // All processing complete, RNG can be unlocked
    }

    /// @dev Unlock RNG after processing is complete for the day.
    ///      Resets VRF state and re-enables RNG usage.
    /// @param day Current day index to record.
    function _unlockRng(uint48 day) private {
        dailyIdx = day;
        rngLockedFlag = false;
        vrfRequestId = 0;
        rngRequestTime = 0;
    }

    /// @notice Pay BURNIE to nudge the next RNG word by +1.
    /// @dev Cost scales +50% per queued nudge and resets after fulfillment.
    ///      Only available while RNG is unlocked (before VRF request is in-flight).
    ///      MECHANISM: Adds 1 to the VRF word for each nudge, changing outcomes.
    ///      SECURITY: Players cannot predict the base word, only influence it.
    /// @param player Player address paying for the nudge (address(0) = msg.sender).
    function reverseFlip(address player) external {
        if (player == address(0)) {
            player = msg.sender;
        } else if (player != msg.sender) {
            _requireApproved(player);
        }
        _reverseFlip(player);
    }

    function _reverseFlip(address player) private {
        if (rngLockedFlag) revert RngLocked();
        uint256 reversals = totalFlipReversals;
        uint256 cost = _currentNudgeCost(reversals);
        coin.burnCoin(player, cost);
        uint256 newCount = reversals + 1;
        totalFlipReversals = newCount;
        emit ReverseFlip(player, newCount, cost);
    }

    /// @dev Try to request a lootbox-specific RNG word.
    ///      Returns true if request was successful, false otherwise.
    function _tryRequestLootboxRng() private returns (bool) {
        if (lootboxRngPendingEth == 0) return false;

        uint48 index = lootboxRngIndex;
        if (lootboxRngWordByIndex[index] != 0) {
            // Already have RNG for this index
            return false;
        }

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
                    extraArgs: hex""
                })
            )
        returns (uint256 id) {
            // Mark this request as lootbox RNG (not daily)
            lootboxRngRequestIndexById[id] = index;
            return true;
        } catch {
            return false;
        }
    }

    /// @notice Chainlink VRF callback for random word fulfillment.
    /// @dev Access: VRF coordinator only.
    ///      Applies any queued nudges before storing the word.
    ///      SECURITY: Validates requestId and coordinator address.
    /// @param requestId The request ID to match.
    /// @param randomWords Array containing the random word (length 1).
    function rawFulfillRandomWords(
        uint256 requestId,
        uint256[] calldata randomWords
    ) external {
        if (msg.sender != address(vrfCoordinator)) revert E();
        uint256 word = randomWords[0];
        if (requestId == vrfRequestId && !rngFulfilled) {
            // Apply any queued nudges (reverseFlip)
            uint256 rngNudge = totalFlipReversals;
            if (rngNudge != 0) {
                unchecked {
                    word += rngNudge;
                }
                totalFlipReversals = 0;
            }
            if (word == 0) word = 1;
            rngFulfilled = true;
            rngWordCurrent = word;
            // Save the first VRF word ever received as ultimate fallback for gameover
            if (firstEverRngWord == 0) {
                firstEverRngWord = word;
            }
            return;
        }

        uint48 lootboxIndex = lootboxRngRequestIndexById[requestId];
        if (lootboxIndex == 0) return;
        if (word == 0) word = 1;
        // Resolve lootbox RNG via standalone contract
        lootbox.resolveLootboxRng(word, lootboxIndex);
        // Note: RNG already stored in lootboxRngWordByIndex, afKing can read from there
        delete lootboxRngRequestIndexById[requestId];
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
    function _clearDailyBurnCount() private {
        // 80 uint32 values packed into 10 consecutive storage slots.
        assembly ("memory-safe") {
            let slot := dailyBurnCount.slot
            let end := add(slot, 10)
            for {
                let s := slot
            } lt(s, end) {
                s := add(s, 1)
            } {
                sstore(s, 0)
            }
        }
    }

    function _seedTraitCounts() private {
        uint32[256] storage remaining = traitRemaining;
        uint32[256] storage startRemaining = traitStartRemaining;

        for (uint16 t; t < 256; ) {
            uint32 value = remaining[t];
            startRemaining[t] = value;
            unchecked {
                ++t;
            }
        }
    }

    function _setExterminatorForLevel(uint24 lvl, address ex) private {
        if (lvl == 0) return;
        levelExterminators[lvl] = ex;
    }

    function _currentDayIndex() private view returns (uint48) {
        // Calculate day boundaries with JACKPOT_RESET_TIME offset
        uint48 currentDayBoundary = uint48(
            (block.timestamp - JACKPOT_RESET_TIME) / 1 days
        );
        return currentDayBoundary - ContractAddresses.DEPLOY_DAY_BOUNDARY + 1;
    }

    function _threeDayRngGap(uint48 day) private view returns (bool) {
        if (rngWordByDay[day] != 0) return false;
        if (day == 0 || rngWordByDay[day - 1] != 0) return false;
        if (day < 2 || rngWordByDay[day - 2] != 0) return false;
        return true;
    }
}
