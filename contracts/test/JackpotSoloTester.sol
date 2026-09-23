// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameJackpotModule} from "../modules/DegenerusGameJackpotModule.sol";

/// @title JackpotSoloTester
/// @notice Test helper that exposes _pickSoloQuadrant as an external-pure passthrough
///         so Hardhat JS tests can invoke the real production bytes directly. The
///         separate `JackpotSoloNoOp` companion shares the calldata shape of
///         `pickSoloQuadrant` and is used by the gas-regression suite to isolate the helper
///         BODY cost from ABI-decode + memory-args overhead via paired-call delta.
/// @dev Deploy in tests to verify gold-priority tie-break, zero-gold rotation
///      fallback, and the body-only gas bound the suite asserts.
contract JackpotSoloTester is DegenerusGameJackpotModule {
    function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        return _pickSoloQuadrant(traits, entropy);
    }
}

/// @dev Kept separate so the production-module inheritance in JackpotSoloTester
///      stays within the deployment-size limit. Both endpoints accept the same
///      arguments; their gas difference isolates the picker's body and wrapper cost.
contract JackpotSoloNoOp {
    function noOp(uint8[4] memory, uint256) external pure returns (uint8) {
        return 0;
    }
}
