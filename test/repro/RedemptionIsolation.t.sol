// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {RedemptionReserveHarness} from "./RedemptionReserve.t.sol";
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionCloseHarness} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

contract RedemptionHostileBalance {
    uint256 private immutable mode;

    constructor(uint256 mode_) { mode = mode_; }

    fallback() external {
        uint256 action = mode;
        bytes4 errorSelector = MineFlipGas.InsufficientExecutionGas.selector;
        assembly ("memory-safe") {
            switch action
            case 0 { revert(0, 0) }
            case 1 { invalid() }
            case 2 { return(0, 31) }
            case 3 {
                let ptr := mload(64)
                mstore(ptr, 0)
                return(ptr, 32768)
            }
            case 4 {
                mstore(0, errorSelector)
                revert(0, 4)
            }
            case 5 {
                mstore(0, not(0))
                return(0, 32)
            }
            default {
                mstore(0, sub(shl(96, 1), 1))
                return(0, 32)
            }
        }
    }
}

contract RedemptionHostileEth {
    uint256 private immutable mode;
    constructor(uint256 mode_) { mode = mode_; }
    fallback() external payable {
        uint256 action = mode;
        bytes4 errorSelector = MineFlipGas.InsufficientExecutionGas.selector;
        assembly ("memory-safe") {
            switch action
            case 0 { revert(0, 0) }
            case 1 { invalid() }
            case 2 { return(0, 1) }
            case 3 { return(mload(64), 32768) }
            case 4 { mstore(0, errorSelector) revert(0, 4) }
            default { mstore(0, 0) return(0, 32) }
        }
    }
}

