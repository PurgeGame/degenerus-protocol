// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";

/// @title BafFarFutureTicketsTest -- BAF ticket legs paid under the daily RNG lock never revert
///        on a far-future roll, so the level-10 BAF completes and the game moves past it.
///
/// @notice Path: the level-10 consolidation (`runBafJackpot`) arms the BAF award stage; the
///         stage (`runBafAwards`, Advance stage 19) pays groups of eight awards under the daily
///         RNG lock. Each ticket leg rolls through `_awardJackpotTickets` -> `_jackpotTicketRoll`,
///         which targets five to fifty levels above the floor with 5% probability per roll and
///         queues through `_queueEntries(winner, target, entries, rngBypass = true)`. The sink's
///         far-future guard (`isFarFuture && rngLockedFlag && !rngBypass` -> `RngLocked`) applies
///         to player purchases only, so a far-future roll inside the stage registers its lane
///         instead of reverting.
///
/// @dev Injects 20 scored BAF players at level 10 so the stage pays awards with ticket legs; the
///      fuzz parameter and the fixed seeds vary the words. Every day is cranked under a realistic
///      per-call allowance and any stop other than mineFlip's own stop errors fails the run; a
///      halted stage would leave the game at level 10, caught by assertGt(finalLevel, 10).
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

            _crankDay(vrfSeed);
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

            _crankDay(vrfSeed);
        }

        uint24 finalLevel = game.level();
        assertTrue(bafInjected, "BAF players were injected");
        assertGt(finalLevel, 10, "Game must advance past level 10 (BAF fires here)");
    }

    // ==================== Internal Helpers ====================

    /// @dev Realistic per-call allowance. Given unbounded gas the engine keeps admitting
    ///      checkpointed chunks while the allowance covers the next declared bound, so an
    ///      unbounded call spends the whole test gas limit on a large legitimate backlog
    ///      (fuzz input 4390: a capped box-spin payout boxes ~13.7k ETH of value for sDGNRS
    ///      and queues ~2.96M far-future entries, which the Tickets stage drains at ~15M gas
    ///      per call). Bounded calls drain the same backlog through checkpoints.
    uint256 private constant CRANK_GAS = 16_700_000;
    /// @dev Calls per day: a bounded backlog drain needs far more calls than an unbounded one
    ///      did, and 1,500 x 16.7M stays under the test gas limit, so a day that never stops
    ///      fails below instead of running out of test gas.
    uint256 private constant MAX_CRANKS_PER_DAY = 1_500;

    /// @dev One day of cranking: answer any pending request, then mineFlip under the realistic
    ///      allowance until the engine stops. A call may stop only with one of mineFlip's own
    ///      stop errors; an out-of-gas or any other revert (RngLocked from a far-future BAF
    ///      roll) fails here instead of silently halting the game.
    function _crankDay(uint256 vrfSeed) private {
        for (uint256 j = 0; j < MAX_CRANKS_PER_DAY; j++) {
            _fulfillVrfIfPending(vrfSeed);
            (bool ok, bytes memory err) = address(game).call{gas: CRANK_GAS}(
                abi.encodeWithSignature("mineFlip()")
            );
            if (ok) continue;
            bytes4 sel = err.length >= 4 ? bytes4(err) : bytes4(0);
            assertTrue(
                sel == NO_WORK || sel == RNG_NOT_READY || sel == INSUFFICIENT_EXECUTION_GAS,
                "a realistic-allowance mineFlip stops only on its own stop errors"
            );
            return;
        }
        fail("day never stopped within the call budget");
    }

    bytes4 private constant NO_WORK = bytes4(keccak256("NoWork()"));
    bytes4 private constant RNG_NOT_READY = bytes4(keccak256("RngNotReady()"));
    bytes4 private constant INSUFFICIENT_EXECUTION_GAS = bytes4(keccak256("InsufficientExecutionGas()"));

    /// @notice Inject N players into BAF leaderboard at the given level.
    function _injectBafPlayers(uint24 lvl) internal {
        for (uint256 i = 0; i < bafPlayers.length; i++) {
            // Stagger stakes so multiple players appear in different BAF slices
            uint256 stake = (100 + i * 50) * 1 ether;
            vm.prank(address(coinflip));
            jackpots.recordBafFlip(bafPlayers[i], lvl, stake);
        }
    }

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
        try game.purchase{value: cost}(who, qty, 0, bytes32(0), MintPaymentKind.DirectEth, false) {} catch {}
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
