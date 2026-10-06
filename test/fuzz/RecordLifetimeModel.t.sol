// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {TicketLevelPrep} from "../helpers/TicketLevelPrep.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";

/// @dev Setup advances completed levels; admission, lane mutation, tombstones,
///      queue release and inventory construction use production primitives.
///      This is not a complete engine reachability campaign.
contract RecordLifetimeHarness is TicketLevelPrep, WalletSeed {
    function atLevel(uint24 current) external { level = current; }
    function add(address owner, uint24 target, uint32 amount) external { _queueEntries(_seedWallet(owner), target, amount, false); }
    function flip() external { ticketWriteSlot = !ticketWriteSlot; }
    function writeKey(uint24 target) external view returns (uint24) { return _tqWriteKey(target); }
    function owed(uint24 key, address owner) external view returns (uint32) { return uint32(_owedOf(key, owner) >> 8); }
    function count(uint24 key) external view returns (uint256) { return _ticketQueueLength(key); }
    function id(address owner) external view returns (uint32) { return _walletIdOf(owner); }
    function ownerAt(uint24 key, uint256 index) external view returns (address) {
        require(index < _ticketQueueLength(key));
        return _walletKey(_tqPositionAt(ticketQueue[_ticketQueueStorageKey(key)], index));
    }
    function cancel(uint24 key, address owner) external { _setEntryOwed(key, _walletIdOf(owner), 0); }
    function drain(uint24 key, uint8 trait) external returns (uint256 quantity) {
        uint24 target = key & 0x3fffff;
        require(_prepareTicketLevel(target), "old paid readers remain");
        uint256[] storage q = ticketQueue[_ticketQueueStorageKey(key)];
        uint256 length = _ticketQueueLength(key);
        for (uint256 i; i < length; ++i) {
            uint32 ownerId = _tqPositionAt(q, i);
            uint32 n = uint32(_entryPacked(key, ownerId) >> 8);
            if (n != 0) _bucketAppendRun(_traitBufferBase(target), trait, ownerId - 1, n, target);
            quantity += n;
            _setEntryOwed(key, ownerId, 0);
        }
        _releaseTicketQueue(key);
    }
    function staleRelease(uint24 key) external { _releaseTicketQueue(key); }
    function ticketCount(uint24 target, uint8 trait) external view returns (uint256) { return _bucketLength(target, trait); }
    function ticketOwner(uint24 target, uint8 trait, uint256 i) external view returns (address) {
        require(i < _bucketLength(target, trait));
        return _bucketOwnerAt(target, trait, i);
    }
}

