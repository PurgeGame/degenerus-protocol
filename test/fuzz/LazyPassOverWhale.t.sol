// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {TicketQueueStorage as TQ} from "./helpers/TicketQueueStorage.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGameWhaleModule} from "../../contracts/modules/DegenerusGameWhaleModule.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";
import {GameSlotKeys} from "../helpers/GameSlots.sol";

/// @title LazyPassOverWhale
/// @notice The freeze carries one pass type. A lazy pass may not extend an active whale pass (its
///         levels would take the whale bonus), and a lazy pass over a lapsed whale record is plain
///         lazy coverage.
contract LazyPassOverWhale is DeployProtocol {
    uint256 private constant LEVEL_OFFBYTES = 12; // `level` uint24 @ slot 0, byte 12
    address private alice = address(0xA11CE);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        _giveWalletId(alice);
        vm.deal(alice, 10 ether);
    }

    function _setPass(uint8 passType, uint24 frozenUntil) private {
        bytes32 slot = GameSlotKeys.mintPacked(game.walletIdOf_g3120(alice));
        uint256 word = uint256(vm.load(address(game), slot));
        word &= ~(uint256(3) << BitPackingLib.WHALE_PASS_TYPE_SHIFT);
        word &= ~(BitPackingLib.MASK_24 << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT);
        word |= uint256(passType) << BitPackingLib.WHALE_PASS_TYPE_SHIFT;
        word |= uint256(frozenUntil) << BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT;
        vm.store(address(game), slot, bytes32(word));
    }

    function _pass() private view returns (uint8 passType, uint24 frozenUntil) {
        uint256 word = game.mintPackedFor(alice);
        passType = uint8((word >> BitPackingLib.WHALE_PASS_TYPE_SHIFT) & 3);
        frozenUntil = uint24((word >> BitPackingLib.FROZEN_UNTIL_LEVEL_SHIFT) & BitPackingLib.MASK_24);
    }

    function _setLevel(uint24 lvl) private {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        if (lvl > uint24(s0 >> (LEVEL_OFFBYTES * 8))) TQ.retireCompleted(address(game), lvl + 1);
        s0 &= ~(uint256(0xFFFFFF) << (LEVEL_OFFBYTES * 8));
        s0 |= uint256(lvl) << (LEVEL_OFFBYTES * 8);
        vm.store(address(game), bytes32(uint256(0)), bytes32(s0));
    }

    function _buyLazy() private {
        vm.prank(alice);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
    }

    /// @dev An active whale pass inside the renewal window: the lazy pass would extend it.
    function test_lazyPassRefusedOverActiveWhalePass() public {
        _setPass(3, 5);
        vm.prank(alice);
        vm.expectRevert(DegenerusGameWhaleModule.PassNotExpired.selector);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
        (uint8 passType, uint24 frozenUntil) = _pass();
        assertEq(passType, 3, "whale pass untouched");
        assertEq(frozenUntil, 5, "freeze not extended");
    }

    /// @dev The whale pass's last level is still active: refused, even though the lazy pass starts next level.
    function test_lazyPassRefusedOnWhalePassLastLevel() public {
        _setLevel(2);
        _setPass(3, 2);
        vm.prank(alice);
        vm.expectRevert(DegenerusGameWhaleModule.PassNotExpired.selector);
        game.purchaseLazyPass{value: 1 ether}(0, bytes32(0));
    }

    /// @dev A lapsed whale record (no mint since it ended) leaves type 3 stored; the lazy pass replaces it.
    function test_lazyPassOverLapsedWhaleRecordIsLazyCoverage() public {
        _setLevel(2);
        _setPass(3, 1);
        _buyLazy();
        (uint8 passType, uint24 frozenUntil) = _pass();
        assertEq(passType, 1, "lazy coverage carries the lazy type");
        assertEq(frozenUntil, 12, "ten levels from level 3");
    }

    /// @dev Lazy over lazy keeps the ordinary renewal window.
    function test_lazyRenewalOverActiveLazyPass() public {
        _setPass(1, 5);
        _buyLazy();
        (uint8 passType, uint24 frozenUntil) = _pass();
        assertEq(passType, 1);
        assertEq(frozenUntil, 10, "ten levels from level 1");
    }
}
