// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {AutomaticRedemptionSettlementTest} from "../fuzz/AutomaticRedemptionSettlement.t.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

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
        (bool done, uint256 charged,) = sdgnrs.processRedemptionSettlement(1856);
        uint256 used = beforeGas - gasleft() + 21_000;
        assertTrue(done);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        assertLe(used, charged * 4700, "cold whole-claim gas within stored-state reservation");
    }

    function test_ColdMaxBeneficiaryThroughRouter() public {
        uint24 day = game.currentDayView();
        _burn(alice, sdgnrs.totalSupply() * 16 / 1000);
        (uint96 base,,) = sdgnrs.pendingRedemptions(alice, day);
        assertEq(base, 160 ether);
        _resolve(day, 175, 99);
        _coolSettlementState();
        uint256 beforeGas = gasleft();
        game.mineFlip();
        uint256 used = beforeGas - gasleft() + 21_000;
        emit log_named_uint("cold_maximum_redemption_router_gas", used);
        assertLe(used, 10_000_000, "unchanged target ceiling");
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

    function _coldRouterGas() private returns (uint256 used) {
        _coolSettlementState();
        uint256 beforeGas = gasleft();
        game.mineFlip();
        used = beforeGas - gasleft() + 21_000;
        assertLe(used, 10_000_000, "full composed router below target");
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
