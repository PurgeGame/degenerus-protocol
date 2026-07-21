// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameJackpotModule} from "../modules/DegenerusGameJackpotModule.sol";

/// @title JackpotSoloTester
/// @notice Test helper that exposes _pickSoloQuadrant as an external-pure passthrough
///         so Hardhat JS tests can invoke the real production bytes directly. The
///         companion `noOp` function shares the calldata shape of `pickSoloQuadrant`
///         and is used by the gas-regression suite to isolate the helper
///         BODY cost from ABI-decode + memory-args overhead via paired-call delta.
/// @dev Deploy in tests to verify gold-priority tie-break, zero-gold rotation
///      fallback, and the body-only gas bound the suite asserts.
contract JackpotSoloTester is DegenerusGameJackpotModule {
    function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        return _pickSoloQuadrant(traits, entropy);
    }

    /// @notice Calldata-shape-matched no-op for paired-call gas-delta isolation.
    /// @dev `traits` and `entropy` are referenced solely to silence unused-parameter
    ///      warnings; the function body has zero effective work and returns the
    ///      literal 0 value. Identical calldata shape to `pickSoloQuadrant` removes the
    ///      ABI-decode overhead from the gas delta `pickSoloQuadrant - noOp`, making it a
    ///      close estimate of the `_pickSoloQuadrant` body cost — selector-dispatch position
    ///      and per-function base overhead are not eliminated.
    function noOp(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        traits;
        entropy;
        return 0;
    }
}
