// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title AdvancePrepareCursorStall — regression for the jackpot-phase advanceGame ticket-drain
///        liveness stall (prepare-future-tickets shared-cursor clobber).
///
/// @notice TEST-ONLY. No contracts are touched by the test itself. It drives a real jackpot-phase
///         day with a large permissionless buyer cohort and asserts the current-level ticket drain
///         RESUMES correctly across transactions and finishes the day.
///
///         BUG (pre-fix): `advanceGame` runs `_prepareFutureTickets(lvl)` before the current-level
///         drain `_runProcessTicketBatch(lvl)` on every call. The two share ONE resume cursor
///         (`ticketCursor`/`ticketLevel`). When the current drain spans multiple transactions (a
///         cohort larger than one write budget), each next call's `_prepareFutureTickets` probes the
///         empty future levels lvl+1..lvl+4; the empty-queue path of `processFutureTicketBatch`
///         (MintModule:325-328) does `ticketCursor = 0; ticketLevel = 0`, erasing the in-flight
///         current-level cursor. `processTicketBatch(lvl)` then re-inits (MintModule:630-632) and
///         rescans from index 0, re-skipping the already-minted prefix at 1 budget unit each. New
///         progress per call decays 32, 29, 27, ... to zero once the skip prefix saturates the
///         358-unit cold budget: the mint cursor plateaus below the cohort size, the tail never
///         mints, `advanceGame` loops STAGE_TICKETS_WORKING, and the day never unlocks (only the
///         120-day liveness game-over escapes). Purchase phase is unaffected — the pre-RNG gate
///         (AdvanceModule:302) drains that level's queue before `_prepareFutureTickets` runs.
///
///         FIX: `_prepareFutureTickets` returns early (defers) while a current-level batch is
///         in flight (`ticketLevel == lvl`), so the shared cursor is never reset mid-drain; future
///         levels are processed after the current drain clears the marker.
///
///         The cohort is fed only by real permissionless `game.purchase` calls (no per-day buyer
///         cap; per-address dedup at Storage:688). Jackpot-phase buys route to `level`
///         (MintModule:1967); the daily RNG-request swap turns that write slot into the read slot
///         the drain consumes. vm.store/vm.load touch ONLY test-side prize-pool seeding and
///         read-only storage inspection — never the queue contents.
///
///         Pre-fix this test FAILS (the drain wedges below N and the day never completes);
///         post-fix it PASSES (the cohort fully materializes and the day proceeds).
///
///         Run: forge test --match-path test/repro/AdvancePrepareCursorStall.t.sol -vv
contract AdvancePrepareCursorStall is DeployProtocol {
    /// @dev prizePoolsPacked slot: [hi128 future][lo128 next].
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;
    /// @dev ticketQueue mapping root slot (forge inspect DegenerusGame storageLayout).
    uint256 private constant TICKETQUEUE_SLOT = 12;
    /// @dev ticketCursor (uint32 @ slot 14 offset 0) + ticketLevel (uint24 @ slot 14 offset 4).
    uint256 private constant TICKET_CURSOR_SLOT = 14;
    /// @dev header slot 0; ticketWriteSlot bool at byte offset 25.
    uint256 private constant TICKET_WRITE_SLOT_BYTE = 25;
    /// @dev Storage.TICKET_SLOT_BIT = 1 << 23 (double-buffer read/write key discriminator).
    uint24 private constant TICKET_SLOT_BIT = uint24(1) << 23;

    /// @dev AdvanceModule STAGE_TICKETS_WORKING (private const in AdvanceModule). Hardcoded.
    uint8 private constant STAGE_TICKETS_WORKING = 5;
    /// @dev topic0 of `event Advance(uint8 stage, uint24 lvl)` (both params non-indexed → in data).
    bytes32 private constant TOPIC_ADVANCE = keccak256("Advance(uint8,uint24)");

    /// @dev Distinct jackpot-phase buyers. Well above the ~358 cold-budget plateau so a broken
    ///      resume would strand a tail; a correct resume drains all of them in a handful of calls.
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

    // ==================== The regression ====================

    function testRegression_JackpotTicketDrainResumesToCompletion() public {
        // 1) Reach real jackpot phase, then seal its entry day so RNG unlocks and purchases open.
        _driveToJackpotPhase();
        _drainUntilUnlocked();
        require(game.jackpotPhase(), "must be in jackpot phase");
        require(!game.rngLocked(), "entry day must be unlocked before buying");
        require(!game.gameOver(), "must be live");

        uint24 lvl = game.level();
        emit log_named_uint("jackpot level", lvl);

        // 2) Fill the current jackpot level's WRITE slot with N distinct permissionless buyers,
        //    one whole ticket each (owed=4). Per-address dedup => distinct addresses == entries.
        for (uint256 i = 0; i < N_BUYERS; i++) {
            _buyTickets(address(uint160(0x100000 + i)), QTY_ONE_TICKET);
        }
        uint256 writeLen = _queueLen(_writeKey(lvl));
        emit log_named_uint("write-slot queue length (pre-swap)", writeLen);
        require(writeLen >= 349, "need >= 349 queued buyers to exercise the multi-tx resume");
        uint256 N = writeLen;

        // 3) Cross the wall-day. The first advance requests the daily word and swaps write->read
        //    (_swapAndFreeze), so the buyers become the read cohort the drain consumes.
        vm.warp(block.timestamp + 1 days + 1);
        game.advanceGame();
        require(game.rngLocked(), "daily VRF request is in flight (word swapped in)");

        uint24 rk = _readKey(lvl);
        require(_queueLen(rk) == N, "swapped read cohort holds all buyers");

        // Fulfill the daily word so the next advance begins draining the read cohort.
        _fulfillVrf();

        // 4) Drive advanceGame with NO further time warp (the 120-day liveness game-over can never
        //    fire, so completion must come from real drain progress). A correct resume drains the
        //    whole cohort in a bounded number of calls; the pre-fix clobber wedges it forever.
        bool drained = false;
        uint32 maxCursor = 0;
        uint256 iters = 0;
        for (uint256 i = 0; i < 200; i++) {
            iters++;
            _fulfillVrf();
            (bool ok, ) = address(game).call(abi.encodeWithSignature("advanceGame()"));
            require(ok, "advanceGame must not revert");
            require(!game.gameOver(), "must not escape via game-over");

            uint32 cur = _cursor();
            if (cur > maxCursor) maxCursor = cur;
            if (i < 10) {
                emit log_named_uint("iter", i);
                emit log_named_uint("  cursor", cur);
            }

            // The drain deletes ticketQueue[rk] when the cohort fully materializes.
            if (_queueLen(rk) == 0) {
                drained = true;
                break;
            }
        }

        emit log_named_uint("iterations driven", iters);
        emit log_named_uint("max cursor reached", maxCursor);
        emit log_named_uint("cohort N", N);

        // ---- Regression assertions: the cohort drains to completion, the day is not wedged ----
        // The read queue is deleted only when every entry has been materialized (idx >= total,
        // MintModule finish paths), so an emptied queue proves the full cohort minted. The mint
        // cursor advances monotonically past the pre-fix ~353 plateau instead of rescanning from 0.
        assertTrue(drained, "current-level cohort fully materialized (read queue emptied)");
        assertGt(uint256(maxCursor), 353, "cursor advanced past the pre-fix stall plateau (healthy resume)");
        assertFalse(game.gameOver(), "still live");
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
