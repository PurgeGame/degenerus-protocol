// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.33;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";

/// @dev Existing production queue sink, without purchase/payment overhead.
contract CurrentEntryOwnerMeasurement is DegenerusGameStorage {
    constructor() { level = 3; }
    function buy(address player, uint24 target) external { _queueEntries(player, target, 4, false); }
    function drain(address player, uint24 target) external returns (address owner, uint32 owed) {
        uint24 key = target > _mintCeiling() ? _tqFarFutureKey(target) : _tqWriteKey(target);
        uint80 packed = _entriesOwed(key, player);
        uint32 pos = uint32(packed >> OWNER_IDX_SHIFT);
        uint256 record = _entryRecord(key, pos);
        owner = address(uint160(record));
        owed = uint32(record >> 168);
        _setEntryOwed(key, pos, 0);
        _releaseTicketQueue(key);
    }
}

/// @dev Measurement prototype only. No production contract calls this registry.
///      Three separate 42-bit lanes share one sentinel-backed pending word.
contract StableEntryOwnerMeasurement is DegenerusGameStorage {
    mapping(address => uint32) private ids;
    address[] private owners;
    mapping(uint24 => mapping(uint32 => uint256)) private pending;
    uint256 private constant MASK = (uint256(1) << 42) - 1;
    uint256 private constant QUEUED = uint256(1) << 41;
    uint256 private constant SENTINEL = uint256(1) << 255;

    constructor() { level = 3; }
    function idOf(address player) external view returns (uint32) { return ids[player]; }

    function buy(address player, uint24 target) external {
        uint32 id = ids[player];
        if (id == 0) {
            require(owners.length < type(uint32).max);
            owners.push(player);
            id = uint32(owners.length);
            ids[player] = id;
            emit EntryOwnerRegistered(target, id - 1, player);
        }
        uint24 key = target > _mintCeiling() ? _tqFarFutureKey(target) : _tqWriteKey(target);
        uint256 shift = key & TICKET_FAR_FUTURE_BIT != 0 ? 84 : (key & TICKET_SLOT_BIT != 0 ? 42 : 0);
        uint256 word = pending[target][id];
        uint256 lane = (word >> shift) & MASK;
        if (lane & QUEUED == 0) _tqAppend(key, id);
        lane = QUEUED | (uint256(uint32(lane >> 8) + 4) << 8) | uint8(lane);
        pending[target][id] = (word & ~(MASK << shift)) | (lane << shift) | SENTINEL;
        emit EntriesQueued(player, target, 4);
    }

    function drain(address player, uint24 target) external returns (address owner, uint32 owed) {
        uint32 id = ids[player];
        owner = owners[id - 1];
        uint24 key = target > _mintCeiling() ? _tqFarFutureKey(target) : _tqWriteKey(target);
        uint256 shift = key & TICKET_FAR_FUTURE_BIT != 0 ? 84 : (key & TICKET_SLOT_BIT != 0 ? 42 : 0);
        uint256 word = pending[target][id];
        owed = uint32(word >> (shift + 8));
        pending[target][id] = (word & ~(MASK << shift)) | SENTINEL;
        _releaseTicketQueue(key);
    }
}

/// @dev Historical prototype screening fixture. The production side now includes permanent IDs
///      and collision tags; the prototype omits those protections. This is not a before/after
///      permanent-ID measurement or whole-protocol acceptance. No transaction intrinsic gas,
///      refund adjustment, payment routing, or trait generation is included.
contract StableEntryOwnerMeasurementTest is Test {
    CurrentEntryOwnerMeasurement private old;
    StableEntryOwnerMeasurement private candidate;
    mapping(address => bytes32[]) private touched;
    address private constant PLAYER = address(0xA11CE);

    function setUp() public {
        old = new CurrentEntryOwnerMeasurement();
        candidate = new StableEntryOwnerMeasurement();
    }

    function _cold(address target) private {
        bytes32[] storage slots = touched[target];
        for (uint256 i; i < slots.length; ++i) vm.coolSlot(target, slots[i]);
        vm.cool(target);
        vm.record();
    }

    function _remember(address target) private {
        (bytes32[] memory reads, bytes32[] memory writes) = vm.accesses(target);
        for (uint256 i; i < reads.length; ++i) touched[target].push(reads[i]);
        for (uint256 i; i < writes.length; ++i) touched[target].push(writes[i]);
    }

    function _buy(address target, uint24 lvl) private returns (uint256 gasUsed) {
        _cold(target);
        uint256 beforeGas = gasleft();
        (bool ok,) = target.call(abi.encodeWithSignature("buy(address,uint24)", PLAYER, lvl));
        gasUsed = beforeGas - gasleft();
        assertTrue(ok);
        _remember(target);
    }

    function _drain(address target, uint24 lvl) private returns (uint256 gasUsed) {
        _cold(target);
        uint256 beforeGas = gasleft();
        (bool ok, bytes memory result) = target.call(abi.encodeWithSignature("drain(address,uint24)", PLAYER, lvl));
        gasUsed = beforeGas - gasleft();
        assertTrue(ok);
        (address owner, uint32 owed) = abi.decode(result, (address, uint32));
        assertEq(owner, PLAYER);
        assertEq(owed, 4);
        _remember(target);
    }

    function test_ColdFirstAndRepeatedCohorts() public {
        emit log_named_uint("old first buy", _buy(address(old), 3));
        emit log_named_uint("candidate first buy", _buy(address(candidate), 3));
        emit log_named_uint("old first drain", _drain(address(old), 3));
        emit log_named_uint("candidate first drain", _drain(address(candidate), 3));
        uint256 oldTotal;
        uint256 newTotal;
        for (uint256 i; i < 8; ++i) {
            oldTotal += _buy(address(old), 3) + _drain(address(old), 3);
            newTotal += _buy(address(candidate), 3) + _drain(address(candidate), 3);
        }
        emit log_named_uint("old eight repeated buy/drain cohorts", oldTotal);
        emit log_named_uint("candidate eight repeated buy/drain cohorts", newTotal);
        assertLt(newTotal, oldTotal);
        assertEq(candidate.idOf(PLAYER), 1);
    }

    function test_ColdOneHundredDistinctFutureLevels() public {
        uint256 oldTotal;
        uint256 newTotal;
        for (uint24 lvl = 5; lvl < 105; ++lvl) {
            oldTotal += _buy(address(old), lvl);
            newTotal += _buy(address(candidate), lvl);
        }
        emit log_named_uint("old 100 future credits", oldTotal);
        emit log_named_uint("candidate 100 future credits", newTotal);
        assertLt(newTotal, oldTotal);
        assertEq(candidate.idOf(PLAYER), 1);
    }
}
