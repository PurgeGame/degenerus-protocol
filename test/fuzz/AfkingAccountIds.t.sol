// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {GameAfkingModule} from "../../contracts/modules/GameAfkingModule.sol";

contract AfkingIdSetHarness is GameAfkingModule {
    function add(address owner, bool tickets) external returns (uint32 id) {
        (id,) = _registerWallet(owner, 0);
        _insertMember(id, uint256(id) | (tickets ? SUB_TICKETS_BIT : 0), 7);
    }
    function remove(uint256 position1) external {
        uint32 id = _subscriberAt(position1 - 1);
        _removeFromSet(position1);
        _setSubMetaLane(id, 0);
    }
    function laneAt(uint256 position) external view returns (uint256) { return _subLaneAt(position); }
    function position1(uint32 id) external view returns (uint256) { return _subPosition1(id); }
    function runStart(uint32 id) external view returns (uint24) { return _subRunStart(id); }
    function root() external pure returns (uint256 r) { assembly { r := _subscribers.slot } }
    function encode(uint256 score) external pure returns (uint256) { return _encodeSubScore(score); }
    function decode(uint256 code) external pure returns (uint16) { return _decodeSubScore(code); }
    function checkpoint(uint256 lane, uint256 day, uint256 streak) external pure returns (uint256) {
        return _withSubCheckpoint(lane, day, streak);
    }
}

contract AfkingIdPackingTest is Test {
    uint256 private constant LANE = (uint256(1) << 85) - 1;

    function _word(AfkingIdSetHarness h, uint256 index) private view returns (uint256) {
        return uint256(vm.load(address(h), bytes32(uint256(keccak256(abi.encode(h.root()))) + index)));
    }

    function testFuzz_ThreeLanesPerWordAndSwapPopPreservesNeighbors(uint8 positionSeed) public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        for (uint32 i = 1; i <= 9; ++i) assertEq(h.add(address(uint160(i)), false), i);
        for (uint256 w; w < 3; ++w) {
            uint256 expected;
            for (uint256 k; k < 3; ++k) expected |= uint256(w * 3 + k + 1) << (k * 85);
            assertEq(_word(h, w), expected, "three lanes per word");
        }
        assertEq(uint256(vm.load(address(h), bytes32(h.root()))), 9, "logical length");

        uint256 position1 = uint256(positionSeed % 8) + 1;
        uint256 before = _word(h, (position1 - 1) / 3);
        h.remove(position1);
        uint256 shift = ((position1 - 1) % 3) * 85;
        uint256 expected = (before & ~(LANE << shift)) | (uint256(9) << shift);
        // The tail (position 8) shares word 2 with positions 6 and 7; its lane is cleared.
        if ((position1 - 1) / 3 == 2) expected &= ~(LANE << 170);
        assertEq(_word(h, (position1 - 1) / 3), expected, "neighbors kept");
        assertEq(h.laneAt(8), 0, "tail lane cleared");
        assertEq(h.position1(9), position1, "mover's lookup follows it");
        assertEq(h.position1(uint32(position1)), 0, "removed member's lookup cleared");
        assertEq(h.runStart(9), 7, "mover keeps its run start");
        for (uint256 p; p < 8; ++p) assertEq(h.position1(uint32(h.laneAt(p))), p + 1);
    }

    function test_TicketSectionDescendsFromTheCap() public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        h.add(address(1), false);
        uint32 t1 = h.add(address(2), true);
        uint32 t2 = h.add(address(3), true);
        uint32 t3 = h.add(address(4), true);
        assertEq(h.position1(t1), 2001);
        assertEq(h.position1(t2), 2000);
        assertEq(h.position1(t3), 1999);
        // 1998..2000 share word 666; removing the newest ticket clears its lane only.
        h.remove(2001);
        assertEq(h.position1(t3), 2001, "ticket tail moved to the head");
        assertEq(uint32(h.laneAt(2000)), t3);
        assertEq(h.laneAt(1998), 0);
        assertEq(uint32(h.laneAt(1999)), t2);
        assertEq(uint32(h.laneAt(0)), 1, "box section untouched");
    }

    function testFuzz_CheckpointRewriteSaturatesAndKeepsOtherFields(uint256 lane, uint24 day, uint32 streak) public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        lane &= LANE;
        uint256 d = day & ((uint256(1) << 22) - 1);
        uint256 out = h.checkpoint(lane, d, streak);
        assertEq((out >> 46) & ((uint256(1) << 22) - 1), d, "day written");
        assertEq(out >> 69, streak > 0xffff ? 0xffff : streak, "streak saturates");
        uint256 kept = LANE & ~(((uint256(1) << 22) - 1) << 46) & ~(uint256(0xffff) << 69);
        assertEq(out & kept, lane & kept, "id, quantity, mode, score and removal bit kept");
        assertEq(out >> 85, 0, "stays inside its lane");
    }

    function testFuzz_ScoreCodeExactThroughKneeThenRoundsDown(uint16 score) public {
        AfkingIdSetHarness h = new AfkingIdSetHarness();
        uint256 code = h.encode(score);
        assertLe(code, 961);
        uint256 decoded = h.decode(code);
        if (score <= 500) assertEq(decoded, score);
        else if (score >= 30_000) assertEq(decoded, 30_000);
        else {
            assertLe(decoded, score);
            assertLt(score - decoded, 64);
        }
        assertEq(h.encode(decoded), code, "decode is a fixed point");
    }
}
