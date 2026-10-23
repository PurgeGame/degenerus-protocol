// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.38;

import {Coinflip} from "../../contracts/Coinflip.sol";

/// @dev Test-only fixture writer for one day's packed stake lane (the ledger is keyed by wallet ID).
abstract contract CoinflipStakeSetter is Coinflip {
    constructor() Coinflip(new address[](0), new bytes32[](0), new uint8[](0), new address[](0), new bytes32[](0)) {}
    uint256 private constant _STAKE_LANE_MAX = type(uint32).max;

    /// @dev Arbitrary-order fixture writes preserve both pages on a ring collision. This
    ///      deliberately does not recycle history; production credit/reuse has separate tests.
    function _setFlipStake(uint24 day, uint32 id, uint256 amount) internal returns (uint256 stored) {
        stored = amount > _STAKE_LANE_MAX ? _STAKE_LANE_MAX : amount;
        uint24 page = day / 7;
        uint256 index = page % 15;
        uint256 word = coinflipStakeRing[id][index];
        bool spill = word != 0 && uint24(word >> 224) != page + 1;
        if (spill) {
            coinflipStakeRing[id][index] = (word & type(uint248).max) | (uint256(0x80 | (page & 0x7f)) << 248);
            word = coinflipStakeOverflow[id][page];
        }
        if (uint24(word >> 224) != page + 1) word = uint256(page + 1) << 224;
        uint256 shift = (day % 7) * 32;
        word = (word & ~(_STAKE_LANE_MAX << shift)) | (stored << shift);
        if (spill) coinflipStakeOverflow[id][page] = word;
        else coinflipStakeRing[id][index] = word;
    }
}
