// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {WWXRP} from "../../contracts/WWXRP.sol";
import {RngTags} from "../../contracts/libraries/RngTags.sol";

/// @notice Regression: WWXRP day d and day d+3 share bank d % 3, and day-(d+3) entries open at the
///         day-(d+3) daily REQUEST (dailyIdx = d+3). claim(d) used to stay open until the day-(d+3)
///         word was APPLIED, so in that tail a d+3 entry landing in day d's winning bucket replaced
///         the header and the unclaimed day-d winner got EmptyWinningBucket. The claim window now
///         closes at the day-(d+3) request, before any day-(d+3) entry can reuse the bank. Full
///         protocol, real Game day/word plumbing, mock VRF only.
contract WwxrpBankReuseTail is DeployProtocol {
    uint256 private _nonce;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(address(game), 2_000 ether);
        _settle();
    }

    function _dailyIdx() internal view returns (uint24) {
        return uint24(uint256(vm.load(address(game), bytes32(0))) >> 24);
    }

    function _fulfill(uint256 word) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (!fulfilled) mockVRF.fulfillRandomWords(reqId, word);
    }

    function _randWord() internal returns (uint256 w) {
        w = uint256(keccak256(abi.encode("reg-wwxrp", _nonce++))) | 2;
    }

    /// @dev Drain all pending work, answering every request with fresh words.
    function _settle() internal {
        for (uint256 i; i < 200; ++i) {
            if (!game.advanceDue() && !game.rngLocked()) return;
            _fulfill(_randWord());
            try game.mineRun(0) {} catch {}
        }
    }

    /// @dev Next wall day: mine until the daily request for `target` is out (dailyIdx == target),
    ///      WITHOUT answering it.
    function _requestDay(uint24 target) internal {
        vm.warp(block.timestamp + 1 days);
        for (uint256 i; i < 200 && _dailyIdx() != target; ++i) {
            try game.mineRun(0) {} catch {}
            if (_dailyIdx() == target) break;
            // Mid-day/maintenance requests before the daily one get answered normally.
            _fulfill(_randWord());
        }
        assertEq(_dailyIdx(), target, "daily request did not go out");
    }

    function _winningWord(uint8 bucket) internal pure returns (uint256 w) {
        for (w = 2; ; ++w) {
            if (uint256(keccak256(abi.encode(RngTags.WWXRP_BIG, w))) % 365 != 0
                && uint256(keccak256(abi.encode(RngTags.WWXRP_SMALL, w))) % 30 == 0
                && uint256(keccak256(abi.encode(RngTags.WWXRP_BUCKET, w))) % 10 == bucket) return w;
        }
    }

    function _enter(address who, uint256 amount) internal {
        vm.prank(address(game));
        wwxrp.mintPrize(who, amount);
        vm.prank(who);
        wwxrp.enterDraw(0, amount);
    }

    function test_ClaimWindowClosesAtDayPlus3RequestBeforeBankReuse() public {
        uint24 d = _dailyIdx();
        address alice = makeAddr("wwxrp_alice");
        uint32 aliceId = _giveWalletId(alice);
        uint8 b = wwxrp.bucketOf(d, aliceId);
        _enter(alice, 100);

        // Day d+1: the request goes out, answered with a word that makes day d a SMALL win in b.
        uint256 w = _winningWord(b);
        _requestDay(d + 1);
        _fulfill(w);
        _settle();
        assertEq(game.latestDailyResultDay(), d + 1, "word d+1 applied");
        assertEq(game.rngWordForDay(d + 1), w, "raw word recorded");
        (bool found, uint32 idx, uint32 winner) = wwxrp.findWinningEntry(d);
        assertTrue(found && idx == 0 && winner == aliceId, "alice won day d");

        // Day d+2: ordinary day. Control: the claim is open through the whole logical day d+2.
        _requestDay(d + 2);
        _settle();
        assertEq(game.latestDailyResultDay(), d + 2);
        uint256 snap = vm.snapshotState();
        wwxrp.claim(d, 0);
        assertTrue(wwxrp.dayClaimed(d), "control claim paid on day d+2");
        assertTrue(vm.revertToState(snap));

        // Day d+3: the request is out, the word is not yet applied. Day d+3 entries can now reuse
        // bank d % 3, so day d's claims are closed.
        _requestDay(d + 3);
        assertEq(game.latestDailyResultDay(), d + 2, "word d+3 not applied yet");
        (found,,) = wwxrp.findWinningEntry(d);
        assertFalse(found, "finder closed at the d+3 request");
        (bool available,,,,,,) = wwxrp.previewOutcome(d);
        assertFalse(available, "preview closed at the d+3 request");
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        wwxrp.claim(d, 0);

        // An ordinary day-(d+3) entrant whose bucket is b writes day d's bank; day d stays closed.
        address bob;
        for (uint256 k; ; ++k) {
            address cand = makeAddr(string(abi.encodePacked("wwxrp_bob", k)));
            uint32 id = _giveWalletId(cand);
            if (wwxrp.bucketOf(d + 3, id) == b) { bob = cand; break; }
        }
        _enter(bob, 25);
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        wwxrp.claim(d, 0);

        _fulfill(_randWord());
        _settle();
        assertEq(game.latestDailyResultDay(), d + 3);
        vm.expectRevert(WWXRP.WordUnavailable.selector);
        wwxrp.claim(d, 0);
        assertFalse(wwxrp.dayClaimed(d));
    }
}
