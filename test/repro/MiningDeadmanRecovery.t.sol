// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {DeadVrfSeeder} from "../fuzz/helpers/DeadVrfSeeder.sol";
import {claimableBalance} from "../helpers/ClaimableBalance.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";

/// @dev Representative dispatcher states, not a claim that arbitrary storage is reachable.
/// The integration tests below separately execute the production terminal workers.
contract MiningDeadmanState is DegenerusGameStorage {
    function seed(MinerAction action) external {
        uint24 today = _wallDay();
        level = 5000;
        purchaseStartDay = today;
        dailyIdx = today;
        dailyComplete = true;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = today;
        _afkingResetDay = today;
        degenesisClosed = 7;
        ticketsFullyProcessed = true;
        humanReadComplete = true;
        rngRequestTime = uint48(block.timestamp);
        rngWordCurrent = 1234;
        _setRngSessionPublished(true);
        _setRngComplete(true);
        if (action != MinerAction.DailyApply) _recordDailyRng(today, 1234);
        if (action >= MinerAction.Publish && action <= MinerAction.CertifyRead) _setRngComplete(false);
        if (action == MinerAction.Wait || action == MinerAction.Publish) {
            _setRngComplete(false);
            _setRngRequest(777);
            _setRngSessionPublished(false);
            if (action == MinerAction.Wait) rngWordCurrent = RNG_WORD_WAITING;
        }
        if (action == MinerAction.Tickets) ticketsFullyProcessed = false;
        if (action == MinerAction.DailyApply || action == MinerAction.DailyPhase) {
            rngLockedFlag = true;
            rngRequestDay = today;
            dailyComplete = false;
        }
        if (action == MinerAction.Afking) _pendingBoxCount = 1;
        if (action == MinerAction.HumanBoxes) humanReadComplete = false;
        if (action == MinerAction.Degenerette) degeneretteReadCount = 1;
        if (action == MinerAction.Decimator) decBattleQueue = 1;
        if (action == MinerAction.Craps) {
            lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngReadBuffer());
        }
        if (action == MinerAction.PrepareSubscriptions || action == MinerAction.RequestDaily) {
            dailyIdx = today - 1;
            lastDailyRequestWallDay = today - 1;
            subsFullyProcessed = action == MinerAction.RequestDaily;
        }
        if (action == MinerAction.RequestMidday) {
            lootboxRngPacked |= uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer());
            vrfCoordinator = IVRFCoordinator(ContractAddresses.VRF_COORDINATOR);
        }
        if (action == MinerAction.GrowthSettle) _setGrowthSettlePending(true);
        if (action == MinerAction.SeizeLoans) _setLoansDuePending(true);
        if (action == MinerAction.DegenesisSettle) {
            degenesisClosed = 6;
            degenesisWord = 1234;
        }
    }

    function action() external view returns (MinerAction) {
        return _nextMinerAction(address(0));
    }

    function ending() external view returns (bool) {
        return _livenessTriggered();
    }
}

