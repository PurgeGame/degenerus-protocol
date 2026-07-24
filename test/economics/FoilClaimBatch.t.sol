// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {PriceLookupLib} from "../../contracts/libraries/PriceLookupLib.sol";

/// @title FoilClaimBatch — behavioural coverage for claimFoilMatchMany
/// @notice The batch claimer is handed out as one shared tuple list that many senders may
///         submit; the first to land settles every tuple. These tests pin the three
///         properties that flow from that: mismatched arrays reject up front, a dead
///         opening tuple reverts the whole call (StaleBatch) so a later sender sees the
///         failure in simulation, and a dead tuple PAST the opener is skipped so one stale
///         entry cannot poison the remaining claims.
/// @dev Claimable tuples are discovered by snapshot-probing the singular entry point, so
///      the tests bind to real wins rather than hard-coded indices.
contract FoilClaimBatch is DeployProtocol {
    uint256 private _lastFulfilledReqId;

    uint256 private constant FOIL_BUYERS = 6;
    uint256 private constant TICKET_BUYERS = 6;

    error LengthMismatch();
    error StaleBatch();

    struct Tuple {
        address player;
        uint24 day;
        uint8 ticketIndex;
        uint8 drawKind;
    }

    address[FOIL_BUYERS] private _fb;
    uint24 private _buyDay;
    uint24 private _endDay;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _runScenario();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Cycle driving (mirrors FoilPackEV: a NotTimeYet "nothing to do" tick is benign)
    // ──────────────────────────────────────────────────────────────────────

    function _advance() internal {
        try game.advanceGame() {} catch {}
    }

    function _completeDay(uint256 vrfWord) internal {
        _advance();
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId != _lastFulfilledReqId && reqId > 0) {
            try mockVRF.fulfillRandomWords(reqId, vrfWord == 0 ? 1 : vrfWord) {} catch {}
            _lastFulfilledReqId = reqId;
        }
        for (uint256 i = 0; i < 50; i++) {
            if (!game.rngLocked()) break;
            _advance();
        }
    }

    /// @dev Domain string and arguments match FoilPackEV exactly: the draws these tests
    ///      need are the ones that scenario is already known to produce.
    function _seed(uint256 a, uint256 b) internal pure returns (uint256 w) {
        w = uint256(keccak256(abi.encode("foilEV", a, b)));
        if (w == 0) w = 1;
    }

    /// @dev Replays FoilPackEV's N=30 scenario move for move — same cohorts in the same
    ///      order, same whale cadence, same seeds — because RNG here is a function of the
    ///      whole purchase history. Dropping the ticket cohort or changing the seed domain
    ///      shifts every draw and the graded matches stop landing (P(score >= 4) ~ 0.0035
    ///      per comparison, so wins only accumulate across the full sweep).
    ///      Day advance goes through vm.getBlockTimestamp(): this whole scenario runs in
    ///      one setUp frame, where via-IR CSEs a chained `block.timestamp + 1 days` into a
    ///      single value and the clock never moves.
    function _runScenario() internal {
        uint256 nPurchaseDays = 30;
        uint24 lvl = game.level();
        uint256 priceWei = PriceLookupLib.priceForLevel(lvl + 1);
        uint256 foilCost = 10 * priceWei; // FOIL_PACK_TICKETS = 10
        uint256 ticketQty = (foilCost * 4 * 100) / priceWei; // one whole ticket = 4*TICKET_SCALE units

        for (uint256 i = 0; i < FOIL_BUYERS; i++) {
            _fb[i] = makeAddr(string(abi.encodePacked("foil", vm.toString(i))));
            vm.deal(_fb[i], 1_000 ether);
            vm.prank(_fb[i]);
            try game.purchase{value: foilCost}(_fb[i], 0, 0, bytes32(0), MintPaymentKind.DirectEth, true) {} catch {}
        }
        for (uint256 i = 0; i < TICKET_BUYERS; i++) {
            address tb = makeAddr(string(abi.encodePacked("tkt", vm.toString(i))));
            vm.deal(tb, 1_000 ether);
            vm.prank(tb);
            try game.purchase{value: foilCost}(tb, ticketQty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
        }

        _buyDay = game.currentDayView();

        address whale = makeAddr("whale");
        vm.deal(whale, 1_000_000 ether);
        for (uint256 d = 0; d < nPurchaseDays + 50; d++) {
            if (!game.jackpotPhase()) {
                uint256 pw = PriceLookupLib.priceForLevel(game.level() + 1);
                vm.prank(whale);
                try game.purchase{value: 50 * pw}(whale, 50 * 400, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
            }
            _completeDay(_seed(nPurchaseDays, d));
            vm.warp(vm.getBlockTimestamp() + 1 days);
        }
        _endDay = game.currentDayView();
    }

    // ──────────────────────────────────────────────────────────────────────
    // Discovery: find tuples that genuinely settle, without consuming them
    // ──────────────────────────────────────────────────────────────────────

    /// @dev Probe the singular entry point under a snapshot so the marker set by a
    ///      successful claim is rolled back; the returned tuples are still claimable.
    function _findClaimable(uint256 want) internal returns (Tuple[] memory found) {
        Tuple[] memory buf = new Tuple[](want);
        uint256 n;
        uint256 snap = vm.snapshotState();
        for (uint256 i = 0; i < FOIL_BUYERS && n < want; i++) {
            for (uint24 day = _buyDay + 1; day <= _endDay && n < want; day++) {
                if (game.rngWordForDay(day) == 0) continue;
                for (uint8 ti = 0; ti < 4 && n < want; ti++) {
                    for (uint8 dk = 0; dk < 2 && n < want; dk++) {
                        try game.claimFoilMatch(_fb[i], day, ti, dk) {
                            buf[n++] = Tuple(_fb[i], day, ti, dk);
                        } catch {}
                    }
                }
            }
        }
        vm.revertToState(snap);

        found = new Tuple[](n);
        for (uint256 i = 0; i < n; i++) found[i] = buf[i];
    }

    function _explode(Tuple[] memory t)
        internal
        pure
        returns (address[] memory p, uint24[] memory d, uint8[] memory ti, uint8[] memory dk)
    {
        p = new address[](t.length);
        d = new uint24[](t.length);
        ti = new uint8[](t.length);
        dk = new uint8[](t.length);
        for (uint256 i = 0; i < t.length; i++) {
            p[i] = t[i].player;
            d[i] = t[i].day;
            ti[i] = t[i].ticketIndex;
            dk[i] = t[i].drawKind;
        }
    }

    /// @dev A tuple that can never settle: ticketIndex is out of the 0-3 domain.
    function _deadTuple(address player) internal pure returns (Tuple memory) {
        return Tuple(player, 1, 9, 0);
    }

    // ──────────────────────────────────────────────────────────────────────
    // Tests
    // ──────────────────────────────────────────────────────────────────────

    /// @notice Array-length disagreement rejects before any claim is attempted.
    function test_lengthMismatch_reverts() public {
        address[] memory p = new address[](2);
        uint24[] memory d = new uint24[](1);
        uint8[] memory ti = new uint8[](2);
        uint8[] memory dk = new uint8[](2);
        vm.expectRevert(LengthMismatch.selector);
        game.claimFoilMatchMany(p, d, ti, dk);
    }

    /// @notice A non-claimable opening tuple reverts the whole call, so a sender handed an
    ///         already-swept list sees the failure in simulation instead of paying to walk it.
    function test_deadOpener_revertsStaleBatch() public {
        Tuple[] memory good = _findClaimable(2);
        require(good.length == 2, "scenario produced no claimable tuples");

        Tuple[] memory batch = new Tuple[](3);
        batch[0] = _deadTuple(_fb[0]); // dead opener
        batch[1] = good[0];
        batch[2] = good[1];

        (address[] memory p, uint24[] memory d, uint8[] memory ti, uint8[] memory dk) = _explode(batch);
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(p, d, ti, dk);
    }

    /// @notice Re-submitting an already-swept list reverts: the opener's marker is set, so
    ///         the second sender aborts at one tuple instead of walking the whole list.
    function test_resubmitSweptList_revertsStaleBatch() public {
        Tuple[] memory good = _findClaimable(3);
        require(good.length >= 2, "scenario produced too few claimable tuples");

        (address[] memory p, uint24[] memory d, uint8[] memory ti, uint8[] memory dk) = _explode(good);

        // First sender settles the list.
        game.claimFoilMatchMany(p, d, ti, dk);

        // Second sender, same calldata: opener is spent.
        vm.expectRevert(StaleBatch.selector);
        game.claimFoilMatchMany(p, d, ti, dk);
    }

    /// @notice A dead tuple PAST the opener is skipped, not fatal: the tuples after it
    ///         still settle, which is the property that lets one list cover many claims.
    function test_deadTuplePastOpener_isSkipped() public {
        Tuple[] memory good = _findClaimable(2);
        require(good.length == 2, "scenario produced too few claimable tuples");

        Tuple[] memory batch = new Tuple[](3);
        batch[0] = good[0];
        batch[1] = _deadTuple(_fb[0]); // dead in the middle
        batch[2] = good[1];

        (address[] memory p, uint24[] memory d, uint8[] memory ti, uint8[] memory dk) = _explode(batch);
        game.claimFoilMatchMany(p, d, ti, dk); // must not revert

        // Both good tuples are consumed: re-claiming either now fails.
        vm.expectRevert();
        game.claimFoilMatch(good[0].player, good[0].day, good[0].ticketIndex, good[0].drawKind);
        vm.expectRevert();
        game.claimFoilMatch(good[1].player, good[1].day, good[1].ticketIndex, good[1].drawKind);
    }
}
