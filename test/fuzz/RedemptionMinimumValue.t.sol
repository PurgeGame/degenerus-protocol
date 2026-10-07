// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RedemptionFixture} from "./helpers/RedemptionFixture.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";

contract RedemptionMinimumValueTest is RedemptionFixture {
    function test_OneMillionthTokenCanMeetValueMinimum() public {
        uint256 amount = 1e6;
        (uint256 gross, ) = sdgnrs.previewBurnValue(sdgnrs.totalSupply());
        uint256 target = 0.01 ether * sdgnrs.totalSupply() / amount;
        vm.deal(address(sdgnrs), address(sdgnrs).balance + target - gross);
        (uint256 value, ) = sdgnrs.previewBurnValue(amount);
        assertEq(value, 0.01 ether);
        vm.prank(alice); sdgnrs.burn(amount);
        (, , , uint256 escrow) = sdgnrs.redemptionBatchState();
        assertEq(escrow, amount);
    }
    function test_OneWeiBelowValueMinimumRejectsWithoutBurn() public {
        uint256 amount = 1e6;
        (uint256 gross, ) = sdgnrs.previewBurnValue(sdgnrs.totalSupply());
        uint256 target = 0.01 ether * sdgnrs.totalSupply() / amount;
        vm.deal(address(sdgnrs), address(sdgnrs).balance + target - gross - 1);
        (uint256 value, ) = sdgnrs.previewBurnValue(amount);
        assertEq(value, 0.01 ether - 1);
        uint256 supply = sdgnrs.totalSupply();
        vm.prank(alice); vm.expectRevert(sDGNRS.BurnTooSmall.selector); sdgnrs.burn(amount);
        assertEq(sdgnrs.totalSupply(), supply);
    }
    function test_EachTopupMustMeetMinimumIndependently() public {
        uint256 amount = sdgnrs.balanceOf(alice) / 100;
        vm.prank(alice); sdgnrs.burn(amount);
        vm.prank(alice); vm.expectRevert(sDGNRS.BurnTooSmall.selector); sdgnrs.burn(1);
    }
    function test_GameOverStillAllowsPositiveDustBurn() public {
        _latchGameOver();
        vm.prank(alice); sdgnrs.burn(1);
    }
}
