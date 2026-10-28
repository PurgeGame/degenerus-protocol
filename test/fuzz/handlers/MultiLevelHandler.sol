// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";
import {BoxOrderLib} from "../../helpers/BoxOrderLib.sol";

/// @title MultiLevelHandler -- Handler for deep multi-level game progression
/// @notice Drives the game through purchase -> VRF -> advance -> next level cycles.
///         The random walk alone never leaves level 0 (measured: the actors' purchases fill a fraction
///         of the level-0 target and the walk locks the daily RNG early), so `scriptedOpening` first
///         plays a fixed, real-money, day-by-day opening to `OPENING_LEVEL`. The fuzzed walk then
///         runs from that deep state, with price escalation and pool growth tracking.
/// @dev Actors are funded with large ETH balances to sustain purchases at escalating prices.
///      Ghost variables track pool balances at each level transition for solvency verification.
contract MultiLevelHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- Ghost variables ---
    uint256 public ghost_maxLevel;
    uint256 public ghost_totalDeposited;
    uint256 public ghost_levelTransitions;
    uint256 public ghost_vrfFulfillments;
    uint256 public ghost_advances;
    uint256 public ghost_successfulPurchases;

    // --- Scripted opening ---
    uint256 public constant OPENING_LEVEL = 10;
    uint256 public constant OPENING_MAX_DAYS = 90;
    uint256 internal constant OPENING_BOX = 60 ether;
    bool public opened;
    address public immutable driver = address(0xD21FE);
    uint256 public openingDays;
    uint256 public openingPurchases;
    uint256 public openingAdvances;

    // Required activity belongs to each fuzz trace, after the opening snapshots.
    // A failed prefix remains observable even when fail_on_revert is false.
    bool public walkStarted;
    bool public walkPrefixComplete;
    bool public walkFailed;
    bytes public walkFailure;
    uint256 public walkPrefixPurchases;
    uint256 public walkPrefixWork;
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");

    // Pool snapshots at level transitions
    uint256 public ghost_lastCurrentPool;
    uint256 public ghost_lastNextPool;
    uint256 public ghost_lastFuturePool;
    uint256 public ghost_lastClaimablePool;

    // Price tracking
    uint256 public ghost_minPrice;
    uint256 public ghost_maxPrice;
    bool public ghost_priceInitialized;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;
    uint256 public calls_heavyPurchase;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(DegenerusGame game_, MockVRFCoordinator vrf_, uint256 numActors) {
        game = game_;
        vrf = vrf_;
        ghost_maxLevel = game_.currentLvl();
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xAA000 + i));
            actors.push(actor);
            // Large balance: 10000 ETH each for deep level progression
            vm.deal(actor, 10_000 ether);
        }
    }

    /// @notice Fixed opening: one real purchase (tickets plus a 60 ETH lootbox) per game day from a funded
    ///         driver, the daily VRF word fulfilled and mineFlip cranked until it refuses, until the game
    ///         reaches `OPENING_LEVEL`. Real ETH moves through the real engine (no pool seeding), so the
    ///         solvency invariant stays meaningful. Latched: runs once, later calls are no-ops.
    /// @dev Measured: level 12 in 44 days; the bound leaves margin and a stall fails the suite's setUp.
    function scriptedOpening() external {
        if (opened) return;
        opened = true;
        vm.deal(driver, 100_000 ether);
        // vm.getBlockTimestamp(): a hoisted block.timestamp can be stale after vm.warp under via-IR.
        uint256 t = vm.getBlockTimestamp();
        for (uint256 day; day < OPENING_MAX_DAYS && game.currentLvl() < OPENING_LEVEL; ++day) {
            t += 1 days + 1;
            vm.warp(t);
            ++openingDays;

            (, , , bool locked, uint256 priceWei) = game.purchaseInfo_g1027();
            if (!locked && !game.gameOver()) {
                uint256 cost = priceWei * 10 + OPENING_BOX;
                vm.prank(driver);
                try game.purchaseOrderFor{value: cost}(
                    0, 4000, BoxOrderLib.boCustomFloor(OPENING_BOX), bytes32(0), MintPaymentKind.DirectEth, false
                ) {
                    ghost_totalDeposited += cost;
                    ghost_successfulPurchases++;
                } catch {}
            }

            for (uint256 j; j < 80; ++j) {
                _fulfillPendingVrf();
                uint256 levelBefore = game.currentLvl();
                vm.prank(driver);
                try game.mineRun(0) {
                    ghost_advances++;
                } catch {
                    break;
                }
                _checkLevelTransition(levelBefore);
            }
        }
        openingPurchases = ghost_successfulPurchases;
        openingAdvances = ghost_advances;
    }

    /// @notice One fuzzed step, preceded once by useful, fuzz-dependent activity.
    /// @dev The prefix runs inside the first fuzz call, never in setUp. Afterwards all seven
    ///      adversarial actions retain their original behavior, including unlimited time skips.
    ///      Catch only the prefix's failure to preserve it for afterInvariant; never retry it.
    function walk(uint256 actionSeed, uint256 actorSeed, uint256 quantitySeed, uint256 wordSeed) external {
        if (!walkStarted) {
            walkStarted = true;
            try this.beginWalk(actorSeed, quantitySeed, wordSeed) {
                walkPrefixComplete = true;
            } catch (bytes memory reason) {
                walkFailed = true;
                walkFailure = reason;
            }
        }
        if (!walkPrefixComplete) return;

        uint256 action = actionSeed % 7;
        if (action == 0) this.purchase(actorSeed, quantitySeed);
        else if (action == 1) this.heavyPurchase(actorSeed, quantitySeed);
        else if (action == 2) this.mineFlip(actorSeed);
        else if (action == 3) this.fulfillVrf(wordSeed);
        else if (action == 4) this.warpDay();
        else if (action == 5) this.warpPastVrfTimeout();
        else this.warpTime(quantitySeed);
    }

    /// @dev Separate frame lets walk retain the exact failure instead of having the fuzzer
    ///      discard a reverting handler. All required calls use production entrypoints.
    function beginWalk(uint256 actorSeed, uint256 quantitySeed, uint256 wordSeed) external {
        require(msg.sender == address(this), "MultiLevel: prefix is self-only");
        require(opened && !game.gameOver() && !game.livenessTriggered(), "MultiLevel: prefix requires a live opening");
        uint256 start = actorSeed % actors.length;
        for (uint256 i; i < 3; ++i) {
            address buyer = actors[(start + i) % actors.length];
            uint256 tickets = 1 + uint256(keccak256(abi.encode(quantitySeed, i))) % 2;
            (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
            uint256 cost = priceWei * tickets;
            uint256 levelBefore = game.currentLvl();
            uint256 balanceBefore = buyer.balance;
            uint256 mintBefore = game.mintPackedFor(buyer);
            vm.prank(buyer);
            game.purchaseOrderFor{value: cost}(
                0, tickets * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false
            );
            require(buyer.balance + cost == balanceBefore, "MultiLevel: required purchase did not spend ETH");
            require(game.mintPackedFor(buyer) != mintBefore, "MultiLevel: required purchase did not record activity");
            ghost_totalDeposited += cost;
            ++ghost_successfulPurchases;
            ++walkPrefixPurchases;
            _checkLevelTransition(levelBefore);
        }

        // A fresh day makes work due if the opening left an idle engine. Fulfil only the
        // request already outstanding here; later fuzz actions receive no automatic help.
        if (game.nextMinerAction() == 0) vm.warp(vm.getBlockTimestamp() + 1 days + 1);
        uint256 reqId = vrf.lastRequestId();
        if (reqId != 0) {
            (, , bool fulfilled) = vrf.pendingRequests(reqId);
            if (!fulfilled) {
                // Required progress uses an admissible word. The unrestricted fulfillVrf
                // action still exercises reserved words 0 and 1 later in the trace.
                vrf.fulfillRandomWords(reqId, wordSeed < 2 ? wordSeed + 2 : wordSeed);
                ++ghost_vrfFulfillments;
            }
        }
        uint256 levelBefore = game.currentLvl();
        address miner = actors[start];
        vm.recordLogs();
        vm.prank(miner);
        game.mineRun(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2
                && logs[i].topics[0] == MINER_WORK
                && address(uint160(uint256(logs[i].topics[1]))) == miner) {
                (, uint256 executionGas,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                if (executionGas != 0) ++walkPrefixWork;
            }
        }
        // Request refusal can return successfully without moving the engine. Its absence of
        // MinerWork must fail required coverage, even though an ordinary handler may tolerate it.
        require(walkPrefixWork == 1, "MultiLevel: prefix miner made no progress");
        ++ghost_advances;
        _checkLevelTransition(levelBefore);
    }

    /// @notice Heavy purchase to rapidly fill prize pool and trigger level transitions
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw quantity, bounded to [1000, 4000]
    function heavyPurchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_heavyPurchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 1000, 4000);

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        uint256 levelBefore = game.currentLvl();

        vm.prank(currentActor);
        try game.purchaseOrderFor{value: cost}(
            0,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth, false
        ) {
            ghost_totalDeposited += cost;
            ghost_successfulPurchases++;

            // Track price
            if (!ghost_priceInitialized) {
                ghost_minPrice = priceWei;
                ghost_maxPrice = priceWei;
                ghost_priceInitialized = true;
            } else {
                if (priceWei < ghost_minPrice) ghost_minPrice = priceWei;
                if (priceWei > ghost_maxPrice) ghost_maxPrice = priceWei;
            }
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Standard purchase with smaller quantities
    /// @param actorSeed Seed for actor selection
    /// @param qty Raw quantity, bounded to [100, 1000]
    function purchase(
        uint256 actorSeed,
        uint256 qty
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 1000);

        (, , , , uint256 priceWei) = game.purchaseInfo_g1027();
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0 || cost > currentActor.balance) return;

        uint256 levelBefore = game.currentLvl();

        vm.prank(currentActor);
        try game.purchaseOrderFor{value: cost}(
            0,
            qty,
            0,
            bytes32(0),
            MintPaymentKind.DirectEth, false
        ) {
            ghost_totalDeposited += cost;
            ghost_successfulPurchases++;
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Advance game (crucial for level transitions)
    /// @param actorSeed Seed for actor selection
    function mineFlip(uint256 actorSeed) external useActor(actorSeed) {
        calls_advanceGame++;

        if (game.gameOver()) return;

        uint256 levelBefore = game.currentLvl();

        vm.prank(currentActor);
        try game.mineRun(0) {
            ghost_advances++;
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Fulfill VRF to unblock level transitions
    /// @param randomWord Random word for VRF fulfillment
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 levelBefore = game.currentLvl();

        try vrf.fulfillRandomWords(reqId, randomWord) {
            ghost_vrfFulfillments++;
        } catch {}

        _checkLevelTransition(levelBefore);
    }

    /// @notice Warp past a game day to enable daily jackpots
    function warpDay() external {
        vm.warp(block.timestamp + 1 days + 1);
    }

    /// @notice Warp past VRF timeout
    function warpPastVrfTimeout() external {
        vm.warp(block.timestamp + 18 hours + 1);
    }

    /// @notice Small time warp
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 12 hours);
        vm.warp(block.timestamp + delta);
    }

    // --- Internal helpers ---

    function _fulfillPendingVrf() private {
        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;
        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;
        try vrf.fulfillRandomWords(reqId, uint256(keccak256(abi.encode(block.timestamp, reqId)))) {
            ghost_vrfFulfillments++;
        } catch {}
    }

    function _checkLevelTransition(uint256 levelBefore) private {
        uint256 levelAfter = game.currentLvl();
        if (levelAfter > levelBefore) {
            ghost_levelTransitions++;
            if (levelAfter > ghost_maxLevel) {
                ghost_maxLevel = levelAfter;
            }
            // Snapshot pool state at transition
            ghost_lastCurrentPool = game.currentPrizePoolView();
            ghost_lastNextPool = game.nextPrizePoolView();
            ghost_lastFuturePool = game.futurePrizePoolView();
            ghost_lastClaimablePool = game.claimablePoolView();
        }
    }
}
