// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {Test} from "forge-std/Test.sol";
import {DegenerusGameJackpotDrawModule} from "../../contracts/modules/DegenerusGameJackpotDrawModule.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

contract JackpotBattleDrawHarness is DegenerusGameJackpotDrawModule, WalletSeed {
    function seed(uint24 target, address[] memory owners, bool gaps) external {
        for (uint256 i; i < owners.length; ++i) {
            // Queue positions need not equal registry positions (e.g. after a salvage swap).
            if (gaps) _seedWallet(address(uint160(0xDEAD0000 + i)));
            uint32 pos = _seedWallet(owners[i]);
            _tqAppend(_tqFarFutureKey(target), pos);
        }
    }

    function collect(uint24 ceiling, uint256 word, uint256 cursor, uint256 remaining)
        external view returns (address[] memory, uint256, bool)
    {
        (uint32[] memory ids, uint256 next, bool exhausted) =
            _collectJackpotChunkWithLevels(ceiling, word, cursor, remaining, _jackpotDrawLevels(ceiling, cursor));
        return (_keys(ids), next, exhausted);
    }

    function collectCached(uint24 ceiling, uint256 word, uint256 count)
        external view returns (address[] memory all, uint256 cursor)
    {
        JackpotDrawLevels memory snapshot = _jackpotDrawLevels(ceiling, 0);
        all = new address[](count);
        uint256 used;
        while (used < count) {
            (uint32[] memory ids, uint256 next, bool exhausted) =
                _collectJackpotChunkWithLevels(ceiling, word, cursor, count - used, snapshot);
            address[] memory seats = _keys(ids);
            require(!exhausted && seats.length != 0, "fixture must have eligible levels");
            cursor = next;
            for (uint256 i; i < seats.length; ++i) all[used++] = seats[i];
        }
    }

    function _keys(uint32[] memory ids) private view returns (address[] memory keys) {
        keys = new address[](ids.length);
        for (uint256 i; i < ids.length; ++i) keys[i] = _walletKey(ids[i]);
    }

    function queued(uint24 target) external view returns (address[] memory owners) {
        uint256[] storage queue = ticketQueue[_ticketQueueStorageKey(_tqFarFutureKey(target))];
        owners = new address[](_ticketQueueLength(_tqFarFutureKey(target)));
        for (uint256 i; i < owners.length; ++i) owners[i] = _walletKey(_tqPositionAt(queue, i));
    }
}

