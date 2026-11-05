// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {FinalSweepPayoutLegs} from "../fuzz/FinalSweepPayoutLegs.t.sol";
import {MinerloopGasProbe} from "../helpers/MinerloopGasProbe.sol";
import {GlamsterdamReprice} from "../helpers/GlamsterdamReprice.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {MineFlipGasBounds as GasBounds} from "../../contracts/libraries/MineFlipGasBounds.sol";
import {DegenerusGame} from "../../contracts/DegenerusGame.sol";

import {GNRUS} from "../../contracts/GNRUS.sol";

/// Optional continuation with the real terminal module and a caller-owned gas floor.
contract GnrusSweepHost is DegenerusGame {
    function optionalSweep(uint256 allowance) external {
        (bool ok, bytes memory reason) = ContractAddresses.GAME_GAMEOVER_MODULE.delegatecall(
            abi.encodeWithSignature("runGameOverAdvance(uint24,uint24,uint256)", dailyIdx, level, allowance));
        if (!ok) assembly ("memory-safe") { revert(add(reason, 32), mload(reason)) }
    }
}

/// Only the Game's balance read exhausts its forwarded gas. Every exit still uses real token code.
contract GnrusSweepReadFailure {
    address private immutable implementation;
    constructor(address target) { implementation = target; }
    fallback() external {
        if (msg.sig == bytes4(keccak256("balanceOf(address)"))
            && abi.decode(msg.data[4:], (address)) == ContractAddresses.GAME) {
            assembly ("memory-safe") { invalid() }
        }
        address target = implementation;
        assembly ("memory-safe") {
            calldatacopy(0, 0, calldatasize())
            let ok := delegatecall(gas(), target, 0, calldatasize(), 0, 0)
            returndatacopy(0, 0, returndatasize())
            if iszero(ok) { revert(0, returndatasize()) }
            return(0, returndatasize())
        }
    }
}

contract GnrusHolderSeed is GNRUS {
    function holders(address a, address b) external {
        balanceOf[address(this)] = 0;
        balanceOf[a] = 50 ether;
        balanceOf[b] = 50 ether;
        totalSupply = 100 ether;
    }
}