contract MiningDeadmanDispatchTest is Test {
    function test_DeadmanPreemptsEveryLiveActionEvenWhenDependencyViewsFail() public {
        vm.warp(uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) * 1 days + 82_621 + 200 days);
        MiningDeadmanState h = new MiningDeadmanState();
        uint256 baseline = vm.snapshotState();
        uint256 checked;
        bytes memory redemption = abi.encodeWithSignature("redemptionSettlementPending_g153837()");
        bytes memory maintenance = abi.encodeWithSignature("minerMaintenancePending_g11976()");
        for (uint8 i; i <= uint8(DegenerusGameStorage.MinerAction.DegenesisSettle); ++i) {
            if (i == uint8(DegenerusGameStorage.MinerAction.Terminal)) continue;
            vm.clearMockedCalls();
            vm.mockCall(
                ContractAddresses.SDGNRS,
                redemption,
                abi.encode(i == uint8(DegenerusGameStorage.MinerAction.Redemption))
            );
            vm.mockCall(
                ContractAddresses.CRAPS,
                maintenance,
                abi.encode(i == uint8(DegenerusGameStorage.MinerAction.Maintenance))
            );
            h.seed(DegenerusGameStorage.MinerAction(i));
            assertEq(uint8(h.action()), i, "non-vacuity: the intended live action is selected");
            uint256 started = vm.getBlockTimestamp();
            vm.warp(started + 14 days - 1);
            assertFalse(h.ending(), "no early hard deadline");
            vm.mockCallRevert(ContractAddresses.SDGNRS, redemption, abi.encodeWithSignature("BrokenView()"));
            vm.mockCallRevert(ContractAddresses.CRAPS, maintenance, abi.encodeWithSignature("BrokenView()"));
            vm.warp(started + 14 days);
            assertTrue(h.ending());
            assertEq(
                uint8(h.action()),
                uint8(DegenerusGameStorage.MinerAction.Terminal),
                "timeout must bypass every live action and its external predicates"
            );
            vm.warp(started + 90 days);
            assertEq(uint8(h.action()), uint8(DegenerusGameStorage.MinerAction.Terminal));
            ++checked;
            assertTrue(vm.revertToState(baseline));
        }
        assertEq(checked, 20, "cover all current nonterminal actions");
    }
}

contract MiningDeadmanTicketState is DeadVrfSeeder {
    function seedBlockedTickets(uint24 lvl) external {
        level = lvl;
        purchaseStartDay = _wallDay();
        dailyIdx = _wallDay();
        dailyComplete = false;
        lastDailyCompletedAt = uint48(block.timestamp);
        lastDailyRequestWallDay = _wallDay();
        rngRequestTime = uint48(block.timestamp);
        rngRequestDay = dailyIdx;
        rngWordCurrent = 1234;
        _setRngRequest(777);
        _setRngSessionPublished(true);
        _setRngComplete(false);
        ticketsFullyProcessed = false;
        rngLockedFlag = true;
        degenesisClosed = 7;
    }

    function readKey(uint24 lvl) external view returns (uint24) {
        return _tqReadKey(lvl);
    }
}

