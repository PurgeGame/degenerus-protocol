// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {MinerProgressHarness} from "./MinerNoProgress.t.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusGameStorage} from "../../contracts/storage/DegenerusGameStorage.sol";
import {DegenerusGameMinerModule} from "../../contracts/modules/DegenerusGameMinerModule.sol";
import {IVRFCoordinator} from "../../contracts/interfaces/IVRFCoordinator.sol";

contract MinerMiddayEligibilityHarness is MinerProgressHarness {
    function seedValue(uint40 pendingEth, uint32 threshold, uint40 pendingFlip, bool crapsWork) external {
        _lrWrite(LR_PENDING_ETH_SHIFT, LR_PENDING_ETH_MASK, pendingEth);
        _lrWrite(LR_THRESHOLD_SHIFT, LR_THRESHOLD_MASK, threshold);
        _lrWrite(LR_PENDING_FLIP_SHIFT, LR_PENDING_FLIP_MASK, pendingFlip);
        uint256 mask = uint256(1) << (LR_CRAPS_PENDING_SHIFT + _rngWriteBuffer());
        if (crapsWork) lootboxRngPacked |= mask;
        else lootboxRngPacked &= ~mask;
    }
    function maxBasefee(uint8 value) external { _lrWrite(LR_MAX_BASEFEE_SHIFT, LR_MAX_BASEFEE_MASK, value); }
}

contract MinerMiddayEligibilityTest is Test {
    MinerMiddayEligibilityHarness private game;
    uint256 private start;

    function setUp() public {
        start = (uint256(ContractAddresses.DEPLOY_DAY_BOUNDARY) + 39) * 1 days + 82_620;
        vm.warp(start + 1 hours);
        vm.fee(1 gwei);
        vm.etch(ContractAddresses.GAME, address(new MinerMiddayEligibilityHarness()).code);
        game = MinerMiddayEligibilityHarness(ContractAddresses.GAME);
        vm.mockCall(ContractAddresses.SDGNRS, abi.encodeWithSignature("redemptionSettlementPending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.CRAPS, abi.encodeWithSignature("minerMaintenancePending()"), abi.encode(false));
        vm.mockCall(ContractAddresses.COINFLIP, abi.encodeWithSignature("creditFlip(address,uint256)"), bytes(""));
        vm.mockCall(ContractAddresses.VRF_COORDINATOR, abi.encodeWithSelector(IVRFCoordinator.getSubscription.selector),
            abi.encode(uint96(100 ether), uint96(0), uint64(0), address(0), new address[](0)));
        game.seed(DegenerusGameStorage.MinerAction.Idle);
        game.wireCoordinator();
    }

    function test_BelowThresholdSkipsRequestAndRevertsNoWork() public {
        game.seedValue(99, 100, 1, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
        assertFalse(game.advanceDue());
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), uint64(0));
        vm.expectRevert(DegenerusGameMinerModule.NoWork.selector);
        game.mineFlip{gas: 16_700_000}();
    }

    function test_BelowThresholdKeepsTicketProgressWithoutRequestAttempt() public {
        game.seed(DegenerusGameStorage.MinerAction.Tickets);
        game.seedValue(99, 100, 1, false);
        vm.mockCall(ContractAddresses.GAME_TICKET_MODULE, abi.encodeWithSignature("runTicketWork(uint24,uint256)"),
            abi.encode(true, true, uint256(65)));
        vm.expectCall(ContractAddresses.GAME_RNG_MODULE, abi.encodeWithSignature("requestMinerRng()"), uint64(0));
        vm.recordLogs();
        game.mineFlip{gas: 16_700_000}();
        assertTrue(game.rngComplete());
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
        Vm.Log[] memory logs = vm.getRecordedLogs();
        uint256 work;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == keccak256("MinerWork(address,uint8,uint256,uint256)")) ++work;
        }
        assertEq(work, 1, "productive call emits work exactly once");
    }

    function testFuzz_ThresholdBoundary(uint32 threshold) public {
        threshold = uint32(bound(threshold, 1, type(uint32).max));
        game.seedValue(threshold - 1, threshold, type(uint40).max, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle), "FLIP cannot fill ETH shortfall");
        game.seedValue(threshold, threshold, 0, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday));
        if (threshold < type(uint32).max) {
            game.seedValue(threshold + 1, threshold, 0, false);
            assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday));
        }
    }

    function test_FlipOnlyAndEmptyQueues() public {
        game.seedValue(0, 1, type(uint40).max, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
        game.seedValue(0, 0, 1, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday));
        game.seedValue(0, 0, 0, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
    }

    function test_CrapsExemptionPreservesGasPriceGate() public {
        game.seedValue(0, type(uint32).max, 0, true);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday));
        game.maxBasefee(1);
        vm.fee(1 gwei + 1);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
        vm.fee(1 gwei);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestMidday));
    }

    function test_ResetWindowDoesNotSelectOptionalRequest() public {
        game.seedValue(100, 100, 0, false);
        vm.warp(start + 1 days - 1 minutes);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.Idle));
    }

    function test_DailyRequestStillRunsBelowMiddayThreshold() public {
        game.seed(DegenerusGameStorage.MinerAction.RequestDaily);
        game.seedValue(1, type(uint32).max, 1, false);
        assertEq(game.minerAction(), uint8(DegenerusGameStorage.MinerAction.RequestDaily));
    }
}
