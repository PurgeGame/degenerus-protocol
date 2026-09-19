// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";

/// @notice Two free genesis passes plus thirty paid passes; doubling starts after 300 ETH.
contract DeityPassPriceCurve is DeployProtocol {
    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    function _expected(uint256 sold) private pure returns (uint256) {
        if (sold <= 23) return 24 ether + (sold * (sold + 1) * 1 ether) / 2;
        return 300 ether << (sold - 23);
    }

    function testThirtyPaidPassesExcludeGenesisAndFollowTheCurve() public {
        uint256 total;
        for (uint256 n = 0; n < 30; ++n) {
            address who = makeAddr(string.concat("deity", vm.toString(n)));
            uint256 price = _expected(n);
            vm.deal(who, price);
            vm.prank(who);
            game.purchaseDeityPass{value: price}(who, uint8(n < 5 ? n + 1 : n + 2), bytes32(0));
            assertEq(game.afkingFundingOf(who), 0, string.concat("exact price at n=", vm.toString(n)));
            assertEq(who.balance, 0, "the whole payment was taken");
            total += price;
        }
        assertEq(_expected(0), 24 ether, "first pass");
        assertEq(_expected(23), 300 ether, "24th paid pass anchor");
        assertEq(_expected(24), 600 ether, "25th doubles");
        assertEq(_expected(29), 19_200 ether, "30th paid pass");
        assertEq(total, 40_676 ether, "2,876 triangular plus 37,800 doubling");
        assertEq(deityPass.ownerOf(0), address(vault));
        assertEq(deityPass.ownerOf(6), address(sdgnrs));
    }
}
