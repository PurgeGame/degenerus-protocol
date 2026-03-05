// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import {DegenerusGame} from "../../../contracts/DegenerusGame.sol";
import {MockVRFCoordinator} from "../../../contracts/mocks/MockVRFCoordinator.sol";
import {MintPaymentKind} from "../../../contracts/interfaces/IDegenerusGame.sol";

/// @title FSMHandler -- Handler that snapshots game FSM state for invariant testing
/// @notice Wraps purchase/advanceGame/VRF operations while tracking FSM ghost state.
///         The invariant test checks that level only increases, gameOver is terminal,
///         and phase transitions are valid.
contract FSMHandler is Test {
    DegenerusGame public game;
    MockVRFCoordinator public vrf;

    // --- FSM Ghost variables ---
    uint256 public ghost_maxLevel;
    bool public ghost_everGameOver;
    uint256 public ghost_levelDecreaseCount;
    uint256 public ghost_gameOverRevival;

    // --- Call counters ---
    uint256 public calls_purchase;
    uint256 public calls_advanceGame;
    uint256 public calls_fulfillVrf;

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
        for (uint256 i = 0; i < numActors; i++) {
            address actor = address(uint160(0xF0000 + i));
            actors.push(actor);
            vm.deal(actor, 100 ether);
        }
    }

    /// @notice Purchase tickets while tracking FSM state
    function purchase(
        uint256 actorSeed,
        uint256 qty,
        uint256 lootboxAmt
    ) external useActor(actorSeed) {
        calls_purchase++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        if (gameOverBefore) {
            // Track if gameOver was ever true
            ghost_everGameOver = true;
            return;
        }

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
        ) {} catch {}

        _updateFSMState(levelBefore, gameOverBefore);
    }

    /// @notice Advance game while tracking FSM state
    function advanceGame(uint256 actorSeed) external useActor(actorSeed) {
        calls_advanceGame++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        if (gameOverBefore) {
            ghost_everGameOver = true;
            return;
        }

        vm.prank(currentActor);
        try game.advanceGame() {} catch {}

        _updateFSMState(levelBefore, gameOverBefore);
    }

    /// @notice Fulfill VRF while tracking FSM state
    function fulfillVrf(uint256 randomWord) external {
        calls_fulfillVrf++;

        uint256 levelBefore = game.level();
        bool gameOverBefore = game.gameOver();

        uint256 reqId = vrf.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = vrf.pendingRequests(reqId);
        if (fulfilled) return;

        try vrf.fulfillRandomWords(reqId, randomWord) {} catch {}

        _updateFSMState(levelBefore, gameOverBefore);
    }

    /// @notice Warp past VRF timeout
    function warpPastVrfTimeout() external {
        vm.warp(block.timestamp + 18 hours + 1);
    }

    /// @notice Warp time by bounded delta
    function warpTime(uint256 delta) external {
        delta = bound(delta, 1 minutes, 30 days);
        vm.warp(block.timestamp + delta);
    }

    /// @dev Update FSM ghost state after an operation
    function _updateFSMState(uint256 levelBefore, bool gameOverBefore) private {
        uint256 levelAfter = game.level();
        bool gameOverAfter = game.gameOver();

        // Track level monotonicity violations
        if (levelAfter < levelBefore) {
            ghost_levelDecreaseCount++;
        }

        // Track max level
        if (levelAfter > ghost_maxLevel) {
            ghost_maxLevel = levelAfter;
        }

        // Track gameOver terminality violations
        if (gameOverBefore && !gameOverAfter) {
            ghost_gameOverRevival++;
        }

        if (gameOverAfter) {
            ghost_everGameOver = true;
        }
    }
}
