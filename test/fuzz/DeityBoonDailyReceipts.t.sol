// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameBoonModule} from "../../contracts/modules/DegenerusGameBoonModule.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract MultipleBoonRngSeeder is DegenerusGameStorage {
    function seed(uint24 day) external { _recordDailyRng(day - 1, 0xCAFE + day); }
}

/// @dev Real pass purchases allocate distinct deity ordinals. Gifts retain their
///      per-deity slot masks and lifetime counters while sharing a recipient day.
contract DeityBoonDailyReceiptsTest is DeployProtocol {
    address private constant DEITY_A = address(0xDE17A);
    address private constant DEITY_B = address(0xDE17B);
    address private constant RECIPIENT = address(0xB001);
    address private constant OTHER = address(0xB002);
    uint32 private a;
    uint32 private b;
    uint32 private recipient;
    uint32 private other;

    function setUp() public {
        _deployProtocol();
        vm.deal(DEITY_A, 100 ether);
        vm.deal(DEITY_B, 100 ether);
        vm.prank(DEITY_A);
        game.purchaseDeityPass{value: 24 ether}(0, 1, bytes32(0));
        vm.prank(DEITY_B);
        game.purchaseDeityPass{value: 25 ether}(0, 2, bytes32(0));
        a = game.walletIdOf(DEITY_A);
        b = game.walletIdOf(DEITY_B);
        recipient = _giveWalletId(RECIPIENT);
        other = _giveWalletId(OTHER);
        _day(41);
    }

    function _day(uint24 day) private {
        vm.warp((uint256(day - 1) + ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621);
        bytes memory code = address(game).code;
        vm.etch(address(game), type(MultipleBoonRngSeeder).runtimeCode);
        MultipleBoonRngSeeder(address(game)).seed(day);
        vm.etch(address(game), code);
    }

    function _give(address owner, uint32 deity, uint32 to, uint8 slot) private {
        vm.prank(owner);
        game.issueDeityBoon(deity, to, slot);
    }

    function test_SixSameDayGiftsFromTwoDeities() public {
        for (uint8 slot; slot < 3; ++slot) {
            _give(DEITY_A, a, recipient, slot);
            _give(DEITY_B, b, recipient, slot);
        }
        (,, uint8 maskA,,) = game.deityBoonData(DEITY_A);
        (,, uint8 maskB,,) = game.deityBoonData(DEITY_B);
        assertEq(maskA, 7);
        assertEq(maskB, 7);
    }

    function test_SlotReuseStillFailsAndNextDayResetsIt() public {
        _give(DEITY_A, a, recipient, 0);
        vm.expectRevert(DegenerusGameBoonModule.SlotAlreadyUsed.selector);
        _give(DEITY_A, a, other, 0);
        _give(DEITY_A, a, recipient, 1);
        _day(42);
        _give(DEITY_A, a, recipient, 0);
    }

    function test_SelfBoonStillFails() public {
        vm.expectRevert(DegenerusGameBoonModule.SelfBoon.selector);
        _give(DEITY_A, a, a, 0);
    }

    function test_TenthGiftExhaustsOnlyItsLifetimePair() public {
        for (uint24 day = 41; day < 44; ++day) {
            _day(day);
            for (uint8 slot; slot < 3; ++slot) _give(DEITY_A, a, recipient, slot);
        }
        _day(44);
        _give(DEITY_A, a, recipient, 0);
        vm.expectRevert(DegenerusGameBoonModule.RecipientBoonCapReached.selector);
        _give(DEITY_A, a, recipient, 1);
        _give(DEITY_A, a, other, 1);
        _give(DEITY_B, b, recipient, 0);
        _day(45);
        vm.expectRevert(DegenerusGameBoonModule.RecipientBoonCapReached.selector);
        _give(DEITY_A, a, recipient, 0);
    }
}