contract GnrusFinalSweepGasTest is FinalSweepPayoutLegs, MinerloopGasProbe {
    function seedSweep(uint8 assets, bool holdings) external {
        require(msg.sender == address(this));
        if (holdings) {
            _unwrapFromVault(ContractAddresses.GNRUS, 1000 ether);
            _dgnrsFromVault(ContractAddresses.GNRUS, 1000 ether);
        }
        _driveToGameOver();
        _backSubscription();
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) { vm.prank(address(game)); mockStETH.transfer(address(0xdead), st); }
        vm.deal(address(game), assets == 0 ? 0 : assets == 1 ? 90 ether : 40 ether);
        if (assets >= 2) mockStETH.mint(address(game), 60 ether);
        // Both payout asset legs can be exercised by each sequential burn.
        vm.deal(address(sdgnrs), 0);
        mockStETH.mint(address(sdgnrs), 80 ether);
        vm.warp(block.timestamp + 30 days + 1);
    }

    function _measured(uint8 assets, bool holdings) private {
        this.seedSweep(assets, holdings);
        (GlamsterdamReprice.Result memory r,) = _probe(address(game), keeper,
            abi.encodeCall(game.mineRun, (uint32(0))), GasBounds.TERMINAL_FINAL_SWEEP + GasBounds.TERMINAL_SWEEP_TAIL);
        assertGt(gnrus.sweptAt(), 0);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        _report(string.concat("gnrus_final_sweep_assets_", vm.toString(assets), "_holdings_", vm.toString(holdings)),
            r, GasBounds.TERMINAL_FINAL_SWEEP);
        assertLe(r.osakaExec, GasBounds.TERMINAL_FINAL_SWEEP);
        assertLe(r.glamsterdamExec + r.stateGas, GasBounds.TERMINAL_FINAL_SWEEP);
        assertLt(GasBounds.TERMINAL_FINAL_SWEEP + GasBounds.TERMINAL_SWEEP_TAIL, 10_000_000);
        // Reserve also has to permit the shutdown's 1M minimum plus 250k tail and EIP-150/frame.
        emit log_named_uint("shutdown_admission", 1_275_873);
        emit log_named_uint("sweep_after_read", GasBounds.TERMINAL_SWEEP_AFTER_READ);
    }

    function test_GasHookAfterSinksPaid() public {
        this.seedSweep(2, true);
        vm.mockCall(address(gnrus), abi.encodeCall(gnrus.onFinalSweep, ()), bytes(""));
        vm.prank(keeper); game.mineRun(0);
        vm.clearMockedCalls();
        (GlamsterdamReprice.Result memory r,) = _probe(address(gnrus), address(game),
            abi.encodeCall(gnrus.onFinalSweep, ()), GasBounds.TERMINAL_SWEEP_AFTER_READ);
        _report("gnrus_hook_after_sinks", r, GasBounds.TERMINAL_SWEEP_AFTER_READ);
        emit log_named_uint("hook_plus_shutdown_admission_osaka", r.osakaExec + 1_275_873);
        emit log_named_uint("hook_plus_shutdown_admission_glamsterdam", r.glamsterdamExec + r.stateGas + 1_275_873);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0);
    }

    /// @dev The sweep with GNRUS's hook mocked: every sink paid, GNRUS still holding both tokens.
    function _sinksPaid(uint8 assets) private {
        this.seedSweep(assets, true);
        vm.mockCall(address(gnrus), abi.encodeCall(gnrus.onFinalSweep, ()), bytes(""));
        vm.prank(keeper); game.mineRun(0);
        vm.clearMockedCalls();
    }

    /// @notice Each cash-out burn, cold, for every asset mix the sweep can leave: an empty, ETH-only
    ///         or mixed Game means GNRUS may hold no stETH yet, so the burn's stETH leg can write a
    ///         fresh balance. Every case fits GNRUS_CASHOUT_BURN at Osaka and Glamsterdam prices.
    function test_GasCashoutBurnsFitTheirAdmission() public {
        uint256 worst;
        for (uint8 assets; assets < 3; ++assets) {
            uint256 snap = vm.snapshotState();
            _sinksPaid(assets);
            uint256 nativeHeld = sdgnrs.balanceOf(ContractAddresses.GNRUS);
            uint256 wrappedHeld = dgnrs.balanceOf(ContractAddresses.GNRUS);
            assertGt(nativeHeld, 0);
            assertGt(wrappedHeld, 0);
            (GlamsterdamReprice.Result memory r,) = _probe(address(sdgnrs), ContractAddresses.GNRUS,
                abi.encodeCall(sdgnrs.burn, (nativeHeld)), GasBounds.GNRUS_CASHOUT_BURN);
            _report(string.concat("gnrus_cashout_burn_assets_", vm.toString(assets)), r, GasBounds.GNRUS_CASHOUT_BURN);
            worst = _fits(r, worst);
            (r,) = _probe(address(sdgnrs), ContractAddresses.GNRUS,
                abi.encodeCall(sdgnrs.burnWrapped, (wrappedHeld)), GasBounds.GNRUS_CASHOUT_BURN);
            _report(string.concat("gnrus_cashout_burn_wrapped_assets_", vm.toString(assets)), r,
                GasBounds.GNRUS_CASHOUT_BURN);
            worst = _fits(r, worst);
            vm.revertToState(snap);
        }
        emit log_named_uint("gnrus_cashout_worst_total", worst);
    }

    function _fits(GlamsterdamReprice.Result memory r, uint256 worst) private pure returns (uint256) {
        uint256 glamsterdam = r.glamsterdamExec + r.stateGas;
        assertLe(r.osakaExec, GasBounds.GNRUS_CASHOUT_BURN);
        assertLe(glamsterdam, GasBounds.GNRUS_CASHOUT_BURN);
        if (r.osakaExec > worst) worst = r.osakaExec;
        return glamsterdam > worst ? glamsterdam : worst;
    }

    /// @notice A refused cash-out never blocks the sweep, so a refusal must never be a gas shortage the
    ///         caller chose: at every gas the hook either refuses whole or cashes out both tokens.
    function test_cashoutIsNeverSkippedForShortGas() public {
        _sinksPaid(2);
        uint256 snap = vm.snapshotState();
        uint256 completed;
        for (uint256 g = 40_000; g <= 2_500_000; g += 5_000) {
            vm.prank(address(game));
            (bool ok,) = address(gnrus).call{gas: g}(abi.encodeCall(gnrus.onFinalSweep, ()));
            if (ok) {
                ++completed;
                assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0, "a completed hook cashed out sDGNRS");
                assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0, "a completed hook cashed out DGNRS");
            }
            vm.revertToState(snap);
        }
        assertGt(completed, 0, "the hook completes with enough gas");
    }

    /// @notice The final sweep is one-shot: at every supplied gas it either reverts whole, keeping the
    ///         VRF subscription and GNRUS's holdings, or it completes with the subscription cancelled
    ///         and both cash-outs done. No gas makes it skip the cancellation or a cash-out.
    function test_sweepAtAnyGasCompletesWholeOrRevertsWhole() public {
        this.seedSweep(2, true);
        uint256 subId = admin.subscriptionId();
        assertGt(subId, 0);
        (,,, address owner,) = mockVRF.getSubscription(subId);
        assertTrue(owner != address(0), "fixture: a live subscription");
        assertEq(mockVRF.pendingCount(subId), 0, "fixture: no pending request, so a cancel is accepted");
        uint256 snap = vm.snapshotState();
        uint256 lowest = type(uint256).max;
        for (uint256 g = 600_000; g <= 6_000_000; g += 20_000) {
            vm.prank(keeper);
            (bool ok,) = address(game).call{gas: g}(abi.encodeCall(game.mineRun, (uint32(0))));
            if (ok) {
                if (g < lowest) lowest = g;
                assertGt(gnrus.sweptAt(), 0, "a completed call swept");
                assertEq(admin.subscriptionId(), 0, "a completed sweep retired the subscription");
                (,,, owner,) = mockVRF.getSubscription(subId);
                assertEq(owner, address(0), "a completed sweep cancelled the subscription");
                assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0, "a completed sweep cashed out sDGNRS");
                assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0, "a completed sweep cashed out DGNRS");
            } else {
                assertEq(gnrus.sweptAt(), 0, "a refused call left the sweep undone");
                assertEq(admin.subscriptionId(), subId, "a refused call kept the subscription");
            }
            vm.revertToState(snap);
        }
        assertLt(lowest, type(uint256).max, "the sweep completes within the swept range");
        emit log_named_uint("lowest_completing_sweep_gas_warm", lowest);
        assertLt(lowest, (uint256(1) << 24) - 21_000, "the sweep fits one transaction");
    }

    function test_afterReadReserveWithGnrusCanRefuseOptionalSweep() public {
        this.seedSweep(2, true);
        // Copy the healthy mock's runtime into a fresh implementation; retain all token storage.
        address implementation = address(0x5D6701);
        vm.etch(implementation, address(mockStETH).code);
        GnrusSweepReadFailure proxy = new GnrusSweepReadFailure(implementation);
        vm.etch(address(mockStETH), address(proxy).code);
        vm.etch(address(game), type(GnrusSweepHost).runtimeCode);
        (bool ok, bytes memory reason) = address(game).call{gas: 4_000_000}(abi.encodeCall(GnrusSweepHost.optionalSweep, (3_000_000)));
        assertFalse(ok, "cashout plus shutdown must not be assumed to fit the reserved after-read tail");
        assertEq(bytes4(reason), bytes4(keccak256("InsufficientExecutionGas()")));
        assertEq(gnrus.sweptAt(), 0, "failed continuation rolls back the sweep");
        // Isolate the added hook: the same failing read and same meter complete without cashout.
        vm.mockCall(address(gnrus), abi.encodeCall(gnrus.onFinalSweep, ()), bytes(""));
        (ok,) = address(game).call{gas: 4_000_000}(abi.encodeCall(GnrusSweepHost.optionalSweep, (3_000_000)));
        assertTrue(ok, "control without cashout completes");
        assertEq(address(game).balance, 0);
    }

    function test_GasGnrusSweepMixedBothTokens() public { _measured(2, true); }
    function test_GasGnrusSweepEthBothTokens() public { _measured(1, true); }
    function test_GasGnrusSweepEmptyGameBothTokens() public { _measured(0, true); }
    function test_GasGnrusSweepZeroTokenBalances() public { _measured(2, false); }

    function test_cashoutMatchesBurningBothTokensAfterAllSinksPaid() public {
        this.seedSweep(2, true);
        uint256 nativeHeld = sdgnrs.balanceOf(ContractAddresses.GNRUS);
        uint256 wrappedHeld = dgnrs.balanceOf(ContractAddresses.GNRUS);
        uint256 snap = vm.snapshotState();
        vm.mockCallRevert(address(sdgnrs), abi.encodeWithSelector(sdgnrs.burn.selector), hex"abcd");
        vm.mockCallRevert(address(sdgnrs), abi.encodeWithSelector(sdgnrs.burnWrapped.selector), hex"abcd");
        vm.prank(keeper); game.mineRun(0);
        assertGt(gnrus.sweptAt(), 0);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), nativeHeld);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), wrappedHeld);
        vm.clearMockedCalls();
        uint256 beforeEth = ContractAddresses.GNRUS.balance;
        uint256 beforeSt = mockStETH.balanceOf(ContractAddresses.GNRUS);
        vm.prank(ContractAddresses.GNRUS); sdgnrs.burn(nativeHeld);
        vm.prank(ContractAddresses.GNRUS); sdgnrs.burnWrapped(wrappedHeld);
        uint256 expectedEth = ContractAddresses.GNRUS.balance;
        uint256 expectedSt = mockStETH.balanceOf(ContractAddresses.GNRUS);
        assertGt(expectedEth + expectedSt, beforeEth + beforeSt);
        assertTrue(vm.revertToState(snap)); vm.clearMockedCalls();
        vm.prank(keeper); game.mineRun(0);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(ContractAddresses.GNRUS.balance, expectedEth);
        assertApproxEqAbs(mockStETH.balanceOf(ContractAddresses.GNRUS), expectedSt, 2);
    }

    function test_oneRefusedBurnDoesNotPreventTheOtherOrTheSweep() public {
        this.seedSweep(2, true);
        uint256 nativeHeld = sdgnrs.balanceOf(ContractAddresses.GNRUS);
        vm.mockCallRevert(address(sdgnrs), abi.encodeWithSelector(sdgnrs.burn.selector), hex"abcd");
        vm.prank(keeper); game.mineRun(0);
        assertGt(gnrus.sweptAt(), 0);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), nativeHeld);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(address(game).balance, 0);
        assertEq(mockStETH.balanceOf(address(game)), 0);
    }

    function test_emptyGameStillCashesOutGnrusTokens() public {
        this.seedSweep(0, true);
        uint256 beforeValue = ContractAddresses.GNRUS.balance + mockStETH.balanceOf(ContractAddresses.GNRUS);
        vm.prank(keeper); game.mineRun(0);
        assertGt(gnrus.sweptAt(), 0);
        assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), 0);
        assertGt(ContractAddresses.GNRUS.balance + mockStETH.balanceOf(ContractAddresses.GNRUS), beforeValue);
    }

    /// @notice A dead stETH leg (an empty revert or a short return) skips both cash-outs, never the
    ///         one-shot sweep: only the protocol's own gas refusals are re-raised.
    function test_deadStethLegSkipsTheCashoutsNotTheSweep() public {
        bytes memory toGnrus = abi.encodeWithSelector(mockStETH.transfer.selector, ContractAddresses.GNRUS);
        for (uint256 mode; mode < 2; ++mode) {
            uint256 snap = vm.snapshotState();
            this.seedSweep(0, true);
            uint256 nativeHeld = sdgnrs.balanceOf(ContractAddresses.GNRUS);
            uint256 wrappedHeld = dgnrs.balanceOf(ContractAddresses.GNRUS);
            uint256 subId = admin.subscriptionId();
            if (mode == 0) vm.mockCallRevert(address(mockStETH), toGnrus, "");
            else vm.mockCall(address(mockStETH), toGnrus, hex"01");
            vm.prank(keeper); game.mineRun(0);
            assertGt(gnrus.sweptAt(), 0, "the sweep completes");
            assertEq(admin.subscriptionId(), 0, "the sweep retires the subscription");
            (,,, address owner,) = mockVRF.getSubscription(subId);
            assertEq(owner, address(0), "the sweep cancels the subscription");
            assertEq(sdgnrs.balanceOf(ContractAddresses.GNRUS), nativeHeld, "the sDGNRS cash-out is skipped");
            assertEq(dgnrs.balanceOf(ContractAddresses.GNRUS), wrappedHeld, "the DGNRS cash-out is skipped");
            vm.clearMockedCalls();
            assertTrue(vm.revertToState(snap));
        }
    }

    function test_holderExitBeforeAndAfterCashoutUsesThenCurrentLiquidBacking() public {
        this.seedSweep(2, true);
        address early = address(0xA111);
        address late = address(0xB222);
        bytes memory original = address(gnrus).code;
        vm.etch(address(gnrus), type(GnrusHolderSeed).runtimeCode);
        GnrusHolderSeed(payable(address(gnrus))).holders(early, late);
        vm.etch(address(gnrus), original);
        vm.deal(address(gnrus), 10 ether);
        vm.prank(early); gnrus.burn(50 ether);
        assertEq(gnrus.balanceOf(early), 0);
        assertEq(gnrus.totalSupply(), 50 ether);
        vm.prank(keeper); game.mineRun(0);
        uint256 lateValue = address(gnrus).balance + mockStETH.balanceOf(address(gnrus));
        vm.prank(late); gnrus.burn(50 ether);
        assertEq(gnrus.totalSupply(), 0);
        assertApproxEqAbs(late.balance + mockStETH.balanceOf(late), lateValue, 2);
    }

}
