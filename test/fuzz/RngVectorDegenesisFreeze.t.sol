// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisHarness} from "./helpers/DegenesisHarness.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title RngVectorDegenesisFreeze -- Degenesis outcomes bind to their word, and nothing a player
///        does after the request changes them
/// @notice Vector 1 (RNG / freeze) on the Degenesis timeline (deploy on day index 1). Each test
///         drives the real engine with mock VRF and checks, at the DegenesisOrderResolved level,
///         that a cohort's orders resolve exactly as the reference computed from the inputs fixed
///         at its request: the stored lanes, frozen V and Q, and the word recorded for the bound
///         day. Covered: activity inside the request window (Degenesis buys, ordinary boxes, smurf
///         buys, AFKing subscribe, nudges, miner calls), the request on the last sale day and on
///         the main-launch day, a VRF stall with an admin retry, a gap-day request, a gap
///         backfill that overwrites the bound day's ring slot during a backlog, the pricing
///         being atomic with its request on every day of the week, and a mid-day word never
///         binding a cohort.
contract RngVectorDegenesisFreeze is DegenesisHarness {
    bytes32 internal constant SIG_DAILY_APPLIED = keccak256("DailyRngApplied(uint24,uint256,uint256,uint256)");
    bytes4 internal constant ERR_RNG_LOCKED = bytes4(keccak256("RngLocked()"));

    address[5] internal buyers;

    function setUp() public override {
        super.setUp();
        _drive(0);
        for (uint256 i; i < 5; ++i) {
            buyers[i] = _player(string.concat("rv-", vm.toString(i)));
            _earnCredit(buyers[i], 60 ether);
        }
        _driveDay(2, 0);
    }

    // =====================================================================
    // Helpers
    // =====================================================================

    /// @dev `n` orders on day index `d` from the five buyers, spread over the day.
    function _placeOrdersOn(uint24 d, uint256 n, uint256 stepSecs) internal {
        for (uint256 i; i < n; ++i) {
            vm.warp(_dayStart(d) + 2 hours + i * stepSecs);
            _buy(buyers[i % 5], 0.01 ether + (i % 7) * 0.0013 ether + (i % 3) * 0.21 ether);
        }
    }

    /// @dev Step to the day's request and make it, leaving it unanswered. Returns the request id.
    function _requestUnanswered() internal returns (uint256 req) {
        _stepToRequest();
        game.mineFlip(0);
        req = mockVRF.lastRequestId();
        lastFulfilledReq = req;
        (,, bool done) = mockVRF.pendingRequests(req);
        assertFalse(done, "request left unanswered");
    }

    /// @dev Answer the latest request with `w`, even if the harness marked it as seen.
    function _answer(uint256 w) internal {
        lastFulfilledReq = 0;
        assertTrue(_fulfillPending(w), "answer: no open request");
    }

    function _rngRequestDay() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(GameSlots.RNG_REQUEST_DAY))));
    }

    /// @dev Every input a priced cohort's resolution reads, hashed: the active word (Q, bound day,
    ///      cursor, paid), the cohort header (V, count), every order slot, the copied word and
    ///      the sDGNRS inventory the awards draw from.
    function _frozenDigest(uint256 c) internal view returns (bytes32 h) {
        h = keccak256(abi.encode(_active(), _header(c), _word(), _degPool()));
        uint256 slots = (_count(c) + 2) / 3;
        for (uint256 s; s < slots; ++s) h = keccak256(abi.encode(h, _orderSlot(c, s * 3)));
    }

    /// @dev Resolved orders of cohort `c` only.
    function _resolvedOf(Vm.Log[] memory logs, uint256 c) internal view returns (Res[] memory out) {
        Res[] memory all = _resolved(logs);
        uint256 n;
        for (uint256 i; i < all.length; ++i) if (all[i].day == c) ++n;
        out = new Res[](n);
        n = 0;
        for (uint256 i; i < all.length; ++i) if (all[i].day == c) out[n++] = all[i];
    }

    /// @dev The finalized word the engine recorded for `day` in these logs (0 if none).
    function _appliedWord(Vm.Log[] memory logs, uint24 day) internal view returns (uint256 w) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length == 0 || logs[i].topics[0] != SIG_DAILY_APPLIED) {
                continue;
            }
            (uint24 d,,, uint256 fin) = abi.decode(logs[i].data, (uint24, uint256, uint256, uint256));
            if (d == day) w = fin;
        }
    }

    /// @dev Cohort and bound day of every DegenesisCohortPriced in `logs`, as a bitmap of cohorts
    ///      and the last bound day.
    function _pricedIn(Vm.Log[] memory logs) internal view returns (uint256 cohorts, uint24 bound) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_PRICED) continue;
            cohorts |= uint256(1) << uint256(logs[i].topics[1]);
            (,, bound) = abi.decode(logs[i].data, (uint256, uint256, uint24));
        }
    }

    /// @dev Degenesis days of every DegenesisBuy in `logs`, as a bitmap.
    function _buyDays(Vm.Log[] memory logs) internal view returns (uint256 days_) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game) || logs[i].topics.length < 2 || logs[i].topics[0] != SIG_BUY) continue;
            (uint8 c,,,) = abi.decode(logs[i].data, (uint8, uint32, uint256, uint256));
            days_ |= uint256(1) << c;
        }
    }

    function _assertSame(Res[] memory x, Res[] memory y, string memory tag) internal pure {
        assertEq(x.length, y.length, string.concat(tag, ": count"));
        for (uint256 i; i < x.length; ++i) _assertRes(x[i], y[i], string.concat(tag, " order ", vm.toString(i)));
    }

    function _assertMatchesRef(Res[] memory got, uint256 c, uint256 word, uint256 q, string memory tag) internal view {
        Res[] memory want = _refCohort(c, word, q);
        _assertSame(got, want, tag);
    }

    /// @dev Count orders whose reference outcome differs between two words: a test that a word
    ///      choice matters (the comparison is not vacuous).
    function _differing(uint256 c, uint256 w1, uint256 w2, uint256 q) internal view returns (uint256 n) {
        Res[] memory a = _refCohort(c, w1, q);
        Res[] memory b = _refCohort(c, w2, q);
        for (uint256 i; i < a.length; ++i) {
            if (a[i].flip != b[i].flip || a[i].dgnrs != b[i].dgnrs || a[i].wwxrp != b[i].wwxrp
                || a[i].normalPasses != b[i].normalPasses || a[i].highPasses != b[i].highPasses) ++n;
        }
    }

    // =====================================================================
    // 1. Activity inside the request window
    // =====================================================================

    /// @notice Cohort 1 is priced and bound at the day-3 request. While that request is out the
    ///         players buy Degenesis boxes (they join cohort 2), buy ordinary boxes, buy for a
    ///         smurf and a Degenesis box for it, try to subscribe to AFKing and to nudge the word
    ///         (both refused while the window is open) and call the miner; after the word lands, more buys and miner calls from
    ///         other callers interleave with settlement. Every frozen input is byte-identical
    ///         until the word arrives, and every cohort-1 order resolves exactly as in the
    ///         undisturbed run and as the reference.
    function test_RequestWindowActivityChangesNoOutcome() public {
        // A smurf owned by buyer 0, with credit of its own, set up before the request.
        address main = buyers[0];
        _grantSmurfBase(main, 1);
        uint256 price = game.mintPrice();
        vm.prank(main);
        uint32 smurf = game.createSmurf{value: price}(bytes32(0), MintPaymentKind.DirectEth);
        vm.prank(main);
        game.purchase{value: 4 ether}(smurf, 0, BoxOrderLib.boCustom(4 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        // A seat for the AFKing subscribe inside the window.
        uint256 seat = _grantSeat(buyers[1]);

        _placeOrdersOn(2, 45, 6 minutes);
        vm.prank(main);
        game.buyDegenesisBox{value: 0.05 ether}(smurf, 0.05 ether);
        uint256 n1 = _count(1);
        uint256 q = _refQ(1, _degPool());

        _warpTo(3, 1 hours);
        _requestUnanswered();
        assertEq(_activeDay(), 3, "cohort 1 bound to the day-3 request");
        assertEq(_rngRequestDay(), 3, "the request is the day-3 request");
        assertEq(game.rngWordForDay(3), 0, "the bound day's word is not yet known");
        assertTrue(game.rngLocked(), "daily window open");
        bytes32 digest0 = _frozenDigest(1);
        uint256 word = uint256(keccak256("rv-window-word"));

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _answer(word);
        _drive(word);
        Res[] memory plain = _resolvedOf(vm.getRecordedLogs(), 1);
        vm.revertToStateAndDelete(snap);

        // ---- the disturbed run ----
        vm.recordLogs();
        for (uint256 i; i < 10; ++i) {
            vm.warp(block.timestamp + 7 minutes);
            _buy(buyers[i % 5], 0.0123 ether + i * 0.0101 ether);
            if (i % 3 == 0) _earnCredit(buyers[(i + 2) % 5], 0.05 ether);
        }
        vm.prank(main);
        game.purchase{value: 1 ether}(smurf, 0, BoxOrderLib.boCustom(1 ether), bytes32(0), MintPaymentKind.DirectEth, false);
        vm.prank(main);
        game.buyDegenesisBox{value: 0.03 ether}(smurf, 0.03 ether);
        // Subscribing is refused while the daily window is open.
        vm.prank(buyers[1]);
        vm.expectRevert(ERR_RNG_LOCKED);
        game.subscribe{value: 1 ether}(0, false, false, 1, 0, seat);
        (, uint256 nudgeCost) = game.rngNudgeQuote();
        vm.prank(buyers[2]);
        vm.expectRevert(ERR_RNG_LOCKED);
        game.reverseFlip(nudgeCost);
        for (uint256 i; i < 3; ++i) {
            vm.prank(makeAddr(string.concat("rv-miner-", vm.toString(i))));
            try game.mineFlip{gas: 3_000_000}(0) {} catch {}
        }
        Vm.Log[] memory windowLogs = vm.getRecordedLogs();
        assertEq(_buyDays(windowLogs), 1 << 2, "every window order joined cohort 2");
        assertEq(_count(1), n1, "cohort 1 took no order");
        assertGt(_count(2), 10, "cohort 2 took the window orders");
        assertEq(_frozenDigest(1), digest0, "cohort 1's inputs unchanged through the window");

        vm.recordLogs();
        _answer(word);
        for (uint256 i; i < 2000 && _closed() == 0; ++i) {
            if (i % 2 == 0) _buy(buyers[i % 5], 0.0111 ether);
            if (i % 5 == 1) _earnCredit(buyers[(i + 1) % 5], 0.02 ether);
            vm.prank(makeAddr(string.concat("rv-settler-", vm.toString(i))));
            try game.mineFlip{gas: 2_000_000}(0) {} catch {
                if (!_mineStep(5_000_000)) break;
            }
        }
        _drive(word);
        Res[] memory mixed = _resolvedOf(vm.getRecordedLogs(), 1);

        assertEq(plain.length, n1, "every cohort-1 order resolved once");
        _assertSame(plain, mixed, "window activity");
        _assertMatchesRef(plain, 1, word, q, "reference");
        assertGt(_differing(1, word, word ^ 1, q), n1 / 4, "the word decides the outcomes");
    }

    // =====================================================================
    // 2. The last sale day and the main-launch day
    // =====================================================================

    /// @notice The day-8 request (Degenesis day 7 open) prices cohort 6; orders placed while it
    ///         is out join cohort 7. The day-9 request (main launch) prices cohort 7, and no
    ///         order can be placed while it is out or before it. Both cohorts resolve exactly as
    ///         the reference from their own bound day's word, and the closing burn follows.
    function test_LastSaleDayAndLaunchDayRequests() public {
        _warpTo(2, 2 hours);
        _buy(buyers[0], 0.02 ether);
        for (uint24 d = 3; d <= 7; ++d) {
            _driveDay(d, 0);
            _warpTo(d, 2 hours);
            _buy(buyers[d % 5], 0.02 ether * uint256(d));
        }
        assertEq(_closed(), 5, "cohorts 1-5 closed by day 7's settlement");
        _placeOrdersOn(7, 12, 9 minutes); // cohort 6
        uint256 n6 = _count(6);

        // ---- day 8: price cohort 6, buy into cohort 7 while the request is out ----
        _warpTo(8, 1 hours);
        _buy(buyers[0], 0.0444 ether); // cohort 7 before the request
        vm.recordLogs();
        _requestUnanswered();
        (uint256 priced, uint24 bound) = _pricedIn(vm.getRecordedLogs());
        assertEq(priced, 1 << 6, "day 8 prices cohort 6");
        assertEq(bound, 8, "bound to day 8");
        uint256 q6 = _activeQ();
        bytes32 digest6 = _frozenDigest(6);
        vm.recordLogs();
        for (uint256 i; i < 6; ++i) _buy(buyers[i % 5], 0.015 ether + i * 0.0001 ether);
        assertEq(_buyDays(vm.getRecordedLogs()), 1 << 7, "window orders join cohort 7");
        assertEq(_count(6), n6, "cohort 6 took no order");
        assertEq(_frozenDigest(6), digest6, "cohort 6's inputs unchanged");
        uint256 w8 = uint256(keccak256("rv-day8"));
        vm.recordLogs();
        _answer(w8);
        _drive(w8);
        Vm.Log[] memory logs8 = vm.getRecordedLogs();
        assertEq(_appliedWord(logs8, 8), w8, "day 8 recorded the answered word");
        _assertMatchesRef(_resolvedOf(logs8, 6), 6, w8, q6, "cohort 6");
        assertEq(_closed(), 6, "cohort 6 closed");
        uint256 n7 = _count(7);
        assertEq(n7, 7, "cohort 7: one order before and six inside the day-8 window");

        // ---- day 9: the sale is over; the request prices cohort 7 ----
        _warpTo(9, 1 hours);
        vm.deal(buyers[0], 10 ether);
        vm.prank(buyers[0]);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        vm.recordLogs();
        _requestUnanswered();
        (priced, bound) = _pricedIn(vm.getRecordedLogs());
        assertEq(priced, 1 << 7, "day 9 prices cohort 7");
        assertEq(bound, GameTimeLib.MAIN_LAUNCH_DAY, "bound to the main-launch request");
        uint256 q7 = _activeQ();
        bytes32 digest7 = _frozenDigest(7);
        vm.prank(buyers[0]);
        vm.expectRevert();
        game.buyDegenesisBox{value: 0.01 ether}(0, 0.01 ether);
        _earnCredit(buyers[1], 0.05 ether); // ordinary activity inside the window
        assertEq(_frozenDigest(7), digest7, "cohort 7's inputs unchanged");
        uint256 w9 = uint256(keccak256("rv-day9"));
        vm.recordLogs();
        _answer(w9);
        _drive(w9);
        Vm.Log[] memory logs9 = vm.getRecordedLogs();
        _assertMatchesRef(_resolvedOf(logs9, 7), 7, w9, q7, "cohort 7");
        assertEq(_closed(), 7, "sale closed");
        assertEq(_countSig(logs9, SIG_BURNED), 1, "closing burn once");
        assertEq(_word(), 0, "copy cleared");
    }

    // =====================================================================
    // 3. VRF stall and admin retry
    // =====================================================================

    /// @notice The day-3 request stalls. Orders placed during the stall join cohort 2. After 20
    ///         hours the admin retry re-issues the request (keeping the day and the cohort): a
    ///         late answer to the orphaned request is ignored, the retried word is the one
    ///         copied, and cohort 1 resolves exactly as the reference from it.
    function test_StallThenRetry_BindsTheRetriedWord() public {
        _placeOrdersOn(2, 30, 7 minutes);
        uint256 q = _refQ(1, _degPool());
        _warpTo(3, 1 hours);
        uint256 orphan = _requestUnanswered();
        assertEq(_activeDay(), 3, "bound to day 3");
        bytes32 digest = _frozenDigest(1);

        vm.recordLogs();
        vm.warp(block.timestamp + 3 hours);
        _buy(buyers[0], 0.0321 ether);
        vm.warp(block.timestamp + 10 hours);
        _buy(buyers[1], 0.0432 ether);
        assertEq(_buyDays(vm.getRecordedLogs()), 1 << 2, "stall-window orders join cohort 2");

        vm.warp(_dayStart(3) + 1 hours + 20 hours + 10 minutes);
        assertEq(game.currentDayView(), 3, "still day 3");
        vm.prank(ContractAddresses.ADMIN);
        game.retryRng();
        uint256 retried = mockVRF.lastRequestId();
        assertGt(retried, orphan, "retry issued a fresh request");
        assertEq(_activeDay(), 3, "retry keeps the bound day");
        assertEq(_rngRequestDay(), 3, "retry keeps the request day");
        assertEq(_frozenDigest(1), digest, "retry changes no cohort input");

        // The orphaned request answers late: ignored.
        uint256 wOrphan = uint256(keccak256("rv-orphan"));
        mockVRF.fulfillRandomWords(orphan, wOrphan);
        assertEq(uint256(vm.load(address(game), bytes32(GameSlots.RNG_WORD_CURRENT))), 1, "orphan word refused");
        assertEq(_frozenDigest(1), digest, "orphan answer changes no cohort input");

        uint256 wRetry = uint256(keccak256("rv-retried"));
        vm.recordLogs();
        _answer(wRetry);
        _drive(wRetry);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(_appliedWord(logs, 3), wRetry, "day 3 recorded the retried word");
        _assertMatchesRef(_resolvedOf(logs, 1), 1, wRetry, q, "retried word");
        assertGt(_differing(1, wRetry, wOrphan, q), 5, "the orphan word would have resolved differently");
        assertEq(_closed(), 1, "cohort 1 closed");
    }

    // =====================================================================
    // 4. Gap days
    // =====================================================================

    /// @notice Nobody cranks on days 3 and 4; orders keep landing in cohorts 2 and 3. The day-5
    ///         request is a gap request: it splits cohorts 1-3 and prices cohort 1 bound to day
    ///         5. The gap backfill records a derived word for day 4; the copy takes day 5's own
    ///         word, and cohort 1 resolves from it, not from the derived one. Cohort 2 then binds
    ///         to the next request.
    function test_GapDayRequest_BindsTheRequestDaysWord() public {
        _placeOrdersOn(2, 24, 9 minutes);
        uint256 q = _refQ(1, _degPool());
        vm.recordLogs();
        _warpTo(3, 3 hours);
        _buy(buyers[2], 0.0555 ether);
        _warpTo(4, 3 hours);
        _buy(buyers[3], 0.0666 ether);
        assertEq(_buyDays(vm.getRecordedLogs()), (1 << 2) | (1 << 3), "uncranked days keep their own cohorts");
        assertEq(_count(2), 1, "cohort 2 = day index 3");
        assertEq(_count(3), 1, "cohort 3 = day index 4");

        uint256 w5 = uint256(keccak256("rv-gap-day5"));
        _warpTo(5, 1 hours);
        vm.recordLogs();
        _requestUnanswered();
        Vm.Log[] memory reqLogs = vm.getRecordedLogs();
        (uint256 priced, uint24 bound) = _pricedIn(reqLogs);
        assertEq(priced, 1 << 1, "the gap request prices cohort 1 only");
        assertEq(bound, 5, "bound to the gap request's own day");
        assertEq(_countSig(reqLogs, SIG_SPLIT), 3, "cohorts 1-3 split together");
        vm.recordLogs();
        _answer(w5);
        _drive(w5);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 gapWord = uint256(keccak256(abi.encodePacked(w5, uint24(4))));
        assertEq(game.rngWordForDay(4), gapWord, "day 4 carries the derived gap word");
        assertEq(_appliedWord(logs, 5), w5, "day 5 recorded its own word");
        _assertMatchesRef(_resolvedOf(logs, 1), 1, w5, q, "gap request");
        assertGt(_differing(1, w5, gapWord, q), 5, "the derived gap word would have resolved differently");
        assertEq(_closed(), 1, "cohort 1 closed");

        _warpTo(6, 1 hours);
        vm.recordLogs();
        _drive(0);
        (priced, bound) = _pricedIn(vm.getRecordedLogs());
        assertEq(priced, 1 << 2, "cohort 2 priced next");
        assertEq(bound, 6, "bound to the day-6 request");
    }

    /// @notice Cohort 1 binds to day 3 with a long backlog. Days 4 and 5 go uncranked, so the
    ///         day-6 request backfills day 5, whose ring slot is day 3's: the ring no longer
    ///         serves day 3 while cohort 1 is still settling. The copy holds day 3's word and the
    ///         whole cohort resolves from it.
    function test_GapBackfillOverwritesBoundSlotDuringBacklog() public {
        _placeOrdersOn(2, 420, 20);
        uint256 n = _count(1);
        uint256 q = _refQ(1, _degPool());
        uint256 w3 = uint256(keccak256("rv-backlog-day3"));
        vm.recordLogs();
        _warpTo(3, 1 hours);
        _requestOnly(w3);
        _driveToSettle();
        assertEq(_word(), w3, "copy written at recording");
        game.mineFlip(0);
        assertLt(_activeCursor(), n, "backlog after one chunk");

        _warpTo(6, 1 hours);
        _stepToRequest();
        game.mineFlip(0);
        _fulfillPending(0);
        _driveToSettle();
        uint256 tags = uint256(vm.load(address(game), bytes32(GameSlots.RNG_DAY_TAGS)));
        assertEq(uint24(tags >> 24), 5, "day 3's ring slot now holds the backfilled day 5");
        assertEq(game.rngWordForDay(3), 0, "the ring no longer serves day 3");
        assertEq(_activeDay(), 3, "still bound to day 3");
        assertEq(_word(), w3, "copy retained across the gap backfill");
        assertLt(_activeCursor(), n, "still settling");
        _drive(0);
        Res[] memory got = _resolvedOf(vm.getRecordedLogs(), 1);
        assertEq(_closed(), 1, "cohort 1 closed");
        _assertMatchesRef(got, 1, w3, q, "backlog across the gap");
    }

    // =====================================================================
    // 5. Pricing is atomic with its request, all week
    // =====================================================================

    /// @notice On every request of the week (days 3..9) the cohort is split, priced and bound in
    ///         the very call that sends the VRF request, to that request's day, while that day's
    ///         word is still unknown; nothing prices a cohort outside a request.
    function test_EveryPricingRidesItsOwnRequest() public {
        uint256 pricedAll;
        _warpTo(2, 2 hours);
        _buy(buyers[2], 0.0114 ether);
        for (uint24 d = 3; d <= 9; ++d) {
            _warpTo(d, 1 hours);
            if (d <= 8) _buy(buyers[d % 5], 0.01 ether + uint256(d) * 0.0007 ether);
            vm.recordLogs();
            _stepToRequest();
            (uint256 before_,) = _pricedIn(vm.getRecordedLogs());
            assertEq(before_, 0, "no pricing ahead of the request call");
            uint256 req0 = mockVRF.lastRequestId();
            vm.recordLogs();
            game.mineFlip(0);
            (uint256 cohorts, uint24 bound) = _pricedIn(vm.getRecordedLogs());
            assertEq(mockVRF.lastRequestId(), req0 + 1, "the call sent the request");
            assertEq(_rngRequestDay(), d, "request day");
            assertEq(cohorts, uint256(1) << (d - 2), "the previous day's cohort priced");
            assertEq(bound, d, "bound to this request");
            assertEq(_activeDay(), d, "active binding");
            assertEq(game.rngWordForDay(d), 0, "bound word unknown at pricing");
            assertEq(_word(), 0, "no copy before the word");
            pricedAll |= cohorts;
            lastFulfilledReq = 0;
            vm.recordLogs();
            _drive(0);
            (uint256 after_,) = _pricedIn(vm.getRecordedLogs());
            assertEq(after_, 0, "nothing priced after the request");
        }
        assertEq(pricedAll, 0xFE, "cohorts 1-7 each priced at its own request");
        assertEq(_closed(), 7, "all closed");
    }

    // =====================================================================
    // 6. A mid-day word never binds a cohort
    // =====================================================================

    /// @notice On Degenesis day 1 with cohort-1 orders on the book, ordinary boxes trigger a
    ///         mid-day request and its word opens them. No cohort is priced or bound and no copy
    ///         is written; cohort 1 binds to the day-3 daily request instead.
    function test_MiddayWordNeverBindsACohort() public {
        mockVRF.fundSubscription(1, 100e18);
        _placeOrdersOn(2, 6, 10 minutes);
        _earnCredit(buyers[0], 1 ether); // 4 ETH of boxes: past the mid-day threshold
        uint256 req0 = mockVRF.lastRequestId();
        vm.recordLogs();
        for (uint256 i; i < 40 && mockVRF.lastRequestId() == req0; ++i) {
            try game.mineFlip(0) {} catch { break; }
        }
        assertEq(mockVRF.lastRequestId(), req0 + 1, "mid-day request sent");
        assertFalse(game.rngLocked(), "a mid-day request holds no daily lock");
        assertEq(game.currentDayView(), 2, "on Degenesis day 1");
        _drive(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (uint256 priced,) = _pricedIn(logs);
        assertEq(priced, 0, "no cohort priced on a mid-day word");
        assertEq(_countSig(logs, SIG_RESOLVED), 0, "no order resolved");
        assertEq(_active(), 0, "no binding");
        assertEq(_word(), 0, "no copy");
        assertEq(game.currentDayView(), 2, "still Degenesis day 1");

        uint256 q = _refQ(1, _degPool());
        uint256 w3 = uint256(keccak256("rv-midday-then-daily"));
        _warpTo(3, 1 hours);
        vm.recordLogs();
        _drive(w3);
        _assertMatchesRef(_resolvedOf(vm.getRecordedLogs(), 1), 1, w3, q, "daily word");
    }
}
