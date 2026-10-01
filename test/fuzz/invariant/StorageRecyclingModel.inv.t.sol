// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {CohortRecyclingHarness} from "../RngCohortRecycling.t.sol";
import {TicketRecyclingHarness} from "../TicketStorageRecycling.t.sol";

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
    mapping(uint48 => mapping(address => uint256)) public orders;
    mapping(uint48 => address[]) internal players;
    mapping(uint48 => uint256) public wordByIndex;
    mapping(uint48 => uint256) public fields;
    mapping(uint48 => uint256) public processed;
    constructor(CohortRecyclingHarness harness) { h = harness; }
    function buyer(uint256 seed) public pure returns (address) { return address(uint160(0xCA1100 + seed % 4)); }
    function buy(uint256 seed, uint256 payload) public {
        address owner = buyer(seed);
        if (orders[active][owner] != 0) return;
        uint256 word = (payload & ((uint256(1) << 255) - 1)) | 1;
        orders[active][owner] = word;
        players[active].push(owner);
        h.queueBox(owner, word);
    }
    function arm() public {
        if (fields[active] >= 4) return;
        ++fields[active];
        h.craps(uint48((active - 1) & 1), true);
    }
    function complete() public view returns (bool) {
        return active == 1 || (delivered && ticketsDone && frontier > active - 1
            && processed[active - 1] == players[active - 1].length && fields[active - 1] == 0);
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
    function open() public {
        if (!delivered) return;
        uint48 read = active - 1;
        uint256 pos = processed[read];
        if (pos < players[read].length) {
            address owner = players[read][pos];
            orders[read][owner] = 0;
            h.processed(owner);
            ++processed[read];
        }
        if (processed[read] == players[read].length) { frontier = active; h.frontier(true); }
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
        (uint256 count, uint256 bets) = h.counts(write);
        assertEq(count, players[active].length);
        assertEq(bets, 0);
        assertEq(h.word(write), 0, "unsealed write word must be inaccessible");
        if (active > 1) {
            (count, bets) = h.counts(read);
            assertEq(count, players[active - 1].length);
            assertEq(bets, 0);
            assertEq(h.word(read), delivered ? wordByIndex[active - 1] : 0);
        }
        for (uint256 i; i < 4; ++i) {
            address owner = buyer(i);
            assertEq(h.order(write, owner), orders[active][owner], "reused write contains only its current epoch");
            if (active > 1) assertEq(h.order(read, owner), orders[active - 1][owner]);
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
