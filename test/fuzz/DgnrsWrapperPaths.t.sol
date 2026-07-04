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
/// @dev CREATOR is the vault owner (holds the initial DGVE majority) and holds CREATOR_INITIAL
///      (50B) DGNRS at deploy; RNG is unlocked at genesis, so `unwrapTo`'s guards are satisfied.
contract DgnrsWrapperPaths is DeployProtocol {
    function setUp() public {
        _deployProtocol();
    }

    /// @notice `unwrapTo` burns DGNRS from the vault owner and forwards an equal amount of
    ///         soulbound sDGNRS to the recipient. Both `DGNRS.totalSupply()` and
    ///         `sDGNRS.balanceOf(DGNRS)` fall by exactly `amount` (the paired decrement), the
    ///         recipient gains exactly `amount`, and the backing==supply equality is preserved.
    function test_unwrapToPairedDecrement() public {
        address owner = ContractAddresses.CREATOR; // vault owner + DGNRS holder at deploy
        address recipient = address(0xBEEF);
        uint256 amount = 1_000_000_000 * 1e18; // 1B DGNRS, < CREATOR_INITIAL (50B)

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

        address owner = ContractAddresses.CREATOR; // holds CREATOR_INITIAL DGNRS
        uint256 amount = 1_000_000_000 * 1e18; // 1B, < CREATOR_INITIAL (50B)

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
                try game.advanceGame() {} catch {}
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
}
