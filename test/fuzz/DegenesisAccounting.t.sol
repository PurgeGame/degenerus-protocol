// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {GameSlots} from "../helpers/GameSlots.sol";
import {IDegenerusGameDegenesisModule} from "../../contracts/interfaces/IDegenerusGameModules.sol";
import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";

/// @title DegenesisAccounting -- ETH obligations of Degenesis buys and the cohort split (check 8)
/// @notice A buy adds its applied price to claimablePool and nothing else; a claimable or prepaid
///         buy first debits its source, so claimablePool is unchanged; overpay lands in the
///         payer's AFKing; frozen pending pools are untouched. The split, at the first request
///         after the cohort's day, moves V/2 out of claimablePool into equal future and insurance shares
///         and reclassifies V/4 each to the Vault budget and sDGNRS AFKing, exact in wei.
///         Claimable balances are seeded with vm.store (ledger, claimablePool and ETH in tandem).
contract DegenesisAccounting is DegenesisFixture {
    address internal alice;
    uint32 internal aliceId;

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 0);
        aliceId = game.walletIdOf(alice);
        _earnCredit(alice, 50 ether);
        _drain();
        _driveDay(2);
    }

    struct Books {
        uint256 claimablePool;
        uint256 balance;
        uint256 next;
        uint256 future;
        uint256 pendingNext;
        uint256 pendingFuture;
        uint256 vaultBudget;
        uint256 sdgnrsAfking;
        uint256 unsplit;
        uint256 insurance;
    }

    function _books() internal view returns (Books memory b) {
        b.claimablePool = _claimablePool();
        b.balance = _gameBalance();
        b.next = _nextPool();
        b.future = _futurePool();
        b.pendingNext = _pendingNext();
        b.pendingFuture = _pendingFuture();
        b.vaultBudget = _vaultBudget();
        b.sdgnrsAfking = _afkingOf(SDGNRS_ID);
        b.unsplit = _unsplitVolume();
        b.insurance = _slot(GameSlots.YIELD_ACCUMULATOR);
    }

    function _assertPoolsUntouched(Books memory a, Books memory b) internal pure {
        assertEq(b.insurance, a.insurance, "insurance unchanged at purchase");
        assertEq(b.next, a.next, "live next untouched");
        assertEq(b.future, a.future, "live future untouched");
        assertEq(b.pendingNext, a.pendingNext, "pending next untouched");
        assertEq(b.pendingFuture, a.pendingFuture, "pending future untouched");
        assertEq(b.vaultBudget, a.vaultBudget, "Vault budget untouched until the split");
        assertEq(b.sdgnrsAfking, a.sdgnrsAfking, "sDGNRS AFKing untouched until the split");
    }

    function _assertSolvent() internal view {
        assertGe(_gameBalance(), _claimablePool(), "ETH + stETH covers claimablePool");
    }

    // ------------------------------------------------------------------ intake

    function test_FreshEthBuy_AddsExactlyAmountToClaimablePool() public {
        Books memory a = _books();
        _buyDegenesis(alice, 0.0123 ether);
        Books memory b = _books();
        assertEq(b.claimablePool, a.claimablePool + 0.0123 ether, "claimablePool += amount");
        assertEq(b.balance, a.balance + 0.0123 ether, "ETH in == amount");
        assertEq(b.unsplit, a.unsplit + 0.0123 ether, "held unsplit");
        _assertPoolsUntouched(a, b);
        _assertSolvent();
    }

    function test_ClaimableBuy_DebitsSourceThenHolds_PoolUnchanged() public {
        _seedClaimable(aliceId, 2 ether);
        Books memory a = _books();
        uint256 claimable = _claimableOf(aliceId);
        vm.prank(alice);
        game.buyDegenesisBox(0, 1 ether);
        Books memory b = _books();
        assertEq(claimable - _claimableOf(aliceId), 1 ether, "claimable debited");
        assertEq(b.claimablePool, a.claimablePool, "a reservation changes category only");
        assertEq(b.balance, a.balance, "no ETH moved");
        assertEq(b.unsplit, a.unsplit + 1 ether, "held unsplit");
        _assertPoolsUntouched(a, b);
        _assertSolvent();
    }

    function test_PrepaidBuy_DebitsAfkingThenHolds_PoolUnchanged() public {
        vm.deal(alice, 3 ether);
        vm.prank(alice);
        game.depositAfkingFunding{value: 3 ether}(aliceId);
        Books memory a = _books();
        vm.prank(alice);
        game.buyDegenesisBox(0, 2 ether);
        Books memory b = _books();
        assertEq(_afkingOf(aliceId), 1 ether, "prepaid debited");
        assertEq(b.claimablePool, a.claimablePool, "claimablePool unchanged");
        assertEq(b.balance, a.balance, "no ETH moved");
        assertEq(b.unsplit, a.unsplit + 2 ether, "held unsplit");
        _assertPoolsUntouched(a, b);
    }

    /// @notice Fresh ETH first, then claimable to its sentinel, then prepaid.
    function test_MixedBuy_FreshThenClaimableThenPrepaid() public {
        _seedClaimable(aliceId, 0.3 ether);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.depositAfkingFunding{value: 1 ether}(aliceId);
        Books memory a = _books();
        vm.deal(alice, 0.2 ether);
        vm.prank(alice);
        game.buyDegenesisBox{value: 0.2 ether}(0, 1 ether);
        Books memory b = _books();
        assertEq(_claimableOf(aliceId), 1, "claimable to its sentinel");
        assertEq(_afkingOf(aliceId), 0.5 ether, "prepaid covers the rest");
        assertEq(b.claimablePool, a.claimablePool + 0.2 ether, "only the fresh part is new");
        assertEq(b.balance, a.balance + 0.2 ether, "fresh ETH in");
        assertEq(b.unsplit, a.unsplit + 1 ether, "the whole amount held");
        _assertPoolsUntouched(a, b);
    }

    /// @notice Overpay is credited to the payer's AFKing, not purchased.
    function test_Overpay_CreditsPayerAfking() public {
        Books memory a = _books();
        uint256 afk = _afkingOf(aliceId);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.buyDegenesisBox{value: 1 ether}(0, 0.25 ether);
        Books memory b = _books();
        assertEq(_afkingOf(aliceId) - afk, 0.75 ether, "overpay to the payer's AFKing");
        assertEq(b.claimablePool, a.claimablePool + 1 ether, "amount plus overpay held");
        assertEq(b.unsplit, a.unsplit + 0.25 ether, "only the amount is purchased volume");
        assertEq(b.balance, a.balance + 1 ether, "all ETH in");
    }

    /// @notice An operator buying for a player: overpay goes to the operator (the payer).
    function test_OperatorOverpay_CreditsOperatorAfking() public {
        address op = _player("operator", 1 ether);
        uint32 opId = game.walletIdOf(op);
        vm.prank(alice);
        game.setOperatorApproval(0, op, true);
        uint256 credit = game.degenesisCreditOf(alice);
        vm.prank(op);
        game.buyDegenesisBox{value: 1 ether}(aliceId, 0.4 ether);
        assertEq(_afkingOf(opId), 0.6 ether, "overpay to the operator");
        assertEq(_afkingOf(aliceId), 0, "nothing to the buyer");
        assertEq(game.degenesisCreditOf(alice), credit - 0.4 ether, "the buyer's credit consumed");
    }

    /// @notice A buy while the pools are frozen (the day's request is out) still writes no pool,
    ///         live or pending; its volume splits exactly at the next request.
    function test_BuyWhileFrozen_TouchesNoPool_SplitsExactlyNextRequest() public {
        _warpDay(3, 1 hours);
        _drain(false, 400);
        assertTrue(_frozen(), "fixture: pools frozen by the request");
        Books memory a = _books();
        _buyDegenesis(alice, 0.0777 ether);
        Books memory b = _books();
        assertEq(b.claimablePool, a.claimablePool + 0.0777 ether, "held in claimablePool");
        _assertPoolsUntouched(a, b);
        _drain();
        _splitAt(4, 2, 0.0777 ether);
    }

    // ------------------------------------------------------------------ split

    /// @dev Warp into day `d`, run the engine up to the daily request (subscription stamping and
    ///      deliveries included), then check the request call that splits cohort `c` against its
    ///      volume `v`. Only the request moves Degenesis money, so its deltas are the split's.
    function _splitAt(uint256 d, uint8 c, uint256 v) internal {
        assertEq(v % 4, 0, "V is a whole number of 0.0001-ETH units, divisible by 4");
        _warpDay(d, 1 hours);
        _stepTo(ACTION_REQUEST_DAILY);
        Books memory a = _books();
        assertFalse(_frozen(), "fixture: the request splits before it freezes");
        vm.recordLogs();
        game.mineFlip(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        (bool found, uint8 day, uint256 volume) = _splitIn(logs);
        assertTrue(found, "the request split a cohort");
        assertTrue(game.rngLocked(), "fixture: the call was the request");
        Books memory b = _books();
        assertEq(day, c, "the expected cohort split");
        assertEq(volume, v, "split volume");
        assertTrue(_cohortSplit(c), "split flag set");
        assertEq(a.claimablePool - b.claimablePool, v / 2, "claimablePool -= V/2 exactly");
        // The request then freezes the pools, moving 1% of the live future pool into pending.
        assertEq(b.future + b.pendingFuture - a.future, v / 4, "future pool += V/4 exactly (live + pending)");
        assertEq(b.insurance - a.insurance, v / 4, "insurance += V/4");
        assertEq(b.next + b.pendingNext, a.next, "next pool untouched");
        assertEq(b.vaultBudget - a.vaultBudget, v / 4, "Vault budget += V/4");
        assertEq(b.sdgnrsAfking - a.sdgnrsAfking, v / 4, "sDGNRS AFKing += V/4");
        assertEq(b.balance, a.balance, "no ETH moves");
        assertEq(a.unsplit - b.unsplit, v, "nothing of V left unsplit");
        _assertSolvent();
    }

    function _splitIn(Vm.Log[] memory logs) internal view returns (bool found, uint8 c, uint256 volume) {
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics.length == 2 && logs[i].topics[0] == SPLIT_SIG) {
                c = uint8(uint256(logs[i].topics[1]));
                volume = abi.decode(logs[i].data, (uint256));
                found = true;
            }
        }
    }

    /// @notice Odd unit amounts from every funding source split exactly in wei at the first
    ///         request after the cohort's day, and not before: cohort 1 waits through its own
    ///         day's processing.
    function test_Split_ExactInWei_AtFirstRequestAfterItsDay() public {
        _seedClaimable(aliceId, 1 ether);
        _buyDegenesis(alice, 0.0101 ether);
        vm.prank(alice);
        game.buyDegenesisBox(0, 0.0257 ether);
        _buyDegenesis(alice, 0.3333 ether);
        uint256 v = 0.0101 ether + 0.0257 ether + 0.3333 ether;
        assertEq(_cohortVolume(1), v, "fixture: cohort 1 volume");
        _drain();
        assertFalse(_cohortSplit(1), "not split during its own day");
        assertEq(_unsplitVolume(), v, "held in claimablePool");
        _splitAt(3, 1, v);
    }

    /// @notice Fuzzed order sizes, three orders: the split stays exact in wei.
    /// forge-config: default.fuzz.runs = 12
    function testFuzz_Split_ExactInWei(uint256 u1, uint256 u2, uint256 u3) public {
        u1 = bound(u1, 100, 100_000);
        u2 = bound(u2, 100, 100_000);
        u3 = bound(u3, 100, 100_000);
        _buyDegenesis(alice, u1 * UNIT);
        _buyDegenesis(alice, u2 * UNIT);
        _buyDegenesis(alice, u3 * UNIT);
        _drain();
        _splitAt(3, 1, (u1 + u2 + u3) * UNIT);
    }

    /// @notice Two cohorts: each stays inside claimablePool until its own split; the later day's
    ///         volume is still held after the earlier one splits.
    function test_UnsplitVolumeStaysReservedUntilItsOwnSplit() public {
        _buyDegenesis(alice, 0.5 ether);
        _drain();
        _warpDay(3, 1 hours);
        _drain();
        assertTrue(_cohortSplit(1), "cohort 1 split at day 3's request");
        _buyDegenesis(alice, 0.7 ether);
        assertFalse(_cohortSplit(2), "cohort 2 still open");
        assertEq(_unsplitVolume(), 0.7 ether, "cohort 2 held in claimablePool");
        _assertSolvent();
        _drain();
        _splitAt(4, 2, 0.7 ether);
    }

    function _isolatedSplit(uint24 day) internal {
        bytes memory code = address(game).code;
        vm.etch(address(game), address(degenesisModule).code);
        IDegenerusGameDegenesisModule(address(game)).prepareDegenesis(day);
        vm.etch(address(game), code);
    }

    function test_MissedCohorts_FrozenSplit_EmptyAndRepeatedProcessing() public {
        _buyDegenesis(alice, 0.0101 ether);
        _warpDay(3, 1 hours);
        _buyDegenesis(alice, 0.0123 ether);
        _warpDay(5, 1 hours);
        _buyDegenesis(alice, 0.0145 ether);
        // Seed only the freeze flag; real purchases supply every cohort's volume.
        uint256 slot0 = _slot(GameSlots.PRIZE_POOL_FROZEN);
        vm.store(address(game), bytes32(GameSlots.PRIZE_POOL_FROZEN), bytes32(slot0 | (uint256(1) << (GameSlots.PRIZE_POOL_FROZEN_OFFSET * 8))));
        Books memory a = _books();
        uint256 volume = 0.0369 ether;
        _isolatedSplit(6);
        Books memory b = _books();
        assertEq(a.claimablePool - b.claimablePool, volume / 2);
        assertEq(b.future, a.future, "frozen live pool untouched");
        assertEq(b.pendingFuture - a.pendingFuture, volume / 4);
        assertEq(b.insurance - a.insurance, volume / 4);
        assertEq(b.vaultBudget - a.vaultBudget, volume / 4);
        assertEq(b.sdgnrsAfking - a.sdgnrsAfking, volume / 4);
        _isolatedSplit(6);
        assertEq(abi.encode(_books()), abi.encode(b), "repeated processing adds nothing");
    }

    function test_AllFundingSources_SplitWithExistingInsurance() public {
        _seedClaimable(aliceId, 1 ether);
        vm.deal(alice, 1 ether);
        vm.prank(alice);
        game.depositAfkingFunding{value: 1 ether}(aliceId);
        // Separate purchases exhaust claimable before drawing prepaid principal.
        vm.prank(alice);
        game.buyDegenesisBox(0, 1 ether);
        vm.prank(alice);
        game.buyDegenesisBox(0, 0.0101 ether);
        _buyDegenesis(alice, 0.0123 ether);
        uint256 volume = 1.0224 ether;
        _warpDay(3, 1 hours);
        Books memory a = _books();
        _isolatedSplit(3);
        Books memory b = _books();
        assertEq(a.claimablePool - b.claimablePool, volume / 2);
        assertEq(b.future + b.pendingFuture - a.future - a.pendingFuture, volume / 4);
        assertEq(b.insurance - a.insurance, volume / 4);
        assertEq(b.vaultBudget - a.vaultBudget, volume / 4);
        assertEq(b.sdgnrsAfking - a.sdgnrsAfking, volume / 4);
    }
}