contract MiningDeadmanRecoveryTest is DeployProtocol {
    uint24 private constant LEVEL = 5000;
    address private constant PLAYER = address(0xA11CE);
    uint32 private playerId;
    uint24 private queueKey;
    bytes private productionCode;

    function setUp() public {
        _deployProtocol();
        vm.warp(vm.getBlockTimestamp() + 200 days);
        vm.deal(address(game), 100 ether);
        productionCode = address(game).code;
        vm.etch(address(game), type(MiningDeadmanTicketState).runtimeCode);
        MiningDeadmanTicketState s = MiningDeadmanTicketState(payable(address(game)));
        s.seedBlockedTickets(LEVEL);
        playerId = s.seedQueued(LEVEL + 1, false, PLAYER, 4, 0);
        (uint256 readCount,,) = s.terminalQueues(LEVEL + 1);
        assertEq(readCount, 1);
        queueKey = s.readKey(LEVEL + 1);
        vm.etch(address(game), productionCode);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Tickets));
    }

    function test_PersistentSemanticTicketFailureStillEndsAndPreservesPaidEntries() public {
        _recoverFromTicketFailure(abi.encodeWithSignature("PoisonedEntry()"));
    }

    function test_PersistentGasTicketFailureStillEndsAndPreservesPaidEntries() public {
        _recoverFromTicketFailure(abi.encodeWithSelector(MineFlipGas.WorkGasBound.selector));
    }

    /// @dev Explicit assurance boundary: terminal asset transfers need a functioning token.
    /// A refusal rolls back the sweep; restoring the dependency makes the same work retryable.
    /// While it waits, the claim window stays open and ETH-covered claims never touch stETH.
    function test_FinalSweepWaitsForStethTransfersAndRetriesWithoutLosingFunds() public {
        vm.prank(address(game));
        mockStETH.submit{value: 10 ether}(address(0));
        vm.warp(vm.getBlockTimestamp() + 14 days);
        _finishEnding();
        uint256[] memory refs = new uint256[](1);
        refs[0] = (uint256(1) << 248) | (uint256(queueKey) << 32) | playerId;
        game.claimDeadVrf(playerId, refs);
        uint256 owed = claimableBalance(game, PLAYER);
        assertGt(owed, 1, "non-vacuity: the player holds a claim through the blocked window");
        vm.warp(uint256(game.gameOverTimestamp()) + 30 days);
        uint256 ethBefore = address(game).balance;
        uint256 stethBefore = mockStETH.balanceOf(address(game));
        assertGt(stethBefore, 0, "non-vacuity: the sweep must transfer stETH");
        bytes memory failure = abi.encodeWithSignature("TokenPaused()");
        vm.mockCallRevert(address(mockStETH), abi.encodeWithSelector(mockStETH.transfer.selector), failure);
        vm.expectRevert(failure);
        game.mineRun{gas: 10_000_000}(0);
        assertFalse(game.isFinalSwept());
        assertEq(address(game).balance, ethBefore);
        assertEq(mockStETH.balanceOf(address(game)), stethBefore);
        uint256 cashout = owed - 1 < ethBefore ? owed - 1 : ethBefore;
        uint256 playerBefore = PLAYER.balance;
        vm.prank(PLAYER);
        game.claimWinnings(playerId, cashout);
        assertEq(PLAYER.balance - playerBefore, cashout, "an ETH-covered claim pays during the refusal");
        assertEq(mockStETH.balanceOf(address(game)), stethBefore);
        vm.clearMockedCalls();
        game.mineRun{gas: 10_000_000}(0);
        assertTrue(game.isFinalSwept());
    }

    function _recoverFromTicketFailure(bytes memory failure) private {
        bytes memory ticketCall = abi.encodeWithSignature("runTicketWork_g1150(uint24,uint256)");
        vm.mockCallRevert(ContractAddresses.GAME_TICKET_MODULE, ticketCall, failure);
        vm.expectRevert(failure);
        game.mineRun{gas: 10_000_000}(0);
        assertFalse(game.gameOver());
        vm.warp(vm.getBlockTimestamp() + 14 days);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Terminal));
        // Keep the fault installed throughout recovery. No live ticket worker may be required.
        _finishEnding();
        vm.etch(address(game), type(MiningDeadmanTicketState).runtimeCode);
        (uint256 pot, uint256 total,, uint256 uncreated,,) =
            MiningDeadmanTicketState(payable(address(game))).deadState();
        vm.etch(address(game), productionCode);
        assertGt(pot, 0, "recovery must release actual backing");
        assertEq(uncreated, 400, "all four paid entries survive without materialization");
        assertEq(total, 400);
        uint256 beforeClaim = claimableBalance(game, PLAYER);
        uint256[] memory refs = new uint256[](1);
        refs[0] = (uint256(1) << 248) | (uint256(queueKey) << 32) | playerId;
        game.claimDeadVrf(playerId, refs);
        assertEq(claimableBalance(game, PLAYER) - beforeClaim, pot, "the sole ticket owner can claim the pot");
        vm.warp(uint256(game.gameOverTimestamp()) + 30 days);
        game.mineRun{gas: 10_000_000}(0);
        assertTrue(game.isFinalSwept(), "the persistent live-worker fault cannot block the final sweep");
    }

    function _finishEnding() private {
        for (uint256 i; i < 32 && game.gameOverTimestamp() == 0; ++i) {
            game.mineRun{gas: 10_000_000}(0);
        }
        assertTrue(game.gameOver());
        assertGt(game.gameOverTimestamp(), 0, "check completed payout, not just the gameOver latch");
    }
}
