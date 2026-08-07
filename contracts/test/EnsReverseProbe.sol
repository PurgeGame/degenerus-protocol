// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

/// @notice Deploy-only probe mirroring the in-constructor ENS reverse-name
///         registration every protocol contract performs.
/// @dev Production swallows the call result (`ok;`) so deployment can never
///      revert on a misconfigured registrar. That also makes a failed
///      registration indistinguishable from a successful one at deploy time —
///      which is not theoretical: Base Sepolia's Basenames registrar reverts
///      inside its resolver because the resolver trusts a different registrar
///      than the registry does. This probe records the result so the failure
///      mode is observable before it reaches a real deploy.
contract EnsReverseProbe {
    /// @notice True when the constructor's setName call succeeded.
    bool public immutable ensOk;

    /// @notice The name this probe claimed as its reverse record.
    string public ensName;

    /// @param reverseRegistrar ENS ReverseRegistrar; address(0) skips the call.
    /// @param name Reverse name to claim, e.g. "game.degenerus.eth".
    constructor(address reverseRegistrar, string memory name) {
        ensName = name;
        bool ok;
        if (reverseRegistrar != address(0)) {
            // raw-selectors: justified — mirrors the production call byte for byte; setName(string) has no deploy-wide bound interface
            (ok, ) = reverseRegistrar.call(
                abi.encodeWithSignature("setName(string)", name)
            );
        }
        ensOk = ok;
    }
}
