// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {BafViews} from "../helpers/BafViews.sol";
import {GameSlots} from "../helpers/GameSlots.sol";

/// @title BafConsolationClaimTest -- Skipped-BAF WWXRP consolation claims.
///
/// @notice When a bracket's BAF skips (daily flip lost at the x10 transition),
///         players' accumulated bracket scores are frozen in storage. Each score
///         is redeemable once for WWXRP at score / 1000, with a one-token minimum
///         for positive scores, via the permissionless
///         DegenerusJackpots.claimBafConsolation(id, lvl) — the mint always
///         goes to the recorded score owner.
///
/// @dev Two layers:
///      1. Unit tests: prank COINFLIP/GAME to build scores and mark skips,
///         covering the gate (skipped flag), epoch staleness after a real
///         resolution, double-claim, permissionless execution, VAULT
///         exclusion, dust, and zero-score claims.
///      2. Driven e2e: run the game organically to past level 10 with VRF words
///         forced even (bit 0 = 0), so the level-10 BAF skips through the real
///         mineFlip path; then claim and verify minted WWXRP.
contract BafConsolationClaimTest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = GameSlots.PRIZE_POOLS_PACKED;

    event BafConsolationClaimed(
        uint32 indexed player,
        uint24 indexed lvl,
        uint256 score,
        uint256 wwxrpAmount
    );

    error NothingToClaim();

    address private alice;
    address private bob;
    address private keeper;
    address private buyer;
    mapping(address => uint32) private ids;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        alice = makeAddr("consolation_alice");
        bob = makeAddr("consolation_bob");
        keeper = makeAddr("consolation_keeper");
        buyer = makeAddr("consolation_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 2_000 ether);
    }

    // ==================== Unit tests (pranked score/skip) ====================

    function _record(address player, uint24 lvl, uint256 amount) private {
        uint32 id = _giveWalletId(player);
        ids[player] = id;
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(id, lvl, amount);
    }

    function _skip(uint24 lvl) private {
        vm.prank(address(game));
        jackpots.markBafSkipped(lvl);
    }

    function testClaimAfterSkipMintsScoreOverThousand() public {
        _record(alice, 10, 5000);
        _record(bob, 10, 250);

        // Bracket not skipped yet: nothing claimable.
        assertEq(jackpots.bafConsolationOf(alice, 10), 0, "no claim before skip");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 10);

        _skip(10);

        assertEq(jackpots.bafConsolationOf(alice, 10), 5, "view after skip");

        // Permissionless: keeper executes, mint goes to alice.
        vm.expectEmit(true, true, false, true, address(jackpots));
        emit BafConsolationClaimed(ids[alice], 10, 5000, 5);
        vm.prank(keeper);
        jackpots.claimBafConsolation(ids[alice], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), 5, "alice minted score/1000");
        assertEq(wwxrp.claimable(game.walletIdOf(keeper)), 0, "keeper gets nothing");
        assertEq(jackpots.bafConsolationOf(alice, 10), 0, "claim consumed score");

        // Double claim reverts.
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 10);

        // A positive score below 1000 receives one whole WWXRP and is consumed once.
        assertEq(jackpots.bafConsolationOf(bob, 10), 1);
        vm.expectEmit(true, true, false, true, address(jackpots));
        emit BafConsolationClaimed(ids[bob], 10, 250, 1);
        vm.prank(bob);
        jackpots.claimBafConsolation(ids[bob], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(bob)), 1);
        assertEq(jackpots.bafConsolationOf(bob, 10), 0);
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[bob], 10);
    }

    function testWholeTokenConsolationBoundaries() public {
        _record(alice, 10, 999);
        _record(bob, 10, 1000);
        _record(keeper, 10, 1999);
        _record(buyer, 10, 2000);
        _skip(10);
        assertEq(jackpots.bafConsolationOf(alice, 10), 1);
        assertEq(jackpots.bafConsolationOf(bob, 10), 1);
        assertEq(jackpots.bafConsolationOf(keeper, 10), 1);
        assertEq(jackpots.bafConsolationOf(buyer, 10), 2);
        jackpots.claimBafConsolation(ids[alice], 10);
        jackpots.claimBafConsolation(ids[bob], 10);
        jackpots.claimBafConsolation(ids[keeper], 10);
        jackpots.claimBafConsolation(ids[buyer], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), 1);
        assertEq(wwxrp.claimable(game.walletIdOf(bob)), 1);
        assertEq(wwxrp.claimable(game.walletIdOf(keeper)), 1);
        assertEq(wwxrp.claimable(game.walletIdOf(buyer)), 2);
    }

    function testResolvedBracketPaysNothing() public {
        _record(alice, 20, 1000);

        // Real resolution: `beginBaf` at consolidation opens it, the award stage draws from the
        // frozen scores, and `finalizeBaf` with the last award group bumps the epoch. The
        // bracket is never skipped, so nothing is claimable at any point.
        vm.prank(address(game));
        jackpots.beginBaf();
        assertEq(jackpots.bafConsolationOf(alice, 20), 0, "a resolving bracket is not claimable");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 20);
        (uint32 best,) = BafViews.round(address(jackpots), 20, uint256(keccak256("resolved_word")), 0, 48);
        assertEq(best, 0, "no sampled entry holds a bracket score");
        assertEq(jackpots.bafHeadWinner(20, uint256(keccak256("resolved_word")), 0), game.walletIdOf(alice),
            "the frozen board still names the top bettor mid-stage");
        vm.prank(address(game));
        jackpots.finalizeBaf(20);
        assertEq(jackpots.bafHeadWinner(20, uint256(keccak256("resolved_word")), 0), 0,
            "finalizeBaf clears the board");

        assertEq(jackpots.bafConsolationOf(alice, 20), 0, "resolved bracket not claimable");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 20);

        // Defensive: even a (production-impossible) late skip mark cannot revive
        // the stale-epoch score.
        _skip(20);
        assertEq(jackpots.bafConsolationOf(alice, 20), 0, "stale epoch pays zero");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 20);
    }

    function testVaultConsolationEscrowsToAllowance() public {
        _record(ContractAddresses.VAULT, 10, 5000);
        _skip(10);

        assertEq(jackpots.bafConsolationOf(ContractAddresses.VAULT, 10), 5, "vault claimable");

        uint256 balanceBefore = wwxrp.claimable(game.walletIdOf(ContractAddresses.VAULT));
        uint256 supplyBefore = wwxrp.totalSupply();
        vm.prank(keeper);
        jackpots.claimBafConsolation(ids[ContractAddresses.VAULT], 10);

        assertEq(wwxrp.claimable(game.walletIdOf(ContractAddresses.VAULT)), balanceBefore + 5, "vault prize balance");
        assertEq(wwxrp.totalSupply(), supplyBefore, "unminted rewards do not circulate");

        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[ContractAddresses.VAULT], 10);
    }

    function testZeroScoreRevertsAndSmallestScorePaysOne() public {
        _skip(10);

        // No score at all.
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 10);

        assertEq(jackpots.bafConsolationOf(alice, 10), 0);

        _record(bob, 10, 1);
        assertEq(jackpots.bafConsolationOf(bob, 10), 1, "smallest positive score pays one");
        jackpots.claimBafConsolation(ids[bob], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(bob)), 1);
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[bob], 10);
        assertEq(jackpots.bafConsolationOf(bob, 10), 0, "small score consumed once");
    }

    function testFractionalConsolationRespectsMintScaleAtClaim() public {
        _record(alice, 10, 1);
        _record(bob, 10, 999);
        _skip(10);
        vm.prank(ContractAddresses.CREATOR);
        wwxrp.setGameMintScale(7);
        assertEq(jackpots.bafConsolationOf(alice, 10), 1, "view reports the unscaled award");
        jackpots.claimBafConsolation(ids[alice], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), 7);
        vm.prank(ContractAddresses.CREATOR);
        wwxrp.setGameMintScale(0);
        jackpots.claimBafConsolation(ids[bob], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(bob)), 0, "zero mint scale still disables emission");
        assertEq(jackpots.bafConsolationOf(bob, 10), 0, "disabled mint still consumes the claim");
    }

    function testFuzzPositiveScoreMinimumAndSingleClaim(uint96 score) public {
        score = uint96(bound(score, 1, type(uint96).max));
        _record(alice, 10, score);
        _skip(10);
        uint256 expected = score < 1000 ? 1 : uint256(score) / 1000;
        assertEq(jackpots.bafConsolationOf(alice, 10), expected);
        vm.prank(keeper);
        jackpots.claimBafConsolation(ids[alice], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), expected);
        assertEq(jackpots.bafConsolationOf(alice, 10), 0);
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ids[alice], 10);
    }

    function testIndependentBracketsClaimSeparately() public {
        _record(alice, 10, 3000);
        _record(alice, 20, 7000);
        _skip(10);
        _skip(20);

        jackpots.claimBafConsolation(ids[alice], 10);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), 3, "bracket 10 minted");
        jackpots.claimBafConsolation(ids[alice], 20);
        assertEq(wwxrp.claimable(game.walletIdOf(alice)), 10, "bracket 20 minted on top");
    }

    // ==================== Driven e2e (forced-even VRF words) ====================

    /// @notice Drive the real game past level 10 with every VRF word forced even,
    ///         so the level-10 BAF skips via mineFlip, then claim consolation.
    function testDrivenSkipThenClaim() public {
        address[5] memory players;
        for (uint256 i = 0; i < players.length; i++) {
            players[i] = makeAddr(string.concat("driven_baf_", vm.toString(i)));
        }

        uint256 simTime = block.timestamp;
        bool injected = false;

        for (uint256 day = 0; day < 600; day++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            if (currentLevel > 10) break;

            if (currentLevel >= 9 && !injected) {
                for (uint256 i = 0; i < players.length; i++) {
                    _record(players[i], 10, (1000 + i * 500) * 1);
                }
                injected = true;

                // Bracket still undecided: claim must revert.
                vm.expectRevert(NothingToClaim.selector);
                jackpots.claimBafConsolation(ids[players[0]], 10);
            }

            simTime += 1 days + 1;
            vm.warp(simTime);

            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfEven();
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("mineFlip()")
                );
                if (!ok) break;
            }
        }

        assertTrue(injected, "BAF scores were injected");
        assertGt(game.level(), 10, "game advanced past level 10");

        // Every word was even => the level-10 BAF skipped through mineFlip.
        for (uint256 i = 0; i < players.length; i++) {
            uint256 score = (1000 + i * 500) * 1;
            assertEq(
                jackpots.bafConsolationOf(players[i], 10),
                score / 1000,
                "claimable equals frozen score / 1000"
            );

            // Permissionless keeper claim, mint to the score owner.
            vm.prank(keeper);
            jackpots.claimBafConsolation(ids[players[i]], 10);
            assertEq(wwxrp.claimable(game.walletIdOf(players[i])), score / 1000, "minted score/1000");

            vm.expectRevert(NothingToClaim.selector);
            jackpots.claimBafConsolation(ids[players[i]], 10);
        }
    }

    // ==================== Internal helpers ====================

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentNext = packed & ((uint256(1) << 128) - 1);
        if (currentNext >= targetNext) return;
        uint256 newPacked = (packed & ~((uint256(1) << 128) - 1)) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint256 currentFuture = (packed >> 128) & ((uint256(1) << 128) - 1);
        if (currentFuture >= targetFuture) return;
        uint256 newPacked = (packed & ~(((uint256(1) << 128) - 1) << 128)) | (targetFuture << 128);
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _buyTickets(address who, uint256 qty) internal {
        (, , , bool rngLocked_, uint256 priceWei) = game.purchaseInfo();
        if (rngLocked_) return;
        if (game.gameOver()) return;

        uint256 cost = (priceWei * qty) / 400;
        if (cost == 0) return;
        if (who.balance < cost) vm.deal(who, cost + 10 ether);

        vm.prank(who);
        try game.purchase{value: cost}(0, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
    }

    /// @dev Fulfill any pending VRF request with an even word (bit 0 = 0), so
    ///      the BAF fire gate (rngWord & 1 == 1) never passes. No reverseFlip
    ///      nudges run in this test, so parity survives _applyDailyRng.
    function _fulfillVrfEven() internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 randomWord = uint256(
            keccak256(abi.encode("baf_skip_word", block.timestamp, game.level(), reqId))
        ) & ~uint256(1);
        if (randomWord == 0) randomWord = 2;
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
