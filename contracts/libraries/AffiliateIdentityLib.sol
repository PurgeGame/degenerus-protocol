// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";
import {BitPackingLib} from "./BitPackingLib.sol";

/// @dev Permanent Game identity roots, pinned against the declared layout in AffiliateIdentity tests.
///      Cached IDs come only from Game's allocator. They cannot be recycled or invalidated.
library AffiliateIdentityLib {
    uint256 internal constant ID_SLOT = 9;
    uint256 internal constant OWNERS_SLOT = 13;
    uint256 private constant OWNERS_BASE = uint256(keccak256(abi.encode(OWNERS_SLOT)));

    /// @dev The wallet ID is the top 32 bits of the owner's mint word.
    function walletId(address owner) internal view returns (uint32) {
        return uint32(
            uint256(IDegenerusGame(ContractAddresses.GAME).extsload(keccak256(abi.encode(owner, ID_SLOT))))
                >> BitPackingLib.WALLET_ID_SHIFT
        );
    }

    /// @dev Account key of wallet-table element `id`. Unallocated elements read zero.
    function ownerOf(uint32 id) internal view returns (address) {
        if (id == 0) return address(0);
        return address(uint160(uint256(IDegenerusGame(ContractAddresses.GAME).extsload(bytes32(OWNERS_BASE + id)))));
    }
}
