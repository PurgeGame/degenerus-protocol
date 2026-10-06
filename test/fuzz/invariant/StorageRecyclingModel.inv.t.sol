// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CohortRecyclingHarness} from "../RngCohortRecycling.t.sol";
import {TicketRecyclingHarness} from "../TicketStorageRecycling.t.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @dev This storage model has no redemption consumer. The production completion
/// check still queries its pinned external frontier, which must exist in the fixture.
contract StorageRecyclingSdgnrsFrontier {
    function redemptionSettlementPending() external pure returns (bool) { return false; }
}

/// @dev Independent lifetime books against the production binary storage primitives.
/// The monotonically increasing reference epoch exists only in this test oracle.
///      Consumer execution/routing is covered separately by the unaided keeper regressions.
contract CohortReferenceHandler is Test {
    CohortRecyclingHarness public immutable h;
    uint48 public active = 1;
    bool public delivered;
    bool public ticketsDone;
    uint48 public frontier;
    uint256 public seals;
    uint256 public completions;
    uint256 public refusals;
    /// @dev Stored entry words per epoch, in append order: one entry per purchase, never merged.
    mapping(uint48 => uint256[]) internal entries;
    mapping(uint48 => uint256) public wordByIndex;
    mapping(uint48 => uint256) public fields;
    mapping(uint48 => uint256) public processed;
    constructor(CohortRecyclingHarness harness) { h = harness; }
    function buyer(uint256 seed) public pure returns (address) { return address(uint160(0xCA1100 + seed % 4)); }
    function buy(uint256 seed, uint256 payload) public {
        if (entries[active].length >= 8) return;
        uint48 write = uint48((active - 1) & 1);
        uint256 position = entries[active].length;
        h.queueBox(buyer(seed), (payload & ((uint256(1) << 223) - 1)) | 1);
        uint256 stored = h.entry(write, position);
        assertTrue(uint32(stored) != 0, "entry carries the wallet ID");
        entries[active].push(stored);
    }
    function arm() public {
        if (fields[active] >= 4) return;
        ++fields[active];
        h.craps(uint48((active - 1) & 1), true);
    }
    function complete() public view returns (bool) {
        return active == 1 || (delivered && ticketsDone && frontier > active - 1
            && processed[active - 1] == entries[active - 1].length && fields[active - 1] == 0);
    }
    function seal() public {
        assertEq(h.complete(), complete(), "completion differs from actual-index reference");
        if (!complete()) { ++refusals; return; }
        h.seal();
        ++active;
        ++seals;
        delivered = false;
        ticketsDone = false;
        h.tickets(false);
    }
    function deliver(uint256 seed) public {
        if (active == 1 || delivered) return;
        uint256 word = seed | 2;
        wordByIndex[active - 1] = word;
        delivered = true;
        h.ready(word);
    }
    function finishTickets() public {
        if (!delivered) return;
        ticketsDone = true;
        h.tickets(true);
    }
    /// @dev The FIFO settles the whole read cohort: the cursor reaches the read count.
    function open() public {
        if (!delivered) return;
        uint48 read = active - 1;
        processed[read] = entries[read].length;
        h.processed();
        frontier = active;
        h.frontier(true);
    }
    function settleField() public {
        if (!delivered || fields[active - 1] == 0) return;
        if (--fields[active - 1] == 0) h.craps(uint48((active - 2) & 1), false);
        ++completions;
    }
    function assertReference() external view {
        uint48 write = uint48((active - 1) & 1);
        uint48 read = write ^ 1;
        assertEq(h.writeBuffer(), write);
        assertEq(h.readBuffer(), read);
        assertEq(h.complete(), complete());
        (uint256 count, uint256 bets) = h.writeCounts();
        assertEq(count, entries[active].length, "write count is this epoch's appends");
        assertEq(bets, 0);
        assertEq(h.word(write), 0, "unsealed write word must be inaccessible");
        for (uint256 i; i < count; ++i) {
            assertEq(h.entry(write, i), entries[active][i], "reused write holds only its current epoch's entries");
        }
        if (active > 1) {
            (count, bets) = h.readCounts();
            assertEq(count, entries[active - 1].length, "read count latched at the seal");
            assertEq(bets, 0);
            assertEq(h.word(read), delivered ? wordByIndex[active - 1] : 0);
            for (uint256 i; i < count; ++i) assertEq(h.entry(read, i), entries[active - 1][i], "sealed entries unchanged");
        }
        assertEq(h.word(2), 0, "nonphysical tags cannot expose historical words");
    }
}

