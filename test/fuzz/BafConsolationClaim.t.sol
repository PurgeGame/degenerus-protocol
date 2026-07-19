// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BafConsolationClaimTest -- Skipped-BAF WWXRP consolation claims.
///
/// @notice When a bracket's BAF skips (daily flip lost at the x10 transition),
///         players' accumulated bracket scores are frozen in storage. Each score
///         is redeemable once for WWXRP at score / 1000 via the permissionless
///         DegenerusJackpots.claimBafConsolation(player, lvl) — the mint always
///         goes to the recorded score owner.
///
/// @dev Two layers:
///      1. Unit tests: prank COINFLIP/GAME to build scores and mark skips,
///         covering the gate (skipped flag), epoch staleness after a real
///         resolution, double-claim, permissionless execution, VAULT
///         exclusion, dust, and zero-score claims.
///      2. Driven e2e: run the game organically to past level 10 with VRF words
///         forced even (bit 0 = 0), so the level-10 BAF skips through the real
///         advanceGame path; then claim and verify minted WWXRP.
contract BafConsolationClaimTest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    event BafConsolationClaimed(
        address indexed player,
        uint24 indexed lvl,
        uint256 score,
        uint256 wwxrpAmount
    );

    error NothingToClaim();

    address private alice;
    address private bob;
    address private keeper;
    address private buyer;

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
        vm.prank(address(coinflip));
        jackpots.recordBafFlip(player, lvl, amount);
    }

    function _skip(uint24 lvl) private {
        vm.prank(address(game));
        jackpots.markBafSkipped(lvl);
    }

    function testClaimAfterSkipMintsScoreOverThousand() public {
        _record(alice, 10, 5000 ether);
        _record(bob, 10, 250 ether);

        // Bracket not skipped yet: nothing claimable.
        assertEq(jackpots.bafConsolationOf(alice, 10), 0, "no claim before skip");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(alice, 10);

        _skip(10);

        assertEq(jackpots.bafConsolationOf(alice, 10), 5 ether, "view after skip");

        // Permissionless: keeper executes, mint goes to alice.
        vm.expectEmit(true, true, false, true, address(jackpots));
        emit BafConsolationClaimed(alice, 10, 5000 ether, 5 ether);
        vm.prank(keeper);
        jackpots.claimBafConsolation(alice, 10);
        assertEq(wwxrp.balanceOf(alice), 5 ether, "alice minted score/1000");
        assertEq(wwxrp.balanceOf(keeper), 0, "keeper gets nothing");
        assertEq(jackpots.bafConsolationOf(alice, 10), 0, "claim consumed score");

        // Double claim reverts.
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(alice, 10);

        // Bob's independent score still claimable (self-executed).
        vm.prank(bob);
        jackpots.claimBafConsolation(bob, 10);
        assertEq(wwxrp.balanceOf(bob), 0.25 ether, "bob minted score/1000");
    }

    function testResolvedBracketPaysNothing() public {
        _record(alice, 20, 1000 ether);

        // Real resolution: epoch bumps, scores go stale, skipped stays false.
        vm.prank(address(game));
        jackpots.runBafJackpot(1 ether, 20, uint256(keccak256("resolved_word")));

        assertEq(jackpots.bafConsolationOf(alice, 20), 0, "resolved bracket not claimable");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(alice, 20);

        // Defensive: even a (production-impossible) late skip mark cannot revive
        // the stale-epoch score.
        _skip(20);
        assertEq(jackpots.bafConsolationOf(alice, 20), 0, "stale epoch pays zero");
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(alice, 20);
    }

    function testVaultConsolationEscrowsToAllowance() public {
        _record(ContractAddresses.VAULT, 10, 5000 ether);
        _skip(10);

        assertEq(jackpots.bafConsolationOf(ContractAddresses.VAULT, 10), 5 ether, "vault claimable");

        uint256 allowanceBefore = wwxrp.vaultAllowance();
        uint256 supplyBefore = wwxrp.totalSupply();
        vm.prank(keeper);
        jackpots.claimBafConsolation(ContractAddresses.VAULT, 10);

        // Vault mints escrow: allowance grows, no circulating balance appears.
        assertEq(wwxrp.vaultAllowance(), allowanceBefore + 5 ether, "escrowed to allowance");
        assertEq(wwxrp.balanceOf(ContractAddresses.VAULT), 0, "no circulating vault balance");
        assertEq(wwxrp.totalSupply(), supplyBefore, "totalSupply excludes escrow");

        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(ContractAddresses.VAULT, 10);
    }

    function testZeroScoreAndDustClaimsRevert() public {
        _skip(10);

        // No score at all.
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(alice, 10);

        // Sub-1000-wei dust rounds to zero and must not be silently consumed.
        _record(bob, 10, 999);
        vm.expectRevert(NothingToClaim.selector);
        jackpots.claimBafConsolation(bob, 10);
        assertEq(jackpots.bafConsolationOf(bob, 10), 0, "dust score worth zero");
    }

    function testIndependentBracketsClaimSeparately() public {
        _record(alice, 10, 3000 ether);
        _record(alice, 20, 7000 ether);
        _skip(10);
        _skip(20);

        jackpots.claimBafConsolation(alice, 10);
        assertEq(wwxrp.balanceOf(alice), 3 ether, "bracket 10 minted");
        jackpots.claimBafConsolation(alice, 20);
        assertEq(wwxrp.balanceOf(alice), 10 ether, "bracket 20 minted on top");
    }

    // ==================== Driven e2e (forced-even VRF words) ====================

    /// @notice Drive the real game past level 10 with every VRF word forced even,
    ///         so the level-10 BAF skips via advanceGame, then claim consolation.
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
                    _record(players[i], 10, (1000 + i * 500) * 1 ether);
                }
                injected = true;

                // Bracket still undecided: claim must revert.
                vm.expectRevert(NothingToClaim.selector);
                jackpots.claimBafConsolation(players[0], 10);
            }

            simTime += 1 days + 1;
            vm.warp(simTime);

            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfEven();
                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }

        assertTrue(injected, "BAF scores were injected");
        assertGt(game.level(), 10, "game advanced past level 10");

        // Every word was even => the level-10 BAF skipped through advanceGame.
        for (uint256 i = 0; i < players.length; i++) {
            uint256 score = (1000 + i * 500) * 1 ether;
            assertEq(
                jackpots.bafConsolationOf(players[i], 10),
                score / 1000,
                "claimable equals frozen score / 1000"
            );

            // Permissionless keeper claim, mint to the score owner.
            vm.prank(keeper);
            jackpots.claimBafConsolation(players[i], 10);
            assertEq(wwxrp.balanceOf(players[i]), score / 1000, "minted score/1000");

            vm.expectRevert(NothingToClaim.selector);
            jackpots.claimBafConsolation(players[i], 10);
        }
    }

    // ==================== Internal helpers ====================

    function _seedNextPrizePool(uint256 targetNext) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        if (uint256(currentNext) >= targetNext) return;
        uint128 currentFuture = uint128(packed >> 128);
        uint256 newPacked = (uint256(currentFuture) << 128) | targetNext;
        vm.store(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT)), bytes32(newPacked));
    }

    function _seedFuturePrizePool(uint256 targetFuture) internal {
        uint256 packed = uint256(vm.load(address(game), bytes32(uint256(PRIZE_POOLS_PACKED_SLOT))));
        uint128 currentNext = uint128(packed);
        uint128 currentFuture = uint128(packed >> 128);
        if (uint256(currentFuture) >= targetFuture) return;
        uint256 newPacked = (targetFuture << 128) | uint256(currentNext);
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
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
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
