// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {CrapsLens} from "../../contracts/CrapsLens.sol";
import {CrapsBattleStorage} from "../../contracts/storage/CrapsBattleStorage.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract CrapsLensState is CrapsBattleStorage {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory values) {
        values = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) {
            bytes32 slot = slots[i];
            bytes32 value;
            assembly ("memory-safe") { value := sload(slot) }
            values[i] = value;
        }
    }

    function seedRound(uint64 slot, JackpotRound memory round, uint256 board, uint64 cursor) external {
        round.day = uint24(slot >> 3);
        _jackpotRounds[(slot) & 511] = round;
        _storeBattle(bytes32(uint256(slot)), board);
        _setSlotIndex(slot, 1);
        _setBonusCursor(slot, cursor);
    }

    function seedDraw(uint64 slot, HighRollerDraw memory draw, uint256 reserve) external {
        _storeHighDraw(slot, draw);
        _highRollerReserve = reserve + 1;
    }

    function seedPreference(uint32 id, uint32 chips, uint256 progressive) external {
        _passCreditsById[id] = (CrapsPreferenceLib.compress(chips) << 64) | CrapsPreferenceLib.INITIALIZED
            | CrapsPreferenceLib.RETAINED | 7 | (uint256(5) << 32);
        _progressive = progressive;
    }

    function seedCustom(uint64 slot, uint256 board, uint64 cursor) external {
        _customBattle[slot] = uint256(100) | (uint256(5) << 28) | (uint256(5) << 33) | (uint256(1) << 43);
        bytes32 key = keccak256(abi.encode(BATTLE_TAG, uint48(slot), uint256(500), uint256(2500), uint256(100), uint256(1)));
        _storeBattle(key, board);
        _setBonusCursor(slot, cursor);
    }

    function seedOpening(uint24 day, uint32 fee) external {
        _bonus = uint256(day) + 1;
        _storeBattle(bytes32(uint256(day) * 8 + 6), (uint256(1) << 255) | (uint256(fee / 100) << 201));
    }
}

contract CrapsLensTest is Test {
    CrapsLensState private table;
    CrapsLens private lens;

    function setUp() public {
        CrapsLensState implementation = new CrapsLensState();
        vm.etch(ContractAddresses.CRAPS, address(implementation).code);
        table = CrapsLensState(ContractAddresses.CRAPS);
        lens = new CrapsLens();
    }

    function testFuzz_RoundReaderMatchesAllPackedFields(
        uint24 day, CrapsBattleStorage.JackpotRound memory expected, uint256 board, uint64 cursor
    ) public {
        uint64 slot = uint64(uint256(day) * 8 + 6);
        expected.day = day;
        expected.started = true;
        expected.drawCursor &= ~uint208(1 << 207);
        CrapsBattleStorage.JackpotRound memory stored = expected;
        stored.drawCursor |= uint208(1 << 207);
        table.seedRound(slot, stored, board, cursor);
        expected.drawCursor &= ~uint208(1 << 207);
        (CrapsBattleStorage.JackpotRound memory actual, uint256 gotBoard, uint64 gotCursor) = lens.jackpotBattleOf(slot);
        assertEq(keccak256(abi.encode(actual)), keccak256(abi.encode(expected)));
        assertEq(gotBoard, board);
        assertEq(gotCursor, cursor);
    }

    function testFuzz_ReserveReaderPreservesNomineeCountersAndFlags(
        uint24 day, CrapsBattleStorage.HighRollerDraw memory expected, uint128 reserve
    ) public {
        uint64 slot = uint64(uint256(day) * 8 + 6);
        table.seedDraw(slot, expected, reserve);
        assertEq(keccak256(abi.encode(lens.highRollerDrawOf(slot))), keccak256(abi.encode(expected)));
        assertEq(lens.highRollerReserve(), reserve);
    }

    function test_PreferenceIgnoresCreditLanesAndRetentionBits() public {
        assertEq(lens.preferredBoardOf(17), 0);
        uint32 board = 3 | (uint32(3) << 9) | (uint32(1) << 12);
        table.seedPreference(17, board, 123456789);
        assertEq(lens.preferredBoardOf(17), board);
        assertEq(lens.progressivePool(), 123456789);
    }

    function test_OpeningFeeQuoteAndLockedFeeUseTheSameUnits() public {
        uint24 day = 50;
        uint64 slot = uint64(uint256(day) * 8 + 6);
        table.seedOpening(day, 10000);
        assertEq(lens.jackpotEntryPrice(), 10000);
        assertEq(lens.jackpotEntryPriceOf(slot), 10000);
        CrapsBattleStorage.JackpotRound memory round;
        round.entryPrice = 8000;
        table.seedRound(slot, round, uint256(12345) << 201, 0);
        assertEq(lens.jackpotEntryPrice(), 8000);
        assertEq(lens.jackpotEntryPriceOf(slot), 8000);
    }
    function test_CustomViewUsesFullKeyAndCursor() public {
        uint64 slot = uint64((uint256(1) << 40) + 1);
        table.seedCustom(slot, 1234567, 88);
        (CrapsBattleStorage.JackpotRound memory round, uint256 board, uint64 cursor) = lens.jackpotBattleOf(slot);
        assertEq(round.requestDay, 0);
        assertEq(board, 1234567);
        assertEq(cursor, 88);
    }

}
