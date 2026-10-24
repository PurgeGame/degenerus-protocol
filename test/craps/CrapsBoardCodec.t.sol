// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsBattle} from "../../contracts/CrapsBattle.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsLensReader} from "../../contracts/CrapsLens.sol";

contract BoardCodecProbe is CrapsBattle {
    function check(uint32 board)
        external
        pure
        returns (uint256 count, uint256 compact, uint32 decoded, uint256 placed)
    {
        (, count) = _packChips(board);
        compact = CrapsPreferenceLib.compress(board);
        (decoded, placed) = CrapsPreferenceLib.decode(compact << CrapsPreferenceLib.SHIFT);
    }
}

contract CrapsBoardCodecTest is Test {
    BoardCodecProbe private probe;
    uint256 private visited;
    uint256 private previous;

    function setUp() public {
        probe = new BoardCodecProbe();
    }

    function test_IndependentLiteralLayout() public pure {
        assertEq(CrapsPreferenceLib.PASS_SLOT, 9);
        assertEq(CrapsLensReader.PASS_CREDITS_SLOT, 9);
        assertEq(CrapsPreferenceLib.MASK, uint256(0x1FFFFF) << 64);
        assertEq(CrapsPreferenceLib.INITIALIZED, uint256(1) << 85);
        assertEq(CrapsPreferenceLib.ID_SHIFT, 86);
        assertEq(CrapsPreferenceLib.RETAINED, uint256(1) << 118);
        assertEq(JackpotBattleFieldLib.BOARD_SHIFT, 160);
        assertEq(JackpotBattleFieldLib.UNITS_SHIFT, 181);
    }

    function test_All14015LegalBoardsRoundTripAndKeepPreviousCompactBits() public {
        _enumerate(0, 7, 0);
        assertEq(visited, 14_015);
        assertGt(previous, 0);
    }

    function testFuzz_PackedValidatorMatchesIndependentCounts(uint32 board) public {
        uint256 sum;
        uint256 remaining = board;
        uint256[10] memory counts;
        bool overCap;
        for (uint256 leg; leg < 10; ++leg) {
            counts[leg] = remaining % 8;
            remaining /= 8;
            sum += counts[leg];
            if (counts[leg] > (leg == 9 ? 5 : 3)) overCap = true;
        }
        bytes4 error;
        if (remaining != 0) error = CrapsBattleStorage.BadRandomCount.selector;
        else if (counts[0] != 0 && counts[9] != 0) error = CrapsBattleStorage.BoardPlaysBothSides.selector;
        else if (overCap) error = CrapsBattleStorage.TooManyChipsOnALeg.selector;
        if (error != bytes4(0)) {
            vm.expectRevert(error);
            probe.check(board);
        } else {
            (uint256 counted,, uint32 decoded, uint256 placed) = probe.check(board);
            assertEq(counted, sum);
            assertEq(placed, sum);
            assertEq(decoded, board);
        }
    }

    // Independent lane-by-lane enumeration: no production masks or packed-sum formula.
    function _enumerate(uint256 leg, uint256 left, uint32 board) private {
        if (leg == 10) {
            if ((board & 7) != 0 && (board >> 27) != 0) return;
            uint256 sum;
            uint256 oldCompact;
            for (uint256 i; i < 10; ++i) {
                uint256 count = (board >> (i * 3)) & 7;
                sum += count;
                oldCompact |= (count & 3) << (i * 2);
            }
            (uint256 counted, uint256 compact, uint32 decoded, uint256 placed) = probe.check(board);
            assertEq(counted, sum);
            assertEq(placed, sum);
            assertEq(decoded, board);
            if (board >> 27 <= 3) {
                assertEq(compact, oldCompact);
                ++previous;
            }
            ++visited;
            return;
        }
        uint256 cap = leg == 9 ? 5 : 3;
        for (uint256 n; n <= cap && n <= left; ++n) {
            _enumerate(leg + 1, left - n, board | uint32(n << (leg * 3)));
        }
    }
}
