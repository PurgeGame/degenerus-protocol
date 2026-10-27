// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "../fuzz/helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {BoundedCall} from "../../contracts/libraries/BoundedCall.sol";

/// A dead stETH balanceOf (no code, short return, or revert) must not block the ETH-only final
/// sweep or the post-game-over ETH-backed holder exits: the failed read counts as 0, the stETH legs
/// are skipped, and any stETH stays where it is.
interface IERC20Like {
    function transfer(address, uint256) external returns (bool);
    function totalSupply() external view returns (uint256);
}


/// Every call succeeds and returns 16 bytes: shorter than one ABI word.
contract ShortReturnSteth {
    fallback() external payable {
        assembly { mstore(0, 0) return(0, 16) }
    }
}

/// A working stETH whose balanceOf costs a fixed, noticeable amount of gas.
contract HungrySteth {
    fallback() external {
        uint256 x;
        for (uint256 i; i < 450; ++i) x = uint256(keccak256(abi.encode(x, i)));
        if (x == 1) revert();
        assembly { mstore(0, 7) return(0, 32) }
    }
}

contract StethReadHarness {
    function read() external view returns (uint256) {
        return BoundedCall.stethBalanceOrZero(ContractAddresses.STETH_TOKEN, address(this));
    }
}

contract V08StethDeadSweep is DeployProtocol {
    address internal keeper = address(0xBEEF);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
        vm.deal(keeper, 100 ether);
        mockVRF.fundSubscription(1, 100e18);
    }

    function _driveToGameOver() internal {
        vm.warp(block.timestamp + 370 days);
        for (uint256 i; i < 40 && !game.gameOver(); i++) {
            vm.prank(keeper);
            try game.mineRun(0) {} catch {}
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (,, bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, uint256(keccak256(abi.encode("v08", i))) | 1) {} catch {}
                }
            }
        }
        require(game.gameOver(), "fixture: game over never latched");
    }

    /// Game holds ETH only (90 ETH), zero stETH.
    function _ethOnlyGame() internal {
        uint256 st = mockStETH.balanceOf(address(game));
        if (st != 0) {
            vm.prank(address(game));
            mockStETH.transfer(address(0xdead), st);
        }
        vm.deal(address(game), 90 ether);
    }

    function _killStethNoCode() internal {
        vm.etch(ContractAddresses.STETH_TOKEN, bytes(""));
    }

    function _killStethRevert() internal {
        vm.mockCallRevert(ContractAddresses.STETH_TOKEN, abi.encodeWithSelector(mockStETH.balanceOf.selector),
            bytes("dead"));
    }

    // Control: healthy stETH, ETH-only game sweeps.
    function test_control_healthyStethEthOnlySweepCompletes() public {
        _driveToGameOver();
        _ethOnlyGame();
        vm.warp(block.timestamp + 30 days + 1);
        vm.prank(keeper);
        game.mineRun(0);
        assertEq(address(game).balance, 0, "control: sweep emptied the game");
    }

    // No-code stETH: the sweep completes and pays the ETH out.
    function test_noCodeSteth_sweepCompletes() public {
        _driveToGameOver();
        _ethOnlyGame();
        vm.warp(block.timestamp + 30 days + 1);
        _killStethNoCode();
        vm.prank(keeper);
        game.mineRun(0);
        assertEq(address(game).balance, 0, "ETH paid out");
        assertGt(ContractAddresses.VAULT.balance, 0, "vault received its leg");
    }

    // Short-return stETH (success, 16 bytes): same.
    function test_shortReturnSteth_sweepCompletes() public {
        _driveToGameOver();
        _ethOnlyGame();
        vm.warp(block.timestamp + 30 days + 1);
        vm.etch(ContractAddresses.STETH_TOKEN, type(ShortReturnSteth).runtimeCode);
        vm.prank(keeper);
        game.mineRun(0);
        assertEq(address(game).balance, 0, "ETH paid out");
    }

    // Reverting stETH balanceOf: the sweep pays the ETH and leaves the Game's stETH in place.
    function test_revertingSteth_sweepCompletesAndLeavesStethInPlace() public {
        _driveToGameOver();
        vm.deal(address(game), 90 ether);
        mockStETH.mint(address(game), 5 ether);
        uint256 st = mockStETH.balanceOf(address(game));
        assertGt(st, 0, "fixture: the game holds stETH");
        vm.warp(block.timestamp + 30 days + 1);
        _killStethRevert();
        vm.prank(keeper);
        game.mineRun(0);
        vm.clearMockedCalls();
        assertEq(address(game).balance, 0, "ETH paid out");
        assertEq(mockStETH.balanceOf(address(game)), st, "stETH left in place");
    }

    // Terminal setup with a short-return stETH still latches game over (bounded read = 0).
    function test_shortReturnSteth_terminalSetupStillCompletes() public {
        vm.etch(ContractAddresses.STETH_TOKEN, type(ShortReturnSteth).runtimeCode);
        _driveToGameOver();
        assertTrue(game.gameOver(), "game over latched with short-return stETH");
    }

    // Terminal setup (game-over drain) tolerates a no-code stETH: game over still latches and pays.
    function test_noCodeSteth_terminalSetupStillCompletes() public {
        _killStethNoCode();
        _driveToGameOver();
        assertTrue(game.gameOver(), "game over latched with dead stETH");
    }

    // Holder exits after game over that hold ETH only: DGNRS burn (sDGNRS _redemptionBacking).
    function test_noCodeSteth_dgnrsBurnAfterGameOverPays() public {
        address holder = address(0xA11CE);
        _dgnrsFromVault(holder, 1_000e12);
        _driveToGameOver();
        vm.deal(address(sdgnrs), 10 ether);
        _killStethNoCode();
        uint256 before = holder.balance;
        vm.prank(holder);
        dgnrs.burn(1_000e12);
        assertGt(holder.balance, before, "ETH paid with dead stETH");
    }

    // Vault DGVE burnEth with an ETH-only vault.
    function test_noCodeSteth_vaultBurnEthPays() public {
        address holder = address(0xD0D0);
        IERC20Like dgve = IERC20Like(vault.dgve());
        uint256 amt = dgve.totalSupply() / 10;
        dgve.transfer(holder, amt);
        vm.deal(address(vault), 10 ether);
        _killStethNoCode();
        uint256 before = holder.balance;
        vm.prank(holder);
        (uint256 ethOut, uint256 stEthOut) = vault.burnEth(amt);
        assertGt(ethOut, 0, "ETH-only burn pays");
        assertEq(stEthOut, 0, "no stETH leg");
        assertEq(holder.balance - before, ethOut, "ETH received");
    }

    // GNRUS burn and the residual sweep read the Game-side backing and on-hand ETH only.
    function test_noCodeSteth_gnrusBurnAndResidualSweep() public {
        address holder = address(0x6A);
        uint256 amount = gnrus.totalSupply() / 100;
        deal(address(gnrus), address(gnrus), gnrus.balanceOf(address(gnrus)) - amount);
        deal(address(gnrus), holder, amount);
        _driveToGameOver();
        vm.deal(address(gnrus), 10 ether);
        _ethOnlyGame();
        _killStethNoCode();
        uint256 before = holder.balance;
        vm.prank(holder);
        gnrus.burn(amount);
        assertGt(holder.balance, before, "GNRUS burn paid ETH with dead stETH");

        vm.warp(vm.getBlockTimestamp() + 30 days + 1);
        vm.prank(keeper);
        game.mineRun(0);
        vm.warp(vm.getBlockTimestamp() + 3 * 365 days + 1);
        uint256 vaultBefore = address(vault).balance;
        uint256 residual = address(gnrus).balance;
        assertGt(residual, 0, "fixture: GNRUS holds residual ETH");
        vm.prank(ContractAddresses.OWNER_GOVERNANCE);
        gnrus.sweepResidualToVault();
        assertEq(address(vault).balance - vaultBefore, residual, "residual swept to the vault");
    }

    // Ordinary player claim (ETH-preferred) is unaffected when Game ETH covers it.
    function test_noCodeSteth_playerEthClaimUnaffected() public {
        address alice = address(0xA1);
        uint32 aid = _giveWalletId(alice);
        vm.deal(address(this), 3 ether);
        game.depositAfkingFunding{value: 3 ether}(aid); // closes at game over; paid by the post-GO claim
        _driveToGameOver();
        _ethOnlyGame();
        _killStethNoCode();
        uint256 before = alice.balance;
        vm.prank(alice);
        game.claimWinnings(0, type(uint256).max);
        assertEq(alice.balance - before, 3 ether, "ETH claim paid with dead stETH");
    }

    // ---------------------------------------------------------------------------------------
    // Working stETH: a short-gas call reverts or pays in full, never skips or underpays the stETH.
    // ---------------------------------------------------------------------------------------

    function _gasLimits(uint256 from, uint256 to, uint256 step) private pure returns (uint256[] memory limits) {
        limits = new uint256[]((to - from) / step + 1);
        for (uint256 i; i < limits.length; ++i) limits[i] = from + i * step;
    }

    function _received(address who) private view returns (uint256) {
        return who.balance + mockStETH.balanceOf(who);
    }

    function test_workingSteth_sweepAcrossGasRange_neverSkipsStETH() public {
        _driveToGameOver();
        vm.deal(address(game), 90 ether);
        mockStETH.mint(address(game), 5 ether);
        vm.warp(block.timestamp + 30 days + 1);
        uint256 snap = vm.snapshotState();
        uint256 completed;
        uint256[] memory limits = _gasLimits(200_000, 3_000_000, 50_000);
        for (uint256 i; i < limits.length; ++i) {
            vm.prank(keeper);
            (bool ok,) = address(game).call{gas: limits[i]}(abi.encodeWithSignature("mineRun(uint32)", uint32(0)));
            if (ok) {
                assertEq(address(game).balance, 0, "a successful sweep paid all ETH");
                assertEq(mockStETH.balanceOf(address(game)), 0, "a successful sweep paid all stETH");
                ++completed;
            }
            assertTrue(vm.revertToState(snap));
        }
        assertGt(completed, 0, "the sweep completes at ample gas");
        assertLt(completed, limits.length, "the sweep refuses at low gas");
    }

    function test_workingSteth_dgnrsBurnAcrossGasRange_neverUnderpays() public {
        address holder = address(0xA11CE);
        _dgnrsFromVault(holder, 1_000e12);
        _driveToGameOver();
        vm.deal(address(sdgnrs), 1 gwei);
        mockStETH.mint(address(sdgnrs), 20 ether);
        uint256 snap = vm.snapshotState();
        vm.prank(holder);
        dgnrs.burn(1_000e12);
        uint256 full = _received(holder);
        assertGt(mockStETH.balanceOf(holder), 0, "fixture: the full payout includes stETH");
        assertTrue(vm.revertToState(snap));
        _assertAllOrNothing(holder, snap, full, abi.encodeCall(dgnrs.burn, (1_000e12)), address(dgnrs));
    }

    function test_workingSteth_vaultBurnEthAcrossGasRange_neverUnderpays() public {
        address holder = address(0xD0D0);
        IERC20Like dgve = IERC20Like(vault.dgve());
        uint256 amt = dgve.totalSupply() / 10;
        dgve.transfer(holder, amt);
        vm.deal(address(vault), 1 ether);
        mockStETH.mint(address(vault), 20 ether);
        uint256 snap = vm.snapshotState();
        vm.prank(holder);
        vault.burnEth(amt);
        uint256 full = _received(holder);
        assertGt(mockStETH.balanceOf(holder), 0, "fixture: the full payout includes stETH");
        assertTrue(vm.revertToState(snap));
        _assertAllOrNothing(holder, snap, full, abi.encodeCall(vault.burnEth, (amt)), address(vault));
    }

    function test_workingSteth_gnrusBurnAcrossGasRange_neverUnderpays() public {
        address holder = address(0x6A);
        uint256 amount = gnrus.totalSupply() / 100;
        deal(address(gnrus), address(gnrus), gnrus.balanceOf(address(gnrus)) - amount);
        deal(address(gnrus), holder, amount);
        vm.deal(address(gnrus), 1 gwei);
        mockStETH.mint(address(gnrus), 20 ether);
        uint256 snap = vm.snapshotState();
        vm.prank(holder);
        gnrus.burn(amount);
        uint256 full = _received(holder);
        assertGt(mockStETH.balanceOf(holder), 0, "fixture: the full payout includes stETH");
        assertTrue(vm.revertToState(snap));
        _assertAllOrNothing(holder, snap, full, abi.encodeCall(gnrus.burn, (amount)), address(gnrus));
    }

    /// @dev Each call at each gas limit either reverts or pays exactly the full-gas payout.
    function _assertAllOrNothing(address holder, uint256 snap, uint256 full, bytes memory data, address target)
        private
    {
        uint256 completed;
        uint256[] memory limits = _gasLimits(30_000, 600_000, 10_000);
        for (uint256 i; i < limits.length; ++i) {
            vm.prank(holder);
            (bool ok,) = target.call{gas: limits[i]}(data);
            if (ok) {
                assertEq(_received(holder), full, "a successful call pays the full share");
                ++completed;
            }
            assertTrue(vm.revertToState(snap));
        }
        assertGt(completed, 0, "the call completes at ample gas");
        assertLt(completed, limits.length, "the call refuses at low gas");
    }

    // The holder-exit read starts only with enough gas for a working stETH: below the admission it
    // reverts, above it a working token is never read as zero.
    function test_workingSteth_holderExitReadNeverReadsZeroFromShortGas() public {
        vm.etch(ContractAddresses.STETH_TOKEN, type(HungrySteth).runtimeCode);
        StethReadHarness h = new StethReadHarness();
        uint256 before = gasleft();
        (bool measured,) = ContractAddresses.STETH_TOKEN.staticcall("");
        uint256 cost = before - gasleft();
        assertTrue(measured);
        assertGt(cost, 40_000, "fixture: the working stETH read is expensive");
        assertLt(cost, 100_000, "fixture: it still fits the 100k admission");

        uint256 completed;
        for (uint256 g = 30_000; g <= 200_000; g += 2_000) {
            // Each holder exit can be its transaction's first stETH access. A warm
            // dependency hides the forwarding shortfall at the admission boundary.
            vm.cool(ContractAddresses.STETH_TOKEN);
            (bool ok, bytes memory out) = address(h).staticcall{gas: g}(abi.encodeCall(h.read, ()));
            if (ok) {
                assertEq(abi.decode(out, (uint256)), 7, "a started read returns the working balance");
                ++completed;
            }
        }
        assertGt(completed, 0, "the read completes at ample gas");
    }
}
