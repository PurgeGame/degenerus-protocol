// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title AdminNativeForward — Admin's `receive` forwards every wei to the vault, bare.
/// @notice A Chainlink v2.5 cancel refunds native to its target unconditionally, and a refund that
///         reverts rolls the whole cancel back — so Admin's hook must never revert. It forwards
///         bare: the vault's `receive` only logs and cannot refuse, and Admin has no path that
///         moves ETH out, so a swallowed failure would strand it there for good.
contract AdminNativeForward is DeployProtocol {
    address internal sender = address(0xF00D);

    function setUp() public {
        _deployProtocol();
        vm.warp(block.timestamp + 1 days);
    }

    /// @notice Any native sent to Admin lands in the vault; Admin keeps nothing.
    function testFuzz_nativeSentToAdminLandsInTheVault(uint96 amount) public {
        vm.deal(sender, amount);
        uint256 vaultBefore = ContractAddresses.VAULT.balance;
        vm.prank(sender);
        (bool ok,) = address(admin).call{value: amount}("");
        assertTrue(ok, "Admin's receive reverted");
        assertEq(address(admin).balance, 0, "ETH stranded in Admin");
        assertEq(ContractAddresses.VAULT.balance - vaultBefore, amount, "the vault did not receive it");
    }

    /// @notice The coordinator's native refund on a cancel targeted at Admin completes — the
    ///         coordinator requires its refund call to succeed — and the refund reaches the vault.
    function test_aNativeCancelRefundToAdminCompletesAndReachesTheVault() public {
        uint256 refund = 3 ether;
        vm.deal(address(mockVRF), refund);
        mockVRF.fundSubscription(1, uint96(refund));
        uint256 vaultBefore = ContractAddresses.VAULT.balance;

        mockVRF.cancelSubscription(1, address(admin));

        assertEq(address(admin).balance, 0, "refund stranded in Admin");
        assertEq(ContractAddresses.VAULT.balance - vaultBefore, refund, "refund did not reach the vault");
    }

    /// @notice The vault's `receive` never refuses ETH, whatever the amount — the property Admin's
    ///         bare forward rests on.
    function testFuzz_vaultReceiveNeverReverts(uint96 amount) public {
        vm.deal(sender, amount);
        vm.prank(sender);
        (bool ok,) = ContractAddresses.VAULT.call{value: amount}("");
        assertTrue(ok, "the vault refused ETH");
    }
}
