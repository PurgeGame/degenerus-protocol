// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {DegenerusGameJackpotModule} from "../../contracts/modules/DegenerusGameJackpotModule.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract RetiredWhaleHarness is DegenerusGameWhaleModule, WalletSeed {
    function seed(address deity, bool retired) external {
        for (uint8 i; i < 32; ++i) deityBySymbol[i] = _seedWallet(deity);
        _setTicketBufferLevel(retired ? 3 : 1);
    }
    function awarded(address player) external view returns (uint256) { return _halfPassesOf(player); }
}
contract RetiredJackpotHarness is DegenerusGameJackpotModule, WalletSeed {
    function seed(address deity, bool retired) external {
        for (uint8 i; i < 32; ++i) deityBySymbol[i] = _seedWallet(deity);
        _setTicketBufferLevel(retired ? 3 : 1);
    }
    function credited(address player) external view returns (uint256) { return _claimableOf(_walletIdOf(player)); }
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
        (, uint256 paid) = h.runTerminalJackpotWork(10 ether, 1, 11, gasleft());
        assertEq(paid, 0, "retired level: every quadrant settles unpaid");
        assertEq(h.credited(DEITY), 0, "no empty-bucket deity draw on a retired level");
        h.seed(DEITY, false);
        vm.prank(ContractAddresses.GAME);
        h.runTerminalJackpotWork(10 ether, 1, 11, gasleft());
        assertGt(h.credited(DEITY), 0, "valid deity draw reaches the cached-length sampler");
    }
}
