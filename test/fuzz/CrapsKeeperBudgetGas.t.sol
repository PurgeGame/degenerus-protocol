// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {JackpotBattle} from "../../contracts/JackpotBattle.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";

/// @notice Native measured-gas admission against real protocol payouts and the real router.
/// @dev The legacy filename is retained for existing gas-suite selection. No walk-unit conversion,
/// post-seat overshoot, or caller-provided legacy budget remains part of the metering contract.
contract CrapsKeeperBudgetGasTest is DeployProtocol {
    address private constant MINER = address(0xC0FFEE);
    uint64 private slot;
    uint48 private index;
    uint256 private constant FIELD = 160;
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");

    function setUp() public {
        _deployProtocol();
        vm.fee(1 gwei);
        mockVRF.fundSubscription(1, 1000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        for (uint256 i; i < 500; ++i) {
            uint256 request = mockVRF.lastRequestId();
            if (request != 0) {
                (,,bool done) = mockVRF.pendingRequests(request);
                if (!done) mockVRF.fulfillRandomWords(request, 0xC01D);
            }
            if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) break;
            game.mineFlip{gas: 15_000_000}();
        }
        assertTrue(game.rngComplete());
        crapsBattle.setBattleCreator(address(this), true);
        slot = crapsBattle.createBattle(300, 25, 1000, 75, uint40(vm.getBlockTimestamp() + 60), true, 255);
        uint32 board = 1 | uint32(1) << 3 | uint32(1) << 6 | uint32(1) << 9
            | uint32(1) << 12 | uint32(1) << 15 | uint32(1) << 18;
        for (uint256 i; i < FIELD; ++i) {
            address player = address(uint160(0xC01000 + i));
            vm.prank(address(game)); coin.mintForGame(player, 100_000_000 ether);
            vm.prank(player); crapsBattle.enterBattle(slot, board, i == 0 ? 255 : 1);
        }
        vm.warp(vm.getBlockTimestamp() + 60);
        index = crapsBattle.closeBattle(slot);
        uint256 prior = mockVRF.lastRequestId();
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == prior; ++i) game.mineFlip{gas: 15_000_000}();
        assertGt(mockVRF.lastRequestId(), prior, "real request seals the custom field");
        mockVRF.fulfillRandomWords(mockVRF.lastRequestId(), 0xBADC0DE);
        // Publish and empty preceding categories, stopping safely before the first whole seat.
        for (uint256 i; i < 100 && game.rngConsumerStage() != 6; ++i) game.mineFlip{gas: 800_000}();
        assertEq(game.rngConsumerStage(), 6);
        assertEq(RecyclingState.readBuffer(address(game)), index);
        assertEq(crapsBattle.bonusCursorOf(slot), 0);
    }

    function _work(uint256 allowance) private returns (MineFlipGas.Result memory result, uint256 used) {
        vm.prank(address(game));
        uint256 before = gasleft();
        result = JackpotBattle(address(crapsBattle)).runCrapsReadWork{gas: 15_000_000}(index, allowance);
        used = before - gasleft();
    }

    function test_ZeroAndSubSeatRemainderCannotSpendAnAtomicSeat() public {
        (MineFlipGas.Result memory result,) = _work(0);
        assertFalse(result.progressed);
        (result,) = _work(1_000_000);
        assertFalse(result.progressed);
        assertEq(crapsBattle.bonusCursorOf(slot), 0);
        uint256 used;
        (result, used) = _work(3_000_000);
        assertTrue(result.progressed);
        assertGt(crapsBattle.bonusCursorOf(slot), 0);
        assertLt(used, 3_000_000, "complete worker call fits parent remainder");
    }

    function test_AllowanceAboveFormerBodyCapCanMakeProgress() public {
        (MineFlipGas.Result memory result, uint256 used) = _work(14_000_000);
        assertTrue(result.progressed);
        assertGt(crapsBattle.bonusCursorOf(slot), 0);
        assertLt(used, 14_000_000, "worker retains the parent's return allowance");
    }

    function test_EntryBelowTenMillionPaysWhenMeasuredWorkExceedsOneMillion() public {
        vm.cool(address(game)); vm.cool(address(crapsBattle)); vm.cool(address(coinflip));
        vm.cool(ContractAddresses.JACKPOT_BATTLE); vm.cool(ContractAddresses.GAME_MINER_MODULE);
        uint256 prior = coinflip.coinflipAmount(MINER);
        vm.recordLogs();
        vm.prank(MINER);
        uint256 before = gasleft();
        game.mineFlip{gas: 9_500_000}();
        uint256 used = before - gasleft() + 21_064;
        emit log_named_uint("cold_real_craps_miner_including_intrinsic", used);
        assertLt(used, 9_530_000, "execution fits supplied gas plus intrinsic/frame");
        assertGt(crapsBattle.bonusCursorOf(slot), 0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 workEvents;
        uint256 reward;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (, uint256 measured, uint256 paid) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                assertGe(measured, 1_000_000, "real work crosses the measured-gas reward cutoff");
                assertGt(paid, 0, "entry gas below 10M must not disqualify useful work");
                ++workEvents;
                reward += paid;
            }
        }
        assertEq(workEvents, 1);
        assertEq(coinflip.coinflipAmount(MINER) - prior, reward);
        if (crapsBattle.bonusCursorOf(slot) < FIELD) _finish(14_000_000, true);
        assertEq(crapsBattle.bonusCursorOf(slot), FIELD, "later checkpoints complete the field");
    }

    function _mineFieldAtGasPrices(uint256 baseFee, uint256 transactionGasPrice)
        private returns (bytes32 digest, uint256 measured, uint256 reward)
    {
        vm.fee(baseFee);
        vm.txGasPrice(transactionGasPrice);
        vm.cool(address(game)); vm.cool(address(crapsBattle)); vm.cool(address(coinflip));
        vm.cool(ContractAddresses.JACKPOT_BATTLE); vm.cool(ContractAddresses.GAME_MINER_MODULE);
        uint256 price = game.mintPrice();
        uint256 prior = coinflip.coinflipAmount(MINER);
        uint256 lockFactor = game.rngLocked() ? 2 : 1;
        vm.recordLogs();
        vm.prank(MINER);
        game.mineFlip{gas: 9_500_000}();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 workEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (, measured, reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                ++workEvents;
            }
        }
        assertEq(workEvents, 1);
        assertGe(measured, 1_000_000);
        uint256 rate = baseFee < 0.5 gwei ? baseFee : 0.5 gwei;
        assertEq(reward, _wholeFlip((measured - 1_000_000) * rate * 1000 ether * 3000 * lockFactor / (price * 10_000)));
        assertEq(coinflip.coinflipAmount(MINER) - prior, reward);
        if (crapsBattle.bonusCursorOf(slot) < FIELD) _finish(14_000_000, true);
        assertEq(crapsBattle.bonusCursorOf(slot), FIELD);
        digest = keccak256(abi.encode(crapsBattle.battleOf(crapsBattle.keyOfSlot(slot)),
            crapsBattle.bonusCursorOf(slot), game.rngComplete(), mockVRF.lastRequestId()));
        // Miner compensation creates a future stake; compare every actual field participant.
        for (uint256 i; i < FIELD; ++i) {
            digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(address(uint160(0xC01000 + i)))));
        }
    }

    function test_TransactionGasPriceCannotChangeRewardOrPlayerOutcomes() public {
        uint256 snap = vm.snapshotState();
        (bytes32 expected, uint256 measured, uint256 reward) = _mineFieldAtGasPrices(0.25 gwei, 1 gwei);
        assertGt(reward, 0);
        vm.revertToState(snap);
        (bytes32 actual, uint256 highTipMeasured, uint256 highTipReward) = _mineFieldAtGasPrices(0.25 gwei, 100 gwei);
        assertEq(actual, expected);
        assertEq(highTipMeasured, measured, "caller gas price cannot change measured work");
        assertEq(highTipReward, reward, "caller gas price cannot increase compensation");
    }

    function test_CappedBaseFeeChangesOnlyCompensationAndZeroFeePaysZero() public {
        uint256 snap = vm.snapshotState();
        (bytes32 expected, uint256 measured, uint256 lowReward) = _mineFieldAtGasPrices(0.25 gwei, 1 gwei);
        vm.revertToState(snap);
        (bytes32 cappedDigest, uint256 cappedMeasured, uint256 cappedReward) = _mineFieldAtGasPrices(1 gwei, 2 gwei);
        assertEq(cappedDigest, expected);
        assertEq(cappedMeasured, measured);
        assertGt(cappedReward, lowReward);
        vm.revertToState(snap);
        (bytes32 actual, uint256 highMeasured, uint256 highReward) = _mineFieldAtGasPrices(50 gwei, 100 gwei);
        assertEq(actual, expected, "base fee cannot change player payouts or request sequence");
        assertEq(highMeasured, measured);
        assertEq(highReward, cappedReward, "base fee above the cap cannot raise compensation");
        vm.revertToState(snap);
        (actual, highMeasured, highReward) = _mineFieldAtGasPrices(0, 0);
        assertEq(actual, expected);
        assertEq(highMeasured, measured);
        assertEq(highReward, 0, "zero base fee has no reward floor");
    }

    function test_HighEntryFinalCompletionTailRemainsUnpaid() public {
        _finish(14_000_000, true);
        (uint256 request, uint64 finalSlot) = _requestSingleSeatField();
        mockVRF.fulfillRandomWords(request, 0xC002);
        for (uint256 i; i < 100 && game.rngConsumerStage() != 6; ++i) game.mineFlip{gas: 800_000}();
        assertEq(game.rngConsumerStage(), 6);
        assertEq(crapsBattle.bonusCursorOf(finalSlot), 0);
        assertFalse(game.rngComplete(), "one final seat remains");
        uint256 prior = coinflip.coinflipAmount(MINER);
        vm.recordLogs();
        vm.prank(MINER);
        game.mineFlip{gas: 15_000_000}();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 workEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (, uint256 measured, uint256 reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                assertGt(measured, 0);
                assertLt(measured, 1_000_000, "the completion tail is below the strict cutoff");
                assertEq(reward, 0, "finishing a cohort does not exempt a small tail");
                ++workEvents;
            }
        }
        assertEq(workEvents, 1);
        assertEq(coinflip.coinflipAmount(MINER), prior);
        assertEq(crapsBattle.bonusCursorOf(finalSlot), 1, "unpaid final tail still settles the player");
        assertTrue(game.rngComplete());
    }

    function _requestSingleSeatField() private returns (uint256 request, uint64 nextSlot) {
        assertTrue(game.rngComplete());
        vm.fee(1 gwei);
        nextSlot = crapsBattle.createBattle(300, 25, 1000, 75,
            uint40(vm.getBlockTimestamp() + 60), true, 255);
        address player = address(0xD00DCAFE);
        vm.prank(address(game)); coin.mintForGame(player, 100_000_000 ether);
        uint32 board = 1 | uint32(1) << 3 | uint32(1) << 6 | uint32(1) << 9
            | uint32(1) << 12 | uint32(1) << 15 | uint32(1) << 18;
        vm.prank(player); crapsBattle.enterBattle(nextSlot, board, 1);
        vm.warp(vm.getBlockTimestamp() + 60);
        crapsBattle.closeBattle(nextSlot);
        uint256 prior = mockVRF.lastRequestId();
        for (uint256 i; i < 100 && mockVRF.lastRequestId() == prior; ++i) game.mineFlip{gas: 15_000_000}();
        request = mockVRF.lastRequestId();
        assertGt(request, prior);
    }

    /// @dev Coinflip stakes are whole FLIP: a positive priced reward pays at least 1 FLIP and
    ///      larger rewards floor to whole FLIP (DegenerusGameMinerModule.mineFlip).
    function _wholeFlip(uint256 priced) private pure returns (uint256) {
        if (priced == 0) return 0;
        return priced < 1 ether ? 1 ether : (priced / 1 ether) * 1 ether;
    }

    /// @dev The miner reward clock's origin: `rngRequestTime`, slot 0 bits 48..95. The engine
    ///      prices a call from the later of this and the current day reset.
    function _requestedAt() private view returns (uint48) {
        return uint48(uint256(vm.load(address(game), bytes32(0))) >> 48);
    }

    function test_VaultOwnerAndOrdinaryMinerBothWaitForAdministrativeRetry() public {
        _finish(14_000_000, true);
        (uint256 request,) = _requestSingleSeatField();
        vm.warp(vm.getBlockTimestamp() + 20 hours + 1);
        assertTrue(vault.isVaultOwner(ContractAddresses.CREATOR));
        assertFalse(vault.isVaultOwner(MINER));
        vm.prank(ContractAddresses.CREATOR);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Wait));
        vm.prank(MINER);
        assertEq(game.nextMinerAction(), uint8(DegenerusGameStorage.MinerAction.Wait));
        vm.prank(ContractAddresses.CREATOR);
        vm.expectRevert();
        game.mineFlip{gas: 15_000_000}();
        vm.prank(MINER);
        vm.expectRevert();
        game.mineFlip{gas: 15_000_000}();
        assertEq(mockVRF.lastRequestId(), request, "neither caller can retry through mining");
    }

    /// @dev The reward clock runs from the request: callbacks — duplicate, wrong-id, reserved or
    ///      accepted — never move it, nor do no-op checkpoints or partial work; only the next
    ///      request restarts it.
    function test_RequestAgeSurvivesCallbacksNoopAndPartialWorkAndOnlyANewRequestResets() public {
        uint48 requested = _requestedAt();
        assertEq(requested, vm.getBlockTimestamp(), "the sealing request stamps the reward clock");
        uint256 request = mockVRF.lastRequestId();
        vm.warp(vm.getBlockTimestamp() + 31 minutes);
        mockVRF.fulfillRandomWordsRaw(request, address(game), 0xAABBCC);
        assertEq(_requestedAt(), requested, "duplicate callback cannot reset age");
        // A call that cannot fit one whole seat makes no progress, and a zero-progress mineFlip
        // reverts instead of committing a no-op (be793ed7c).
        vm.prank(MINER);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        game.mineFlip{gas: 800_000}();
        assertEq(crapsBattle.bonusCursorOf(slot), 0);
        assertEq(_requestedAt(), requested, "no-op checkpoint cannot reset age");

        vm.fee(50 gwei);
        uint256 price = game.mintPrice();
        uint256 lockFactor = game.rngLocked() ? 2 : 1;
        vm.recordLogs();
        vm.prank(MINER);
        game.mineFlip{gas: 9_500_000}();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 workEvents;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (, uint256 measured, uint256 reward) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                assertGe(measured, 1_000_000);
                assertEq(reward, _wholeFlip((measured - 1_000_000) * 1 gwei * 1000 ether * 7_500 * lockFactor / (price * 10_000)),
                    "31-minute backlog uses the first raised cap and multiplier");
                ++workEvents;
            }
        }
        assertEq(workEvents, 1);
        assertGt(crapsBattle.bonusCursorOf(slot), 0);
        assertLt(crapsBattle.bonusCursorOf(slot), FIELD, "fixture must leave a real continuation");
        assertEq(_requestedAt(), requested, "partial work retains the original request clock");
        _finish(14_000_000, true);
        assertTrue(game.rngComplete());
        assertEq(_requestedAt(), requested, "completion leaves the request clock where it was");

        (uint256 replacement,) = _requestSingleSeatField();
        assertGt(replacement, request);
        uint48 restarted = _requestedAt();
        assertEq(restarted, vm.getBlockTimestamp(), "a new request restarts the reward clock");
        assertGt(restarted, requested);
        vm.warp(vm.getBlockTimestamp() + 15);
        mockVRF.fulfillRandomWordsRaw(request, address(game), 0x1234);
        mockVRF.fulfillRandomWordsRaw(replacement, address(game), 0);
        mockVRF.fulfillRandomWordsRaw(replacement, address(game), 1);
        assertEq(_requestedAt(), restarted, "wrong IDs and reserved words cannot reset the clock");
        mockVRF.fulfillRandomWords(replacement, 0xC002);
        assertEq(_requestedAt(), restarted, "an accepted callback does not move the reward clock");
        vm.warp(vm.getBlockTimestamp() + 15);
        mockVRF.fulfillRandomWordsRaw(replacement, address(game), 0xC003);
        assertEq(_requestedAt(), restarted, "the request clock is immutable through publication");
    }

    function _finish(uint256 allowance, bool cold) private returns (bytes32 digest) {
        for (uint256 i; i < FIELD; ++i) {
            if (cold) { vm.cool(address(crapsBattle)); vm.cool(address(coinflip)); }
            (MineFlipGas.Result memory result, uint256 used) = _work(allowance);
            assertLt(used, allowance);
            assertTrue(result.progressed);
            if (result.done) {
                digest = keccak256(abi.encode(crapsBattle.battleOf(crapsBattle.keyOfSlot(slot)),
                    crapsBattle.bonusCursorOf(slot)));
                for (uint256 j; j < FIELD; ++j) {
                    address player = address(uint160(0xC01000 + j));
                    digest = keccak256(abi.encode(digest, coinflip.coinflipAmount(player)));
                }
                return digest;
            }
        }
        revert("funded native field did not complete");
    }

    function test_ColdRemainderPartitionsPreserveFieldAndEveryPlayerPayment() public {
        uint256 snap = vm.snapshotState();
        bytes32 small = _finish(3_000_000, true);
        vm.revertToState(snap);
        assertEq(_finish(14_000_000, false), small);
    }

    function test_SubSeatGasMakesNoProgressAndEarnsNoReward() public {
        uint256 prior = coinflip.coinflipAmount(MINER);
        // Sub-seat gas cannot admit the atomic seat; the zero-progress call reverts (be793ed7c).
        vm.prank(MINER);
        vm.expectRevert(MineFlipGas.InsufficientExecutionGas.selector);
        game.mineFlip{gas: 800_000}();
        assertEq(crapsBattle.bonusCursorOf(slot), 0);
        assertEq(coinflip.coinflipAmount(MINER), prior);
        _finish(14_000_000, true);
    }
}
