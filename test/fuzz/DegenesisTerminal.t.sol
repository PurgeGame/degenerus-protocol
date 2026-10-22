// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Vm} from "forge-std/Vm.sol";
import {DegenesisFixture} from "./helpers/DegenesisFixture.sol";
import {GameSlots} from "../helpers/GameSlots.sol";
import {GameTimeLib} from "../../contracts/libraries/GameTimeLib.sol";

/// @title DegenesisTerminal -- Degenesis money at game over (check 11)
/// @notice Both endings, driven for real: the VRF-alive ending through the 30-day deadman (every
///         request answered), and the dead-VRF ending through a daily request left unanswered for
///         14 days. Terminal setup splits every unsplit cohort, then releases the Vault budget and
///         all sDGNRS AFKing funding from claimablePool into the final prizes, exactly once, before
///         gameOver; unresolved orders are forfeited with the burned inventory; player claims and
///         genuine claimable winnings stay intact. A bystander's claimable winnings are seeded in
///         storage (ledger, claimablePool and ETH in tandem).
contract DegenesisTerminal is DegenesisFixture {
    bytes32 internal constant RESOLVED_SIG =
        keccak256("DegenesisOrderResolved(uint32,uint8,uint32,uint256,uint256,uint256,uint256,uint32,uint32)");
    bytes32 internal constant DRAINED_SIG = keccak256("GameOverDrained(uint24,uint256,uint256)");
    bytes32 internal constant REFUNDS_SIG = keccak256("DeityPassRefundsSettled(uint256)");
    uint8 internal constant ACTION_DEGENESIS_SETTLE_ = 21;

    address internal alice;
    address internal bob;
    uint32 internal bobId;

    function setUp() public override {
        super.setUp();
        alice = _player("alice", 100 ether);
        vm.prank(alice);
        game.purchaseWhalePass{value: 48 ether}(0, 20, bytes32(0)); // 12 ETH of credit
        bob = _player("bob", 1 ether);
        bobId = game.walletIdOf(bob);
        vm.prank(bob);
        game.depositAfkingFunding{value: 1 ether}(bobId);
        _seedClaimable(bobId, 0.5 ether);
        _drain();
    }

    struct Pre {
        uint256 claimablePool;
        uint256 unsplit;
        uint256 vaultBudget;
        uint256 sdgnrsAfking;
        uint256 sdgnrsClaimable;
        uint256 vaultWord;
    }

    function _pre() internal view returns (Pre memory p) {
        p.claimablePool = _claimablePool();
        p.unsplit = _unsplitVolume();
        p.vaultBudget = _vaultBudget();
        p.sdgnrsAfking = _afkingOf(SDGNRS_ID);
        p.sdgnrsClaimable = _claimableOf(SDGNRS_ID);
        p.vaultWord = _packed(VAULT_ID);
    }

    struct Ending {
        uint256 releases;
        uint256 releasedVault;
        uint256 releasedSdgnrs;
        uint256 splitsDuringEnding;
        uint256 resolvedDuringEnding;
        bool drained;
        uint256 drainedClaimablePool;
        uint256 drainedAvailable;
        uint256 drainedBacking;
        uint256 refunds;
        Pre atGameOver; // state just before the call that set gameOver
        Pre atSplit; // state just before the call that split
        bool splitCallSetGameOver;
        uint256 splitCallReleases;
        bool frozenAtSplit;
        uint256 pendingFutureBeforeSplit;
        uint256 pendingFutureAfterSplit;
        uint256 claimablePoolAfterSplit;
    }

    function _jackpotPaid() internal view returns (bool) {
        return uint8(_slot(GameSlots.GAME_OVER_STATE_PACKED) >> 48) != 0;
    }

    /// @dev Drive the ending one engine call at a time until the terminal payout is done,
    ///      answering requests when `answer` is set.
    function _driveEnding(bool answer) internal returns (Ending memory e) {
        for (uint256 i; i < 400; ++i) {
            if (game.gameOver() && _jackpotPaid()) return e;
            if (answer) _fulfillPending();
            Pre memory p = _pre();
            bool wasOver = game.gameOver();
            bool frozen = _frozen();
            uint256 pendingFuture = _pendingFuture();
            vm.recordLogs();
            _tryMine();
            Vm.Log[] memory logs = vm.getRecordedLogs();
            uint256 splits = _countSig(logs, SPLIT_SIG);
            uint256 releases;
            for (uint256 j; j < logs.length; ++j) {
                Vm.Log memory l = logs[j];
                if (l.emitter != address(game)) continue;
                if (l.topics[0] == RELEASED_SIG) {
                    (uint256 v, uint256 s) = abi.decode(l.data, (uint256, uint256));
                    e.releasedVault += v;
                    e.releasedSdgnrs += s;
                    ++releases;
                } else if (l.topics[0] == DRAINED_SIG) {
                    (, e.drainedAvailable, e.drainedClaimablePool) = abi.decode(l.data, (uint24, uint256, uint256));
                    e.drainedBacking = _gameBalance();
                    e.drained = true;
                } else if (l.topics[0] == REFUNDS_SIG) {
                    e.refunds += abi.decode(l.data, (uint256));
                }
            }
            e.releases += releases;
            e.resolvedDuringEnding += _countSig(logs, RESOLVED_SIG);
            if (splits != 0) {
                e.splitsDuringEnding += splits;
                e.atSplit = p;
                e.frozenAtSplit = frozen;
                e.pendingFutureBeforeSplit = pendingFuture;
                e.pendingFutureAfterSplit = _pendingFuture();
                e.claimablePoolAfterSplit = _claimablePool();
                e.splitCallSetGameOver = game.gameOver();
                e.splitCallReleases = releases;
            }
            if (!wasOver && game.gameOver()) e.atGameOver = p;
        }
        revert("ending did not finish");
    }

    /// @dev Every terminal check shared by the endings.
    function _assertTerminal(Ending memory e, Pre memory start, uint256 bobClaimable, uint256 bobAfking) internal view {
        assertTrue(game.gameOver(), "game over");
        assertEq(e.releases, 1, "one release");
        // Setup splits what is unsplit, then releases: both in the call that sets gameOver.
        assertEq(e.releasedVault, e.atGameOver.vaultBudget + e.atGameOver.unsplit / 4, "the whole Vault budget released");
        assertEq(e.releasedSdgnrs, e.atGameOver.sdgnrsAfking + e.atGameOver.unsplit / 4, "all sDGNRS AFKing released");
        assertEq(_unsplitVolume(), 0, "no Degenesis volume unsplit");
        assertEq(_vaultBudget(), 0, "budget zeroed");
        assertEq(_afkingOf(SDGNRS_ID), 0, "sDGNRS AFKing zeroed before gameOver");
        assertEq(_active(), 0, "unresolved orders forfeited");
        assertEq(_degenesisPool(), 0, "Degenesis inventory burned");
        assertTrue(e.drained, "final prizes funded");
        assertEq(_slot(GameSlots.YIELD_ACCUMULATOR), 0, "insurance cleared");
        assertEq(_pendingNext() + _pendingFuture(), 0, "pending balances cleared");
        assertFalse(_frozen(), "terminal freeze cleared");
        assertEq(e.drainedAvailable + e.drainedClaimablePool, e.drainedBacking, "final distributable includes insurance exactly once");
        // The release left claimablePool by exactly what it released (plus any deity refunds),
        // so the final prize budget (ETH + stETH - claimablePool) includes it exactly once.
        assertEq(e.drainedClaimablePool + e.atGameOver.unsplit / 2 + e.releasedVault + e.releasedSdgnrs,
            e.atGameOver.claimablePool + e.refunds, "split and release left claimablePool exactly once");
        // Every Degenesis wei held in claimablePool when the ending began left it once: the unsplit
        // volume's half through the split, its quarters and the standing balances through the release.
        assertEq(e.releasedVault + e.releasedSdgnrs, start.vaultBudget + start.sdgnrsAfking + start.unsplit / 2,
            "budget, sDGNRS AFKing and the unsplit quarters released exactly once");
        // Player claims intact.
        assertEq(_claimableOf(bobId), bobClaimable, "bystander claimable intact");
        assertEq(_afkingOf(bobId), bobAfking, "bystander AFKing intact");
        // sDGNRS and the Vault hold tickets, so the terminal jackpot may pay them: their genuine
        // claimable never falls, and the Vault's ordinary AFKing is untouched.
        assertGe(_claimableOf(SDGNRS_ID), e.atGameOver.sdgnrsClaimable, "sDGNRS claimable winnings kept");
        assertGe(uint128(_packed(VAULT_ID)), uint128(e.atGameOver.vaultWord), "Vault claimable kept");
        assertEq(_packed(VAULT_ID) >> 128, e.atGameOver.vaultWord >> 128, "Vault AFKing untouched");
        assertGe(_gameBalance(), _claimablePool(), "solvent");
    }

    // ------------------------------------------------------------------ VRF-alive, after the sale

    function test_VrfAliveEnding_AfterSale_ReleasesOnceIntoFinalPrizes() public {
        for (uint256 d = 2; d <= 8; ++d) {
            _driveDay(d);
            _buyDegenesis(alice, 1 ether);
        }
        _driveThrough(10);
        assertEq(_degenesisClosed(), 7, "fixture: sale closed");
        assertEq(_unsplitVolume(), 0, "fixture: all split");
        assertGt(_vaultBudget(), 0, "fixture: Vault budget");
        assertGt(_afkingOf(SDGNRS_ID), 0, "fixture: sDGNRS AFKing");
        uint256 bobClaimable = _claimableOf(bobId);
        uint256 bobAfking = _afkingOf(bobId);

        _warpDay(10 + 32, 1 hours);
        assertTrue(game.livenessTriggered(), "deadman: 30 days without a sealed day");
        Pre memory start = _pre();
        Ending memory e = _driveEnding(true);
        assertEq(e.splitsDuringEnding, 0, "nothing left to split");
        assertEq(e.releasedVault, start.vaultBudget, "budget at the ending released");
        assertEq(e.releasedSdgnrs, start.sdgnrsAfking, "sDGNRS AFKing at the ending released");
        _assertTerminal(e, start, bobClaimable, bobAfking);

        // No second release on resumed work or the final sweep.
        vm.recordLogs();
        _warpDay(10 + 32 + 31, 1 hours);
        for (uint256 i; i < 50; ++i) if (!_tryMine()) break;
        assertEq(_countSig(vm.getRecordedLogs(), RELEASED_SIG), 0, "no second release");
        assertEq(_slot(GameSlots.YIELD_ACCUMULATOR), 0, "insurance stays cleared");
        assertEq(_pendingNext() + _pendingFuture(), 0, "pending balances stay cleared");
        assertEq(_vaultBudget(), 0, "budget stays zero");
        assertEq(_afkingOf(SDGNRS_ID), 0, "sDGNRS AFKing stays zero");
    }

    // ------------------------------------------------------------------ VRF-alive, during the sale

    /// @notice The game ends (deadman) while cohort 3 is priced with orders unresolved and cohort 4
    ///         is still unsplit: setup splits cohort 4, forfeits cohort 3's orders, and releases.
    function test_VrfAliveEnding_DuringSale_SplitsAllAndForfeitsUnresolved() public {
        for (uint256 d = 2; d <= 4; ++d) {
            _driveDay(d);
            _buyDegenesis(alice, 1 ether);
            _buyDegenesis(alice, 0.5 ether);
        }
        _warpDay(5, 1 hours);
        _buyDegenesis(alice, 0.7 ether);
        _stepTo(ACTION_DEGENESIS_SETTLE_);
        assertTrue(_active() != 0, "fixture: cohort 3 priced, orders unresolved");
        assertEq(_degenesisClosed(), 2, "fixture: cohorts 1-2 closed");
        assertEq(_unsplitVolume(), 0.7 ether, "fixture: cohort 4 unsplit");
        uint256 bobClaimable = _claimableOf(bobId);
        uint256 bobAfking = _afkingOf(bobId);

        _warpDay(5 + 32, 1 hours);
        assertTrue(game.livenessTriggered(), "deadman");
        Pre memory start = _pre();
        Ending memory e = _driveEnding(true);
        assertEq(e.splitsDuringEnding, 1, "cohort 4 split at terminal setup");
        assertEq(e.resolvedDuringEnding, 0, "no unresolved order paid");
        assertEq(e.releasedVault, start.vaultBudget + 0.7 ether / 4, "budget includes cohort 4's quarter");
        assertEq(e.releasedSdgnrs, start.sdgnrsAfking + 0.7 ether / 4, "sDGNRS AFKing includes its quarter");
        _assertTerminal(e, start, bobClaimable, bobAfking);
    }

    // ------------------------------------------------------------------ dead VRF, during the sale

    /// @notice Day 4's request is never answered: cohort 2 stays priced with orders unresolved and
    ///         cohorts 3-7 keep taking orders. Once VRF is dead the ending latches the deterministic
    ///         path up front (before setup), so setup itself splits every cohort while the pools
    ///         are still frozen by the unanswered request and releases in the same call, once.
    function test_DeadVrfEnding_DuringSale_SplitsThenReleasesOnce() public {
        _driveDay(2);
        _buyDegenesis(alice, 1 ether);
        _driveDay(3);
        _buyDegenesis(alice, 1.2 ether);
        _warpDay(4, 1 hours);
        _buyDegenesis(alice, 0.3 ether);
        _drain(false, 400);
        assertTrue(game.rngLocked(), "fixture: day 4's request is out");
        uint256 requestedAt = block.timestamp;
        assertTrue(_active() != 0, "fixture: cohort 2 priced");
        for (uint256 d = 5; d <= 8; ++d) {
            _warpDay(d, 1 hours);
            _buyDegenesis(alice, 0.1 ether * d);
        }
        uint256 unsplit = _unsplitVolume();
        assertEq(unsplit, 0.3 ether + 2.6 ether, "fixture: cohorts 3-7 unsplit");
        uint256 bobClaimable = _claimableOf(bobId);
        uint256 bobAfking = _afkingOf(bobId);

        vm.warp(requestedAt + 14 days + 1);
        assertTrue(game.livenessTriggered(), "VRF dead");
        Pre memory start = _pre();
        Ending memory e = _driveEnding(false);

        assertEq(e.splitsDuringEnding, 5, "cohorts 3-7 split at terminal setup");
        assertTrue(e.frozenAtSplit, "split while the pools are frozen by the unanswered request");
        assertTrue(e.splitCallSetGameOver, "dead latched up front: setup splits and releases together");
        assertEq(e.splitCallReleases, 1, "the release follows the split in the same call");
        assertEq(e.atGameOver.unsplit, unsplit, "the whole unsplit volume reached setup");
        assertEq(_pendingFuture(), 0, "terminal state clears the pending pool (its share joins the prizes)");
        assertEq(e.resolvedDuringEnding, 0, "no unresolved order paid");
        _assertTerminal(e, start, bobClaimable, bobAfking);
    }
}