contract RedemptionIsolationTest is RedemptionFixture {
    function _fundLedger(uint256 amount) private {
        vm.deal(address(sdgnrs), amount);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: amount}(2, amount);
    }

    function _reserveLedger(uint256 amount) private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionReserveHarness).runtimeCode);
        RedemptionReserveHarness(address(game)).reserveFromOrdinary(amount);
        vm.etch(address(game), code);
    }

    function _pool() private view returns (uint256) {
        return uint256(vm.load(address(game), bytes32(uint256(1)))) >> 128;
    }

    function _closeFunded() private {
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        RedemptionCloseHarness(address(game)).close();
        vm.etch(address(game), code);
    }

    function testCloseMovesOnlyAvailableEthAndPreservesLedgerRemainder() public {
        _fundLedger(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0.1 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforePool = _pool();
        uint256 beforeSteth = mockStETH.balanceOf(address(sdgnrs));
        _closeFunded();
        assertEq(address(sdgnrs).balance, 0.1 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve(), beforeClaimable - 0.1 ether);
        assertEq(_pool(), beforePool - 0.1 ether);
        assertEq(mockStETH.balanceOf(address(sdgnrs)), beforeSteth);
        assertTrue(sdgnrs.redemptionSettlementPending());
    }

    function testLiveDirectFundingMovesLedgerAndOnlyEthIncreasesPool() public {
        _fundLedger(100 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforeAlice = game.claimableWinningsOf(alice);
        uint256 beforePool = _pool();
        uint32 aliceId = game.walletIdOf(alice);
        _reserveLedger(8 ether);
        vm.deal(address(sdgnrs), 2 ether);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: 2 ether}(aliceId, 10 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable - 8 ether);
        assertEq(game.claimableWinningsOf(alice), beforeAlice + 10 ether);
        assertEq(_pool(), beforePool + 2 ether);
    }

    function testLiveSelfCreditRecyclesOnlyForwardedEth() public {
        _fundLedger(100 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforePool = _pool();
        _reserveLedger(8 ether);
        vm.deal(address(sdgnrs), 2 ether);
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect{value: 2 ether}(2, 10 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable + 2 ether);
        assertEq(_pool(), beforePool + 2 ether);
    }

    function testCustodyFailuresAndOversizedWordsCannotBlockClose() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 7; ++mode) {
            vm.etch(ContractAddresses.STETH_TOKEN, address(new RedemptionHostileBalance(mode)).code);
            _closeFunded();
            assertTrue(sdgnrs.redemptionSettlementPending());
            (, , uint96 base, , ,) = sdgnrs.redemptionBatches(1);
            assertGt(base, 0);
            assertLt(base, 100 ether);
            assertTrue(vm.revertToState(snapshot));
        }
    }

    function testStethFailureLeavesLedgerFundedSettlementMoving() public {
        _fundLedger(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 1000);
        vm.deal(address(game), 0);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        vm.etch(ContractAddresses.STETH_TOKEN, address(new RedemptionHostileBalance(0)).code);
        _closeFunded();
        assertEq(game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve(), beforeClaimable);
        settlementWord = _wordForRoll(100);
        vm.mockCall(address(game), abi.encodeWithSelector(game.rngConsumerStage.selector), abi.encode(uint8(1)));
        uint256 beforeAlice = game.claimableWinningsOf(alice);
        assertTrue(_work(9_000_000));
        assertGt(game.claimableWinningsOf(alice), beforeAlice);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function testBatchParityReplacesBothWordsAndSlotSevenRetainsSentinel() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 first = _resolveLive(175);
        assertTrue(_work(9_000_000));
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(uint256(7)))), 1);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolveLive(100);
        assertTrue(_work(9_000_000));
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(uint256(7)))), 1);

        bytes32 slot = keccak256(abi.encode(uint256(first & 1), uint256(6)));
        vm.store(address(sdgnrs), slot, bytes32(type(uint256).max));
        vm.store(address(sdgnrs), bytes32(uint256(slot) + 1), bytes32(type(uint256).max));
        (uint80 stale, , , , ,) = sdgnrs.redemptionBatches(first);
        assertEq(stale, 0, "mismatched tag cannot expose poisoned terms");
        uint256 amount = sdgnrs.totalSupply() / 2000;
        _burn(carol, amount);
        (uint80 tokens, uint96 payout, uint96 base, uint96 flip, uint16 roll, uint16 reward) =
            sdgnrs.redemptionBatches(first + 2);
        assertEq(tokens, amount);
        assertEq(uint256(payout) | base | flip | roll | reward, 0, "every old term resets");
        assertEq(uint256(vm.load(address(sdgnrs), slot)), amount, "whole first word overwritten");
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(uint256(slot) + 1))),
            uint256(first + 2) << 224, "whole second word overwritten");
        (tokens, payout, base, flip, roll, reward) = sdgnrs.redemptionBatches(first);
        assertEq(uint256(tokens) | payout | base | flip | roll | reward, 0, "old generation retired");
        assertEq(_claimTokens(alice, first), 0);
        assertEq(_claimTokens(carol, first + 2), amount);
    }

    function testUnderfundedFirstClaimCannotBeDropped() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _resolveLive(100);
        uint256 tokens = _claimTokens(alice, id);
        uint256 reserved = sdgnrs.pendingRedemptionEthValue();
        vm.prank(address(game));
        (bool ok, bytes memory reason) = address(sdgnrs).call{gas: 200_000}(
            abi.encodeWithSelector(sdgnrs.runRedemptionWork.selector, settlementWord,
                MineFlipGas.budget(0, 10_000, true))
        );
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
        assertEq(_claimTokens(alice, id), tokens);
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserved);
        assertEq(_cursor(), 0);
    }
    function testCloseEthSendFailureModesConserveLedger() public {
        _fundLedger(10 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforePool = _pool();
        uint256 snap = vm.snapshotState();
        for (uint256 mode; mode < 6; ++mode) {
            vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.redemptionSettlementPending.selector), abi.encode(false));
            vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.closeRedemptionBatch.selector), abi.encode(uint256(1 ether)));
            vm.etch(address(sdgnrs), address(new RedemptionHostileEth(mode)).code);
            _closeFunded();
            bool success = mode == 2 || mode == 3 || mode == 5;
            uint256 moved = success ? 1 ether : 0;
            assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable - 1 ether);
            assertEq(game.redemptionReserve(), 1 ether - moved);
            assertEq(_pool(), beforePool - moved);
            assertEq(address(sdgnrs).balance, moved);
            assertTrue(vm.revertToState(snap));
        }
        vm.clearMockedCalls();
    }

    function testCloseEthSendUnderfundingCannotBecomeRefusal() public {
        _fundLedger(10 ether);
        uint256 beforePool = _pool();
        vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.closeRedemptionBatch.selector), abi.encode(uint256(1 ether)));
        bytes memory code = address(game).code;
        vm.etch(address(game), type(RedemptionCloseHarness).runtimeCode);
        (bool ok, bytes memory reason) = address(game).call{gas: 60_000}(abi.encodeWithSelector(RedemptionCloseHarness.close.selector));
        vm.etch(address(game), code);
        vm.clearMockedCalls();
        assertFalse(ok);
        assertEq(reason, abi.encodeWithSelector(MineFlipGas.InsufficientExecutionGas.selector));
        assertEq(_pool(), beforePool);
        assertEq(address(sdgnrs).balance, 0);
    }

    /// @dev Live pricing counts only what live legs can pay, so the close reads no token custody.
    function testCloseReadsNoTokenCustody() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        vm.expectCall(address(mockStETH), abi.encodeWithSelector(mockStETH.balanceOf.selector, address(sdgnrs)), 0);
        _closeFunded();
        assertTrue(sdgnrs.redemptionSettlementPending());
    }

}
