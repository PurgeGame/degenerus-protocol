// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;
import {PeripheralSlots} from "../helpers/PeripheralSlots.sol";

import {RedemptionReserveHarness} from "./RedemptionReserve.t.sol";
import {RedemptionFixture} from "../fuzz/helpers/RedemptionFixture.sol";
import {RedemptionCloseHarness} from "../fuzz/helpers/RedemptionCloseTools.sol";
import {MineFlipGas} from "../../contracts/libraries/MineFlipGas.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {GameFunding} from "../helpers/GameFunding.sol";

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
        GameFunding.credit(2, amount);
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

    function testCloseMovesWholePullIntoReserveAndSendsNoEth() public {
        _fundLedger(100 ether);
        _burn(alice, sdgnrs.totalSupply() / 100);
        vm.deal(address(game), 0.1 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforePool = _pool();
        uint256 beforeSteth = mockStETH.balanceOf(address(sdgnrs));
        uint256 beforeSdgnrs = address(sdgnrs).balance;
        _closeFunded();
        assertEq(address(sdgnrs).balance, beforeSdgnrs, "no ETH reaches sDGNRS");
        assertEq(address(game).balance, 0.1 ether, "no ETH leaves the Game");
        assertEq(game.redemptionReserve(), sdgnrs.pendingRedemptionEthValue(), "reserve is the whole pull");
        assertGt(game.redemptionReserve(), 0);
        assertEq(game.claimableWinningsOf(address(sdgnrs)) + game.redemptionReserve(), beforeClaimable);
        assertEq(_pool(), beforePool, "the reserve stays inside claimablePool");
        assertEq(mockStETH.balanceOf(address(sdgnrs)), beforeSteth);
        assertTrue(sdgnrs.redemptionSettlementPending_g153837());
    }

    function testLiveDirectLegMovesReserveToWalletWithoutPoolChange() public {
        _fundLedger(100 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforeAlice = game.claimableWinningsOf(alice);
        uint32 aliceId = game.walletIdOf_g3120(alice);
        _reserveLedger(10 ether);
        uint256 beforePool = _pool();
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect(aliceId, 10 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable - 10 ether);
        assertEq(game.claimableWinningsOf(alice), beforeAlice + 10 ether);
        assertEq(game.redemptionReserve(), 0);
        assertEq(_pool(), beforePool);
    }

    function testLiveSelfCreditReturnsReserveToClaimable() public {
        _fundLedger(100 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        _reserveLedger(10 ether);
        uint256 beforePool = _pool();
        vm.prank(address(sdgnrs));
        game.creditRedemptionDirect(2, 10 ether);
        assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable);
        assertEq(game.redemptionReserve(), 0);
        assertEq(_pool(), beforePool);
    }

    function testLiveLegsRefuseWhatTheReserveCannotCover() public {
        _fundLedger(100 ether);
        _reserveLedger(1 ether);
        vm.startPrank(address(sdgnrs));
        vm.expectRevert();
        game.creditRedemptionDirect(2, 1 ether + 1);
        vm.expectRevert();
        game.resolveRedemptionLootbox(2, 1 ether + 1, 1, 0, 1);
        vm.stopPrank();
        assertEq(game.redemptionReserve(), 1 ether);
    }

    function testCustodyFailuresAndOversizedWordsCannotBlockClose() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint256 snapshot = vm.snapshotState();
        for (uint256 mode; mode < 7; ++mode) {
            vm.etch(ContractAddresses.STETH_TOKEN, address(new RedemptionHostileBalance(mode)).code);
            _closeFunded();
            assertTrue(sdgnrs.redemptionSettlementPending_g153837());
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
        vm.mockCall(address(game), abi.encodeWithSelector(game.rngConsumerStage_g379.selector), abi.encode(uint8(1)));
        uint256 beforeAlice = game.claimableWinningsOf(alice);
        assertTrue(_work(9_000_000));
        assertGt(game.claimableWinningsOf(alice), beforeAlice);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0);
    }

    function testBatchParityReplacesBothWordsAndEscrowRetainsSentinel() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 first = _resolveLive(175);
        assertTrue(_work(9_000_000));
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(PeripheralSlots.SD_BATCH_COUNTS))), 1);
        _burn(bob, sdgnrs.totalSupply() / 1000);
        _resolveLive(100);
        assertTrue(_work(9_000_000));
        assertEq(uint256(vm.load(address(sdgnrs), bytes32(PeripheralSlots.SD_BATCH_COUNTS))), 1);

        bytes32 slot = bytes32(PeripheralSlots.SD_BATCHES + uint256(first & 1) * 2);
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

    /// @dev The first unit always starts; with too little gas for its claim the step reverts
    ///      whole, so the claim is neither retired nor paid.
    function testUnderfundedFirstClaimCannotBeDropped() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        uint32 id = _resolveLive(100);
        uint256 tokens = _claimTokens(alice, id);
        bytes32 before = _redemptionDigest(id);
        vm.prank(address(game));
        (bool ok,) = address(sdgnrs).call{gas: 200_000}(
            abi.encodeWithSelector(sdgnrs.runRedemptionWork.selector, settlementWord,
                MineFlipGas.budget(0, 10_000, true))
        );
        assertFalse(ok);
        assertEq(_redemptionDigest(id), before, "an underfunded step changes no redemption state");
        assertEq(_claimTokens(alice, id), tokens);
        assertEq(_cursor(), 0);
    }
    /// @dev The close never calls sDGNRS with ETH, whatever its code does on receipt.
    function testCloseSendsNoEthWhateverSdgnrsDoes() public {
        _fundLedger(10 ether);
        uint256 beforeClaimable = game.claimableWinningsOf(address(sdgnrs));
        uint256 beforePool = _pool();
        uint256 beforeGame = address(game).balance;
        uint256 snap = vm.snapshotState();
        for (uint256 mode; mode < 6; ++mode) {
            vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.redemptionSettlementPending_g153837.selector), abi.encode(false));
            vm.mockCall(address(sdgnrs), abi.encodeWithSelector(sdgnrs.closeRedemptionBatch_g165517.selector), abi.encode(uint256(1 ether)));
            vm.etch(address(sdgnrs), address(new RedemptionHostileEth(mode)).code);
            _closeFunded();
            assertEq(game.claimableWinningsOf(address(sdgnrs)), beforeClaimable - 1 ether);
            assertEq(game.redemptionReserve(), 1 ether);
            assertEq(_pool(), beforePool);
            assertEq(address(sdgnrs).balance, 0);
            assertEq(address(game).balance, beforeGame);
            assertTrue(vm.revertToState(snap));
        }
        vm.clearMockedCalls();
    }

    /// @dev Live pricing counts only what live legs can pay, so the close reads no token custody.
    function testCloseReadsNoTokenCustody() public {
        _burn(alice, sdgnrs.totalSupply() / 1000);
        vm.expectCall(address(mockStETH), abi.encodeWithSelector(mockStETH.balanceOf.selector, address(sdgnrs)), 0);
        _closeFunded();
        assertTrue(sdgnrs.redemptionSettlementPending_g153837());
    }

}
