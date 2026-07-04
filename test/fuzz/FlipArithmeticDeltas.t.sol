// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FlipArithmeticDeltas -- deterministic foundry coverage of FLIP mint/transfer/burn
///        arithmetic. The v75 mutation campaign's FLIP "survivors" (MUT-V75-01,
///        audit/mutation/FINDINGS-v75.md) were a scoping artifact: FLIP's arithmetic is asserted
///        by the Hardhat suite (test/unit/FLIP.test.js), which the foundry mutation oracle never
///        runs, and the foundry `CoinSupplyInvariant` is a tautology (a+b == a+b). This adds the
///        missing FOUNDRY-side exact-delta coverage so a foundry mutation of `_mint` (435-436),
///        `_transfer` (391/417), or `_burn` (458-459) is caught, complementing the Hardhat suite.
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

        // _mint (FLIP:435-436): GAME mints to a fresh holder.
        vm.prank(ContractAddresses.GAME);
        coin.mintForGame(alice, mintAmt);
        assertEq(coin.totalSupply(), supply0 + mintAmt, "mint: totalSupply += amount (FLIP:435)");
        assertEq(coin.balanceOf(alice), mintAmt, "mint: balanceOf[to] += amount (FLIP:436)");

        // _transfer (FLIP:391/417): alice -> bob, neither is the VAULT (normal debit+credit path).
        vm.prank(alice);
        coin.transfer(bob, xferAmt);
        assertEq(coin.balanceOf(alice), mintAmt - xferAmt, "transfer: sender balance - amount (FLIP:391)");
        assertEq(coin.balanceOf(bob), xferAmt, "transfer: recipient balance + amount (FLIP:417)");
        // A transfer moves value but changes neither totalSupply nor the two-party sum.
        assertEq(coin.totalSupply(), supply0 + mintAmt, "transfer: totalSupply unchanged");

        // _burn (FLIP:458-459): GAME burns from alice (balance >= amount skips the shortfall path).
        vm.prank(ContractAddresses.GAME);
        coin.burnCoin(alice, burnAmt);
        assertEq(coin.balanceOf(alice), mintAmt - xferAmt - burnAmt, "burn: balanceOf[from] -= amount (FLIP:458)");
        assertEq(coin.totalSupply(), supply0 + mintAmt - burnAmt, "burn: totalSupply -= amount (FLIP:459)");
    }
}
