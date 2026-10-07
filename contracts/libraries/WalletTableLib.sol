// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";

/// @dev Reads Game's wallet table through its pinned root (asserted against the declared layout
///      by the slot-pin test). Element `id` holds the account key in bits 0..159; IDs are never
///      reassigned, so a decoded key is permanent.
library WalletTableLib {
    uint256 internal constant OWNERS_SLOT = 13;
    uint256 private constant OWNERS_BASE = uint256(keccak256(abi.encode(OWNERS_SLOT)));

    /// @dev Account key of wallet-table element `id`. Element 0 and unallocated elements read zero.
    function ownerOf(uint32 id) internal view returns (address) {
        return address(uint160(uint256(IDegenerusGame(ContractAddresses.GAME).extsload(bytes32(OWNERS_BASE + id)))));
    }
}
