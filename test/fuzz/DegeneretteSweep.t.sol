// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {RecyclingState} from "../helpers/RecyclingState.sol";

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title DegeneretteSweep -- queued Degenerette bets resolve inside the box-open sweep.
/// @notice A bet is one word appended to degeneretteQueue[index & 1]; its id is the queue
///         position + 1. mineFlip's Degenerette read-consumer stage resolves every bet queued
///         at an index after that index's box entries, admitted per bet against its gas bound
///         and resumable mid-queue. This suite owns:
///
///         1. PLACEMENT: one word per bet with the documented layout; whole stake units only.
///         2. EQUIVALENCE: a queue swept in one call resolves every bet in order, and sweeping
///            it across many small-budget calls pays exactly what one full-budget call pays.
///         3. EVENT: DegeneretteResolved carries every spin as five packed bytes.
///         4. FROZEN POOL: the sweep holds the queue while the prize pool is frozen.
///         5. KEEPER: a plain mineFlip() resolves the queue and pays the box-open bounty.
///
///         Callees the sweep reaches, driven here: IDegenerusCoin.mintForGame (the owner FLIP
///         flush), ICoinflip.creditFlip + IDegenerusAffiliate.getReferrer (the affiliate leg of
///         a high-match ETH spin) and IsDGNRS.poolBalance / IsDGNRS.transferFromPool (the S>=7
///         award). The record-bounty chain's IDegenerusCoin.mintForGame is driven by
///         BigRecordArming.
contract DegeneretteSweep is DeployProtocol {
    uint256 private constant LR_PACKED_SLOT = GameSlots.LOOTBOX_RNG_PACKED;
    uint256 private constant LR_WORD_SLOT = GameSlots.RNG_WORD_CURRENT;
    uint256 private constant PRIZE_POOLS_SLOT = GameSlots.PRIZE_POOLS_PACKED;
    uint256 private constant QUEUE_SLOT = GameSlots.DEGENERETTE_QUEUE; // degeneretteQueue mapping root
    uint256 private constant FROZEN_BIT = uint256(1) << 208; // slot 0, byte 26

    uint8 private constant ETH = 0;
    uint8 private constant FLIP = 1;
    uint8 private constant SYMBOL = 9;
    uint48 private constant IDX = 1;

    bytes32 private constant PLACED_SIG = keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)");
    bytes32 private constant RESOLVED_SIG =
        keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");
    bytes32 private constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");
    /// @dev Emitted by the unlock right after the freeze lifts.
    bytes32 private constant SNAPSHOT_SIG =
        keccak256("PrizePoolDailySnapshot(uint256,uint256,uint256,uint256,uint256,uint256,uint24)");

    address private alice;
    address private bob;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        alice = makeAddr("sweepAlice");
        bob = makeAddr("sweepBob");
        vm.deal(alice, 1_000 ether);
        vm.deal(bob, 1_000 ether);
        _setActiveIndex(IDX);
        _setFuturePool(1_000_000 ether);
        vm.startPrank(address(game));
        coin.mintForGame(alice, 1_000_000);
        coin.mintForGame(bob, 1_000_000);
        vm.stopPrank();
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _setActiveIndex(uint48 idx) private {
        RecyclingState.seedWriteBuffer(address(game), idx);
    }

    /// @dev Deliver and publish `word` for the sealed cohort at `idx`, as a fulfilled mid-day
    ///      request leaves it. The day itself is already sealed (dailyIdx = today, tickets drained),
    ///      so the delivered cohort's read consumers are the engine's only work and mineFlip stops
    ///      when the cohort completes instead of preparing the next day.
    function _landWord(uint48 idx, uint256 word) private {
        RecyclingState.seedWord(address(game), idx, bytes32(word));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
    }

    /// @dev Bets resolve as the Degenerette read consumer of the published word, reached only by
    ///      mineFlip. One unbounded call runs the cohort's whole consumer chain.
    function _resolveCohort() private {
        vm.prank(makeAddr("sweepCrank"));
        game.mineFlip();
    }

    /// @dev Resolved bets in a recorded log window.
    function _countResolved(Vm.Log[] memory logs) private pure returns (uint256 n) {
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == RESOLVED_SIG) ++n;
    }

    /// @dev One mineFlip given the smallest allowance that still resolves a bet: the engine admits a
    ///      bet only when the remaining allowance covers its declared bound, so at the minimum the
    ///      call resolves exactly the next bet. Found by bisection over snapshots of the same state.
    function _crankOneBet() private returns (uint256 resolved, uint256 supplied) {
        uint256 lo = 300_000;
        uint256 hi = 30_000_000;
        while (hi - lo > 1_000) {
            uint256 mid = (lo + hi) / 2;
            uint256 snap = vm.snapshotState();
            vm.recordLogs();
            vm.prank(makeAddr("sweepCrank"));
            (bool ok,) = address(game).call{gas: mid}(abi.encodeWithSignature("mineFlip()"));
            uint256 n = ok ? _countResolved(vm.getRecordedLogs()) : 0;
            vm.revertToStateAndDelete(snap);
            if (n != 0) hi = mid;
            else lo = mid;
        }
        supplied = hi;
        resolved = _crankWith(hi);
    }

    function _crankWith(uint256 supplied) private returns (uint256 resolved) {
        vm.recordLogs();
        vm.prank(makeAddr("sweepCrank"));
        game.mineFlip{gas: supplied}();
        resolved = _countResolved(vm.getRecordedLogs());
    }

    function _setFuturePool(uint256 future) private {
        uint256 pools = uint256(vm.load(address(game), bytes32(PRIZE_POOLS_SLOT)));
        pools = (pools & ((uint256(1) << 128) - 1)) | (future << 128);
        vm.store(address(game), bytes32(PRIZE_POOLS_SLOT), bytes32(pools));
    }

    function _place(address who, uint8 currency, uint128 perSpin, uint8 spins) private {
        vm.prank(who);
        game.placeDegeneretteBet{value: currency == ETH ? uint256(perSpin) * spins : 0}(
            address(0), currency, perSpin, spins, SYMBOL
        );
    }

    /// @dev A mixed queue: both owners, both currencies, short and long bets, owner runs.
    function _placeMixedQueue() private {
        _place(alice, ETH, 0.01 ether, 25);
        _place(alice, FLIP, 200, 15);
        _place(bob, FLIP, 100, 3);
        _place(bob, ETH, 0.05 ether, 1);
        _place(alice, ETH, 0.02 ether, 7);
        _place(bob, FLIP, 1_000, 15);
    }

    struct Fingerprint {
        uint256 aliceFlip;
        uint256 bobFlip;
        uint256 aliceEth;
        uint256 bobEth;
        uint256 claimablePool;
        uint256 future;
        uint256 aliceDgnrs;
        uint256 bobDgnrs;
    }

    function _fingerprint() private view returns (Fingerprint memory f) {
        f.aliceFlip = coin.balanceOf(alice);
        f.bobFlip = coin.balanceOf(bob);
        f.aliceEth = game.claimableWinningsOf(alice);
        f.bobEth = game.claimableWinningsOf(bob);
        f.claimablePool = game.claimablePoolView();
        f.future = game.futurePrizePoolView();
        f.aliceDgnrs = sdgnrs.balanceOf(alice);
        f.bobDgnrs = sdgnrs.balanceOf(bob);
    }

    function _assertSame(Fingerprint memory a, Fingerprint memory b) private pure {
        assertEq(a.aliceFlip, b.aliceFlip, "alice FLIP");
        assertEq(a.bobFlip, b.bobFlip, "bob FLIP");
        assertEq(a.aliceEth, b.aliceEth, "alice ETH claimable");
        assertEq(a.bobEth, b.bobEth, "bob ETH claimable");
        assertEq(a.claimablePool, b.claimablePool, "claimablePool");
        assertEq(a.future, b.future, "future pool");
        assertEq(a.aliceDgnrs, b.aliceDgnrs, "alice sDGNRS");
        assertEq(a.bobDgnrs, b.bobDgnrs, "bob sDGNRS");
    }

    /// @dev Resolve the whole queue at IDX in one full-budget sweep call — the only surviving
    ///      resolution entry point. Used as the one-shot reference against which a many-call,
    ///      small-budget sweep is compared for budget-split invariance.
    function _resolveAllInOneSweep() private {
        _resolveCohort();
    }

    /// @dev Resolved (betId => totalPayout) pairs in log order.
    function _resolvedPayouts(Vm.Log[] memory logs) private pure returns (uint256[] memory out) {
        uint256 n;
        for (uint256 i; i < logs.length; ++i) if (logs[i].topics[0] == RESOLVED_SIG) ++n;
        out = new uint256[](n * 2);
        n = 0;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != RESOLVED_SIG) continue;
            (uint256 total,,) = abi.decode(logs[i].data, (uint256, uint32, bytes));
            out[n++] = uint256(logs[i].topics[3]);
            out[n++] = total;
        }
    }

    // =========================================================================
    // 1. Placement
    // =========================================================================

    function testPlacementQueuesOneWordPerBet() public {
        vm.recordLogs();
        _place(alice, ETH, 0.01 ether, 3);
        _place(bob, FLIP, 200, 2);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 seen;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != PLACED_SIG) continue;
            ++seen;
            assertEq(uint256(logs[i].topics[2]), IDX, "placed at the active index");
            assertEq(uint256(logs[i].topics[3]), seen, "bet id = queue position + 1");
            assertEq(abi.decode(logs[i].data, (uint256)), game.degeneretteBetInfo(IDX, uint64(seen)), "event word");
        }
        assertEq(seen, 2, "two placements");

        uint256 a = game.degeneretteBetInfo(IDX, 1);
        assertEq(address(uint160(a)), alice, "owner");
        assertEq((a >> 160) & 0x1F, SYMBOL, "symbol");
        assertEq((a >> 165) & 0x1F, 3, "spins");
        assertEq((a >> 170) & 1, ETH, "currency");
        assertEq((a >> 171) & 1, 0, "no record");
        assertEq((a >> 188) & type(uint64).max, 0.01 ether / 1 gwei, "ETH stake in gwei");
        assertEq(a >> 252, 0, "reserved bits");

        uint256 b = game.degeneretteBetInfo(IDX, 2);
        assertEq(address(uint160(b)), bob, "second owner");
        assertEq((b >> 170) & 1, FLIP, "FLIP currency");
        assertEq((b >> 188) & type(uint64).max, 200, "FLIP stake in whole FLIP");
        assertEq(game.degeneretteBetInfo(IDX, 3), 0, "past the queue reads zero");
        assertEq(game.degeneretteBetInfo(IDX, 0), 0, "id zero reads zero");
    }

    function testPlacementRejectsPartialUnits() public {
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        game.placeDegeneretteBet{value: 0.01 ether + 1}(address(0), ETH, 0.01 ether + 1, 1, SYMBOL);

        _place(alice, FLIP, 101, 1); // any whole FLIP is fine
        assertEq((game.degeneretteBetInfo(IDX, 1) >> 188) & type(uint64).max, 101, "whole FLIP accepted");
    }

    // =========================================================================
    // 2. Equivalence
    // =========================================================================

    /// @notice The sweep resolves every bet in a fuzzed-word mixed queue in one unbounded mineFlip
    ///         call, strictly in queue order, zeroing each bet and completing the index's
    ///         frontier. (Sweep resolution is now the only entry point, so there is no second
    ///         independent path left to cross-check payouts against; this asserts the sweep's
    ///         own resolution shape directly instead.)
    function testFuzz_SweepResolvesFullMixedQueueInOrder(uint256 word) public {
        vm.assume(word > 1);
        _placeMixedQueue();
        _landWord(IDX, word);

        vm.recordLogs();
        _resolveCohort();
        uint256[] memory swept = _resolvedPayouts(vm.getRecordedLogs());

        assertEq(swept.length, 12, "six resolved bets, id+payout pairs");
        for (uint256 i; i < 6; ++i) assertEq(swept[i * 2], i + 1, "resolved in queue order");
        for (uint64 id = 1; id <= 6; ++id) assertEq(game.degeneretteBetInfo(IDX, id), 0, "bet zeroed");
        assertTrue(game.boxIndexComplete(IDX), "frontier passed the index");
    }

    function testSweepResumesAcrossCallsWithoutPayingTwice() public {
        for (uint256 i; i < 12; ++i) _place(i % 2 == 0 ? alice : bob, FLIP, 300, 15);
        _landWord(IDX, uint256(keccak256("sweep_resume_word")));

        uint256 snap = vm.snapshotState();
        _resolveAllInOneSweep();
        Fingerprint memory handPrint = _fingerprint();
        vm.revertToState(snap);

        // The walk-unit budget became a gas allowance (60d31f775: each bet is admitted only while
        // the remaining allowance covers its declared bound). The first call gets the smallest
        // allowance that resolves a bet at all, so it resolves exactly one; every later call reuses
        // that same allowance, which no longer has to cover the earlier stages, so no call fits
        // more than two and the queue drains over several calls.
        (uint256 calls, uint256 resolvedTotal) = (1, 0);
        (uint256 first, uint256 allowance) = _crankOneBet();
        assertEq(first, 1, "the starved first call resolves exactly one bet");
        resolvedTotal = first;
        emit log_named_uint("per-call allowance", allowance);
        while (!game.boxIndexComplete(IDX)) {
            uint256 n = _crankWith(allowance);
            assertGt(n, 0, "every call makes progress");
            assertLe(n, 2, "the budget splits the queue");
            resolvedTotal += n;
            ++calls;
            require(calls < 20, "sweep stalled");
        }
        assertEq(resolvedTotal, 12, "each bet resolved exactly once");
        assertGe(calls, 6, "the budget split the queue across calls");
        _assertSame(handPrint, _fingerprint());
    }


    // =========================================================================
    // 3. The packed per-bet event
    // =========================================================================

    function testFuzz_ResolvedEventCarriesEverySpin(uint256 word) public {
        vm.assume(word > 1);
        _place(alice, ETH, 0.01 ether, 25);
        _landWord(IDX, word);
        vm.recordLogs();
        _resolveCohort();
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != RESOLVED_SIG) continue;
            found = true;
            assertEq(address(uint160(uint256(logs[i].topics[1]))), alice, "owner topic");
            assertEq(uint256(logs[i].topics[2]), IDX, "index topic");
            assertEq(uint256(logs[i].topics[3]), 1, "bet id topic");
            (, uint32 resultTraits, bytes memory spins) = abi.decode(logs[i].data, (uint256, uint32, bytes));
            assertEq(resultTraits, Ref.house(word, uint32(IDX), 0, false), "spin-0 house traits");
            assertEq(spins.length, 25 * 5, "five bytes per spin");
            for (uint8 s; s < 25; ++s) {
                uint32 p = Ref.player(word, uint32(IDX), SYMBOL, s, false);
                (uint8 score, uint8 wilds) = Ref.score(p, Ref.house(word, uint32(IDX), s, false));
                uint256 o = uint256(s) * 5;
                uint32 packedTraits = (uint32(uint8(spins[o])) << 24) | (uint32(uint8(spins[o + 1])) << 16)
                    | (uint32(uint8(spins[o + 2])) << 8) | uint32(uint8(spins[o + 3]));
                assertEq(packedTraits, p, "player traits");
                assertEq(uint8(spins[o + 4]), score | (wilds << 4), "score | wilds << 4");
            }
        }
        assertTrue(found, "one resolved event");
    }

    // =========================================================================
    // 4. Frozen pool holds the queue
    // =========================================================================

    /// @dev Only the reachable freeze is seeded (387dd5d96 dropped the frozen-pool refusal as
    ///      unreachable): the daily request sets the freeze together with the daily lock, the
    ///      unlock clears both, and the Degenerette stage needs the lock released. So while the
    ///      pool is frozen the consumer stage is closed and nothing resolves; the queue resolves
    ///      only after the real unlock lifts the freeze.
    function testSweepHoldsQueueWhilePoolFrozen() public {
        _placeMixedQueue();
        uint256 before = mockVRF.lastRequestId();
        for (uint256 i; i < 64 && mockVRF.lastRequestId() == before; ++i) game.mineFlip();
        uint256 reqId = mockVRF.lastRequestId();
        assertTrue(reqId != before, "the daily request went out");
        assertTrue(_poolFrozen(), "the daily request froze the pool");
        assertTrue(game.rngLocked(), "the freeze comes with the daily lock");
        assertEq(RecyclingState.readBuffer(address(game)), IDX, "the queued cohort is sealed for this word");

        // Frozen and waiting on the word: the consumer stage is closed and the queue holds.
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Wait), "waiting on the word");
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.mineFlip();
        assertTrue(game.degeneretteBetInfo(IDX, 1) != 0, "bet still queued");
        assertFalse(game.boxIndexComplete(IDX), "frontier holds at the queue");

        // Deliver the word and crank. Every step that starts frozen starts locked and off the
        // Degenerette stage, and no bet resolves before the unlock's snapshot lifts the freeze.
        mockVRF.fulfillRandomWords(reqId, uint256(keccak256("frozen_word")));
        vm.recordLogs();
        uint256 frozenSteps;
        for (uint256 i; i < 64 && !game.boxIndexComplete(IDX); ++i) {
            if (_poolFrozen()) {
                ++frozenSteps;
                assertTrue(game.rngLocked(), "a frozen pool holds the daily lock");
                assertTrue(
                    game.nextMinerAction() != uint8(DegenerusGameStorage.MinerAction.Degenerette),
                    "the queue is not work while frozen"
                );
            }
            vm.prank(makeAddr("sweepCrank"));
            game.mineFlip();
        }
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGt(frozenSteps, 0, "fixture: the delivered day cranked while still frozen");
        assertFalse(_poolFrozen(), "the unlock lifted the freeze");
        assertFalse(game.rngLocked(), "and released the lock");
        assertTrue(game.boxIndexComplete(IDX), "frontier passes");

        uint256 unfrozenAt = type(uint256).max;
        uint256 resolved;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(game)) continue;
            if (logs[i].topics[0] == SNAPSHOT_SIG && unfrozenAt == type(uint256).max) unfrozenAt = i;
            if (logs[i].topics[0] == RESOLVED_SIG) {
                assertLt(unfrozenAt, i, "nothing resolves while frozen");
                ++resolved;
            }
        }
        assertEq(resolved, 6, "resolves once the freeze lifts");
        for (uint64 id = 1; id <= 6; ++id) assertEq(game.degeneretteBetInfo(IDX, id), 0, "bet zeroed");
    }

    function _poolFrozen() private view returns (bool) {
        return uint256(vm.load(address(game), bytes32(0))) & FROZEN_BIT != 0;
    }

    // =========================================================================
    // 5. Keeper path and the reached callees
    // =========================================================================

    /// @dev A word whose spin 0 scores at least `minScore` for SYMBOL.
    function _wordScoring(uint8 minScore) private pure returns (uint256 word) {
        for (uint256 k; k < 200_000; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_high_score", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false));
            if (s >= minScore) return word;
        }
        revert("no word");
    }

    function testHighScoreEthSpinReachesAffiliateAndDgnrsLegs() public {
        _place(alice, ETH, 0.01 ether, 1);
        _landWord(IDX, _wordScoring(7));
        uint256 dgnrsBefore = sdgnrs.balanceOf(alice);
        vm.expectCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.poolBalance.selector));
        vm.expectCall(address(coinflip), abi.encodeWithSelector(coinflip.creditFlip.selector));
        _resolveCohort();
        assertGt(sdgnrs.balanceOf(alice), dgnrsBefore, "S>=7 transferFromPool paid sDGNRS");
        assertEq(game.degeneretteBetInfo(IDX, 1), 0, "resolved by the sweep");
    }

    function testFlipWinFlushesThroughMintForGame() public {
        _place(bob, FLIP, 1_000, 1);
        _landWord(IDX, _wordScoring(4));
        uint256 before = coin.balanceOf(bob);
        _resolveCohort();
        // The survival flip may zero the payout; either way the queue drains once.
        assertEq(game.degeneretteBetInfo(IDX, 1), 0, "resolved");
        assertGe(coin.balanceOf(bob), before, "mintForGame never debits");
    }

    /// @dev 30+ minutes into the sealed day, with the delivered cohort's read consumers as the only
    ///      engine work. A nonzero base fee prices the bounty, which mineFlip pays in FLIP on the
    ///      gas a call measured above its unpaid first MIN_REWARDED_GAS (72fc06f6c).
    function _readyKeeperLeg() private {
        uint256 elapsed = (vm.getBlockTimestamp() - 82620) % 1 days;
        if (elapsed < 30 minutes) vm.warp(vm.getBlockTimestamp() + 30 minutes - elapsed);
        vm.fee(1 gwei);
        assertTrue(game.boxesPending(), "only the delivered cohort's read consumers remain");
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.HumanBoxes), "advance settled");
    }

    bytes32 private constant MINER_WORK_SIG = keccak256("MinerWork(address,uint8,uint256,uint256)");

    /// @dev Run mineFlip as `keeper`; return bets resolved, the bounty paid and the measured gas.
    function _crank(address keeper) private returns (uint256 resolved, uint256 bounty, uint256 used) {
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RESOLVED_SIG) ++resolved;
            if (logs[i].topics[0] == MINER_BOUNTY_SIG) {
                (uint8 kind, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                // One miner bounty kind for every paid mineFlip (60d31f775 retired the per-category
                // box-open kind 2 with its flat per-bet credit).
                assertEq(kind, 1, "miner bounty kind");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), keeper, "paid to the keeper");
                bounty += amount;
            }
            if (logs[i].topics[0] == MINER_WORK_SIG) (,used,) = abi.decode(logs[i].data, (uint8, uint256, uint256));
        }
        emit log_named_uint("measured mineFlip execution gas", used);
        emit log_named_uint("bounty paid", bounty);
    }

    /// @notice A plain mineFlip resolves the whole queue. Pay is priced on measured gas, and the
    ///         first MIN_REWARDED_GAS of every call is unpaid (72fc06f6c, replacing the flat
    ///         1,500-gas per-bet credit and its knee steps), so a short queue alone earns none.
    function testMineFlipResolvesShortQueueInsideTheUnpaidFirstMillion() public {
        _placeMixedQueue();
        _landWord(IDX, uint256(keccak256("keeper_word")));
        _readyKeeperLeg();
        (uint256 resolved, uint256 bounty, uint256 used) = _crank(makeAddr("sweepKeeper"));
        assertEq(resolved, 6, "mineFlip resolved the whole queue");
        assertLe(used, MineFlipGas.MIN_REWARDED_GAS, "six bets fit the unpaid first million");
        assertEq(bounty, 0, "six bets earn no bounty");
    }

    /// @notice A real backlog still pays the crank: resolving 120 bets measures past the unpaid
    ///         first MIN_REWARDED_GAS (48 bets measured ~0.68M, inside it), and the excess is paid.
    function testBacklogPastTheUnpaidFirstMillionEarnsTheBounty() public {
        for (uint256 i; i < 120; ++i) _place(i % 2 == 0 ? alice : bob, FLIP, 100, 1);
        _landWord(IDX, uint256(keccak256("keeper_word")));
        _readyKeeperLeg();
        (uint256 resolved, uint256 bounty, uint256 used) = _crank(makeAddr("sweepKeeper"));
        assertEq(resolved, 120, "one crank resolved the backlog");
        assertGt(used, MineFlipGas.MIN_REWARDED_GAS, "the backlog measures past the unpaid first million");
        assertGt(bounty, 0, "the measured excess earns the bounty");
    }

    /// @notice A Degenerette walk that resolves nothing still reports the slots it stepped past
    ///         (here ten zeroed bet slots) as progress, so mineFlip commits the walk and finishes
    ///         the cohort instead of refusing the call as workless.
    function testSweepThatOpensNothingStillProgresses() public {
        for (uint256 i; i < 10; ++i) _place(alice, FLIP, 100, 1);
        _landWord(IDX, uint256(keccak256("hole_word")));
        // Holes ahead of the cursor: zero the ten queued words in place, leaving the cursor
        // where it stands, to reach the walk's zeroed-bet skip.
        uint256 base = uint256(keccak256(abi.encode(keccak256(abi.encode(uint256(IDX), QUEUE_SLOT)))));
        for (uint256 i; i < 10; ++i) vm.store(address(game), bytes32(base + i), bytes32(0));
        for (uint64 id = 1; id <= 10; ++id) assertEq(game.degeneretteBetInfo(IDX, id), 0, "hole forged");
        assertFalse(game.boxIndexComplete(IDX), "the holes sit ahead of the cursor");
        vm.recordLogs();
        vm.prank(makeAddr("sweepCrank"));
        game.mineFlip();
        assertEq(_countResolved(vm.getRecordedLogs()), 0, "holes open nothing");
        assertTrue(game.boxIndexComplete(IDX), "the walk stepped past every zeroed slot");
        assertTrue(game.rngComplete(), "the cohort completed behind the walk");
    }
}
