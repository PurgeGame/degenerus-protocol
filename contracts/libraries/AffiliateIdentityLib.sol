// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";

/// @dev Permanent Game identity roots, pinned against the declared layout in AffiliateIdentity tests.
///      Cached IDs come only from Game's allocator. They cannot be recycled or invalidated.
library AffiliateIdentityLib {
    uint256 internal constant ID_SLOT = 13;
    uint256 internal constant OWNERS_SLOT = 67;
    uint256 private constant OWNERS_BASE = uint256(keccak256(abi.encode(OWNERS_SLOT)));

    function walletId(address owner) internal view returns (uint32) {
        return uint32(uint256(IDegenerusGame(ContractAddresses.GAME).extsload(keccak256(abi.encode(owner, ID_SLOT)))));
    }

    function ownerOf(uint32 id) internal view returns (address) {
        if (id == 0 || id > 3_000_000_000) return address(0);
        // Unallocated array elements are zero. Restrict the index to the allocator's namespace;
        // no storage writer touches its future elements, and allocated elements are immutable.
        return address(uint160(uint256(IDegenerusGame(ContractAddresses.GAME).extsload(bytes32(OWNERS_BASE + id - 1)))));
    }
}
