// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {FLIP} from "../../contracts/FLIP.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title FlipTombstone — BTOMB-03: gameover FLIP tombstone signals ONLY in uncirculated supply
/// @notice Deterministic scenario tests against the APPLIED Phase-326 diff that drive every property
///         of `FLIP.tombstoneAtGameOver()` (the one-shot 1e18-wei VAULT-allowance flood) plus
///         the downstream DGVF pro-rata FLIP claim (`DegenerusVault.burnCoin`) against a flooded
///         allowance.
///
///         Four properties (BTOMB-01/02 mechanic → BTOMB-03 non-distortion proof):
///         1. NON-CIRCULATING       — the flood does NOT change `totalSupply()` (circulating leg).
///         2. SIGNAL LOCALIZATION   — `vaultMintAllowance()` += EXACTLY 1e18 and
///                                    `supplyIncUncirculated()` += EXACTLY 1e18, while
///                                    `totalSupply()` is unchanged (whole delta in the uncirculated leg).
///         3. ONE-SHOT + GAME-GATE  — a second `tombstoneAtGameOver()` is a no-op (early-return,
///                                    NOT revert, total += 1e18 not 2e18); a non-GAME caller reverts
///                                    `OnlyGame`; the CHECKED `_toUint128` add holds at the seeded
///                                    +escrowed value AND is a LIVE negative control at the cap.
///         4. DGVF CLAIM-SAFE       — the DGVF pro-rata `burnCoin` share math
///                                    (`flipOut = coinBal * amount / supply`) does NOT overflow /
///                                    revert on a 1e18-inflated `coinBal` and returns a correct-magnitude
///                                    payout (the false-confidence guard: a test that only checks
///                                    `totalSupply()` unchanged but never claims against the 1e18
///                                    allowance would miss a downstream overflow).
///
///         False-confidence guard (threat T-327-03-FC1/FC2/FC3): the one-shot test calls TWICE and
///         asserts +EXACTLY 1e18 (not 2e18) with no revert; the checked-add test drives the existing
///         allowance to the uint128 boundary and proves both the flood-holds case AND the
///         past-the-cap SupplyOverflow revert (the cap is a live control, not a vacuous pass); the
///         DGVF test drives an ACTUAL `burnCoin` against the flooded reserve and asserts a
///         correct-magnitude non-zero payout.
///
/// @dev Run:
///        forge test --match-path test/fuzz/FlipTombstone.t.sol -vv
///      Subject FROZEN at the Phase-326 diff (HEAD); ZERO contracts/*.sol edits.
contract FlipTombstone is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @dev The one-shot flood constant (FLIP.FLIP_TOMBSTONE_AMOUNT = 1e18).
    uint256 internal constant TOMBSTONE_AMOUNT = 1e18;

    /// @dev Initial VAULT mint allowance (zero — the initial emission arrives as
    ///      Coinflip seed stakes, not a constructor allowance).
    uint256 internal constant SEED_VAULT_ALLOWANCE = 0;

    /// @dev Initial circulating supply (zero — no constructor mint; FLIP only mints
    ///      after surviving a coinflip).
    uint256 internal constant SEED_CIRCULATING = 0;

    /// @dev DGVF / DGVE initial share supply (DegenerusVaultShare.INITIAL_SUPPLY = 1T * 1e18 = 1e30),
    ///      all minted to CREATOR.
    uint256 internal constant DGVB_INITIAL_SUPPLY = 1_000_000_000_000 * 1e18;

    /// @dev uint128 maximum (the _toUint128 cap boundary).
    uint256 internal constant U128_MAX = type(uint128).max;

    address internal constant GAME = ContractAddresses.GAME;
    address internal constant VAULT = ContractAddresses.VAULT;
    address internal constant CREATOR = ContractAddresses.CREATOR;

    function setUp() public {
        _deployProtocol();
    }

    // =====================================================================
    //          (a) NON-CIRCULATING — totalSupply() untouched by the flood
    // =====================================================================

    /// @notice The 1e18 flood does NOT change circulating totalSupply().
    function test_BTOMB03_TotalSupplyUntouched() public {
        uint256 tsBefore = coin.totalSupply();
        assertEq(tsBefore, SEED_CIRCULATING, "precondition: circulating seed = 0");

        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.totalSupply(),
            tsBefore,
            "flood must NOT touch circulating totalSupply()"
        );
    }

    // =====================================================================
    //   (b) SIGNAL LOCALIZATION — delta lands ONLY in the uncirculated leg
    // =====================================================================

    /// @notice vaultMintAllowance() and supplyIncUncirculated() each += EXACTLY 1e18 while
    ///         totalSupply() is unchanged (the entire delta is in the uncirculated leg).
    function test_BTOMB03_SignalLandsOnlyInUncirculated() public {
        uint256 allowanceBefore = coin.vaultMintAllowance();
        uint256 uncircBefore = coin.supplyIncUncirculated();
        uint256 tsBefore = coin.totalSupply();

        assertEq(allowanceBefore, SEED_VAULT_ALLOWANCE, "precondition: seeded allowance = 0");
        assertEq(
            uncircBefore,
            SEED_CIRCULATING + SEED_VAULT_ALLOWANCE,
            "precondition: uncirculated = circulating + allowance"
        );

        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        // The signal lands ONLY in the uncirculated leg, by EXACTLY 1e18.
        assertEq(
            coin.vaultMintAllowance(),
            allowanceBefore + TOMBSTONE_AMOUNT,
            "vaultMintAllowance must += EXACTLY 1e18"
        );
        assertEq(
            coin.supplyIncUncirculated(),
            uncircBefore + TOMBSTONE_AMOUNT,
            "supplyIncUncirculated must += EXACTLY 1e18"
        );
        assertEq(
            coin.totalSupply(),
            tsBefore,
            "totalSupply must be unchanged - entire delta is in the uncirculated leg"
        );

        // Cross-check: supplyIncUncirculated == totalSupply + vaultMintAllowance still holds.
        assertEq(
            coin.supplyIncUncirculated(),
            coin.totalSupply() + coin.vaultMintAllowance(),
            "supply identity must hold post-flood"
        );
    }

    // =====================================================================
    //         (c) ONE-SHOT — a second flood is a no-op (early-return)
    // =====================================================================

    /// @notice A second tombstoneAtGameOver() is a no-op: allowance += EXACTLY 1e18 total (not 2e18)
    ///         and the second call does NOT revert (early-return, not revert, so it cannot brick
    ///         the critical gameover path).
    function test_BTOMB03_OneShot() public {
        uint256 allowanceBefore = coin.vaultMintAllowance();

        vm.prank(GAME);
        coin.tombstoneAtGameOver();
        uint256 allowanceAfterFirst = coin.vaultMintAllowance();
        assertEq(
            allowanceAfterFirst,
            allowanceBefore + TOMBSTONE_AMOUNT,
            "first flood += 1e18"
        );

        // Second call: must NOT revert and must NOT re-flood.
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            allowanceBefore + TOMBSTONE_AMOUNT,
            "second flood is a no-op - total += EXACTLY 1e18, NOT 2e18"
        );
        // totalSupply still untouched across both calls.
        assertEq(coin.totalSupply(), SEED_CIRCULATING, "totalSupply untouched across both calls");
    }

    // =====================================================================
    //              (d) GAME-GATED — non-GAME caller reverts
    // =====================================================================

    /// @notice A non-GAME sender cannot flood — reverts OnlyGame.
    function test_BTOMB03_GameGated() public {
        address attacker = address(0xBAD);
        vm.expectRevert(FLIP.OnlyGame.selector);
        vm.prank(attacker);
        coin.tombstoneAtGameOver();

        // Allowance untouched by the failed attempt.
        assertEq(
            coin.vaultMintAllowance(),
            SEED_VAULT_ALLOWANCE,
            "failed non-GAME flood must not change allowance"
        );

        // The CREATOR (a holder, but not GAME) also cannot flood.
        vm.expectRevert(FLIP.OnlyGame.selector);
        vm.prank(CREATOR);
        coin.tombstoneAtGameOver();
    }

    // =====================================================================
    //   (e) CHECKED ADD — holds at the seeded+escrowed value; live cap control
    // =====================================================================

    /// @notice The checked _toUint128 add holds at a realistic high allowance (a large
    ///         escrow) — no SupplyOverflow, result == existing + 1e18.
    function test_BTOMB03_CheckedAddNoOverflow() public {
        // Escrow a large additional allowance by minting to the VAULT as GAME. Push the
        // existing allowance to a plausible high value.
        uint256 escrow = 1_000_000_000_000; // whole FLIP
        vm.prank(GAME);
        coin.mintForGame(VAULT, escrow);

        uint256 existing = coin.vaultMintAllowance();
        assertEq(existing, SEED_VAULT_ALLOWANCE + escrow, "escrow applied");

        // Flood: the checked add holds (existing + 1e18 << uint128 max ~3.4e38).
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            existing + TOMBSTONE_AMOUNT,
            "checked add holds at seeded+escrowed value: result == existing + 1e18"
        );
    }

    /// @notice The checked add holds EXACTLY at the boundary: drive the existing allowance to
    ///         (uint128 max - 1e18) so existing + 1e18 == uint128 max — the flood still succeeds.
    function test_BTOMB03_CheckedAddAtBoundary() public {
        // Target existing = U128_MAX - 1e18 so existing + 1e18 == U128_MAX exactly.
        uint256 target = U128_MAX - TOMBSTONE_AMOUNT;
        uint256 escrow = target - SEED_VAULT_ALLOWANCE;
        vm.prank(GAME);
        coin.mintForGame(VAULT, escrow);

        assertEq(coin.vaultMintAllowance(), target, "existing pushed to U128_MAX - 1e18");

        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            U128_MAX,
            "flood holds exactly at the uint128 boundary: result == uint128 max"
        );
    }

    /// @notice Negative control — the cap is LIVE: pushing the existing allowance past
    ///         (uint128 max - 1e18) makes the flood's _toUint128(existing + 1e18) revert
    ///         SupplyOverflow. Proves the checked add is not vacuous.
    function test_BTOMB03_CheckedAddCapIsLive() public {
        // Drive existing to (U128_MAX - 1e18 + 1) so existing + 1e18 == U128_MAX + 1 → overflow.
        uint256 target = U128_MAX - TOMBSTONE_AMOUNT + 1;
        uint256 escrow = target - SEED_VAULT_ALLOWANCE;
        vm.prank(GAME);
        coin.mintForGame(VAULT, escrow);

        assertEq(coin.vaultMintAllowance(), target, "existing pushed 1 wei past the flood-holds bound");

        vm.expectRevert(FLIP.SupplyOverflow.selector);
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        // The latch was NOT set (the revert reverted state), so the allowance is unchanged.
        assertEq(coin.vaultMintAllowance(), target, "reverted flood leaves allowance unchanged");
    }

    // =====================================================================
    //  TASK 2 — (f) DGVF claim-safe on a 1e18-inflated allowance share
    // =====================================================================

    /// @notice The DGVF pro-rata FLIP claim (DegenerusVault.burnCoin) does NOT overflow / revert
    ///         when the VAULT allowance it draws against has been flooded by 1e18, and returns a
    ///         correct-magnitude pro-rata payout.
    ///
    ///         burnCoin computes: flipOut = (coinBal * amount) / supplyBefore where coinBal includes
    ///         vaultMintAllowance() (post-flood ≈ 1e18). The intermediate product
    ///         coinBal * amount must not overflow uint256, and the remainder mint via vaultMintTo
    ///         (which casts the share to uint128 and debits the allowance) must not revert.
    function test_BTOMB03_DgvbClaimNoOverflowOn1e18Share() public {
        // Flood the VAULT allowance by 1e18 (gameover tombstone).
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        uint256 reserve = coin.vaultMintAllowance();
        assertEq(
            reserve,
            SEED_VAULT_ALLOWANCE + TOMBSTONE_AMOUNT,
            "DGVF reserve = seeded allowance + 1e18 flood"
        );

        // CREATOR holds the entire DGVF share supply (DGVB_INITIAL_SUPPLY = 1e30, minted in the
        // DegenerusVaultShare constructor, untouched at fresh deploy). The vault's FLIP balance and
        // coinflip claimable are both 0 here, so coinBal == vaultMintAllowance() ≈ 1e18.
        uint256 dgvbSupply = DGVB_INITIAL_SUPPLY;

        // Burn 1% of the DGVF supply (1e28 shares) — a clean fractional pro-rata claim that does NOT
        // trigger the full-supply REFILL branch, so flipOut is a true pro-rata share of the reserve.
        uint256 burnShares = dgvbSupply / 100; // 1e28
        uint256 expectedCoinOut = (reserve * burnShares) / dgvbSupply; // ≈ reserve / 100 ≈ 1e34

        uint256 vaultAllowanceBefore = coin.vaultMintAllowance();
        uint256 creatorBalBefore = coin.balanceOf(CREATOR);

        vm.prank(CREATOR);
        uint256 flipOut = vault.burnCoin(burnShares);

        // No overflow / no revert reaching here, and the math is correct-magnitude.
        assertEq(flipOut, expectedCoinOut, "DGVF pro-rata flipOut matches reserve * shares / supply");
        assertGt(flipOut, 0, "nonzero entitlement must yield a nonzero payout");
        assertLe(flipOut, reserve, "pro-rata share cannot exceed the reserve");

        // The payout was minted to CREATOR from the flooded allowance (vault balance was 0, so the
        // whole flipOut is drawn via vaultMintTo, which debits the allowance and credits circulating).
        assertEq(
            coin.balanceOf(CREATOR),
            creatorBalBefore + flipOut,
            "CREATOR received the pro-rata FLIP payout"
        );
        assertEq(
            coin.vaultMintAllowance(),
            vaultAllowanceBefore - flipOut,
            "allowance debited by exactly the minted payout"
        );

        // The claim drew the whole payout from the flooded allowance (vault FLIP balance was 0),
        // so circulating totalSupply increased by exactly flipOut (vaultMintTo moves
        // allowance → circulating). supplyIncUncirculated is conserved across the claim.
        assertEq(
            coin.supplyIncUncirculated(),
            SEED_CIRCULATING + reserve,
            "supplyIncUncirculated conserved across the DGVF claim (allowance to circulating)"
        );
    }
}
