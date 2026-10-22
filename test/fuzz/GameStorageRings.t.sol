// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameLens} from "../../contracts/DegenerusGameLens.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

contract GameRingsHarness is DegenerusGameStorage {
    function stamp(uint24 lvl) external { _setTicketBufferLevel(lvl); }
    function append(uint24 lvl, uint8 trait, uint32 id, uint256 count, bool lanes) external {
        if (lanes) _bucketAppendLanes(_traitBufferBase(lvl), trait, id, 1, lvl);
        else _bucketAppendRun(_traitBufferBase(lvl), trait, id, count, lvl);
    }
    function bitmap(uint24 lvl) external view returns (uint256 logical, uint256 physical, uint8 stale) {
        return (_traitBitmap(lvl), traitBucketLive[lvl & 1], traitBucketStale);
    }
    function length(uint24 lvl, uint8 trait) external view returns (uint256) { return _bucketLengthUnchecked(lvl, trait); }
    function idAt(uint24 lvl, uint8 trait, uint256 index) external view returns (uint32) { return _bucketIdAtUnchecked(lvl, trait, index); }
    function pool(uint24 lvl, uint128 amount) external { _setLevelPrizePool(lvl, amount); }
    function pool(uint24 lvl) external view returns (uint256) { return _levelPrizePool(lvl); }
    function allocate(uint24 lvl, uint128 amount) external { _setLevelDgnrsAllocation(lvl, amount); level = lvl; }
    function claim(uint24 lvl, uint96 amount) external { _addLevelDgnrsClaimed(lvl, amount); }
    function allocation(uint24 lvl) external view returns (uint256, uint256) { return _getLevelDgnrs(lvl); }
    function mark(uint24 lvl) external { _markTicketGenerationStart(lvl); }
    function start(uint24 lvl) external view returns (uint256) {
        return uint24(ticketGenerationStartBlock) == lvl ? ticketGenerationStartBlock >> 24 : 0;
    }
    function open(uint24 lvl) external { decEntriesLevel = lvl; decBattleRounds[lvl].count = 0; }
    function append(uint24 lvl, uint128 value) external {
        uint64 id = ++decBattleRounds[lvl].count;
        _storeDecEntry(lvl, id, value);
    }
    function update(uint24 lvl, uint64 id, uint128 value) external { _storeDecEntry(lvl, id, value); }
    function entry(uint24 lvl, uint64 id) external view returns (uint256) { return _loadDecEntry(lvl, id); }
    function owed(uint24 lvl, uint32 id, uint32 amount) external {
        _setEntryOwed(lvl | TICKET_FAR_FUTURE_BIT, id,
            amount == 0 ? 0 : (uint80(id) << 48) | (uint80(amount) << 8));
    }
    function owed(uint24 lvl, uint32 id) external view returns (uint256) { return _farFutureLane(lvl, id) & 0x3fffffff; }
    function sub(uint32 id, uint256 value) external { _setSubMetaLane(id, value); }
    function sub(uint32 id) external view returns (uint256) { return _subMetaLane(id); }
    function extsload(bytes32 slot) external view returns (bytes32 value) {
        assembly ("memory-safe") { value := sload(slot) }
    }
}

