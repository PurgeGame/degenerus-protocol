// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {EntropyLib} from "../../contracts/libraries/EntropyLib.sol";

contract BafSingleLevelHarness is DegenerusGame {
    function seed(uint24 target, uint256 count) public {
        level = 100;
        _releaseTicketQueue(_tqFarFutureKey(target));
        for (uint256 i; i < count; ++i) {
            address player = address(uint160((uint256(target) << 32) + i + 1));
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(player, target) >> OWNER_IDX_SHIFT));
        }
    }

    function seedRange(uint24 fromLevel, uint24 toLevel, uint256 count) external {
        for (uint24 target = fromLevel; target <= toLevel; ++target) seed(target, count);
    }

    function seedProtocolRange(uint24 fromLevel, uint24 toLevel) external {
        level = 100;
        for (uint24 target = fromLevel; target <= toLevel; ++target) {
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(ContractAddresses.SDGNRS, target) >> OWNER_IDX_SHIFT));
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(ContractAddresses.VAULT, target) >> OWNER_IDX_SHIFT));
        }
    }
}

/// @dev sampleFarFutureTickets(entropy, fromLevel, toLevel) returns eight slots: four packs, each an
///      independent level and a lane pair (a uniform lane a, plus a distinct lane b among the next
///      min(8, len) - 1, wrapping). Pack p fills slot p (the even round) and slot p + 4 (the odd
///      round). The BAF calls it for band 2 (level+2..level+5) and band 3 (level+6..level+99).
///      _model is a line-for-line replica; the fuzz pins the contract to it, and the enumeration
///      proves the replica gives every lane the same odds whatever the queue length.
contract BafSingleLevelSamplingTest is Test {
    BafSingleLevelHarness private h;

    function setUp() public { h = new BafSingleLevelHarness(); }

    function _owner(uint24 target, uint256 lane) private pure returns (address) {
        return address(uint160((uint256(target) << 32) + lane + 1));
    }

    function _model(uint256 entropy, uint24 fromLevel, uint24 toLevel, uint24 selected, uint256 len, uint256 fallbackLength)
        private pure returns (address[8] memory slots)
    {
        uint256 span = uint256(toLevel - fromLevel) + 1;
        uint256 packs;
        for (uint256 attempt; packs < 4 && attempt < 12; ++attempt) {
            entropy = EntropyLib.hash2(entropy, attempt);
            uint24 target = fromLevel + uint24(entropy % span);
            uint256 length = target == selected ? len : fallbackLength;
            if (length == 0) continue;
            uint256 a = (entropy >> 64) % length;
            slots[packs] = _owner(target, a);
            uint256 window = length < 8 ? length : 8;
            if (window > 1) slots[packs + 4] = _owner(target, (a + 1 + (entropy >> 128) % (window - 1)) % length);
            ++packs;
        }
    }

    function _check(uint256 entropy, uint256 len, uint256 fallbackLength, uint24 fromLevel, uint24 toLevel) private {
        uint24 selected = fromLevel + uint24(EntropyLib.hash2(entropy, 0) % (uint256(toLevel - fromLevel) + 1));
        h.seedRange(fromLevel, toLevel, fallbackLength);
        h.seed(selected, len);
        address[] memory players = h.sampleFarFutureTickets(entropy, fromLevel, toLevel);
        assertEq(players.length, 8, "two rounds of four candidate slots");
        address[8] memory expected = _model(entropy, fromLevel, toLevel, selected, len, fallbackLength);
        for (uint256 i; i < 8; ++i) assertEq(players[i], expected[i], "slot matches the uniform-lane replica");
    }

    function testFuzz_MatchesReplicaWideBand(uint256 entropy, uint16 length) public {
        _check(entropy, uint256(length) % 512, 3, 106, 199);
    }

    function testFuzz_MatchesReplicaNarrowBand(uint256 entropy, uint16 length) public {
        _check(entropy, uint256(length) % 40, 1, 102, 105);
    }

    /// @dev The lane pair's odds, enumerated exactly: over every (a, offset) pair, each lane is
    ///      `a` once and `b` once per offset value, so both slots are uniform at every length —
    ///      including a partial tail word, where a word-first pick would over-weight the tail.
    function test_LanePairIsUniformAtEveryLength() public pure {
        for (uint256 len = 1; len <= 40; ++len) {
            uint256 window = len < 8 ? len : 8;
            uint256[40] memory asB;
            for (uint256 a; a < len; ++a) {
                for (uint256 r; r + 1 < window; ++r) ++asB[(a + 1 + r) % len];
            }
            for (uint256 lane; lane < len; ++lane) {
                assertEq(asB[lane], window - 1, "every lane is b equally often");
            }
        }
    }

    function test_SingleHolderLeavesOddSlotEmpty() public {
        h.seed(150, 1);
        address[] memory players = h.sampleFarFutureTickets(11, 150, 150);
        for (uint256 p; p < 4; ++p) {
            assertEq(players[p], _owner(150, 0), "the lone holder takes every even slot");
            assertEq(players[p + 4], address(0), "no distinct partner, odd slot stays empty");
        }
    }

    function test_EmptySelectedLevelIsSkipped() public {
        h.seedRange(106, 199, 2);
        h.seed(199, 0);
        address[] memory players = h.sampleFarFutureTickets(93, 106, 199);
        for (uint256 i; i < 8; ++i) {
            assertTrue(uint256(uint160(players[i])) >> 32 != 199, "no slot names the empty level");
            assertTrue(players[i] != address(0), "every slot names a live owner");
        }
    }

    function test_AllLevelsEmptyReturnsEmptySlotsWithoutReverting() public {
        h.seed(106, 0); // sets level = 100 and leaves the candidate queue empty
        address[] memory players = h.sampleFarFutureTickets(7, 106, 199);
        assertEq(players.length, 8);
        for (uint256 i; i < 8; ++i) assertEq(players[i], address(0), "an unseeded range fills nothing");
    }

    // Narrow band (level+2..level+5 = 102..105, span 4): every level has exactly the two
    // protocol holders, so each pack names both of them once.
    function test_ProtocolOwnersPairInEveryPack() public {
        h.seedProtocolRange(102, 105);
        address[] memory players = h.sampleFarFutureTickets(1, 102, 105);
        for (uint256 p; p < 4; ++p) {
            assertTrue(players[p] != players[p + 4], "a pack's two lanes are distinct");
            assertTrue(
                (players[p] == ContractAddresses.SDGNRS && players[p + 4] == ContractAddresses.VAULT)
                    || (players[p] == ContractAddresses.VAULT && players[p + 4] == ContractAddresses.SDGNRS),
                "only the two protocol owners were seeded"
            );
        }
    }
}
