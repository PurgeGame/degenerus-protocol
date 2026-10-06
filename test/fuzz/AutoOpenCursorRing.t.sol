// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {IDegenerusGameAdvanceModule, IDegenerusGameRngModule, IDegenerusGameTicketModule, IGameAfkingModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @dev Test-only checkpoint driver: executes exactly the currently selected
/// production worker before AFK, or the AFK open worker alone. The composed miner
/// ordinarily opens the boxes within the same transaction, so it cannot expose these
/// intermediate checkpoints. Every production worker keeps its own guards; no
/// obligation/word is fabricated.
contract RingSingleStepFixture is DegenerusGame {
    function stepBeforeAfk() external {
        MinerAction action = _nextMinerAction(address(0));
        address target;
        bytes memory input;
        if (action == MinerAction.Publish) {
            target = ContractAddresses.GAME_RNG_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameRngModule.publishRng.selector);
        } else if (action == MinerAction.Tickets) {
            target = ContractAddresses.GAME_TICKET_MODULE;
            uint24 anchor = !jackpotPhaseFlag && lastPurchaseDay && rngLockedFlag ? level : level + 1;
            input = abi.encodeWithSelector(IDegenerusGameTicketModule.runTicketWork.selector, anchor, uint256(10_000_000));
        } else if (action == MinerAction.DailyGap) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyGap.selector);
        } else if (action == MinerAction.DailyApply) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.applyDailyWord.selector);
        } else if (action == MinerAction.DailyPhase) {
            target = ContractAddresses.GAME_ADVANCE_MODULE;
            input = abi.encodeWithSelector(IDegenerusGameAdvanceModule.runDailyPhase.selector, uint256(10_000_000));
        } else revert("unexpected pre-AFK checkpoint");
        (bool ok, bytes memory reason) = target.delegatecall(input);
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
        if (action == MinerAction.Tickets) {
            (, bool done,) = abi.decode(reason, (bool, bool, uint256));
            // Exactly the miner's successful-ticket completion transition.
            if (done) {
                ticketsFullyProcessed = true;
                _lrWrite(LR_MID_DAY_SHIFT, LR_MID_DAY_MASK, 0);
            }
        }
    }

    /// @dev One call of the AFK open worker mineFlip dispatches for the Afking stage, with the
    ///      same allowance shape. Returns the boxes it opened (its reward basis).
    function runAfkOnce() external returns (uint256 opened) {
        (bool ok, bytes memory ret) = ContractAddresses.GAME_AFKING_MODULE.delegatecall(
            abi.encodeWithSelector(IGameAfkingModule.runAfkingWork.selector, uint256(10_000_000)));
        if (!ok) assembly ("memory-safe") { revert(add(ret, 32), mload(ret)) }
        opened = abi.decode(ret, (MineFlipGas.Result)).rewardBasis;
    }
}

