// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";

/// @title SnapValveHarness — drives the REAL processTicketBatch drain with a
///        non-zero snapShift. Test-only; NO contracts/*.sol is mutated. Adds only
///        seeders, setters, and inspection views over the inherited module.
contract SnapValveHarness is DegenerusGameMintModule {
    function seedQueue(uint24 lvl, uint256 n, uint32 owedEach, uint8 remEach, uint160 base) external {
        _lrWrite(LR_INDEX_SHIFT, LR_INDEX_MASK, 1);
        lootboxRngWordByIndex[0] = uint256(keccak256("snapvalve_entropy")) | 1;

        uint24 rk = _tqReadKey(lvl);
        address[] storage queue = ticketQueue[rk];
        mapping(address => uint48) storage owedMap = entriesOwedPacked[rk];
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            queue.push(p);
            owedMap[p] = (uint48(owedEach) << 8) | uint48(remEach);
        }
        ticketCursor = 0;
        ticketLevel = 0;
    }

    function setSnapShift(uint8 s) external {
        snapShift = s;
    }

    function setPending(uint24 lvl, uint8 s) external {
        snapLevel = lvl;
        snapPendingShift = s;
    }

    function exposedSnapShiftFor(uint24 lvl) external view returns (uint8) {
        return _snapShiftFor(lvl);
    }

    function owedPacked(uint24 lvl, address p) external view returns (uint48) {
        return entriesOwedPacked[_tqReadKey(lvl)][p];
    }

    function snapDoneBit() external pure returns (uint48) {
        return SNAP_DONE_BIT;
    }

    function exposedSnapOwedPacked(uint48 packed, uint8 s) external pure returns (uint48) {
        return _snapOwedPacked(packed, s);
    }

    function queueLen(uint24 lvl) external view returns (uint256) {
        return ticketQueue[_tqReadKey(lvl)].length;
    }

    function seedFarFutureQueue(uint24 lvl, uint256 n, uint32 owedEach, uint160 base) external {
        uint24 ffk = _tqFarFutureKey(lvl);
        address[] storage queue = ticketQueue[ffk];
        mapping(address => uint48) storage owedMap = entriesOwedPacked[ffk];
        for (uint256 i; i < n; ++i) {
            address p = address(base + uint160(i + 1));
            queue.push(p);
            owedMap[p] = uint48(owedEach) << 8;
        }
        // Arm the FF resume marker so processFutureTicketBatch drains the FF key.
        ticketLevel = lvl | TICKET_FAR_FUTURE_BIT;
        ticketCursor = 0;
    }
}

