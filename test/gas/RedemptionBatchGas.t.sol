// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {AutomaticRedemptionSettlementTest} from "../fuzz/AutomaticRedemptionSettlement.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";

contract RedemptionBatchGasTest is AutomaticRedemptionSettlementTest {
    function _coolSettlementState() internal {
        vm.cool(address(game));
        vm.cool(address(sdgnrs));
        vm.cool(address(coinflip));
        vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.GAME_AFKING_MODULE);
        vm.cool(ContractAddresses.GAME_LOOTBOX_MODULE);
        vm.cool(ContractAddresses.GAME_MINT_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE);
        vm.cool(ContractAddresses.GAME_BOON_MODULE);
        vm.cool(ContractAddresses.GAME_DEGENERETTE_MODULE);
    }

    function testFuzz_ColdWholeClaimFitsItsReservation(uint256 word, uint16 rollSeed, uint8 fundingMode) public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        uint16 roll = uint16(25 + uint256(rollSeed) % 151);
        _resolve(day, roll, word > 1 ? word : 99);
        if (fundingMode % 3 != 0) {
            uint256 reserve = sdgnrs.pendingRedemptionEthValue();
            uint256 ethPart = fundingMode % 3 == 1 ? 0 : reserve / 7;
            vm.deal(address(sdgnrs), ethPart);
            mockStETH.mint(address(sdgnrs), reserve - ethPart);
        }
        _coolSettlementState();
        vm.prank(address(game));
        uint256 beforeGas = gasleft();
        bool done = sdgnrs.runRedemptionWork(9_000_000).done;
        uint256 used = beforeGas - gasleft() + 21_000;
        assertTrue(done);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        uint256 chunks = ((uint256(160 ether) * uint256(roll) / 100) / 2 + 5 ether - 1) / 5 ether;
        assertLe(used, 350_000 + chunks * 250_000 + 80_000, "whole beneficiary fits admission bound");
    }

    function test_ColdMaxBeneficiaryThroughRouter() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        (uint96 base,,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        uint256 used = _coldRouterGas();
        emit log_named_uint("cold_maximum_redemption_router_gas", used);
        // Per-chunk: the maximum beneficiary is one indivisible chunk whose declared admission
        // bound stays inside the 10M realistic chunk limit (its actual cost is pinned against the
        // bound by testFuzz_ColdWholeClaimFitsItsReservation).
        assertLe(
            GasBounds.REDEMPTION_BASE_GAS + 28 * GasBounds.REDEMPTION_CHUNK_GAS + GasBounds.REDEMPTION_TAIL_GAS,
            uint256(10_000_000),
            "maximum beneficiary chunk bound"
        );
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "real maximum claim settled");
    }
    function _queueBurners(uint256 n, uint256 amount) private returns (address[] memory players) {
        players = new address[](n);
        for (uint256 i; i < n; ++i) {
            players[i] = address(uint160(0xC01000 + i));
            vm.prank(address(game));
            assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[i], amount), amount);
            _burn(players[i], amount);
        }
    }

    /// @dev One cold keeper call with a realistic 10M allowance: it must succeed and make progress.
    ///      The engine keeps admitting chunks while the allowance covers the next declared bound, so
    ///      the whole call's gas is reported, not bounded; per-chunk bounds are asserted separately.
    function _coldRouterGas() private returns (uint256 used) {
        _coolSettlementState();
        uint256 beforeGas = gasleft();
        game.mineFlip{gas: 10_000_000}();
        used = beforeGas - gasleft() + 21_000;
    }

    function test_ColdMultipleMaximumBeneficiariesAndContinuation() public {
        uint24 day = game.currentDayView();
        address[] memory players = _queueBurners(3, sdgnrs.totalSupply() * 16 / 1000);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_two_maximum_router_gas", _coldRouterGas());
        (uint96 base,,) = sdgnrs.pendingRedemptions(players[2], day);
        assertGt(base, 0, "next beneficiary remains whole");
        assertTrue(sdgnrs.redemptionSettlementPending());
        emit log_named_uint("cold_maximum_continuation_router_gas", _coldRouterGas());
        if (sdgnrs.redemptionSettlementPending()) _coldRouterGas();
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_ColdManyMinimumBeneficiaries() public {
        uint24 day = game.currentDayView();
        _queueBurners(45, 1 ether);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_45_dust_router_gas", _coldRouterGas());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

    function test_ColdMaximumMiddleOfMixedBatch() public {
        uint24 day = game.currentDayView();
        address[] memory players = _queueBurners(3, 1 ether);
        (uint96 prior,,) = sdgnrs.pendingRedemptions(players[1], day);
        uint256 supply = sdgnrs.totalSupply();
        (uint256 freeBacking,) = sdgnrs.previewBurnValue(supply);
        uint256 topup = ((160 ether - prior) * supply + freeBacking - 1) / freeBacking;
        vm.prank(address(game));
        assertEq(sdgnrs.transferFromPool(sDGNRS.Pool.Whale, players[1], topup), topup);
        _burn(players[1], topup);
        (uint96 base,,) = sdgnrs.pendingRedemptions(players[1], day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        emit log_named_uint("cold_mixed_batch_maximum_middle_gas", _coldRouterGas());
        assertFalse(sdgnrs.redemptionSettlementPending());
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function test_ColdLongManuallyClaimedCohortClearsInConstantTime() public {
        uint24 day = game.currentDayView();
        address[] memory players = _queueBurners(2000, 1 ether);
        _resolve(day, 100, 99);
        for (uint256 i; i < players.length; ++i) sdgnrs.claimRedemption(players[i], day);
        assertTrue(sdgnrs.redemptionSettlementPending(), "metadata cleanup remains owed");
        uint256 used = _coldRouterGas();
        emit log_named_uint("cold_2000_manual_claim_cleanup_router_gas", used);
        assertLe(used, 500_000, "cleanup must not rescan already-consumed beneficiaries");
        assertFalse(sdgnrs.redemptionSettlementPending());
    }

}
