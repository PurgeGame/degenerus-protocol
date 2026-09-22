// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import "forge-std/Test.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

contract TicketLensHarness is DegenerusGameStorage {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly { value := sload(slot) }
    }
    function append(uint24 lvl, uint8 trait, uint32 ownerIdx, uint32 count) external {
        uint256 base;
        assembly { base := lvlTraitEntry.slot }
        _bucketAppendRun(uint256(keccak256(abi.encode(lvl, base))), trait, ownerIdx, count);
    }
    function appendQueue(uint24 key, uint32 pos) external { _tqAppend(key, pos); }
}

contract TicketLensTest is Test {
    DegenerusGameLens lens;
    TicketLensHarness game;
    function setUp() public { lens = new DegenerusGameLens(); game = new TicketLensHarness(); }
    function testFuzzFindAcrossPackedBoundary(uint8 preceding, uint8 suffix, uint32 target) public {
        target = uint32(bound(target, 1, type(uint32).max));
        game.append(7, 0, 0, uint32(preceding) + 1);
        game.append(7, 0, target, 1);
        game.append(7, 0, 0, uint32(suffix) + 1);
        uint32[] memory ids = new uint32[](1); ids[0] = target;
        uint32 cursor;
        bool found;
        uint32 position;
        for (uint256 i; i < 34; ++i) {
            uint32 next;
            (found, position, next,) = lens.findTraitEntry(address(game), 7, 0, ids, cursor, 1);
            assertLe(next - cursor, 8);
            if (found) break;
            assertGt(next, cursor); cursor = next;
        }
        assertTrue(found); assertEq(position, uint32(preceding) + 1);
    }
    function testZeroOwnerAndTailLanes() public {
        game.append(3, 255, 99, 9);
        uint32[] memory ids = new uint32[](2); ids[0] = 0; ids[1] = 100;
        (bool found,, uint32 next, uint32 total) = lens.findTraitEntry(address(game), 3, 255, ids, 1, 2);
        assertFalse(found); assertEq(next, 9); assertEq(total, 9);
        game.append(3, 255, 0, 1);
        uint32 position;
        (found, position,,) = lens.findTraitEntry(address(game), 3, 255, ids, 9, 1);
        assertTrue(found); assertEq(position, 9);
    }
    function testQueueAndBudgetLimits() public {
        for (uint32 i = 1; i <= 17; ++i) game.appendQueue(0x400010, i);
        (bool found,, uint32 next,) = lens.findQueueEntry(address(game), 0x400010, 17, 0, 1);
        assertFalse(found); assertEq(next, 8);
        uint32 position;
        (found, position,,) = lens.findQueueEntry(address(game), 0x400010, 17, 16, 1);
        assertTrue(found); assertEq(position, 16);
        vm.expectRevert(bytes("page")); lens.findQueueEntry(address(game), 0x400010, 17, 0, 0);
        vm.expectRevert(bytes("page")); lens.findQueueEntry(address(game), 0x400010, 17, 0, 2049);
    }
}
