// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm, VmSafe} from "forge-std/Vm.sol";
import {JackpotBattleFieldLib} from "../../contracts/libraries/JackpotBattleFieldLib.sol";
import {CrapsPreferenceLib} from "../../contracts/libraries/CrapsPreferenceLib.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @dev Stands in for the table's raw reader at `ContractAddresses.CRAPS`: both `extsload` forms
///      over its own storage, so a fixture plants pass words with `vm.store`.
contract CrapsReaderStub {
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }

    function extsload(bytes32[] calldata slots) external view returns (bytes32[] memory out) {
        out = new bytes32[](slots.length);
        for (uint256 i; i < slots.length; ++i) {
            bytes32 s = slots[i];
            bytes32 v;
            assembly ("memory-safe") { v := sload(s) }
            out[i] = v;
        }
    }
}

/// @title The jackpot battle field under wallet IDs
/// @notice `JackpotBattleFieldLib.prepare(uint32[] ids)` builds one word per drawn entry,
///         `id | board << 160 | 1 << 180`, reading each distinct wallet's saved board from the
///         ID-keyed pass word (`_passCreditsById`, slot 15) in one batched `extsload`.
contract JackpotBattleFieldIdsTest is Test {
    uint256 internal constant ADDRESS_SLOT = 14;
    uint256 internal constant ID_SLOT = 15;
    bytes4 internal constant BATCH_SEL = bytes4(keccak256("extsload(bytes32[])"));
    uint32 internal constant BOARD_A = 3 | (3 << 12) | (1 << 15);
    uint32 internal constant BOARD_B = 2 | (1 << 3);

    function setUp() public {
        vm.etch(ContractAddresses.CRAPS, address(new CrapsReaderStub()).code);
    }

    function _idKey(uint32 id) internal pure returns (bytes32) {
        return keccak256(abi.encode(uint256(id), ID_SLOT));
    }

    /// @dev A saved ID word: passes in the low lanes (which must never reach the field), the
    ///      compact board, and the initialized bit.
    function _saveBoard(uint32 id, uint32 chips, uint64 passes) internal {
        vm.store(
            ContractAddresses.CRAPS,
            _idKey(id),
            bytes32(uint256(passes) | (CrapsPreferenceLib.compress(chips) << CrapsPreferenceLib.SHIFT) | CrapsPreferenceLib.INITIALIZED)
        );
    }

    function _word(uint32 id, uint32 chips) internal pure returns (uint256) {
        return uint256(id) | (CrapsPreferenceLib.compress(chips) << JackpotBattleFieldLib.BOARD_SHIFT)
            | (uint256(1) << JackpotBattleFieldLib.UNITS_SHIFT);
    }

    /// @dev Prepare under state-diff recording and return the field with every batched read's slots.
    function _prepareRecorded(uint32[] memory ids)
        internal
        returns (uint256[] memory field, bytes32[][] memory reads)
    {
        vm.startStateDiffRecording();
        field = JackpotBattleFieldLib.prepare(ids);
        Vm.AccountAccess[] memory acc = vm.stopAndReturnStateDiff();
        reads = new bytes32[][](acc.length);
        uint256 n;
        for (uint256 i; i < acc.length; ++i) {
            if (acc[i].account != ContractAddresses.CRAPS) continue;
            if (acc[i].kind != VmSafe.AccountAccessKind.StaticCall && acc[i].kind != VmSafe.AccountAccessKind.Call) continue;
            bytes memory d = acc[i].data;
            require(bytes4(d) == BATCH_SEL, "only the batched reader is called");
            bytes memory args = new bytes(d.length - 4);
            for (uint256 j; j < args.length; ++j) args[j] = d[j + 4];
            reads[n++] = abi.decode(args, (bytes32[]));
        }
        assembly ("memory-safe") { mstore(reads, n) }
    }

    function test_fieldWordIsIdBoardAndOneUnit() public {
        _saveBoard(9, BOARD_A, type(uint64).max);
        uint32[] memory ids = new uint32[](1);
        ids[0] = 9;
        (uint256[] memory field,) = _prepareRecorded(ids);
        assertEq(field.length, 1);
        assertEq(field[0], _word(9, BOARD_A), "field word == id | board << 160 | 1 << 180");
        assertEq(uint32(field[0]), 9);
        assertEq((field[0] >> 32) & ((uint256(1) << 128) - 1), 0, "pass balances never enter the field");
    }

    function test_lowByteCollisionAndRepeatsDedupeToOneBatchedRead() public {
        _saveBoard(1, BOARD_A, 7);
        _saveBoard(257, BOARD_B, 3);
        uint32[] memory ids = new uint32[](5);
        ids[0] = 1;
        ids[1] = 257;
        ids[2] = 1;
        ids[3] = 513;
        ids[4] = 257;
        (uint256[] memory field, bytes32[][] memory reads) = _prepareRecorded(ids);
        assertEq(reads.length, 1, "exactly one extsload");
        assertEq(reads[0].length, 3, "one slot per distinct ID");
        assertEq(reads[0][0], _idKey(1));
        assertEq(reads[0][1], _idKey(257));
        assertEq(reads[0][2], _idKey(513));
        assertEq(field.length, 5, "one word per drawn entry, in draw order");
        assertEq(field[0], _word(1, BOARD_A));
        assertEq(field[1], _word(257, BOARD_B), "257 keeps its own board despite sharing 1's low byte");
        assertEq(field[2], _word(1, BOARD_A));
        assertEq(field[3], _word(513, 0), "an ID with no saved board plays random");
        assertEq(field[4], _word(257, BOARD_B));
    }

    function test_theBoardComesFromTheIdWordNotTheAddressWord() public {
        uint32 id = 42;
        address owner = makeAddr("field-owner");
        // The address word holds a different board and the ID cache; only the ID word may be read.
        vm.store(
            ContractAddresses.CRAPS,
            keccak256(abi.encode(owner, ADDRESS_SLOT)),
            bytes32((CrapsPreferenceLib.compress(BOARD_A) << CrapsPreferenceLib.SHIFT) | CrapsPreferenceLib.INITIALIZED
                | (uint256(id) << CrapsPreferenceLib.ID_SHIFT))
        );
        uint32[] memory ids = new uint32[](1);
        ids[0] = id;
        (uint256[] memory field, bytes32[][] memory reads) = _prepareRecorded(ids);
        assertEq(reads[0][0], _idKey(id), "the read targets _passCreditsById");
        assertEq(field[0], _word(id, 0), "no ID-word board: board zero");
        _saveBoard(id, BOARD_B, 0);
        (field,) = _prepareRecorded(ids);
        assertEq(field[0], _word(id, BOARD_B), "the ID word's board, not the address word's");
    }

    function test_anEmptyDrawReadsNothing() public {
        (uint256[] memory field, bytes32[][] memory reads) = _prepareRecorded(new uint32[](0));
        assertEq(field.length, 0);
        assertEq(reads.length, 0);
    }

    /// @dev Any draw: one read, as many slots as distinct IDs in first-seen order, and every word
    ///      the entry's own ID with its own saved board.
    function testFuzz_prepareMatchesAReferenceDedupe(uint256 seed, uint8 rawN) public {
        uint256 units = 1 + uint256(rawN) % JackpotBattleFieldLib.MAX_CHUNK;
        uint32[] memory ids = new uint32[](units);
        uint32[] memory distinct = new uint32[](units);
        uint256 nd;
        for (uint256 i; i < units; ++i) {
            uint256 r = uint256(keccak256(abi.encode(seed, i)));
            // A small pool on few low bytes forces both repeats and collisions.
            uint32 id = uint32(1 + (r % 6) * 256 + (r >> 8) % 3);
            ids[i] = id;
            bool seen;
            for (uint256 j; j < nd; ++j) if (distinct[j] == id) seen = true;
            if (!seen) {
                distinct[nd++] = id;
                if ((r >> 16) % 2 == 0) _saveBoard(id, (r >> 24) % 2 == 0 ? BOARD_A : BOARD_B, uint64(r >> 32));
            }
        }
        (uint256[] memory field, bytes32[][] memory reads) = _prepareRecorded(ids);
        assertEq(reads.length, 1, "one batched read");
        assertEq(reads[0].length, nd, "one slot per distinct ID");
        for (uint256 j; j < nd; ++j) assertEq(reads[0][j], _idKey(distinct[j]), "first-seen order");
        for (uint256 i; i < units; ++i) {
            uint256 saved = uint256(vm.load(ContractAddresses.CRAPS, _idKey(ids[i])));
            (uint32 chips,) = CrapsPreferenceLib.decode(saved);
            assertEq(field[i], _word(ids[i], chips), "entry word");
        }
    }
}
