// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {SeatFixture} from "./SeatConsumption.t.sol";
import {WalletSeed} from "../helpers/WalletSeed.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {AFKingSubscriptionToken} from "../../contracts/AFKingSubscriptionToken.sol";
import {BitPackingLib} from "../../contracts/libraries/BitPackingLib.sol";

/// @dev Storage-only access to the `_subMeta` helpers and the capacity constants.
contract SubMetaHarness is WalletSeed {
    function setLane(uint32 id, uint256 lane) external { _setSubMetaLane(id, lane); }
    function setPosition1(uint32 id, uint256 position1) external { _setSubPosition1(id, position1); }
    function setRunStart(uint32 id, uint256 day) external { _setSubRunStart(id, day); }
    function position1(uint32 id) external view returns (uint256) { return _subPosition1(id); }
    function runStart(uint32 id) external view returns (uint24) { return _subRunStart(id); }
    function rawWord(uint32 id) external view returns (uint256) { return _subMeta[id >> 2]; }
    function cap() external pure returns (uint256) { return SUBSCRIBER_CAP; }
    function ticketPhase() external pure returns (uint256) { return SUBSCRIBER_TICKET_PHASE; }
    function positionMask() external pure returns (uint256) { return SUB_META_POSITION_MASK; }
    function runStartShift() external pure returns (uint256) { return SUB_META_RUN_START_SHIFT; }
    function dayMask() external pure returns (uint256) { return SUB_DAY_MASK; }
}

/// @dev Etched over the Game for fixture seeding only: registers fresh wallets and places them
///      in the two-ended set with a given run-start day, as production membership lays them out.
contract CapacitySeeder is WalletSeed {
    function seed(uint256 boxes, uint256 tickets, uint160 base, uint24 runStart) external {
        for (uint256 i; i < boxes + tickets; ++i) {
            uint32 id = _seedWallet(address(base + uint160(i)));
            _seedSubscriber(id, i >= boxes);
            _setSubRunStart(id, runStart);
        }
    }
}

