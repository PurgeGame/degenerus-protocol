// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.34;

import {DegenerusGameJackpotModule} from "../modules/DegenerusGameJackpotModule.sol";

/// @title JackpotSoloTester
/// @notice Test helper that exposes _pickSoloQuadrant as an external-pure passthrough
///         so Hardhat JS tests can invoke the real production bytes directly.
/// @dev Deploy in tests to verify gold-priority tie-break and zero-gold rotation fallback.
contract JackpotSoloTester is DegenerusGameJackpotModule {
    function pickSoloQuadrant(uint8[4] memory traits, uint256 entropy) external pure returns (uint8) {
        return _pickSoloQuadrant(traits, entropy);
    }
}
