// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {DegenerusGameMintModule} from "../../contracts/modules/DegenerusGameMintModule.sol";

/// @title MintWalletSeed — WalletSeed for harnesses built on the Mint module
/// @dev Same helpers as WalletSeed (keep the two aligned); a separate base because the Mint
///      module overrides storage hooks, so a diamond with WalletSeed would force overrides.
/// @notice Harnesses that extend Game storage (directly or through a module) mix this in to
///         register wallets the way production does (`_registerWallet`) and to read queue,
///         bucket and whale-pass state by address. Bucket and queue lanes hold wallet IDs.
abstract contract MintWalletSeed is DegenerusGameMintModule {
    /// @dev Register `owner` through the production allocator (idempotent; paid admission
    ///      bypassed) and return its wallet ID.
    function _seedWallet(address owner) internal returns (uint32 id) {
        (id,) = _registerWallet(owner, type(uint256).max);
    }

    /// @dev Entry-owed record (`id << 48 | owed << 8 | rem`) for `owner` on queue key `key`;
    ///      zero for an unregistered owner.
    function _owedOf(uint24 key, address owner) internal view returns (uint80) {
        uint32 id = _walletIdOf(owner);
        return id == 0 ? 0 : _entryPacked(key, id);
    }

    /// @dev Account key named by bucket lane `k` (address(0) for an empty lane).
    function _bucketOwnerAt(uint24 lvl, uint8 trait, uint256 k) internal view returns (address) {
        return _walletKey(_bucketIdAtUnchecked(lvl, trait, k));
    }

    /// @dev Owner key in the low 160 bits and the entry-owed record above it.
    function _entryRecordOf(uint24 key, uint32 id) internal view returns (uint256) {
        return uint256(uint160(_walletKey(id))) | (uint256(_entryPacked(key, id)) << 160);
    }

    /// @dev Whale-pass half passes held by `owner` (zero when unregistered).
    function _halfPassesOf(address owner) internal view returns (uint256) {
        uint32 id = _walletIdOf(owner);
        return id == 0 ? 0 : _halfPassCount(id);
    }

    /// @dev Register `owner` and append its ID to the packed deity lanes.
    function _seedDeity(address owner) internal returns (uint32 id) {
        id = _seedWallet(owner);
        _pushDeityId(id);
    }

    /// @dev Set `owner`'s half-pass count to `n`, registering it first.
    function _seedHalfPasses(address owner, uint256 n) internal {
        uint32 id = _seedWallet(owner);
        _takeHalfPasses(id);
        if (n != 0) _addHalfPasses(id, n);
    }
}
