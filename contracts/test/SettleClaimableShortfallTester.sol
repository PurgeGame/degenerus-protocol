// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameStorage} from "../storage/DegenerusGameStorage.sol";

/// @title SettleClaimableShortfallTester
/// @notice Test-only harness that exposes the canonical shortfall settle
///         (`DegenerusGameStorage._settleShortfall`) plus minimal getters/setters for the
///         packed claimable/afking balances and `claimablePool`, so tests can assert the
///         paired-debit invariant `claimablePool == Σ (claimable + afking)`, the strict 1-wei
///         sentinel, and the claimable-then-afking waterfall in isolation. Scope is the
///         settle body itself, not the whale/mint/presale callers.
/// @dev Inherits the canonical storage layout so the EXACT production `_settleShortfall` body
///      runs (no re-implementation), reading and writing the same packed balance slot through
///      the accessors. The internal-constant external-contract references in DegenerusGameStorage
///      are never invoked by this helper, so deployment off-address is safe.
contract SettleClaimableShortfallTester is DegenerusGameStorage {
    /// @notice Seed `buyer`'s claimable balance to `amount` (absolute, not additive).
    function setClaimable(address buyer, uint256 amount) external {
        uint256 cur = _claimableOf(buyer);
        if (cur != 0) _debitClaimable(buyer, cur);
        _creditClaimable(buyer, amount);
    }

    /// @notice Seed `buyer`'s prepaid afking balance to `amount` (absolute, not additive).
    /// @dev Writes the high half RAW and leaves `claimablePool` alone. Production has no bare
    ///      afking-credit primitive — the only credit is `_creditAfkingValue`, which moves the
    ///      pool in tandem — so seeding an arbitrary balance (including the deliberately
    ///      unpaired states this harness exists to build) has to write the slot directly.
    ///      Callers that care about the identity set the pool explicitly via setClaimablePool.
    ///      Byte-identical to the paired credit's own write, so the halves cannot cross-bleed.
    function setAfking(address buyer, uint256 amount) external {
        uint256 cur = _afkingOf(buyer);
        if (cur != 0) _debitAfking(buyer, cur);
        if (amount != 0) balancesPacked[buyer] += amount << 128;
    }

    /// @notice Run the canonical PAIRED afking credit (`_creditAfkingValue`) verbatim.
    /// @dev Additive, and moves `claimablePool` and emits AfkingFunded exactly as production
    ///      does — so packing proofs can assert cross-half non-interference against the real
    ///      production write rather than against a copy of it in this harness.
    function creditAfkingValue(address buyer, uint256 amount) external {
        _creditAfkingValue(buyer, amount);
    }

    /// @notice Seed `claimablePool` to `amount` (narrows to the uint128 storage width).
    function setClaimablePool(uint256 amount) external {
        claimablePool = uint128(amount);
    }

    /// @notice Read `buyer`'s claimable balance.
    function getClaimable(address buyer) external view returns (uint256) {
        return _claimableOf(buyer);
    }

    /// @notice Read `buyer`'s prepaid afking balance.
    function getAfking(address buyer) external view returns (uint256) {
        return _afkingOf(buyer);
    }

    /// @notice Read `claimablePool`.
    function getClaimablePool() external view returns (uint256) {
        return claimablePool;
    }

    /// @notice Run the production settle: claimable to the 1-wei sentinel (when allowed) then afking.
    function settle(address buyer, uint256 shortfall, bool allowClaimable)
        external
        returns (uint256 claimableUsed, uint256 afkingUsed)
    {
        return _settleShortfall(buyer, shortfall, allowClaimable);
    }

    /// @notice 4-byte selector of the inherited `E()` error the strict-1-wei sentinel reverts with.
    /// @dev Re-exposed so tests can `vm.expectRevert(tester.sentinelError())` with a tight match
    ///      (the inherited error is not addressable via the child contract name under this solc).
    function sentinelError() external pure returns (bytes4) {
        return E.selector;
    }
}
