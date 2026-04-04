// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BafFarFutureTicketsTest -- Regression test for the RngLocked revert
///        during BAF reward jackpot processing in advanceGame.
///
/// @notice The bug: during the purchase→jackpot transition at level 10 (BAF fires),
///         _runRewardJackpots → _runBafJackpot → _awardJackpotTickets → _jackpotTicketRoll
///         has a 5% chance per roll of targeting +5 to +50 levels ahead (far-future).
///         This calls _queueTicketsScaled which checks:
///
///           if (isFarFuture && rngLockedFlag && !phaseTransitionActive) revert RngLocked();
///
///         At BAF time, rngLockedFlag is true and phaseTransitionActive is false, so
///         far-future ticket rolls revert — bricking the game permanently.
///
///         The fix: set phaseTransitionActive = true before _runRewardJackpots and clear
///         it after, bypassing the far-future guard for internal reward distributions.
///
/// @dev Injects 20 BAF leaderboard entries to maximize the probability of hitting the 5%
///      far-future branch. With ~20 rolls, P(at least one far-future) ≈ 64%. Multiple
///      VRF words are tested via the fuzz parameter to push coverage higher.
///      If any VRF word causes RngLocked revert, advanceGame halts and the game is stuck
///      at level 10 — caught by assertGt(finalLevel, 10).
contract BafFarFutureTicketsTest is DeployProtocol {
    uint256 private constant PRIZE_POOLS_PACKED_SLOT = 2;

    address private buyer;
    address[20] private bafPlayers;

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);

        buyer = makeAddr("baf_ff_buyer");
        vm.deal(buyer, 100_000 ether);
        vm.deal(address(game), 2_000 ether);

        for (uint256 i = 0; i < 20; i++) {
            bafPlayers[i] = makeAddr(string.concat("baf_player_", vm.toString(i)));
            vm.deal(bafPlayers[i], 10_000 ether);
        }
    }

    /// @notice Fuzz: BAF must complete without RngLocked revert for any VRF word.
    /// @param vrfSeed Fuzz input used to derive VRF words during advancement.
    function testBafFarFutureTicketsNoRevert(uint256 vrfSeed) public {
        uint256 simTime = block.timestamp;
        bool bafInjected = false;

        for (uint256 day = 0; day < 600; day++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            if (currentLevel > 10) break;

            // Inject BAF entries once we're approaching level 10
            if (currentLevel >= 9 && !bafInjected) {
                _injectBafPlayers(10);
                bafInjected = true;
            }

            simTime += 1 days + 1;
            vm.warp(simTime);

            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending(vrfSeed);

                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }

        uint24 finalLevel = game.level();
        assertGt(finalLevel, 10, "Game must advance past level 10 (BAF fires here)");
        assertTrue(bafInjected, "BAF players were injected");
    }

    /// @notice Deterministic: run with several known seeds to catch the far-future path.
    function testBafFarFutureSeed0xDEAD() public { _runWithSeed(0xDEAD); }
    function testBafFarFutureSeed0xBEEF() public { _runWithSeed(0xBEEF); }
    function testBafFarFutureSeed0xCAFE() public { _runWithSeed(0xCAFE); }
    function testBafFarFutureSeedRegression() public { _runWithSeed(uint256(keccak256("far_future_regression"))); }
    function testBafFarFutureSeedRngLocked() public { _runWithSeed(uint256(keccak256("rng_locked_bug"))); }

    function _runWithSeed(uint256 vrfSeed) private {
        uint256 simTime = block.timestamp;
        bool bafInjected = false;

        for (uint256 day = 0; day < 600; day++) {
            uint24 currentLevel = game.level();
            if (game.gameOver()) break;
            if (currentLevel > 10) break;

            if (currentLevel >= 9 && !bafInjected) {
                _injectBafPlayers(10);
                bafInjected = true;
            }

            simTime += 1 days + 1;
            vm.warp(simTime);

            _seedNextPrizePool(49.9 ether);
            _seedFuturePrizePool(100 ether);
            _buyTickets(buyer, 4000);

            for (uint256 j = 0; j < 80; j++) {
                _fulfillVrfIfPending(vrfSeed);

                (bool ok, ) = address(game).call(
                    abi.encodeWithSignature("advanceGame()")
                );
                if (!ok) break;
            }
        }

        uint24 finalLevel = game.level();
        assertTrue(bafInjected, "BAF players were injected");
        assertGt(finalLevel, 10, "Game must advance past level 10 (BAF fires here)");
    }

    // ==================== Internal Helpers ====================

    /// @notice Inject N players into BAF leaderboard at the given level.
    function _injectBafPlayers(uint24 lvl) internal {
        for (uint256 i = 0; i < bafPlayers.length; i++) {
            // Stagger stakes so multiple players appear in different BAF slices
            uint256 stake = (100 + i * 50) * 1 ether;
            vm.prank(address(coin));
            jackpots.recordBafFlip(bafPlayers[i], lvl, stake);
        }
    }

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
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth) {} catch {}
    }

    function _fulfillVrfIfPending(uint256 seed) internal {
        uint256 reqId = mockVRF.lastRequestId();
        if (reqId == 0) return;

        (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
        if (fulfilled) return;

        uint256 randomWord = uint256(keccak256(abi.encode(seed, block.timestamp, game.level(), reqId)));
        try mockVRF.fulfillRandomWords(reqId, randomWord) {} catch {}
    }
}