/// @title SubMetaLaneTest -- the widened `_subMeta` lane in isolation.
contract SubMetaLaneTest is Test {
    SubMetaHarness internal h;

    function setUp() public {
        h = new SubMetaHarness();
    }

    function test_CapacityConstantsFitTheirFields() public view {
        assertEq(h.cap(), 10_002, "10,000 player places plus the two protocol subscriptions");
        assertEq(h.positionMask(), 0x3fff);
        assertEq(h.runStartShift(), 14);
        // Physical positions run 0..cap, so position + 1 reaches cap + 1.
        assertLe(h.cap() + 1, h.positionMask(), "position + 1 fits");
        // The run-start day sits below the allocated bit 63.
        assertLe(h.runStartShift() + 22, 63, "run-start day below bit 63");
        // Section offsets reach the member count and stay below the ticket-section bit; the
        // cursor stays inside its uint16.
        assertLt(h.cap(), h.ticketPhase(), "section offsets below bit 15");
        assertLt(h.ticketPhase() + h.cap(), uint256(type(uint16).max), "ticket cursor fits uint16");
    }

    function _positions() internal view returns (uint256[9] memory p) {
        p = [uint256(1), 2047, 2048, 2049, 8191, 8192, 8193, h.cap(), h.cap() + 1];
    }

    /// @notice Positions across the old 11-bit edge, the 13-bit edge and the new maximum read back
    ///         exactly; a position write keeps the run-start day and a run-start write keeps the
    ///         position; the three neighbouring lanes in the word never move.
    function testFuzz_PositionAndRunStartRoundTrip(uint256 pick, uint24 day, uint32 id, uint256 neighbourSeed) public {
        uint256[9] memory positions = _positions();
        uint256 position = positions[pick % positions.length];
        day = uint24(bound(day, 0, h.dayMask()));
        id = uint32(bound(id, 4, type(uint32).max));
        uint32 base = id & ~uint32(3);
        // Populate every lane of the word with distinct values first.
        for (uint32 k; k < 4; ++k) {
            uint256 np = 1 + uint256(keccak256(abi.encode(neighbourSeed, k))) % (h.cap() + 1);
            uint256 nd = uint256(keccak256(abi.encode(neighbourSeed, k, "day"))) & h.dayMask();
            h.setLane(base + k, np | (nd << h.runStartShift()));
        }
        uint256 word = h.rawWord(id);

        h.setRunStart(id, day);
        h.setPosition1(id, position);
        assertEq(h.position1(id), position, "position + 1 reads back");
        assertEq(h.runStart(id), day, "the position write keeps the run-start day");

        uint24 otherDay = uint24((uint256(day) + 12_345) & h.dayMask());
        h.setRunStart(id, otherDay);
        assertEq(h.position1(id), position, "the run-start write keeps the position");
        assertEq(h.runStart(id), otherDay);

        uint256 shift = (id & 3) * 64;
        uint256 others = ~(uint256(type(uint64).max) << shift);
        assertEq(h.rawWord(id) & others, word & others, "neighbouring lanes untouched");
        assertEq((h.rawWord(id) >> (shift + 63)) & 1, 1, "allocated bit set");
    }

    /// @notice Each boundary position, explicitly, beside the maximum run-start day.
    function test_BoundaryPositionsWithMaximumDay() public {
        uint256[9] memory positions = _positions();
        uint24 maxDay = uint24(h.dayMask());
        for (uint256 i; i < positions.length; ++i) {
            uint32 id = uint32(100 + i * 4);
            h.setLane(id + 1, positions[(i + 1) % positions.length] | (uint256(7) << h.runStartShift()));
            h.setRunStart(id, maxDay);
            h.setPosition1(id, positions[i]);
            assertEq(h.position1(id), positions[i]);
            assertEq(h.runStart(id), maxDay);
            assertEq(h.position1(id + 1), positions[(i + 1) % positions.length], "neighbour position kept");
            assertEq(h.runStart(id + 1), 7, "neighbour run start kept");
            h.setPosition1(id, 0);
            assertEq(h.position1(id), 0, "cleared position");
            assertEq(h.runStart(id), maxDay, "clearing the position keeps the day");
        }
    }
}

