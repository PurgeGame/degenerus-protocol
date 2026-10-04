// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {IDegenerusGameTicketModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {Vm} from "forge-std/Vm.sol";

contract RecyclingProgressSeeder is DeadVrfSeeder {
    function seedDeferredFoil(address foilOwner, address ticketOwner) external {
        uint24 day = _simulatedDayIndex();
        level = 202;
        dailyIdx = day;
        purchaseStartDay = day;
        earlyTicketLevel = 203;
        _setTicketBufferLevel(201);
        _setTicketBufferLevel(202);
        foilRecord[201 & 3][foilOwner] = uint256(day) | (uint256(10_000) << _FOIL_MULT_SHIFT)
            | (uint256(201) << _FOIL_LEVEL_SHIFT);
        uint256 pos = uint256(_registerEntryOwner(foilOwner, 201) >> OWNER_IDX_SHIFT) - 1;
        foilQueue[_foilReadKey()].push(((pos + 1) << 192) | (uint256(201) << 160) | uint160(foilOwner));
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
        _recordDailyRng(day, uint256(keccak256("old foil word")) | 1);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((2) & 1) << 12);
        rngWordCurrent = uint256(keccak256("new ticket word")) | 1; _setRngSessionPublished(true); _setRngComplete(false);
        _seedQueued(_tqReadKey(203), 203, ticketOwner, uint80(100) << 8);
    }
    function seedWrappedPending(address owner) external {
        uint24 day = _simulatedDayIndex();
        level = 202; dailyIdx = day - 1; purchaseStartDay = day;
        earlyTicketLevel = 203;
        _setTicketBufferLevel(201); _setTicketBufferLevel(202);
        ticketsFullyProcessed = false;
        // A daily request records its day; the chained daily apply reads it.
        rngLockedFlag = true; rngRequestTime = uint48(block.timestamp); rngRequestDay = day;
        // A request always clears the completion marker; ticket work is selected only under it.
        vrfRequestId = 777; _setRngRequestActive(true); _setRngSessionPublished(false); _setRngComplete(false);
        rngWordCurrent = 2; _setNudgeCount(3);
        rngFlagsAndNudges = (rngFlagsAndNudges & ~(uint16(1) << 12)) | (uint16((2) & 1) << 12);
        _setRngSessionPublished(false);
        _seedQueued(_tqReadKey(203), 203, owner, uint80(100) << 8);
    }
    function seedPaidFoil(uint24 lvl, uint24 day, address owner) external {
        foilRecord[lvl & 3][owner] = uint256(day) | (uint256(10_000) << _FOIL_MULT_SHIFT)
            | (uint256(lvl) << _FOIL_LEVEL_SHIFT);
        uint256 pos = uint256(_registerEntryOwner(owner, lvl) >> OWNER_IDX_SHIFT) - 1;
        foilQueue[_foilReadKey()].push(((pos + 1) << 192) | (uint256(lvl) << 160) | uint160(owner));
        foilGenerationDay = 0;
        foilFirstDrawDay = 0;
    }
    function foilRecordWord(uint24 lvl, address owner) external view returns (uint256) { return _foilRecordWord(owner, lvl); }
    function retireBeforeFoilWord() external { _setTicketBufferLevel(203); }
    /// @dev The production ticket worker, delegatecalled exactly as mineFlip's Tickets stage
    ///      dispatches it, with all remaining gas as its allowance.
    function runProductionTickets(uint24 anchor) external returns (bool finished, bool worked) {
        (bool ok, bytes memory data) = ContractAddresses.GAME_TICKET_MODULE.delegatecall(
            abi.encodeWithSelector(IDegenerusGameTicketModule.runTicketWork.selector, anchor, gasleft())
        );
        if (!ok) assembly ("memory-safe") { revert(add(data, 32), mload(data)) }
        MineFlipGas.Result memory r = abi.decode(data, (MineFlipGas.Result));
        return (r.done, r.progressed);
    }
    function foilCount(uint24) external view returns (uint256) { return _foilDrainPending() ? 1 : 0; }
    function stamped(uint24 lvl) external view returns (uint24) { return _ticketBufferLevel(lvl); }
    function bucketTotal(uint24 lvl) external view returns (uint256 total) {
        for (uint256 t; t < 256; ++t) total += _bucketLength(lvl, t);
    }
}

