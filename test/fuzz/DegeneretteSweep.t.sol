// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {DegeneretteReference as Ref} from "../helpers/DegeneretteReference.sol";

/// @title DegeneretteSweep -- queued Degenerette bets resolve inside the box-open sweep.
/// @notice A bet is one word appended to degeneretteQueue[index]; its id is the queue
///         position + 1. The human-box sweep (openHumanBoxes, reached by mineFlip and
///         openBoxes) resolves every bet queued at an index after that index's box entries,
///         priced per bet in walk units and resumable mid-queue. This suite owns:
///
///         1. PLACEMENT: one word per bet with the documented layout; whole stake units only.
///         2. EQUIVALENCE: sweeping a queue pays exactly what resolving the same bets by hand
///            pays, owner by owner, including across calls the budget splits.
///         3. SKIPS: a bet resolved by hand is skipped by the sweep and never paid twice.
///         4. EVENT: DegeneretteResolved carries every spin as five packed bytes.
///         5. FROZEN POOL: the sweep holds the queue while the prize pool is frozen.
///         6. KEEPER: a plain mineFlip() resolves the queue and pays the box-open bounty.
///
///         Callees the sweep reaches, driven here: IDegenerusCoin.mintForGame (the owner FLIP
///         flush), ICoinflip.creditFlip + IDegenerusAffiliate.getReferrer (the affiliate leg of
///         a high-match ETH spin) and IsDGNRS.poolBalance / IsDGNRS.transferFromPool (the S>=7
///         award). The record-bounty chain's IDegenerusCoin.mintForGame is driven by
///         BigRecordArming.
contract DegeneretteSweep is DeployProtocol {
    uint256 private constant LR_PACKED_SLOT = 33;
    uint256 private constant LR_WORD_SLOT = 34;
    uint256 private constant PRIZE_POOLS_SLOT = 2;
    uint256 private constant FROZEN_BIT = uint256(1) << 208; // slot 0, byte 26

    uint8 private constant ETH = 0;
    uint8 private constant FLIP = 1;
    uint8 private constant SYMBOL = 9;
    uint48 private constant IDX = 1;

    bytes32 private constant PLACED_SIG = keccak256("DegeneretteBetPlaced(address,uint32,uint64,uint256)");
    bytes32 private constant RESOLVED_SIG =
        keccak256("DegeneretteResolved(address,uint32,uint64,uint256,uint32,bytes)");
    bytes32 private constant MINER_BOUNTY_SIG = keccak256("MinerBounty(uint8,address,uint256)");

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
        coin.mintForGame(alice, 1_000_000 ether);
        coin.mintForGame(bob, 1_000_000 ether);
        vm.stopPrank();
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    function _setActiveIndex(uint48 idx) private {
        uint256 lr = uint256(vm.load(address(game), bytes32(LR_PACKED_SLOT)));
        vm.store(address(game), bytes32(LR_PACKED_SLOT), bytes32((lr & ~uint256(0xFFFFFFFFFFFF)) | idx));
    }

    function _landWord(uint48 idx, uint256 word) private {
        vm.store(address(game), keccak256(abi.encode(uint256(idx), LR_WORD_SLOT)), bytes32(word));
        _setActiveIndex(idx + 1);
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
        _place(alice, FLIP, 200 ether, 15);
        _place(bob, FLIP, 100 ether, 3);
        _place(bob, ETH, 0.05 ether, 1);
        _place(alice, ETH, 0.02 ether, 7);
        _place(bob, FLIP, 1_000 ether, 15);
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

    function _resolveAllByHand(uint64 count) private {
        uint64[] memory ids = new uint64[](count);
        for (uint64 i; i < count; ++i) ids[i] = i + 1;
        game.resolveDegeneretteBets(IDX, ids);
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
        _place(bob, FLIP, 200 ether, 2);
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

        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        game.placeDegeneretteBet(address(0), FLIP, 100.5 ether, 1, SYMBOL);

        _place(alice, FLIP, 101 ether, 1); // any whole FLIP is fine
        assertEq((game.degeneretteBetInfo(IDX, 1) >> 188) & type(uint64).max, 101, "whole FLIP accepted");
    }

    // =========================================================================
    // 2. Equivalence with hand resolution
    // =========================================================================

    function testFuzz_SweepPaysExactlyWhatHandResolutionPays(uint256 word) public {
        vm.assume(word != 0);
        _placeMixedQueue();
        _landWord(IDX, word);

        uint256 snap = vm.snapshotState();
        vm.recordLogs();
        _resolveAllByHand(6);
        uint256[] memory byHand = _resolvedPayouts(vm.getRecordedLogs());
        Fingerprint memory handPrint = _fingerprint();
        vm.revertToState(snap);

        vm.recordLogs();
        game.openBoxes(type(uint256).max);
        uint256[] memory swept = _resolvedPayouts(vm.getRecordedLogs());
        _assertSame(handPrint, _fingerprint());

        assertEq(swept.length, byHand.length, "resolved count");
        for (uint256 i; i < swept.length; ++i) assertEq(swept[i], byHand[i], "per-bet id/payout");
        for (uint64 id = 1; id <= 6; ++id) assertEq(game.degeneretteBetInfo(IDX, id), 0, "bet zeroed");
        assertTrue(game.boxIndexComplete(IDX), "frontier passed the index");
    }

    function testSweepResumesAcrossCallsWithoutPayingTwice() public {
        for (uint256 i; i < 12; ++i) _place(i % 2 == 0 ? alice : bob, FLIP, 300 ether, 15);
        _landWord(IDX, uint256(keccak256("sweep_resume_word")));

        uint256 snap = vm.snapshotState();
        _resolveAllByHand(12);
        Fingerprint memory handPrint = _fingerprint();
        vm.revertToState(snap);

        // Each FLIP 15-spin bet weighs 4 + 15 = 19 units; openBoxes(3) hands the human sweep at
        // most 45 (less whatever the afking scan and index header take), so no call fits more
        // than two and the queue drains over several calls.
        uint256 calls;
        uint256 resolvedTotal;
        while (!game.boxIndexComplete(IDX)) {
            uint256 n = game.openBoxes(3);
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
    // 3. Hand-resolved bets are skipped
    // =========================================================================

    function testHandResolvedBetIsSkippedNotRepaid() public {
        _placeMixedQueue();
        _landWord(IDX, uint256(keccak256("sweep_skip_word")));

        uint256 snap = vm.snapshotState();
        _resolveAllByHand(6);
        Fingerprint memory handPrint = _fingerprint();
        vm.revertToState(snap);

        uint64[] memory ids = new uint64[](2);
        ids[0] = 2;
        ids[1] = 5;
        game.resolveDegeneretteBets(IDX, ids);
        assertEq(game.degeneretteBetInfo(IDX, 2), 0, "resolved by hand");

        uint256 n = game.openBoxes(type(uint256).max);
        assertEq(n, 4, "the sweep resolves only the four still queued");
        _assertSame(handPrint, _fingerprint());
    }

    function testHandResolutionGuards() public {
        _place(alice, FLIP, 100 ether, 1);
        uint64[] memory ids = new uint64[](1);
        ids[0] = 1;
        vm.expectRevert(bytes4(keccak256("RngNotReady()")));
        game.resolveDegeneretteBets(IDX, ids);

        _landWord(IDX, uint256(keccak256("guard_word")));
        ids[0] = 0;
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        game.resolveDegeneretteBets(IDX, ids);
        ids[0] = 2;
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        game.resolveDegeneretteBets(IDX, ids);

        ids[0] = 1;
        game.resolveDegeneretteBets(IDX, ids);
        vm.expectRevert(bytes4(keccak256("InvalidBet()")));
        game.resolveDegeneretteBets(IDX, ids);
    }

    // =========================================================================
    // 4. The packed per-bet event
    // =========================================================================

    function testFuzz_ResolvedEventCarriesEverySpin(uint256 word) public {
        vm.assume(word != 0);
        _place(alice, ETH, 0.01 ether, 25);
        _landWord(IDX, word);
        vm.recordLogs();
        game.openBoxes(type(uint256).max);
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
                (uint8 score, uint8 gold) = Ref.score(p, Ref.house(word, uint32(IDX), s, false), SYMBOL >> 3);
                uint256 o = uint256(s) * 5;
                uint32 packedTraits = (uint32(uint8(spins[o])) << 24) | (uint32(uint8(spins[o + 1])) << 16)
                    | (uint32(uint8(spins[o + 2])) << 8) | uint32(uint8(spins[o + 3]));
                assertEq(packedTraits, p, "player traits");
                assertEq(uint8(spins[o + 4]), score | (gold << 4), "score | gold << 4");
            }
        }
        assertTrue(found, "one resolved event");
    }

    // =========================================================================
    // 5. Frozen pool holds the queue
    // =========================================================================

    function testSweepHoldsQueueWhilePoolFrozen() public {
        _placeMixedQueue();
        _landWord(IDX, uint256(keccak256("frozen_word")));
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        vm.store(address(game), bytes32(0), bytes32(slot0 | FROZEN_BIT));

        assertEq(game.openBoxes(type(uint256).max), 0, "nothing resolves while frozen");
        assertFalse(game.boxIndexComplete(IDX), "frontier holds at the queue");
        assertTrue(game.degeneretteBetInfo(IDX, 1) != 0, "bet still queued");

        vm.store(address(game), bytes32(0), bytes32(slot0));
        assertEq(game.openBoxes(type(uint256).max), 6, "resolves once the freeze lifts");
        assertTrue(game.boxIndexComplete(IDX), "frontier passes");
    }

    // =========================================================================
    // 6. Keeper path and the reached callees
    // =========================================================================

    /// @dev A word whose spin 0 scores at least `minScore` for SYMBOL.
    function _wordScoring(uint8 minScore) private pure returns (uint256 word) {
        for (uint256 k; k < 200_000; ++k) {
            word = uint256(keccak256(abi.encodePacked("sweep_high_score", k)));
            (uint8 s,) = Ref.score(
                Ref.player(word, uint32(IDX), SYMBOL, 0, false), Ref.house(word, uint32(IDX), 0, false), SYMBOL >> 3
            );
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
        game.openBoxes(type(uint256).max);
        assertGt(sdgnrs.balanceOf(alice), dgnrsBefore, "S>=7 transferFromPool paid sDGNRS");
        assertEq(game.degeneretteBetInfo(IDX, 1), 0, "resolved by the sweep");
    }

    function testFlipWinFlushesThroughMintForGame() public {
        _place(bob, FLIP, 1_000 ether, 1);
        _landWord(IDX, _wordScoring(4));
        uint256 before = coin.balanceOf(bob);
        game.openBoxes(type(uint256).max);
        // The survival flip may zero the payout; either way the queue drains once.
        assertEq(game.degeneretteBetInfo(IDX, 1), 0, "resolved");
        assertGe(coin.balanceOf(bob), before, "mintForGame never debits");
    }

    /// @dev Settle today's advance 30+ minutes into the day so mineFlip takes its box-open leg.
    function _readyKeeperLeg() private {
        uint256 elapsed = (vm.getBlockTimestamp() - 82620) % 1 days;
        if (elapsed < 30 minutes) vm.warp(vm.getBlockTimestamp() + 30 minutes - elapsed);
        // dailyIdx (slot 0, bits 24..47) = today and ticketsFullyProcessed (bit 192) set.
        uint256 slot0 = uint256(vm.load(address(game), bytes32(0)));
        slot0 = (slot0 & ~(uint256(0xFFFFFF) << 24)) | (uint256(game.currentDayView()) << 24) | (uint256(1) << 192);
        vm.store(address(game), bytes32(0), bytes32(slot0));
        assertFalse(game.advanceDue(), "advance settled");
    }

    /// @dev Run mineFlip as `keeper`; return bets resolved and the box-open bounty paid.
    function _crank(address keeper) private returns (uint256 resolved, uint256 bounty) {
        vm.recordLogs();
        vm.prank(keeper);
        game.mineFlip();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == RESOLVED_SIG) ++resolved;
            if (logs[i].topics[0] == MINER_BOUNTY_SIG) {
                (uint8 kind, uint256 amount) = abi.decode(logs[i].data, (uint8, uint256));
                assertEq(kind, 2, "box-open bounty kind");
                assertEq(address(uint160(uint256(logs[i].topics[1]))), keeper, "paid to the keeper");
                bounty += amount;
            }
        }
    }

    /// @notice A plain mineFlip resolves the whole queue. Each resolved bet credits only a small
    ///         flat amount toward the bounty, so a short queue alone earns none: six bets credit
    ///         6 x 1,500 gas, under one knee step (15 walk units of 4,700 gas).
    function testMineFlipResolvesQueueWithOnlyTheFlatCredit() public {
        _placeMixedQueue();
        _landWord(IDX, uint256(keccak256("keeper_word")));
        _readyKeeperLeg();
        (uint256 resolved, uint256 bounty) = _crank(makeAddr("sweepKeeper"));
        assertEq(resolved, 6, "mineFlip resolved the whole queue");
        assertEq(bounty, 0, "six bets are under one knee step");
    }

    /// @notice A real backlog still pays the crank: 48 resolved bets credit 72,000 gas, just
    ///         past one knee step, which earns a fifth of the bounty unit.
    function testFlatCreditReachesOneKneeStepAtFortyEightBets() public {
        for (uint256 i; i < 48; ++i) _place(i % 2 == 0 ? alice : bob, FLIP, 100 ether, 1);
        _landWord(IDX, uint256(keccak256("keeper_word")));
        _readyKeeperLeg();
        (uint256 resolved, uint256 bounty) = _crank(makeAddr("sweepKeeper"));
        assertEq(resolved, 48, "one crank resolved the backlog");
        assertGt(bounty, 0, "a knee step of bet work earns the bounty");
    }
}
