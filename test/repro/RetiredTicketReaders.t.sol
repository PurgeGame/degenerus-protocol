// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract RetiredWhaleHarness is DegenerusGameWhaleModule {
    function seed(address deity, bool retired) external {
        for (uint8 i; i < 32; ++i) deityBySymbol[i] = deity;
        _setTicketBufferLevel(retired ? 3 : 1);
    }
    function awarded(address player) external view returns (uint256) { return whalePassClaims[player]; }
}
contract RetiredJackpotHarness is DegenerusGameJackpotModule {
    function seed(address deity, bool retired) external {
        for (uint8 i; i < 32; ++i) deityBySymbol[i] = deity;
        _setTicketBufferLevel(retired ? 3 : 1);
    }
    function credited(address player) external view returns (uint256) { return _claimableOf(player); }
}

contract RetiredTicketReadersTest is Test {
    address constant DEITY = address(0xDE17);
    function test_RetiredWhaleTicketLegRejectsEmptyDeityBuckets() public {
        RetiredWhaleHarness h = new RetiredWhaleHarness();
        h.seed(DEITY, true);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.awardWhalePass(1, 0, 2, 11, true);
        assertEq(h.awarded(DEITY), 0);
        h.seed(DEITY, false);
        h.awardWhalePass(1, 0, 2, 11, true);
        assertEq(h.awarded(DEITY), 2, "retirement guard must preserve a valid empty-deity draw");
    }
    function test_RetiredWhaleQuadrantRejectsEmptyDeityBucket() public {
        RetiredWhaleHarness h = new RetiredWhaleHarness();
        h.seed(DEITY, true);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.awardWhalePass(1, 0, 80 ether, 11, false);
        assertEq(h.awarded(DEITY), 0);
    }
    function test_RetiredJackpotTerminalPaysNobodyBeforeCachedLengthDeityDraw() public {
        RetiredJackpotHarness h = new RetiredJackpotHarness();
        h.seed(DEITY, true);
        vm.prank(ContractAddresses.GAME);
        assertEq(h.runTerminalJackpot(10 ether, 1, 11), 0, "retired level: every quadrant settles unpaid");
        assertEq(h.credited(DEITY), 0, "no empty-bucket deity draw on a retired level");
        h.seed(DEITY, false);
        vm.prank(ContractAddresses.GAME);
        h.runTerminalJackpot(10 ether, 1, 11);
        assertGt(h.credited(DEITY), 0, "valid deity draw reaches the cached-length sampler");
    }
}