contract TicketRecyclingProgressTest is DeployProtocol {
    bytes realCode;
    address buyer;
    function setUp() public {
        _deployProtocol();
        realCode = address(game).code;
        buyer = makeAddr("paid-terminal-buyer");
        vm.warp(block.timestamp + 100 days);
        vm.deal(address(game), 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }
    function _overlay() private returns (RecyclingProgressSeeder s) {
        vm.etch(address(game), type(RecyclingProgressSeeder).runtimeCode);
        return RecyclingProgressSeeder(payable(address(game)));
    }
    function test_DeferredPreparationDrainsBlockingFoilBeforeRetryingTickets() public {
        address foilOwner = makeAddr("old-foil-owner");
        RecyclingProgressSeeder s = _overlay();
        s.seedDeferredFoil(foilOwner, buyer);
        emit log_named_uint("retirement deferred by drainable foil", s.foilCount(201));
        assertEq(s.foilCount(201), 1, "nonvacuity: the old foil is pending");
        assertEq(s.stamped(201), 201, "nonvacuity: the parity buffer still holds the paid old inventory");
        // The ticket worker keeps admitting steps while the caller's gas covers them, so one
        // ample-gas call both drains the blocking foil and then retires the buffer for 203.
        // The order is read from events.
        vm.recordLogs();
        (bool done, bool worked) = s.runProductionTickets(203);
        (uint256 foilAt, uint256 ticketAt) = _traitsOrder(vm.getRecordedLogs(), foilOwner, buyer);
        assertTrue(worked, "the deferral must still drain the blocking old foil");
        assertTrue(done);
        assertEq(s.foilCount(201), 0);
        assertLt(foilAt, ticketAt, "the old foil generates on the retained 201 inventory before any 203 ticket");
        assertTrue(s.foilRecordWord(201, foilOwner) >> 255 != 0, "the drained old foil stored its lines");
        assertEq(s.stamped(203), 203);
        assertEq(s.bucketTotal(203), 100, "all pending new tickets materialized");
    }

    /// @dev Log positions of the first TraitsGenerated for `first` and for `second`.
    function _traitsOrder(Vm.Log[] memory logs, address first, address second)
        private view returns (uint256 firstAt, uint256 secondAt)
    {
        bytes32 topic = keccak256("TraitsGenerated(address,uint256,uint32)");
        firstAt = type(uint256).max;
        secondAt = type(uint256).max;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != topic) continue;
            address player = address(uint160(uint256(logs[i].topics[1])));
            if (player == first && firstAt == type(uint256).max) firstAt = i;
            if (player == second && secondAt == type(uint256).max) secondAt = i;
        }
        assertTrue(firstAt != type(uint256).max, "first owner generated traits");
        assertTrue(secondAt != type(uint256).max, "second owner generated traits");
    }
    function test_NudgeWrapCannotLeaveCommittedReadWordZero() public {
        RecyclingProgressSeeder s = _overlay();
        s.seedWrappedPending(buyer);
        vm.etch(address(game), realCode);
        game.mineFlip();
        assertEq(RecyclingState.word(address(game), 1), 2, "wrapped nudge normalized before ticket generation");
        s = _overlay();
        assertEq(s.bucketTotal(203), 100);
    }
    function test_LateWordForRetiredFoilCommitsProgressWithoutOverwritingNewInventory() public {
        address foilOwner = makeAddr("late-old-foil-owner");
        RecyclingProgressSeeder s = _overlay();
        s.seedDeferredFoil(foilOwner, buyer);
        uint256 record = s.foilRecordWord(201, foilOwner);
        // The pack was queued before takeover; its committed cohort resolves afterwards.
        s.retireBeforeFoilWord();
        (bool done, bool worked) = s.runProductionTickets(203);
        assertTrue(worked, "a retired foil record must not wedge the generation frontier");
        assertEq(s.foilCount(201), 0, "late foil queue consumed");
        assertEq(s.stamped(201), 203, "never restore retired inventory");
        uint256 generated = s.foilRecordWord(201, foilOwner);
        assertEq(uint32(generated >> 24), uint32(record >> 24), "frozen boost and activity retained");
        assertTrue(generated >> 255 != 0, "late pack still stores its generated lines");
        assertGt(uint128(generated >> 56), 0, "four lines retained for claims");
        if (!done) (done, worked) = s.runProductionTickets(203);
        assertTrue(done);
        assertEq(s.bucketTotal(203), 100, "late old foil contributes no stale lanes to new tickets");
    }
    function test_NormalEndingPreparesPreviouslyUnmaterializedPaidTerminalLevel() public {
        RecyclingProgressSeeder s = _overlay();
        s.seedCreated(4, 7, makeAddr("old-retained-owner"), 1);
        s.seedDeadlineWithLandedCohort(5, 0xB0B5);
        uint32 position = s.seedQueued(6, true, buyer, 1024, 0);
        uint24 terminalDay = game.currentDayView();
        address oldFoil = makeAddr("retired-terminal-foil");
        s.seedPaidFoil(4, terminalDay, oldFoil);
        uint256 paidRecord = s.foilRecordWord(4, oldFoil);
        uint48 priorIndex = RecyclingState.readBuffer(address(game));
        vm.etch(address(game), realCode);
        // The already committed old foil cohort drains first, on its own word.
        // Each keeper call completes one bounded step before the ending requests RNG.
        for (uint256 i; i < 4 && mockVRF.lastRequestId() == 0; ++i) game.mineFlip();
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0, "ending requests its own entropy after committed foil work");
        mockVRF.fulfillRandomWords(request, uint256(keccak256("terminal recycling word")) | 1);
        for (uint256 i; i < 100 && !game.gameOver(); ++i) game.mineFlip();
        assertTrue(game.gameOver(), "terminal preparation must not stall ending");
        s = _overlay();
        assertEq(s.stamped(6), 6);
        assertEq(s.bucketTotal(6), 1024, "paid terminal tickets reached the payout inventory");
        assertEq(s.owedAt(6, position), 0);
        assertEq(s.foilCount(4), 0, "older foil cannot wedge the frozen payout buffer");
        assertEq(s.foilRecordWord(4, oldFoil), paidRecord, "older match/gold claim inputs survive");
        vm.etch(address(game), realCode);
        assertEq(RecyclingState.word(address(game), priorIndex), 0, "terminal kills unfinished prior lootbox consumers");
        assertGt(game.rngWordForDay(terminalDay), 0, "older foil still has its daily claim entropy");
        assertGt(game.claimableWinningsOf(buyer), 0, "paid terminal owner receives the ending pot");
    }
}