/// @title AfkingCapacityTest -- capacity, packed positions and the free tranche on a real deploy.
contract AfkingCapacityTest is SeatFixture {
    uint256 internal constant CAP = 10_002;
    uint24 internal constant SEEDED_RUN_START = 777;

    function setUp() public {
        _setUpSeats();
    }

    /// @dev Seed `boxes` box members and `tickets` ticket members after the two protocol boxes.
    function _seed(uint256 boxes, uint256 tickets, uint160 base) internal {
        bytes memory runtime = address(game).code;
        vm.etch(address(game), type(CapacitySeeder).runtimeCode);
        CapacitySeeder(address(game)).seed(boxes, tickets, base, SEEDED_RUN_START);
        vm.etch(address(game), runtime);
    }

    function _meta(uint32 id) internal view returns (uint256) {
        return uint64(uint256(vm.load(address(game), keccak256(abi.encode(uint256(id >> 2), GameSlots.SUB_META))))
            >> ((id & 3) * 64));
    }

    function _runStartOf(uint32 id) internal view returns (uint24) {
        return uint24((_meta(id) >> 14) & ((uint256(1) << 22) - 1));
    }

    function _boxCount() internal view returns (uint256) {
        return uint16(uint256(vm.load(address(game), bytes32(GameSlots.SUB_BOX_COUNT))) >> (8 * GameSlots.SUB_BOX_COUNT_OFFSET));
    }

    function _newPlayer(string memory tag) internal returns (address who, uint32 id, uint256 seat) {
        who = makeAddr(tag);
        id = _giveWalletId(who);
        seat = _giveSeat(who);
    }

    function _subscribeMode(address who, bool tickets, uint256 seat) internal {
        vm.deal(who, who.balance + 1 ether);
        vm.prank(who);
        game.subscribe{value: SUB_FUND}(0, tickets, 1, seat);
    }

    /// @notice A real box subscription lands at position + 1 = 2,047, 2,048, 8,191 and 8,192, with
    ///         today's run start; a cancel below it moves it down without touching its run start.
    function test_BoxInsertAndMoveAroundLaneBoundaries() public {
        uint256[4] memory targets = [uint256(2047), 2048, 8191, 8192];
        for (uint256 t; t < targets.length; ++t) {
            uint256 snap = vm.snapshotState();
            // Box positions 0 and 1 are the protocol subscriptions.
            _seed(targets[t] - 3, 0, uint160(0xB0000000));
            assertEq(_boxCount(), targets[t] - 1, "fixture: box count before the insert");
            (address who, uint32 id, uint256 seat) = _newPlayer("boundary-box");
            uint256 neighbour = _meta(id ^ 1);
            _subscribeMode(who, false, seat);
            uint24 today = game.currentDayView_g542950();
            assertEq(_pos(id), targets[t], "position + 1 at the boundary");
            assertEq(_setElement(targets[t] - 1), id, "the lane holds the member");
            assertEq(_runStartOf(id), today, "run starts today");
            assertEq(_meta(id ^ 1), neighbour, "the neighbouring meta lane is untouched");

            // Cancel the seeded member at box position 2: the tail (this member) moves into it.
            uint32 moved = uint32(_setElement(2));
            address movedOwner = address(uint160(0xB0000000));
            assertEq(game.walletIdOf_g3120(movedOwner), moved, "fixture: first seeded member at position 2");
            _cancel(movedOwner, 0);
            assertEq(_pos(moved), 0, "the cancelled member left");
            assertEq(_pos(id), 3, "the tail moved into the freed position");
            assertEq(_runStartOf(id), today, "the move keeps the run start");
            assertEq(_setElement(targets[t] - 1), 0, "the old tail position is cleared");
            vm.revertToState(snap);
        }
    }

    /// @notice The first ticket member sits at the top physical position: position + 1 = 10,003.
    function test_FirstTicketMemberAtTheMaximumPosition() public {
        (address who, uint32 id, uint256 seat) = _newPlayer("top-ticket");
        _subscribeMode(who, true, seat);
        assertEq(_pos(id), CAP + 1, "position + 1 is the maximum");
        assertEq(_setElement(CAP), id, "physical position 10,002");
        assertEq(_runStartOf(id), game.currentDayView_g542950());
        // Cancel and reinsert in box mode: the run start of a mode change is kept.
        vm.prank(who);
        game.subscribe(0, false, 1, 0);
        assertEq(_pos(id), 3, "moved to the box section");
        assertEq(_setElement(CAP), 0, "the top position is cleared");
        assertEq(_runStartOf(id), game.currentDayView_g542950(), "the mode change keeps the run start");
    }

    /// @notice Box-only at capacity: the last box sits at position + 1 = 10,002, the top position
    ///         stays the empty sentinel and one more subscription is refused.
    function test_ExactCapacityBoxesThenOneOverReverts() public {
        _seed(CAP - 3, 0, uint160(0xC0000000));
        assertEq(_S(), CAP - 1);
        (address who, uint32 id, uint256 seat) = _newPlayer("last-box");
        _subscribeMode(who, false, seat);
        assertEq(_S(), CAP, "the set is full");
        assertEq(_pos(id), CAP, "the last box position");
        assertEq(_setElement(CAP), 0, "the sentinel above the boxes is empty");

        (address late, , uint256 lateSeat) = _newPlayer("one-over");
        vm.deal(late, 1 ether);
        vm.prank(late);
        vm.expectRevert(E.selector);
        game.subscribe{value: SUB_FUND}(0, true, 1, lateSeat);
        assertEq(afkingSubToken.ownerOf(lateSeat), late, "the refused subscription burned nothing");
    }

    /// @notice A mixed full set keeps both sections dense around one empty sentinel; one more is
    ///         refused, and a cancel reopens exactly one place.
    function test_ExactCapacityMixedSentinelAndReplenish() public {
        uint256 tickets = 4000;
        _seed(CAP - 3 - tickets, tickets, uint160(0xD0000000));
        (address who, uint32 id, uint256 seat) = _newPlayer("last-ticket");
        _subscribeMode(who, true, seat);
        assertEq(_S(), CAP, "the set is full");
        uint256 boxes = _boxCount();
        assertEq(boxes, CAP - tickets - 1, "box section");
        assertEq(_pos(id), CAP + 1 - tickets, "the last ticket position");
        assertEq(_setElement(boxes), 0, "one empty sentinel between the sections");
        assertTrue(_setElement(boxes - 1) != 0 && _setElement(boxes + 1) != 0, "both sections dense");

        (address late, , uint256 lateSeat) = _newPlayer("mixed-over");
        vm.deal(late, 1 ether);
        vm.prank(late);
        vm.expectRevert(E.selector);
        game.subscribe{value: SUB_FUND}(0, false, 1, lateSeat);

        _cancel(who, 0);
        assertEq(_S(), CAP - 1, "the cancel freed one place");
        _subscribeMode(late, false, lateSeat);
        assertEq(_S(), CAP, "the freed place is reusable");
        assertEq(_pos(game.walletIdOf_g3120(late)), boxes + 1, "the new box takes the sentinel's place");
        assertEq(_setElement(boxes + 1), 0, "the sentinel moved up to the vacated ticket position");
    }

    /// @notice The 5,000th pass purchase receives the last free seat; the next purchaser receives
    ///         none and still latches its one lifetime chance.
    function test_FreeTrancheBoundaryOnRealPassPurchases() public {
        _fillFreeTrancheTo(4999);
        (address last,) = _passBuyer("five-thousandth");
        assertEq(afkingSubToken.balanceOf(last), 1, "the 5,000th purchaser gets a seat");
        assertEq(afkingSubToken.freeClaims(), 5000);

        address after_ = makeAddr("after-tranche");
        vm.deal(after_, 10 ether);
        uint32 next = afkingSubToken.nextSerial();
        vm.prank(after_);
        game.purchaseLazyPass{value: 0.24 ether}(0, bytes32(0));
        assertEq(afkingSubToken.balanceOf(after_), 0, "no seat past the tranche");
        assertEq(afkingSubToken.nextSerial(), next, "no serial consumed");
        assertEq((game.mintPackedFor(after_) >> BitPackingLib.SEAT_CLAIMED_SHIFT) & 1, 1, "the latch is still spent");

        // The vault mint unlocks exactly now and fills only to the cap.
        address to = makeAddr("vault-grantee");
        _mintToCap(to, 0);
        assertEq(_L() + _S(), CAP, "vault mints fill to the cap");
    }

    /// @notice Both protocol subscriptions are live at deployment with no seat, at box positions 0
    ///         and 1, and keep their deity passes.
    function test_ProtocolSubscriptionsAtDeployment() public view {
        assertEq(_pos(VAULT_ID), 1, "Vault at box position 0");
        assertEq(_pos(SDGNRS_ID), 2, "sDGNRS at box position 1");
        assertTrue(_activeId(VAULT_ID) && _activeId(SDGNRS_ID), "both live");
        assertEq(afkingSubToken.balanceOf(address(vault)) + afkingSubToken.balanceOf(address(sdgnrs)), 0, "no seat");
        assertEq(deityPass.ownerOf(0), address(vault), "Vault deity pass");
        assertEq(deityPass.ownerOf(6), address(sdgnrs), "sDGNRS deity pass");
    }
}