/// @title AutoOpenCursorRing — pending AFK boxes drain across the whole subscriber ring.
/// @notice Directed cursor cases retain openable members below a non-pending tail
/// cursor and exercise the production AFK open worker and mineFlip.
/// Subscription creation and box purchases use public protocol paths; the
/// intermediate pre-open checkpoint and the isolated open call use RingSingleStepFixture
/// to execute the guarded production worker mineFlip would select. That checkpoint
/// instrumentation is necessary because one composed mineFlip can finish and open in
/// one call. It is a worker-order fixture, not proof that a public transaction stops there.
/// @dev Cursor pokes are explicit for the two directed wrap cases. The growth
/// case uses no cursor poke. No contracts/*.sol source is changed.
contract AutoOpenCursorRing is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the post-PACK Sub-slot offset block
    // (forge inspect DegenerusGame storage: _subOf@52, _subscribers@54, _subscriberIndex@55, cursors@56)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = GameSlots.SUB_OF;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = GameSlots.SUBSCRIBERS;      // address[] _subscribers (length @ slot; elements @ keccak256(slot)+i)
    uint256 private constant CURSOR_SLOT = GameSlots.SUB_CURSOR;           // packed: _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4
    uint256 private constant OPEN_CURSOR_BYTE = 2;       // byte offset of _subOpenCursor within CURSOR_SLOT
    uint256 private constant MINTPACKED_SLOT = GameSlots.MINT_PACKED;        // mintPacked_ mapping root (deity bit @ 184)

    //   dailyQuantity u8 @0 · flags u8 @1 · score u16 @2 · amount u24 @4
    //   lastAutoBoughtDay u24 @7 · lastOpenedDay u24 @10 · afkCoveredThroughDay u24 @13 · afkingStartDay u24 @16
    //   affiliateBase u32 @19 · pendingFlip u24 @23 · subStreakLatch u16 @26
    uint256 private constant OFF_LASTBOUGHT = 7;      // uint24 lastAutoBoughtDay (bytes 7..9)
    uint256 private constant OFF_LASTOPENED = 10;     // uint24 lastOpenedDay     (bytes 10..12)

    uint256 private constant DEITY_SHIFT = 184;

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(admin.subscriptionId(), uint96(100 ether));
        _t = block.timestamp + 1 days;
        vm.warp(_t);
        vm.deal(address(game), 5_000_000 ether);
    }

    // =========================================================================
    // 1 — stranded subs in [0, cursor) drain after the cursor wedges mid-array
    // =========================================================================

    /// @notice With several subs each carrying a SEALED openable box, wedge `_subOpenCursor` at a mid-array
    ///         index whose sub is NON-pending (so a suffix-only scan from there finds nothing) and assert
    ///         the open path STILL opens the stranded boxes at indices `< cursor`: their `lastOpenedDay`
    ///         advances to `lastAutoBoughtDay` and `opened > 0`. The full-ring scan wraps past `len` back to
    ///         0; the old suffix-only `[cursor, len)` scan provably could not reach `[0, cursor)`.
    function test_StrandedSubsDrainAfterCursorWedge() public {
        // Five subs, each with a sealed (stamped-but-unopened) openable box. Stamping via the real STAGE
        // (a new-day buy with NO subsequent open) leaves each with lastOpenedDay < lastAutoBoughtDay and a
        // landed _recordedDailyWord(lastAutoBoughtDay) — exactly the openable predicate.
        address[] memory subs = _stampSealedOpenableSubs(5);

        // The "wedge" sub: a fresh, NOT-yet-stamped subscriber pushed to the tail of `_subscribers` AFTER
        // the openable subs. A just-created sub has no pending box (lastOpenedDay == lastAutoBoughtDay == 0
        // pre-buy), so it is non-pending — landing the cursor on it makes a suffix-only scan find no work.
        address wedge = _freshNonPendingSub("ring_wedge");
        uint256 wedgeIdx = _subscriberIndexOf(wedge) - 1; // 0-based index in _subscribers

        // Wedge the open cursor onto the non-pending fresh sub (a mid-array index, since the openable subs
        // sit at indices < wedgeIdx). Documented vm.store poke: it reproduces the exact stuck-cursor state
        // (cursor at a non-openable mid-array sub) the real subscribe-grows-the-set path produces.
        _setOpenCursor(uint16(wedgeIdx));
        assertTrue(wedgeIdx < _subscribersLength(), "fixture: the cursor index is mid-array (< len)");
        assertTrue(_isNonPending(wedge), "fixture: the cursor sub is non-pending (suffix scan finds nothing here)");

        // Fails-without: every openable box sits STRICTLY BELOW the cursor, so the old [cursor, len)-only
        // scan provably could not reach any of them — only the full-ring scan opens them.
        for (uint256 i; i < subs.length; i++) {
            assertTrue(_subscriberIndexOf(subs[i]) - 1 < wedgeIdx, "fails-without: openable box is at an index strictly < cursor");
            assertTrue(_isOpenable(subs[i]), "fixture: the sub below the cursor is openable (pending box + landed word)");
        }

        // Drive the production AFK open worker. The full-ring scan wraps from the wedge index past len back
        // to 0, reaching the stranded openable boxes.
        uint256 opened = _openAfkRing();
        assertGt(opened, 0, "ring: the open leg did NOT return 0 with openable boxes still present");

        // Every stranded box was opened — its lastOpenedDay caught up to lastAutoBoughtDay.
        for (uint256 i; i < subs.length; i++) {
            assertEq(_lastOpenedDayOf(subs[i]), _lastBoughtDayOf(subs[i]), "ring: the stranded [0,cursor) box was opened (marker advanced)");
            assertFalse(_isOpenable(subs[i]), "ring: no openable box left behind for the stranded sub");
        }
    }

    /// @notice The same wedge driven through the keeper path (Game.mineFlip's open category) opens the
    ///         stranded boxes too — mineFlip pays the open bounty rather than reverting NoWork while
    ///         openable boxes exist below the cursor.
    function test_StrandedSubsDrainViaMintFlipKeeper() public {
        address[] memory subs = _stampSealedOpenableSubs(4);
        address wedge = _freshNonPendingSub("mf_wedge");
        uint256 wedgeIdx = _subscriberIndexOf(wedge) - 1;
        _setOpenCursor(uint16(wedgeIdx));
        assertTrue(_isNonPending(wedge), "fixture: cursor sub non-pending");
        for (uint256 i; i < subs.length; i++) {
            assertTrue(_subscriberIndexOf(subs[i]) - 1 < wedgeIdx, "fails-without: openable box strictly < cursor");
            assertTrue(_isOpenable(subs[i]), "fixture: sub below cursor openable");
        }

        // AFK is the selected committed consumer. The public keeper must find
        // the openable boxes below the cursor and make progress.
        address keeper = makeAddr("mf_keeper");
        _grantDeityPass(keeper); // retain the original eligible keeper fixture
        require(uint8(game.nextMinerAction()) == 9 && !game.rngLocked(), "fixture: AFK is the selected consumer");
        vm.prank(keeper);
        game.mineFlip(); // MUST NOT revert NoWork — the open category had work below the cursor

        for (uint256 i; i < subs.length; i++) {
            assertEq(_lastOpenedDayOf(subs[i]), _lastBoughtDayOf(subs[i]), "ring(keeper): stranded box opened");
        }
    }

    // =========================================================================
    // 2 — NoWork fires ONLY when the whole set is truly drained, never while boxes remain
    // =========================================================================

    /// @notice With the same wedge, the keeper open path does NOT revert NoWork while openable boxes exist,
    ///         and DOES cleanly no-op (returns 0 / reverts NoWork) only once EVERY box is opened. Proves the
    ///         0-open / NoWork signal now means "whole set drained", not "suffix drained".
    function test_NoWorkOnlyWhenTrulyDrained() public {
        address[] memory subs = _stampSealedOpenableSubs(5);
        address wedge = _freshNonPendingSub("nw_wedge");
        uint256 wedgeIdx = _subscriberIndexOf(wedge) - 1;
        _setOpenCursor(uint16(wedgeIdx));
        assertTrue(_isNonPending(wedge), "fixture: cursor sub non-pending");
        for (uint256 i; i < subs.length; i++) {
            assertTrue(_subscriberIndexOf(subs[i]) - 1 < wedgeIdx, "fails-without: openable box strictly < cursor");
        }

        // While openable boxes exist below the cursor, mineFlip's open leg has work -> NO NoWork revert.
        address keeper = makeAddr("nw_keeper");
        _grantDeityPass(keeper);
        require(uint8(game.nextMinerAction()) == 9 && !game.rngLocked(), "fixture: AFK is the selected consumer");
        vm.prank(keeper);
        game.mineFlip(); // MUST NOT revert NoWork — there IS open work

        // Every afking box is now opened: the whole afking ring is drained (the ring scan reached the
        // stranded [0, cursor) subs, not just the suffix).
        for (uint256 i; i < subs.length; i++) {
            assertFalse(_isOpenable(subs[i]), "drain: no openable afking box remains after the ring scan");
        }
        // Finish the rest of the read cohort (the incidental human boxes the STAGE buys created), then a
        // final clean AFK worker call opens nothing — the open path cleanly no-ops once every box is opened.
        _finishReadConsumers();
        assertEq(_openAfkRing(), 0, "drained: a follow-up AFK open opens nothing (whole set drained)");

        // NOW (and only now) mineFlip cleanly signals no work: with no advance due and the afking ring
        // fully drained, both router categories are empty -> the clean NoWork no-op (not a suffix-strand
        // false-positive while [0, cursor) boxes remained).
        // The crank has a craps arm now, so a NoWork probe has to quiet the table too or it is
        // asserting an idleness it never set up.
        _quietCrapsTable();
        // The fresh wedge subscription also bought an indexed human cover
        // box. If it is below the midday request threshold, the next normal
        // daily commitment is its guaranteed settlement path.
        _t += 1 days;
        vm.warp(_t);
        _settleClean(uint256(keccak256("ring_final_drain")) | 1);
        require(!game.advanceDue() && !game.rngLocked(), string.concat("fixture: final drain action=", vm.toString(uint8(game.nextMinerAction()))));
        assertEq(uint8(game.nextMinerAction()), 0, "all consumer and maintenance work is idle");
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mineFlip();
    }

    // =========================================================================
    // Real-path wedge — a subscribe grows the set while the cursor sits at the old length
    // =========================================================================

    /// @notice A public subscription grows the set without a cursor poke. After
    /// a later guarded-worker checkpoint stamps fresh boxes, the AFK open worker
    /// drains them. Directed wrap geometry is asserted by the separate wedge cases.
    function test_RealPathSubscribeGrowsSetThenDrains() public {
        // Stamp two openable subs, then drain the current ring.
        address[] memory first = _stampSealedOpenableSubs(2);
        // Open everything currently pending and record the resulting cursor.
        _openAfkRing();
        for (uint256 i; i < first.length; i++) {
            assertFalse(_isOpenable(first[i]), "fixture: the first wave's boxes opened (cursor walked the set)");
        }
        uint16 cursorAfterDrain = _openCursor();
        uint256 lenBeforeGrow = _subscribersLength();

        // A fresh subscription grows the set. No particular post-drain cursor
        // position is assumed by this growth case.
        address grower = _freshNonPendingSub("realpath_grow");
        assertGt(_subscribersLength(), lenBeforeGrow, "real path: the subscribe grew _subscribers (push, no cursor reset)");

        // Stamp a new box on an original member through the guarded worker
        // checkpoint and require nonempty work before invoking the open worker.
        address stranded = first[0];
        _stampSealedBoxOn(stranded);
        assertTrue(_isOpenable(stranded), "fixture: a fresh openable box exists on the original member");
        // The original member remains in the grown set.
        assertTrue(_subscriberIndexOf(stranded) - 1 < _subscribersLength(), "non-vacuity: stranded sub in-set");
        // Record the actual geometry without assuming the cursor parks at length.
        emit log_named_uint("open cursor after drain", cursorAfterDrain);
        emit log_named_uint("grown set length", _subscribersLength());
        emit log_named_uint("grower index (cursor sub)", _subscriberIndexOf(grower) - 1);

        // The ring scan drains the stranded openable box no matter where the cursor parked.
        uint256 opened = _openAfkRing();
        assertGt(opened, 0, "real path: the ring scan opened the stranded box (no suffix-only strand)");
        assertEq(_lastOpenedDayOf(stranded), _lastBoughtDayOf(stranded), "real path: the stranded box opened (marker advanced)");
    }

    // =========================================================================
    // Box-drive helpers
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Create `n` seated, funded subs and stamp ONE sealed openable box on each: a new-day STAGE
    ///      buy that stamps the box + lands its stamp-day word, with NO subsequent open. Each sub ends up
    ///      with lastOpenedDay < lastAutoBoughtDay and _recordedDailyWord(lastAutoBoughtDay) != 0 (openable).
    function _stampSealedOpenableSubs(uint256 n) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address p = makeAddr(string(abi.encodePacked("ring_sub_", vm.toString(i))));
            _grantSeat(p);          // the AFKing Subscription Token is the sole subscribe credential
            _fundPool(p, 80 ether); // grounds the NEW-run cover-buy
            _subscribeLootbox(p, 1);
            subs[i] = p;
        }
        // ONE new-day STAGE buy stamps a pending box on every in-set sub + lands the stamp-day word; NO open.
        _runStageNewDay(uint256(keccak256(abi.encode("ring_stamp", _deliverNonce++))) | 1);
        for (uint256 i; i < n; i++) {
            require(_isOpenable(subs[i]), "fixture: each sub carries a sealed openable box (pending + landed word)");
        }
    }

    /// @dev Stamp a fresh sealed openable box on an existing in-set sub via a real new-day STAGE buy (no open).
    function _stampSealedBoxOn(address p) internal {
        _runStageNewDay(uint256(keccak256(abi.encode("ring_restamp", _deliverNonce++))) | 1);
        require(_isOpenable(p), "fixture: a fresh sealed openable box was stamped");
    }

    /// @dev Create a fresh seated/funded subscriber at the tail. Its inline cover
    /// purchase is indexed separately, so its AFK Sub has no pending stamped box.
    function _freshNonPendingSub(string memory tag) internal returns (address p) {
        p = makeAddr(tag);
        _grantSeat(p);
        _fundPool(p, 80 ether);
        _subscribeLootbox(p, 1);
        require(_subscriberIndexOf(p) > 0, "fixture: the fresh sub joined the set");
    }

    /// @dev One call of the production AFK open worker (GameAfkingModule.runAfkingWork, the worker
    ///      mineFlip dispatches for the Afking stage), run in the Game's context through the checkpoint
    ///      fixture. Returns the afking ring boxes it opened.
    function _openAfkRing() internal returns (uint256 opened) {
        bytes memory productionCode = address(game).code;
        vm.etch(address(game), address(new RingSingleStepFixture()).code);
        opened = RingSingleStepFixture(payable(address(game))).runAfkOnce();
        vm.etch(address(game), productionCode);
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        // Reach a real commitment with the normal keeper, then use guarded
        // production worker checkpoints to stop immediately before AFK opens.
        for (uint256 i; i < 128 && !game.rngLocked(); ++i) game.mineFlip();
        require(game.rngLocked(), "fixture: new daily request");
        _fulfillPending(vrfWord);
        bytes memory productionCode = address(game).code;
        bytes memory checkpointCode = address(new RingSingleStepFixture()).code;
        for (uint256 i; i < 256; ++i) {
            if (uint8(game.nextMinerAction()) == 9) return;
            vm.etch(address(game), checkpointCode);
            RingSingleStepFixture(payable(address(game))).stepBeforeAfk();
            vm.etch(address(game), productionCode);
        }
        revert(string.concat("fixture: AFK checkpoint not reached, action=", vm.toString(uint8(game.nextMinerAction()))));
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (_daySealed()) break;
            _fulfillPending(vrfWord);
            if (_daySealed()) break;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (_daySealed()) return;
            _fulfillPending(vrfWord);
            if (_daySealed()) return;
            game.mineFlip();
            _fulfillPending(vrfWord);
        }
    }

    /// @dev A false advance hint can mean the read cohort must drain first.
    function _daySealed() internal view returns (bool) {
        uint24 sealedDay = uint24(uint256(vm.load(address(game), bytes32(uint256(0)))) >> 24);
        return game.currentDayView() == sealedDay && !game.advanceDue() && !game.rngLocked();
    }

    function _fulfillPending(uint256 vrfWord) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
            if (!fulfilled) {
                mockVRF.fulfillRandomWords(reqId, vrfWord);
                _lastFulfilledReqId = reqId;
            }
        }
    }

    function _subscribeLootbox(address who, uint8 q) internal {
        vm.prank(who);
        game.subscribe(address(0), false, false, q, address(0)); // self, lootbox mode, no reinvest
    }

    function _fundPool(address who, uint256 amount) internal {
        vm.deal(address(this), amount);
        game.depositAfkingFunding{value: amount}(who);
    }

    function _grantDeityPass(address who) internal {
        bytes32 slot = keccak256(abi.encode(who, uint256(MINTPACKED_SLOT)));
        uint256 packed = uint256(vm.load(address(game), slot));
        packed |= (uint256(1) << DEITY_SHIFT);
        vm.store(address(game), slot, bytes32(packed));
    }

    // =========================================================================
    // Storage reads / pokes — the subscriber set + the open cursor + the Sub markers
    // =========================================================================

    /// @dev `_subscribers.length` (the dynamic-array length lives directly in its slot).
    function _subscribersLength() internal view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(SUBSCRIBERS_SLOT))));
    }

    /// @dev Read the current `_subOpenCursor` (byte 2..3 of the packed CURSOR_SLOT).
    function _openCursor() internal view returns (uint16) {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        return uint16(packed >> (OPEN_CURSOR_BYTE * 8));
    }

    /// @dev Poke `_subOpenCursor` to `idx` (the wedged mid-array index), preserving the other packed fields.
    function _setOpenCursor(uint16 idx) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(CURSOR_SLOT))));
        packed &= ~(uint256(0xFFFF) << (OPEN_CURSOR_BYTE * 8));
        packed |= uint256(idx) << (OPEN_CURSOR_BYTE * 8);
        vm.store(address(game), bytes32(uint256(CURSOR_SLOT)), bytes32(packed));
    }

    function _subField(address who, uint256 off, uint256 widthBits) internal view returns (uint256) {
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(uint256(game.walletIdOf(who)), GameSlots.SUB_OF)))) >> 224; // Sub.setPosition (1-based)
    }

    /// @dev Openable under the entry-gate: pending box (lastOpenedDay < lastAutoBoughtDay) AND the frozen
    ///      stamp-day word has landed (_recordedDailyWord(lastAutoBoughtDay) != 0). Mirrors the _runAfkingWork predicate.
    function _isOpenable(address who) internal view returns (bool) {
        uint32 bought = _lastBoughtDayOf(who);
        if (_lastOpenedDayOf(who) >= bought) return false;
        return game.rngWordForDay(uint24(bought)) != 0;
    }

    /// @dev Non-pending: no pending box (lastOpenedDay >= lastAutoBoughtDay) — a suffix-only scan landing
    ///      here finds no work.
    function _isNonPending(address who) internal view returns (bool) {
        return _lastOpenedDayOf(who) >= _lastBoughtDayOf(who);
    }
}
