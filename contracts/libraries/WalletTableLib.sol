// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {ContractAddresses} from "../ContractAddresses.sol";
import {IDegenerusGame} from "../interfaces/IDegenerusGame.sol";

/// @dev Resolve an external payee from Game's pinned wallet-table root.
library WalletTableLib {
    uint256 internal constant OWNERS_SLOT = 13;
    uint256 private constant OWNERS_BASE = uint256(keccak256(abi.encode(OWNERS_SLOT)));

    /// @dev Ordinary accounts store an address; subaccounts store their ordinary owner's ID.
    ///      Element zero and unallocated elements return zero.
    function ownerOf(uint32 id) internal view returns (address) {
        IDegenerusGame game = IDegenerusGame(ContractAddresses.GAME);
        uint256 element = uint256(game.extsload(bytes32(OWNERS_BASE + id)));
        uint32 ownerId = uint32(element >> 160);
        if (ownerId != 0) element = uint256(game.extsload(bytes32(OWNERS_BASE + ownerId)));
        ownerId = uint32(element >> 160);
        if (ownerId != 0) element = uint256(game.extsload(bytes32(OWNERS_BASE + ownerId)));
        return address(uint160(element));
    }
}
