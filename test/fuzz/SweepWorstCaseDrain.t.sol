// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @dev Read-only view overlay etched onto the live game to inspect internal box-queue state.
///      A DegenerusGame subclass: etching type().runtimeCode (no constructor) gives the reads access
///      to the live internal boxPlayers / lootboxEth / presaleBoxEth maps + the packed cursor pair
///      without any storage change; the real code is restored after each read.
contract SweepViewer is DegenerusGame {
    function lrIndexView() external view returns (uint48) {
        return uint48(_lrRead(LR_INDEX_SHIFT, LR_INDEX_MASK));
    }

    function queueLen(uint48 index) external view returns (uint256) {
        return boxPlayers[index].length;
    }

    function lootboxAmountFor(uint48 index, address who) external view returns (uint256) {
        return lootboxEth[index][who] & LB_AMOUNT_MASK;
    }

    function presaleAmountFor(uint48 index, address who) external view returns (uint256) {
        return presaleBoxEth[index][who] & PRESALE_BOX_AMOUNT_MASK;
    }

    function boxCursorView() external view returns (uint48) {
        return boxCursor;
    }

    function boxCursorIndexView() external view returns (uint48) {
        return boxCursorIndex;
    }
}

/// @title SweepWorstCaseDrain — AUTO-03 worst-case multi-index, step-budgeted human-box sweep.
///
/// @notice The relocated openHumanBoxes sweep (DegenerusGameLootboxModule, delegatecall'd from
///         openBoxes) walks the open frontier boxCursorIndex..LR_INDEX-1, opening BOTH legs of every
///         ready entry. The worst case the step budget defends against: a LONG prefix of already-
///         opened / presale-only / no-box entries (each a pure skip) ahead of a live lootbox box,
///         plus MULTIPLE finalized indices behind the frontier. The skip-wall must be crossed via the
///         per-call step budget (opens AND skips each cost one step), so no single tx ever approaches
///         the 16.7M ceiling, progress is monotonic across calls, and nothing is ever marooned.
///
///         This test seeds that exact shape and asserts:
///           (1) every openBoxes() chunk stays WELL under the 16.7M per-tx ceiling;
///           (2) the open frontier (boxCursorIndex, boxCursor) advances MONOTONICALLY each call;
///           (3) the drain COMPLETES — every finalized index is fully swept, no box bricked;
///           (4) the live lootbox box AND a presale box are auto-opened by the sweep (both legs).
///
/// @dev Test-only. ZERO contracts/*.sol mutation. Real lootbox + presale boxes are created through
///      the genuine purchase entrypoints (so their resolution is solvent); the skippable prefix
///      (no-box addresses) and the earlier finalized indices are seeded via field-isolated slot
///      pokes (the established BoxCreationHandler / PresaleBoxDrain idiom). A read-only viewer is
///      etched to inspect internal maps; the real code is restored after every read.
contract SweepWorstCaseDrain is DeployProtocol {
    // Authoritative slots (post Stage B pack), RE-DERIVED via `solc --storage-layout`.
    uint256 private constant SLOT_LOOTBOX_RNG_PACKED = 34;   // [0:47] lootboxRngIndex
    uint256 private constant SLOT_LOOTBOX_RNG_WORD = 35;     // mapping(uint48 => uint256)
    uint256 private constant SLOT_BOX_PLAYERS = 59;          // mapping(uint48 => address[])
    uint256 private constant SLOT_BOX_CURSORS = 58;          // boxCursor @ byte 7, boxCursorIndex @ byte 13
    uint256 private constant LR_INDEX_MASK = 0xFFFFFFFFFFFF;

    // Hard per-tx ceilings (mirrors V56AfkingGasMarginal): 16.7M = the gameover-composition gg bound.
    uint256 private constant EFFECTIVE_GAS_CEILING = 16_700_000;
    uint256 private constant TEN_M_TARGET = 10_000_000;

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
    // Etched-viewer helpers (real code restored after each read)
    // =========================================================================

    function _lrIndex() internal returns (uint48 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        v = SweepViewer(payable(address(game))).lrIndexView();
        vm.etch(address(game), real);
    }

    function _lootAmt(uint48 index, address who) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        v = SweepViewer(payable(address(game))).lootboxAmountFor(index, who);
        vm.etch(address(game), real);
    }

    function _presaleAmt(uint48 index, address who) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        v = SweepViewer(payable(address(game))).presaleAmountFor(index, who);
        vm.etch(address(game), real);
    }

    function _queueLen(uint48 index) internal returns (uint256 v) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        v = SweepViewer(payable(address(game))).queueLen(index);
        vm.etch(address(game), real);
    }

    function _frontier() internal returns (uint48 idx, uint48 cur) {
        bytes memory real = address(game).code;
        vm.etch(address(game), type(SweepViewer).runtimeCode);
        idx = SweepViewer(payable(address(game))).boxCursorIndexView();
        cur = SweepViewer(payable(address(game))).boxCursorView();
        vm.etch(address(game), real);
    }

    // =========================================================================
    // Slot-poke seeding helpers (no contract mutation)
    // =========================================================================

    /// @dev Bump the active lootbox RNG index (low 48 bits of lootboxRngPacked) by `n`, mirroring
    ///      requestLootboxRng's pre-increment, so boxes queued at the prior indices become finalized
    ///      (LR_INDEX-1 and below — the indices the sweep opens).
    function _advanceLrIndexBy(uint48 n) internal {
        bytes32 slot = bytes32(uint256(SLOT_LOOTBOX_RNG_PACKED));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint48 idx = uint48(packed & LR_INDEX_MASK);
        packed = (packed & ~LR_INDEX_MASK) | (uint256(idx + n) & LR_INDEX_MASK);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Land the committed VRF word for `index` (the per-index freeze anchor the open reads).
    function _landWord(uint48 index, uint256 word) internal {
        bytes32 slot = keccak256(abi.encode(uint256(index), uint256(SLOT_LOOTBOX_RNG_WORD)));
        vm.store(address(game), slot, bytes32(word));
    }

    /// @dev Park the open frontier (boxCursorIndex @ byte 13, boxCursor @ byte 7, both slot 58) at
    ///      `index` with a zero in-index cursor, so the sweep begins exactly there.
    function _parkFrontier(uint48 index) internal {
        bytes32 slot = bytes32(uint256(SLOT_BOX_CURSORS));
        uint256 packed = uint256(vm.load(address(game), slot));
        uint256 m = (uint256(1) << 48) - 1;
        packed &= ~(m << (7 * 8));   // boxCursor = 0
        packed &= ~(m << (13 * 8));  // boxCursorIndex field cleared
        packed |= (uint256(index) & m) << (13 * 8);
        vm.store(address(game), slot, bytes32(packed));
    }

    /// @dev Append `count` no-box addresses to boxPlayers[index] — a pure skip-prefix. Each entry has
    ///      a zero lootbox amount AND zero presale leg, so the sweep skips it (one step, no
    ///      resolution, never reverts). boxPlayers[index] is mapping(uint48 => address[]) at slot 59:
    ///      length at keccak(index, 59); element i at keccak(keccak(index,59)) + i.
    function _appendSkipPrefix(uint48 index, uint256 count, uint256 saltSeed) internal {
        bytes32 lenSlot = keccak256(abi.encode(uint256(index), uint256(SLOT_BOX_PLAYERS)));
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

    /// @dev Drive a genesis daily cycle so rngWordByDay[today] != 0 and the lock clears
    ///      (requestLootboxRng requires today's daily word recorded + rngLocked == false).
    function _driveDailyCycleOnce() internal {
        (, , , , uint256 priceWei) = game.purchaseInfo();
        if (priceWei != 0 && priceWei <= actor.balance) {
            vm.prank(actor);
            try game.purchase{value: priceWei}(actor, 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }
        for (uint256 i; i < 12 && !game.rngLocked(); i++) {
            vm.warp(block.timestamp + 1 days);
            vm.prank(actor);
            try game.advanceGame() {} catch {}
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
            try game.advanceGame() {} catch {}
        }
    }

    /// @dev Buy a REAL human lootbox-mode box at the current active index (first-deposit enqueue).
    function _buyLootbox(address who, uint256 lootboxWei) internal {
        vm.deal(who, lootboxWei + 2 ether);
        vm.prank(who);
        game.purchase{value: lootboxWei + 1 ether}(who, 400, lootboxWei, bytes32(0), MintPaymentKind.DirectEth, false);
    }

    /// @dev Buy a REAL presale box at the current active index (credit-funded; enqueues for auto-open).
    function _buyPresaleBox(address who, uint256 boxWei) internal returns (bool created) {
        if (game.presaleBoxEthRemaining() == 0) return false;
        // Seed spendable presale-box credit (slot 17 — a credit ALLOWANCE, not a box record).
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

    /// @notice FUZZ: a long skip-prefix ahead of a live lootbox box at the finalized index, plus
    ///         earlier finalized indices each carrying their own skip-prefix, all drain across
    ///         bounded-gas openBoxes chunks — every tx well under 16.7M, monotonic progress, never
    ///         bricks. A presale box is auto-opened by the sweep too. (No assertion is weakened: the
    ///         drain MUST complete and both real boxes MUST open.)
    function testFuzz_WorstCaseSweepDrainsBoundedNoBrick(
        uint256 prefixSeed,
        uint256 chunkSeed,
        uint256 lootSeed
    ) public {
        // 1) Live game so a real lootbox + presale box resolve solvently.
        _driveDailyCycleOnce();
        vm.assume(!game.rngLocked());

        // 2) Real boxes at the CURRENT active index (the one that will become the frontier).
        uint48 liveIndex = _lrIndex();
        address lootOwner = makeAddr("loot-owner");
        uint256 lootboxWei = bound(lootSeed, 0.05 ether, 2 ether);
        _buyLootbox(lootOwner, lootboxWei);
        assertGt(_lootAmt(liveIndex, lootOwner), 0, "fixture: real lootbox box queued at liveIndex");

        address presaleOwner = makeAddr("presale-owner");
        bool presaleCreated = _buyPresaleBox(presaleOwner, 1 ether);
        // Presale must actually be created for the presale-leg assertion to be non-vacuous.
        vm.assume(presaleCreated);
        assertGt(_presaleAmt(liveIndex, presaleOwner), 0, "fixture: real presale box queued at liveIndex");

        // 3) A LONG skip-prefix AHEAD of the live boxes at liveIndex (pure skips: no-box addresses).
        uint256 prefixLen = bound(prefixSeed, 40, 160);
        // Append the skips AFTER the real entries: the sweep still must scan past them to fully drain
        // the index (the skip-wall is the tail here). Both placements (head/tail) are pure skips; a
        // tail prefix additionally proves the cursor persists past the real opens within one index.
        _appendSkipPrefix(liveIndex, prefixLen, prefixSeed);

        // 4) MULTIPLE finalized indices BEHIND the frontier, each a pure skip-prefix with its word
        //    landed (so the sweep advances through them rather than orphan-breaking).
        uint48 earlierA = liveIndex >= 2 ? liveIndex - 1 : liveIndex; // distinct only if room
        uint48 earlierB = liveIndex >= 3 ? liveIndex - 2 : liveIndex;
        if (earlierA != liveIndex) {
            _appendSkipPrefix(earlierA, bound(prefixSeed >> 8, 20, 80), prefixSeed ^ 0xA);
            _landWord(earlierA, uint256(keccak256("wordA")) | 1);
        }
        if (earlierB != liveIndex && earlierB != earlierA) {
            _appendSkipPrefix(earlierB, bound(prefixSeed >> 16, 20, 80), prefixSeed ^ 0xB);
            _landWord(earlierB, uint256(keccak256("wordB")) | 1);
        }

        // 5) Finalize: advance LR_INDEX past liveIndex so liveIndex (and earlier) are openable, land
        //    the live index word, and park the frontier at the lowest seeded index.
        _advanceLrIndexBy(1);
        assertEq(_lrIndex(), liveIndex + 1, "finalize: LR_INDEX advanced; liveIndex is now LR_INDEX-1");
        _landWord(liveIndex, uint256(keccak256("liveWord")) | 1);

        uint48 startIndex = earlierB != liveIndex && earlierB != earlierA
            ? earlierB
            : (earlierA != liveIndex ? earlierA : liveIndex);
        _parkFrontier(startIndex);

        // 6) Drain in BOUNDED chunks. Each call: assert gas under the ceiling + monotonic progress.
        uint256 chunk = bound(chunkSeed, 8, 64);
        uint256 totalEntries = prefixLen + 2; // real loot + presale at liveIndex
        if (earlierA != liveIndex) totalEntries += bound(prefixSeed >> 8, 20, 80);
        if (earlierB != liveIndex && earlierB != earlierA) totalEntries += bound(prefixSeed >> 16, 20, 80);

        (uint48 prevIdx, uint48 prevCur) = _frontier();
        uint256 guard;
        bool progressedOnce;
        while (guard < 4000) {
            guard += chunk + 1;

            uint256 gasBefore = gasleft();
            vm.prank(actor);
            game.openBoxes(chunk); // the human sweep is the only leg (no afking subs here)
            uint256 gasUsed = gasBefore - gasleft();

            // (1) per-tx gas bound — well under the 16.7M gg ceiling.
            assertLt(gasUsed, EFFECTIVE_GAS_CEILING, "BOUNDED: a sweep chunk must stay under the 16.7M ceiling");

            (uint48 nowIdx, uint48 nowCur) = _frontier();

            // (3)+drained check: stop once the frontier has swept past the live (highest) index.
            if (nowIdx > liveIndex) break;

            // (2) monotonic progress: the frontier (index, then cursor) never regresses, and a
            //     non-terminal call ALWAYS makes forward progress (the step budget crosses the wall).
            bool advanced = (nowIdx > prevIdx) || (nowIdx == prevIdx && nowCur > prevCur);
            assertTrue(advanced, "MONOTONIC: each non-terminal sweep chunk advances the open frontier (no stall, no regress)");
            progressedOnce = progressedOnce || advanced;
            prevIdx = nowIdx;
            prevCur = nowCur;
        }
        assertTrue(progressedOnce, "non-vacuity: the sweep actually walked the queue");
        assertLt(guard, 4000, "DRAIN COMPLETE: the whole multi-index queue drains in bounded chunks (no brick / infinite stall)");

        // (4) the live lootbox box AND the presale box were auto-opened (both legs drained).
        assertEq(_lootAmt(liveIndex, lootOwner), 0, "DRAINED: the live lootbox box was auto-opened by the sweep");
        assertEq(_presaleAmt(liveIndex, presaleOwner), 0, "DRAINED: the presale box was auto-opened by the sweep (presale leg)");

        // The frontier swept entirely past the live index — nothing marooned below it.
        (uint48 finalIdx, ) = _frontier();
        assertGt(finalIdx, liveIndex, "FRONTIER: the open frontier advanced past every finalized index (none marooned)");
    }

    /// @dev Regression: when the human sweep scans only stale entries (opens nothing) but advances
    ///      the monotonic open frontier, mintFlip COMMITS that progress with no bounty instead of
    ///      reverting NoWork and rolling it back. So the keeper route advances through a skip wall
    ///      cumulatively across calls and reaches the live box behind it. Pre-fix this
    ///      reverted NoWork every call, rolling cursor=79 back to 0 and stranding the tail box on
    ///      the rewarded route (recoverable only via the unrewarded openBoxes valve).
    function testRegression_MintFlipCommitsSkipProgressAndReachesLiveTail() public {
        _driveDailyCycleOnce();
        require(!game.rngLocked(), "fixture: game unlocked");

        // Settle any pending advance WITHOUT warping the clock: advanceGame catches dailyIdx up to
        // the fixed sim day (fulfilling each VRF request), after which advance is not due and the
        // game is unlocked — the state where mintFlip takes the box-open arm.
        for (uint256 i = 0; i < 40 && (game.advanceDue() || game.rngLocked()); i++) {
            try game.advanceGame() {} catch {}
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("settle", i))) | 1) {} catch {}
                }
            }
        }

        // Clear any incidental afking boxes so mintFlip's only possible work is the human queue.
        vm.prank(actor);
        game.openBoxes(1_000);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: no advance work, unlocked");

        uint48 index = _lrIndex();
        _appendSkipPrefix(index, 80, 0xBAD5EED);

        address liveOwner = makeAddr("audit-live-owner");
        _buyLootbox(liveOwner, 1 ether);
        assertEq(_queueLen(index), 81, "fixture: eighty stale entries precede one live box");
        assertGt(_lootAmt(index, liveOwner), 0, "fixture: tail box is live");

        _advanceLrIndexBy(1);
        _landWord(index, uint256(keccak256("audit-word")) | 1);
        _parkFrontier(index);
        assertTrue(game.boxesPending(), "fixture: router advertises human-box work");
        require(!game.advanceDue(), "fixture: mintFlip takes open arm");

        (uint48 beforeIdx, uint48 beforeCur) = _frontier();
        assertEq(beforeIdx, index, "fixture: frontier index");
        assertEq(beforeCur, 0, "fixture: zero cursor");

        // Call 1: budget 80 spends one step on the index header and 79 on stale entries, opening
        // nothing — but the frontier advanced to cur=79. Post-fix mintFlip does NOT revert; it
        // COMMITS that skip-only progress (no bounty).
        uint256 keeperFlipBefore = coinflip.coinflipAmount(actor);
        uint256 gasBefore = gasleft();
        vm.prank(actor);
        game.mintFlip();
        uint256 skipOnlyGas = gasBefore - gasleft();

        (uint48 afterIdx, uint48 afterCur) = _frontier();
        assertEq(afterIdx, beforeIdx, "regression: still sweeping the same index");
        assertEq(afterCur, 79, "regression: skip-only progress is COMMITTED, not rolled back");
        assertGt(_lootAmt(index, liveOwner), 0, "regression: budget hit the wall - tail box not yet reached");
        assertEq(
            coinflip.coinflipAmount(actor),
            keeperFlipBefore,
            "regression: skip-only housekeeping earns no bounty"
        );
        assertLt(skipOnlyGas, EFFECTIVE_GAS_CEILING, "regression: skip-only keeper call fits the tx ceiling");

        // Call 2: the keeper route resumes past the committed frontier and opens the live box. This
        // call performs an actual open, so it receives the normal work-scaled bounty.
        vm.prank(actor);
        game.mintFlip();
        assertEq(_lootAmt(index, liveOwner), 0, "regression: keeper route reaches and opens the live tail box");
        assertGt(
            coinflip.coinflipAmount(actor),
            keeperFlipBefore,
            "regression: an actual box open earns the normal keeper bounty"
        );
        (uint48 finalIdx, ) = _frontier();
        assertGt(finalIdx, index, "regression: frontier swept past the finalized index");

        // Genuine no-work still reverts cleanly: nothing opened AND the frontier cannot move.
        require(!game.boxesPending(), "fixture: no human-box work remains");
        require(!game.advanceDue(), "fixture: no advance work remains");
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
    }

    /// @dev The logical frontier clamps the uninitialized storage value 0 to genesis index 1 on
    ///      BOTH sides of the progress comparison. A true genesis no-work probe therefore cannot
    ///      report phantom progress merely because openHumanBoxes returns before storing the clamp;
    ///      nor can parking raw storage at 1 in front of an unworded index count as progress.
    function testRegression_MintFlipLogicalFrontierRejectsPhantomProgress() public {
        // Undo setUp's one-day warp: immediately after deployment the game is settled, the active
        // lootbox index is genesis index 1, and the human-box frontier is still raw storage zero.
        vm.warp(block.timestamp - 1 days);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: genesis is idle and unlocked");
        assertEq(_lrIndex(), 1, "fixture: genesis active index is one");
        (uint48 beforeIdx, uint48 beforeCur) = _frontier();
        assertEq(beforeIdx, 0, "fixture: raw frontier is still uninitialized");
        assertEq(beforeCur, 0, "fixture: raw cursor is zero");

        // active <= 1 makes openHumanBoxes return before writing. Logical 1 -> logical 1 is not
        // progress, even though comparing a normalized pre-value against raw post-storage would
        // incorrectly see 1 != 0.
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
        (uint48 afterIdx, uint48 afterCur) = _frontier();
        assertEq(afterIdx, beforeIdx, "genesis no-work leaves the raw frontier unchanged");
        assertEq(afterCur, beforeCur, "genesis no-work leaves the raw cursor unchanged");

        // Finalize index 1 without landing its word. openHumanBoxes temporarily stores the raw
        // 0 -> 1 clamp before stopping at the orphan guard, but logical 1 -> logical 1 is still no
        // progress; the outer NoWork revert rolls that housekeeping-only store back.
        _advanceLrIndexBy(1);
        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
        (afterIdx, afterCur) = _frontier();
        assertEq(afterIdx, 0, "unworded-index probe cannot commit the raw clamp as work");
        assertEq(afterCur, 0, "unworded-index probe leaves the entry cursor unchanged");

        // Once the index is worded, traversing its empty queue really advances logical 1 -> 2.
        // That bounded housekeeping progress commits once, then a stationary follow-up is NoWork.
        _landWord(1, uint256(keccak256("genesis-frontier-word")) | 1);
        vm.prank(actor);
        game.mintFlip();
        (afterIdx, afterCur) = _frontier();
        assertEq(afterIdx, 2, "worded empty index advances and commits the logical frontier");
        assertEq(afterCur, 0, "empty index leaves the entry cursor zero");

        vm.prank(actor);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
    }
}
