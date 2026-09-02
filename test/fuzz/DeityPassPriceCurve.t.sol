// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @title Deity pass price curve
/// @notice The nth deity pass (n passes already sold) costs 24 + n(n+1)/2 ETH through the 27th
///         pass (n = 26, 375 ETH); every later pass doubles the one before it, so the 28th is
///         750 ETH and the 32nd 12,000 ETH. Pinned through the production purchase: each buyer
///         pays the expected price exactly, so a higher live price would revert on the
///         shortfall and a lower one would leave the excess in the payer's afking funding.
contract DeityPassPriceCurve is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _expected(uint256 sold) private pure returns (uint256) {
        if (sold <= 26) return 24 ether + (sold * (sold + 1) * 1 ether) / 2;
        return 375 ether << (sold - 26);
    }

    function testAllThirtyTwoPassesFollowTheCurve() public {
        uint256 total;
        for (uint256 n = 0; n < 32; ++n) {
            address who = makeAddr(string.concat("deity", vm.toString(n)));
            uint256 price = _expected(n);
            vm.deal(who, price);
            vm.prank(who);
            game.purchaseDeityPass{value: price}(who, uint8(n), bytes32(0));
            assertEq(game.afkingFundingOf(who), 0, string.concat("exact price at n=", vm.toString(n)));
            assertEq(who.balance, 0, "the whole payment was taken");
            total += price;
        }
        assertEq(_expected(0), 24 ether, "first pass");
        assertEq(_expected(26), 375 ether, "27th pass is the anchor");
        assertEq(_expected(27), 750 ether, "28th doubles the anchor");
        assertEq(_expected(31), 12_000 ether, "32nd pass");
        assertEq(total, 27_174 ether, "curve total: 3,924 triangular + 23,250 doubling");
    }
}
