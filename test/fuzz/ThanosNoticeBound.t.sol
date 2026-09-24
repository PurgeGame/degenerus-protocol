// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title ThanosNoticeBound — setThanosLevel's 3-level notice and lock
/// @notice A level X first materializes at level X-1's last-purchase seal, while `level == X-2`:
///         the seal lifts the mint ceiling to level + 2 = X, so X's frozen far-future pool and
///         its write buffer mint on the first swap after it. A declaration must therefore land
///         while level <= X-3 and must freeze from level X-2 on. These tests pin both edges.
/// @dev Shift 0 skips the SNAP_FLOOR_ENTRIES projection, so the bounds are the only gate under
///      test. `level` is poked (slot 0, byte 12) and snapLevel read back (slot 14, byte 8) at
///      the offsets in scripts/layout/golden/DegenerusGame.json; the layout oracle fails the
///      build on a move.
contract ThanosNoticeBound is DeployProtocol {
    uint256 private constant LEVEL_SLOT = 0;
    uint256 private constant LEVEL_BYTE = 12;
    uint256 private constant SNAP_SLOT = 14;
    uint256 private constant SNAP_LEVEL_BYTE = 8;

    uint24 private constant L = 20;

    address private owner;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        owner = ContractAddresses.CREATOR;
        require(vault.isVaultOwner(owner), "harness: CREATOR is not the vault owner");
        _forceLevel(L);
        assertEq(game.level(), L, "level poke did not land");
    }

    function _forceLevel(uint24 lvl) internal {
        uint256 cur = uint256(vm.load(address(game), bytes32(LEVEL_SLOT)));
        cur &= ~(uint256(0xffffff) << (LEVEL_BYTE * 8));
        cur |= uint256(lvl) << (LEVEL_BYTE * 8);
        vm.store(address(game), bytes32(LEVEL_SLOT), bytes32(cur));
    }

    function _snapLevel() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(SNAP_SLOT))) >> (SNAP_LEVEL_BYTE * 8));
    }

    function _declare(uint24 target) internal returns (bool ok) {
        vm.prank(owner);
        (ok, ) = address(game).call(abi.encodeWithSignature("setThanosLevel(uint24,uint8)", target, uint8(0)));
    }

    function testNoticeIsThreeLevels() public {
        assertFalse(_declare(L + 2), "level + 2 materializes at this level's seal; must revert");
        assertEq(_snapLevel(), 0, "rejected declaration left state");
        assertTrue(_declare(L + 3), "level + 3 is the earliest legal target");
        assertEq(_snapLevel(), L + 3, "declaration did not land");
    }

    function testSharedOwnerGuardRejectsNonOwnerOnEveryControl() public {
        vm.startPrank(address(0xBAD));
        bytes4 onlyVault = bytes4(keccak256("OnlyVault()"));
        vm.expectRevert(onlyVault);
        game.setLootboxRngThreshold(1 ether);
        vm.expectRevert(onlyVault);
        game.setMiddayMaxBasefee(2);
        vm.expectRevert(onlyVault);
        game.setThanosLevel(L + 3, 0);
        vm.expectRevert(onlyVault);
        game.adminStakeEthForStEth(1 ether);
        vm.stopPrank();
    }

    function testPendingDeclarationMovableUntilTargetMinusTwo() public {
        uint24 target = L + 3;
        assertTrue(_declare(target), "declare");
        // level == target - 3: nothing of target can mint yet (ceiling <= target - 1).
        assertTrue(_declare(target + 1), "still movable three levels out");
        assertEq(_snapLevel(), target + 1, "move did not land");
    }

    function testPendingDeclarationLocksAtTargetMinusTwo() public {
        uint24 target = L + 3;
        assertTrue(_declare(target), "declare");
        // level == target - 2: target's pool can mint at this level's seal, so the pair locks.
        _forceLevel(target - 2);
        assertFalse(_declare(target + 5), "a pending declaration must lock at target - 2");
        assertEq(_snapLevel(), target, "locked declaration moved");
    }
}
