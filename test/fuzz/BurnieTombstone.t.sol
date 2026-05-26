// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DeployProtocol} from "./helpers/DeployProtocol.sol";
import {BurnieCoin} from "../../contracts/BurnieCoin.sol";
import {DegenerusVault} from "../../contracts/DegenerusVault.sol";
import {ContractAddresses} from "../../contracts/ContractAddresses.sol";

/// @title BurnieTombstone — BTOMB-03: gameover BURNIE tombstone signals ONLY in uncirculated supply
/// @notice Deterministic scenario tests against the APPLIED Phase-326 diff that drive every property
///         of `BurnieCoin.tombstoneAtGameOver()` (the one-shot 1e36-wei VAULT-allowance flood) plus
///         the downstream DGVB pro-rata BURNIE claim (`DegenerusVault.burnCoin`) against a flooded
///         allowance.
///
///         Four properties (BTOMB-01/02 mechanic → BTOMB-03 non-distortion proof):
///         1. NON-CIRCULATING       — the flood does NOT change `totalSupply()` (circulating leg).
///         2. SIGNAL LOCALIZATION   — `vaultMintAllowance()` += EXACTLY 1e36 and
///                                    `supplyIncUncirculated()` += EXACTLY 1e36, while
///                                    `totalSupply()` is unchanged (whole delta in the uncirculated leg).
///         3. ONE-SHOT + GAME-GATE  — a second `tombstoneAtGameOver()` is a no-op (early-return,
///                                    NOT revert, total += 1e36 not 2e36); a non-GAME caller reverts
///                                    `OnlyGame`; the CHECKED `_toUint128` add holds at the seeded
///                                    +escrowed value AND is a LIVE negative control at the cap.
///         4. DGVB CLAIM-SAFE       — the DGVB pro-rata `burnCoin` share math
///                                    (`coinOut = coinBal * amount / supply`) does NOT overflow /
///                                    revert on a 1e36-inflated `coinBal` and returns a correct-magnitude
///                                    payout (the false-confidence guard: a test that only checks
///                                    `totalSupply()` unchanged but never claims against the 1e36
///                                    allowance would miss a downstream overflow).
///
///         False-confidence guard (threat T-327-03-FC1/FC2/FC3): the one-shot test calls TWICE and
///         asserts +EXACTLY 1e36 (not 2e36) with no revert; the checked-add test drives the existing
///         allowance to the uint128 boundary and proves both the flood-holds case AND the
///         past-the-cap SupplyOverflow revert (the cap is a live control, not a vacuous pass); the
///         DGVB test drives an ACTUAL `burnCoin` against the flooded reserve and asserts a
///         correct-magnitude non-zero payout.
///
/// @dev Run:
///        forge test --match-path test/fuzz/BurnieTombstone.t.sol -vv
///      Subject FROZEN at the Phase-326 diff (HEAD); ZERO contracts/*.sol edits.
contract BurnieTombstone is DeployProtocol {
    // =====================================================================
    //                          CONSTANTS
    // =====================================================================

    /// @dev The one-shot flood constant (BurnieCoin.BURNIE_TOMBSTONE_WEI = 1e36).
    uint256 internal constant TOMBSTONE_WEI = 1e36;

    /// @dev Constructor seed of the VAULT mint allowance (BurnieCoin._supply.vaultAllowance).
    uint256 internal constant SEED_VAULT_ALLOWANCE = 2_000_000 ether;

    /// @dev Constructor mint to SDGNRS (BurnieCoin._mint(SDGNRS, 2_000_000 ether)) = circulating seed.
    uint256 internal constant SEED_CIRCULATING = 2_000_000 ether;

    /// @dev DGVB / DGVE initial share supply (DegenerusVaultShare.INITIAL_SUPPLY = 1T * 1e18 = 1e30),
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

    /// @notice The 1e36 flood does NOT change circulating totalSupply().
    function test_BTOMB03_TotalSupplyUntouched() public {
        uint256 tsBefore = coin.totalSupply();
        assertEq(tsBefore, SEED_CIRCULATING, "precondition: circulating seed = 2M");

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

    /// @notice vaultMintAllowance() and supplyIncUncirculated() each += EXACTLY 1e36 while
    ///         totalSupply() is unchanged (the entire delta is in the uncirculated leg).
    function test_BTOMB03_SignalLandsOnlyInUncirculated() public {
        uint256 allowanceBefore = coin.vaultMintAllowance();
        uint256 uncircBefore = coin.supplyIncUncirculated();
        uint256 tsBefore = coin.totalSupply();

        assertEq(allowanceBefore, SEED_VAULT_ALLOWANCE, "precondition: seeded allowance = 2M");
        assertEq(
            uncircBefore,
            SEED_CIRCULATING + SEED_VAULT_ALLOWANCE,
            "precondition: uncirculated = circulating + allowance"
        );

        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        // The signal lands ONLY in the uncirculated leg, by EXACTLY 1e36.
        assertEq(
            coin.vaultMintAllowance(),
            allowanceBefore + TOMBSTONE_WEI,
            "vaultMintAllowance must += EXACTLY 1e36"
        );
        assertEq(
            coin.supplyIncUncirculated(),
            uncircBefore + TOMBSTONE_WEI,
            "supplyIncUncirculated must += EXACTLY 1e36"
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

    /// @notice A second tombstoneAtGameOver() is a no-op: allowance += EXACTLY 1e36 total (not 2e36)
    ///         and the second call does NOT revert (early-return, not revert, so it cannot brick
    ///         the critical gameover path).
    function test_BTOMB03_OneShot() public {
        uint256 allowanceBefore = coin.vaultMintAllowance();

        vm.prank(GAME);
        coin.tombstoneAtGameOver();
        uint256 allowanceAfterFirst = coin.vaultMintAllowance();
        assertEq(
            allowanceAfterFirst,
            allowanceBefore + TOMBSTONE_WEI,
            "first flood += 1e36"
        );

        // Second call: must NOT revert and must NOT re-flood.
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            allowanceBefore + TOMBSTONE_WEI,
            "second flood is a no-op - total += EXACTLY 1e36, NOT 2e36"
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
        vm.expectRevert(BurnieCoin.OnlyGame.selector);
        vm.prank(attacker);
        coin.tombstoneAtGameOver();

        // Allowance untouched by the failed attempt.
        assertEq(
            coin.vaultMintAllowance(),
            SEED_VAULT_ALLOWANCE,
            "failed non-GAME flood must not change allowance"
        );

        // The CREATOR (a holder, but not GAME) also cannot flood.
        vm.expectRevert(BurnieCoin.OnlyGame.selector);
        vm.prank(CREATOR);
        coin.tombstoneAtGameOver();
    }

    // =====================================================================
    //   (e) CHECKED ADD — holds at the seeded+escrowed value; live cap control
    // =====================================================================

    /// @notice The checked _toUint128 add holds at a realistic high allowance (seeded 2M + a large
    ///         escrow) — no SupplyOverflow, result == existing + 1e36.
    function test_BTOMB03_CheckedAddNoOverflow() public {
        // Escrow a large additional allowance as GAME (vaultEscrow is GAME-or-VAULT gated). Push the
        // existing allowance to a plausible high value well above the 2M seed.
        uint256 escrow = 1_000_000_000_000 ether; // 1e30 wei
        vm.prank(GAME);
        coin.vaultEscrow(escrow);

        uint256 existing = coin.vaultMintAllowance();
        assertEq(existing, SEED_VAULT_ALLOWANCE + escrow, "escrow applied");

        // Flood: the checked add holds (existing + 1e36 << uint128 max ~3.4e38).
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            existing + TOMBSTONE_WEI,
            "checked add holds at seeded+escrowed value: result == existing + 1e36"
        );
    }

    /// @notice The checked add holds EXACTLY at the boundary: drive the existing allowance to
    ///         (uint128 max - 1e36) so existing + 1e36 == uint128 max — the flood still succeeds.
    function test_BTOMB03_CheckedAddAtBoundary() public {
        // Target existing = U128_MAX - 1e36 so existing + 1e36 == U128_MAX exactly.
        uint256 target = U128_MAX - TOMBSTONE_WEI;
        uint256 escrow = target - SEED_VAULT_ALLOWANCE;
        vm.prank(GAME);
        coin.vaultEscrow(escrow);

        assertEq(coin.vaultMintAllowance(), target, "existing pushed to U128_MAX - 1e36");

        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        assertEq(
            coin.vaultMintAllowance(),
            U128_MAX,
            "flood holds exactly at the uint128 boundary: result == uint128 max"
        );
    }

    /// @notice Negative control — the cap is LIVE: pushing the existing allowance past
    ///         (uint128 max - 1e36) makes the flood's _toUint128(existing + 1e36) revert
    ///         SupplyOverflow. Proves the checked add is not vacuous.
    function test_BTOMB03_CheckedAddCapIsLive() public {
        // Drive existing to (U128_MAX - 1e36 + 1) so existing + 1e36 == U128_MAX + 1 → overflow.
        uint256 target = U128_MAX - TOMBSTONE_WEI + 1;
        uint256 escrow = target - SEED_VAULT_ALLOWANCE;
        vm.prank(GAME);
        coin.vaultEscrow(escrow);

        assertEq(coin.vaultMintAllowance(), target, "existing pushed 1 wei past the flood-holds bound");

        vm.expectRevert(BurnieCoin.SupplyOverflow.selector);
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        // The latch was NOT set (the revert reverted state), so the allowance is unchanged.
        assertEq(coin.vaultMintAllowance(), target, "reverted flood leaves allowance unchanged");
    }

    // =====================================================================
    //  TASK 2 — (f) DGVB claim-safe on a 1e36-inflated allowance share
    // =====================================================================

    /// @notice The DGVB pro-rata BURNIE claim (DegenerusVault.burnCoin) does NOT overflow / revert
    ///         when the VAULT allowance it draws against has been flooded by 1e36, and returns a
    ///         correct-magnitude pro-rata payout.
    ///
    ///         burnCoin computes: coinOut = (coinBal * amount) / supplyBefore where coinBal includes
    ///         vaultMintAllowance() (post-flood ≈ 1e36 + 2M seed). The intermediate product
    ///         coinBal * amount must not overflow uint256, and the remainder mint via vaultMintTo
    ///         (which casts the share to uint128 and debits the allowance) must not revert.
    function test_BTOMB03_DgvbClaimNoOverflowOn1e36Share() public {
        // Flood the VAULT allowance by 1e36 (gameover tombstone).
        vm.prank(GAME);
        coin.tombstoneAtGameOver();

        uint256 reserve = coin.vaultMintAllowance();
        assertEq(
            reserve,
            SEED_VAULT_ALLOWANCE + TOMBSTONE_WEI,
            "DGVB reserve = seeded allowance + 1e36 flood"
        );

        // CREATOR holds the entire DGVB share supply (DGVB_INITIAL_SUPPLY = 1e30, minted in the
        // DegenerusVaultShare constructor, untouched at fresh deploy). The vault's BURNIE balance and
        // coinflip claimable are both 0 here, so coinBal == vaultMintAllowance() ≈ 1e36 + 2M seed.
        uint256 dgvbSupply = DGVB_INITIAL_SUPPLY;

        // Burn 1% of the DGVB supply (1e28 shares) — a clean fractional pro-rata claim that does NOT
        // trigger the full-supply REFILL branch, so coinOut is a true pro-rata share of the reserve.
        uint256 burnShares = dgvbSupply / 100; // 1e28
        uint256 expectedCoinOut = (reserve * burnShares) / dgvbSupply; // ≈ reserve / 100 ≈ 1e34

        uint256 vaultAllowanceBefore = coin.vaultMintAllowance();
        uint256 creatorBalBefore = coin.balanceOf(CREATOR);

        vm.prank(CREATOR);
        uint256 coinOut = vault.burnCoin(burnShares);

        // No overflow / no revert reaching here, and the math is correct-magnitude.
        assertEq(coinOut, expectedCoinOut, "DGVB pro-rata coinOut matches reserve * shares / supply");
        assertGt(coinOut, 0, "nonzero entitlement must yield a nonzero payout");
        assertLe(coinOut, reserve, "pro-rata share cannot exceed the reserve");

        // The payout was minted to CREATOR from the flooded allowance (vault balance was 0, so the
        // whole coinOut is drawn via vaultMintTo, which debits the allowance and credits circulating).
        assertEq(
            coin.balanceOf(CREATOR),
            creatorBalBefore + coinOut,
            "CREATOR received the pro-rata BURNIE payout"
        );
        assertEq(
            coin.vaultMintAllowance(),
            vaultAllowanceBefore - coinOut,
            "allowance debited by exactly the minted payout"
        );

        // The claim drew the whole payout from the flooded allowance (vault BURNIE balance was 0),
        // so circulating totalSupply increased by exactly coinOut (vaultMintTo moves
        // allowance → circulating). supplyIncUncirculated is conserved across the claim.
        assertEq(
            coin.supplyIncUncirculated(),
            SEED_CIRCULATING + reserve,
            "supplyIncUncirculated conserved across the DGVB claim (allowance to circulating)"
        );
    }
}
