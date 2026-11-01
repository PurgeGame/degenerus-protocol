// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FlipArithmeticDeltas -- deterministic foundry coverage of FLIP mint/transfer/burn
///        arithmetic. FLIP's arithmetic is also asserted by the Hardhat suite
///        (test/unit/FLIP.test.js), and the foundry `CoinSupplyInvariant` is a tautology
///        (a+b == a+b). This adds FOUNDRY-side exact-delta coverage so a change to `_mint`,
///        `_transfer` or `_burn` is caught.
/// @dev FLIP supply is NOT conserved — it is an inflationary/deflationary game token; the property
///      asserted here is per-operation arithmetic correctness (a mint/burn moves supply by exactly
///      `amount`, a transfer moves exactly `amount` between two non-vault holders), not any total.
contract FlipArithmeticDeltas is DeployProtocol {
    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);

    function setUp() public {
        _deployProtocol();
    }

    function test_mintTransferBurnDeltas() public {
        uint256 mintAmt = 1_000e18;
        uint256 xferAmt = 300e18;
        uint256 burnAmt = 200e18;

        uint256 supply0 = coin.totalSupply();

        // _mint: GAME mints to a fresh holder.
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame_g152734(alice, mintAmt);
        assertEq(coin.totalSupply(), supply0 + mintAmt, "mint: totalSupply += amount");
        assertEq(coin.balanceOf(alice), mintAmt, "mint: balanceOf[to] += amount");

        // _transfer: alice -> bob, neither is the VAULT (normal debit+credit path).
        vm.prank(alice);
        coin.transfer(bob, xferAmt);
        assertEq(coin.balanceOf(alice), mintAmt - xferAmt, "transfer: sender balance - amount");
        assertEq(coin.balanceOf(bob), xferAmt, "transfer: recipient balance + amount");
        // A transfer moves value but changes neither totalSupply nor the two-party sum.
        assertEq(coin.totalSupply(), supply0 + mintAmt, "transfer: totalSupply unchanged");

        // _burn: GAME burns from alice (balance >= amount skips the shortfall path).
        vm.prank(ContractAddresses.GAME);
        coin.burnCoin_g27673(alice, burnAmt);
        assertEq(coin.balanceOf(alice), mintAmt - xferAmt - burnAmt, "burn: balanceOf[from] -= amount");
        assertEq(coin.totalSupply(), supply0 + mintAmt - burnAmt, "burn: totalSupply -= amount");
    }
}