contract TicketReferenceHandler is Test {
    TicketRecyclingHarness public immutable h;
    uint24 public newest = 2;
    uint24[2] public stamps;
    uint256 public retirements;
    bool public foil;
    mapping(uint24 => bool) public pendingRead;
    mapping(uint24 => bool) public pendingWrite;
    mapping(uint24 => mapping(uint8 => address[])) internal owners;
    constructor(TicketRecyclingHarness harness) {
        h = harness;
        require(h.prepare(1) && h.prepare(2));
        stamps[0] = 2; stamps[1] = 1;
        h.completed(2);
    }
    function append(uint256 which, uint256 traitSeed, uint256 ownerSeed, uint256 nSeed) public {
        uint24 lvl = stamps[which & 1];
        uint8 trait = uint8(traitSeed % 4);
        uint256 n = 1 + nSeed % 16;
        if (owners[lvl][trait].length >= 256) return;
        address owner = address(uint160(0x710000 + ownerSeed % 8));
        h.append(lvl, trait, owner, n);
        for (uint256 i; i < n; ++i) owners[lvl][trait].push(owner);
    }
    function queue(bool write, bool pending) public {
        uint24 old = stamps[(newest + 1) & 1];
        if (write) pendingWrite[old] = pending;
        else pendingRead[old] = pending;
        h.pending(old, write, pending ? 1 : 0);
    }
    function setFoil(bool pending) public { foil = pending; h.foilPending(0, pending ? 1 : 0); }
    function rotate() public {
        if (newest >= 32) return;
        uint24 next = newest + 1;
        uint24 old = stamps[next & 1];
        bool expected = !pendingRead[old] && !pendingWrite[old] && !foil;
        assertEq(h.prepare(next), expected, "takeover cannot ignore committed queue halves or foil");
        if (!expected) return;
        stamps[next & 1] = next;
        newest = next;
        h.completed(next);
        ++retirements;
    }
    function assertReference() external view {
        for (uint256 slot; slot < 2; ++slot) {
            uint24 lvl = stamps[slot];
            assertFalse(h.retired(lvl));
            for (uint8 trait; trait < 4; ++trait) {
                address[] storage ref = owners[lvl][trait];
                assertEq(h.count(lvl, trait), ref.length);
                for (uint256 i; i < ref.length; ++i) assertEq(h.ownerAt(lvl, trait, i), ref[i], "stale lane or wrong owner index");
            }
            if (lvl > 2) assertTrue(h.retired(lvl - 2));
        }
    }
}

contract StorageRecyclingReferenceInvariant is StdInvariant, Test {
    CohortReferenceHandler cohort;
    TicketReferenceHandler tickets;
    function setUp() public {
        vm.etch(ContractAddresses.SDGNRS, address(new StorageRecyclingSdgnrsFrontier()).code);
        cohort = new CohortReferenceHandler(new CohortRecyclingHarness());
        tickets = new TicketReferenceHandler(new TicketRecyclingHarness());
        // Every campaign starts beyond actual reuse/retirement, not a vacuous virgin state.
        for (uint256 i; i < 4; ++i) {
            cohort.buy(0, 123 + i); cohort.arm(); cohort.seal(); cohort.deliver(11 + i);
            cohort.finishTickets(); cohort.open(); cohort.settleField();
            tickets.append(i, i, i, 8); tickets.rotate();
        }
        targetContract(address(cohort)); targetContract(address(tickets));
    }
    function invariant_ActualIndexReferenceMatchesRecycledCohorts() public view { cohort.assertReference(); }
    function invariant_ActualLevelReferenceMatchesRetainedTraitLanes() public view { tickets.assertReference(); }
    function afterInvariant() public view {
        assertGe(cohort.seals(), 4); assertGe(cohort.completions(), 4);
        assertGe(tickets.retirements(), 4);
        cohort.assertReference(); tickets.assertReference();
    }
}