contract RecordLifetimeModelTest is Test {
    RecordLifetimeHarness private h;
    uint24 private constant FAR = 1 << 22;
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    // Absolute target -> domain -> owner. No parity/modulo identifies oracle data.
    mapping(uint24 => mapping(uint8 => mapping(address => uint32))) private expected;
    uint256 private submitted;
    uint256 private canceled;
    uint256 private settled;
    uint256 private reuseVisits;

    function setUp() public { h = new RecordLifetimeHarness(); }

    function _add(uint24 target, uint8 domain, address who, uint32 n) private {
        h.add(who, target, n);
        expected[target][domain][who] += n;
        submitted += n;
    }

    function _checkDrain(uint24 target, uint8 domain, uint24 key) private {
        assertEq(h.owed(key, ALICE), expected[target][domain][ALICE]);
        assertEq(h.owed(key, BOB), expected[target][domain][BOB]);
        uint256 amount = uint256(expected[target][domain][ALICE]) + expected[target][domain][BOB];
        assertEq(h.drain(key, 7), amount);
        settled += amount;
        expected[target][domain][ALICE] = 0;
        expected[target][domain][BOB] = 0;
        assertEq(h.owed(key, ALICE), 0);
        assertEq(h.owed(key, BOB), 0);
        assertEq(h.count(key), 0);
    }

    function test_AllDomainsSameWalletThroughJointPeriod3200() public {
        // Warm up the oldest future cohort with the same wallets later used in both near domains.
        h.atLevel(0);
        _add(2, 2, ALICE, 3);
        _add(2, 2, BOB, 5);
        uint24[5] memory deltas = [uint24(2), 4, 100, 128, 3200];
        for (uint24 target = 1; target <= 3202; ++target) {
            h.atLevel(target - 1);
            uint24 first = h.writeKey(target);
            uint32 aliceAmount = 1 + uint32(target % 11);
            _add(target, 0, ALICE, aliceAmount);
            _add(target, 0, BOB, 9); // crossed packed owner tail in earlier tests; canceled here.
            if (target % 3 == 0) {
                h.cancel(first, BOB);
                canceled += 9;
                expected[target][0][BOB] = 0;
            }
            h.flip();
            uint24 second = h.writeKey(target);
            _add(target, 1, ALICE, 13);
            _add(target, 1, BOB, 2);
            if (target > 128) {
                assertEq(h.owed(first - 128, ALICE), 0, "new live pending cannot authenticate old 128-generation tag");
                assertEq(h.owed(second - 128, ALICE), 0, "second domain also authenticates full level");
            }
            assertEq(h.id(ALICE), 1, "permanent owner identity");
            assertEq(h.id(BOB), 2, "permanent owner identity");
            assertEq(h.ownerAt(first, 0), ALICE);
            assertEq(h.ownerAt(second, 0), ALICE);
            uint256 expectedInventory = uint256(expected[target][0][ALICE]) + expected[target][0][BOB]
                + expected[target][1][ALICE] + expected[target][1][BOB]
                + expected[target][2][ALICE] + expected[target][2][BOB];
            _checkDrain(target, 0, first);
            _checkDrain(target, 1, second);
            _checkDrain(target, 2, target | FAR);
            assertEq(h.ticketCount(target, 7), expectedInventory, "inventory conservation at checkpoint");
            assertEq(h.ticketOwner(target, 7, 0), ALICE);
            for (uint256 j; j < deltas.length; ++j) {
                if (target <= deltas[j]) continue;
                uint24 old = target - deltas[j];
                assertEq(h.owed(old, ALICE), 0);
                assertEq(h.owed(old | (1 << 23), ALICE), 0);
                assertEq(h.owed(old | FAR, ALICE), 0);
                ++reuseVisits;
            }
            // Next target + 1 is the smallest far-future level under the current completed level.
            _add(target + 2, 2, ALICE, 3);
            _add(target + 2, 2, BOB, 5);
            h.staleRelease(target > 100 ? (target - 100) | FAR : target | FAR);
            assertEq(h.owed((target + 2) | FAR, ALICE), 3, "stale release preserves live future work");
            // Two future cohorts remain after every ordinary iteration (except genesis).
            uint256 futurePending = 16;
            assertEq(submitted, canceled + settled + futurePending, "absolute accounting after every level");
        }
        assertGt(reuseVisits, 10_000, "all named alias boundaries actually visited");
        h.atLevel(3202);
        _checkDrain(3203, 2, 3203 | FAR);
        h.atLevel(3203);
        _checkDrain(3204, 2, 3204 | FAR);
        assertEq(submitted, canceled + settled, "bounded drain suffix has no orphan");
    }

    function testFuzz_LiveNonemptyRootRefusesNewGeneration(uint24 start, uint32 amount) public {
        uint24 target = uint24(bound(start, 2, 4_000_000));
        amount = uint32(bound(amount, 1, 1_000));
        h.atLevel(target - 2);
        h.add(ALICE, target, amount);
        vm.expectRevert(DegenerusGameStorage.E.selector);
        h.add(BOB, target + 100, 1);
        assertEq(h.count(target | FAR), 1);
        assertEq(h.owed(target | FAR, ALICE), amount);
        h.atLevel(target - 1);
        assertEq(h.drain(target | FAR, 7), amount, "rejected new admission does not brick older settlement");
        h.atLevel(target + 98);
        h.add(BOB, target + 100, 1);
        assertEq(h.count(target | FAR), 0, "old full level cannot authenticate new occupant");
        assertEq(h.owed((target + 100) | FAR, BOB), 1);
    }
}
