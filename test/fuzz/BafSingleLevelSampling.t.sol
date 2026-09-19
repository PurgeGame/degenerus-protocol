// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract BafSingleLevelHarness is DegenerusGame {
    function seed(uint24 target, uint256 count) public {
        level = 100;
        _releaseTicketQueue(_tqFarFutureKey(target));
        for (uint256 i; i < count; ++i) {
            address player = address(uint160((uint256(target) << 32) + i + 1));
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(player, target) >> OWNER_IDX_SHIFT));
        }
    }

    function seedRange(uint256 count) external {
        for (uint24 target = 105; target <= 199; ++target) seed(target, count);
    }

    function seedProtocolRange() external {
        level = 100;
        for (uint24 target = 105; target <= 199; ++target) {
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(ContractAddresses.SDGNRS, target) >> OWNER_IDX_SHIFT));
            _tqAppend(_tqFarFutureKey(target), uint32(_registerEntryOwner(ContractAddresses.VAULT, target) >> OWNER_IDX_SHIFT));
        }
    }
}

contract BafSingleLevelSamplingTest is Test {
    BafSingleLevelHarness private h;

    function setUp() public { h = new BafSingleLevelHarness(); }

    function _check(uint256 entropy, uint256 len, uint256 fallbackLength) private {
        uint24 selected = 105 + uint24(entropy % 95);
        h.seedRange(fallbackLength);
        h.seed(selected, len);
        address[] memory players = h.sampleFarFutureTickets(entropy);
        assertEq(players.length, 4, "every BAF draw needs four candidate slots");
        uint256 found;
        while (found < 4) {
            uint24 target = 105 + uint24(entropy % 95);
            uint256 length = target == selected ? len : fallbackLength;
            uint256 take = length < 4 - found ? length : 4 - found;
            for (uint256 i; i < take; ++i) {
                uint256 seed = entropy >> 32;
                uint256 index;
                if (length <= 8) index = (seed % length + i) % length;
                else {
                    uint256 start = seed % (((length + 7) / 8) * 8);
                    index = (start / 8) * 8 + ((start % 8 + i) % 8);
                    if (index >= length) index = uint256(keccak256(abi.encode(seed, i))) % length;
                }
                assertEq(players[found + i], address(uint160((uint256(target) << 32) + index + 1)), "level grouping and packed-word decoding");
            }
            found += take;
            entropy = uint256(keccak256(abi.encode(entropy, found)));
        }
    }

    function testFuzz_GroupedLevelsFillFourSlots(uint256 entropy, uint16 length) public {
        _check(entropy, 1 + uint256(length) % 512, 2);
    }

    function test_OneHolderUsesFourLevels() public { _check(1, 1, 1); }
    function test_TwoHoldersUseAnotherLevel() public { _check(2, 2, 2); }
    function test_ThreeHoldersFillOneMoreSlot() public { _check(3, 3, 2); }
    function test_FourHoldersNeedOnlyOneLevel() public { _check(4, 4, 2); }
    function test_FullWordNeedsOnlyOneLevel() public { _check(5, 16, 2); }
    function test_PartialTailRedrawStaysInSelectedLevel() public { _check(uint256(8) << 32, 9, 2); }
    function test_FirstCandidateLevel() public { _check(0, 4, 2); }
    function test_LastCandidateLevel() public { _check(94, 4, 2); }

    function test_EmptySelectedLevelIsSkipped() public {
        uint256 entropy = 94; // offset 94 -> level 199
        h.seedRange(2);
        h.seed(199, 0);
        address[] memory players = h.sampleFarFutureTickets(entropy);
        assertEq(players.length, 4, "an empty level re-rolls and the slots still fill");
        for (uint256 i; i < 4; ++i) {
            assertTrue(uint256(uint160(players[i])) >> 32 != 199, "no slot names the empty level");
            assertTrue(players[i] != address(0), "every slot names a live owner");
        }
    }

    function test_AllLevelsEmptyReturnsNoSlotsWithoutReverting() public {
        h.seed(105, 0); // sets level = 100 and leaves every candidate queue empty
        address[] memory players = h.sampleFarFutureTickets(7);
        assertEq(players.length, 0, "an unseeded range yields no candidates rather than a revert");
    }

    function test_ProtocolOwnersRepeatAcrossLevels() public {
        h.seedProtocolRange();
        address[] memory players = h.sampleFarFutureTickets(1);
        assertEq(players.length, 4);
        uint256 sdgnrsSlots;
        uint256 vaultSlots;
        for (uint256 i; i < 4; ++i) {
            if (players[i] == ContractAddresses.SDGNRS) ++sdgnrsSlots;
            else if (players[i] == ContractAddresses.VAULT) ++vaultSlots;
            else fail("only the two protocol owners were seeded");
        }
        assertEq(sdgnrsSlots, 2);
        assertEq(vaultSlots, 2);
    }
}
