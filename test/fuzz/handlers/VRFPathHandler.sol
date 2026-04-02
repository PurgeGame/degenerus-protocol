// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {DegenerusAdmin} from "../../../contracts/DegenerusAdmin.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title VRFPathHandler -- Invariant handler for VRF path lifecycle testing
/// @notice Wraps purchase/advanceGame/VRF/coordinatorSwap/warp operations while
///         tracking ghost variables for TEST-01 (lootbox index lifecycle),
///         TEST-02 (stall-to-recovery state machine), and TEST-03 (gap backfill).
contract VRFPathHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;
    DegenerusAdmin public admin;

    // --- Actor management ---
    address[] public actors;
    address internal currentActor;

    // --- Ghost variables: TEST-01 (lootbox index lifecycle) ---
    uint48 public ghost_expectedIndex;
    uint256 public ghost_indexSkipViolations;
    uint256 public ghost_doubleIncrementCount;
    uint256 public ghost_orphanedIndices;

    // --- Ghost variables: TEST-02 (stall-to-recovery state machine) ---
    uint256 public ghost_stallCount;
    uint256 public ghost_recoveryCount;
    uint256 public ghost_stateViolations;
    bool public ghost_swapPending;

    // --- Ghost variables: TEST-03 (gap backfill) ---
    uint256 public ghost_maxGapSize;
    uint256 public ghost_gapBackfillFailures;
    uint48 public ghost_dayBeforeSwap;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;
    uint256 public calls_coordinatorSwap;
    uint256 public calls_requestLootboxRng;
    uint256 public calls_warpTime;

    /// @dev Read lootboxRngIndex directly from storage slot 40.
    function _lootboxRngIndex() internal view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(uint256(40)))));
    }

    /// @dev Read lootboxRngWordByIndex[index] from storage (mapping at slot 44).
    function _lootboxRngWord(uint48 index) internal view returns (uint256) {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(44)));
        return uint256(vm.load(address(game), slot));
    }

    modifier useActor(uint256 seed) {
        currentActor = actors[bound(seed, 0, actors.length - 1)];
        _;
    }

    constructor(
        DegenerusGame game_,
        MockVRFCoordinator vrf_,
        DegenerusAdmin admin_,
        uint256 numActors
    ) {
        game = game_;
        vrf = vrf_;
        admin = admin_;
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xF0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
        ghost_expectedIndex = _lootboxRngIndex();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Handler Actions (7 fuzzer-callable functions)
    // ═══════════════════════════════════════════════════════════════════════

    /// @notice Purchase tickets while tracking VRF path state
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        if (game.gameOver()) return;

        qty = bound(qty, 100, 4000);
        lootboxAmt = bound(lootboxAmt, 0, 2 ether);

        (, , , , uint256 priceWei) = game.purchaseInfo();
        uint256 ticketCost = (priceWei * qty) / 400;
        uint256 totalCost = ticketCost + lootboxAmt;

        if (totalCost == 0 || totalCost > currentActor.balance) return;

        vm.prank(currentActor);
        try game.purchase{value: totalCost}(
            currentActor,
            qty,
            lootboxAmt,
            bytes32(0),
            MintPaymentKind.DirectEth
        ) {} catch {
            return;
        }
    }

    /// @notice Advance game while tracking index lifecycle and recovery state
    function advanceGame() external {
        calls_advanceGame++;

        if (game.gameOver()) return;

        uint48 indexBefore = _lootboxRngIndex();
        bool lockedBefore = game.rngLocked();

        try game.advanceGame() {} catch {
            return;
        }

        uint48 indexAfter = _lootboxRngIndex();
        bool lockedAfter = game.rngLocked();

        // TEST-01: double-increment detection
        if (indexAfter > indexBefore + 1) {
            ghost_doubleIncrementCount++;
        }

        // TEST-01: track expected index
        if (indexAfter > indexBefore) {
            ghost_expectedIndex += (indexAfter - indexBefore);
        }

        // TEST-02: recovery detection after coordinator swap
        // Only check gap days after the FULL recovery cycle completes:
        // advanceGame transitioned the game from locked to unlocked, meaning
        // the VRF word was consumed and gap days were backfilled in this call.
        if (ghost_swapPending && lockedBefore && !lockedAfter) {
            uint48 dayAfter = game.currentDayView();

            if (dayAfter > ghost_dayBeforeSwap) {
                // Full recovery cycle completed -- check gap days
                // Gap days are from (dayBeforeSwap+1) to (dayAfter-1).
                // The current day (dayAfter) is processed normally, not a gap day.
                if (dayAfter > ghost_dayBeforeSwap + 1) {
                    uint48 gapStart = ghost_dayBeforeSwap + 1;
                    uint48 gapEnd = dayAfter;
                    for (uint48 d = gapStart; d < gapEnd; d++) {
                        if (game.rngWordForDay(d) == 0) {
                            ghost_gapBackfillFailures++;
                        }
                    }

                    uint256 gapSize = uint256(gapEnd - gapStart);
                    if (gapSize > ghost_maxGapSize) {
                        ghost_maxGapSize = gapSize;
                    }
                }

                ghost_swapPending = false;
                ghost_recoveryCount++;
            }
        }
    }

    /// @notice Fulfill pending VRF request with fuzzed random word
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        uint48 indexBefore = _lootboxRngIndex();

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {
            return;
        }

        uint48 indexAfter = _lootboxRngIndex();

        // TEST-01: check for orphaned indices after VRF unlock
        // Only check the most recently unlocked index to avoid re-counting
        if (!game.rngLocked() && indexAfter > 0 && indexAfter > indexBefore) {
            if (_lootboxRngWord(indexAfter - 1) == 0) {
                ghost_orphanedIndices++;
            }
        }
    }

    /// @notice Request mid-day lootbox RNG while tracking index lifecycle
    function requestLootboxRng() external {
        calls_requestLootboxRng++;

        if (game.gameOver() || game.rngLocked()) return;

        uint48 indexBefore = _lootboxRngIndex();

        try game.requestLootboxRng() {} catch {
            return;
        }

        uint48 indexAfter = _lootboxRngIndex();

        // TEST-01: skip/double-increment detection
        if (indexAfter > indexBefore + 1) {
            ghost_doubleIncrementCount++;
        }

        if (indexAfter > indexBefore) {
            ghost_expectedIndex += (indexAfter - indexBefore);
        }
    }

    /// @notice Perform coordinator swap and track stall-to-recovery state
    function coordinatorSwap() external {
        calls_coordinatorSwap++;

        if (game.gameOver()) return;

        ghost_dayBeforeSwap = game.currentDayView();

        MockVRFCoordinator newVRF = new MockVRFCoordinator();
        uint256 newSubId = newVRF.createSubscription();
        newVRF.addConsumer(newSubId, address(game));

        vm.prank(address(admin));
        try game.updateVrfCoordinatorAndSub(
            address(newVRF),
            newSubId,
            bytes32(uint256(1))
        ) {} catch {
            return;
        }

        vrf = newVRF;
        ghost_stallCount++;
        ghost_swapPending = true;

        // TEST-02: rngLocked must be false after swap
        if (game.rngLocked()) {
            ghost_stateViolations++;
        }
    }

    /// @notice Warp time by bounded delta
    function warpTime(uint256 delta) external {
        calls_warpTime++;
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
    }

    /// @notice Warp past VRF timeout (12h + 1h buffer)
    function warpPastTimeout() external {
        vm.warp(block.timestamp + 13 hours);
    }
}
