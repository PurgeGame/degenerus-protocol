// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {sDGNRS} from "../../contracts/sDGNRS.sol";
import {DGNRS} from "../../contracts/DGNRS.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title DgnrsWrapperPaths -- drives the DGNRS wrapper unwrap path and pins its exact balance
///        deltas. Closes two gaps the v75 mutation campaign exposed (audit/mutation/FINDINGS-v75.md):
///        (1) the sDGNRS:455-456 `wrapperTransferTo` survivor cluster — no test drove `unwrapTo`;
///        (2) the wrapper-backing EQUALITY non-vacuity noted in audit/DGNRS-WRAPPER-BACKING-PROOF.md
///        — the RedemptionInvariants net asserts only the `>=` safety direction because its handler
///        never moves the wrapper balances. Here the paired decrement is exercised directly.
/// @dev The VAULT holds VAULT_INITIAL (50B) DGNRS at deploy and is the only caller `unwrapTo`
///      accepts; RNG is unlocked at genesis, so `unwrapTo`'s other guards are satisfied.
contract DgnrsWrapperPaths is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    function test_TwelveDecimalsAndWrappedBurnPreserveEveryRawUnit() public {
        assertEq(sdgnrs.decimals(), 12);
        assertEq(dgnrs.decimals(), 12);
        assertEq(sdgnrs.totalSupply(), 1e24);
        address owner = ContractAddresses.VAULT; // holds the deploy-time DGNRS and has wallet ID 1
        assertEq(game.walletIdOf(owner), 1, "the vault is a protocol wallet");
        vm.deal(address(sdgnrs), 100 ether);
        uint256 amount = 1e21 + 1;
        (uint256 burnValue,) = sdgnrs.previewBurnValue(amount);
        assertGe(burnValue, sdgnrs.MIN_REDEMPTION_VALUE(), "fixture: wrapped burn meets minimum");
        uint256 before = dgnrs.balanceOf(owner);
        uint256 supply = dgnrs.totalSupply();
        (uint32 batchId,,,) = sdgnrs.redemptionBatchState();
        vm.prank(owner); sdgnrs.burnWrapped(amount);
        assertEq(before - dgnrs.balanceOf(owner), amount);
        assertEq(supply - dgnrs.totalSupply(), amount);
        assertEq(sdgnrs.balanceOf(ContractAddresses.DGNRS), dgnrs.totalSupply());
        (uint80 pending,) = sdgnrs.pendingRedemptions(game.walletIdOf(owner), batchId);
        assertEq(pending, amount, "the last raw unit is included in the packed claim");
    }

    /// @notice `unwrapTo` burns DGNRS from the Vault and forwards an equal amount of
    ///         soulbound sDGNRS to the recipient. Both `DGNRS.totalSupply()` and
    ///         `sDGNRS.balanceOf(DGNRS)` fall by exactly `amount` (the paired decrement), the
    ///         recipient gains exactly `amount`, and the backing==supply equality is preserved.
    function test_unwrapToPairedDecrement() public {
        address owner = ContractAddresses.VAULT; // DGNRS holder at deploy and the only unwrap caller
        address recipient = address(0xBEEF);
        uint256 amount = 1_000_000_000 * 1e12; // 1B DGNRS, < VAULT_INITIAL (50B)

        require(!game.rngLocked(), "fixture: RNG must be unlocked at genesis for unwrapTo");
        // Equality holds at deploy: DGNRS.totalSupply == sDGNRS.balanceOf(DGNRS).
        assertEq(
            sdgnrs.balanceOf(ContractAddresses.DGNRS),
            dgnrs.totalSupply(),
            "precondition: wrapper exactly backed at genesis"
        );

        uint256 supplyBefore = dgnrs.totalSupply();
        uint256 backingBefore = sdgnrs.balanceOf(ContractAddresses.DGNRS);
        uint256 recipBefore = sdgnrs.balanceOf(recipient);
        uint256 ownerDgnrsBefore = dgnrs.balanceOf(owner);

        vm.prank(owner);
        dgnrs.unwrapTo(recipient, amount);

        // Left side: the wrapper token supply and the owner's holding both fall by amount.
        assertEq(dgnrs.totalSupply(), supplyBefore - amount, "DGNRS.totalSupply -= amount");
        assertEq(dgnrs.balanceOf(owner), ownerDgnrsBefore - amount, "owner DGNRS -= amount");
        // Right side (sDGNRS:455-456): backing leaves the wrapper, recipient receives soulbound.
        assertEq(
            sdgnrs.balanceOf(ContractAddresses.DGNRS),
            backingBefore - amount,
            "wrapper backing -= amount (sDGNRS:455)"
        );
        assertEq(sdgnrs.balanceOf(recipient), recipBefore + amount, "recipient soulbound += amount (sDGNRS:456)");
        // Equality preserved: both sides fell equally, so the wrapper stays exactly backed.
        assertEq(
            sdgnrs.balanceOf(ContractAddresses.DGNRS),
            dgnrs.totalSupply(),
            "equality clause: wrapper still exactly backed after unwrap"
        );
    }

    /// @notice Post-game-over `DGNRS.burn` routes through `sDGNRS._deterministicBurnFrom`, the
    ///         deterministic-payout path the redemption fuzz never reaches (its handler
    ///         early-returns once `gameOver` is set). Asserts the supply/balance decrements
    ///         (sDGNRS:686-687) and a nonzero ETH payout basis (sDGNRS:682, 697-711). This is the
    ///         v75 682-701 survivor cluster — genuinely unasserted anywhere in the foundry suite,
    ///         confirmed by re-verifying the 687 mutant survives even RedemptionEdgeCases at HEAD.
    function test_postGameOverDeterministicBurnDecrement() public {
        _reachGameOver();

        address owner = ContractAddresses.VAULT; // holds VAULT_INITIAL DGNRS
        uint256 amount = 1_000_000_000 * 1e12; // 1B, < VAULT_INITIAL (50B)

        uint256 dgnrsSupplyBefore = dgnrs.totalSupply();
        uint256 sdgnrsSupplyBefore = sdgnrs.totalSupply();
        uint256 backingBefore = sdgnrs.balanceOf(ContractAddresses.DGNRS);

        // Unfunded burn: the deterministic path still runs its full body (basis calc at
        // sDGNRS:682, supply/balance decrements at 686-687). No ETH moves, so no receiver
        // dependency. The 682 basis mutation `- pending` → `/ pending` reverts on the zero
        // divisor and is caught as an unexpected revert; 686/687 are caught by the deltas below.
        vm.prank(owner);
        dgnrs.burn(amount);

        assertEq(dgnrs.totalSupply(), dgnrsSupplyBefore - amount, "DGNRS.totalSupply -= amount");
        assertEq(sdgnrs.totalSupply(), sdgnrsSupplyBefore - amount, "sDGNRS._totalSupply -= amount (sDGNRS:687)");
        assertEq(
            sdgnrs.balanceOf(ContractAddresses.DGNRS),
            backingBefore - amount,
            "wrapper backing -= amount (sDGNRS:686)"
        );
    }

    /// @dev Reach the terminal gameOver state via the level-0 deploy-idle timeout: warp past it,
    ///      then advance + fulfill VRF until `gameOver()` latches (pattern from V61CurseSet).
    function _reachGameOver() internal {
        vm.warp(block.timestamp + 400 days);
        for (uint256 d; d < 240 && !game.gameOver(); d++) {
            uint256 word = uint256(keccak256(abi.encode("go", d))) | 1;
            if (game.advanceDue() || game.rngLocked()) {
                try game.mineFlip(0) {} catch {}
            }
            uint256 reqId = mockVRF.lastRequestId();
            if (reqId != 0) {
                (, , bool fulfilled) = mockVRF.pendingRequests(reqId);
                if (!fulfilled) {
                    try mockVRF.fulfillRandomWords(reqId, word) {} catch {}
                }
            }
            if (!game.advanceDue() && !game.rngLocked() && !game.gameOver()) {
                vm.warp(block.timestamp + 1 days);
            }
        }
        require(game.gameOver(), "fixture: gameOver must latch");
    }

    /// @notice Lifetime unwraps stop at 40B, 20% of the 200B DGNRS supply: calls add up to the
    ///         cap exactly, anything past it reverts, and the counter reads the running total.
    function test_unwrapToLifetimeCap() public {
        address owner = ContractAddresses.VAULT; // holds VAULT_INITIAL (50B), above the cap
        uint256 cap = 40_000_000_000 * 1e12;

        vm.startPrank(owner);
        dgnrs.unwrapTo(address(0xBEEF), cap - 1_000e12);
        vm.expectRevert(DGNRS.UnwrapCapExceeded.selector);
        dgnrs.unwrapTo(address(0xBEEF), 1_000e12 + 1);
        dgnrs.unwrapTo(address(0xCAFE), 1_000e12);
        assertEq(dgnrs.totalUnwrapped(), cap, "lifetime total reached the cap exactly");
        vm.expectRevert(DGNRS.UnwrapCapExceeded.selector);
        dgnrs.unwrapTo(address(0xBEEF), 1e12);
        vm.stopPrank();

        assertEq(dgnrs.balanceOf(owner), 10_000_000_000 * 1e12, "only the cap left the owner");
        assertEq(sdgnrs.balanceOf(address(0xBEEF)) + sdgnrs.balanceOf(address(0xCAFE)), cap, "recipients hold the cap");
    }

    /// @notice Vesting and the unwrap total share one slot: an unwrap leaves the vesting mark
    ///         alone, and a vest leaves the unwrap total alone. Anyone may trigger a vest; the
    ///         Vault always receives it.
    function test_vestingAndUnwrapShareTheSlot() public {
        address owner = ContractAddresses.VAULT;
        address poker = address(0xCA11);
        vm.prank(owner);
        dgnrs.unwrapTo(address(0xBEEF), 7_000e12);

        // Level 4 vests 50B + 4 x 5B = 70B, so 20B is claimable past the 50B released at deploy.
        vm.mockCall(ContractAddresses.GAME, abi.encodeWithSignature("level()"), abi.encode(uint24(4)));
        uint256 before = dgnrs.balanceOf(owner);
        vm.prank(poker);
        dgnrs.claimVested();
        assertEq(dgnrs.balanceOf(owner), before + 20_000_000_000 * 1e12, "vested the level-4 tranche to the vault");
        assertEq(dgnrs.balanceOf(poker), 0, "the caller of a vest receives nothing");
        assertEq(dgnrs.totalUnwrapped(), 7_000e12, "vesting left the unwrap total alone");

        vm.prank(poker);
        vm.expectRevert(DGNRS.Insufficient.selector);
        dgnrs.claimVested();
    }

    /// @notice The creator account receives no DGNRS; the Vault holds the whole deploy-time release.
    function test_vaultHoldsTheInitialAllocation() public view {
        assertEq(dgnrs.balanceOf(ContractAddresses.VAULT), 50_000_000_000 * 1e12, "vault holds 50B at deploy");
        assertEq(dgnrs.balanceOf(ContractAddresses.CREATOR), 0, "the creator holds none");
        assertEq(dgnrs.balanceOf(address(dgnrs)), dgnrs.totalSupply() - 50_000_000_000 * 1e12, "the rest is unvested");
    }

    /// @notice Only the Vault may unwrap, even a DGVE-majority holder: its owner reaches the
    ///         wrapper through `dgnrsUnwrapTo`, and everyone else is refused by the Vault.
    function test_ownerUnwrapsOnlyThroughTheVault() public {
        address recipient = address(0xBEEF);
        uint256 amount = 5_000e12;
        assertTrue(vault.isVaultOwner(address(this)), "fixture: the test contract holds the DGVE majority");

        vm.expectRevert(DGNRS.Unauthorized.selector);
        dgnrs.unwrapTo(recipient, amount); // the owner account itself is not the vault

        uint256 vaultBefore = dgnrs.balanceOf(ContractAddresses.VAULT);
        vault.dgnrsUnwrapTo(recipient, amount);
        assertEq(dgnrs.balanceOf(ContractAddresses.VAULT), vaultBefore - amount, "vault DGNRS -= amount");
        assertEq(sdgnrs.balanceOf(recipient), amount, "recipient holds soulbound sDGNRS");

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        vault.dgnrsUnwrapTo(recipient, amount);
    }

    /// @notice During the game the Vault files a redemption claim for its wrapped DGNRS; the owner
    ///         triggers it through `dgnrsBurnWrapped` and nobody else can.
    function test_vaultBurnWrappedFilesAClaimInGame() public {
        uint256 amount = 1e21 + 1;
        vm.deal(address(sdgnrs), 100 ether);
        (uint256 burnValue,) = sdgnrs.previewBurnValue(amount);
        assertGe(burnValue, sdgnrs.MIN_REDEMPTION_VALUE(), "fixture: burn meets the minimum");
        uint256 before = dgnrs.balanceOf(ContractAddresses.VAULT);
        (uint32 batchId,,,) = sdgnrs.redemptionBatchState();

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        vault.dgnrsBurnWrapped(amount);

        vault.dgnrsBurnWrapped(amount);
        assertEq(before - dgnrs.balanceOf(ContractAddresses.VAULT), amount, "vault DGNRS -= amount");
        (uint80 pending,) = sdgnrs.pendingRedemptions(game.walletIdOf(ContractAddresses.VAULT), batchId);
        assertEq(pending, amount, "the claim is recorded for the vault's wallet");
    }

    /// @notice After game over the same call pays the Vault ETH/stETH at once, into its reserves.
    function test_vaultBurnWrappedPaysTheVaultAfterGameOver() public {
        _reachGameOver();
        uint256 amount = 1_000_000_000 * 1e12;
        vm.deal(address(sdgnrs), address(sdgnrs).balance + 10 ether);
        uint256 supplyBefore = dgnrs.totalSupply();
        uint256 vaultBalanceBefore = ContractAddresses.VAULT.balance;
        uint256 vaultStethBefore = mockStETH.balanceOf(ContractAddresses.VAULT);

        (uint256 ethOut, uint256 stethOut,) = vault.dgnrsBurnWrapped(amount);

        assertEq(dgnrs.totalSupply(), supplyBefore - amount, "DGNRS supply fell by the burn");
        assertEq(ContractAddresses.VAULT.balance - vaultBalanceBefore, ethOut, "ETH landed in the vault");
        assertEq(mockStETH.balanceOf(ContractAddresses.VAULT) - vaultStethBefore, stethOut, "stETH landed in the vault");
        assertGt(ethOut + stethOut, 0, "the burn paid something");
    }

    /// @notice Icons32Data follows vault ownership: the DGVE majority holder edits and finalizes,
    ///         and moving the majority moves the ability.
    function test_iconsFollowVaultOwnership() public {
        string[] memory paths = new string[](1);
        paths[0] = "M0 0L10 10";
        icons32.setPaths(0, paths); // the test contract is the DGVE majority holder

        address newOwner = address(0xCAFE);
        address dgve = vm.computeCreateAddress(address(vault), 2); // the vault's second child: DGVE
        (bool ok,) = dgve.call(abi.encodeWithSignature("transfer(address,uint256)", newOwner, 1_000_000_000_000 ether));
        require(ok, "fixture: move the DGVE majority");
        assertTrue(vault.isVaultOwner(newOwner) && !vault.isVaultOwner(address(this)), "fixture: ownership moved");

        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        icons32.setPaths(0, paths);
        vm.expectRevert(abi.encodeWithSignature("NotVaultOwner()"));
        icons32.finalize();

        vm.prank(newOwner);
        icons32.setPaths(1, paths);
        vm.prank(newOwner);
        icons32.finalize();
    }
}