contract GameStorageRingsTest is Test {
    GameRingsHarness private h;
    DegenerusGameLens private lens;
    function setUp() public { h = new GameRingsHarness(); lens = new DegenerusGameLens(); }

    function test_TraitRecycleHidesOldBitmapBeforeAnyAppend() public {
        h.stamp(2);
        h.append(2, 9, 7, 3, false);
        h.append(2, 17, 8, 1, true);
        (uint256 live, uint256 beforeBits,) = h.bitmap(2);
        assertEq(live, (1 << 9) | (1 << 17));
        h.stamp(4);
        uint256 bits;
        uint8 stale;
        (live, bits, stale) = h.bitmap(4);
        assertEq(live, 0);
        assertEq(bits, beforeBits, "retirement retains the physical bitmap");
        assertEq(stale & 1, 1);
        assertEq(h.length(4, 9), 0, "new level cannot see old headers");
        assertEq(h.length(2, 9), 0, "old tag cannot see current bank");
        uint32[] memory ids = new uint32[](1);
        ids[0] = 7;
        (bool found,,,uint32 total) = lens.findTraitEntry(address(h), 4, 9, ids, 0, 8);
        assertFalse(found);
        assertEq(total, 0, "Lens observes the stale flag");
    }

    function testFuzz_FirstAppendReplacesStaleBitmapAndHeader(bool lanes) public {
        h.stamp(2);
        h.append(2, 9, 7, 3, false);
        h.append(2, 17, 8, 1, true);
        h.stamp(4);
        h.append(4, 9, 12, 1, lanes);
        (uint256 live, uint256 physical, uint8 stale) = h.bitmap(4);
        assertEq(live, 1 << 9, "stale traits cannot survive whole-word replacement");
        assertEq(physical, live);
        assertEq(stale & 1, 0, "first append resets stale state");
        assertEq(h.length(4, 9), 1, "old count does not survive");
        assertEq(h.idAt(4, 9, 0), 12, "old owner does not survive");
        assertEq(h.length(4, 17), 0);
        h.append(4, 17, 13, 1, !lanes);
        assertEq(h.length(4, 9), 1, "second append preserves the new first trait");
        assertEq(h.length(4, 17), 1);
    }

    function testFuzz_PrizePoolWindowAndWholeWordOverwrite(uint24 first, uint128 oldAmount, uint128 next) public {
        first = uint24(bound(first, 0, type(uint24).max - 4));
        for (uint24 i; i < 4; ++i) h.pool(first + i, oldAmount);
        for (uint24 i; i < 4; ++i) assertEq(h.pool(first + i), oldAmount);
        bytes32 slot = bytes32(GameSlots.LEVEL_PRIZE_POOL + uint256(first & 3));
        vm.store(address(h), slot, bytes32(type(uint256).max));
        assertEq(h.pool(first), 0, "poisoned tag is unreadable");
        h.pool(first + 4, next);
        assertEq(h.pool(first), 0, "retired key is unreadable");
        assertEq(h.pool(first + 4), next);
        assertEq(uint256(vm.load(address(h), slot)), (uint256(first) + 5) << 128 | next,
            "reuse replaces tag, payload and padding");
        for (uint24 i = 1; i < 4; ++i) assertEq(h.pool(first + i), oldAmount, "other live slots survive");
    }

    function testFuzz_DgnrsNewAllocationResetsClaimsAndHidesHistory(uint24 lvl, uint128 amount, uint96 claimed) public {
        lvl = uint24(bound(lvl, 1, type(uint24).max - 1));
        h.allocate(lvl, amount);
        h.claim(lvl, claimed);
        (uint256 a, uint256 c) = h.allocation(lvl);
        assertEq(a, amount); assertEq(c, claimed);
        (uint128 la, uint128 lc) = lens.levelDgnrsInfo(address(h), lvl);
        assertEq(la, amount); assertEq(lc, claimed);
        vm.store(address(h), bytes32(GameSlots.LEVEL_DGNRS_PACKED), bytes32(type(uint256).max));
        h.allocate(lvl + 1, 123);
        (a, c) = h.allocation(lvl + 1);
        assertEq(a, 123); assertEq(c, 0, "new level has no stale claims");
        (a, c) = h.allocation(lvl);
        assertEq(a | c, 0, "old level has no allocation");
        (la, lc) = lens.levelDgnrsInfo(address(h), lvl);
        assertEq(uint256(la) | lc, 0, "Lens hides retired allocation");
        assertEq(uint256(vm.load(address(h), bytes32(GameSlots.LEVEL_DGNRS_PACKED))), (uint256(1) << 255) | 123);
        h.allocate(lvl + 1, 0);
        assertEq(uint256(vm.load(address(h), bytes32(GameSlots.LEVEL_DGNRS_PACKED))), uint256(1) << 255);
    }

    function test_TicketGenerationRetainsFirstBlockAndEmitsEachNewWindow() public {
        vm.roll(80);
        vm.recordLogs();
        h.mark(1);
        vm.roll(90);
        h.mark(1);
        assertEq(h.start(1), 80);
        h.mark(2);
        assertEq(h.start(1), 0, "old bound comes from the event");
        assertEq(h.start(2), 90);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "one event per generation window");
        assertEq(logs[0].topics[0], keccak256("TicketGenerationStarted(uint24,uint256)"));
        assertEq(uint256(logs[0].topics[1]), 1);
        assertEq(abi.decode(logs[0].data, (uint256)), 80);
        assertEq(uint256(logs[1].topics[1]), 2);
        assertEq(abi.decode(logs[1].data, (uint256)), 90);
        vm.store(address(h), bytes32(GameSlots.TICKET_GENERATION_START_BLOCK), bytes32(type(uint256).max));
        h.mark(3);
        assertEq(uint256(vm.load(address(h), bytes32(GameSlots.TICKET_GENERATION_START_BLOCK))), (90 << 24) | 3);
    }

    function test_DecimatorRoundGuardCountAndPairReset() public {
        h.open(5);
        h.append(5, 11); h.append(5, 22); h.append(5, 33); h.append(5, 44);
        h.open(10);
        assertEq(h.entry(5, 1), 0, "old round is unreadable");
        assertEq(h.entry(10, 1), 0, "empty new round cannot read old bank");
        bytes32 first = keccak256(abi.encode(uint256(0), GameSlots.DEC_BATTLE_ENTRIES));
        vm.store(address(h), first, bytes32(type(uint256).max));
        h.append(10, 55);
        assertEq(uint256(vm.load(address(h), first)), 55, "first lane replaces stale sibling");
        assertEq(h.entry(10, 1), 55);
        assertEq(h.entry(10, 2), 0, "unwritten sibling remains invisible");
        h.append(10, 66);
        h.update(10, 1, 77);
        assertEq(h.entry(10, 1), 77); assertEq(h.entry(10, 2), 66, "top-up preserves live sibling");
        h.append(10, 88);
        assertEq(h.entry(10, 3), 88); assertEq(h.entry(10, 4), 0);
        assertEq(h.entry(10, 0), 0);
    }

    function testFuzz_FarFutureClearRetainsWordAndPreservesOtherLevel(uint32 count) public {
        count = uint32(bound(count, 1, 0x3fffffff));
        h.owed(1, 7, count); h.owed(2, 7, 9);
        bytes32 slot = keccak256(abi.encode(uint32(7), GameSlots.FAR_FUTURE_OWED));
        h.owed(1, 7, 0);
        assertEq(h.owed(1, 7), 0); assertEq(h.owed(2, 7), 9);
        assertEq(uint32(uint256(vm.load(address(h), slot))), 0x40000000);
        h.owed(1, 7, count);
        assertEq(h.owed(1, 7), count); assertEq(h.owed(2, 7), 9);
    }

    function testFuzz_SubMetaClearRetainsWordAndPreservesSibling(uint32 id, uint32 value) public {
        id = uint32(bound(id, 4, type(uint32).max - 1));
        h.sub(id, value); h.sub(id ^ 1, 777);
        h.sub(id, 0);
        assertEq(h.sub(id), 0); assertEq(h.sub(id ^ 1), 777);
        bytes32 slot = keccak256(abi.encode(id >> 2, GameSlots.SUB_META));
        assertEq(uint64(uint256(vm.load(address(h), slot)) >> ((id & 3) * 64)), uint64(1) << 63);
        h.sub(id, value);
        assertEq(h.sub(id), value); assertEq(h.sub(id ^ 1), 777);
    }
}
