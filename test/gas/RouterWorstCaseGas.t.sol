// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @notice A real new day with queued tickets completes through checkpointed keeper calls.
/// @dev Whole-call gas is diagnostic. Native operation suites assert admission bounds and tails.
///      Run with --isolate for measurements against committed state.
contract RouterWorstCaseGas is DeployProtocol {
    uint256 internal constant REALISTIC_CALL_GAS = 10_000_000;

    function setUp() public {
        _deployProtocol();
        // Advance one day off the deploy boundary so the day index is a clean, stable index.
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 10_000_000 ether);
    }


    /// @notice TST-06 / Δ3 advance leg: with NO subscribers and NO ready boxes, a real new day's work
    ///         (subscriber preparation, the day's request, then the day's processing with its ticket
    ///         drain) is driven THROUGH `mineFlip()` with a realistic 10M allowance per call.
    /// @dev    Owner gas rule (2026-10-03): the engine admits checkpoints while the allowance covers the
    ///         next declared bound (MineFlipGasBounds), so a call given unbounded gas composes the whole
    ///         day and a whole-call ceiling would only measure its own allowance. The property kept here
    ///         is that every call at a realistic allowance succeeds (never runs out of gas, never refuses
    ///         a required checkpoint) and makes progress until the day is processed. Per-chunk bounds are
    ///         pinned by the MineFlipGasBounds-driven suites (test/repro/*Checkpoints*.t.sol,
    ///         test/gas/DirectJackpotAdvanceGas.t.sol). Calls are logged for calibration.
    function testMineFlipAdvanceCompletesWithRealisticAllowance() public {
        // Seed a real ticket queue so the new-day advance has structural drain work (the heaviest
        // realizable advance step on the fresh fixture).
        address buyer = makeAddr("mbAdvBuyer");
        vm.deal(buyer, 1_000 ether);
        for (uint256 i; i < 8; ++i) {
            vm.prank(buyer);
            game.purchase{value: 0.01 ether}(0, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }

        vm.warp(block.timestamp + 1 days);
        assertTrue(game.advanceDue(), "advanceDue on the new day");
        assertFalse(game.boxesPending(), "no boxes pending -> mineFlip routes to advance");

        address opener = makeAddr("mbAdv_opener");
        uint256 maxCallGas;
        uint256 calls;
        // The new day's preparation and request (a request ends its call).
        while (!game.rngLocked()) {
            assertLt(calls, 16, "advance non-vacuity: a real new-day advance step ran (rngLock/day moved)");
            maxCallGas = _realisticCall(opener, maxCallGas);
            ++calls;
        }
        uint256 sealedBefore = uint24(uint256(vm.load(address(game), bytes32(0))) >> 24);
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), uint256(keccak256("mbAdv_word")) | 1);
        // The day's processing: publication, the ticket drain, the day's word, its daily phase.
        while (game.rngLocked()) {
            assertLt(calls, 64, "the day's processing completes at a realistic allowance");
            maxCallGas = _realisticCall(opener, maxCallGas);
            ++calls;
        }
        assertGt(uint24(uint256(vm.load(address(game), bytes32(0))) >> 24), sealedBefore, "the new day was sealed");

        emit log_named_uint("mintflip_advance_calls", calls);
        emit log_named_uint("mintflip_advance_max_call_gas", maxCallGas);
        emit log_named_uint("realistic_call_allowance", REALISTIC_CALL_GAS);
    }

    /// @dev One mineFlip at the realistic allowance; it must succeed (progress is enforced by the
    ///      engine: a zero-progress call reverts).
    function _realisticCall(address caller, uint256 maxSoFar) internal returns (uint256) {
        vm.prank(caller);
        uint256 gasBefore = gasleft();
        game.mineFlip{gas: REALISTIC_CALL_GAS}();
        uint256 used = gasBefore - gasleft();
        emit log_named_uint("mintflip_advance_call_gas", used);
        return used > maxSoFar ? used : maxSoFar;
    }
}
