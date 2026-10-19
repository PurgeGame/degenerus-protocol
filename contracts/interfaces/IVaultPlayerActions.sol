// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

// Solidity cannot take .selector from an overloaded method name. These aliases
// disambiguate only those overloads; all other selectors use canonical interfaces.
// check-vault-player-actions.js verifies these signatures against the compiled targets.
interface IVaultWinnings {
    function claimWinnings(uint32) external;
}
interface IVaultPartialWinnings {
    function claimWinnings(uint32, uint256) external;
}
interface IVaultAffiliateClaim {
    function claimAffiliateDgnrs(uint32) external;
}
interface IVaultBatchAffiliateClaim {
    function claimAffiliateDgnrs(uint32[] calldata) external;
}
