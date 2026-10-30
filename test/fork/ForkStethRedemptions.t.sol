// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {stdStorage, StdStorage} from "forge-std/StdStorage.sol";
import {ForkDeployProtocol} from "./ForkDeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";
import {DegenerusVaultShare} from "../../contracts/DegenerusVault.sol";
import {DegenerusGameRngUtils} from "../../contracts/modules/DegenerusGameRngUtils.sol";

/// @dev Seed backed ledger entries and the terminal latch without simulating a full game.
///      The actual Game claim/withdrawal, batch close and holder payout paths execute unchanged.
contract ForkExitState is DegenerusGameRngUtils {
    function credit(uint32 id, uint256 claimable, uint256 afking) external {
        _creditClaimable(id, claimable);
        claimablePool += uint128(claimable);
        _creditAfkingValue(id, afking);
    }

    function end() external { gameOver = true; }
    function close() external { _closeRedemptionBatch(); }
}

/// @notice Focused redemption regressions against the pinned real Lido implementation.
/// @dev Holder distributions and Game liabilities are seeded boundary fixtures, not a proof
///      of the complete lifecycle. ForkSteth covers the surrounding production lifecycle.
contract ForkStethRedemptionsTest is ForkDeployProtocol {
    using stdStorage for StdStorage;

    address private holder = address(0xA11CE);
    address private claimant = address(0xCA11);
    uint256 private constant TOKENS = 100e12;

    receive() external payable {}

    function setUp() public {
        _forkAndDeploy();
        _giveWalletId(holder);
        _giveWalletId(claimant);
        address funder = makeAddr("exit backing funder");
        vm.deal(funder, 100 ether);
        vm.startPrank(funder);
        lido.submit{value: 100 ether}(address(0));
        lido.transfer(address(game), 90 ether);
        vm.stopPrank();
        vm.deal(address(game), 0);
    }

    function _gameCall(bytes memory data) private {
        bytes memory original = address(game).code;
        vm.etch(address(game), type(ForkExitState).runtimeCode);
        (bool ok, bytes memory result) = address(game).call(data);
        if (!ok) assembly ("memory-safe") { revert(add(result, 32), mload(result)) }
        vm.etch(address(game), original);
    }

    function _credit(address sink, uint256 claimable, uint256 afking) private {
        _gameCall(abi.encodeCall(ForkExitState.credit, (game.walletIdOf_g3120(sink), claimable, afking)));
    }

    function _end() private { _gameCall(abi.encodeCall(ForkExitState.end, ())); }

    function _roundedAmount() private view returns (uint256 amount) {
        for (amount = 1 ether; amount < 1 ether + 100; ++amount) {
            if (lido.getPooledEthByShares(lido.getSharesByPooledEth(amount)) < amount) return amount;
        }
        revert("fixture: expected transfer rounding");
    }

    function _seedNativeHolder(address owner) private {
        // Discover slots through getters, including packed fields, rather than pinning offsets.
        stdstore.target(address(sdgnrs)).sig("totalSupply()").enable_packed_slots().checked_write(TOKENS);
        stdstore.target(address(sdgnrs)).sig("balanceOf(address)").with_key(address(sdgnrs)).checked_write(uint256(0));
        stdstore.target(address(sdgnrs)).sig("balanceOf(address)").with_key(address(dgnrs)).checked_write(uint256(0));
        for (uint256 i; i < 5; ++i) {
            stdstore.target(address(sdgnrs)).sig("poolBalance(uint8)").with_key(i)
                .enable_packed_slots().checked_write(uint256(0));
        }
        stdstore.target(address(sdgnrs)).sig("balanceOf(address)").with_key(owner).checked_write(TOKENS);
    }

    function _seedWrappedHolder() private {
        _seedNativeHolder(address(dgnrs));
        stdstore.target(address(dgnrs)).sig("totalSupply()").checked_write(TOKENS);
        stdstore.target(address(dgnrs)).sig("balanceOf(address)").with_key(address(vault)).checked_write(uint256(0));
        stdstore.target(address(dgnrs)).sig("balanceOf(address)").with_key(holder).checked_write(TOKENS);
    }

    function _assertPaid(address owner, uint256 beforeBalance, uint256 nominal, uint256 legs) private view {
        uint256 received = lido.balanceOf(owner) - beforeBalance;
        assertLe(received, nominal, "payout exceeds entitlement");
        assertLe(nominal - received, 2 * legs, "loss exceeds per-transfer rounding");
    }

    function test_fullVaultExitPullsClaimableBeforeSweep() public {
        uint256 nominal = _roundedAmount();
        _credit(address(vault), nominal, 0);
        uint256 beforeBalance = lido.balanceOf(address(this));
        vault.burnEth(DegenerusVaultShare(vault.dgve()).totalSupply());
        _assertPaid(address(this), beforeBalance, nominal, 2);
    }

    function test_partialVaultExitPullsExactAfkingShortfall() public {
        uint256 nominal = _roundedAmount();
        _credit(address(vault), 0, nominal * 10);
        uint256 beforeBalance = lido.balanceOf(address(this));
        vault.burnEth(DegenerusVaultShare(vault.dgve()).totalSupply() / 10);
        _assertPaid(address(this), beforeBalance, nominal, 2);
        assertEq(game.afkingFundingOf(address(vault)), nominal * 9, "remaining backing preserved");
    }

    function test_fullVaultExitPullsClaimableAndAfking() public {
        uint256 nominal = _roundedAmount();
        _credit(address(vault), nominal, nominal);
        uint256 beforeBalance = lido.balanceOf(address(this));
        vault.burnEth(DegenerusVaultShare(vault.dgve()).totalSupply());
        _assertPaid(address(this), beforeBalance, nominal * 2, 3);
        assertEq(game.afkingFundingOf(address(vault)), 0);
    }

    function test_fullNativeExitBeforeSweep() public {
        _seedNativeHolder(holder);
        uint256 nominal = _roundedAmount();
        _credit(address(sdgnrs), nominal, 0);
        _end();
        uint256 beforeBalance = lido.balanceOf(holder);
        vm.prank(holder);
        sdgnrs.burn(TOKENS);
        assertEq(sdgnrs.totalSupply(), 0);
        _assertPaid(holder, beforeBalance, nominal, 2);
    }

    function test_fullWrappedExitThroughDgnrsBeforeSweep() public {
        _wrappedExit(false);
    }

    function test_fullWrappedExitThroughSdgnrsBeforeSweep() public {
        _wrappedExit(true);
    }

    function _wrappedExit(bool throughStaked) private {
        _seedWrappedHolder();
        uint256 nominal = _roundedAmount();
        _credit(address(sdgnrs), nominal, 0);
        _end();
        uint256 beforeBalance = lido.balanceOf(holder);
        vm.prank(holder);
        if (throughStaked) sdgnrs.burnWrapped(TOKENS);
        else dgnrs.burn(TOKENS);
        assertEq(sdgnrs.totalSupply(), 0);
        assertEq(dgnrs.totalSupply(), 0);
        _assertPaid(holder, beforeBalance, nominal, throughStaked ? 2 : 3);
    }

    function test_lastOpenBatchClaimBeforeSweep() public {
        _seedNativeHolder(holder);
        uint256 nominal = _roundedAmount();
        _credit(address(sdgnrs), nominal, 0);
        (uint32 batch,,,) = sdgnrs.redemptionBatchState();
        vm.prank(holder);
        sdgnrs.burn(TOKENS);
        _end();
        uint256 beforeBalance = lido.balanceOf(holder);
        vm.prank(holder);
        sdgnrs.claimRedemption(0, batch);
        (uint80 remaining,) = sdgnrs.pendingRedemptions(game.walletIdOf_g3120(holder), batch);
        assertEq(remaining, 0, "claim consumed");
        (,,,uint256 escrow) = sdgnrs.redemptionBatchState();
        assertEq(escrow, 0, "open escrow released");
        _assertPaid(holder, beforeBalance, nominal, 2);
    }

    function test_closedBatchClaimAfterLiquidHolderExit() public {
        _seedNativeHolder(holder);
        stdstore.target(address(sdgnrs)).sig("balanceOf(address)").with_key(holder).checked_write(TOKENS / 2);
        stdstore.target(address(sdgnrs)).sig("balanceOf(address)").with_key(claimant).checked_write(TOKENS / 2);
        uint256 reserve = 0.5 ether;
        uint256 nominal;
        for (nominal = 1 ether; nominal < 1 ether + 100; ++nominal) {
            uint256 left = lido.getSharesByPooledEth(nominal) - lido.getSharesByPooledEth(nominal - reserve);
            if (lido.getPooledEthByShares(left) < reserve) break;
        }
        assertLt(nominal, 1 ether + 100, "fixture: closed claim must be short");
        _credit(address(sdgnrs), nominal, 0);
        (uint32 batch,,,) = sdgnrs.redemptionBatchState();
        vm.prank(claimant);
        sdgnrs.burn(TOKENS / 2);
        _gameCall(abi.encodeCall(ForkExitState.close, ()));
        vm.prank(address(game));
        sdgnrs.resolveTerminalRedemptions();
        assertEq(sdgnrs.pendingRedemptionEthValue(), reserve);
        _end();
        vm.prank(holder);
        sdgnrs.burn(TOKENS / 2);
        assertLt(lido.balanceOf(address(sdgnrs)), reserve, "rounding shortfall reached");
        assertEq(game.claimableWinningsOf(address(sdgnrs)), 1, "Game backing already pulled");
        uint256 beforeBalance = lido.balanceOf(claimant);
        vm.prank(claimant);
        sdgnrs.claimRedemption(0, batch);
        assertEq(sdgnrs.pendingRedemptionEthValue(), 0, "reserve released exactly once");
        _assertPaid(claimant, beforeBalance, reserve, 2);
        vm.expectRevert();
        vm.prank(claimant);
        sdgnrs.claimRedemption(0, batch);
    }

    function test_lastGnrusHolderExitBeforeSweep() public {
        uint256 amount = 1.5 ether;
        stdstore.target(address(gnrus)).sig("totalSupply()").checked_write(amount);
        stdstore.target(address(gnrus)).sig("balanceOf(address)").with_key(address(gnrus)).checked_write(uint256(0));
        stdstore.target(address(gnrus)).sig("balanceOf(address)").with_key(holder).checked_write(amount);
        uint256 nominal = _roundedAmount();
        _credit(address(gnrus), nominal, 0);
        _end();
        uint256 beforeBalance = lido.balanceOf(holder);
        vm.prank(holder);
        gnrus.burn(amount);
        assertEq(gnrus.totalSupply(), 0);
        _assertPaid(holder, beforeBalance, nominal, 2);
    }
}
