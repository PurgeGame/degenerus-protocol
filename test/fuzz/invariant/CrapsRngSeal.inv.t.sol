// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {StdInvariant} from "forge-std/StdInvariant.sol";
import {DeployProtocol} from "../helpers/DeployProtocol.sol";
import {CrapsRngSealHandler} from "../handlers/CrapsRngSealHandler.sol";
import {CrapsBattle} from "../../../contracts/CrapsBattle.sol";
import {Craps} from "../../../contracts/Craps.sol";
import {LootboxCraps} from "../../../contracts/LootboxCraps.sol";
import {ContractAddresses} from "../../../contracts/ContractAddresses.sol";

/// @title CrapsRngSeal — the craps lane of the RNG-freeze net, against the real VRF lifecycle.
///
/// @notice The craps table is a satellite consumer of the protocol's lootbox-RNG words: a field
///         binds to `_currentIndex()` when it shuts and reads that leaf at settlement. The
///         freeze standard for every VRF consumer is that nothing an actor controls can change WHICH
///         word settles an outcome or HOW after the request is made. For craps that decomposes into
///         the six properties the handler counts (see CrapsRngSealHandler): the bound leaf is
///         unworded and above the reserved region, no request in flight at the arm can fulfil into
///         it, no slip moves after its field shuts, no settlement runs on a zero word, and no craps
///         door moves the game's enumerated consumed set while a protocol VRF window is open.
///
/// @dev Test-only: ZERO contracts/*.sol mutation. The only vm.store is inside the excluded
///      falsifiability seam and the focused falsifiability test below.
contract CrapsRngSeal is DeployProtocol {
    CrapsRngSealHandler public handler;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 5_000_000 ether);
        // requestLootboxRng gates on the subscription's LINK; the craps caller needs >= 10.
        mockVRF.fundSubscription(1, 100e18);

        handler = new CrapsRngSealHandler(game, mockVRF, coin, crapsBattle, 5);
        targetContract(address(handler));

        bytes4[] memory excluded = new bytes4[](1);
        excluded[0] = CrapsRngSealHandler.debugSeedWordedArmAndCheck.selector;
        excludeSelector(StdInvariant.FuzzSelector({addr: address(handler), selectors: excluded}));
    }

    // =========================================================================
    // THE PROPERTIES
    // =========================================================================

    function invariant_armedLeafIsUnworded() public view {
        assertEq(handler.ghost_armsOnWordedIndex(), 0, "CRAPS-SEAL: a field shut onto a leaf that already held a word");
    }

    function invariant_armedLeafAboveReservedRegion() public view {
        assertEq(handler.ghost_armsBelowCursor(), 0, "CRAPS-SEAL: a field shut onto a leaf a request had already claimed");
    }

    function invariant_inFlightRequestNeverLandsOnArmedLeaf() public view {
        assertEq(
            handler.ghost_inFlightLandedOnArmedIndex(),
            0,
            "CRAPS-SEAL: a request in flight at the arm fulfilled into the armed leaf"
        );
    }

    function invariant_noSlipMovesAfterItsFieldShuts() public view {
        assertEq(handler.ghost_postArmSlipMutations(), 0, "CRAPS-SEAL: a slip's frozen fields changed after its field shut");
        assertEq(handler.ghost_postArmAmendsAccepted(), 0, "CRAPS-SEAL: amendSlip accepted a slip on a shut field");
    }

    function invariant_noSettlementWithoutAWord() public view {
        assertEq(handler.ghost_settlesWithoutWord(), 0, "CRAPS-SEAL: the resolution cursor advanced on a zero word");
    }

    function invariant_crapsDoorsFreezeTheGameSet() public view {
        assertEq(
            handler.ghost_inWindowGameSetMutations(),
            0,
            "CRAPS-SEAL: a craps action inside a protocol VRF window moved the game's consumed set"
        );
    }

    // =========================================================================
    // SURVEILLANCE (non-asserting reads so forge surfaces the counters)
    // =========================================================================

    function invariant_sealExercised() public view {
        handler.ghost_daysOpened();
        handler.ghost_entries();
        handler.ghost_dayTickets();
        handler.ghost_customBattles();
        handler.ghost_arms();
        handler.ghost_armsWhileDailyLocked();
        handler.ghost_armsWhileMidDayInFlight();
        handler.ghost_armsWithLiveRequest();
        handler.ghost_postArmAmendAttempts();
        handler.ghost_settlesWithWord();
        handler.ghost_settleAttemptsWithoutWord();
        handler.ghost_inWindowCrapsActions();
        handler.ghost_midDayInWindowCrapsActions();
        handler.ghost_fulfilments();
        handler.ghost_keeps();
        handler.ghost_wordsLandedOnArmedIndices();
    }

    // =========================================================================
    // NON-VACUITY
    // =========================================================================

    function afterInvariant() public view {
        assertGt(handler.ghost_daysOpened(), 1, "vacuous: the campaign never opened a second craps day");
        assertGt(handler.ghost_entries(), 0, "vacuous: no entry ever bound");
        assertGt(handler.ghost_arms(), 0, "vacuous: no field ever shut");
        assertGt(
            handler.ghost_armsWhileDailyLocked() + handler.ghost_armsWhileMidDayInFlight(),
            0,
            "vacuous: no field shut while a protocol VRF window was open"
        );
        assertGt(handler.ghost_postArmAmendAttempts(), 0, "vacuous: no amendment was ever tried on a shut field");
        assertGt(handler.ghost_settlesWithWord(), 0, "vacuous: no field ever settled on a real word");
        assertGt(
            handler.ghost_inWindowCrapsActions() + handler.ghost_midDayInWindowCrapsActions(),
            0,
            "vacuous: no craps door was tried inside a protocol VRF window"
        );
        assertGt(handler.ghost_fulfilments(), 0, "vacuous: the VRF machinery never delivered a word");
    }

    // =========================================================================
    // FOCUSED PINS + FALSIFIABILITY
    // =========================================================================

    /// @dev Drive one craps day open through the real heartbeat and seat one entrant in period 0.
    function _openDayWithOneEntrant() internal returns (uint64 slot, uint256 betId, address who) {
        handler.advanceDay(1);
        require(handler.ghost_daysOpened() == 1, "fixture: the craps day did not open");
        who = handler.actors(0);
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(who, 1_000_000 ether);
        Craps.Bets memory board;
        board.passLine = 3;
        board.place8 = 3;
        board.place9 = 1;
        vm.prank(who);
        betId = crapsBattle.enterBonusBattle(0, board, 1);
        slot = uint64(betId >> 64);
    }

    /// @notice The arm binds the cursor's own leaf, the leaf is unworded, and the arm's own
    ///         request is the one that fulfils into it — the cursor moves past it in the same call.
    function test_armBindsTheCursorAndItsOwnRequestLandsThere() public {
        (uint64 slot,,) = _openDayWithOneEntrant();
        uint48 cursorBefore = crapsBattle.currentIndex();
        vm.warp(block.timestamp + crapsBattle.BONUS_EVENT_CLOSE() + crapsBattle.BONUS_CLOCK_ALIGN());
        uint48 index = crapsBattle.armBonusWindow(slot);
        assertEq(index, cursorBefore, "the field must bind the cursor's leaf");
        assertEq(crapsBattle.wordAt(index), 0, "the bound leaf must be unworded");
        assertEq(crapsBattle.currentIndex(), cursorBefore + 1, "the arm's request must have advanced the cursor");

        uint256 reqId = mockVRF.lastRequestId();
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("seal-pin")) | 1);
        assertGt(crapsBattle.wordAt(index), 0, "the arm's own request lands on the armed leaf");
        assertEq(crapsBattle.wordAt(index + 1), 0, "the leaf above stays unworded for the next arm");
    }

    /// @notice After the field shuts, the slip is frozen: amendSlip is refused and the stored
    ///         fields are byte-identical.
    function test_amendIsRefusedOnceTheFieldShuts() public {
        (uint64 slot, uint256 betId, address who) = _openDayWithOneEntrant();
        CrapsBattle.Bet memory before = crapsBattle.betOf(betId);
        vm.warp(block.timestamp + crapsBattle.BONUS_EVENT_CLOSE() + crapsBattle.BONUS_CLOCK_ALIGN());
        crapsBattle.armBonusWindow(slot);
        Craps.Bets memory other;
        other.dontPass = 2;
        vm.prank(who);
        vm.expectRevert();
        crapsBattle.amendSlip(betId, other);
        CrapsBattle.Bet memory after_ = crapsBattle.betOf(betId);
        assertEq(after_.chips, before.chips, "the packed board moved after the arm");
        assertEq(after_.standing, before.standing, "the standing moved after the arm");
        assertEq(after_.seat, before.seat, "the seat moved after the arm");
    }

    /// @notice A settlement on a zero word is refused outright.
    function test_settlementRefusesAZeroWord() public {
        (uint64 slot,,) = _openDayWithOneEntrant();
        vm.warp(block.timestamp + crapsBattle.BONUS_EVENT_CLOSE() + crapsBattle.BONUS_CLOCK_ALIGN());
        uint48 index = crapsBattle.armBonusWindow(slot);
        assertEq(crapsBattle.wordAt(index), 0);
        vm.expectRevert(LootboxCraps.RngNotReady.selector);
        crapsBattle.resolveSlot(slot, type(uint64).max);
    }

    /// @notice FALSIFIABILITY: seed a word onto the leaf the next arm will bind and prove the
    ///         detector registers it (property 1 is not unfalsifiably green).
    function test_falsifiable_wordedArmIsCaught() public {
        (uint64 slot,,) = _openDayWithOneEntrant();
        vm.warp(block.timestamp + crapsBattle.BONUS_EVENT_CLOSE() + crapsBattle.BONUS_CLOCK_ALIGN());
        assertTrue(handler.debugSeedWordedArmAndCheck(slot), "the seal detector must register a pre-worded leaf");
    }

    /// @notice A second field shut while the first arm's request is in flight is an in-window
    ///         arm, and it moves nothing in the game's consumed set.
    function test_secondArmDuringTheFirstArmsRequestIsInWindow() public {
        handler.advanceDay(1);
        handler.enterWindow(0, 5, 0, false);
        handler.enterWindow(1, 6, 1, false);
        handler.enterWindow(2, 7, 2, false);
        assertEq(handler.ghost_entries(), 3, "three seats on three windows");
        handler.arm(0);
        assertEq(handler.ghost_armsWithLiveRequest(), 1, "the first arm's request opened a mid-day window");
        handler.arm(1);
        handler.arm(2);
        assertEq(handler.ghost_arms(), 3);
        assertEq(handler.ghost_armsWhileMidDayInFlight(), 2, "both later arms ran inside the mid-day window");
        assertEq(handler.ghost_inWindowGameSetMutations(), 0, "no craps arm moved the game's consumed set");
        assertEq(handler.ghost_armsOnWordedIndex() + handler.ghost_armsBelowCursor(), 0);
    }

    /// @notice A past day's field shut under the DAILY lock is an in-window arm; its own request is
    ///         refused, so the lock's consumed set is untouched.
    function test_armUnderTheDailyLockIsInWindowAndInert() public {
        handler.primeLockedArm(3, 9);
        assertEq(handler.ghost_armsWhileDailyLocked(), 1, "the arm ran under the daily lock");
        assertEq(handler.ghost_inWindowCrapsActions(), 1);
        assertEq(handler.ghost_inWindowGameSetMutations(), 0, "the arm moved the daily consumed set");
        assertTrue(game.rngLocked(), "the daily window is still held after the arm");
    }

    /// @notice Each arm's own request lands its armed leaf — a request issued AFTER the field shut,
    ///         and the one that fills exactly the table the field bound — so a field settles as
    ///         soon as its own request fulfils, and a later arm binds the leaf above it.
    function test_eachArmsOwnRequestLandsItsLeafAndItSettles() public {
        handler.advanceDay(1);
        handler.enterWindow(0, 5, 0, false);
        handler.enterWindow(1, 6, 1, false);
        handler.arm(0);
        uint64 s0 = handler.armedSlots(0);
        uint48 i0 = handler.armedIndexOf(s0);
        assertEq(crapsBattle.wordAt(i0), 0, "the first leaf was worded when it bound");
        handler.fulfil(11);
        assertGt(crapsBattle.wordAt(i0), 0, "the arm's own request must land on its leaf");
        handler.settle(0);
        assertEq(handler.ghost_settlesWithWord(), 1, "the first field settled on its word");
        assertEq(handler.ghost_settlesWithoutWord(), 0);
        handler.arm(1);
        uint64 s1 = handler.armedSlots(1);
        uint48 i1 = handler.armedIndexOf(s1);
        assertEq(i1, i0 + 1, "the second arm did not bind the leaf above the first");
        assertEq(crapsBattle.wordAt(i1), 0, "the second leaf was worded when it bound");
        handler.fulfil(12);
        assertGt(crapsBattle.wordAt(i1), 0, "the second arm's own request must land on its leaf");
        handler.settle(1);
        assertEq(handler.ghost_settlesWithWord(), 2, "the second field settled on its word");
        handler.advanceDay(2);
        assertEq(handler.ghost_settlesWithoutWord(), 0);
        assertEq(handler.ghost_postArmSlipMutations(), 0);
    }
}
