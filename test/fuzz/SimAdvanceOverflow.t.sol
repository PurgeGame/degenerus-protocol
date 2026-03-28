// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

contract SimAdvanceOverflow is DeployProtocol {
    function setUp() public {
        // Use the sim's actual timestamp range instead of 86400
        vm.warp(1774654000); // ~March 27 2026, before 22:57 UTC
        _deployProtocol();
    }

    function test_dayCalcSanity() public view {
        uint48 day = GameTimeLib.currentDayIndex();
        // With DEPLOY_DAY_BOUNDARY = 0 and ts = 1774654000:
        // boundary = (1774654000 - 82620) / 86400 = 20538
        // day = 20538 - 0 + 1 = 20539
        // This is fine for DEPLOY_DAY_BOUNDARY = 0 but would be 1 for a matching boundary
        assert(day > 0);
    }

    function test_simAdvanceWithRealTimestamp() public {
        for (uint i = 0; i < 100; i++) {
            address buyer = address(uint160(0x1000 + i));
            vm.deal(buyer, 10 ether);
            vm.prank(buyer);
            game.purchase{value: 1 ether}(buyer, 400, 0.5 ether, bytes32(0), MintPaymentKind.DirectEth);
        }
        vm.warp(block.timestamp + 1 days + 1861);
        game.advanceGame();
    }
}
