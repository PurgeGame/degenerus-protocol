// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AutoOpenCursorRing -- the afking-box open leg drains EVERY openable box regardless of where
///        `_subOpenCursor` sits in `_subscribers`, not just the suffix `[cursor, len)`.
///
/// @notice The open leg (`GameAfkingModule._autoOpen`, reached via Game.openBoxes -> delegatecall
///   drainAfkingBoxes, and via Game.mintFlip's open category) walks `_subscribers` from `_subOpenCursor`,
///   opening up to `maxCount` materializable boxes. A box is OPENABLE when, under the entry-gate (not
///   rngLocked, not the terminal-liveness control), the sub has a pending box (`lastOpenedDay <
///   lastAutoBoughtDay`) AND its frozen stamp-day word has landed (`rngWordByDay[lastAutoBoughtDay] != 0`).
///
/// @notice The wedge these tests reproduce: the cursor can come to rest at a mid-array index `< len`
///   whose sub is non-pending — e.g. a `subscribe` pushes a fresh (un-stamped, so non-openable) player to
///   the tail while the cursor sits at the prior length, or any non-pending sub sits at/after the cursor.
///   A suffix-only scan starting there would visit only `[cursor, len)`, find no openable box, return 0,
///   and (through mintFlip) revert NoWork() — stranding the still-openable boxes in `[0, cursor)`, never
///   re-reaching them. The full-ring scan visits up to `len` subs from the cursor, wrapping mid-scan, so a
///   0-open result means the WHOLE set is drained, never just the suffix. Per-call opens stay bounded by
///   `maxCount` (OPEN_BATCH = 80).
///
/// @dev Reuses the V56SecUnmanipulable / V56SubHardening afking-box drive VERBATIM (the deity-pass +
///   funded-sub + new-day STAGE harness, the fulfill-first settle loop, the accumulating-`t` warp, the
///   post-PACK Sub-slot offset block). Adds the `_subscribers`-array reads (slot 56) and the packed
///   cursor-slot read/poke (slot 58: `_subCursor` u16 at byte 0, `_subOpenCursor` u16 at byte 2). The open path
///   is driven through the production Game.openBoxes(maxCount) valve (delegatecalls drainAfkingBoxes ->
///   _autoOpen) and through Game.mintFlip() as a keeper. Test-only: ZERO contracts/*.sol mutation.
contract AutoOpenCursorRing is DeployProtocol {
    // -------------------------------------------------------------------------
    // Game-resident storage slots + the post-PACK Sub-slot offset block
    // (forge inspect DegenerusGame storage: _subOf@54, _subscribers@56, _subscriberIndex@57, cursors@58)
    // -------------------------------------------------------------------------
    uint256 private constant SUBOF_SLOT = 53;            // _subOf mapping root (address => Sub, one packed slot)
    uint256 private constant SUBSCRIBERS_SLOT = 55;      // address[] _subscribers (length @ slot; elements @ keccak256(slot)+i)
    uint256 private constant SUBSCRIBER_INDEX_SLOT = 56; // mapping(address => uint256) _subscriberIndex (1-indexed)
    uint256 private constant CURSOR_SLOT = 57;           // packed: _subCursor u16 @byte0 · _subOpenCursor u16 @byte2 · _afkingResetDay u24 @byte4
    uint256 private constant OPEN_CURSOR_BYTE = 2;       // byte offset of _subOpenCursor within CURSOR_SLOT
    uint256 private constant MINTPACKED_SLOT = 9;        // mintPacked_ mapping root (deity bit @ 184)

    //   dailyQuantity u8 @0 · validThroughLevel u24 @1 · reinvestPct u8 @4 · flags u8 @5
    //   scorePlus1 u16 @6 · amount u24 @8
    //   lastAutoBoughtDay u24 @11 · lastOpenedDay u24 @14 · afkCoveredThroughDay u24 @17 · afkingStartDay u24 @20
    //   affiliateBase u32 @23 · pendingFlip u24 @27 · subStreakLatch u16 @30
    uint256 private constant OFF_LASTBOUGHT = 10;     // uint24 lastAutoBoughtDay (bytes 11..13)
    uint256 private constant OFF_LASTOPENED = 13;     // uint24 lastOpenedDay     (bytes 14..16)

    uint256 private constant DEITY_SHIFT = 184;

    uint256 private constant OPEN_BATCH = 80; // GameAfkingModule.OPEN_BATCH (per-call open cap)

    uint256 private constant DRAIN_MAX_ITERATIONS = 60;
    uint256 private _lastFulfilledReqId;
    uint256 private _t; // explicit accumulating timestamp (the Foundry block.timestamp caching workaround)

    function setUp() public {
        _deployProtocol();
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
        // landed rngWordByDay[lastAutoBoughtDay] — exactly the openable predicate.
        address[] memory subs = _stampSealedOpenableSubs(5);

        // The "wedge" sub: a fresh, NOT-yet-stamped subscriber pushed to the tail of `_subscribers` AFTER
        // the openable subs. A just-created sub has no pending box (lastOpenedDay == lastAutoBoughtDay == 0
        // pre-buy), so it is non-pending — landing the cursor on it makes a suffix-only scan find no work.
        address wedge = _freshUnstampedSub("ring_wedge");
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

        // Drive the production open valve. The full-ring scan wraps from the wedge index past len back to 0,
        // reaching the stranded openable boxes.
        uint256 opened = _openViaValve(OPEN_BATCH);
        assertGt(opened, 0, "ring: the open leg did NOT return 0 with openable boxes still present");

        // Every stranded box was opened — its lastOpenedDay caught up to lastAutoBoughtDay.
        for (uint256 i; i < subs.length; i++) {
            assertEq(_lastOpenedDayOf(subs[i]), _lastBoughtDayOf(subs[i]), "ring: the stranded [0,cursor) box was opened (marker advanced)");
            assertFalse(_isOpenable(subs[i]), "ring: no openable box left behind for the stranded sub");
        }
    }

    /// @notice The same wedge driven through the keeper path (Game.mintFlip's open category) opens the
    ///         stranded boxes too — mintFlip pays the open bounty rather than reverting NoWork while
    ///         openable boxes exist below the cursor.
    function test_StrandedSubsDrainViaMintFlipKeeper() public {
        address[] memory subs = _stampSealedOpenableSubs(4);
        address wedge = _freshUnstampedSub("mf_wedge");
        uint256 wedgeIdx = _subscriberIndexOf(wedge) - 1;
        _setOpenCursor(uint16(wedgeIdx));
        assertTrue(_isNonPending(wedge), "fixture: cursor sub non-pending");
        for (uint256 i; i < subs.length; i++) {
            assertTrue(_subscriberIndexOf(subs[i]) - 1 < wedgeIdx, "fails-without: openable box strictly < cursor");
            assertTrue(_isOpenable(subs[i]), "fixture: sub below cursor openable");
        }

        // A keeper cranks mintFlip while no advance is due (settled clean) -> the open category runs. With
        // openable boxes below the wedged cursor, the full-ring scan finds them, so mintFlip does NOT revert.
        address keeper = makeAddr("mf_keeper");
        _grantDeityPass(keeper); // eligible so the open-bounty creditFlip path is exercised end-to-end
        require(!game.advanceDue() && !game.rngLocked(), "fixture: settled clean so mintFlip runs the OPEN leg");
        vm.prank(keeper);
        game.mintFlip(); // MUST NOT revert NoWork — the open category had work below the cursor

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
        address wedge = _freshUnstampedSub("nw_wedge");
        uint256 wedgeIdx = _subscriberIndexOf(wedge) - 1;
        _setOpenCursor(uint16(wedgeIdx));
        assertTrue(_isNonPending(wedge), "fixture: cursor sub non-pending");
        for (uint256 i; i < subs.length; i++) {
            assertTrue(_subscriberIndexOf(subs[i]) - 1 < wedgeIdx, "fails-without: openable box strictly < cursor");
        }

        // While openable boxes exist below the cursor, mintFlip's open leg has work -> NO NoWork revert.
        address keeper = makeAddr("nw_keeper");
        _grantDeityPass(keeper);
        require(!game.advanceDue() && !game.rngLocked(), "fixture: settled clean so the open leg is the only category");
        vm.prank(keeper);
        game.mintFlip(); // MUST NOT revert NoWork — there IS open work

        // Every afking box is now opened: the whole afking ring is drained (the ring scan reached the
        // stranded [0, cursor) subs, not just the suffix).
        for (uint256 i; i < subs.length; i++) {
            assertFalse(_isOpenable(subs[i]), "drain: no openable afking box remains after the ring scan");
        }
        // Fully drain the liveness valve (afking + the incidental human boxes the STAGE buys created), then
        // a final clean valve call returns 0 — the open path cleanly no-ops once every box is opened.
        _drainValveToZero();
        assertEq(_openViaValve(OPEN_BATCH), 0, "drained: a follow-up open valve returns 0 (whole set drained)");

        // NOW (and only now) mintFlip cleanly signals no work: with no advance due and the afking ring
        // fully drained, both router categories are empty -> the clean NoWork no-op (not a suffix-strand
        // false-positive while [0, cursor) boxes remained).
        require(!game.advanceDue() && !game.rngLocked(), "fixture: still clean -> NoWork is the genuine drained signal");
        vm.prank(keeper);
        vm.expectRevert(abi.encodeWithSignature("NoWork()"));
        game.mintFlip();
    }

    // =========================================================================
    // Real-path wedge — a subscribe grows the set while the cursor sits at the old length
    // =========================================================================

    /// @notice The wedge arises on the REAL path with NO cursor poke: drive an open pass so `_subOpenCursor`
    ///         advances to the set length, then `subscribe` a fresh player. The push leaves the cursor at the
    ///         prior length — now a mid-array index (< the grown len) pointing at the just-pushed non-pending
    ///         sub, exactly the live-observed strand shape. A subsequent open pass over the OTHER, still-
    ///         openable subs (stamped after, at indices below the parked cursor) must STILL drain them.
    function test_RealPathSubscribeGrowsSetThenDrains() public {
        // Stamp two openable subs, then open + settle so the open cursor walks to the set length and parks.
        address[] memory first = _stampSealedOpenableSubs(2);
        // Open everything currently pending so the cursor advances to len and the existing boxes clear.
        _openViaValve(OPEN_BATCH);
        for (uint256 i; i < first.length; i++) {
            assertFalse(_isOpenable(first[i]), "fixture: the first wave's boxes opened (cursor walked the set)");
        }
        uint16 cursorAtLen = _openCursor();
        uint256 lenBeforeGrow = _subscribersLength();

        // A fresh subscribe GROWS the set; the cursor stays where it parked (no reset on push). If it parked
        // at the prior length it is now a mid-array index pointing at the just-pushed non-pending sub.
        address grower = _freshUnstampedSub("realpath_grow");
        assertGt(_subscribersLength(), lenBeforeGrow, "real path: the subscribe grew _subscribers (push, no cursor reset)");

        // Now stamp a NEW openable box on one of the original subs (a real new-day buy, NO open) so there is
        // genuine openable work the parked cursor must reach via the ring wrap. Its index is below the cursor.
        address stranded = first[0];
        _stampSealedBoxOn(stranded);
        assertTrue(_isOpenable(stranded), "fixture: a fresh openable box exists below the parked cursor");
        // The cursor is mid-array (it parked at/near the pre-grow length) and the stranded sub is below it.
        assertTrue(_subscriberIndexOf(stranded) - 1 < _subscribersLength(), "non-vacuity: stranded sub in-set");
        // Document the wedge geometry the real path produced.
        emit log_named_uint("parked open cursor", cursorAtLen);
        emit log_named_uint("grown set length", _subscribersLength());
        emit log_named_uint("grower index (cursor sub)", _subscriberIndexOf(grower) - 1);

        // The ring scan drains the stranded openable box no matter where the cursor parked.
        uint256 opened = _openViaValve(OPEN_BATCH);
        assertGt(opened, 0, "real path: the ring scan opened the stranded box (no suffix-only strand)");
        assertEq(_lastOpenedDayOf(stranded), _lastBoughtDayOf(stranded), "real path: the stranded box opened (marker advanced)");
    }

    // =========================================================================
    // Box-drive helpers
    // =========================================================================

    uint256 private _deliverNonce;

    /// @dev Create `n` deity-passed, funded subs and stamp ONE sealed openable box on each: a new-day STAGE
    ///      buy that stamps the box + lands its stamp-day word, with NO subsequent open. Each sub ends up
    ///      with lastOpenedDay < lastAutoBoughtDay and rngWordByDay[lastAutoBoughtDay] != 0 (openable).
    function _stampSealedOpenableSubs(uint256 n) internal returns (address[] memory subs) {
        subs = new address[](n);
        for (uint256 i; i < n; i++) {
            address p = makeAddr(string(abi.encodePacked("ring_sub_", vm.toString(i))));
            _grantDeityPass(p);     // clears the pass gate
            _fundPool(p, 80 ether); // grounds the NEW-run cover-buy
            _subscribeLootbox(p, 1);
            subs[i] = p;
        }
        // ONE new-day STAGE buy stamps a pending box on every in-set sub + lands the stamp-day word; NO open.
        _runStageNewDay(uint256(keccak256(abi.encode("ring_stamp", _deliverNonce++))) | 1);
        _settleClean(uint256(keccak256(abi.encode("ring_stampc", _deliverNonce++))) | 1);
        for (uint256 i; i < n; i++) {
            require(_isOpenable(subs[i]), "fixture: each sub carries a sealed openable box (pending + landed word)");
        }
    }

    /// @dev Stamp a fresh sealed openable box on an existing in-set sub via a real new-day STAGE buy (no open).
    function _stampSealedBoxOn(address p) internal {
        _runStageNewDay(uint256(keccak256(abi.encode("ring_restamp", _deliverNonce++))) | 1);
        _settleClean(uint256(keccak256(abi.encode("ring_restampc", _deliverNonce++))) | 1);
        require(_isOpenable(p), "fixture: a fresh sealed openable box was stamped");
    }

    /// @dev Create a fresh subscriber (deity-passed + funded so the subscribe succeeds) WITHOUT delivering /
    ///      opening it — it joins `_subscribers` at the tail with no pending box (non-openable).
    function _freshUnstampedSub(string memory tag) internal returns (address p) {
        p = makeAddr(tag);
        _grantDeityPass(p);
        _fundPool(p, 80 ether);
        _subscribeLootbox(p, 1);
        require(_subscriberIndexOf(p) > 0, "fixture: the fresh sub joined the set");
    }

    /// @dev Drive the production open valve: Game.openBoxes delegatecalls drainAfkingBoxes -> _autoOpen.
    ///      Returns the boxes opened (afking + human; here only the afking ring boxes are pending).
    function _openViaValve(uint256 maxCount) internal returns (uint256 opened) {
        vm.prank(makeAddr("ring_opener"));
        opened = game.openBoxes(maxCount);
    }

    /// @dev Drain the liveness valve (afking + human boxes) to empty so a follow-up call returns 0.
    function _drainValveToZero() internal {
        for (uint256 i; i < 64; i++) {
            if (_openViaValve(OPEN_BATCH) == 0) return;
        }
    }

    /// @dev Drive the per-sub buy STAGE for a NEW day (the accumulating-timestamp warp).
    function _runStageNewDay(uint256 vrfWord) internal {
        _settleGame(vrfWord ^ 0xF00D);
        _t += 1 days;
        vm.warp(_t);
        _settleGame(vrfWord);
    }

    function _settleGame(uint256 vrfWord) internal {
        for (uint256 d; d < DRAIN_MAX_ITERATIONS; d++) {
            if (!game.advanceDue() && !game.rngLocked()) break;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) break;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
    }

    function _settleClean(uint256 vrfWord) internal {
        for (uint256 d; d < 240; d++) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfillPending(vrfWord);
            if (!game.advanceDue() && !game.rngLocked()) return;
            game.advanceGame();
            _fulfillPending(vrfWord);
        }
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
        uint256 p = uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBOF_SLOT))))) >> (off * 8);
        return p & ((uint256(1) << widthBits) - 1);
    }

    function _lastBoughtDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTBOUGHT, 24));
    }

    function _lastOpenedDayOf(address who) internal view returns (uint32) {
        return uint32(_subField(who, OFF_LASTOPENED, 24));
    }

    function _subscriberIndexOf(address who) internal view returns (uint256) {
        return uint256(vm.load(address(game), keccak256(abi.encode(who, uint256(SUBSCRIBER_INDEX_SLOT)))));
    }

    /// @dev Openable under the entry-gate: pending box (lastOpenedDay < lastAutoBoughtDay) AND the frozen
    ///      stamp-day word has landed (rngWordByDay[lastAutoBoughtDay] != 0). Mirrors the _autoOpen predicate.
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