contract SnapValveTest is Test {
    SnapValveHarness h;
    uint24 constant LVL = 7;
    uint160 constant BASE = 0xA000;
    bytes32 constant TRAITS_SIG = keccak256("TraitsGenerated(address,uint256,uint32)");

    function setUp() public {
        h = new SnapValveHarness();
    }

    // --- _snapOwedPacked math -------------------------------------------------

    /// Fold correctness, flag placement, and bit disjointness for all inputs.
    function testFuzz_snapFold(uint32 owed, uint8 rem, uint8 s) public view {
        rem = uint8(bound(rem, 0, 99));
        s = uint8(bound(s, 1, 40));
        uint48 packed = (uint48(owed) << 8) | uint48(rem);
        uint48 snapped = h.exposedSnapOwedPacked(packed, s);

        uint256 scaled = (uint256(owed) * 100 + rem) >> s;
        assertEq(uint32(snapped >> 8), uint32(scaled / 100), "owed fold");
        assertEq(uint8(snapped), uint8(scaled % 100), "rem fold");
        assertTrue(snapped & h.snapDoneBit() != 0, "flag set");
        // No bits above the flag; rem stays below 100.
        assertEq(snapped >> 41, 0, "no stray high bits");
        assertLt(uint8(snapped), 100, "rem < QTY_SCALE");
    }

    // --- Drain behavior -------------------------------------------------------

    function _drainAll() internal returns (uint256 totalTake) {
        vm.recordLogs();
        for (uint256 i; i < 200; ++i) {
            (bool finished, ) = h.processTicketBatch(LVL);
            if (finished) break;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TRAITS_SIG) {
                (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
                totalTake += take;
            }
        }
    }

    function _drainAllFuture() internal returns (uint256 totalTake) {
        uint256 entropy = uint256(keccak256("snapvalve_future_entropy")) | 1;
        vm.recordLogs();
        for (uint256 i; i < 200; ++i) {
            (, bool finished, ) = h.processFutureTicketBatch(LVL, entropy);
            if (finished) break;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TRAITS_SIG) {
                (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
                totalTake += take;
            }
        }
    }

    /// Refactor guard: the future drain (shared per-entry engine) is identity at
    /// s = 0 and divides exactly at s = 2, including a whale spanning batches.
    function test_futureDrainDormantAndSnapped() public {
        h.seedQueue(LVL, 5, 8, 0, BASE);
        assertEq(_drainAllFuture(), 5 * 8, "future drain identity at s=0");

        h.seedQueue(LVL, 5, 8, 0, BASE + 50);
        h.setSnapShift(2);
        assertEq(_drainAllFuture(), 5 * 2, "future drain quarters at s=2");

        h.seedQueue(LVL, 1, 2000, 0, BASE + 100);
        assertEq(_drainAllFuture(), 2000 >> 2, "whale single division across batches");
        assertEq(h.owedPacked(LVL, address(BASE + 101)), 0, "whale cleared, no residue");
    }

    /// Refactor guard: the far-future key path drains through the same engine.
    function test_futureDrainFarFutureKey() public {
        h.setSnapShift(1);
        h.seedFarFutureQueue(LVL, 4, 10, BASE);
        assertEq(_drainAllFuture(), 4 * 5, "FF key halved at s=1");
    }

    /// Dormant valve (s = 0): drain generates exactly the raw owed count.
    function test_dormantDrainIsIdentity() public {
        h.seedQueue(LVL, 5, 8, 0, BASE);
        uint256 total = _drainAll();
        assertEq(total, 5 * 8, "raw count at s=0");
        for (uint256 i; i < 5; ++i) {
            assertEq(h.owedPacked(LVL, address(BASE + uint160(i + 1))), 0, "cleared");
        }
    }

    /// s = 1 halves every balance exactly (even counts, no remainder).
    function test_snapHalvesGeneratedEntries() public {
        h.seedQueue(LVL, 5, 8, 0, BASE);
        h.setSnapShift(1);
        uint256 total = _drainAll();
        assertEq(total, 5 * 4, "halved at s=1");
    }

    /// Un-thanos: a pending declaration below the active shift applies from its
    /// target level onward while earlier levels keep the higher active exponent.
    function test_unThanosBoundary() public {
        h.setSnapShift(2);
        h.setPending(LVL + 1, 0);
        assertEq(h.exposedSnapShiftFor(LVL), 2, "below target keeps active");
        assertEq(h.exposedSnapShiftFor(LVL + 1), 0, "target level un-thanosed");
        h.seedQueue(LVL, 5, 8, 0, BASE);
        uint256 total = _drainAll();
        assertEq(total, 5 * 2, "level below the un-thanos still divides");
    }

    /// A pending declaration applies exactly from its target level onward.
    function test_pendingDeclarationBoundary() public {
        h.setSnapShift(0);
        h.setPending(LVL, 2);
        assertEq(h.exposedSnapShiftFor(LVL - 1), 0, "below target: active shift");
        assertEq(h.exposedSnapShiftFor(LVL), 2, "at target: pending shift");
        assertEq(h.exposedSnapShiftFor(LVL + 3), 2, "past target: pending shift");

        // Drain of the declared level divides; the level below does not.
        h.seedQueue(LVL, 5, 8, 0, BASE);
        uint256 total = _drainAll();
        assertEq(total, 5 * 2, "quartered at declared level");
    }

    /// A whale spanning multiple budget-limited batches is divided exactly once:
    /// total generated == owed >> s, and the mid-drain balance carries the marker.
    function test_whaleResumeSingleDivision() public {
        h.seedQueue(LVL, 1, 2000, 0, BASE);
        h.setSnapShift(2);
        address whale = address(BASE + 1);

        (bool finished, ) = h.processTicketBatch(LVL);
        assertFalse(finished, "must span batches");
        uint48 mid = h.owedPacked(LVL, whale);
        assertTrue(mid & h.snapDoneBit() != 0, "marker persists mid-drain");
        assertLt(uint32(mid >> 8), 500, "partially consumed post-snap balance");

        vm.recordLogs();
        for (uint256 i; i < 200; ++i) {
            (bool fin, ) = h.processTicketBatch(LVL);
            if (fin) break;
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 tail;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == TRAITS_SIG) {
                (, uint32 take) = abi.decode(logs[i].data, (uint256, uint32));
                tail += take;
            }
        }
        // First batch's take = 2000>>2 minus what the tail batches generated.
        assertEq(h.owedPacked(LVL, whale), 0, "fully drained to zero, no flag residue");
        assertLt(tail, 500, "first batch did some of the work");
        // Whole-queue conservation: re-seed and drain in one recording for the exact total.
        h.seedQueue(LVL, 1, 2000, 0, BASE + 100);
        uint256 total = _drainAll();
        assertEq(total, 2000 >> 2, "exactly one division across resumes");
    }

    /// Sub-unit balances fold into the remainder and Bernoulli-resolve to 0 or 1.
    function test_smallBalanceFoldsToRemainder() public {
        h.seedQueue(LVL, 1, 1, 0, BASE);
        h.setSnapShift(1); // (100)>>1 = 50 -> owed 0, rem 50
        uint256 total = _drainAll();
        assertLe(total, 1, "0 or 1 from the 50% remainder roll");
        assertEq(h.owedPacked(LVL, address(BASE + 1)), 0, "cleared regardless of roll");
    }

    /// Mixed remainders: expectation-preserving fold, exact per-player floor+roll bound.
    function test_remainderFoldBounds() public {
        h.seedQueue(LVL, 10, 5, 50, BASE); // each: (550)>>2 = 137 -> owed 1, rem 37
        h.setSnapShift(2);
        uint256 total = _drainAll();
        assertGe(total, 10, "at least floor per player");
        assertLe(total, 20, "at most floor+1 per player");
        for (uint256 i; i < 10; ++i) {
            assertEq(h.owedPacked(LVL, address(BASE + uint160(i + 1))), 0, "cleared");
        }
    }

}
