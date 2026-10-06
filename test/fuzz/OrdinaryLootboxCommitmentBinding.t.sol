// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;
import {RecyclingState} from "../helpers/RecyclingState.sol";

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {Vm} from "forge-std/Vm.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {IsDGNRS} from "../../contracts/interfaces/IsDGNRS.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

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
///
/// Each purchase is its own queue entry at a fixed (buffer, position); settlement only moves
/// `boxCursor`, so a settled entry keeps its stored word and reads as spent by position. The
/// fixed words are found deterministically from the queued-entry seed formula (root =
/// H(QUEUED_ORDER_DOMAIN, word, buffer, position), box n = H(root, walletId, BOX_OPEN_TAG, n)) for
/// the owners' actual wallet IDs and positions, so the reference shares no code with the resolver.
contract OrdinaryLootboxCommitmentBindingTest is DeployProtocol {
    address private constant ALICE = address(0xA11CE);
    address private constant BOB = address(0xB0B);
    address private constant KEEPER_ONE = address(0xC0DE);
    address private constant KEEPER_TWO = address(0xD00D);
    uint256 private constant QUEUED_ORDER_DOMAIN = 0x5175657565644f72646572;
    uint256 private constant BOX_TAG = 0x426f784f70656e;
    uint256 private constant FLIP_ROUND_TAG = 0x466c6970526f756e64;
    uint256 private constant PASS_ROUND_TAG = 0x50617373526f756e64;
    uint256 private constant NORMAL_PASS_VALUE = 24_800 ether;
    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");

    struct Outcome {
        uint256[51] entries;
        uint256 flip;
        uint256 dgnrs;
        uint256 normal;
    }

    /// @dev The owners' entry positions in the committed buffer, set by `_prepare`.
    uint256 private posA;
    uint256 private posB;

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

    function _entry(uint48 index, uint256 position) private view returns (uint256) {
        return RecyclingState.boxEntry(address(game), index, position);
    }

    /// @dev An entry is spent once the read cursor of its sealed buffer has passed it. Queried only
    ///      after `index` was sealed: if a later request has since sealed the other buffer, the
    ///      cohort at `index` completed first (a request waits for every read consumer), so all its
    ///      entries are spent.
    function _spent(uint48 index, uint256 position) private view returns (bool) {
        if (RecyclingState.readBuffer(address(game)) != index) return true;
        uint256 cursor = (uint256(vm.load(address(game), bytes32(GameSlots.BOX_CURSOR)))
            >> (GameSlots.BOX_CURSOR_OFFSET * 8)) & type(uint48).max;
        return cursor > position;
    }

    /// @dev Digest of the write buffer's entries: later purchases append there, never to the
    ///      committed buffer.
    function _writeSide(uint48 index) private view returns (bytes32 digest) {
        uint256 n = RecyclingState.boxCount(address(game), index);
        digest = bytes32(n);
        for (uint256 p; p < n; ++p) digest = keccak256(abi.encode(digest, _entry(index, p)));
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
    ///      own later call, where mineFlip reaches the owners' entries. Mid-day cohorts carry no
    ///      stamps and are unaffected.
    function _spawnAfkingSubscribers(uint256 n) private {
        for (uint256 i; i < n; ++i) {
            address sub = address(uint160(0x5AB000 + i));
            _grantSeat(sub);
            _giveWalletId(sub); // a third-party deposit needs the beneficiary's wallet ID
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
    ///      orders are the next read consumer of mineFlip.
    function _advanceToHumanBoxes(uint48 index, uint256[2] memory orders) private {
        for (uint256 i; i < 400; ++i) {
            if (game.nextMinerAction() == 10) return; // MinerAction.HumanBoxes
            _stepMinimal();
            _assertOrders(index, orders, false);
        }
        revert("harness: the human-box stage was never reached");
    }

    function _drained(uint48 index) private view returns (uint256 n) {
        if (_spent(index, posA)) ++n;
        if (_spent(index, posB)) ++n;
    }

    /// @dev The smallest mineFlip allowance that drains the next `entries` owner entries (bisection
    ///      over snapshots): each entry is admitted only while the remaining allowance covers its
    ///      declared bound, and both owners' entries carry the same bound, so this budget opens
    ///      exactly `entries` and leaves too little to admit a later request.
    function _drainBudget(uint48 index, uint256 entries) private returns (uint256) {
        uint256 before = _drained(index);
        uint256 lo = 100_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            bool opened = ok && _drained(index) >= before + entries;
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
        posA = RecyclingState.boxCount(address(game), index);
        _buy(ALICE, count, 1 ether);
        posB = RecyclingState.boxCount(address(game), index);
        _buy(BOB, count, 1 ether);
        assertEq(posB, posA + 1, "each purchase appends its own entry");
        assertEq(RecyclingState.boxCount(address(game), index), posB + 1);
        orders[0] = _entry(index, posA);
        orders[1] = _entry(index, posB);
        // Exact full words: the owner's wallet ID, level 1, score 1, no boost/distress/EV-cap/
        // cover/presale lane, `count` customs of 1 ETH (1e9 gwei). The fresh purchase supplies
        // this score; it is not injected by the test.
        uint256 lanes = (uint256(1) << 32) | (uint256(1) << 56) | (count << 121) | (uint256(1e9) << 128);
        assertEq(orders[0], uint256(game.walletIdOf(ALICE)) | lanes, "Alice's exact committed entry fields");
        assertEq(orders[1], uint256(game.walletIdOf(BOB)) | lanes, "Bob's exact committed entry fields");
        assertEq(_word(index), 0, "purchase must precede word revelation");
        assertGt(_pool(), 0, "funded reward inventory");
    }

    function _assertOrders(uint48 index, uint256[2] memory orders, bool aliceSpent) private view {
        assertEq(_entry(index, posA), orders[0], "old Alice entry cannot be rewritten");
        assertEq(_entry(index, posB), orders[1], "old Bob entry cannot be rewritten");
        assertEq(_spent(index, posA), aliceSpent, "Alice's entry is spent exactly when settled");
        assertFalse(_spent(index, posB), "Bob's entry is not yet spent");
        assertEq(_index(), (index ^ 1), "new actions remain on the subsequent index");
    }

    function _perturb(uint48 index, uint256[2] memory orders, bool aliceSpent) private {
        assertEq(_index(), (index ^ 1));
        uint256 next = RecyclingState.boxCount(address(game), index ^ 1);
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
        assertEq(RecyclingState.boxCount(address(game), index ^ 1), next + 2, "two next-index entries really appended");
        assertEq(BoxOrderLib.boId(_entry(index ^ 1, next)), game.walletIdOf(ALICE), "next-index Alice entry");
        assertEq(BoxOrderLib.boId(_entry(index ^ 1, next + 1)), game.walletIdOf(BOB), "next-index Bob entry");
        assertGt(
            address(game).balance + mockStETH.balanceOf(address(game)), ethBefore, "public mutation moved real backing"
        );
        _assertOrders(index, orders, aliceSpent);
        vm.roll(block.number + 1);
        vm.warp(block.timestamp + 1);
    }

    function _seed(uint256 word, uint48 index, uint256 position, uint32 id, uint256 nonce)
        private
        pure
        returns (uint256)
    {
        uint256 root = uint256(keccak256(abi.encode(QUEUED_ORDER_DOMAIN, word, uint256(index), position)));
        return uint256(keccak256(abi.encode(root, uint256(id), BOX_TAG, nonce)));
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
        uint256 ppm = roll < 497 ? 10 : roll < 864 ? 390 : roll < 995 ? 800 : 8000;
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

    /// @dev `supported` is false when a box leaves the reference's scope (a spin, a ticket target
    ///      above the .01 ETH tier, a high-pass conversion or a zero-pass fallback).
    function _reference(uint256 word, uint48 index, uint256 position, uint32 id, uint256 count, uint256 inventory)
        private
        pure
        returns (Outcome memory expected, bool supported)
    {
        for (uint256 nonce = 1; nonce <= count; ++nonce) {
            uint256 seed = _seed(word, index, position, id, nonce);
            uint256 roll = uint16(seed >> 40) % 20;
            if (roll < 8) {
                uint256 target = _target(seed);
                if (target > 4) return (expected, false); // reference fixtures use the .01 ETH ticket tier
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
                    expected.flip += hundreds * 100;
                } else {
                    expected.flip += amount / 1 ether;
                }
            } else if (roll == 15 || roll == 16) {
                uint256 budget = _largeFlip(seed);
                if (budget > 22 * NORMAL_PASS_VALUE) return (expected, false); // high-pass conversion
                uint256 passes = budget / NORMAL_PASS_VALUE;
                if (
                    uint256(keccak256(abi.encode(seed, PASS_ROUND_TAG))) % NORMAL_PASS_VALUE
                        < budget % NORMAL_PASS_VALUE
                ) {
                    ++passes;
                }
                if (passes == 0) return (expected, false); // zero-pass spin fallback
                expected.normal += passes;
            } else {
                return (expected, false); // a spin
            }
        }
        supported = true;
    }

    /// @dev The first word (searched deterministically) whose draws for the owners' committed
    ///      entries exercise the fixture's lanes: with two boxes each, an Alice ticket at the fourth
    ///      level, a Bob ticket at the first, and an sDGNRS award for both owners whose later award
    ///      distinguishes live from stale inventory; with one box each, Alice's flat FLIP and Bob's
    ///      normal passes. Every box stays inside the reference's scope.
    function _findWord(uint48 index, uint256 count) private view returns (uint256 word) {
        uint32 idA = game.walletIdOf(ALICE);
        uint32 idB = game.walletIdOf(BOB);
        uint256 inventory = _pool();
        for (uint256 k;; ++k) {
            word = uint256(keccak256(abi.encode("commitment-binding", count, k)));
            (Outcome memory alice, bool okA) = _reference(word, index, posA, idA, count, inventory);
            if (!okA) continue;
            (Outcome memory bob, bool okB) = _reference(word, index, posB, idB, count, inventory - alice.dgnrs);
            if (!okB) continue;
            if (count == 2) {
                if (alice.entries[3] == 0 || bob.entries[0] == 0 || alice.dgnrs == 0 || bob.dgnrs == 0) continue;
                if (bob.dgnrs == _dgnrs(_seed(word, index, posB, idB, 1), inventory)) continue;
            } else if (alice.flip == 0 || bob.normal == 0) {
                continue;
            }
            return word;
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

    /// @dev The FLIP a single recorded mineFlip paid its caller (MinerWork.flipReward).
    function _minerReward(Vm.Log[] memory logs) private view returns (uint256 reward) {
        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length != 0 && logs[i].topics[0] == MINER_WORK_SIG) {
                (,, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++seen;
            }
        }
        assertEq(seen, 1, "one MinerWork per mineFlip");
    }

    /// @dev One mineFlip by `caller`. `boxesPerOrder` is each owner's committed box count, so the
    ///      owners' consumed orders give the exact number of consumed boxes.
    function _open(uint256 budget, address caller, uint256 expectedCount, uint48 index, uint256 boxesPerOrder) private {
        bytes32 writeSide = _writeSide(index ^ 1);
        uint256 next = game.nextPrizePoolView();
        uint256 future = game.futurePrizePoolView();
        uint256 current = game.currentPrizePoolView();
        uint256 liability = game.claimablePoolView();
        uint256 drainedBefore = _drained(index);
        uint256 callerFlip = coinflip.coinflipAmount(caller);
        // A budget of 2 is the smallest allowance that opens one owner's entry; a large budget is
        // the smallest allowance that opens every expected entry in one call, so the call stops at
        // the cohort's checkpoint rather than committing the next request in the same transaction.
        // With nothing left to open the call is unbounded.
        uint256 entries = expectedCount / boxesPerOrder;
        uint256 allowance = budget == 2 ? _drainBudget(index, 1) : entries != 0 ? _drainBudget(index, entries) : 0;
        vm.recordLogs();
        vm.prank(caller);
        (bool ok, bytes memory ret) = allowance == 0
            ? address(game).call(abi.encodeWithSignature("mineFlip()"))
            : address(game).call{gas: allowance}(abi.encodeWithSignature("mineFlip()"));
        uint256 reward;
        if (ok) {
            reward = _minerReward(vm.getRecordedLogs());
        } else {
            // Only a fully consumed cohort can leave the engine idle.
            assertEq(expectedCount, 0, "the engine had work while boxes remained");
            assertEq(bytes4(ret), bytes4(keccak256("NoWork()")), "an idle engine reports NoWork");
        }
        assertEq((_drained(index) - drainedBefore) * boxesPerOrder, expectedCount, "exact number of consumed boxes");
        assertEq(_writeSide(index ^ 1), writeSide, "unrevealed next-index entries survive old-index opening");
        assertEq(game.nextPrizePoolView(), next, "ordinary reward does not spend ticket backing");
        assertEq(game.futurePrizePoolView(), future, "ordinary reward does not spend live ETH inventory");
        assertEq(game.currentPrizePoolView(), current);
        assertEq(game.claimablePoolView(), liability);
        assertEq(game.claimableWinningsOf(caller), 0, "third-party keeper receives no owner ETH");
        assertEq(sdgnrs.balanceOf(caller), 0, "third-party keeper receives no owner sDGNRS");
        assertEq(coinflip.coinflipAmount(caller), callerFlip + reward, "the keeper's only FLIP is its measured miner reward");
    }

    function _run(uint48 index, uint256[2] memory orders, uint256 count, uint256 word, bool daily, bool perturb)
        private
        returns (bytes32 outcome)
    {
        if (daily) {
            vm.warp(block.timestamp + 1 days);
            _requestDaily();
        } else {
            // The owners' pending ETH clears the threshold: the engine's mid-day request.
            game.mineFlip();
        }
        _assertOrders(index, orders, false);
        assertEq(_word(index), 0);
        uint256 request = mockVRF.lastRequestId();
        assertGt(request, 0);
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        assertFalse(fulfilled);
        vm.prank(KEEPER_ONE);
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
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
        (Outcome memory alice, bool okA) = _reference(word, index, posA, game.walletIdOf(ALICE), count, inventory);
        (Outcome memory bob, bool okB) =
            _reference(word, index, posB, game.walletIdOf(BOB), count, inventory - alice.dgnrs);
        assertTrue(okA && okB, "every committed box stays inside the reference's scope");
        if (count == 2) {
            assertGt(alice.entries[3], 0, "known Alice ticket roll exercised");
            assertGt(bob.entries[0], 0, "known Bob ticket roll exercised");
            assertGt(alice.dgnrs, 0, "known mega-tier sDGNRS roll exercised");
            assertGt(bob.dgnrs, 0, "second owner sDGNRS roll exercised");
            assertNotEq(
                bob.dgnrs,
                _dgnrs(_seed(word, index, posB, game.walletIdOf(BOB), 1), inventory),
                "fixture distinguishes live from stale inventory"
            );
        } else {
            assertGt(alice.flip, 0, "known flat FLIP branch exercised");
            assertGt(bob.normal, 0, "known pass branch exercised");
        }
        Balance memory beforeAlice = _balance(ALICE);
        Balance memory beforeBob = _balance(BOB);
        if (perturb) {
            _open(2, KEEPER_ONE, count, index, count);
            _assertOrders(index, orders, true); // first owner consumed exactly once; budget break preserves Bob
            _assertDelta(ALICE, beforeAlice, alice);
            Outcome memory none;
            _assertDelta(BOB, beforeBob, none);
            assertEq(_pool(), inventory - alice.dgnrs, "first owner's actual pool debit");
            _perturb(index, orders, true);
            // New purchases can change FLIP stake and queues legitimately; snapshot those
            // writes separately so the second open is graded only for its own rewards.
            beforeAlice = _balance(ALICE);
            beforeBob = _balance(BOB);
            _open(2, KEEPER_TWO, count, index, count);
            _assertDelta(ALICE, beforeAlice, none);
            _assertDelta(BOB, beforeBob, bob);
        } else {
            _open(1000, KEEPER_TWO, count * 2, index, count);
            _assertDelta(ALICE, beforeAlice, alice);
            _assertDelta(BOB, beforeBob, bob);
        }
        assertTrue(_spent(index, posA) && _spent(index, posB), "both entries spent");
        assertEq(_entry(index, posA), orders[0], "settlement never rewrites an entry");
        assertEq(_entry(index, posB), orders[1], "settlement never rewrites an entry");
        assertEq(
            _pool(), inventory - alice.dgnrs - bob.dgnrs, "actual pool debit equals both independently priced awards"
        );
        assertEq(_word(index), word, "consumption cannot alter the commitment");
        assertEq(_word((index ^ 1)), 0);
        beforeAlice = _balance(ALICE);
        beforeBob = _balance(BOB);
        _open(1000, KEEPER_ONE, 0, index, count);
        Outcome memory zero;
        _assertDelta(ALICE, beforeAlice, zero);
        _assertDelta(BOB, beforeBob, zero);
        outcome = keccak256(abi.encode(alice, bob));
    }

    function _compare(bool daily, uint256 count) private {
        (uint48 index, uint256[2] memory orders) = _prepare(count);
        uint256 word = _findWord(index, count);
        uint256 snapshot = vm.snapshotState();
        bytes32 baseline = _run(index, orders, count, word, daily, false);
        assertTrue(vm.revertToState(snapshot));
        bytes32 attacked = _run(index, orders, count, word, daily, true);
        assertEq(attacked, baseline, "fixed draws retain payout identity under allowed public perturbations");
    }

    function testMiddayTicketAndSequentialDgnrsBinding() public {
        _compare(false, 2);
    }

    function testDailyTicketAndSequentialDgnrsBinding() public {
        _compare(true, 2);
    }

    function testMiddayFlipAndPassBinding() public {
        _compare(false, 1);
    }

    function testDailyFlipAndPassBinding() public {
        _compare(true, 1);
    }
}