contract JackpotBattleDrawTest is Test {
    JackpotBattleDrawHarness private h;
    uint24 private constant CEILING = 40;

    function setUp() public { h = new JackpotBattleDrawHarness(); }

    function _owners(uint256 base, uint256 count) private pure returns (address[] memory owners) {
        owners = new address[](count);
        for (uint256 i; i < count; ++i) owners[i] = address(uint160(base + i));
    }

    /// @dev Scalar oracle: concatenate circular visits to plain address arrays. No production
    ///      cursor packing, queue storage, packed-word decoding or chunk logic is reused.
    function _oracle(address[][] memory levels, uint256 word, uint256 count)
        private pure returns (address[] memory expected)
    {
        expected = new address[](count);
        uint256 used;
        for (uint256 visit; used < count; ++visit) {
            uint256 entropy = uint256(keccak256(abi.encode(word, visit)));
            address[] memory owners = levels[entropy % levels.length];
            uint256 start = (entropy >> 128) % owners.length;
            for (uint256 j; j < owners.length && used < count; ++j) {
                expected[used++] = owners[(start + j) % owners.length];
            }
        }
    }

    function _draw(uint256 word, uint256 count, uint256 chunk)
        private view returns (address[] memory all, uint256 cursor)
    {
        all = new address[](count);
        uint256 used;
        while (used < count) {
            uint256 request = count - used;
            if (request > chunk) request = chunk;
            address[] memory seats;
            bool exhausted;
            (seats, cursor, exhausted) = h.collect(CEILING, word, cursor, request);
            assertFalse(exhausted);
            assertEq(seats.length, request < JackpotBattleFieldLib.MAX_CHUNK ? request : JackpotBattleFieldLib.MAX_CHUNK);
            for (uint256 i; i < seats.length; ++i) all[used++] = seats[i];
        }
    }

    function test_EmptyFieldAndOutOfRangeLevels() public {
        h.seed(CEILING, _owners(0x1000, 2), false);
        (address[] memory seats, uint256 cursor, bool exhausted) = h.collect(CEILING, 123, 0, 500);
        assertEq(seats.length, 0);
        assertEq(cursor, 0);
        assertTrue(exhausted);

        // Both excluded edges occupy the same recycled root. A live L queue must
        // reject L+100; check the upper edge in its own fresh storage instead.
        vm.expectRevert(bytes4(keccak256("E()")));
        h.seed(CEILING + 100, _owners(0x2000, 2), false);
        assertEq(h.queued(CEILING), _owners(0x1000, 2), "collision preserves the old queue");

        JackpotBattleDrawHarness upperEdge = new JackpotBattleDrawHarness();
        upperEdge.seed(CEILING + 100, _owners(0x2000, 2), false);
        (seats, cursor, exhausted) = upperEdge.collect(CEILING, 123, 0, 500);
        assertEq(seats.length, 0);
        assertEq(cursor, 0);
        assertTrue(exhausted);
    }

    function test_OneWalletFillsFiveHundredSeatsWithReplacement() public {
        h.seed(CEILING + 1, _owners(0x1000, 1), false);
        (address[] memory seats,) = _draw(123, 500, JackpotBattleFieldLib.MAX_CHUNK);
        for (uint256 i; i < seats.length; ++i) assertEq(seats[i], address(0x1000));
    }

    function test_WrapsUnalignedTailBeforeSelectingAnotherLevel() public {
        address[][] memory levels = new address[][](1);
        levels[0] = _owners(0x1000, 17);
        h.seed(CEILING + 1, levels[0], true);
        uint256 word = 1;
        while ((uint256(keccak256(abi.encode(word, uint256(0)))) >> 128) % 17 != 15) ++word;
        (address[] memory seats,) = _draw(word, 17, JackpotBattleFieldLib.MAX_CHUNK);
        assertEq(seats, _oracle(levels, word, 17));
        for (uint256 i; i < 17; ++i) assertEq(seats[i], levels[0][(15 + i) % 17]);
        assertEq(h.queued(CEILING + 1), levels[0], "drawing must not consume tickets");
    }

    function test_CanSelectTheSameLevelTwiceWhileAnotherIsEligible() public {
        address[][] memory levels = new address[][](2);
        levels[0] = _owners(0x1000, 3);
        levels[1] = _owners(0x2000, 5);
        h.seed(CEILING + 1, levels[0], false);
        h.seed(CEILING + 99, levels[1], false);
        uint256 word = 1;
        while (uint256(keccak256(abi.encode(word, uint256(0)))) % 2 != 0
            || uint256(keccak256(abi.encode(word, uint256(1)))) % 2 != 0) ++word;
        (address[] memory seats,) = _draw(word, 6, 2);
        assertEq(seats, _oracle(levels, word, 6));
        uint256[3] memory counts;
        for (uint256 i; i < seats.length; ++i) ++counts[uint160(seats[i]) - 0x1000];
        for (uint256 i; i < counts.length; ++i) assertEq(counts[i], 2);
    }

    function test_ResumesWithinVisitAndAtItsExactEnd() public {
        address[][] memory levels = new address[][](1);
        levels[0] = _owners(0x1000, 160);
        h.seed(CEILING + 99, levels[0], true);
        (address[] memory full, uint256 fullCursor) = _draw(123, 500, JackpotBattleFieldLib.MAX_CHUNK);
        (address[] memory split, uint256 splitCursor) = _draw(123, 500, 17);
        assertEq(full, _oracle(levels, 123, 500));
        assertEq(split, full);
        assertEq(splitCursor, fullCursor, "continuation is independent of chunk boundaries");
    }

    function test_ResumeKeepsEligibleLevelSnapshot() public {
        address[] memory original = _owners(0x1000, 200);
        h.seed(CEILING + 99, original, true);
        (address[] memory first, uint256 cursor,) = h.collect(CEILING, 123, 0, 500);
        // A newly populated level is deliberately introduced between calls. The real daily lock
        // prevents registration; this also pins the cursor's frozen eligibility independently.
        h.seed(CEILING + 1, _owners(0x2000, 200), false);
        (address[] memory second,,) = h.collect(CEILING, 123, cursor, 500 - first.length);
        address[][] memory levels = new address[][](1);
        levels[0] = original;
        address[] memory expected = _oracle(levels, 123, first.length + second.length);
        for (uint256 i; i < first.length; ++i) {
            assertEq(first[i], expected[i]);
            assertEq(second[i], expected[first.length + i]);
        }
    }

    function testFuzz_CircularVisitsMatchOracleAcrossChunkSizes(
        uint256 word, uint16 rawA, uint16 rawB, uint16 rawCount, uint8 rawChunk
    ) public {
        address[][] memory levels = new address[][](3);
        levels[0] = _owners(0x1000, 1 + uint256(rawA) % 40);
        levels[1] = _owners(0x2000, 1 + uint256(rawB) % 200);
        levels[2] = _owners(0x3000, 9);
        h.seed(CEILING + 1, levels[0], true);
        h.seed(CEILING + 48, levels[1], true);
        h.seed(CEILING + 99, levels[2], true);
        uint256 count = 1 + uint256(rawCount) % 500;
        (address[] memory full, uint256 fullCursor) = h.collectCached(CEILING, word, count);
        (address[] memory split, uint256 splitCursor) = _draw(word, count, 1 + uint256(rawChunk) % JackpotBattleFieldLib.MAX_CHUNK);
        assertEq(full, _oracle(levels, word, count));
        assertEq(split, full);
        assertEq(splitCursor, fullCursor);
        assertEq(h.queued(CEILING + 1), levels[0]);
        assertEq(h.queued(CEILING + 48), levels[1]);
        assertEq(h.queued(CEILING + 99), levels[2]);
    }
}
