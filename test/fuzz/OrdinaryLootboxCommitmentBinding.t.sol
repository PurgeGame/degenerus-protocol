// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";

/// @notice Public purchase/request/fulfill/open commitment proof for ordinary boxes.
/// Two unrelated owners and fixed words cover ticket, sDGNRS, flat FLIP and normal
/// Craps-pass rolls. Expected payouts are reconstructed independently from known
/// committed inputs, then compared with balances, queued ownership, inventory and
/// banked/reserved passes, never with an event-derived payout oracle.
///
/// Every setup and attack action uses production public entry points; no state or
/// runtime injection. Late orders/bets use the next index. Time/block/caller and
/// per-owner open partition change, while level/day remain fixed during opening.
/// Later purchases legitimately change ETH pools; each open is checked against
/// its own actual pool snapshot. sDGNRS uses sequential live inventory, not a
/// claimed immutable award amount. Pass awards include an automatic reservation.
///
/// Scope: one/two unboosted 1-ETH custom boxes per owner at level zero, low frozen
/// activity score, four ordinary reward lanes. Spins, boon formulas, presale,
/// AFKing/direct/redemption boxes, high-pass conversion and level changes are
/// outside this proof. Unsupported reward rolls fail rather than silently skip.
contract OrdinaryLootboxCommitmentBindingTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant KEEPER_ONE = address(0xC0DE);
    address private constant KEEPER_TWO = address(0xD00D);
    uint256 private constant TICKET_DGNRS_WORD = 23_784;
    uint256 private constant FLIP_PASS_WORD = 461;
    uint256 private constant BOX_TAG = 0x426f784f70656e;
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64;
    uint256 private constant PASS_ROUND_TAG = 0x50617373526f756e64;
    uint256 private constant NORMAL_PASS_VALUE = 24_800 ether;

    struct Outcome {
        uint256[51] entries;
        uint256 flip;
        uint256 dgnrs;
        uint256 normal;
    }

    struct Balance {
        uint256[51] entries;
        uint256 flip;
        uint256 dgnrs;
        uint256 normal;
        uint256 high;
        uint256 liquidFlip;
        uint256 wwxrp;
        uint256 claimable;
    }

    function setUp() public {
        _deployProtocol();
        mockVRF.fundSubscription(1, 100e18);
        vm.warp(block.timestamp + 1 days);
        // Subscribed before the bootstrap request, so their subscribe-time cover boxes resolve in
        // the bootstrap cohort and never share a cohort with the owners' orders.
        _spawnAfkingSubscribers(40);
        _requestDaily();
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xB007);
        _finishDaily();
        _settleIdle();
        assertEq(game.level(), 0, "fixture's live denomination");
        vm.deal(ALICE, 100 ether);
        vm.deal(BOB, 100 ether);
    }

    function _index() private view returns (uint48) {
        return RecyclingState.writeBuffer(address(game));
    }

    function _word(uint48 index) private view returns (uint256) {
        return RecyclingState.word(address(game), index);
    }

    function _order(uint48 index, address owner) private view returns (uint256) {
        uint48 active = _index();
        if (index > 1) return 0;
        bytes32 outer = keccak256(abi.encode(uint256(index & 1), uint256(15)));
        uint256 order = uint256(vm.load(address(game), keccak256(abi.encode(owner, outer))));
        return order & (uint256(1) << 255) != 0 ? 0 : order;
    }

    function _pool() private view returns (uint256) {
        return IsDGNRS(address(sdgnrs)).poolBalance(IsDGNRS.Pool.Lootbox);
    }

    function _requestDaily() private {
        for (uint256 i; i < 50 && !game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertTrue(game.rngLocked(), "real daily request must engage");
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled, "fixture needs a fresh unfulfilled request");
    }

    function _finishDaily() private {
        for (uint256 i; i < 100 && game.rngLocked(); ++i) {
            game.mineFlip();
        }
        assertFalse(game.rngLocked(), "bounded daily processing must finish");
    }

    /// @dev Finish every read consumer of the delivered cohorts. A shut craps window the day
    ///      bound to the write buffer rides the next request, which the engine makes as mid-day
    ///      work; answer and drain it too, so a fresh request is admissible.
    function _settleIdle() private {
        for (uint256 i; i < 20; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,, bool done) = mockVRF.pendingRequests(request);
                if (!done) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("trailing", i))) | 2);
            }
            _finishReadConsumers();
            if (!game.advanceDue() && game.rngComplete()) return;
            if (game.advanceDue()) game.mineFlip();
        }
        revert("harness: cohorts never settled");
    }

    /// @dev Lootbox-mode AFKing subscribers, stamped a box each at every day's preparation. A
    ///      daily cohort's read consumers run in the same call that releases the day's lock, and
    ///      the final day chunk's declared bound leaves room for both owners' entries; the AFKing
    ///      stage precedes human boxes, so a backlog of stamped boxes holds the human stage to its
    ///      own later call, where openBoxes reaches the owners' entries. Mid-day cohorts carry no
    ///      stamps and are unaffected.
    function _spawnAfkingSubscribers(uint256 n) private {
        for (uint256 i; i < n; ++i) {
            address sub = address(uint160(0x5AB000 + i));
            _grantSeat(sub);
            vm.deal(address(this), 10 ether);
            game.depositAfkingFunding{value: 10 ether}(sub);
            vm.prank(sub);
            game.subscribe(address(0), false, false, 1, address(0));
        }
    }

    /// @dev One mineFlip given the smallest allowance that succeeds (bisection over snapshots).
    ///      A zero-progress call reverts, so the minimal call runs exactly the next admitted chunk
    ///      and leaves too little allowance to admit a later, larger one.
    function _stepMinimal() private {
        uint256 lo = 200_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            vm.revertToStateAndDelete(snap);
            if (ok) hi = mid;
            else lo = mid;
        }
        game.mineFlip{gas: hi}();
    }

    /// @dev Drive the delivered cohort (publication, tickets, and on a daily request the whole
    ///      day's processing) in minimal checkpoints up to its human-box stage, where the box
    ///      orders are the next read consumer: openBoxes is the door that opens them from here.
    function _advanceToHumanBoxes(uint48 index, uint256[2] memory orders) private {
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() == 10) return; // MinerAction.HumanBoxes
            _stepMinimal();
            _assertOrders(index, orders, false);
        }
        revert("harness: the human-box stage was never reached");
    }

    function _drained(uint48 index) private view returns (uint256 n) {
        if (_order(index, ALICE) == 0) ++n;
        if (_order(index, BOB) == 0) ++n;
    }

    /// @dev The smallest openBoxes allowance that drains the next owner's entry (bisection over
    ///      snapshots): each entry is admitted only while the remaining allowance covers its
    ///      declared bound, and both owners' entries carry the same bound, so this budget opens
    ///      exactly one.
    function _oneEntryBudget(uint48 index) private returns (uint256) {
        uint256 before = _drained(index);
        uint256 lo = 100_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("openBoxes(uint256)", uint256(2)));
            bool opened = ok && _drained(index) > before;
            vm.revertToStateAndDelete(snap);
            if (opened) hi = mid;
            else lo = mid;
        }
        return hi;
    }

    function _buy(address owner, uint256 count, uint256 size) private {
        vm.prank(owner);
        game.purchase{value: 0.01 ether + count * size}(
            owner, 400, BoxOrderLib.boCustoms(count, size), bytes32(0), MintPaymentKind.DirectEth, false
        );
    }

    function _prepare(uint256 count) private returns (uint48 index, uint256[2] memory orders) {
        index = _index();
        _buy(ALICE, count, 1 ether);
        _buy(BOB, count, 1 ether);
        orders[0] = _order(index, ALICE);
        orders[1] = _order(index, BOB);
        // Exact full words: level 1, score 1, no boost/distress/EV-cap/cover lane,
        // `count` customs of 1 ETH (1e6 stored units). The fresh purchase supplies
        // this score; it is not injected by the test.
        uint256 expected = 1 | (uint256(1) << 24) | (count << 105) | (uint256(1_000_000) << 113);
        assertEq(orders[0], expected, "Alice's exact committed order fields");
        assertEq(orders[1], expected, "Bob's exact committed order fields");
        assertEq(_word(index), 0, "purchase must precede word revelation");
        assertGt(_pool(), 0, "funded reward inventory");
    }

    function _assertOrders(uint48 index, uint256[2] memory orders, bool aliceSpent) private view {
        assertEq(_order(index, ALICE), aliceSpent ? 0 : orders[0], "old Alice order cannot be rewritten or replayed");
        assertEq(_order(index, BOB), orders[1], "old Bob order cannot be rewritten");
        assertEq(_index(), (index ^ 1), "new actions remain on the subsequent index");
    }

    function _perturb(uint48 index, uint256[2] memory orders, bool aliceSpent) private {
        assertEq(_index(), (index ^ 1));
        uint256 nextAlice = _order((index ^ 1), ALICE);
        uint256 nextBob = _order((index ^ 1), BOB);
        uint256 ethBefore = address(game).balance + mockStETH.balanceOf(address(game));
        // Different custom denomination, plus new paid tickets and a competing bet.
        // These are successful public writes, not a set of swallowed reverts.
        _buy(ALICE, 1, 0.25 ether);
        _buy(BOB, 1, 0.25 ether);
        vm.prank(ALICE);
        game.placeDegeneretteBet{value: 0.01 ether}(ALICE, 0, 0.01 ether, 1, 17);
        if (game.rngLocked()) vm.expectRevert(bytes4(keccak256("BetLocked()")));
        vm.prank(BOB);
        crapsBattle.setPreferredBoard(uint32(1 << 9));
        assertGt(_order((index ^ 1), ALICE), nextAlice, "next-index Alice order really grew");
        assertGt(_order((index ^ 1), BOB), nextBob, "next-index Bob order really grew");
        assertGt(
            address(game).balance + mockStETH.balanceOf(address(game)), ethBefore, "public mutation moved real backing"
        );
        _assertOrders(index, orders, aliceSpent);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _seed(uint256 word, address owner, uint256 nonce) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(word, uint256(uint160(owner)), BOX_TAG, nonce)));
    }

    function _target(uint256 seed) private pure returns (uint256) {
        return uint16(seed) % 100 < 20 ? 6 + uint16(seed >> 24) % 46 : 1 + uint8(seed >> 16) % 5;
    }

    function _variance(uint256 seed) private pure returns (uint256) {
        uint256 roll = uint24(seed >> 96) % 10_000;
        uint256[6] memory cut = [uint256(0), 100, 500, 2500, 7000, 10_000];
        uint256[5] memory lo = [uint256(40_000), 20_000, 10_000, 5923, 3600];
        uint256[5] memory hi = [uint256(65_000), 35_000, 16_000, 9923, 7200];
        for (uint256 i; i < 5; ++i) {
            if (roll < cut[i + 1]) return lo[i] + (roll - cut[i]) * (hi[i] - lo[i]) / (cut[i + 1] - cut[i] - 1);
        }
        revert("unreachable variance");
    }

    function _dgnrs(uint256 seed, uint256 inventory) private pure returns (uint256 amount) {
        uint256 roll = uint24(seed >> 56) % 1000;
        uint256 ppm = roll < 795 ? 10 : roll < 945 ? 390 : roll < 995 ? 800 : 8000;
        // 1 ETH * 90.16% frozen score multiplier, less the 10% boon budget.
        amount = inventory * ppm * 0.811_44 ether / (1_000_000 * 1 ether);
        uint256 step = 1;
        while (amount / step >= 1000) step *= 10;
        amount = amount / step * step;
        if (amount > inventory) amount = inventory;
    }

    function _largeFlip(uint256 seed) private pure returns (uint256) {
        uint256 roll = uint16(seed >> 80) % 20;
        uint256 bps = roll < 16 ? 4388 + roll * 360 : 23_199 + (roll - 16) * 7125;
        return (0.811_44 ether * bps / 10_000) * 1000 ether / 0.01 ether;
    }

    function _reference(uint256 word, address owner, uint256 count, uint256 inventory)
        private
        pure
        returns (Outcome memory expected)
    {
        for (uint256 nonce = 1; nonce <= count; ++nonce) {
            uint256 seed = _seed(word, owner, nonce);
            uint256 roll = uint16(seed >> 40) % 20;
            if (roll < 8) {
                uint256 target = _target(seed);
                require(target <= 4, "reference fixtures use the .01 ETH ticket tier");
                uint256 budget = (0.811_44 ether * 19_678 / 10_000) * 8750 / 10_000;
                uint256 scaled = (budget * _variance(seed) / 10_000) * 100 / 0.01 ether;
                uint256 whole = scaled / 100;
                if (uint32(seed >> 224) % 100 < scaled % 100) ++whole;
                expected.entries[target - 1] += whole * 4;
            } else if (roll < 11) {
                uint256 award = _dgnrs(seed, inventory - expected.dgnrs);
                expected.dgnrs += award;
            } else if (roll == 14) {
                uint256 amount = _largeFlip(seed);
                if (amount > 1000 ether) {
                    uint256 hundreds = amount / 100 ether;
                    uint256 rem = amount % 100 ether / 1 ether;
                    uint256 entropy = uint256(keccak256(abi.encode(seed, FLIP_ROUND_TAG)));
                    if (uint32(entropy) % 100 < rem) ++hundreds;
                    expected.flip += hundreds * 100 ether;
                } else {
                    expected.flip += amount / 1 ether * 1 ether;
                }
            } else if (roll == 15 || roll == 16) {
                uint256 budget = _largeFlip(seed);
                require(budget <= 22 * NORMAL_PASS_VALUE, "reference excludes high-pass conversion");
                uint256 passes = budget / NORMAL_PASS_VALUE;
                if (
                    uint256(keccak256(abi.encode(seed, PASS_ROUND_TAG))) % NORMAL_PASS_VALUE
                        < budget % NORMAL_PASS_VALUE
                ) {
                    ++passes;
                }
                require(passes != 0, "reference excludes the zero-pass spin fallback");
                expected.normal += passes;
            } else {
                revert("reference fixture entered an unsupported spin");
            }
        }
    }

    function _balance(address owner) private view returns (Balance memory state) {
        for (uint24 lvl = 1; lvl <= 51; ++lvl) {
            state.entries[lvl - 1] = game.entriesOwedView(lvl, owner);
        }
        state.flip = coinflip.coinflipAmount(owner);
        state.dgnrs = sdgnrs.balanceOf(owner);
        (state.normal, state.high) = crapsBattle.passCreditsOf(owner);
        uint24 tomorrow = crapsBattle.currentDayIndex() + 1;
        if (crapsBattle.daySeatNumberOf(tomorrow, owner) != 0) {
            if (crapsBattle.daySeatIsHigh(tomorrow, owner)) ++state.high;
            else ++state.normal;
        }
        state.liquidFlip = coin.balanceOf(owner);
        state.wwxrp = wwxrp.balanceOf(owner);
        state.claimable = game.claimableWinningsOf(owner);
    }

    function _assertDelta(address owner, Balance memory beforeState, Outcome memory expected)
        private
        view
        returns (bytes32)
    {
        Balance memory afterState = _balance(owner);
        for (uint256 i; i < 51; ++i) {
            assertEq(
                afterState.entries[i],
                beforeState.entries[i] + expected.entries[i],
                "actual owner/target ticket binding"
            );
        }
        assertEq(afterState.flip, beforeState.flip + expected.flip, "actual beneficiary FLIP stake");
        assertEq(afterState.dgnrs, beforeState.dgnrs + expected.dgnrs, "actual beneficiary live-inventory sDGNRS award");
        assertEq(
            afterState.normal, beforeState.normal + expected.normal, "pass bank plus reserved seat preserves the award"
        );
        assertEq(afterState.high, beforeState.high, "no unexpected high pass");
        assertEq(afterState.liquidFlip, beforeState.liquidFlip, "flat FLIP is a stake, not an extra liquid payment");
        assertEq(afterState.wwxrp, beforeState.wwxrp, "no unexpected spin/consolation reward");
        assertEq(afterState.claimable, beforeState.claimable, "no unexpected ETH award");
        return keccak256(abi.encode(expected));
    }

    function _open(uint256 budget, address caller, uint256 expectedCount, uint48 index) private {
        uint256 nextAlice = _order((index ^ 1), ALICE);
        uint256 nextBob = _order((index ^ 1), BOB);
        uint256 next = game.nextPrizePoolView();
        uint256 future = game.futurePrizePoolView();
        uint256 current = game.currentPrizePoolView();
        uint256 liability = game.claimablePoolView();
        // The walk-unit count became a gas allowance (60d31f775): a budget of 2 is the smallest
        // allowance that opens one owner's entry; a large budget is an unbounded call.
        uint256 allowance = budget == 2 ? _oneEntryBudget(index) : 0;
        vm.prank(caller);
        if (allowance == 0) assertEq(game.openBoxes(budget), expectedCount, "exact number of consumed boxes");
        else assertEq(game.openBoxes{gas: allowance}(budget), expectedCount, "exact number of consumed boxes");
        assertEq(_order((index ^ 1), ALICE), nextAlice, "unrevealed Alice order survives old-index opening");
        assertEq(_order((index ^ 1), BOB), nextBob, "unrevealed Bob order survives old-index opening");
        assertEq(game.nextPrizePoolView(), next, "ordinary reward does not spend ticket backing");
        assertEq(game.futurePrizePoolView(), future, "ordinary reward does not spend live ETH inventory");
        assertEq(game.currentPrizePoolView(), current);
        assertEq(game.claimablePoolView(), liability);
        assertEq(game.claimableWinningsOf(caller), 0, "third-party keeper receives no owner ETH");
        assertEq(sdgnrs.balanceOf(caller), 0, "third-party keeper receives no owner sDGNRS");
        assertEq(coinflip.coinflipAmount(caller), 0, "unrewarded opener receives no owner FLIP");
    }

    function _run(uint48 index, uint256[2] memory orders, uint256 count, uint256 word, bool daily, bool perturb)
        private
        returns (bytes32 outcome)
    {
        if (daily) {
            vm.warp(block.timestamp + 1 days);
            _requestDaily();
        } else {
            game.requestLootboxRng();
        }
        _assertOrders(index, orders, false);
        assertEq(_word(index), 0);
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled);
        vm.prank(KEEPER_ONE);
        assertEq(game.openBoxes(1000), 0, "unready orders cannot be silently consumed");
        _assertOrders(index, orders, false);
        if (perturb) _perturb(index, orders, false);
        mockVRF.fulfillRandomWords(request, word);
        (,, fulfilled) = mockVRF.pendingRequests(request);
        assertTrue(fulfilled, "callback really fulfilled");
        if (perturb) _perturb(index, orders, false);
        // Publish the delivered word (and on a daily request, finish the day) before opening.
        _advanceToHumanBoxes(index, orders);
        assertFalse(game.rngLocked(), "the day's processing finished before opening");
        assertEq(game.level(), 0, "opening denomination intentionally held fixed");
        assertEq(_word(index), word, "exact delivered word reaches its committed index");
        assertEq(_word((index ^ 1)), 0, "later purchases remain unrevealed");
        _assertOrders(index, orders, false);

        uint256 inventory = _pool();
        Outcome memory alice = _reference(word, ALICE, count, inventory);
        Outcome memory bob = _reference(word, BOB, count, inventory - alice.dgnrs);
        if (count == 2) {
            assertGt(alice.entries[3], 0, "known Alice ticket roll exercised");
            assertGt(bob.entries[0], 0, "known Bob ticket roll exercised");
            assertGt(alice.dgnrs, 0, "known mega-tier sDGNRS roll exercised");
            assertGt(bob.dgnrs, 0, "second owner sDGNRS roll exercised");
            assertNotEq(
                bob.dgnrs, _dgnrs(_seed(word, BOB, 1), inventory), "fixture distinguishes live from stale inventory"
            );
        } else {
            assertGt(alice.flip, 0, "known flat FLIP branch exercised");
            assertGt(bob.normal, 0, "known pass branch exercised");
        }
        Balance memory beforeAlice = _balance(ALICE);
        Balance memory beforeBob = _balance(BOB);
        if (perturb) {
            _open(2, KEEPER_ONE, count, index);
            assertEq(_order(index, ALICE), 0, "first owner consumed exactly once");
            assertEq(_order(index, BOB), orders[1], "budget break preserves second owner");
            _assertDelta(ALICE, beforeAlice, alice);
            Outcome memory none;
            _assertDelta(BOB, beforeBob, none);
            assertEq(_pool(), inventory - alice.dgnrs, "first owner's actual pool debit");
            _perturb(index, orders, true);
            // New purchases can change FLIP stake and queues legitimately; snapshot those
            // writes separately so the second open is graded only for its own rewards.
            beforeAlice = _balance(ALICE);
            beforeBob = _balance(BOB);
            _open(2, KEEPER_TWO, count, index);
            _assertDelta(ALICE, beforeAlice, none);
            _assertDelta(BOB, beforeBob, bob);
        } else {
            _open(1000, KEEPER_TWO, count * 2, index);
            _assertDelta(ALICE, beforeAlice, alice);
            _assertDelta(BOB, beforeBob, bob);
        }
        assertEq(_order(index, ALICE), 0);
        assertEq(_order(index, BOB), 0);
        assertEq(
            _pool(), inventory - alice.dgnrs - bob.dgnrs, "actual pool debit equals both independently priced awards"
        );
        assertEq(_word(index), word, "consumption cannot alter the commitment");
        assertEq(_word((index ^ 1)), 0);
        beforeAlice = _balance(ALICE);
        beforeBob = _balance(BOB);
        _open(1000, KEEPER_ONE, 0, index);
        Outcome memory zero;
        _assertDelta(ALICE, beforeAlice, zero);
        _assertDelta(BOB, beforeBob, zero);
        outcome = keccak256(abi.encode(alice, bob));
    }

    function _compare(bool daily, uint256 count, uint256 word) private {
        (uint48 index, uint256[2] memory orders) = _prepare(count);
        uint256 snapshot = vm.snapshotState();
        bytes32 baseline = _run(index, orders, count, word, daily, false);
        assertTrue(vm.revertToState(snapshot));
        bytes32 attacked = _run(index, orders, count, word, daily, true);
        assertEq(attacked, baseline, "fixed draws retain payout identity under allowed public perturbations");
    }

    function testMiddayTicketAndSequentialDgnrsBinding() public {
        _compare(false, 2, TICKET_DGNRS_WORD);
    }

    function testDailyTicketAndSequentialDgnrsBinding() public {
        _compare(true, 2, TICKET_DGNRS_WORD);
    }

    function testMiddayFlipAndPassBinding() public {
        _compare(false, 1, FLIP_PASS_WORD);
    }

    function testDailyFlipAndPassBinding() public {
        _compare(true, 1, FLIP_PASS_WORD);
    }
}
