// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {IJackpotBattle} from "../../contracts/interfaces/IJackpotBattle.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {MintPaymentKind} from "../../contracts/interfaces/IDegenerusGame.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {BoxOrderLib} from "../helpers/BoxOrderLib.sol";
import {RecyclingState} from "../helpers/RecyclingState.sol";
import {Vm} from "forge-std/Vm.sol";

/// @dev The large-cycle fixture changes only already-funded prize pools. Checkpoint
/// readers never write: request words, locks, ticket queues and phase flags remain real.
contract StateEnginePoolFixture is DegenerusGame {
    function enlargePool() external { _setPrizePools(2000 ether, uint128(_getFuturePrizePool())); }
    function engineCheckpoint() external view returns (bool battle, uint8 kind, bool ticketLeg, bool transition) {
        return (_jackpotBattlePending(), jackpotWork.kind,
            _earlyBirdLegPending() || dailyJackpotCoinTicketsPending, phaseTransitionActive);
    }
}

/// @dev Real deployed modules and real VRF request/fulfillment lifecycle. No cursor writes,
/// etched workers, mocked payouts or synthetic session publication are used in these checks.
contract StateEngineIntegrationTest is DeployProtocol {
    address private constant MINER = address(0xA11CE999);
    address private constant ALICE = address(0xA11CE);
    bytes32 private constant MINER_WORK = keccak256("MinerWork(address,uint8,uint256,uint256)");
    uint256 private constant HIGH_GAS = 15_000_000;
    uint256 private constant LOW_GAS = 9_500_000;
    bytes32 private constant JACKPOT_ETH = keccak256("JackpotEthWin(address,uint24,uint16,uint256,uint256)");
    bytes32 private constant JACKPOT_TICKET = keccak256("JackpotTicketWin(address,uint24,uint16,uint32,uint24,uint256,bool)");
    bytes32 private jackpotTranscript;
    uint256 private payoutCalls;
    uint256 private largestCall;


    function setUp() public {
        _deployProtocol();
        vm.fee(1 gwei);
        mockVRF.fundSubscription(1, 1000 ether);
        vm.warp(vm.getBlockTimestamp() + 1 days);
        _drain(HIGH_GAS);
    }

    function _step(uint256 supplied) private returns (uint256 used, uint256 reward) {
        vm.recordLogs();
        vm.prank(MINER);
        uint256 before = gasleft();
        game.mineFlip{gas: supplied}();
        used = before - gasleft() + 21_064;
        assertLe(used, supplied + 30_000, "engine call exceeds supplied gas plus intrinsic/frame");
        if (used > largestCall) largestCall = used;
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool paidJackpot;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter == address(game)
                && (logs[i].topics[0] == JACKPOT_ETH || logs[i].topics[0] == JACKPOT_TICKET)) {
                jackpotTranscript = keccak256(abi.encode(jackpotTranscript, logs[i].topics, logs[i].data));
                paidJackpot = true;
            }
            if (logs[i].emitter == address(game) && logs[i].topics[0] == MINER_WORK) {
                (uint8 action, uint256 measured, uint256 paid) = abi.decode(logs[i].data, (uint8, uint256, uint256));
                if (measured < 1_000_000 || action == uint8(DegenerusGameStorage.MinerAction.Terminal) || game.gameOver()) {
                    assertEq(paid, 0, "sub-threshold or terminal work must be unpaid");
                } else {
                    assertGt(paid, 0, "normal measured work above the cutoff earns compensation");
                }
                reward += paid;
            }
        }
        if (paidJackpot) ++payoutCalls;
    }

    function _fulfillPending() private {
        uint256 request = mockVRF.lastRequestId();
        if (request == 0) return;
        (,, bool fulfilled) = mockVRF.pendingRequests(request);
        if (!fulfilled) mockVRF.fulfillRandomWords(request, uint256(keccak256(abi.encode("engine parity", request))) | 2);
    }

    function _drain(uint256 supplied) private returns (uint256 calls, uint256 paid) {
        for (; calls < 1000; ++calls) {
            _fulfillPending();
            if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) return (calls, paid);
            (, uint256 reward) = _step(supplied);
            paid += reward;
        }
        revert("engine fixture failed to finish the committed lifecycle");
    }

    function _queueMixedWork() private returns (uint24 burnDay) {
        vm.deal(address(sdgnrs), 10_000 ether);
        uint256 amount = sdgnrs.totalSupply() * 16 / 1000;
        vm.prank(address(game));
        sdgnrs.transferFromPool(sDGNRS.Pool.Reward, ALICE, amount);
        vm.prank(ALICE);
        sdgnrs.burn(amount);
        burnDay = sdgnrs.pendingResolveDay();
        (,,,, uint256 price) = game.purchaseInfo();
        for (uint256 i; i < 6; ++i) {
            address player = address(uint160(0xB0000 + i));
            vm.deal(player, price * 100);
            vm.prank(player);
            game.purchase{value: price * 100}(player, 0, BoxOrderLib.boSmalls(100), bytes32(0), MintPaymentKind.DirectEth, false);
        }
        vm.deal(ALICE, 1 ether);
        vm.prank(ALICE);
        game.placeDegeneretteBet{value: 0.025 ether}(ALICE, 0, 0.005 ether, 5, 0);
        vm.warp(vm.getBlockTimestamp() + 1 days);
    }

    function _outcome(uint24 burnDay) private view returns (bytes32 digest) {
        digest = keccak256(abi.encode(game.level(), game.currentDayView(), sdgnrs.redemptionPeriods(burnDay),
            sdgnrs.pendingRedemptionEthValue(), game.claimableWinningsOf(ALICE), coinflip.coinflipAmount(ALICE),
            mockVRF.lastRequestId(), game.rngComplete()));
        for (uint256 i; i < 6; ++i) {
            address player = address(uint160(0xB0000 + i));
            digest = keccak256(abi.encode(digest, game.claimableWinningsOf(player), coinflip.coinflipAmount(player)));
        }
    }

    function test_AppendedModulesHavePinnedCodeAndRealEngineBootstraps() public view {
        assertEq(address(ticketModule), ContractAddresses.GAME_TICKET_MODULE);
        assertEq(address(minerModule), ContractAddresses.GAME_MINER_MODULE);
        assertEq(address(rngModule), ContractAddresses.GAME_RNG_MODULE);
        assertEq(address(jackpotDrawModule), ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        assertGt(address(ticketModule).code.length, 0);
        assertGt(address(minerModule).code.length, 0);
        assertGt(address(rngModule).code.length, 0);
        assertTrue(game.rngComplete());
    }

    function test_GasPartitionsPreservePlayerOutcomesAndRewardMeasuredWork() public {
        uint24 burnDay = _queueMixedWork();
        uint256 snap = vm.snapshotState();
        (, uint256 paid) = _drain(LOW_GAS);
        assertGt(paid, 0, "calls supplied less than 10M gas can earn compensation");
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
        bytes32 low = _outcome(burnDay);
        vm.revertToState(snap);
        (, paid) = _drain(HIGH_GAS);
        assertGt(paid, 0, "normal measured work earns metered incentive");
        assertEq(_outcome(burnDay), low, "gas partitions changed player results or request sequence");
    }

    function test_SmallGasCheckpointCannotRequestRngOrEarnBounty() public {
        _queueMixedWork();
        uint256 request = mockVRF.lastRequestId();
        uint256 prior = coinflip.coinflipAmount(MINER);
        _step(800_000);
        assertEq(mockVRF.lastRequestId(), request, "insufficient boundary gas must leave request pending");
        assertEq(coinflip.coinflipAmount(MINER), prior);
        _drain(HIGH_GAS);
    }

    function test_NewRequestCannotReplaceAnUnfinishedConsumerWord() public {
        _queueMixedWork();
        bool observed;
        for (uint256 i; i < 100; ++i) {
            _fulfillPending();
            uint8 stage = game.rngConsumerStage();
            if (stage >= 1 && stage <= 6) {
                observed = true;
                uint256 request = mockVRF.lastRequestId();
                uint48 read = RecyclingState.readBuffer(address(game));
                uint256 word = RecyclingState.word(address(game), read);
                vm.expectRevert();
                game.requestLootboxRng();
                assertEq(mockVRF.lastRequestId(), request);
                assertEq(RecyclingState.word(address(game), read), word);
                break;
            }
            _step(LOW_GAS);
        }
        assertTrue(observed, "fixture must expose a real unfinished consumer stage");
        _drain(HIGH_GAS);
        assertTrue(game.rngComplete());
    }
    function _phaseCheckpoint() private returns (bool battle, uint8 kind, bool ticketLeg, bool transition) {
        bytes memory production = address(game).code;
        vm.etch(address(game), type(StateEnginePoolFixture).runtimeCode);
        (battle, kind, ticketLeg, transition) = StateEnginePoolFixture(payable(address(game))).engineCheckpoint();
        vm.etch(address(game), production);
    }

    function _coolEngine() private {
        vm.cool(address(game)); vm.cool(address(sdgnrs)); vm.cool(address(coinflip));
        vm.cool(address(crapsBattle)); vm.cool(address(mockStETH));
        vm.cool(ContractAddresses.GAME_MINER_MODULE); vm.cool(ContractAddresses.GAME_ADVANCE_MODULE);
        vm.cool(ContractAddresses.GAME_RNG_MODULE); vm.cool(ContractAddresses.GAME_TICKET_MODULE);
        vm.cool(ContractAddresses.GAME_JACKPOT_MODULE); vm.cool(ContractAddresses.GAME_JACKPOT_DRAW_MODULE);
        vm.cool(ContractAddresses.GAME_FOILPACK_MODULE); vm.cool(ContractAddresses.GAME_AFKING_MODULE);
    }

    function _driveCycle(bool split) private returns (uint256 checkpoints) {
        bool entered;
        for (uint256 daysRun; daysRun < 8; ++daysRun) {
            vm.warp(vm.getBlockTimestamp() + 1 days);
            for (uint256 calls; calls < 1000; ++calls) {
                _fulfillPending();
                if (!game.advanceDue() && !game.rngLocked() && game.rngComplete()) break;
                (, bool jackpot,,,) = game.purchaseInfo();
                (bool battle, uint8 kind, bool tickets, bool transition) = _phaseCheckpoint();
                uint256 supplied = HIGH_GAS;
                if (split && game.nextMinerAction() == uint8(DegenerusGameStorage.MinerAction.DailyPhase) && jackpot && !transition) {
                    if (battle) {
                        (,, bool started,) = IJackpotBattle(address(crapsBattle)).jackpotProgress();
                        if (started) supplied = 3_000_000;
                    } else supplied = kind == 2 ? 7_500_000 : 2_000_000;
                }
                uint256 request = mockVRF.lastRequestId();
                _coolEngine();
                _step(supplied);
                (, kind, tickets,) = _phaseCheckpoint();
                if (kind != 0 || tickets) {
                    ++checkpoints;
                    assertTrue(game.rngLocked(), "daily payout cursor outlived its RNG lock");
                    assertEq(mockVRF.lastRequestId(), request, "payout checkpoint requested a replacement word");
                    assertEq(game.rngConsumerStage(), 0, "basic read consumers bypassed daily payout");
                }
                (, jackpot,,,) = game.purchaseInfo();
                entered = entered || jackpot;
                if (calls == 999) revert("full cycle did not finish daily work");
            }
            (, bool jackpot,,,) = game.purchaseInfo();
            if (entered && !jackpot && game.rngComplete()) return checkpoints;
        }
        revert("purchase jackpot purchase cycle did not finish");
    }

    function _cycleBalances() private view returns (bytes32 digest) {
        digest = keccak256(abi.encode(game.level(), game.currentDayView(), mockVRF.lastRequestId(),
            game.nextPrizePoolView(), game.futurePrizePoolView(), game.currentPrizePoolView()));
        for (uint256 i; i < 32; ++i) {
            address player = address(uint160(0xF1000 + i));
            digest = keccak256(abi.encode(digest, game.claimableWinningsOf(player), coinflip.coinflipAmount(player)));
        }
    }

    function test_ColdPurchaseJackpotPurchaseCycleKeepsLocksAndPartitionInvariantPayouts() public {
        (,,,, uint256 price) = game.purchaseInfo();
        for (uint256 i; i < 32; ++i) {
            address player = address(uint160(0xF1000 + i));
            vm.deal(player, price * 100);
            vm.prank(player);
            game.purchase{value: price * 100}(player, 40_000, 0, bytes32(0), MintPaymentKind.DirectEth, false);
        }
        vm.deal(address(game), address(game).balance + 2000 ether);
        bytes memory production = address(game).code;
        vm.etch(address(game), type(StateEnginePoolFixture).runtimeCode);
        StateEnginePoolFixture(payable(address(game))).enlargePool();
        vm.etch(address(game), production);
        uint256 snap = vm.snapshotState();
        uint256 checkpoints = _driveCycle(true);
        assertGt(checkpoints, 1, "multiple daily payout checkpoints must be exercised");
        assertGt(payoutCalls, 1, "multiple payout calls must execute");
        assertTrue(game.rngComplete());
        bytes32 expectedTranscript = jackpotTranscript;
        bytes32 expectedBalances = _cycleBalances();
        emit log_named_uint("split_cycle_maximum_cold_engine_gas_with_intrinsic", largestCall);
        vm.revertToState(snap);
        _driveCycle(false);
        assertEq(jackpotTranscript, expectedTranscript, "partitions changed ordered ETH/ticket winners");
        assertEq(_cycleBalances(), expectedBalances, "partitions changed balances, pools or request sequence");
        assertGt(largestCall - 21_064, 10_000_000, "real composed execution exceeds the removed transaction cap");
        emit log_named_uint("full_cycle_maximum_cold_engine_gas_with_intrinsic", largestCall);
    }

}
