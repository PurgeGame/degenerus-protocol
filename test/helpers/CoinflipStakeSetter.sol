// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.26;

import {Coinflip} from "../../contracts/Coinflip.sol";

/// @dev Test-only fixture writer for one day's packed stake lane.
abstract contract CoinflipStakeSetter is Coinflip {
    uint256 private constant _STAKE_LANE_MAX = type(uint32).max;

    /// @dev Masked write of `day`'s stake lane, preserving the seven sibling days; the amount
    ///      clamps at the lane width so it cannot spill into a sibling day.
    /// @return stored The whole-FLIP value the lane now holds.
    function _setFlipStake(uint24 day, address p, uint256 amount) internal returns (uint256 stored) {
        uint256 units = amount;
        if (units > _STAKE_LANE_MAX) units = _STAKE_LANE_MAX;
        uint256 shift = (day & 7) << 5;
        uint24 key = day >> 3;
        uint256 w = coinflipStakePacked[key][p];
        w = (w & ~(_STAKE_LANE_MAX << shift)) | (units << shift);
        coinflipStakePacked[key][p] = w;
        stored = units;
    }
}
