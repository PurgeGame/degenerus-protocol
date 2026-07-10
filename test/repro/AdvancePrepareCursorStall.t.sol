// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title AdvancePrepareCursorStall — PoC for the jackpot-phase advanceGame ticket-drain
///        liveness stall (prepare-future-tickets cursor clobber -> full rescan -> zero net progress).
///
/// @notice TEST-ONLY. No contracts/*.sol are touched. This test ASSERTS THE BUG EXISTS on HEAD
///         (contracts tree d5e9f58a): it PASSES precisely because advanceGame can never complete
///         the day. When the contract fix lands, this test MUST be INVERTED into a regression test
///         (drive to completion / assert the day unlocks), exactly like AdvanceGapBackfillBrick.t.sol
///         inverted the C2 brick.
///
///         MECHANISM (AdvanceModule @ HEAD, jackpot phase, base = level `lvl`):
///           - The day-walk runs `_prepareFutureTickets(lvl, rngWord)` (AdvanceModule:513) BEFORE
///             the current-level drain `_runProcessTicketBatch(lvl)` (AdvanceModule:526).
///           - `_prepareFutureTickets` probes future levels lvl+1..lvl+4. Those read queues are
///             empty, so each `processFutureTicketBatch` hits its empty-queue path
///             (MintModule:325-328) and executes `ticketCursor = 0; ticketLevel = 0`, ERASING the
///             in-flight base-level resume cursor the previous advance left.
///           - The following `processTicketBatch(lvl)` (MintModule:621) then sees `ticketLevel != lvl`,
///             resets the cursor to 0 (MintModule:630-632), and RESCANS the read queue from index 0,
///             re-skipping the already-minted prefix at 1 write-budget unit per entry
///             (owed==0 skip path, MintModule:825) before minting any new tickets.
///           - Cold budget/call = WRITES_BUDGET_SAFE(550) - 35% = 358. A whole-ticket mint (owed=4)
///             costs 11 units (MintModule:851-854); a skip costs 1. So each call makes only
///             ~floor((358 - processedPrefix)/11) NEW progress. The minted prefix grows
///             (32,61,88,...) and, once the skip prefix saturates the whole 358-unit budget, NEW
///             progress hits ZERO — the cursor plateaus below the queue length forever.
///           - With N distinct queued jackpot-phase buyers above that plateau, the tail is NEVER
///             processed: `_runProcessTicketBatch` keeps returning finished=false, advanceGame loops
///             STAGE_TICKETS_WORKING every call, the day never unlocks, and only the 120-day liveness
///             game-over would ever escape.
///
///         The queue is fed by ordinary PERMISSIONLESS `game.purchase` calls (no per-day buyer cap;
///         dedup is per distinct address at Storage:688). Jackpot-phase ticket buys route to `level`
///         (MintModule:1967 `cachedJpFlag ? level : level+1`); the daily RNG-request swap
///         (`_swapAndFreeze`, AdvanceModule:450) then turns that write slot into the read slot that
///         :526 drains.
///
/// @dev FULL END-TO-END: the queue is filled only by real `game.purchase` calls and the stall
///      emerges purely from real `game.advanceGame()` + mock VRF fulfillment. vm.store/vm.load touch
///      ONLY test-side prize-pool seeding and read-only storage inspection (queue lengths / cursor) —
///      never the queue contents or the stall itself.
///
///      Run: forge test --match-path test/repro/AdvancePrepareCursorStall.t.sol -vv
contract AdvancePrepareCursorStall is DeployProtocol {
    /// @dev prizePoolsPacked slot (confirmed via the BAF/RngRetry/RngReuse tests): [hi128 future][lo128 next].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    /// @dev ticketQueue mapping root slot (forge inspect DegenerusGame storageLayout).
    uint256 private constant TICKETQUEUE_SLOT = 12;
    /// @dev ticketCursor (uint32 @ slot 14 offset 0) + ticketLevel (uint24 @ slot 14 offset 4).
    uint256 private constant TICKET_CURSOR_SLOT = 14;
    /// @dev header slot 0; ticketWriteSlot bool lives at byte offset 25 (Storage layout doc).
    uint256 private constant TICKET_WRITE_SLOT_BYTE = 25;
    /// @dev Storage.TICKET_SLOT_BIT = 1 << 23 (double-buffer read/write key discriminator).
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev AdvanceModule STAGE_TICKETS_WORKING (private const in AdvanceModule, ~L63). Hardcoded.
    uint8 private constant STAGE_TICKETS_WORKING = 5;
    /// @dev topic0 of `event Advance(uint8 stage, uint24 lvl)` (both params non-indexed → in data).
    bytes32 private constant TOPIC_ADVANCE = keccak256("Advance(uint8,uint24)");

    /// @dev Distinct jackpot-phase buyers. The confirmed cold-budget plateau is ~358 minted entries,
    ///      so N well above that guarantees a permanently unreachable tail.
    uint256 private constant N_BUYERS = 420;
    /// @dev One whole ticket per buyer = 4 entries = 4 * QTY_SCALE(100) = 400 scaled entries → owed=4.
    uint256 private constant QTY_ONE_TICKET = 400;

    address private buyer;
    uint256 private lastFulfilledReqId;
    uint256 private vrfNonce;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        buyer = makeAddr("cursorstall_driver");
        vm.deal(buyer, 1_000_000 ether);
        vm.deal(address(game), 5_000 ether);
        mockVRF.fundSubscription(1, 1_000 ether);
    }

    // ==================== The test ====================

    function testBug_JackpotTicketDrainStallsForever() public {
        // 1) Reach real jackpot phase, then seal its entry day so RNG unlocks and purchases open.
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        require(game.jackpotPhase(), "must be in jackpot phase");
        require(!game.rngLocked(), "entry day must be unlocked before buying");
        require(!game.gameOver(), "must be live");

        uint24 lvl = game.level();
        emit log_named_uint("jackpot level", lvl);

        // 2) Fill the current jackpot level's WRITE slot with N distinct permissionless buyers.
        //    Each buys exactly one whole ticket (owed=4). Dedup is per-address (Storage:688), so
        //    distinct addresses => distinct queue entries.
        uint256 landed = 0;
        for (uint256 i = 0; i < N_BUYERS; i++) {
            address b = address(uint160(0x100000 + i));
            uint256 before = _queueLen(_writeKey(lvl));
            _buyTickets(b, QTY_ONE_TICKET);
            if (_queueLen(_writeKey(lvl)) == before + 1) landed++;
        }
        uint256 writeLen = _queueLen(_writeKey(lvl));
        emit log_named_uint("distinct buyers landed in level write queue", landed);
        emit log_named_uint("write-slot queue length (pre-swap)", writeLen);
        require(writeLen >= 349, "need >= 349 queued buyers to clear the stall threshold");

        // 3) Cross the wall-day. The first advance requests the daily word and swaps write->read
        //    (_swapAndFreeze), so the buyers become the read cohort that :526 drains.
        vm.warp(block.timestamp + 1 days + 1);
        vm.recordLogs();
        game.advanceGame();
        (uint8 reqStage, bool reqFound) = _lastAdvanceStage(vm.getRecordedLogs());
        emit log_named_uint("post-request advance stage", reqStage);
        require(reqFound, "advance emitted a stage");
        require(game.rngLocked(), "daily VRF request is in flight (word swapped in)");

        uint256 readLen = _queueLen(_readKey(lvl));
        emit log_named_uint("read-slot queue length (post-swap)", readLen);
        require(readLen >= 349, "swapped read cohort must hold >= 349 buyers");
        uint256 N = readLen;

        // Fulfill the daily word so the next advance begins actually draining the read cohort.
        _fulfillVrf();

        // 4) Drive advanceGame in a large fixed number of iterations with NO further time warp (so the
        //    120-day liveness game-over can never fire). Real per-call NEW progress decays as the
        //    re-skipped prefix grows and converges to a fixed point strictly below N: the tail entries
        //    never mint, the day never unlocks. A correctly-resuming batch would instead drain
        //    monotonically to N and finish the day in a handful of calls.
        uint32 prevCursor = _cursor();
        uint32 startCursor = prevCursor;
        uint256 ITERS = 250;

        for (uint256 i = 0; i < ITERS; i++) {
            _fulfillVrf(); // no-op once the day's word is cached; kept for safety
            vm.recordLogs();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            require(ok, "advanceGame must not revert during the stall");

            (uint8 stage, bool found) = _lastAdvanceStage(vm.getRecordedLogs());
            require(found, "advance emitted a stage");
            // The day is permanently wedged in the current-level ticket drain.
            assertEq(uint256(stage), uint256(STAGE_TICKETS_WORKING), "stage stuck at TICKETS_WORKING");
            assertTrue(game.rngLocked(), "RNG never unlocks (day never completes)");
            assertFalse(game.gameOver(), "no game-over: no time elapsed to trip 120-day liveness");

            uint32 cur = _cursor();
            uint32 delta = cur >= prevCursor ? cur - prevCursor : 0;
            if (i < 8) {
                emit log_named_uint("iter", i);
                emit log_named_uint("  cursor (cumulative minted prefix)", cur);
                emit log_named_uint("  new-progress delta this call", delta);
            }
            prevCursor = cur;
        }

        uint32 finalCursor = _cursor();
        emit log_named_uint("iterations driven", ITERS);
        emit log_named_uint("start cursor", startCursor);
        emit log_named_uint("final cursor (max entries ever minted)", finalCursor);
        emit log_named_uint("queued buyers N (read cohort)", N);
        emit log_named_uint("stranded tail entries (N - finalCursor)", N - finalCursor);

        // ---- Core assertions: the stall is real and permanent ----
        // After 250 real advance calls with no time passing, the drain has NOT finished: the mint
        // cursor is wedged strictly below the queue length, so the tail can never be materialized.
        assertLt(uint256(finalCursor), N, "the queue tail can NEVER be minted (final cursor < N)");
        assertTrue(game.rngLocked(), "FINAL: RNG still locked - the day never completes");
        assertFalse(game.gameOver(), "FINAL: still live, not escaped via game-over");
    }

    // ==================== Drive helpers (from RngReuseJackpotStraddle) ====================

    function _driveToJackpotPhase() internal {
        for (uint256 i = 0; i < 4000; i++) {
            require(!game.gameOver(), "gameOver before jackpot phase");
            if (game.jackpotPhase()) return;

            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) {
                vm.warp(block.timestamp + 1 days + 1);
                _seedNextPrizePool(49.9 ether);
                _buyTickets(buyer, 4000);
            }
        }
        revert("did not reach jackpot phase");
    }

    function _drainUntilUnlocked() internal {
        for (uint256 i = 0; i < 120; i++) {
            if (!game.rngLocked()) return;
            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            if (!ok) return;
        }
    }

    // ==================== Low-level helpers ====================

    function _fulfillVrf() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0 || reqId == lastFulfilledReqId) return;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) {
            lastFulfilledReqId = reqId;
            return;
        }
        vrfNonce++;
        uint256 w = uint256(keccak256(abi.encode("cursorstall-vrf", reqId, vrfNonce)));
        if (w == 0) w = 1;
        mockVRF.fulfillRandomWords(reqId, w);
        lastFulfilledReqId = reqId;
    }

    function _lastAdvanceStage(Vm.Log[] memory logs)
        internal
        view
        returns (uint8 stage, bool found)
    {
        for (uint256 i = logs.length; i > 0; i--) {
            Vm.Log memory lg = logs[i - 1];
            if (
                lg.emitter == address(game) &&
                lg.topics.length > 0 &&
                lg.topics[0] == TOPIC_ADVANCE
            ) {
                (uint8 s, ) = abi.decode(lg.data, (uint8, uint24));
                return (s, true);
            }
        }
        return (0, false);
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_ || game.gameOver()) return;
        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);
        vm.prank(who);
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        vm.store(
            address(game),
            bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)),
            bytes32((uint256(currentFuture) << 128) | targetNext)
        );
    }

    // ==================== Read-only storage inspectors (test-side vm.load only) ====================

    function _ticketWriteSlot() internal view returns (bool) {
        uint256 s0 = uint256(vm.load(address(game), bytes32(uint256(0))));
        return ((s0 >> (TICKET_WRITE_SLOT_BYTE * 8)) & 1) == 1;
    }

    /// @dev Mirrors Storage._tqReadKey: !ticketWriteSlot ? lvl|BIT : lvl.
    function _readKey(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? lvl : (lvl | TICKET_SLOT_BIT);
    }

    /// @dev Mirrors Storage._tqWriteKey: ticketWriteSlot ? lvl|BIT : lvl.
    function _writeKey(uint24 lvl) internal view returns (uint24) {
        return _ticketWriteSlot() ? (lvl | TICKET_SLOT_BIT) : lvl;
    }

    function _queueLen(uint24 key) internal view returns (uint256) {
        bytes32 root = keccak256(abi.encode(uint256(key), TICKETQUEUE_SLOT));
        return uint256(vm.load(address(game), root));
    }

    function _cursor() internal view returns (uint32) {
        return uint32(uint256(vm.load(address(game), bytes32(TICKET_CURSOR_SLOT))));
    }
}
