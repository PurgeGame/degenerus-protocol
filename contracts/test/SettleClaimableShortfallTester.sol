// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

/// @title SettleClaimableShortfallTester
/// @notice Test-only harness that exposes the R3 canonical CPAY claimable-shortfall settle
///         (`DegenerusGameStorage._settleClaimableShortfall`) plus minimal getters/setters for
///         `claimableWinnings[buyer]` and `claimablePool`, so the REDEEM-08 refinement suite can
///         assert the paired-debit invariant `claimablePool == Σ claimableWinnings` and the strict
///         1-wei sentinel in isolation — a focused refinement check, NOT a full re-audit of the 5
///         whale/mint callers (each passes its own basis; the helper is the single shared sink).
/// @dev Inherits the canonical storage layout so the EXACT production `_settleClaimableShortfall`
///      body runs (no re-implementation). The internal-constant external-contract references in
///      DegenerusGameStorage are never invoked by this helper, so deployment off-address is safe.
contract SettleClaimableShortfallTester is DegenerusGameStorage {
    /// @notice Seed `claimableWinnings[buyer]` to `amount`.
    function setClaimable(address buyer, uint256 amount) external {
        claimableWinnings[buyer] = amount;
    }

    /// @notice Seed `claimablePool` to `amount` (narrows to the uint128 storage width).
    function setClaimablePool(uint256 amount) external {
        claimablePool = uint128(amount);
    }

    /// @notice Read `claimableWinnings[buyer]`.
    function getClaimable(address buyer) external view returns (uint256) {
        return claimableWinnings[buyer];
    }

    /// @notice Read `claimablePool`.
    function getClaimablePool() external view returns (uint256) {
        return claimablePool;
    }

    /// @notice Run the production R3 settle with the caller-chosen `basis`.
    function settle(address buyer, uint256 basis, uint256 shortfall) external {
        _settleClaimableShortfall(buyer, basis, shortfall);
    }

    /// @notice 4-byte selector of the inherited `E()` error the strict-1-wei sentinel reverts with.
    /// @dev Re-exposed so tests can `vm.expectRevert(tester.sentinelError())` with a tight match
    ///      (the inherited error is not addressable via the child contract name under this solc).
    function sentinelError() external pure returns (bytes4) {
        return E.selector;
    }
}
