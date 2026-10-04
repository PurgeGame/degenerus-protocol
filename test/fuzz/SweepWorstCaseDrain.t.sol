// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {MineFlipGasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @dev View/seed overlay etched onto the live game to inspect internal box-queue state.
///      A DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads access
///      to the live internal boxPlayers / lootboxOrder / presaleBoxEth maps and the read frontier
///      (humanReadComplete, boxCursor); the real code is restored after each call.
contract SweepViewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return _rngWriteBuffer();
    }

    function queueLen(uint48 index) external view returns (uint256) {
        return boxPlayers[index & 1].length;
    }

    function lootboxAmountFor(uint48 index, address who) external view returns (uint256) {
        return _boxOrder(index, who);
    }

    function presaleAmountFor(uint48 index, address who) external view returns (uint256) {
        return presaleBoxEth[index & 1][who] & PRESALE_BOX_AMOUNT_MASK;
    }

    function boxCursorView() external view returns (uint48) {
        return boxCursor;
    }

    function humanReadCompleteView() external view returns (bool) {
        return humanReadComplete;
    }

    function boxCursorIndexView() external view returns (uint48) {
        return _rngReadBuffer();
    }

    /// @dev The human sweep's declared admission bound for `who`'s entry in `index`
    ///      (GameAfkingModule._runHumanBoxWork).
    function entryDeclaredGas(uint48 index, address who) external view returns (uint256) {
        uint256 boxes = _boxOrderCount(_boxOrder(index, who));
        uint256 stored = presaleDrained ? 0 : presaleBoxEth[index & 1][who];
        if (boxes == 0 && stored == 0) return MineFlipGasBounds.HUMAN_SKIP_GAS;
        return MineFlipGasBounds.HUMAN_ENTRY_GAS + boxes * MineFlipGasBounds.HUMAN_BOX_GAS
            + (stored == 0 ? 0 : MineFlipGasBounds.HUMAN_PRESALE_GAS);
    }

    /// @dev Fixture seal of the write cohort as a mid-day request leaves it before its word lands
    ///      (RngModule._requestLootboxRng: _sealRngWriteBuffer, then the request goes out). Used at
    ///      genesis, where no real mid-day request is possible before the first daily word.
    function sealWriteCohortPending(uint256 requestId) external {
        lootboxRngPacked &= ~((LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
            | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
        rngWordCurrent = RNG_WORD_WAITING;
        _setRngSessionPublished(false);
        rngRequestTime = uint48(block.timestamp);
        vrfRequestId = requestId;
        _setRngRequestActive(true);
    }

    /// @dev Fixture seal of the write cohort, mirroring RngModule._sealRngWriteBuffer followed by
    ///      a published delivery: the pending-value counters clear, the buffers swap (which
    ///      reopens the read frontier), the new write buffer's queues reset, and the sealed
    ///      cohort's word lands published.
    function sealWriteCohort(uint256 word) external {
        lootboxRngPacked &= ~((LR_PENDING_ETH_MASK << LR_PENDING_ETH_SHIFT)
            | (LR_PENDING_FLIP_MASK << LR_PENDING_FLIP_SHIFT));
        _swapRngBuffers();
        _resetLootboxWriteBuffer(_rngWriteBuffer());
        rngWordCurrent = word;
        _setRngRequestActive(false);
        _setRngSessionPublished(true);
    }
}

/// @title SweepWorstCaseDrain — AUTO-03 worst-case, gas-checkpointed human-box sweep.
///
/// @notice The human sweep (GameAfkingModule._runHumanBoxWork, reached from openBoxes and the
///         mineFlip HumanBoxes action) walks the sealed read cohort boxPlayers[read] from
///         boxCursor, opening every ready entry (lootbox order and presale leg). Lootbox RNG
///         uses two physical buffers (slot 0 bit 252, read = write ^ 1) and a fresh request
///         waits for every read consumer, so at most ONE sealed cohort is ever outstanding; its
///         frontier is (humanReadComplete, boxCursor). The worst case the gas checkpoints defend
///         against: LONG walls of stale / no-box entries (each a pure skip) around the live
///         boxes. A wall must be crossed across bounded-gas calls (each entry is admitted only if
///         its declared bound fits the remaining allowance), so progress is monotonic across
///         calls and nothing is ever marooned.
///
///         This test seeds that shape and asserts:
///           (1) every openBoxes() call given a realistic bounded allowance succeeds;
///           (2) the read frontier advances MONOTONICALLY on every call (cursor, then completion);
///           (3) the drain COMPLETES: the cohort's frontier reaches humanReadComplete;
///           (4) the live lootbox box AND a presale box are auto-opened by the sweep.
///
/// @dev Test-only. ZERO contracts/*.sol mutation. Real lootbox + presale boxes are created through
///      the genuine purchase entrypoints (so their resolution is solvent); the skip walls
///      (no-box addresses) are appended via field-isolated slot pokes, and the cohort is sealed
///      through an etched overlay that runs the storage contract's own swap/reset routines.
contract SweepWorstCaseDrain is DeployProtocol {
    // boxPlayers: mapping(uint48 => address[]) at slot 57 (scripts/layout/golden/DegenerusGame.json).
    uint256 private constant SLOT_BOX_PLAYERS = 57;

    // A realistic keeper/door allowance: one call admits work only while the remaining gas covers
    // the next entry's declared bound.
    uint256 private constant TEN_M_TARGET = 10_000_000;
    // openBoxes reserves 30k before and after the human leg; dispatch/delegatecall overhead slack.
    uint256 private constant DOOR_OVERHEAD = 150_000;
    // A wall no realistic 10M call can cross by declared admission (HUMAN_SKIP_GAS each).
    uint256 private constant SKIP_WALL = 4_000;
    // The per-call budget is gas (a skip costs a few thousand gas actual, ~200 to ~1,500 fit in
    // one bounded call), so the fuzzed wall lengths are scaled to stay longer than one call.
    uint256 private constant WALL_SCALE = 10;
    uint8 private constant ACTION_AFKING = 9;
    uint8 private constant ACTION_HUMAN_BOXES = 10;

    address private actor;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        mockVRF.fundSubscription(1, 100e18);
        actor = makeAddr("sweepActor");
        vm.deal(actor, 1_000 ether);
        vm.deal(address(game), 1_000_000 ether);
    }

    // =========================================================================
    // Etched-viewer helpers (real code restored after each call)
    // =========================================================================

    function _viewer() internal returns (bytes memory real, SweepViewer v) {
        real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        v = SweepViewer(payable(address(game)));
    }

    function _lrIndex() internal returns (uint48 v) {
        (bytes memory real, SweepViewer sv) = _viewer();
        v = sv.lrIndexView();
        vm.etch(address(game), real);
    }

    function _lootAmt(uint48 index, address who) internal returns (uint256 v) {
        (bytes memory real, SweepViewer sv) = _viewer();
        v = sv.lootboxAmountFor(index, who);
        vm.etch(address(game), real);
    }

    function _presaleAmt(uint48 index, address who) internal returns (uint256 v) {
        (bytes memory real, SweepViewer sv) = _viewer();
        v = sv.presaleAmountFor(index, who);
        vm.etch(address(game), real);
    }

    function _queueLen(uint48 index) internal returns (uint256 v) {
        (bytes memory real, SweepViewer sv) = _viewer();
        v = sv.queueLen(index);
        vm.etch(address(game), real);
    }

    function _entryDeclaredGas(uint48 index, address who) internal returns (uint256 v) {
        (bytes memory real, SweepViewer sv) = _viewer();
        v = sv.entryDeclaredGas(index, who);
        vm.etch(address(game), real);
    }

    /// @dev The read cohort's frontier: (completed, in-cohort cursor).
    function _frontier() internal returns (bool done, uint48 cur) {
        (bytes memory real, SweepViewer sv) = _viewer();
        done = sv.humanReadCompleteView();
        cur = sv.boxCursorView();
        vm.etch(address(game), real);
    }

    /// @dev Seal the current write cohort with request `requestId` in flight (word not landed).
    function _sealCohortPending(uint256 requestId) internal {
        (bytes memory real, SweepViewer sv) = _viewer();
        sv.sealWriteCohortPending(requestId);
        vm.etch(address(game), real);
    }

    /// @dev Seal the current write cohort with `word` landed and published.
    function _sealCohort(uint256 word) internal {
        (bytes memory real, SweepViewer sv) = _viewer();
        sv.sealWriteCohort(word);
        vm.etch(address(game), real);
    }

    // =========================================================================
    // Slot-poke seeding helpers (no contract mutation)
    // =========================================================================

    /// @dev Append `count` no-box addresses to boxPlayers[index & 1] — a pure skip wall. Each entry
    ///      has a zero lootbox order AND zero presale leg, so the sweep skips it (one admitted
    ///      HUMAN_SKIP_GAS step, no resolution, never reverts). boxPlayers is mapping(uint48 =>
    ///      address[]) at slot 57: length at keccak(index & 1, 57); element i at
    ///      keccak(keccak(index & 1, 57)) + i.
    function _appendSkipPrefix(uint48 index, uint256 count, uint256 saltSeed) internal {
        bytes32 lenSlot = keccak256(abi.encode(uint256(index & 1), uint256(SLOT_BOX_PLAYERS)));
        uint256 len = uint256(vm.load(address(game), lenSlot));
        bytes32 dataBase = keccak256(abi.encode(lenSlot));
        for (uint256 i; i < count; ++i) {
            address ghost = address(uint160(uint256(keccak256(abi.encode("skip", saltSeed, len + i)))));
            vm.store(address(game), bytes32(uint256(dataBase) + len + i), bytes32(uint256(uint160(ghost))));
        }
        vm.store(address(game), lenSlot, bytes32(len + count));
    }

    // =========================================================================
    // Box-creation helpers (REAL entrypoints — solvent resolution)
    // =========================================================================

    /// @dev Drive a genesis daily cycle so _recordedDailyWord(today) != 0 and the lock clears.
    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 12 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.mineFlip() {} catch {}
            if (game.rngLocked()) break;
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("daily", i))) | 1) {} catch {}
                }
            }
        }
        for (uint256 i; i < 12 && game.rngLocked(); i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("dw", i))) | 1) {} catch {}
                }
            }
            vm.prank(actor);
            try game.mineFlip() {} catch {}
        }
    }

    /// @dev Deliver any outstanding request (a mid-day request the crank issues for a shut Craps
    ///      window, say) and drain its consumers without moving the clock, so the game is
    ///      unlocked, its read cohort complete and nothing is due: the state a seal starts from.
    function _settleIdle() internal {
        for (uint256 i; i < 64; ++i) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("idle", i))) | 1);
            }
            if (!game.rngLocked() && !game.advanceDue() && game.rngComplete() && !_requestOutstanding()) return;
            vm.prank(actor);
            try game.mineFlip() {} catch {}
        }
        revert("fixture: the game never went idle");
    }

    function _requestOutstanding() internal view returns (bool) {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return false;
        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        return !fulfilled;
    }

    /// @dev Buy a REAL human lootbox-mode box into the current write cohort.
    function _buyLootbox(address who, uint256 lootboxWei) internal {
        vm.deal(who, lootboxWei + 2 ether);
        vm.prank(who);
        game.purchase{value: lootboxWei + 1 ether}(who, 400, BoxOrderLib.boCustomFloor(lootboxWei), bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @dev Buy a REAL presale box into the current write cohort (credit-funded; enqueues for auto-open).
    function _buyPresaleBox(address who, uint256 boxWei) internal returns (bool created) {
        if (game.presaleBoxEthRemaining() == 0) return false;
        // Seed spendable presale-box credit (presaleBoxCredit, slot 17 — a credit ALLOWANCE, not a box record).
        bytes32 cslot = keccak256(abi.encode(who, uint256(17)));
        uint256 existing = uint256(vm.load(address(game), cslot));
        vm.store(address(game), cslot, bytes32(existing + boxWei));
        vm.deal(who, boxWei + 1 ether);
        vm.prank(who);
        try game.buyPresaleBox{value: boxWei}(who, boxWei) {
            created = true;
        } catch {
            created = false;
        }
    }

    // =========================================================================
    // The worst-case drain
    // =========================================================================

    /// @notice FUZZ: long skip walls before and after a live lootbox box and a presale box in the
    ///         sealed read cohort all drain across openBoxes calls given a bounded realistic
    ///         allowance — every call succeeds, the frontier advances monotonically, the drain
    ///         completes and both real boxes open. (No assertion is weakened: the drain MUST
    ///         complete and both real boxes MUST open.)
    function testFuzz_WorstCaseSweepDrainsBoundedNoBrick(
        uint256 prefixSeed,
        uint256 chunkSeed,
        uint256 lootSeed
    ) public {
        // 1) Live game so a real lootbox + presale box resolve solvently; settled and idle.
        _driveDailyCycleOnce();
        vm.assume(!game.rngLocked());
        _settleIdle();

        // 2) Two head walls in the write cohort that the seal will commit. With two physical
        //    buffers only one sealed cohort can be outstanding, so every wall lives in the single
        //    read cohort: head walls before the real entries, a tail wall after them.
        uint48 cohort = _lrIndex();
        uint256 headA = bound(prefixSeed >> 8, 20, 80) * WALL_SCALE;
        uint256 headB = bound(prefixSeed >> 16, 20, 80) * WALL_SCALE;
        _appendSkipPrefix(cohort, headA, prefixSeed ^ 0xA);
        _appendSkipPrefix(cohort, headB, prefixSeed ^ 0xB);

        // 3) Real boxes behind the head walls.
        address lootOwner = makeAddr("loot-owner");
        uint256 lootboxWei = bound(lootSeed, 0.05 ether, 2 ether);
        _buyLootbox(lootOwner, lootboxWei);
        assertGt(_lootAmt(cohort, lootOwner), 0, "fixture: real lootbox box queued in the write cohort");

        address presaleOwner = makeAddr("presale-owner");
        bool presaleCreated = _buyPresaleBox(presaleOwner, 1 ether);
        // Presale must actually be created for the presale-leg assertion to be non-vacuous.
        vm.assume(presaleCreated);
        assertGt(_presaleAmt(cohort, presaleOwner), 0, "fixture: real presale box queued in the write cohort");

        // 4) A LONG tail wall after the real entries: the sweep must still scan past it to drain the
        //    cohort, proving the cursor persists past the real opens.
        uint256 prefixLen = bound(prefixSeed, 40, 160) * WALL_SCALE;
        _appendSkipPrefix(cohort, prefixLen, prefixSeed);
        uint256 totalEntries = headA + headB + 2 + prefixLen;
        assertEq(_queueLen(cohort), totalEntries, "fixture: walls and real entries queued in the cohort");

        // 5) Seal: the cohort becomes the read buffer with its word landed.
        _sealCohort(uint256(keccak256("liveWord")) | 1);
        assertEq(RecyclingState.readBuffer(address(game)), cohort, "seal: the cohort is the read buffer");
        // Clear incidental AFKing boxes so the human sweep is the only leg being measured.
        for (uint256 i; i < 16 && game.nextMinerAction() == ACTION_AFKING; ++i) {
            vm.prank(actor);
            game.openBoxes(0);
        }
        assertEq(game.nextMinerAction(), ACTION_HUMAN_BOXES, "fixture: the human sweep is the next read consumer");

        // 6) Per-chunk property: the heaviest entry's declared bound fits a realistic 10M call.
        uint256 heaviest = _entryDeclaredGas(cohort, lootOwner);
        uint256 presaleEntry = _entryDeclaredGas(cohort, presaleOwner);
        if (presaleEntry > heaviest) heaviest = presaleEntry;
        // The Game's delegatecall retains 1/64 of the forwarded gas.
        uint256 minChunk = (heaviest + MineFlipGasBounds.HUMAN_TAIL_GAS + DOOR_OVERHEAD) * 64 / 63;
        emit log_named_uint("heaviest human entry declared gas", heaviest);
        assertLe(minChunk, TEN_M_TARGET, "BOUNDED: the heaviest entry is admitted by a realistic 10M call");

        // 7) Drain with a bounded allowance per call. Each call must succeed and advance.
        uint256 allowance = bound(chunkSeed, minChunk, TEN_M_TARGET);
        (bool prevDone, uint48 prevCur) = _frontier();
        assertFalse(prevDone, "fixture: the sealed cohort's frontier is open");
        assertEq(prevCur, 0, "fixture: the sweep starts at the cohort head");
        uint256 calls;
        while (!prevDone && calls < 4000) {
            ++calls;
            uint256 gasBefore = gasleft();
            vm.prank(actor);
            game.openBoxes{gas: allowance}(0);
            uint256 gasUsed = gasBefore - gasleft();
            emit log_named_uint("openBoxes chunk gas", gasUsed);

            (bool nowDone, uint48 nowCur) = _frontier();
            // (2) monotonic progress: the cursor strictly advances, or the cohort completes.
            bool advanced = nowDone || nowCur > prevCur;
            assertTrue(advanced, "MONOTONIC: each sweep chunk advances the open frontier (no stall, no regress)");
            prevDone = nowDone;
            prevCur = nowCur;
        }
        emit log_named_uint("openBoxes calls to drain", calls);
        assertTrue(prevDone, "DRAIN COMPLETE: the whole cohort drains in bounded chunks (no brick / infinite stall)");
        assertLe(calls, totalEntries + 1, "DRAIN COMPLETE: at least one entry per bounded call");

        // (4) the live lootbox box AND the presale box were auto-opened (both legs drained).
        assertEq(_lootAmt(cohort, lootOwner), 0, "DRAINED: the live lootbox box was auto-opened by the sweep");
        assertEq(_presaleAmt(cohort, presaleOwner), 0, "DRAINED: the presale box was auto-opened by the sweep (presale leg)");

        // The frontier swept the whole cohort — nothing marooned behind it.
        (, uint48 finalCur) = _frontier();
        assertEq(finalCur, 0, "FRONTIER: completion resets the cursor (none marooned)");
        assertTrue(game.nextMinerAction() != ACTION_HUMAN_BOXES, "FRONTIER: no human-box work remains for the cohort");
    }

    /// @dev Regression: when the human sweep scans only stale entries (opens nothing) but advances
    ///      the frontier, mineFlip COMMITS that progress instead of reverting NoWork and rolling it
    ///      back. So the keeper route advances through a skip wall cumulatively across calls and
    ///      reaches the live box behind it. Pre-fix this reverted NoWork every call, rolling the
    ///      cursor back to 0 and stranding the tail box on the rewarded route.
    /// @dev SKIP_WALL is sized so a realistic 10M mineFlip cannot cross it in one call: each skip is
    ///      admitted only while the remaining allowance covers HUMAN_SKIP_GAS plus the tail.
    function testRegression_MintFlipCommitsSkipProgressAndReachesLiveTail() public {
        _driveDailyCycleOnce();
        require(!game.rngLocked(), "fixture: game unlocked");
        // Settle without warping: the read cohort completes and nothing is due.
        _settleIdle();
        require(!game.advanceDue() && !game.rngLocked(), "fixture: no advance work, unlocked");

        uint48 index = _lrIndex();
        uint256 skipPrefixLen = SKIP_WALL;
        _appendSkipPrefix(index, skipPrefixLen, 0xBAD5EED);

        address liveOwner = makeAddr("audit-live-owner");
        _buyLootbox(liveOwner, 1 ether);
        assertEq(_queueLen(index), skipPrefixLen + 1, "fixture: stale entries precede one live box");
        assertGt(_lootAmt(index, liveOwner), 0, "fixture: tail box is live");

        _sealCohort(uint256(keccak256("audit-word")) | 1);
        for (uint256 i; i < 16 && game.nextMinerAction() == ACTION_AFKING; ++i) {
            vm.prank(actor);
            game.openBoxes(0);
        }
        assertTrue(game.boxesPending(), "fixture: router advertises human-box work");
        assertEq(game.nextMinerAction(), ACTION_HUMAN_BOXES, "fixture: mineFlip takes the human-box arm");

        (bool beforeDone, uint48 beforeCur) = _frontier();
        assertFalse(beforeDone, "fixture: open frontier");
        assertEq(beforeCur, 0, "fixture: zero cursor");

        // The miner reward prices measured gas above each call's first 1M at min(basefee, cap);
        // Foundry's default basefee is zero, which would price every call at zero.
        vm.fee(1 gwei);

        // Call 1: a realistic allowance walks part of the stale wall and opens nothing. mineFlip
        // does NOT revert; it COMMITS that skip-only progress. The only reward the engine pays is
        // the gas-priced miner reward (MinerBounty kind 1): the stale walk is measured keeper
        // work above the unpaid first 1M, and nothing else is credited.
        uint256 keeperFlipBefore = coinflip.coinflipAmount(actor);
        vm.recordLogs();
        vm.prank(actor);
        game.mineFlip{gas: TEN_M_TARGET}();
        (uint256 skipOnlyGas, uint256 skipOnlyReward) = _minerRewardOnly(vm.getRecordedLogs());
        emit log_named_uint("skip-only keeper call execution gas", skipOnlyGas);

        (bool afterDone, uint48 afterCur) = _frontier();
        assertFalse(afterDone, "regression: still sweeping the same cohort");
        assertGt(afterCur, beforeCur, "regression: skip-only progress is COMMITTED, not rolled back");
        assertLt(afterCur, skipPrefixLen, "regression: budget hit the wall - stopped inside the stale wall");
        assertGt(_lootAmt(index, liveOwner), 0, "regression: budget hit the wall - tail box not yet reached");
        assertGt(skipOnlyReward, 0, "regression: the stale walk is measured work above the unpaid 1M");
        assertEq(
            coinflip.coinflipAmount(actor),
            keeperFlipBefore + skipOnlyReward,
            "regression: skip-only housekeeping earns only the gas-priced miner reward"
        );

        // Later calls resume past the committed cursor (never from zero) and open the live box.
        uint48 resumed = afterCur;
        for (uint256 i; i < 16 && _lootAmt(index, liveOwner) != 0; ++i) {
            vm.prank(actor);
            game.mineFlip{gas: TEN_M_TARGET}();
            (afterDone, afterCur) = _frontier();
            assertTrue(afterDone || afterCur > resumed, "regression: each keeper call resumes past the committed cursor");
            resumed = afterCur;
        }
        assertEq(_lootAmt(index, liveOwner), 0, "regression: keeper route reaches and opens the live tail box");
        assertGt(
            coinflip.coinflipAmount(actor),
            keeperFlipBefore + skipOnlyReward,
            "regression: an actual box open earns the normal keeper bounty"
        );
        assertTrue(afterDone, "regression: frontier swept past the whole cohort");

        // Genuine no-work still reverts cleanly: nothing opened AND the frontier cannot move.
        require(!game.boxesPending(), "fixture: no human-box work remains");
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up. Quieting arms the closed windows, and an arm asks
        // the game for a lootbox word — which makes the crank due again (a request in flight). So
        // land that word and let the crank consume it, re-quieting the table each lap, until
        // neither side has work left.
        _quietCrapsTable();
        bool idle;
        for (uint256 i; i < 12 && !idle; i++) {
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("quiet", i))) | 1);
            }
            for (uint256 j; j < 4 && game.advanceDue(); j++) {
                try game.mineFlip() {} catch {}
            }
            _quietCrapsTable();
            vm.prank(actor);
            try game.mineFlip() {}
            catch (bytes memory err) {
                idle = bytes4(err) == bytes4(keccak256("NoWork()"));
            }
        }
        require(idle, "fixture: the router never went idle after quieting");
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip();
    }

    /// @dev The read frontier is (humanReadComplete, boxCursor) of the one sealed cohort (two
    ///      physical buffers, no logical index to clamp).
    ///      A no-work probe — at genesis, or against a sealed cohort whose word has not landed —
    ///      must not commit phantom progress; an empty worded cohort completes exactly once, and a
    ///      stationary follow-up is NoWork.
    function testRegression_MintFlipLogicalFrontierRejectsPhantomProgress() public {
        // Undo setUp's one-day warp: immediately after deployment the game is settled, buffer 0
        // accumulates writes and the genesis read cohort is complete.
        vm.warp(block.timestamp - 1 days);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: genesis is idle and unlocked");
        assertEq(_lrIndex(), 0, "fixture: genesis writes buffer zero");
        assertTrue(game.rngComplete(), "fixture: the genesis read cohort is complete");
        (bool beforeDone, uint48 beforeCur) = _frontier();
        assertEq(beforeCur, 0, "fixture: raw cursor is zero");

        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip();
        (bool afterDone, uint48 afterCur) = _frontier();
        assertEq(afterDone, beforeDone, "genesis no-work leaves the completion flag unchanged");
        assertEq(afterCur, beforeCur, "genesis no-work leaves the raw cursor unchanged");

        // Seal the (empty) genesis write buffer with a request in flight whose word has not landed
        // (no real mid-day request exists before the first daily word). The unworded cohort
        // cannot commit completion as work: the crank waits.
        uint256 requestId = 777;
        _sealCohortPending(requestId);
        assertEq(RecyclingState.readBuffer(address(game)), 0, "the genesis write buffer is the sealed cohort");
        assertEq(_queueLen(0), 0, "fixture: the sealed cohort holds no box entries");
        (afterDone, afterCur) = _frontier();
        assertFalse(afterDone, "the seal opens the cohort's frontier");
        assertEq(afterCur, 0, "the seal resets the cursor");
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("RngNotReady()"));
        game.mineFlip();
        (afterDone, afterCur) = _frontier();
        assertFalse(afterDone, "unworded-cohort probe cannot commit completion as work");
        assertEq(afterCur, 0, "unworded-cohort probe leaves the entry cursor unchanged");

        // Once the word lands through the real callback, traversing the empty queue really
        // completes the frontier. That bounded housekeeping progress commits once, then a
        // stationary follow-up is NoWork.
        uint256[] memory words = new uint256[](1);
        words[0] = uint256(keccak256("genesis-frontier-word")) | 2;
        vm.prank(address(mockVRF));
        game.rawFulfillRandomWords(requestId, words);
        assertTrue(game.isRngFulfilled(), "fixture: the callback landed the word");
        vm.prank(actor);
        game.mineFlip();
        (afterDone, afterCur) = _frontier();
        assertTrue(afterDone, "worded empty cohort completes and commits the frontier");
        assertEq(afterCur, 0, "empty cohort leaves the entry cursor zero");

        _quietCrapsTable();
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip();
        (bool finalDone, uint48 finalCur) = _frontier();
        assertTrue(finalDone, "the stationary follow-up keeps the completed frontier");
        assertEq(finalCur, 0, "the stationary follow-up leaves the cursor zero");
    }

    /// @dev The call's MinerWork (execution gas, reward), requiring every `MinerBounty` in it to be
    ///      the engine's gas-priced miner reward (kind 1) and to equal the reported reward: any
    ///      other kind on a skip-only sweep is the regression.
    function _minerRewardOnly(Vm.Log[] memory logs) internal view returns (uint256 used, uint256 reward) {
        bytes32 bountyTopic = keccak256("MinerBounty(uint8,address,uint256)");
        bytes32 workTopic = keccak256("MinerWork(address,uint8,uint256,uint256)");
        uint256 credited;
        bool sawWork;
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0) continue;
            if (logs[i].topics[0] == bountyTopic) {
                (uint8 kind, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                require(kind == 1, "regression: a non-miner bounty was paid for skip-only sweep progress");
                credited += amount;
            } else if (logs[i].topics[0] == workTopic) {
                (, used, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                sawWork = true;
            }
        }
        require(sawWork, "fixture: the keeper call reported its work");
        require(credited == reward, "regression: the credited bounty differs from the reported reward");
    }
}
